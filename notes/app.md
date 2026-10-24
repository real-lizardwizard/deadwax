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
  else; `test_me.py` overrides the dependency to prove the route reads it. (**Done in
  2.0.0-player.48** - every router checked by it, and the app's sign-in: see "Logins and roles".)
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

### Navidrome required (2.0.0-player.46)

James (2026-10-14, finishing the web app): the one app's library is Navidrome's, so **Navidrome is required
for the library** - no longer "optional, for the phone player" - and a folder Navidrome doesn't list is raised
in Needs a look as "Not in Navidrome" rather than given a second library view (that half, and how deadwax
knows what Navidrome lists, is notes/app-desktop.md's "Navidrome required (2.0.0-player.46)").

- **The gate's words** (`app/NeedsNavidrome.tsx`): the titles stay - **Connect Navidrome** / **Can't reach
  Navidrome**, which troubleshooting.md quotes - with the server's reason under them. Unset:
  `NAVIDROME_REQUIRED` ("deadwax needs Navidrome for your library: the app shows and plays the albums
  Navidrome lists, through deadwax - so the phone never needs Navidrome's password.") then "Set it up in
  deadwax's [settings] (Connections), then come back." - a sentence true of the main page's settings tab the
  link opens today (`/`, beside the app, as app-rules holds every link out) and of the phone's settings
  when they come; the link's file stays on app-rules' list. Set up but unreachable: `NAVIDROME_UNREACHED`
  ("Your library comes from Navidrome, so it shows here once deadwax can reach it.") above Try again.
  Where the gate is drawn didn't change: Home's shelves, the Library tab, album pages, Navidrome artists'
  pages and Search's library half; Search's MusicBrainz half, the album you don't have and its Get,
  Requests, Home's Arriving, You and Needs a look work without Navidrome (checked in the real page:
  Requests and You drawn, Needs a look listing the rest of its queue).
- **The start-up log** (`Config.report_navidrome`): unset says "deadwax needs it for the app's library - until
  it is, the app at /player/ says Connect Navidrome where the library would be and plays nothing
  (searching, Get, Requests and You work without it)" - still INFO. Not "the player at /player/ is off",
  as it said before: the page isn't off, only its library half waits (review). With only some of the
  three set, the ERROR says the same ("...so the app at /player/ says Connect Navidrome where the library
  would be"). The compose and `.env` templates' Navidrome blocks say "needed for the app's library" too (review).
- **The docs**: README's prerequisites (Navidrome, reading the same music folder, item 4 no longer
  "optionally") and the OMV list (five things, the fifth no longer "optional, for the phone player"), the
  app paragraphs (what works without it; Not in Navidrome), a probable issue; getting-started's "What you
  need", a seventh first-run step (set up Navidrome) and "What the app shows without Navidrome";
  configuration.md's section renamed **Navidrome (Settings → Connections)** (anchor
  `#navidrome-settings--connections`, player.md's link moved with it); library.md's issue table row, a
  "Not in Navidrome" section and Needs a look's line; player.md's "What you need", its gate words and the
  sidebar's Needs a look; troubleshooting.md's "An album says "Not in Navidrome"", the count's lag and the
  gate's new words.

### Up Next, shuffle and repeat (2.0.0-player.57)

James, 2026-10-20: **"i need shuffle, loop, and queue options across the board. in the player, browse, etc."** and
**"i'd like to be able to see the queue somewhere in the player, but I don't want to disrupt the theme we have
going"**. Apple Music is his reference: Up Next, Play Next / Play Last, shuffle, repeat off / all / one. He approved
every choice of `uplan/slice-queue.md` the same day, Part B (the whole library shuffled, paged in) included. The
engine files changed, as that spec said they would: `ui/src/player/usePlayer.ts`, `ui/src/player/streamSource.ts`, and
`ui/test/player.sim.cjs` by additions only; `lib/{playQueue,gapless,scrub,streamWrap,streamPlan,fmp4}.ts` have no diff.

- **The model, `lib/upNext.ts` (pure).** The engine's queue stays `{ tracks, index }`; Up Next's account rides beside it
  (`UpNextQueue = PlayQueue & { upNext? }`), one `Mark` per entry - where it came from (`source`, the list playTracks was
  given; `added`, Play Next or Play Last; `one`, a copy Repeat One put there), its place in the list (`at`) and which time
  round (`pass`) - with the list itself (`source`), Shuffle, the next key, where playTracks started (`startedAt`) and the
  list's songs taken out of a round (`left`). Every `{ ...queue, index }` in the engine already carries it. **The
  invariant**: after the song playing, copies, then added songs, then the list's songs round by round; an edit never
  touches `tracks[0..index]`, `marks[0..index]` or `index`, and hands back the same object when it changes nothing.
  `upnext.sim.cjs` holds it over 2,000 seeded runs of every edit, top-up and forward move. (`jumpedTo` alone puts the row
  first, ahead of the added songs, for the moment until the engine moves onto it; and Previous, walking BACK across a song
  added during a later round, can leave the order after it as it was played - history order, which is right for Previous
  then Next, and which Up Next then draws as far as its groups allow.)
- **Repeat is the queue, unrolled.** The stream places songs at `last + 1` and can't go back to index 0, so Repeat All
  appends the next time round once fewer than `REPEAT_AHEAD` (2) entries follow the song playing - in its order, or a
  fresh shuffle that never starts with the song that ended the round before - and Repeat One puts copies of the song
  after it. `topUp()` runs only once a song has been HEARD for `TOP_UP_HEARD_S` (2 s, or half a shorter one; a song whose
  length is unknown needs the 2 s), at the end of every `timeupdate` and join - never in `beginListen()`, since WebKit sends
  'playing' from inside play() before any sound and a list whose songs all fail would loop for ever. Next (`onward`),
  Previous (`backward`, previousAction's rule but back past the run of copies) and a failure's skip (`pastCopies`) pass
  the copies; `onEnded` and lib/gapless keep reading `index + 1`. *After review*: a song that is the list's last and was
  begun under 2 s ago (two quick Nexts, or a row jumped to) had nothing after it yet - Next did nothing and a seek to its
  end stopped the music under Repeat All. `next()` now tops up first when nothing follows and Repeat is All (a tap, so it
  can't loop on failing songs), and `onEnded` when nothing follows and Repeat is on (the song played to its end, so it was
  heard) - setting `state.queue` directly there, since the queue moves on to a new source or the standby straight after.
- **One way in: `replaceUpcoming()`.** Every Up Next change goes through `edit()` - `catchUp()` first (onTimeUpdate's
  crossing test, factored out unchanged: an edit made just after the clock crossed a join is made against the song now
  playing). **Next, Previous and a row's tap catch up first too** (the spec's "every action"): pressed in the up-to-250 ms
  (longer locked) before a 'timeupdate' sees a join, they act on the song the clock is in - Next goes to the song after the
  one heard, where before it went to the song already playing (in one stream, a seek back to its start). That is a change
  on the album-in-order path, chosen and pinned (player.sim "on the song the clock is in": Next, Previous, a row's tap, a
  removal and a move each 0.2 s past an unseen join) - then `replaceUpcoming(next)`: the stream replanned (`StreamSource.replan`), `state.queue` set in the same
  turn (so `stream.tracks === state.queue.tracks` keeps its meaning for `moveInStream`, `placed` and `streamFailed`),
  `fitStandby()`, and `preloadSoon()` while playing. When the stream can't take it (its playhead already past the queue's
  song, a seek on its way) the change is HELD (`state.heldEdit`) and made at the next 'timeupdate' or join, against the
  queue as it is then. *Deviation from the spec, on purpose:* a change already held is composed with the next one rather
  than replaced by it (Repeat's top-up four times a second would otherwise have thrown a held Play Next away), and
  `load()` doesn't clear a held change - only `playTracks` does - so a Play Next held across a song change isn't lost
  (pinned after review: two edits held through a seek under Repeat All both made at the very update that crosses the join
  - crossInto's runHeld - and a held Play Next dropped by playing another album). A
  jump (`jumpTo`) is never held: it is a tap, done now or not at all, and goes through `next()` (a seek in the stream when
  it holds the song, a handover, or a new stream from it). `refusedHandover` now goes by a count of the queue's moves
  (`state.moves`, bumped by load, moveInStream, crossInto and handOver, never by an edit): the queue's object (an edit
  replaces it) left the music stopped, and its index and song would misfire on Next then Previous.
- **Withdrawn from the spec's wording, `withRepeat` leaving All**: the spec says it drops the passes later than the one Up
  Next shows; at a round's LAST song Up Next shows the next round, so that kept one more round after Repeat was turned off.
  It drops every pass later than the song playing's own round instead - "Nothing after this song." there, as Repeat off
  means.
- **The controls.** Now Playing gains ONE button, Up next (`app-upnext-button`, QueueIcon), between AirPlay's place and •••,
  tinted while Shuffle or Repeat is on and named for it ("Up next - Shuffle and Repeat all"); Shuffle and Repeat are in Up
  Next, where the iPhone's Music app has them, so nothing else on the screen moves. Up Next (`app/UpNext.tsx`) is Info's
  shell: a sheet over Now Playing (App's `over` gains 'upnext') and on a desktop the side panel (`lib/appFrame.ts`'s `Side`
  gains 'upnext', `closesOnCrossing` returns `upNextPanel`, the one-panel rule both ways). It draws `upNextView`: the song
  playing, the chips, Playing Next with Clear, the shown round's rows (`UP_NEXT_DRAWN` 100, then "And N more songs."), what
  comes after. Its Edit is Home's Pinned (dropIndex and dragOffset imported from lib/pins). The desktop's player bar gains
  Shuffle and Repeat beside the transport and Up Next in the tools. Every song row's ••• (`app-row-more`: album pages,
  Search's library songs, the Library's Songs) and an album page's bar ••• (`app-album-more`) open the song menu
  (`app/QueueMenu.tsx`, ActionMenu's sheet): Play Next / Play Last, `rememberAdded` first (player/api.ts over
  lib/playedAlbums' new `also()`, which keeps an added song's album without letting go of the queue's), the app's one
  notice only when the songs were queued (the player's action says whether it started the music instead - nothing playing,
  or a queue played out).
- **The look**: nearly all reused (Info, Pinned, ActionMenu, the chips, Search's rows); app.css's new section "Up Next,
  shuffle and repeat (2.0.0-player.57)" adds only the two locks, the head's Edit, the chips' row, a group's gutter, Now
  Playing's tint, the row ••• (on an album row its glyph's right edge where the time ended, the row's own hairline to the
  edge) and the album bar's room between ••• and the pin (`--app-album-more-room`, so their 44px reaches meet and no
  more); app-desktop.css's, inside its query, the bar's Shuffle and Repeat in the tools' grey and size, accent while on. No
  existing rule's declarations changed (app.css's diff is insertions only). The section sits above the phone frame's
  ("looking after deadwax from a phone"), which test_app_css holds to be the file's last.
- **The gesture rule** (`ui/test/app-rules.sim.cjs`): the new actions found by name; `ALLOWED` gains QueueMenu (playNext,
  playLast), UpNext (its six), PlayerBar (setShuffle, setRepeat), ShuffleSongs (playTracks) and useShuffleFeed
  (extendQueue); ActionsContext isn't widened (App hands `player` to Up Next, the menu and the bar); the rows' ••• call
  App's menu, never the player; lib/upNext is pure.
- **Part B, the whole library shuffled.** `GET /deadwax/navidrome/shuffle?scope=yours|store` (search3's empty query as the
  asker, SCAN_PAGE 2,000 at a time, each song once; `yours` filtered to the asker's starred albums from getAlbumList2;
  `yours` with logins off or for break-glass is the store) keeps the list SHUFFLE_LIST_TTL_S (600 s) per (user, scope), one
  build at a time, makes a permutation (`random.SystemRandom`) under a `secrets` token and answers its first SHUFFLE_PAGE
  (200); `GET /shuffle/{token}?offset=N` pages it, claiming it, asking Navidrome nothing (another's or a gone token: 404
  "gone"). Per user and scope the four unclaimed orders asked for most recently (SHUFFLE_UNCLAIMED_KEPT - one, until
  the second review), and per user the two claimed most recently, each kept 24 h after it was
  last asked for. *After review* (the order playing was thrown away by the next tap's ask, so "every song once" broke past
  200 songs - its second page, ~150 songs in, was a 404 and the shuffle "started over" with songs heard again): an order is
  claimed when it is HANDED to the player, not when it is first paged - `/shuffle?playing=<token>` (ShuffleSongs' ask after a
  tap names the order the tap played, until one such ask gets through) claims it before the new order replaces the
  unclaimed one, and `/shuffle?claim=true` (the feed's fresh orders, which go straight into the queue) makes the new order
  claimed; and the unclaimed ones are kept per scope, so your albums' Shuffle and Browse's Songs' each keep their own.
  *Second review*: at one unclaimed order per scope, another DEVICE's visit took the order a list held for its tap (one
  person on a phone and a desktop - or everyone, as `local`, with logins off): the desktop's tap played its order, the
  claim named it too late, and ~150 songs on its second page was a 404 and the shuffle "started over". Four kept, the
  oldest going first, so a list's order outlives the visits of other devices meanwhile
  (test_another_devices_visit_never_takes_the_order_this_devices_list_holds; at one it fails). Past
  SHUFFLE_MAX (200,000) songs read: 413 in words. A full page bringing nothing new ends the read (a Navidrome ignoring the
  offset can't loop it). `app/ShuffleSongs.tsx` (above your albums with logins on, above Songs otherwise and in Browse)
  asks its first page as the list shows and plays it from the tap, then asks the next; `app/useShuffleFeed.ts` (called once
  in App) appends the next page below FEED_BELOW (50) songs ahead, a fresh order as the next round at the end with Repeat
  All (`startingElsewhere`: never starting with the song that ended), a fresh order as the rest of the round after a 404
  (said once), a retry after 30 s. *After review*: Repeat turned off (or to One) once the next round was queued let go of
  that round but left the shuffle on the NEXT round's order - so the feed went on paging a second shuffle; the state now
  keeps the order of each earlier round still queued (`pagedRounds`), and `withRepeat` goes back to the round playing's,
  whole, so the shuffle ends. A fresh round still on its way when Repeat goes off is let go (superseded), and one landing
  anyway is dropped unless Repeat is still All (read through a ref). A fresh order with no songs (a library emptied
  meanwhile) is appended as nothing - `withMore` hands the queue back - so the feed asks no more instead of asking again for
  ever. ShuffleSongs draws its "12,480 songs" only above your albums (`count`; the Songs views' head counts the same songs),
  and nothing at all for a scope with no songs (no dead pill over "0 songs"). The engine's only Part B lines: playTracks' `paged` and `extendQueue` (an edit, like
  Play Last, through `withMore`). Cost for 30,000 songs, from Navidrome's answer shape, NOT measured: a build is 15 search3
  calls, ~30-45 MB of JSON, expected 5-15 s on a NAS; the trimmed list ~15-25 MB per (user, scope) while kept; 4 bytes a
  song per order; 200 songs (~70 KB) to the phone per page.
- **Verified** - the sims: upnext.sim (the model by property and by example; Up Next and the menu rendered), shuffle.sim
  (the button and the feed against a faked deadwax), player.sim's new sections (the engine as before with Up Next untouched
  under all four page kinds - replan never called, lib/upNext asked once; Play Next mid-song and in a song's last seconds,
  sample-exact, in one MediaSource; a song that can't join; remove, move, Clear, strikes and an in-flight append of a
  let-go song; jump; Shuffle mid-song; Repeat All three rounds, turned on after the source ended, a single looping; Repeat
  One every way; failures never looping; the standby following; a handover refused across an edit; an edit 0.2 s past an
  unseen join, and held through a seek; Play Next after the queue played out; the lock screen; Repeat kept; a 450-song
  library shuffle fed in three pages with a fresh order as the next round, in one stream), test_navidrome_shuffle.py, the
  walk and the routes table; 21 mutations of lib/upNext, 21 of the engine, 12 of the server and 13 of the feed, the menus and the
  frame each caught. In a real page (headless Chromium, plain MediaSource, `http://deadwax.test`): an album in order
  joining at 0 ms in one stream; Play Next from a row's ••• - the notice, the panel's Playing Next - and its joins in and
  out at 0 ms in the same MediaSource with no reload; Shuffle on and off mid-song with no emptied/loadstart/seek and the
  album's order back from the song playing; Repeat All's wrap and Repeat One's loop at 0 ms in the same MediaSource; the
  bar's five transport buttons at 1024; the row ••• at 375 and 320 (a full target, the title's ellipsis kept, the time
  readable, the bar's ••• 14 px from the pin); Now Playing's icon row; Up Next's sheet and Edit at both widths. That Play
  Next was made mid-song, BEFORE the next song was placed - it cut nothing, so it says nothing about an edit in a song's
  last seconds (below).
- **After review, the rest**: a desktop's Top results song TILE has no ••• (beside its cover and ▶ it left the title ~40 px:
  "Gli…"; the same song's row in Songs has it - search.sim); Up Next's Edit sends focus to Done as the Edit button goes,
  and a row's tap to the row after it (or Done), so focus is never dropped to the page where Escape can't reach the panel
  (upnext.sim); the Up Next drawer (1024-1279) goes as the bar's album link or an artist opens a page, as Info's does
  (`leaveInfoDrawer`); the desktop bar's Shuffle is aria-disabled and dimmed during a whole library's shuffle, as Up Next's
  chip is; and the clean-up `replan` does of a let-go song's piece in flight or fetched-and-waiting, the half-a-short-song
  rule (a 1.5 s single on Repeat One) and the player bar's three buttons and Up Next's drag are now pinned by sims. Not
  pinned: the `rest` of a split piece (split only on a full SourceBuffer, which no new check drives).
- **Second review**: (1) the server's unclaimed orders, four per user and scope (see Part B above), so another device's
  visit never takes a list's order; (2) `appendFailed`'s guard is the queue's tracks alone - it had also asked whether the
  song was still among the stream's `songs`, which a run ended before it (pieceFailed's `endAt`, an album in order, nothing
  replanned) makes false, so a song whose append then failed was let off and streamed again on its next tap, unlike
  before .57 (player.sim: "song 2 blamed all the same"); (3) the bar's disabled Shuffle is named by the shuffle's scope in
  Up Next's words - "shuffling everything" from Browse's Songs, "shuffling your whole library" from your albums (upnext.sim).
- **NOT verified - the iPhone's**: all of it on ManagedMediaSource (`replan` taking a placed song back out, an ended source
  reopened by an append) and a Repeat All loop for an hour (memory, the timeline, Safari's eviction around the loop - the
  stream keeps every placed song's entry, a few KB each, never pruned); Repeat One and Repeat All locked, the loop's join in
  a pocket, a Play Next made before locking; the lock screen's previous and next with Repeat One; Up Next's scrolling and the
  grip's drag in the home-screen app, and VoiceOver through Up Next, Edit and the menu; the URL way's Repeat One (about
  100 ms a handover, and the song downloaded into memory again each loop); **an edit in a song's last seconds on WebKit** -
  whether removing the next song's frames, already enqueued to the AVSampleBufferAudioRenderer, flushes and drops a moment
  of the playing song's end (Plan B, `stream.lockedThrough()` keeping a song that starts within 5 s, is named and not
  built); all of it on AirPods. **Not run in Chromium either** (the real page): a Play Next 1 s and 3 s before a join,
  recorded through Web Audio - the Plan B gate, so that decision is open; an edit within 100 ms AFTER a join; Play Next of
  an MP3 while streaming (it should be handed over); a reload keeping Repeat; a 24/96 album under 48 kHz with Up Next
  edits; Part B against 3,000 stand-in songs (every song once, the build's time and size, a deadwax restart mid-shuffle).
  Part B against a real Navidrome 0.64.2: search3 with songCount 2000 and offsets into the
  tens of thousands, its time on James's NAS, and an order made while a scan runs. Not built (spec's "Left out"): history,
  autoplay, keeping the queue across a reload (built in 2.0.0-player.64, below), long-press menus and a ••• on album tiles, saving Up Next as a playlist, a •••
  on Up Next's own rows, dragging between groups, crossfade.

### Resume what was playing (2.0.0-player.64)

James, 2026-10-22: **"every time I open the app, whatever was playing is gone. Is there a way we can fix that?"** Asked
where it should be kept he chose **"Follows you everywhere"** - as the signed-in person's play queue in Navidrome - and
approved all 16 choices of `uplan/slice-resume.md` ("Go"), choice 7 (a paused player taking a newer queue from another
device, logins on) included. On opening, the queue, the song and the second come back **paused**: iOS starts sound only
from a tap, so nothing loads or plays until one.

- **What Navidrome's source says** (0.64.2, read at `work/design57/navidrome/nd-v0.64.2`): ONE play queue per user
  (`model/playqueue.go`, `persistence/playqueue_repository.go`, `server/subsonic/bookmarks.go`) - the ids comma-joined,
  `current` an INDEX (migration `20250611010101`), `position` the client's int64 (ms), `changed_by` the call's `c`,
  `changed` the server's time; no size limit, duplicates kept; an empty save clears it (deleted, nothing inserted); the
  user's row goes with the account (`on delete cascade`). **`savePlayQueue` finds `current` by the FIRST id equal to
  it** - wrong for deadwax's queue, which holds a song more than once by design (Repeat One's copies, Repeat All's
  rounds) - so deadwax uses **`savePlayQueueByIndex`** (error 10 for a `currentIndex` missing or outside the ids) and
  **`getPlayQueueByIndex`** (OpenSubsonic's `indexBasedQueue` v1, which 0.64.2 advertises; every call takes a form body).
  **On a read, songs no longer in the library are dropped but the stored index is answered unchanged** - after a
  deletion it can name the wrong song or none - so the page aligns rather than trusts. Navidrome's own web player keeps
  its queue in the browser's localStorage, not here. **Amperfy doesn't use it at all** (every `forAction:` in
  `SubsonicServerApi.swift` read: no savePlayQueue, getPlayQueue or bookmarks; its queue is Core Data on the phone): it
  will neither show deadwax's queue nor overwrite it, and the docs say so plainly. Which other apps use Navidrome's
  queue isn't verified, and the docs name none as fact.
- **Two places, written together, read together.** Navidrome's play queue as the asker (`client_for`) - the interchange,
  and the authority on what was played last - and **deadwax's record beside it**, per deadwax user, in SQLite
  (`play_queue`: the same ids and index, the position in seconds, the page's opaque versioned snapshot of Up Next, the
  device and its label, `rev` bumped by every save, `ids_rev` the rev of the last save that sent the ids). Navidrome's
  answer always decides WHAT is newest: the record is handed out (`kept`) only when Navidrome says deadwax saved last,
  and the page believes it only when Navidrome's ids are its ids (equal, or less songs Navidrome dropped). Anything
  else - another app, a second deadwax on the same account, a record from before logins - comes back as a **plain
  list**: Navidrome's songs in its order from its index, as `playTracks(tracks, index)` would queue them.
- **The server** (`src/routes/navidrome.py`'s last section, `src/play_queue.py` pure, `store.py`'s three methods):
  `GET /queue` (Navidrome's queue in SHUFFLE_FIELDS, its index as it said it, the position in seconds, `changed_by`
  cleaned to 64 characters, `shared` with logins off, `kept`; a foreign list over 2,000 answered as the window around
  its song), `POST /queue` (`QueueSave`, `extra="forbid"`: 1-2,000 ids, an index inside them, 0-86,400 s, a device of
  8-64 `[A-Za-z0-9_-]`, a label of 1-40 letters, digits and spaces, a snapshot of at most 262,144 characters that must
  be a JSON object of `v: 1`; Navidrome written as a form, THEN the record) and `POST /queue/at` (`QueueAt`: a position
  against the record's ids - no record, or another `ids_rev`, a 409 "The queue changed on another device or in another
  app"; an index past them a 422). One save at a time per user (an asyncio lock per event loop, as `_gate`'s), so a
  beacon and a full save can't interleave their two writes - and the GET reads under it too (review: a reload's GET
  could otherwise read before its own pagehide's save landed, or between its two writes); a Navidrome failure leaves the record and logs one warning
  per user per 10 minutes, never to the page's log. **Break-glass** (`logins_on() and asks_as_shared(client_for())`):
  an empty GET and `{rev: null}` saves, Navidrome asked nothing - the shared account's queue may be a person's. With
  logins off it is `local`'s record and the shared account's queue: `shared: true`. Every answer `no-store`.
  `play_queue` joins `PERSON_TABLES`; `adopt_local` leaves `local`'s (it describes the shared account's queue).
  *Beyond the spec, each on purpose*: (1) **`known_users` lists a `queue`** - a name with only a queue left would
  otherwise be refused a new account (`keeps_anything`) yet never offered Forget; People's Remove and known-only
  words gain "their play queue" / "a play queue" (people.sim); (2) **the queue routes' 422s are words**
  (`validation_words` now covers `/deadwax/navidrome/queue`, `QUEUE_FORM` for a bound's refusal) - FastAPI's list
  would echo a 256 KB snapshot back; (3) **no database is a 503 and Navidrome is not written** (the two places stay in
  step), where the spec left it open.
- **The page's rules** (`lib/resume.ts`, pure): `toSave` (the window - at most 50 before the song and 2,000 in all,
  `startedAt` moved down and floored, the marks sliced; snapshot v1 with one level character an entry, the source by
  id and `extra` - the whole song - only for source songs outside the window, left out over the cap; returns `start`
  too, which the hook needs to number a later position save inside that window), `fromSnapshot` (songs rebuilt one
  object per (id, level), shared by entries and source; every check the spec lists but one - and a source mark's `at`
  must name its own song; `startedAt` need only be at or after 0, not at or before the index as the spec said: Previous
  takes the index back before where playTracks began, a live state the review found refused, Playing Next lost), `resumed` (exact / dropped / anyone else's / played to its end; returns `exact` beside the spec's three,
  for the hook's `ids_rev`; Navidrome's ids equal to the record's at ANOTHER index - its position save landing in
  Navidrome but not the record - is the plain list at Navidrome's index), `relevel`, `deviceLabel`, `pickedUpWords`
  ("an iPhone", "an iPad", "an Android phone" with logins off), `changedSince` and `saveDue` (the save rules as a
  function of the baseline, the queue, the position, playing, the clock and the trigger).
- **The hook** (`app/useResume.ts`, called once in App after `useShuffleFeed`): the open's GET through latestOnly, used
  only while the queue is still the one asked for and nothing plays; `restoreQueue`; the notice (`sayPins`); the
  album asked through its own latestOnly and remembered only while its song shows; the re-check on visible, `pageshow`
  and `focus` (15 s, never playing, unsaved changes saved instead, logins off never taking anything into a paused
  player - nor even asking, once it knows); the saves. *Choices the spec left to the build*: the render's queue and
  play state are read during render (a ref, bookkeeping only - what it asks for is sent in a microtask), because a
  render comes reliably after every change where an effect waits for a frame a locked phone may not draw; while
  playing, the waits are judged at the player's own position updates too (the timers are a paused page's), so a
  locked phone's sleeping timers lose nothing; **the 30 s are counted from the later of the last save and playing
  starting**, so a pause's save and a play a minute later don't save at once; a trigger met while a request is out is
  kept by kind and asked again in the order pause (or a 409's full save), wait, position - asking every one "at once"
  sent a second save after every 30 s save on a slow network (resume.sim caught it); `ids_rev` is taken from `kept`
  only when the queue put back is exactly the record's ids - fitting it to this device's Repeat (copies made, a round
  dropped) changes the list, and a position save then would name the wrong song; a 401 stops saving until
  `api/http.ts`'s session counter moves (a sign-in since - `currentSession()`, new), since the same person signing in
  again doesn't remount App; an answer with no rev (break-glass) stops it for the page's life; the beacon's answer is
  taken as saved, so `pagehide` after `visibilitychange` sends nothing twice, and a full save going away goes keepalive
  only while its body's UTF-8 BYTES (`utf8Length`), with every keepalive save still out, are within BEACON_MAX - the
  browser's 64 KiB is for all keepalive bodies in flight, and one over it is refused outright (`post()` gains a
  `keepalive` flag). The device id is `persisted.ts`'s `readPlayerDevice()`
  under the key **`deadwax-player-device`** - the spec said `deadwax.player.device`; every other key here is
  `deadwax-player-*`, so it follows them.
- **The engine** (`ui/src/player/usePlayer.ts` only, as the spec named; `ui/test/player.sim.cjs` by additions only;
  `streamSource.ts` and `lib/{playQueue,gapless,scrub,streamWrap,streamPlan,fmp4}.ts` have no diff): a put-back queue is
  **parked** - `state.parked = { position }` beside `state.queue`, React's queue showing it, nothing on any element.
  `songPosition()` reads the parked second; `load()` lets it go (`state.parked = null` beside `state.queue = next` -
  the one line on an album tap's path); the inner `seek()` moves the parked second (held to the song, `report`,
  `updatePositionState`, null - so the scrubber, the lock screen's seekto and Previous's restart load nothing);
  `onTimeUpdate` returns while parked (an emptied element's 'timeupdate' would draw 0:00); `toggle()` and the lock
  screen's play call `resume()` - `unlockSpare()`, `load(state.queue, true, true)` (a tap's load: a stream may start,
  play() inside), then the ordinary seek, in the same turn. `letGo()` empties what a paused queue held (the retry, the
  standby, the element - a stream detached and closed - the readout's ask, the warm-ups). `restoreQueue` refuses while
  the listener means music to play, the element plays or a retry is pending; fits the queue to Repeat (`withRepeat`
  then `toppedUp`); holds the second to the song (past its end at its end, below 0 or not a number at 0:00); clears a
  held edit and a pending seek, closes Debug's seek on its way (as a song change does), drops a "Skipped …" line and
  Buffering (paused while a song loaded); counts a move (a refused handover can't fire on it); and tells the lock
  screen (metadata, `paused`, the position) - each of those pinned in player.sim. It also clears a change, a join, the
  retry's marks and the listen, and lets go whenever the queue had a song even with nothing on an element: defensive
  only - a pause has already cleared the change, and the next `load()` (resume's) clears the rest before anything
  reads them, so no test can tell them apart (a review's mutation run found them surviving; this says so rather than
  claiming them).
- **Verified** - Python: 3536 collected (3534 passed, 2 skipped; 63 more than .63's 3473, all in the new
  `test_play_queue.py`, 7 of them the review's; the walk, the ROUTES and route-list tables - test_navidrome's, test_turntable_disc_art's - and
test_navidrome_search's seam list grew the queue). Sims, all 63 (resume.sim
  new); player.sim's new section "a queue put back, paused" (nothing touched on a fresh page; refused while playing,
  while a tapped song loads, while a retry waits, while a handover's play() is out, while the element plays by itself;
  over a paused queue - the URL way, a stream with a held edit, a standby, a handover refused a moment later -
  everything let go; the tap in both MediaSources from 1:35 within 0.05 s, the join sample-exact; the URL way's start
  set while loading; a hi-res and a levelled entry's addresses; the lock screen; every other action; **an album from a
  tap after a put-back exactly today's trace event for event**, four page kinds; **play on it exactly playTracks + a
  seek in one tap**, three page kinds; and, ahead of all of it, **an album's tap on a fresh page held line for line to
  the trace the engine of 2.0.0-player.63 made** - every element write, fetch and lock-screen line, four page kinds,
  recorded by running that engine (git e2f1d2b, exported with `git archive`) under the new sim with
  `DEADWAX_RECORD_TAP=1`, the two recordings byte-identical; an extra lock-screen line in load() fails all four). Mutations: 17 of the engine (all caught but the retry-pending refusal, which no
  reachable state tells apart - a retry is only ever pending while the listener means to play, so the first refusal
  covers it; kept as the spec's belt and braces), 16 of lib/resume, 19 of the hook and app-rules, 14 of the server -
  each caught, the file put back byte for byte (sha256 compared). **The real page** (own deadwax on 8110 logins on /
  8111 off, the stand-in Navidrome on 4554 grown the four play-queue calls by Navidrome's rules and `missing.json`,
  headless Chromium as `deadwax.test` over plain http, 390x844 and 1440x900): an album played, song 3 sought to 1:36 and
  paused - the stand-in held the five ids, currentIndex 2, 96 431 ms, `deadwax`; reloaded - the mini player showed song
  3 paused, the scrubber at 96, Up Next "From Long Album" 4 and 5, and the reload asked the queue once and no audio at
  all; tap play with Gapless on - one MediaSource, the first 'playing' at 96.444 s (the second saved to the
  millisecond), song 3's head asked first, into song 4 with one buffered range and no 'waiting'; an iPhone's user agent
  with Gapless off - `wrap=mp4&level=album`, playing on from the second put back; Play Next twice, Shuffle on, Repeat
  All, reload - Playing Next, the order and both chips back; a second device picked it up ("Picked up from your iPad" -
  the first context's Mac user agent with touch points reads as an iPad, as iPadOS's does), played to song 5 and
  paused; the first, paused, brought to the front took song 5 with logins on ("Picked up from your iPhone") and kept
  its own with them off; a Symfonium save of three songs came back as a plain list at its song and 0:04, "Picked up
  from Symfonium"; song 3 in `missing.json` - song 4 at 0:00; break-glass - nothing put back, the stand-in's queue
  untouched by its playing; hidden while playing - a beacon to `/queue/at` within 300 ms and in Navidrome within the
  second; song 3 (100 s) played 76 s - saves at 2, 32 and 62 s; two 30 s songs - one save a second after each change
  and no more; a queue put back and hidden for a minute - none; the desktop bar's Play from the parked second, and
  after a reload the visualizer's Space (its first 'playing' read at 10.75 s against the 10.60 put back - inside the
check's 0.3 s; why 0.15 s later than the phone's landing to the millisecond is not known); a 2,500-song
  playlist (nine songs cycled) from its tenth - 2,000 ids, currentIndex 9, the snapshot's source all 2,500 - and
  reloaded, "Still to play", 100 rows, "And 1,890 more songs.". No console errors in any.
- **NOT verified - the iPhone's** (docs/player.md's list): iOS killing the home-screen app (whether
  `visibilitychange`/`pagehide` fire and the beacon gets out, or the last 30 s save is what comes back; whether the 30 s
  saves go out locked in a pocket); the lock screen after reopening (nothing until the first play, then the song, its
  cover and position, previous/next; AirPods' play before any tap - likely nothing, no session yet); the first tap's
  resume on ManagedMediaSource (the seek before the head landing at the saved second) and the URL way (WebKit's default
  playback start position honoured in the MP4); the app kept in memory for hours, brought back after the desktop played
  on; how long the open's GET takes over WireGuard before the mini player shows the song. Not run against a real
  Navidrome either: `getPlayQueueByIndex`'s answer and `changedBy` as a real 0.64.2 writes them, and a real Subsonic
  app's `c` in the notice.
- **After review** (eleven findings, all real; each fix with a check that fails without it):
  - `fromSnapshot` refused any queue with `startedAt` past the index - an album tapped at song 5, Play Next, then
    Previous - so Up Next came back a plain list (under Repeat All the list grew to both rounds). Now `startedAt >= 0`
    only (withShuffle reads it only as a loop's start, bounded by the index). resume.sim's round trip gained Previous
    - and a first draw thrown away: a small seed's first draw is always near 0, so EVERY run had started from its first
    song (null), and no run had ever had a `startedAt` above 0.
  - **A deleted song comes back** (the premise was wrong): Navidrome's `loadTracks` drops only ids
    `mediaFileRepository.GetAll` doesn't return, and that has no `missing = false` - a deleted file is marked missing
    and kept until purged (`Scanner.PurgeMissing` defaults to `never`; the Missing Files page). So it is put back and
    skipped on its first play like any song that won't play; only once purged does "the next at 0:00" apply.
    docs/player.md, troubleshooting.md and src/play_queue.py say so now; the fakes model a purged song.
  - Keepalive by bytes, and by the bytes still out (above). resume.sim: Japanese titles under BEACON_MAX in characters
    and over it in bytes; two 37 KB saves going away at once, the second an ordinary request.
  - **The notice once**: a desktop tab put back from the phone and untouched took the phone's newer save at every
    return to the front (its rev moves every 30 s) and said "Picked up from your iPhone" each time, asking the album
    again. Now said only when where it came from or its songs change, or the queue had been played here since; the
    album is not asked while `playedAlbum()` has it.
  - **The focusing click**: a window's `focus` fires on the mousedown of the click that focused it, often a press of
    Play; an answer landing before the click swapped the queue under it. `focus` now asks RESUME_FOCUS_GRACE_MS (500 ms)
    after it (a click that played makes front() ask nothing); `visibilitychange` and `pageshow` still ask at once,
    since a phone's page shows before it can be touched (the interaction guard the review offered first would have
    dropped the desktop's queue whenever a phone was touched within the GET's round trip).
  - **GET under the save lock** (above); test_play_queue: a save held at Navidrome's write and at the record's, the GET
    answering after with both agreeing.
  - Pins for what the build chose but no test held: the `sameIds` guard (a Repeat One record put back under Repeat off,
    then a song change: a full save), the 30 s from playing starting, a 422 then a full save, a scrubbed put-back queue
    kept against its own device's newer save; fromSnapshot's added-mark, copy-mark and `extra` song checks; the engine's
    restoreQueue `setWrapped(null)` and `pendingSeek = null`, letGo's warm-up abort, the parked seek's clamps
    (player.sim, additions only); the device id and `post()`'s keepalive through the real persisted.ts and player/api.ts
    (resume.sim compiles them apart from its stubs); the server's no-store on every 200 (the break-glass admin's too),
    the record failing to read (a plain list) or to write (503), another app's name cleaned, a 401 never logged.
  - Mutations, each caught, the file put back byte for byte: 24 against resume.sim (resume.ts, useResume.ts,
    persisted.ts, http.ts, player/api.ts), 5 of the engine against player.sim, 7 of the server (the lockless GET caught by each of its two cases).
- **After a second review** (three findings, all real):
  - **An edit, then a song change inside its 2 s, while paused, was never saved on a schedule**: render() chose the
    wait from the drawing before (only the index moved: a position wait) and moved `changedAt`, so the full wait ran
    out under 2 s after the last change, the position wait saw a change of the songs still under 2 s, and with no
    position updates while paused nothing asked again - the edit sat unsaved until the page went away or came back,
    when front() saved it over whatever another device had saved since. The wait is now chosen against what was last
    SAVED (`changedSince(clock.saved, …) === 'songs'`: full, from the last change). resume.sim pins it: paused, Play
    Next, Next 1.5 s later, one full save 2 s after the Next and no position save.
  - player.sim's "held to the song" check read no second: now 999 s of a 100 s song reads 100 (position() and the
    bar), -5 and NaN 0:00; and restoreQueue's `setError(null)` (a "Skipped" line showing), `setBuffering(false)`
    (paused while loading) and `readSeek` (Debug's seek on its way closed) are pinned. What is left unpinned is said
    above as defensive.
  - troubleshooting.md's "deadwax's own log" for the queue warning (which never reaches the event log - `_warn_queue`
    logs without `frontend`) is now "the container's log (not the event log)".
- **Left out, on purpose** (the spec's list): a "Resume?" prompt; a setting to turn it off; syncing a PLAYING queue live
  between devices; history beyond 50 songs back; Repeat and speed following you; bookmarks; Navidrome's native
  `/api/queue`; carrying the listen heard before closing into the play count.

### Debug for admins only (2.0.0-player.63)

James (2026-10-22): "can we reduce the amount of debug info? or maybe only make the debug info available to an
admin". Info's Debug (2.0.0-player.10 on) was built for James testing on his phone; with logins (.48) and
permissions (.61) Ethan and everyone else saw it too.

- **Debug is drawn only for an admin** - /deadwax/me's `admin`: a Navidrome admin as deadwax last read it,
  break-glass, or everyone with logins off (today's behaviour, unchanged). `app/access.ts`'s store carries it
  (`Access.admin`, from /me, and before /me from the session - no session meaning logins off, so an admin), and
  a change of it alone redraws its readers. App hands `admin={access.admin}` to `InfoSheet`, which stays a leaf.
- **Everyone else's Info is About alone, with no tab strip** - not a strip of one, and no empty Debug to tap.
  The scroller is then `role="region"` named by the sheet's title, not a tab panel of a tab that isn't there.
  The rules are pure, in `lib/debugRows.ts`: `infoTabs(admin)` and `shownTab(tab, admin)`; `INFO_TABS` and
  `InfoTab` moved there from InfoSheet.tsx so debug.sim can hold them.
- **About's "Playing" group, for everyone** (admins too), after the artist and before the folder (which stays
  last, so a line landing late moves nothing a finger reaches for): Format, Gapless and Normalization -
  `playingRows()`, Debug's own `formatRow`, `gaplessRow` and `normalizationRow`, so the words are Debug's and
  the sims' (debug.sim holds the three to be exactly Debug's rows). Nothing else of Debug moved. About now asks
  `sentFormat` (the player's own audio element's `canPlayType`, nothing set on it) for the Normalization row,
  which says an MP3 transcode isn't levelled; still only while Info is open. `useLevelAnswer` already asked the
  level whenever Info is open, whatever the tab, and its route is a user's (`tests/test_logins.py`).
- **A role change**: App asks /me again as Info opens, on either frame (through the one `meRequests`
  latestOnly, a failed ask leaving things as they were), so a role given or taken shows at the next open -
  once that ask answers, a round trip after the sheet appears (review: for that moment a person just made
  ordinary still sees the Debug they left it on, and a person just made an admin sees the strip arrive above
  the list). Accepted, not held back: holding Debug until the ask answers would flash About at an admin on
  every open, and Debug shows only this device's own readouts to someone who was an admin a moment before;
  the docs say "a moment after it opens". The role going while Debug shows draws About at once (`shownTab`),
  and an effect forgets the Debug chosen, so a role given back opens on About.
- **Focus kept when the strip goes** (review): the role taken away with a tab focused unmounted the tablist
  with the focus in it, dropping it to `<body>` - out of a phone's sheet, and on a desktop's panel out of
  reach of its Escape. The render that removes the strip, while it is still in the page, notes that focus is
  inside it (`strip.current.contains(document.activeElement)`), and a layout effect on `tabs.length` then
  focuses the list (`#app-info-panel`, a tab stop, `preventScroll`). Focus anywhere else is left alone.
- **Device rows are read on the device** (review): the docs no longer say "ask an admin to look" for a row
  about the device - Sent as, Resampled, Why, Speed, Gap, Last seek, the turntable's sound, timing and
  recording read the browser Info is open on, so an admin on their own phone reads their own. Troubleshooting's
  "Info has no Debug tab, or it went" splits the rows about the song (Navidrome sent's three, readable on any
  device) from those (an admin signs in on the person's device), and the entries point there.
- **Debug itself loses nothing** for an admin: the five sections, the Record 20 s recording, the test bench
  link, Navidrome's field names. The bench at `/player/lab/` is still reachable by its address.
- **Nothing on the server changed**: no route exists only to feed Debug (its rows are drawn from what the page
  already has; the turntable report and recording are the page's own; the level route also feeds About and
  the stream), so none was added, removed or re-guarded. The app only hides, as with permissions.
- **No other debug readouts**: the turntable (`player/Turntable.tsx`) and Now Playing draw none of their own -
  the speed fader's readout and the visualizer's "feel" are controls and a feature, not debug - so nothing
  else needed the rule.
- Pinned: info.sim (no strip and no tab without `admin`, About's four headings and the three rows, nothing of
  Debug, the region, the role going and coming back, focus handed to the list when the strip goes with it
  inside and left alone otherwise; Debug's own `sentFormat` ask counted apart from About's, which since this
  slice asks too), debug.sim (`infoTabs`, `shownTab`, `playingRows` equal
  to Debug's rows and found among them), signin.sim (the store's `admin` from a session and from /me, logins
  off), app-rules.sim (App's prop and its /me ask on open, access.ts's three admin rules, InfoSheet's gating
  and its focus hand-off, nothing but Info drawing `debugSections` or the bench link).
- **NOT verified - the iPhone's**: an ordinary account's Info on James's phone (About alone, Playing's rows),
  and an admin's unchanged.

### The main page retired (2.0.0-player.66)

James (2026-10-23): "the old page will be removed with 2.0.0". The app at `/player/` does what the main page at
`/` did - his parity audit's 158 capabilities, re-checked against ce501b4 - so the main page went in one commit.
The last version that has it is tagged `last-main-page` (ce501b4; not a `v*` tag, so it publishes nothing).

**What went.** `interface/index.html`, `interface/scripts/` (main.js, resize.js, init.js and the four `.mjs`
twins), `interface/styles/main.css`, `interface/assets/` (two LidBrainz icons and two logos); `ui/src/main.tsx`
and `ui/src/bridge.ts` (`window.deadwax` is gone - "an empty bridge means the migration is done"); the thirteen
files only it reached (LibraryView, LibraryTree, LibraryDetails, ArtistDetails, CandidatesPanel, DownloadsPanel,
DownloadJobRow, StoreStatusBox, SignedOutNotice, Tabs, useNewImports, useTrackFields and lib/treeWindow.ts), and the exports in kept files that only they used (the column half of trackFields, the
tree half of libraryTree - it keeps `discTitle` - the row text of candidates and jobs, LibraryParts' AlbumArt,
IssueChips, ArtistIcon and CoverGrid, persisted.ts's layout keys, `newImports`, `describeIssues`,
`returnTarget`); `SettingsView` the component, its file keeping the server settings' parts the app draws
(`tabMarks` lost its third, main-page-only argument); the dev harness (`ui/index.html`, `npm run dev`, vite's
proxy) rather than pointing it at the app; `sort.sim` with `sort.mjs`. `docs/FRONTEND-MIGRATION.md` moved word
for word to `notes/frontend-migration.md`. The app's own ways back to the main page went too: You's row and
footnote, the desktop sidebar's "Open the main page", the sign-in's `?return=/` hand-back.

**What stayed.** Every backend route, `GET /deadwax/library/queue/new_imports` included though nothing calls it
now. The editors the Edit panel hosts (MetadataEditor, TrackTagEditor, DeleteAlbumDialog, ArtViewer, the Get
buttons), unchanged: their computed styles were compared element by element with ce501b4's in the Edit panel at
1440 and 390 (metadata 580 elements, tags 104, delete 13: none differs). The app's one-time carry-over of the
main page's Format, quality floor and Confirm before cancelling from its old browser keys (`readPreferences`,
`readDownloadDefaults`), which never clears them.

**`/` is a 307 to `/player/`, from the server.** `app.py` routes GET and HEAD of `/` and `/index.html`, before
the static mount, to `RedirectResponse("/player/", status_code=307)`; `RevalidateInterfaceAssets` sends both
`no-cache` (`REVALIDATE_PATHS`), and `RelativeRedirects` (2.0.0-player.65) has nothing to do since the Location
is already relative - pinned behind a TLS proxy anyway. Not the plan's HTML redirect page: a 307 needs no script
and draws nothing, works for HEAD, and is never permanent - a 301 or 308 is kept by the browser for good, and
`/` could never be given back. A browser holding the old page revalidates it (it was always `no-cache`), gets
the 307 and follows it. The query is dropped (`/?return=/` lands on `/player/`); the browser carries any
`#fragment` itself. The two routes are public (tests/test_logins.py ROUTES, GET and HEAD), and the logins mark
goes only on the app's page now.

**Old links: nothing to map.** The main page never had hash routes - no `location.hash`, `hashchange` or
`history.*State` in `interface/scripts/` in any commit, its tabs lived in `main.tsx` state - so a fragment that
rides the 307 is the app's `parseHash`'s to read: an app route (`#/library`, the player's old `#/album/<id>`)
opens; anything else opens Home. **Home-screen icons**: the main page had no manifest, no
`apple-mobile-web-app-capable` and no apple-touch-icon, so an icon for `/` was a Safari web clip; on iOS 26,
where every home-screen site opens as a web app, its scope is `/`, and `/player/` is inside it, so the 307
stays in scope. The installed app's manifest (`/player/`, its start_url and scope) is byte for byte ce501b4's.

**The token trim.** With main.css gone, 109 of theme.css's 260 tokens were read by nothing - liveness counted
transitively, a token alive only if a live token or a rule in player/*.css, player/lab/*.css or ui/src reads it.
They went in this commit; sections 3, 4, 6, 8 and 9 emptied and were dropped, keeping the other numbers so
"section 10" still means the app's `--dw-*`. `tests/test_app_css.py`'s
`test_every_token_theme_css_defines_is_read` keeps a dead one out (it fails on `--accent-muted` put back).

**Frozen twin expectations.** owned, tracklist, latest and credits sims held the TypeScript copy to the
main page's `.mjs` twin. With the twin gone, its answers were frozen into the fixtures first, from the twin
itself: `tests/fixtures/pressings/owned.json`'s `frozen` (the exported names, the folded pairs, the tooltip)
and each pressings fixture's `expected.pairs` (a count and a sha256 of every pair's answer) and
`expected.picks`; tracklist.sim's thresholds and exported names are literals. The sims keep every case,
against the TypeScript alone.

**Gaps James accepted.** "yeah I like those recommendations" (2026-10-23): G1 built (below); dropped - bitrate
floors under 320 (the app's are Any, 320 kbps, Lossless, 24-bit), MusicBrainz's "% match" on a search result,
format chips built from the formats found (the README and downloading.md no longer promise them); and the small
losses: the server settings' last tab not remembered, an artist's albums not orderable newest first, the
candidates' starting filters and sort not saved defaults, the library's total length, "N tracks carry their
own picture" said per track only, the Library's Artist and Title orders not reversible, "Open the log on start"
and "Reset preferences".

**G1, Needs a look's Ignored chip.** "It's fine as it is" ignores every outstanding issue, `not_in_navidrome`
included; the folder then leaves Needs a look, and Edit opens only from an album page (which Navidrome must
list) or a Needs a look row - so a folder Navidrome doesn't list, once accepted, was out of reach; on the main
page the tree still listed it. Now `facets()` ends with **Ignored N** (title "Albums whose issues you accepted
as they are") when any album has an issue found and every one of them ignored (`isIgnoredOnly`); its rows,
artist then album, carry a quiet "Ignored" mark (its title naming what was accepted) and open Edit like any
row, where un-ignore already is. The mark is drawn under that chip only: a new import whose every issue was
accepted outside a session (nothing marked it reviewed) is still in All, being new, and is drawn there as
before - New alone (review: it said New and Ignored at first). A view, not a count: All and the badge still
count outstanding issues and new imports only ("never count different things"). Same saved scan, no new
request. Pinned in needslook.sim.

**A checkout built before .66 keeps `interface/dist/deadwax-ui.js`** (and its map and `assets/`): `interface/dist`
is gitignored, so a pull doesn't delete it, and StaticFiles serves it until `npm run build` empties the folder
(`emptyOutDir` on the app's pass). Nothing loads it, so it is harmless; but it is why test_pages' 404 check
asks only for tracked files (review). CI and the image build from nothing.

**The server's own words.** Its messages and log lines said "the settings tab" (MUSICBRAINZ_EMAIL unset, Navidrome
not set up or its address unusable, the start-up and override lines, the CD-art fanart.tv hint), and
LIBRARY_PATH's row said it is "what the library tab reads": the app's page is Server settings, and its Library
tab is Navidrome's. They now say Server settings (Connections where the setting is), and the row names what
reads the folder, as configuration.md does (review). test_pages fails on "settings tab" in any string under
src/ but docstrings and the SQL schema; test_settings pins the row.

**Docs.** The guide describes only the app: finding-music, downloading and library rewritten, player.md
retitled "The app" (its file name kept for the links), troubleshooting gains "An old bookmark or home-screen
icon opens the app" and loses the main page's entries, getting-started's "Coming from 1.x" names
`last-main-page`, and the prerelease history ("since 2.0.0-player.N") came out of the README and docs - the
README's `:player` rows and compose pin are the merge commit's. All twelve screenshots were recaptured from the
app (notes/screenshots.md).

**Pinned**: test_pages.py (the 307 for GET and HEAD, logins off and on, `/?return=/`, no-cache, following it
gives the app, relative behind TLS, the files gone and their addresses 404, nothing reaching for the bridge;
vite's inputs are the app and the bench alone), test_logins.py, test_health.py, test_app_css.py; app-rules.sim
("the main page retired": no `href="/"` and no "main page" in the app's code, no `window.deadwax`, one app
entry), signin.sim (`?return=/` drawn as any load), you.sim, needslook.sim, libraryscan.sim (tree.sim's
surviving checks). **Checked in a real page** (my own instance, stand-ins): `/`, `/index.html`, `/#/library`,
`/#/album/<id>`, `/#settings` and `/?return=/` land in the app at 1440 and 390, with logins off and on (the
sign-in at `/player/`, then Home), with no request for `/scripts/`, main.css or deadwax-ui.js and nothing in the
console. **NOT verified - James's**: the home-screen icon on his iPhone, an old bookmark or icon for `/`, and an
old `/` tab reloaded.

### Settings described for the person using them (2.0.1)

James, 2026-10-23, right after 2.0.0: "let's clean up the settings. I need the descriptions to be more user
oriented and not testing oriented. Like where gapless says 'an experiment' is unacceptable." The words had been
written while each feature was on trial on his phone, so some said how a thing was built or how it compared
with before rather than what it does for you. Words only: no behaviour, default, setting name, value or route
changed, and the engine files have no diff.

**You.** Every note says what the setting does and when you'd change it. Gapless: "Plays one song straight into
the next. In Safari and Chrome, FLAC albums play through with no pause at all, as they were recorded; other songs
change with a much shorter pause. It downloads the next song ahead, which uses more data, and on a slow
connection that can stop helping: turn it off if song changes are no quicker" - the guide's own advice (Gapless
never stops the music; on a slow connection it costs data and stops helping), and the one stream's browsers
(it is still off by default - the words don't tell anyone to leave it on). Getting albums' note now says what
both "When I tap Get" choices mean (Pick the best shows the sources instead when nothing matches well, or when you
already have the album or are getting it - autoPickBlocked's other cases, so no "only"); Now Playing opens as, Pause winds the record down and Normalization's notes
were tightened, the first two ending "For phones: a big screen has no Now Playing view" / "... has no turntable"
(You shows them on a desktop too, where they change nothing; "big screen", not "desktop", because app-rules.sim
holds You.tsx free of the word - You is told no frame); the closing line no longer counts the settings ("All five"). Maximum quality's two notes keep
every fact the sim holds them to (88.2 to 384 kHz, 48 or 44.1 kHz, lossless 24-bit, "with Gapless on", 3 dB
quieter with Normalization off - HEADROOM_DB) in plainer words. Original says hi-res songs are sent "at their own rate, in case a USB DAC can play them at
it" - not "exactly as they are" (Normalization, on by default, levels them under Original too) and not "the
choice for a USB DAC" (whether an iPhone ever runs one at a song's own rate isn't known: player.md's Maximum
quality and Known gaps); settings.sim holds both out.
Normalization's Off no longer measures itself against "before this setting": "No levelling: every song plays
exactly as the file is, bit for bit, unless Maximum quality converts it."

**Server settings.** For an admin running a home server: the intro line says a saved change takes effect at once
and is used instead of the compose file's value until reverted; SLSKD_URL, SLSKD_APIKEY, the picture keys,
MUSICBRAINZ_EMAIL, the three Navidrome rows, DEADWAX_SECRET_KEY, DEADWAX_ADMIN_PASSWORD, LIBRARY_PATH,
SLSKD_INCOMPLETE_PATH, DB_PATH (and its locked reason), the player cache's two rows (no longer "for Safari"
alone: the cache holds what iPhones and Safari seek in, Gapless's stream and the resampled and levelled copies
too), the shared-account lock ("deadwax's own Navidrome account, which deadwax uses for its own work and for
anything that isn't one person's" - with logins on each person plays as their own, as the row beside it says),
PLAYER_CACHE_MB's "a few GB suits it better" (said only at the default or under it, never to an admin who gave
the cache more), the organizing verdict's blockers and the group's note (ORGANIZE_MODE "is set to Off" / "Dry
run", the dropdown's words, not `'dry_run'`; organizing is "the only setting here that files or moves your
music", since the caches write files too), and the notes of When a download fails ("the sources", the app's word, not "the
candidates list"), Cover art (Get cover and the Edit panel, not "the metadata editor") and Lyrics (an album's Get
lyrics). AUTO_RETRY_PEER's off line named a button the app doesn't have ("Try next peer"); it is **Next peer**,
in Requests - configuration.md and .env.example's AUTO_RETRY_PEER comment ("in the downloads panel" too) said
the same and are fixed with it. ORGANIZE_MODE's dropdown names its modes Off,
Dry run, Copy and Move (ORGANIZE_MODE_CHOICES; the values stay `off`/`dry_run`/`copy`/`move`, and the Organize
modes list under the group still shows them as compose takes them). The rows are still titled by their
environment names: an admin types those into compose, so they are words a person acts on.

**Docs.** player.md's "Gapless playback (experimental)" is "Gapless playback" (its anchor `#gapless-playback`,
every link to it changed), the README's "Gapless, as an experiment" and troubleshooting's "is an experiment" went,
and player.md's and configuration.md's Normalization Off and By song match the app (Off keeps "unless Maximum
quality converts it" in both, and player.md's "Off is bit-perfect" no longer measures itself against "before
this setting existed" - nor says the file is sent "exactly as it is", which a 24/192 FLAC resampled under the
default Up to 48 kHz is not: it is the file itself "unless Maximum quality converts it"). player.md's "What still needs
trying on a real iPhone" is a section of the guide, not a setting's words, and is left.

**Pinned**: tests/test_settings_words.py - no word "experiment", "trial", "test", "verified" or a build number
in the settings route's answer (a plain install, a filled-in one, a broken one reaching every "unrecognised"
branch, as an admin sees it and as someone given Settings and the log does), in the tables the rows are drawn
from, in any string literal of src/routes/settings.py but its docstrings, or in the comment-stripped source of
You's and Server settings' files; ORGANIZE_MODE's labels are words over the same values, and the blockers and
the group note use them; PLAYER_CACHE_MB's advice only at or under the default; the shared-account lock never
says everything goes through deadwax's account; configuration.md's Normalization Off and player.md's "Off is
bit-perfect" keep Maximum quality's exception; .env.example names Next peer in Requests, never "Try next peer". you.sim scans
everything You draws (About's version taken out) and pins the new notes word for word; settings.sim scans the
choices' labels and notes and pins Maximum quality's and Normalization's word for word.

### Errors and connections in a listener's words (2.0.4)

James, 2026-10-23: "apply that same review to the info panel and everything else. I want to make sure it all
provides a good user experience." The words-and-UX review of every screen (~225 findings) found the worst
problem to be listeners shown raw server errors, settings and plumbing where they needed a sentence; he chose
to build its five words batches in order, and this is **batch 1, errors and connections**, with the review's
"error classification" and "server reason codes" (its "Bigger than wording" B1, B7). Words and small UX only:
no route's status changed, nothing heard changed, and the engine files have no diff (the player's own
playback-error words live in usePlayer.ts and are batch 4's).

**One helper, `lib/errorWords.ts`** (pure). `errorKind` classes an error by what it is - never by its words, but
for one test: **offline** (fetch's TypeError: "Failed to fetch", Safari's "Load failed", Firefox's
"NetworkError…"), **timeout** (408, 504, a TimeoutError), **unreachable** (a 502/503 with no words fit for
anyone), **not-found** (404), **not-allowed** (401, 403), **refused** (a 4xx - or a 502/503 - whose words are
fit for anyone, or an answer deadwax split in two), **other** (a 500, an error of the page's own). The one test
of words is `plumbing`: a setting's name (`[A-Z]+_[A-Z_]+`), an address, an exception's name, an errno, a path,
http.ts's "GET /x failed", a status ("answered 502"), slskd, "Navidrome said" - such words never become a
listener's line. `errorWords(error, {admin, service, gone, failed})` gives the sentence (`text`), what to do
(`advice`) and, for whoever runs deadwax only, the error's own words (`detail`; the server's `why` first). The
sentences: "Can't connect to deadwax." + "Check your connection, then try again."; "That took too long." +
"Try again."; unreachable by whose answer it was - `serviceOf`, from the route ApiError now carries (`path`):
the Navidrome routes "Can't reach the music server right now.", the downloads' and slskd's "Downloads aren't
working right now.", anything else "deadwax can't do that right now." - + "Try again in a minute"; a 404 the
caller's sentence (`gone`), else deadwax's words, never FastAPI's bare "Not Found"; a 401 "Your sign-in has
ended - sign in again."; a 403 deadwax's words ("That needs Edit albums…"); refused the server's words AS
WRITTEN (a user's name in them is never re-cased; "deadwax" and "slskd" never capitalised); other "Something
went wrong." + "Try again". To someone who doesn't run deadwax the advice adds "- if it keeps happening, tell
whoever runs deadwax." (unreachable, other), "If it keeps happening, tell whoever runs deadwax." (deadwax's own
5xx in words) or **"Tell whoever runs deadwax."** (deadwax's split 503); whoever runs it is never told to tell
themselves, and gets the detail instead.

**Who runs deadwax** (`access.ts seesDetail`): an admin, or someone given **Settings and the log** - they read
the event log anyway. They see the error's own words in a smaller line under the sentence (`.app-error-detail`)
or, in a one-line notice, in brackets after it.

**How a page says it.** `app/ErrorNote.tsx`'s `errorNote(error, opts)` and `errorLine(text, detail, opts)` are
FUNCTIONS returning the page's own `<p>`/`<span>`, not components: a page's words stay its own (every sim reads
them as it reads the rest), and they call no hook, so `{error ? errorNote(error) : null}` changes no hook order;
who reads is what /me last said (`accessNow`). `app/sayError.ts`'s `sayError(error, lead)` is the one-line form
for stores that keep words (the pins, the playlists, Getting albums, Search's halves, a notice) - no JSX, so a
store needs nothing of Preact's. Pages that kept `x instanceof Error ? x.message : String(x)` in state now keep
the error itself (`unknown`) and say it at render: Home's Recently added, the Library root and sections and
Songs (usePaged), the album page (its 404 "This album isn't here any more - it may have been moved or
deleted.", and Add/Remove's refusal), the artist page (the library half; the albums-you-don't-have half's
non-MusicBrainz failures), Search's library halves and the album you don't have (via sayError), Sources (the
search's error - "Downloads aren't working right now." with slskd's words for whoever runs deadwax, never
"Error searching slskd: HTTPConnectionPool…"), the store box's Join and Add, the pins (read, pin, Edit - "Couldn't
pin Dummy. …", "Not saved. …"), the playlists (list, open, refresh "Couldn't update this playlist - showing it as
it was.", edit, delete, add, create), You's /me failure, Getting albums' saves, Change password, Your library's
Put away, and the Library sections' "Couldn't update this list - showing it as it was." (was "Couldn't refresh:
<raw>").

**Requests' reasons** (`jobErrorWords`): every string the server writes into a job's `error` - store.py's
TRANSFER_FAILURE_REASONS, poller.py's `_fail` and filing messages, routes/download.py's cancel - has a sentence
("The person sharing it refused to send it.", "deadwax lost track of this download - the person sharing
it may have gone offline, or downloads stopped working for a while." - slskd down or restarted looks the same as a
peer gone, since get_downloads answers [] on any failure, "It downloaded, but deadwax couldn't find its files to add them to your library." for
`NOTHING_ORGANIZED`, "…couldn't be added to your library." for `organize failed: <exception>`, a dry run's, the
already-there and failed-to-organize counts; "3 of 10 files arrived." after a failure's reason). A RequestRow
carries `reason` (everyone's), `reasonTell` (JobCard adds "Tell whoever runs deadwax." for anyone else) and
`reasonDetail` (the job's own words, for whoever runs it); a retry's problem `problemDetail` likewise
(RETRY_WORDS says slskd's "still stopping the last attempt" in a listener's words; plumbing becomes "The
download couldn't be started."). A Done row that wasn't added says the sentence instead of "Not filed: <raw>" -
and (after review) keeps the tell and the job's own words too: outcomeWords returns them, the row carries them as
reasonTell / reasonDetail, and DoneRow draws the words under the line for whoever runs deadwax (with logins off,
everyone - the SLSKD_DOWNLOAD_PATH hint is theirs) and "Tell whoever runs deadwax." for anyone else.
Words that are fit as written ("reel2reel went offline after 4 of 10 files") pass as written. The ending words
themselves - Partly filed, Interrupted while filing, organizing, peer - are batch 3's. The failure banner is
"Can't update your requests right now" over the error in a listener's words (no "try again": it asks again
itself), the database line "Requests can't be shown right now: deadwax can't keep track of downloads. Tell
whoever runs deadwax." to anyone but whoever runs deadwax (they keep DB_PATH); a Done row that can't open says
"Can't open this album yet - the music server isn't set up." / "Can't open this album right now - the music
server can't be reached. Try again in a minute." (App's navidromeProblem).

**The Navidrome gate** (NeedsNavidrome): a listener reads "Your music isn't available right now" / "…yet" and
what to do (Try again; or to tell whoever runs deadwax) - never Navidrome's address, its error or a setting;
whoever runs deadwax keeps "Connect Navidrome" / "Can't reach Navidrome" and the reason (troubleshooting's
titles); **Set up Navidrome** is an admin's alone (Navidrome's rows are), a Settings holder reading "An admin
can set it up in Server settings (Connections)." It reads `accessNow()`, not a hook: a leaf the sims call as a
function, drawn again with every status.

**You -> Connections** is for whoever runs deadwax only: nobody else's You draws it, and nothing is asked for
them (no MusicBrainz ping either). Each row says a word for its code (`PING_STATUS`: "Can't reach it", "Not on
Soulseek", "Key refused", "Not running", "Not set up", "Unclear", "No answer", "Busy"…) - never the code - over a
sentence: slskd's from the server (slskd_endpoint.py `PING_WORDS`, in place of the log's own lines - "slskd ping
failed with connection error, functionality enabled, but couldnt connect…"; slskd's state keeps
describe_server_state's words; get_client's own refusals, SLSKD_URL unusable or no SLSKD_APIKEY, are a new code
`NOT_SET_UP` with their words, where they were UNKNOWN_ERROR), MusicBrainz's from `MUSICBRAINZ_LINES` (its ping
answers with request_with_retries's error dict, shared with every MusicBrainz question, so its words are the
app's). A ping deadwax didn't answer is "Couldn't check". You's "Check again" goes with Connections (/me is asked
again as You shows).

**The sign-in and a session's words** (src/auth.py): **`Explained`**, an HTTPException with a `why`, answered
by app.py's handler as `{"detail", "why"}` with its own status: `detail` for anyone, `why` for whoever runs
deadwax. Logins that can't work (`unusable()`: the key, organizing off) answer `CANT_SIGN_IN` "deadwax isn't
ready for signing in, so nobody can use it just now." with unusable()'s words as the why; a database that can't
be read `NO_DATABASE` "deadwax can't read its database just now, so it can't check who you are." with
`NO_DATABASE_WHY` (DB_PATH); Navidrome not set up or its address unusable at a sign-in `NAVIDROME_UNSET`
(was "deadwax can't ask Navidrome: {e}"); Navidrome answering oddly `NAVIDROME_REFUSED` (was "Navidrome couldn't
check your password: {e}"); an LDAP account `LDAP_ACCOUNT`. `KEY_CHANGED` is "deadwax's sign-ins have been reset
since you signed in - sign in again." (the log names the key, as it did). Navidrome down at a sign-in keeps its
words, with no why. The app (`lib/signIn.ts`): `signInProblem` shows deadwax's words only when they hold no
plumbing - a split 503 with " Tell whoever runs deadwax." after it - else "Something went wrong on the server -
try again in a moment." (was "deadwax answered 500"); no answer at all "Can't reach deadwax. Check you're on the
right network (or your VPN is on) and try again." (was "…over WireGuard…"); `signInWhy` is the why (or a
detail too technical for the line), drawn folded under **For whoever runs deadwax** (a `<details>`, signin.css)
- the screen can't tell who is reading, at the gate's failed /me as on a failed sign-in. The playlist route's
part-saved answers (PART_SAVED, SAVED_UNREAD) are Explained too: the sentence, with Navidrome's words as the why
(they were ": {why}" on the end).

**The database-down lines** add "Tell whoever runs deadwax." for anyone who doesn't run it: Getting albums'
(`GETTING_UNSAVED`), Your library's (`LIBRARY_UNREAD`), a pin's (`pinsUnsaved`), Requests' (above). Needs a
look's IGNORES_UNSAVED is a managing page's, read by those who run it, and is left (batch 5).

**Left for later batches, on purpose**: the managing pages (People, Server settings, the event log, Needs a
look, Library care, Held by nobody, the Edit panel's editors and inspector, the artist panel) still show their
errors' own words - their readers are those who run deadwax (batch 5); the player's playback errors
(usePlayer.ts, an engine file - batch 4); the vocabulary inside fit server words ("in the store", "MusicBrainz
release id", Navidrome by name - batches 2 and 3); Home's Arriving line ("Can't reach deadwax just now"); a
"Server: everything's working" row for listeners in You (the review's #2 offered it; batch 1 as the review
defines it doesn't build it).

**Pinned**: ui/test/errors.sim.cjs (new) - every class and sentence, for a listener and for whoever runs deadwax;
THE SCAN: every raw error the app is known to meet (slskd's traceback line, Navidrome's address, NOT_CONFIGURED,
an errno, http.ts's fallback, fetch's words…) put through every way the app says an error, for a listener -
no plumbing, no raw words, no detail; every job error read out of the Python with a sentence of its own; a word
for every ping code read out of the Python; the gate for each reader; and the listener pages and stores holding
no catch that keeps an error's raw words (`x instanceof Error ? x.message`, `String(caught)`) off a console line.
signin.sim, you.sim, requests.sim, sources.sim, search.sim, pins.sim, playlists.sim, artist.sim, mylibrary.sim
and app-rules.sim were updated on purpose - their fakes throw what api/http.ts throws (an ApiError with its
status and route, fetch's TypeError) where they threw a bare Error - and pin the listener's words beside the
admin's. tests/test_error_words.py (new): no sign-in or session sentence anyone but an admin reads holds a
setting, an exception or WireGuard; the key, organizing, the database, Navidrome unset, odd and LDAP answered
in two halves with their statuses; every slskd ping branch a sentence with its code kept, NOT_SET_UP naming the
setting; the part-saved playlist sentences. test_logins.py, test_downloads_per_person.py and test_playlists.py
now read the setting from `why`.

**Verified** (as built, before review): 3757 Python tests (3755 passed, 2 skipped; tests/test_error_words.py new - 36), pyflakes, tsc, the
build, and all 64 sims (errors.sim new). Mutation-checked (each broken, its test seen failing, restored byte for
byte): fetch's TypeError as offline; a 502/503's words passing only when fit; no detail for a listener; a job
error's sentence; the gate's listener branch; Connections and its pings for whoever runs deadwax; a catch keeping
raw words (the page scan); seesDetail taking Settings and the log; the sign-in hiding plumbing; JobCard's tell;
RETRY_WORDS; "deadwax" never capitalised; KEY_CHANGED holding no setting; no key answered as an Explained; slskd's
ping sentence; the Explained handler's `why`. Seen in a real page (headless Chromium as deadwax.test, 390x844,
logins on, a stand-in Navidrome, slskd absent): ethan's You has no Connections and his Home and Library, Navidrome
down, say "Your music isn't available right now" and the music server sentence; james's You shows Connections'
"Can't reach it" over slskd's sentence, and his Home keeps "Can't reach Navidrome" with the address; Sources with
slskd down says "Downloads aren't working right now." - with the traceback's line under it for james only; a
server with no DEADWAX_SECRET_KEY shows the sign-in's sentence and tell, the key folded under For whoever runs
deadwax; a sign-in that can't reach deadwax says so without WireGuard.

**After review.**
- "no transfers reported by slskd" said "It never started - the person sharing it has probably gone offline." -
  but get_downloads answers [] on ANY failure, so slskd down or restarted (mid-download too) ends every open job
  the same way. Now "deadwax lost track of this download - the person sharing it may have gone offline, or
  downloads stopped working for a while.", true of both (troubleshooting and downloading.md say when it's slskd).
- A refusal deadwax named a `kind` of (people.py's Refused - People's and Change password's `{detail, kind}`) is
  `refused` whatever its status, its words passing plumbing: Change password's TIMED_OUT (504) and NOT_KEPT (500)
  had become "That took too long. Try again." / "Something went wrong.", losing "sign in again with the new
  password" - and a try again then fails. Server side NOT_KEPT holds no exception's name now, and UNKNOWN /
  UNKNOWN_SAVED put what wasn't read in brackets only when it isn't one (`_unknown_words`; the log has it).
- Done rows that weren't added (above) keep the tell and the job's words.
- Connections: a "Couldn't check" row says the ask's own words in brackets after the sentence (`unansweredLine`,
  noticeWords as an admin), not "Something went wrong. Try again." alone; access growing while You is shown (a
  Settings-and-log grant landing with /me) asks the pings at once (an effect on seesDetail, a `pinged` ref so the
  first show isn't asked twice) - they sat on "Checking…" with Check again disabled; slskd's 401, CONNECTION_ERROR
  and NOT_SET_UP sentences are said for the reader - the ping route passes `is_admin(user)`, and anyone else reads
  PING_WORDS_NOT_ADMIN (Key refused "...only an admin can change it", Can't reach it "...its address (SLSKD_URL)
  only an admin can change", Not set up "...only an admin can set it", each "in Server settings (Connections)."):
  SLSKD_URL and SLSKD_APIKEY are ADMINS_ONLY.
- The artist page for an artist the music server no longer has (an old pin or link) says ARTIST_GONE, never
  "Navidrome has nothing by that id", and offers no Try again on a not-found.
- Download sentences say "your library" (an album added) and "the collection" (already there), the decided words.
- The sign-in answered with the very words the screen came up with says them once, as the answer (the live region
  reads it), with one fold.
- `retry` (ErrorOptions): where the page draws its own Try again (Home, the Library root, sections and songs, the
  artist page, Sources, Search's halves, the gate's MUSIC_UNREACHED) the advice leaves trying again to the button -
  "Check your connection.", the tell alone for a listener, nothing for whoever runs deadwax.
- errors.sim pins the whole JOB_ERRORS table (words and tell) and that it holds exactly the fixed strings the server
  writes, and the formatted ones whole; its page scan also catches `(x as Error).message`, `.message` of a caught
  error and `${error}` interpolation (checked by putting each back).
- The CLAUDE.md rule is scoped to the pages errors.sim scans; the managing pages are batch 5's.

**Verified after review**: 3764 Python tests (3762 passed, 2 skipped; test_error_words.py 40, test_own_password.py
+3), pyflakes, tsc, the build, all 64 sims; the engine files no diff. Mutation-checked (each broken, its check seen
failing, restored and compared): the no-transfers sentence (errors.sim's table), the `kind` rule (errors.sim, and
NOT_KEPT's name back in test_own_password), the Done row's detail and tell (requests.sim), the "Couldn't check"
detail and the pings on access growing (you.sim), the reader's slskd sentence (test_error_words), ARTIST_GONE and
its hidden Try again (artist.sim), the sign-in's single sentence (signin.sim), `retry` (errors.sim, sources.sim),
the tell of a dry run and of an interrupted filing (errors.sim's table), and the two scan forms
(`(error as Error).message`, `${error}`) put back into Home.tsx. Not seen in a real page after review.

**After the second review.**
- deadwax ITSELF not answering the gate's Navidrome check (fetch's TypeError: off the network, the VPN off, deadwax
  restarting) told a listener "Can't reach the music server right now. If it keeps happening, tell whoever runs
  deadwax." - the music server may be fine. lib/navidromeCheck.ts marks that status `offline` (a field the route
  never sends, on NavidromeStatus), and the gate's listener line is then DEADWAX_UNREACHED, "Can't connect to
  deadwax. Check your connection." beside its Try again; a Done row's can't-open line likewise CANT_OPEN_OFFLINE
  ("Can't open this album right now - can't connect to deadwax. Check your connection, then try again."). Whoever runs
  deadwax keeps "Can't reach Navidrome" over the error's own words, as before (batch 5's).
- test_error_words pins each slskd ping code's sentence whole (it let anything starting "slskd" through).
- requests.sim pins a retry's problemDetail by reader; you.sim the Getting albums database line's tell for a listener.
- Docs quote the three not-an-admin ping sentences as written, and the README counts Settings-and-log holders in.

**Verified after the second review**: 3764 Python tests (3762 passed, 2 skipped - no new test, the ping one now
exact), pyflakes, tsc, the build, all 64 sims; the engine files no diff. Mutation-checked: the gate's offline line and its
`offline` mark (errors.sim), the can't-open line (errors.sim), the ping sentence back to a log line (test_error_words),
the retry's detail shown to anyone (requests.sim), the Getting albums tell dropped (you.sim).

### Your library, Home and the Library in one vocabulary (2.0.5)

James, 2026-10-23: "I want to make sure it all provides a good user experience." This is **batch 2** of the words-and-UX
review's five (`work/ux-audit/words-ux.md` in the scratch folder: its "Batches" section, the findings X2, #7, #8, #9,
shot 15, and the A1-A3, A7, A9, A11 and B8 sections), with James's binding decisions (`work/ux-audit/decisions.md`):
the shared music on the server is **"All music"** as a heading and **"the collection"** in a sentence - never "the
store", "Browse", "Navidrome" or "everything" in listener text - and **Home's Recently added shows the listener's OWN
library**. The rest is the review's recommended vocabulary: "your library", "added to your library" (not filed or
starred), "Dismiss" (not "Put away"), "Get it again", "an admin", "songs" on listener pages, one label for pressings.
Words and three small UX changes - Home's source, the Properties role check, the badge; no route or status changed,
nothing heard changed, and the engine files have no diff.

**"The collection", everywhere a person reads it.** `lib/whose.ts` `IN_THE_STORE` is "in the collection" (the
identifier stays), so every line built on it changed at once: the album page's badge, the album you don't have's line
and its **Pressing** list, Search's rows and region and late place ("Searching the collection…", "More from the
collection", "The collection can't be searched just now."), songs' "a pressing in the collection", the artist page
(its facts headed **In the collection**, "Plays the 2 albums in the collection", "Looking in the collection…"), Info's
folder heading and artist count, the store box (`lib/myLibrary.ts` "In the collection, not in your library", "The
collection has 9 of 11 tracks…", "The collection also has another pressing…", the Done rows' "Already in the
collection…"), Held by nobody's "Every album in the collection is in somebody's library.", People's "the albums stay in
the collection", the listen-only warning ("They can still play, look through and add what the collection has."). The
server's own: routes/my_library.py (LOGINS_OFF, the two Add refusals - "That pressing isn't matched to a release on
MusicBrainz, so it can't be added from here.", "That pressing isn't in the collection now - Get it instead." - REMOVED,
REMOVE_UNWRITTEN "It's out of your library, but deadwax couldn't save that, so it may come back - try Remove again in
a moment.", Navidrome keeping the star "It's still in your library - try Remove again in a moment.") and
routes/held.py's flag refusal ("…isn't in the collection any more - dismiss it."). "Everything" for the collection:
Up Next's "All music, shuffled", the player bar's "Shuffle - shuffling all music"; the sidebar's "Search everything"
placeholder is **Search** (Search's own "Artists, albums and songs" didn't fit the field; its aria-label says what it
searches). Left on purpose: poller.py's job error "already in the store" (a key old rows carry, which the app says in a
sentence since 2.0.4, and admins' detail), the log's lines, and "the store index" in the docs - a mechanism's name.

**The Library root** (#8): with a library of your own the first group is yours, named so - `SIDEBAR_YOURS`: Recently
added, **Your albums**, **Your artists** - and the second, headed **All music** (`ALL_MUSIC`, was "Browse"), is the
collection's: **All albums**, **All artists**, **All songs** (`SIDEBAR_BROWSE`'s labels). No label appears twice across
the two (whose.sim pins it), the desktop's sidebar has the same two groups and headings, and each page's title is its
row's own word (`PERSONAL_TITLES`: "All albums" where it was "Albums in the store"). With logins off nothing changed:
one group, Albums, Artists, Songs. The empty states say "Nothing in your library yet." and "Look through All music and
add the albums you like, or find new ones in Search and Get them." with **See All music** (was Browse the store);
"You haven't played anything from your library yet."; with logins off "No albums yet." / "No artists yet." / "No
songs yet." (`lib/yourLibrary.ts` NO_ALBUMS, NO_ARTISTS, NO_SONGS) - never "in Navidrome".

**Home's Recently added is yours** (#9, James's choice of the review's behaviour option): `app/Home.tsx`
`recentlyAddedAlbums(personal)` - with a library of your own the Library's own list (app/albumIndex.ts `yours`, sorted
`newest` by lib/shelves.ts and cut at RECENT_COUNT, as LibraryHome does), so the two shelves never differ; with logins
off (one library, the collection) getAlbumList2 `newest` at 20 as ever. It is keyed on the `yours` generation
(useYourAlbumsGeneration - an Add, a Remove, your count moving), and App now calls `refreshIfOld('yours')` as Home
comes into view too, as it does for the Library tab. App hands Home `personal={hasLibrary()}`. Your library empty, the
shelf says the Library's two lines. The review saw ethan's Home lead with Dummy and Mezzanine, which weren't in his
library, while his Library led with his own (shot 16); in a real page now his Home and his Library show the same two.

**Your library in what the person sees** (#7). The album page: "It's already here - add it to your library to keep
it with your music." over **Add to my library**, "Added to your library." after it; "This album can't be added from
here - make it a favourite in another music app, and it joins your library." (no release id) and "…from here yet - …"
(a folder deadwax hasn't found); after a Remove Add can't undo, "To add it back, make it a favourite in another music
app." You > Your library: "12 albums · 2 waiting to be added"; "N of them is/are missing some songs."; the dead login
"New albums can't be added to your library until you sign in again. Sign out, then sign in - with your new password if
you changed it. Nothing is lost meanwhile." (never the server's `login_problem`, which names Navidrome; it also covers
KEY_CHANGED); waiting with no words "Waiting its turn to be added."; the footnote, Amperfy's one mention: "Your library
is also in your other music apps, such as Amperfy, as your favourite albums. Making an album a favourite there, or
taking it out, adds it here or takes it out within a few minutes."; an album an admin deleted "Removed by an admin."
with **Get it again** and **Dismiss** ("Dismissing…", "<album> dismissed" said), and Held by nobody's **Dismiss** too.
The delete dialog's holders "…removed by an admin." The server's waiting reasons (src/library_ledger.py PROBLEM_WORDS):
"The music server hasn't picked it up yet - it's added as soon as it has.", "An admin needs to match it to a release
on MusicBrainz before it can be added.", "Its files aren't there just now - it's added once they are.", "The music
server isn't answering - it's added once it does.", "Being added again - nothing for you to do." (not confirmed), "It
was moved or re-tagged, so it's being added again - nothing for you to do." (a star lost). Saying "Apply a release to
it in Edit album" to the admin reading it is batch 5's (M8).

**Pins** (H8-H10): "Removed from the collection" - with logins off "Removed from your library" (`pinLine(pin,
personal)`, Pinned reading hasLibrary()) - "Can't be found right now", "Not ready to play yet".

**The artist page**: "None of their albums are here to play.", "Couldn't load their songs.", "…- the rest didn't load"
(AR1); its facts' **Songs** (was Tracks); **Now known as** / **Also known here as** (was Now / Also filed as). Artist
rows count only inside your own library (shot 15): Your artists - and every artist with logins off - "3 albums";
All artists keeps "3 albums in the collection" (`albumCountLine(count, '')`). Its MusicBrainz words are batch 3's.

**The album page.** The cover viewer's missing words "No cover for this album" (AP10). **Properties** (AP11-AP13): the
release is **MusicBrainz: View this pressing ↗** - the same link, words not the raw id (so not in the data face: the
`is-mono` rule went); **Added** (was First seen), ", downloaded here" (was ", filed by deadwax"); the no-release line
"Not matched to a release - match it in Edit album" only for whoever can Edit albums - `albumProperties(…, edits)`,
AlbumPage reading `albumEdit(useAccess().permissions).editors` (an admin, an Edit-albums holder, everyone with logins
off). **Pressings ›** is the chip's one name on every frame (was "Other pressings", "Pressings" in a narrow row; the
page it opens lists every pressing, as the picker's own "Pressings" does) - `PRESSINGS`, and no long/short spans.

**"In your library" is a badge** (AP8, M3): label-sized (`--dw-text-label`), as tall as the tracklist's Bonus badge
(`--app-held-badge: var(--app-rg-chip)`, 22px against a chip's 30, its padding `--app-rg-chip-pad`), centred on the
chips' row - it had a chip's own height, padding and box and read as a button that did nothing. It keeps its words
wherever "In your library", the Also chip and "Pressings" fit whole: the narrow rule is now a row of 420px or less
(was 600), measured in a real page - badge 119px + "Also: the 2014 pressing" 182 + "Pressings" 99 + two gaps is 416,
a 390px phone's row 350, a 1024px desktop's 524, a 1440px desktop's with Info or the Edit panel open 470. There - a
phone held upright, with an Also chip - it gives way whole, as "In the collection" always has (still read; after
review - as built it kept a bare tick with no box, which read as the Also pressing ticked); M3 was a desktop with Info
open, which keeps its words now. With the words kept on a phone the Also chip read "Also: the 2014…" at 390 and "A…"
at 320.

**Pinned**: ui/test/vocabulary.sim.cjs (new) - a small tokenizer reads what a listener reads in each file (string
literals that are words, JSX text; comments, imports, class lists, scopes and regex literals left out, nested
templates followed) and checks the batch's own files say none of "store", "Browse", "Navidrome", starring, "Subsonic",
"Put away", "Request it again", "the admin", "First seen", "Other pressings", and that no file of the app says "the
store" - each rule first shown catching a sample. home.sim: Home's shelf source both ways, its order and count, the
generation, the empty words, never `newest` with a library of your own. app-rules.sim: App's `personal` and
refreshIfOld for Home, Pressings' one name, Properties' role from useAccess. inspector.sim: the Properties rows and the
role. whose.sim: the badge's tokens and its narrow rule, the groups' labels (none twice) and titles, the album page's
lines holding no starring, Subsonic or Navidrome. tests/test_personal_libraries.py: every waiting reason and every
Add/Remove answer free of store/Navidrome/star/Subsonic, and REMOVED the page's own REMOVED_FROM_PAGE. Updated on
purpose for the new words: app-rules, artist, group, inspector, mylibrary, people, permissions, pins, requests,
searchList, searchQuery, search, songs, sources, upnext and whose sims; test_app_css (the badge, the narrow rule),
test_personal_libraries, test_player_as_you.

**Verified** (as built, before review): 3785 Python tests (3783 passed, 2 skipped; two new in test_personal_libraries),
pyflakes, tsc, the build, all 65 sims (vocabulary.sim new); the engine files no diff. Mutation-checked (each broken, its
check seen failing, restored byte for byte): Home's source ignoring `personal` (home.sim, app-rules), App's
refreshIfOld for Home and its `personal` prop (app-rules), "Not in Navidrome yet", "More from the store", "(starred)"
in the footnote, a "Browse" heading, "No albums in Navidrome yet.", "Put away", "Other pressings" and a Subsonic line
each put back (vocabulary.sim, and pins / mylibrary / whose / app-rules where they pin it), the scanner skipping no
regex literal (vocabulary.sim), the no-release line shown to everyone and AlbumPage passing no role (inspector,
app-rules), the badge's chip height and the narrow row keeping its box (test_app_css, whose.sim), "All albums" or "Your
albums" named "Albums" (whose.sim), "Navidrome" in a waiting reason and "the store" in an Add refusal and REMOVED
differing from the page (test_personal_libraries), Your artists' "in your library" back (whose.sim), pinLine ignoring
`personal` (pins.sim), the old dead-login sentence (mylibrary, vocabulary). Seen in a real page (headless Chromium as
deadwax.test, a stand-in Navidrome, logins on and off, 390x844 and 1440x900): ethan (a listener) - Home and the
Library's Recently added the same two albums of his, the root's Your albums / Your artists / All music (All albums,
All artists, All songs), the empty states, You's "Your library" and its one footnote, album pages' badge ("In the
collection" grey; "In your library" a small badge, its tick alone beside an Also chip at 390, 430 and 320 and its words
at 800, 1024 and 1440 - and at 1440 with Info or the Edit panel open beside the page, the row 470px: M3's case), "Pressings ›", Properties' "MusicBrainz View this pressing ↗" with no no-release line; james
(an admin) - the no-release line "Not matched to a release - match it in Edit album", All artists' "3 albums in the
collection", Your artists' "3 albums", the desktop sidebar's Library and All music groups; logins off - one group,
"3 albums", the collection's newest on Home. No console errors.

**After review** (eleven findings, nine once duplicates are merged; each reproduced by tracing the code or refuted):
- **"N still being added" said progress for albums that only an admin can move** (a NO_RELEASE entry waits for ever):
  You > Your library says **"12 albums · 2 waiting to be added"**, true of every waiting state (`libraryLine`;
  mylibrary.sim pins it), and the docs quoting it changed - troubleshooting.md's heading too (no link pointed at it).
- **Home's Recently added was described as "what was added to your library recently"** (README, player.md, sharing.md),
  but it is ordered by Navidrome's `created` - when the COLLECTION got each album - as the Library's own Recently added
  is (the spec's "same source"; kept). The docs now say so, and that an album you Add that the collection has had a
  while keeps its old place, so it may be on neither Home shelf (New in your library leaves an Add out on purpose) -
  it is in Your albums. Ordering by when it joined your library would be a new order for the Library too: James's call.
- **The bare tick**: on a phone's row with an Also chip the badge kept its tick with no box and no words, which read as
  the Also pressing ticked. It now gives way whole there, as "In the collection" always has (still read); the line under
  Play says whose the album is (Add or Remove, logins on - with logins off every album is in your library). The
  review's alternative, letting the row wrap, was not taken: the second line lands with the bridge's answer and pushes
  the songs down under a finger, which 2.0.0-player.41 and .52 fixed. And a regression of the badge's own found
  meanwhile: shorter than a chip (22px against 30), the row drawn with it alone - unseen, until the bridge answers -
  grew by 8px as "Pressings ›" landed, moving the songs; `.app-album-chips` now holds `min-height: var(--app-chip)`
  from the first frame (test_app_css, whose.sim).
- **Get it again offered to someone who may not Get** (its page then says "Getting albums is off for you"): shown only
  with Get albums (`gets(useAccess().permissions)`, as Search, ReleaseGroupPage and JobCard gate Get); Dismiss stays
  for everyone (mylibrary.sim, both ways).
- **Stale words in the docs**: README's "Other pressings" is **Pressings**; downloading.md's "Put away" is **Dismiss**;
  player.md's and troubleshooting.md's "**Now** row" is **Now known as**.
- **held.py's reworded refusal unpinned**: test_add_and_remove_answer_in_the_collections_words reads routes/held.py's
  answers too, each free of store/Navidrome/star/Subsonic and of "put … away".
- **Not changed - New in your library and Recently added can show one album twice** (a Get filed for you is both new
  and newest): true, but not 2.0.5's - the collection's newest, the shelf until now, led with that same album too.

Verified after review: 3785 Python tests (3783 passed, 2 skipped), pyflakes, tsc, the build, all 65 sims; the engine
files no diff. Mutation-checked (each broken, its check seen failing, restored byte for byte): "still being added" back
(mylibrary.sim), Get it again ungated (mylibrary.sim), the row's min-height gone and the bare tick put back
(test_app_css, whose.sim), held.py's "put the flag away." back (test_personal_libraries).

**Second review** (four findings, all real; each fix with a check that fails without it):
- **Up Next still said "everything"**: with Repeat All on a shuffle of all music, its last line read "Then everything
  again, in a new order." - it is **"Then all music again, in a new order."** now (lib/upNext.ts; upnext.sim). The
  vocabulary scan missed it because it reads a one-word literal as an identifier (`'everything'`, like `'store'` or a
  scope), so it now has an "everything" rule for what it does read (a placeholder "Search everything" fails it) and
  upnext.sim pins the sentence itself.
- **Held by nobody was outside the scan**: its "Put away" became Dismiss in this batch, but app/HeldByNobody.tsx was
  not in vocabulary.sim's BATCH; it is now ("Put away" or "put away" back fails it).
- **Pinned's own wiring was unpinned**: pins.sim checked pinLine both ways but nothing that Pinned hands it
  `hasLibrary()`. pins.sim now signs in (setSessionMe) and reads a deleted album's card and its Edit row: both
  "Removed from the collection".
- **"Amperfy once" was unpinned**: mylibrary.sim counts Amperfy in everything You > Your library draws - once, and
  that in the footnote.

Verified after the second review: 3785 Python tests (3783 passed, 2 skipped), pyflakes, tsc, the build, all 65 sims;
the engine files no diff. Mutation-checked: Held by nobody's spoken "put away" and its "Put away" label back
(vocabulary.sim), `const personal = false` and Edit's row calling pinLine without it (pins.sim), a second Amperfy in
the footnote (mylibrary.sim), Up Next's 'everything' back (upnext.sim), the sidebar's "Search everything" (vocabulary.sim).

### Search, the album you don't have, Sources and Requests in one vocabulary (2.0.6)

James, 2026-10-23: "I want to make sure it all provides a good user experience." This is **batch 3** of the words-and-UX
review's five (`work/ux-audit/words-ux.md` in the scratch folder: its "Batches" section, findings #3, #10, #11, RG5 and the
A4-A6 and A8 sections - and the artist page's MusicBrainz words and "2 editions", which batch 2 left to this one), with
James's decisions (`work/ux-audit/decisions.md`): **"source"** for where a download comes from, never peer, folder,
Soulseek or slskd; **Get** the verb and **Requests** the list; **"added to your library"**, never filed or organizing;
**"pressing"** for one release of an album. Words and the small UX the batch names (the maybe box's tooltip made visible
text, the score as a percentage with each chip's meaning beside it) - no route, status or behaviour changed, nothing heard
changed, the engine files have no diff. Batch 1's errorWords and batch 2's words are kept; batch 2's vocabulary sim is
extended.

**Search** (#3, S1-S23). The **"saved" mark is gone**: a row from MusicBrainz's answers kept on disk is drawn exactly as
MusicBrainz's own row would be - "· saved" read as "you saved this album", and nothing a listener does needs to know
where an answer was kept. Only a failure under such rows says what they are: *Showing earlier results - searching for
more isn't working right now.* (*Showing earlier results.* in a kind's one-row slot, which must fit 320). A desktop tile's
third line for something nobody here has is **Not in your library** (**Not in the collection** with logins on, where
your library is only part of what's here; was "On MusicBrainz" / "Saved from MusicBrainz"), **Maybe in your library** for
a group a folder of its name may be (ownedForGroup's `guessed`, the album page's own "maybe" - `groupMaybe`, shared with
the group's section row, which says *maybe in your library* too, so tile and row never disagree), and nothing for an album
or song while the owned index hasn't come (lib/searchList.ts `placeLabel`, `notHere`). A MusicBrainz ARTIST tile says
*Not in your library* only once the library's artist list (getArtists, `Marks.artists`) has come and no artist in it has
that name or the name it was matched as: an mb-artist row only means newArtists or creditedRow didn't tie it to a library
artist - two Nirvanas answering stay MusicBrainz's beside the library's untagged Nirvana - and is blank otherwise (review).
A tile with a **Get** (SearchRows `topRow`) leaves its third line empty, its height kept: at 1440 with no side panel a tile
is 224px and its text 62px beside the Get, so the line read "Not in y…" (measured, review) - the Get says it isn't here,
and the group's section row and its page carry the "maybe". MusicBrainz's name is out of
every line: the hint *Search your library and albums you don't have yet.* (*Search your library, the collection, and
albums nobody has yet.*), the field's label *Search for artists, albums and songs*, the busy lines *Searching…* (was
"Asking MusicBrainz…", "Searching your library and MusicBrainz…") and *Loading…* for a More button (was "Asking your
library…"), the region's *Also found: 3 albums.* / *Found earlier: 1 song.* / *More found: …* / *Nothing more found.*,
*Show 3 more albums* (a fold), *No other albums for "…".*, *No more albums for "…".*, *Show 12 from your library*,
*Can't search for more right now.*, *Searching for more isn't working right now - try again in a few minutes.*,
*Too many searches just now - try again in a moment.*, *Studio albums and EPs - See all for everything they
made.*, *Type a little more, or press Search, to find albums you don't have yet.*, *…to find songs you don't have yet.*,
*Found songs called "…", but none is on an album yet - there's nothing to get.*, *No more results.* (was "MusicBrainz
sent nothing new."), *You already have everything found.*, **More artists** / **More albums** (was "More from
MusicBrainz"), *That's all for this search - add a word to narrow it.*, *No results for "…".* with its full stop. The
server's 422 for words MusicBrainz can't read is *That search couldn't be read - try other words* (routes/
search_musicbrainz.py REJECTED_WORDS). A row's Get reads **Getting…** while it asks (Search and the artist page).

**The album you don't have** (A5): *Loading…*, *This album's details can't be loaded right now - try again in a few
minutes.*, *There are no pressings of this album to get.*, *That link isn't an album.*, the desktop table's **Compared
with the usual** column, the pressing notes *No tracklist listed* / *The only tracklist listed* / *No tracks are listed
for this pressing* / *The only pressing (with a tracklist)*, the filter's placeholder *JP, CD, a label or catalogue no.*
(the review's "Country, format…" was not taken: the code's own comment says a country is typed as its code, as the rows
show it). **RG5**: the dashed maybe's explanation was its tooltip alone (folders' paths and "the metadata editor"), which a
phone never shows - now a line under Get, where a late line moves nothing a finger is reaching for (lib/whose.ts
`maybeLine`): *You may already have this - an album with this name is in your library, but it isn't matched to a
pressing.* (*It may already be here - … in the collection …* when the folders aren't yours), plus *Match it to a pressing
in Edit album.* for whoever can Edit albums - who alone keeps the tooltip, its words now "not matched to a pressing …
Edit album". The "· 2 editions" of the artist page and owned.ts' label are **2 pressings**. **The artist page**:
*Loading their albums…*, *Their other albums can't be shown right now - try again in a few minutes.*, *Only the albums you
have are shown - their other albums can't be found.*, *Showing their first 500 albums.*, *No other albums found.* / *No
studio albums found - turn off Studio only to see them all.*, *Artist details can't be loaded right now.*, *Loading…*.
Its "Which artist is this?" panel stays MusicBrainz's (an admin's, batch 5); **On MusicBrainz** stays over the ↗ links.

**Sources** (#11, A6). *Looking for "Third" by Portishead…* over *This takes a few seconds.* (was "Asking Soulseek…" and
"slskd listens for answers…"); **Search for** / **Search** under Search again (was "Search Soulseek for" / "Re-search");
*Nothing found for "…".*, *Nothing lossless found for "…".* over *Some were found, but none with lossless files - your
Format is Lossless only, which leaves the rest out. …* (never how many lossy ones: `response_count` counts answers);
*41 sources found - none match your filters.*; under the cards *Searched for "…" · 41 sources, 4 match your filters*;
the region's lines now each end in a full stop (it said "…Getting albums.. Didn't pick…" before). The **Starts now** chip
(was Free slot); a card's Speed note *their usual speed* (was "their own average"); Starts *now* / *after 3 others* / *soon*
(was "3 ahead" / "next" - queue_length counts those ahead, so "3rd in their queue" would have been wrong); a set shared
one folder per disc *in 2 parts, one per disc*. **The score is a percentage**, "70%" (VoiceOver "70% match"; the
desktop panel's box grows to hold "100%": `width: auto`, min-width and `--app-desk-source-score-pad`), and its reasons
are headed **Why it's a 70% match** (a visible heading, the group labelled by it). **The six signals** have names a
listener reads and what each measures written beside its chip (lib/candidates.ts SIGNAL_LABELS, SIGNAL_MEANINGS - each
read against src/matching.py): **Track names** (title_match: "the pressing's tracks it has, found by their names"),
**Track count** ("how near its number of files is to the pressing's tracks"), **Track lengths** ("the tracks found whose
length is right, to within 8 seconds" - DURATION_TOLERANCE_SEC), **Edition** ("whether its name says the same edition
(deluxe, remaster…) - its year there helps": score_edition only adds for the year), **Format** ("lossless or not, as your Format asks"), **Availability** (score_peer: "how
soon it can start: a free slot, a short queue, their speed" - the review's "Their speed" would have been untrue, speed is
a fifth of it). Each chip says its value with "%". Drawn as rows (app.css: `.app-source-signals` a two-column grid, chips
in one column so the words line up, `.app-source-signal-row` `display: contents`). The desktop's **Match details** chip
(was Signals) has the same six names; its popover is 300px with a 100px name column so they stay on one line. A pick not
made says what to do: *No close match that passes your filters - choose a source yourself.*, *You already have part of
it - choose a source yourself.*, *This pressing has no tracklist to check the sources against - …*, *It can't be told
whether you already have this pressing - …*; with no source found at all there is no such line (nothing to choose:
`notPickedLine(blocked, found)` is null at 0, and the empty state speaks - review). The store box: *To get it from another source, cancel it in Requests first.*,
*being added to your library now*, *didn't work - trying another source*, *Getting it adds only the tracks that folder
doesn't have yet.* / *Getting it would add a separate copy, in …*, *Its quality isn't known, so it may be below your
quality floor (…)*, *…another source isn't offered for a download you share.* Its folder paths stay (B6, beyond the batches).

**Requests and Arriving** (#10, A8). *starting…* (was "asking slskd…"), *didn't start* (was "refused"), *adding to your
library…* / Arriving's *adding…* (was "organizing"), *4th in their queue* / *4th in line* (was "#4 in their queue" / "#4 in
queue"), *2nd try* (was "try 2") - `ordinal()`. The buttons **Another source · 2 left** / **Same source again**, busy
*Trying another source…* / *Trying again…* (was Next peer / Ask again / Trying next peer… / Asking again…): 174px of words at
their size, so `--app-job-action-min` is 192px and the pair stacks on a 390px phone (measured in a real page - "Next peer"
fitted two across; a shorter "Next source · 10 left" still didn't). The other places naming the buttons say them too (review): People's line under Get albums
(permissions.ts LINES.request, pinned by permissions.sim), Server settings' AUTO_RETRY_PEER line while it is off (pinned by
test_settings_words), configuration.md's row and README. The retry problems *They refused - try another source.*,
*No other source would send it.*, and RETRY_WORDS turns the server's "no other peers to try - search again for more" into
*No other source to try - Get it again to search for more.*, MOVED_ON into *It's already been tried again meanwhile.* and
CLEARED into *It's been cleared from the list - Get it again to download it.*; and by how they start (`retryWordsStarting`,
review) store_index's in_flight_words and already_have, which name a source, say "being filed" and carry a library folder's
path (safeWords catches only a path from the root): *It's already downloading.*, *It's already downloaded, and being added
now.*, *It's already in your library.* (*…in the collection.* with logins on - RequestsInput's `personal`, App's
hasLibrary()). The same goes for /enqueue's 409 on a pending row's *didn't start*. The route's own words stay the detail,
for whoever runs deadwax (errors.sim reads them out of the Python; requests.sim the pending row). Done rows: *You already had it* (was "Already in your library,
nothing filed"), *In your library - 2 files couldn't be added* (was "Partly filed: 2 file(s) failed to organize";
`partlyWords`, the job's own words for whoever runs deadwax), *Stopped while being added to your library* with the tell
(was "Interrupted while filing: check the library and slskd's folder" to everyone - that is now the detail), *Downloaded,
but not added to your library* with the tell (organizing off), with logins on *In their library* (was "Filed - in their
library"), *Not added - the collection's copy may be another pressing, so an admin has been asked to check it* / *…; an
admin has checked it* (grant_for's FLAGGED is another pressing OR an untagged rip, so "may be"), *In your library - 2
files couldn't be added* for an incomplete grant. The dry run's sentence says "rehearse adding albums" (errorWords). A row
that can't open: *Not ready to play yet - it may still be scanning.*, *Can't find this album to open it - it may have moved, or isn't
matched to a pressing.*, *Couldn't open it - tap to try again.* (R19). The ✕ asks *…You'll lose your place in their queue.* Empty
Requests says "tap Get" only to someone who can Get; anyone else reads GET_OFF (the review's "Albums you join show here"
was not true: Join is Get albums' too). Arriving's stale line *Can't update downloads right now - showing the last
progress. Trying again…* (H4). The database line for whoever runs deadwax keeps slskd's folder and DB_PATH.

**Pinned**: vocabulary.sim reads batch 3's files (BATCH3: Search, SearchRows, searchList, searchResults, songs,
ReleaseGroupPage, pressings, PressingPicker, owned, Sources, SourceCard, candidates, getSettings, StoreState,
useCandidateSearch, Requests, JobCard, requestsView, perPerson, useDownloadJobs, Arriving, myLibrary, artistPage,
ArtistPage) for "MusicBrainz", "Soulseek", "slskd", peer, folder, filed/filing, organizing, "release id", "editions", the
saved mark, "Asking", Signals/Titles/Lengths, Free slot, their own average, Re-search, "#N in", Next peer/Ask again, "Get…",
"ahead" and Navidrome - each rule shown catching a sample; six lines left on purpose in ALLOW3 with why (the ↗ links'
label, the maybe tooltip, the store box's library folders, the database line for whoever runs deadwax, the artist facts'
Folder row, Held by nobody's flag line), and a check that none of ALLOW3 is stale. Its tokenizer also skips JSX "text" that
is code (a type annotation, a loop's head, a spread, a call). A one-word template part ("${n} editions", "try ${n}") reads
as an identifier to it, so those two are pinned by artist.sim and requests.sim instead. candidates.sim: the six names and
meanings read against matching.py (WEIGHTS, DURATION_TOLERANCE_SEC), Starts' words, the not-picked lines; sources.sim: the
"%" score, the heading, each chip beside its meaning, Match details; requests.sim: every row's new words, `ordinal`, the
empty line by reader, the tell on a stopped filing; group.sim: the maybe line for an editor and a listener (no tooltip);
searchList.sim: Not in your library / the collection / Maybe, no saved mark; test_app_css: the signal rows' grid, the
desktop score box, the 192px stacking point. Updated on purpose: artist, candidates, errors, group, owned (its fixture's
"2 pressings"), pressings, requests, search, searchList, searchQuery, songs, sources, vocabulary, whose sims;
test_app_css, test_musicbrainz_routes.

**Verified** (as built, before review): 3786 Python tests (3784 passed, 2 skipped; one new in test_app_css), pyflakes,
tsc, the build, all 65 sims; the engine files no diff. 35 mutations, each caught and restored byte for byte (sha256
checked; `work/uxb3-builder/mut/mutate.py`) - among them the tile's "On MusicBrainz", the saved mark, the maybe tile, a
MusicBrainz word in Search / the album page / the artist page, "Get…", the old hint, "peer" as a signal's name, the 8 s
meaning, the meaning or "%" not drawn, Free slot, slskd in the asking note, "#4", Partly filed, the interrupted tell,
Next peer, the ordinals' teens, "as another copy", the empty line ungated, "the peer refused", Navidrome in a Done note,
Arriving's old line, the maybe tooltip for everyone, the maybe line not drawn or ungated, "2 editions", the retry words,
a stale ALLOW3, the code filter, the 150px stacking point, the signal grid, the desktop score box, the server's 422
words. Seen in a real page (headless Chromium as deadwax.test, logins off, my own deadwax on 8110 over a stand-in
Navidrome and slskd, real MusicBrainz; 390x844, 320x640, 1440x900): Search's hint and rows, Requests' four sections and
Arriving in the new words, the retry pair stacked at 390 and 320 and side by side at 1440 with no label clipped, the
album you don't have's "not in your library", Sources' asking lines, chips, "65%" scores (55px with the chevron on a
phone, 35px on the desktop panel), "Why it's a 65% match" with each chip beside its meaning (two lines each at 390), the
footer, and Match details' six sliders on one line each inside the panel; no horizontal scroll, no console errors.
