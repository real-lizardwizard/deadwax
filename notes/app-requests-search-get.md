# The app: Requests, Search, the album you don't have, Sources and Get

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Requests, and what's arriving (2.0.0-player.12)

Slice 3 of the one app (`uplan/slices.md` S3, numbered .12 because the turntable went in first).
The boards are `Requests.dc.html` and `Home.dc.html`'s Arriving card. James, of Arriving: "is it
possible to hide arriving when there isn't anything arriving? ... I don't know that I want it to be
persistent all the time".

- **`useDownloadJobs` is called ONCE, in App** - the hook the main page's downloads panel uses,
  unchanged, as is `downloads.sim.cjs`; the old page keeps its own instance (another page, another
  module instance). So the Requests tab, Home's Arriving and the tab's badge are one poll and one
  set of overlays. `app-rules.sim.cjs` holds it to one call there and in no other app file. Its
  `open` is `watching === 'requests' || stalled`. `watchingOf()` (requestsView.ts, pure, pinned)
  makes `watching` from the tab, the depth of its stack, Now Playing and the page being shown: the
  Requests tab's ROOT showing (`nav.stacks.requests` empty - Go to album can push an album on it),
  Now Playing not over it, and the page shown (App's own `usePageShown`, on `visibilitychange`;
  Turntable keeps its own `useVisible`, which app-rules reads there). So it polls every 500ms only
  then, every 5s (1s while filing) while something is active, and otherwise stops, as the hook
  always did.
- **A failed look while something is arriving keeps it asking** (`stallsOn`, review). The hook
  stops for good after one failed poll with `open` off - `hasActive` is false in its catch - so a
  Komodo redeploy or the phone off the VPN for a moment froze Home's Arriving and the badge on the
  last answer until a tab switch. App can't run a timer (app-rules), so `stallsOn(watching, error,
  view.arriving.length)` - on Home or another tab, the last look failed, something on its way - is
  put in state by an effect and ORed into `open`: the hook polls every 500ms until an answer clears
  the error, then the next render turns it off. Arriving says so meanwhile (`trouble`: "Can't reach
  deadwax just now: this is its last answer, and it keeps asking."). **The root fix belongs in the
  hook, on main first** (keep polling after an error when the last good answer had active jobs):
  main's Downloads badge freezes the same way; this is the app's side of it until that lands.
- **Asked again without a poll left running** (`asksAgain` in `lib/requestsView.ts`, pinned): App
  tracks what it shows as `Watching` - requests, home, other, hidden - and calls the hook's
  `refresh()` as Home comes into view (a tab switch, back to its root, Now Playing closing over it)
  and as the page comes back from hidden on any tab but Requests. Never for Requests itself, coming
  or going: `open` changing re-runs the hook's effect, which polls at once - a `refresh()` beside it
  would be a second request, throwing the first's answer away. Nothing on mount: the hook's own first
  poll is there. So a download started on another device shows when you look, which is what the
  plan's "refresh on visibility" was for.
- **App registers `handleDownloadRequests(enqueue)`**, so a Get hands its pending row to the one
  hook. Until Get existed nothing in the app enqueued, so "asking slskd…" and refused rows couldn't
  appear there; the words were pinned for when they did - and since 2.0.0-player.15 they do (see
  "Sources and Get").
- **The grouping and every word are `lib/requestsView.ts`** (pure; `requests.sim.cjs`, 149 checks):
  Downloading (downloading, organizing, and queued with progress - bytes moving before the poller's
  next look), Waiting (asking slskd first, then queued: "#4 in their queue", or "starting" as the
  board says, with "N failed" in amber when the peer has already refused some files - as the old
  panel's `jobDetailText` says it, or it reads as an ordinary wait right up until it fails), Needs
  attention (refusals, then failed and cancelled: the reason in red, "Next peer · N left" from
  `alternatives_left`, "Ask again" always, "Trying next peer…"/"Asking again…" on the button tapped
  with both aria-disabled, the retry's refusal as a second red line), Done (everything
  else, sorted by `updated_at`, newest first, so the ages read in order: "In your library · 12
  minutes ago"). "try N" from `attempt`. Each section only with rows; the page draws none empty.
  - **ONE solid purple button on the screen** (STYLE.md): only the first Next peer is `primary`;
    any after it is tinted. Two failed jobs with runners-up would otherwise be two primaries.
  - **Arriving is exactly what the badge counts, by construction**: App gives TabBar
    `view.arriving.length`, the list Home draws - one list read twice (review: it was the hook's
    `activeCount`, and nothing checked which number App passed). The sim holds `view.arriving.length`
    to downloadOverlay's `activeCount` across six scenarios, and pins where the two part: a retry's
    overlay left on a job that has since finished (`reconcile` drops `retrying` only once the job is
    active or gone, and no TTL covers it), which activeCount counts for good and the view draws under
    Done - the metadata queue's lesson ("the tab badge and the queue must never count different
    things"). Home shows the first three (`ARRIVING_MAX`), and NOTHING when there are none -
    `Arriving` returns null, no heading. The sim renders Home with Navidrome unset, down and unknown
    to hold Arriving outside the gate (a text check of Home.tsx passed with it inside).
  - **An Arriving card's state word gives way before the album's name**: the brief shrinks with an
    ellipsis and the body keeps `--app-arriving-body-min`; a retry's brief is "retrying…" either
    way (it was "trying next peer…", 133px at 320, leaving "The D…").
  - **Organizing has no ✕** (nothing in slskd is left to cancel, and filing can't be stopped; the
    old row offered one). **Waiting jobs have one** although the board draws none: giving up on a
    job at #40 in a queue is the commonest cancel, and the old panel allows it.
  - **"Already in your library, nothing filed"** for `already_there`, where the board says "nothing
    downloaded": the download DID happen - its files are in slskd's folder, which a move's clean-up
    keeps because duplicates count as skipped. The other Done words: "Partly filed: <the row's
    error>", "Interrupted while filing: check the library and slskd's folder", "Not filed: <error>"
    for an ending with no outcome (a dry run, nothing that could be filed, filing that raised, no
    track filed), "Downloaded, not filed" for one with no error (organizing off: `ORGANIZE_MODE`
    'off', or `LIBRARY_PATH` or `SLSKD_DOWNLOAD_PATH` unset - `organizing_enabled()` is all three).
    Warnings amber.
- **The server** (`/download/jobs`): each row gains `updated_at` and `release_mbid` (list_jobs
  always read them; the route dropped them), `release_group_mbid` and `edition`, and `outcome`.
  - The two read out of the stored release BY SQLITE in `list_jobs`' SELECT (`json_extract`, as the
    runners-up's usernames are), never decoded in Python - the v0.9.24 cost. `edition` is
    `COALESCE(NULLIF(TRIM($.edition_label), ''), NULLIF(TRIM($.disambiguation), ''))`: a blank label
    falls through. Both behind `json_valid`, so one bad row gives nulls instead of failing the poll
    (list_jobs answers [] on any error). Measured: fifty jobs with 4.7 KB releases, 1.14ms a poll
    before and 1.25ms after, on this Mac.
  - **`outcome`** is `poller.job_outcome(status, error)`: `filed` (organized), `failed` (failed AND
    cancelled - the two retries restart), `already_there` (complete, error starting
    `f"{ALREADY_THERE}:"`), `interrupted` (complete, error == `INTERRUPTED_FILING`), `partly_filed`
    (complete, error ending `f" {FAILED_TO_ORGANIZE}"`), and null for anything still going or any
    other ending - the client shows those in the row's own words. The constants are NAMED in
    poller.py and the poller builds its messages FROM them (the all-duplicates message is
    byte-identical to before: `ALREADY_THERE` is its old prefix), so the two can't drift; a test runs
    the real `_organize_if_enabled` with a faked organizer and reads each message back as its
    outcome. Free text that merely mentions one ("the peer said: already in the store") is not it.
  - **One message changed, on this branch only**: a filing where files failed and NO TRACK landed
    now says "N file(s) failed to organize, no track was filed" (`NO_TRACK_FILED`), so it isn't read
    as partly filed. Judged by `results["tracks_organized"]` - the test the enrolment makes - not
    `organized`, which counts a cover (review: a folder left with only a cover read "Partly filed"
    with none of the album in the library; troubleshooting.md promised it showed as New). A result
    without the count is taken as all audio (`.get("tracks_organized", organized)`; execute_plan
    always gives it, test fakes don't). `test_a_folder_left_holding_only_a_cover_is_not_enrolled` -
    main's test - now reads the new words and an outcome of None. Main's message isn't wrong there -
    nothing on main reads it as an outcome - so this isn't a main fix; a merge touching those lines
    will conflict, and should keep this. A row written before it, where nothing landed, can't be
    told apart and reads as partly filed (troubleshooting.md says so).
  - `tests/test_jobs_route.py` (16) through `TestClient(start())` with a real store and a fake slskd:
    every field, the edition's order and blanks, a row with broken JSON, `list_jobs` never handing
    the release to `json.loads` (the loads are watched for a marker only the release holds), each
    outcome from status and constant, free text refused, the poller's own messages end to end, a
    queued row's position, and the runners-up still counted only for a retryable job.
- **Re-rendering**: a poll re-renders App (the hook's state lives there). Home and Requests are
  memoised apiece on what they draw; the other roots as before; Home's shelf is memoised inside
  Home, and `NOTHING_ARRIVING` keeps Home's element still while nothing is arriving. **Each tab's
  top page is memoised on `[nav, status, playingId, player.playing]`** - what AlbumPage reads of the
  player (the playing song's id, whether it plays, and `playTracks`, one function for the page's
  life). Not on `player`: usePlayer returns a new object every render, so a memo keyed on it (the
  first cut's) held for no poll, and every mounted album page re-rendered twice a second while
  Requests showed (review). `app-rules.sim.cjs` holds AlbumPage to reading only `player.track?.id`,
  `player.playing` and `player.playTracks`, so reading more there fails until the memo has it too.
  The mini player, Now Playing, its menu and Info still re-render with App - at most 2 Hz, while
  Requests shows - since app-rules pins their JSX in App as it is.
- **Covers**: `https://coverartarchive.org/release/<release_mbid>/front-250` (`jobCoverUrl`, the id
  encoded), the phone fetching it itself; `JobCover` remembers which address failed, as `Cover`
  does, so offline or no picture is the plain tile (`--dw-empty-cover` with the board's edge), and
  the next pressing is still asked. Lazy: a hidden pane fetches nothing. Pending rows have none.
- **The ✕ asks first, IN the card - never `window.confirm()`** (review). This page plays the music,
  and a blocking dialog holds its JavaScript: a song ending while it was up waited for the answer
  (the engine starts the next one from `ended`), a stream stopped being fed, and on a locked phone
  the music stopped at the end of the song - the engine's first rule broken by a cancel. The main
  page could use confirm() because it never hosted the player. Now the ✕ (by the main page's
  `confirmCancel` preference, read at the tap - which a home-screen app, own storage and no
  Settings tab, always has on; since 2.0.0-player.41 this device's own "Confirm before cancelling"
  in You, carried over once - see "Get, as the main page had it") opens a question in the card: "Cancel this download? You'll lose
  your place in this peer's queue.", **Keep it** (secondary) and **Cancel download** (secondary,
  red words - the one solid purple stays Next peer). The ✕ is `aria-expanded` with
  `aria-controls`, and a second tap on it closes the question; one card asks at a time (Requests'
  `asking`, by row key); a row whose cancel isn't `ready` any more draws no question.
  `app-rules.sim.cjs` fails on any confirm(), alert() or prompt() in app/ or player/. The docs say
  so, and configuration.md's label for the preference is fixed ("Confirm before cancelling", as the
  tab says; it read "Ask before cancelling").
- **Until deadwax first answers, a spinner** (review): the hook starts with `jobs = []` and no
  error, so a cold open on #requests (iOS reloads a tab it put aside) said "Nothing requested yet"
  for a round trip - longer with slskd slow to answer deadwax (no timeout on SlskdClient). App
  notes the first answer without touching the hook: `answered` turns true once `jobs` is no longer
  the hook's first array, or there is an error, or tracking is off, and Requests draws
  `pl-spinner` while the view is empty and nothing is known.
- **Taps answered for a screen reader** (review): busy buttons and the cancelling ✕ are
  `aria-disabled` with the tap refused in the handler, never `disabled`, which dropped the focus a
  keyboard or VoiceOver had on the button tapped. One polite, atomic live region, always in the
  page (iOS reads only a region already there), says what `changes(before, now)` found: a row under
  another heading ("Heligoland: waiting", "...: needs attention: <why>", "...: In your library ·
  just now"), a retry's refusal, a tap's answer starting ("trying next peer…", "asking again…",
  "cancelling…") - pure, pinned. A card that moved is drawn afresh in another list, so each `<li>`
  carries `data-row` and `tabIndex={-1}`, and a layout effect puts focus on the moved card when the
  focus was in it and fell to the page (only then: a deliberate tap elsewhere is left alone).
- **Clear done is the clear route**: it forgets every finished, failed and cancelled job (and the
  refused pending rows), the Needs attention ones included, exactly as "Clear finished" does. The
  label is the board's; the docs say what it clears. Disabled (`button:disabled`'s 0.4) with
  nothing to clear, rather than hidden, so the title row doesn't move.
- **The tab's badge**: `badgeText` (none at 0, "99+" past 99), drawn over the icon's corner,
  `aria-hidden`, with the button's `aria-label` "Requests, 2 arriving"; STYLE.md's purple badge laid
  over the tab bar's colour so no icon stroke shows through. **On a phone on its side it goes into
  the row**, between the icon and the label (`position: static` in the max-height block): the label
  is beside the icon there, and "12" over the corner covered the top of the R (review).
- **"See all" and the Arriving cards go to Requests' ROOT** (`router.root`, appHistory.ts; review):
  a tab tap shows a tab as it was left, so after Go to album on the Requests tab, See all showed the
  album. `root()` is the switch and then the pop-to-root, so the history is what tapping the tab
  twice makes; `routes.sim.cjs` drives it.
- **Style**: cards are `.app-card` (#24222c, 6px, inset highlight), the bar STYLE.md's sunken track
  (`--dw-bar` 6px, `--dw-radius-fill`), data monospace, tokens only (`--dw-amber-text`,
  `--dw-badge-purple-*` new in theme.css section 10; the layout's `--app-job-*`, `--app-done-row`,
  `--app-arriving-*`, `--app-tab-badge*` in app.css). Every control a tap target: the ✕ a 32px box
  in 44px (its bleed into the card's padding keeps the box where the board puts it), Next peer and
  Ask again 36px reaching 44 through `::before`, Clear done and See all text buttons 44px tall.
  **The buttons have no overflow of their own** (review): the button is its `::before`'s containing
  block, so `overflow: hidden` for the ellipsis clipped the reach back to 36px; the label is a
  `.app-job-action-label` span holding the ellipsis, as Now Playing's album line does, and the reach
  counts the button's 1px border (`+ var(--dw-hairline)`). **The pair stacks below
  `--app-job-action-min` (150px a column)**, `repeat(auto-fit, minmax(...))`: at 320px a column held
  105px of text and "Next peer · 2 left" (121px) lost its count; stacked, the row gap is twice the
  reach so the reaches don't overlap. **A row being cancelled fades its cover, title, bar and (on a
  Downloading card) who it's from**, never the words saying "cancelling…" (the whole card at 0.55
  put them at 2.7:1). `test_app_css.py` holds all of these, the bar, the opaque badge and its row
  on its side, a busy button's opacity, and the live region's hidden box.
- **Not built, on purpose**: the board's "Missing from artists you have" and "Only as MP3" (after
  step 4, per the plan); per-user requests (step 4); tapping a Done row to play its album (the id
  bridge, slices.md's S6 - built in 2.0.0-player.17, "Artists, and the two libraries joined"); Get
  (S5 - built in 2.0.0-player.15, "Sources and Get").
- **After review**: nineteen findings, each confirmed by skeptics, fixed together - the blocking
  confirm, the album-page memo that never held, "Nothing requested yet" before the first answer,
  Arriving and the badge freezing after one failed look (the app's side; the hook's is main's),
  See all landing on an album page, Waiting rows dropping "N failed", "Partly filed" for a cover
  alone, the clipped 44px reach, the badge over the label on a phone on its side, the primary
  button's count lost at 320px, taps silent to VoiceOver, the Arriving title squeezed by a long
  state word, the cancelling row's 2.7:1 words, the gate check that passed with Arriving inside it,
  the badge's unpinned wiring, the unpinned watching derivation, the drawn states unpinned at the
  component, "organizing off" naming one of its three causes, and the slice numbers above.
- **Verified**: 1878 Python tests (`test_jobs_route.py` new, nine new in `test_app_css.py`),
  pyflakes, tsc, and all 27 sims (`requests` new, 149 checks; `app-rules` and `routes` extended);
  50 mutations for the first cut, one per rule pinned, and 38 for the review, one or more per fix,
  each caught and restored byte for byte. The engine guard is empty, and the hook,
  `downloads.sim.cjs`, `player.sim.cjs` and the old downloads panel are untouched.
  **NOT verified here**: the real page (the build workaround and a check against the stubs and a
  fake slskd come after this change), and everything on the iPhone - the tab and its badge under a
  real finger (and beside the icon on its side), the ✕'s question in the home-screen app, Arriving
  coming and going, a download started elsewhere showing on coming back, VoiceOver reading the live
  region, and the Archive's covers over WireGuard.

### Search, and albums you don't have (2.0.0-player.13)

Slice 4 of the one app (`uplan/slices.md` S4, numbered .13). The boards are `Search.dc.html` and
`Request.dc.html` (its `album` tweak: Third with every pressing alike, The Slow Rush, and The Slow
Rush with the Japanese CD picked; RequestBonus merged into it). James: "One search box: library
first, then MusicBrainz; an album you don't have opens like one you do" - the canvas gives it the
SAME header as an album you have: back, centred cover, title, artist, meta line, then the Pressing
dropdown where the album page has its chips and "Get the album" where it has Play/Shuffle; "for
both, I'd like the album page to show the tracklist instead of the release list. Then there should
be a dropdown somewhere to pick which release you're viewing, with the most common as default";
and "show the bonus track differences on an album that has them".

- **The Search tab** (`app/Search.tsx`) replaced its placeholder: one box (17px, so iOS doesn't zoom
  as it is tapped; `role="search"`, `enterKeyHint="search"`, and Search on the keyboard blurs the
  field so the answers have the screen).
  - **The library half**: Navidrome's search3 through the new `/navidrome/search`
    (`searchLibrary` in player/api.ts, `SEARCH_COUNTS` 5 artists, 8 albums, 12 songs),
    `LIBRARY_SETTLE_MS` (200) after typing stops, inside the Navidrome gate. The **Top result** is an
    artist whose folded name IS what was typed (`topArtist`), drawn as a plain row - NOT a link:
    there is no artist page until S6, and a row going somewhere else would be a lie. (Since
    2.0.0-player.17 it opens the artist's page, and the other artists found are rows that do.) Album rows open
    the album (prefetching on pointerdown, as a tile does); song rows, below.
  - **A song plays within its album once that album is in hand**: as the answer lands, the first
    `SONG_ALBUMS_PREFETCHED` (5) distinct albums of the songs (`albumsToPrefetch`) go through the
    album page's own `prefetchAlbum`, which now RETURNS its held promise (callers that ignored the
    void are unchanged; the album page still takes the ask once), and each landing album is kept in
    `ready` - only for the newest library search. **Asked with `keep`** (review): a tile's or an
    album row's press shares the one ask, and a press that turned into a scroll (`dropPrefetch`)
    aborted it - so a scroll starting on the Dummy row while Search's ask of Dummy was out left
    every Dummy song opening the album instead of playing, with nothing asking again. A kept
    entry (`Prefetched.kept`, set by whichever asked with `keep`, first or second) is never called
    off; a tile's own ask still is. `search.sim.cjs` runs the real api.ts for it. The tap: `rememberPlayed(album)` then
    `actions.playTracks(album.song.map(toQueueTrack), at)`, from `ActionsContext`, in the click,
    nothing awaited - the gesture rule; `app/Search.tsx: playTracks` is the one new file on
    `app-rules.sim.cjs`'s allowlist. Not in hand: the tap opens the album, where Play is. A ▶ on the
    row says which it will do.
  - **The MusicBrainz half, "Not in your library yet" / "From MusicBrainz"**: `lib/searchQuery.ts`
    (pure, `searchQuery.sim.cjs`) reads the box against the library's artist names (/library/owned's
    album artists plus the library half's artists, folded by owned's `foldName`): a leading or
    trailing artist is `fieldedAlbumQuery` (`releasegroup:"rest" AND (artist:"A" OR
    artistname:"A")`, the longest name first, the start before the end, separators like " - "
    dropped), an artist alone `artist:"A"`, `va`/"various artists" Various Artists, anything else
    the words as typed. `withTypeFilter` ALWAYS brackets the query before a type filter
    (`typeFilter` builds main.js's clauses; the sim reads main.js's NOISY_SECONDARY_TYPES to keep the
    lists one). **The app sends no type filter**: the board draws none, and a filter silently on (the
    main page's `searchStudioOnly` preference) is the search that quietly returns less. Asked on
    Enter, or `MUSICBRAINZ_SETTLE_MS` (700) after typing stops with `MUSICBRAINZ_MIN_CHARS` (3)
    or more, as `fully_search?releases=false&limit=12` (`MUSICBRAINZ_LIMIT`); `asked`/`libraryAsked`
    refs stop Enter and the pause after it asking twice. A fielded read that finds nothing is asked
    again as free text (the metadata editor's fallback: an artist's name starting a title).
    `notInLibrary` drops a group the library holds BY GROUP ID only - a "maybe" (an untagged folder of
    that name) stays on offer. **Worked out ONCE, as the answer is drawn** (`shown` in the state,
    review): the answer waits up to `OWNED_WAIT_MS` (1500) for the library's, asked beside it
    (`refreshOwned()` resolves once an ask made after it has landed), so a held album is left out
    BEFORE drawing; an answer landing later never takes a row away - the rows under the finger moved
    up and the tap opened another album - and marks it in place instead (`groupLine(group, held)`:
    "Album · 2008 · in your library"). **A box cut back below 3 characters** to anything not asked
    (`musicBrainzOnTyping`, pure: clear | settle | drop | keep) supersedes the MusicBrainz search,
    clears `asked` (or 'por' -> 'po' -> 'por' would keep an idle half saying nothing) and goes back
    to idle, which says how to ask: before, the longer text's albums stayed under a box reading
    "po" for good, and a search still out drew there. The box takes `maxLength` `SEARCH_MAX_CHARS`
    (200, the route's bound: a longer paste was a 422 shown as a URL, with a Try again that could
    never work). States: the sweep and "Asking MusicBrainz…"; MusicBrainzUnavailable ->
    "MusicBrainz isn't answering just now - it often goes away for a few minutes." with Try again;
    "Nothing on MusicBrainz for …"; "Everything MusicBrainz found is in your library already".
    The library half's failure is drawn the same way (`.app-search-problem`, a full-width 44px
    `.app-button` Try again; it was a bare 20px text button beside MusicBrainz's).
  - **Only the newest answer draws** in each half (`libraryRequests`, `musicRequests`, latestOnly;
    app-rules holds both, and the prefetch landing too). `/fully_search` still runs to its end on
    the server when the page gives up (no `unless_abandoned` there), which is why the page paces it.
- **`/library/owned` in the app** (`app/useOwned.ts`, a module store over `owned()` in
  api/library.ts and `lib/owned.ts`): one request in flight and one "ask again", so the newest
  answer lands last; `refreshOwned()` returns a promise resolved once an ask made AFTER it has
  landed (answered or not - what Search waits on), and `ownedNow()` is the store's answer for code
  that has awaited. **Never asked as the app starts** - Search is mounted, hidden, from the start,
  and the first /owned after a restart walks the whole library (`library_is_behind`); it is asked
  when Search first SHOWS (`searchSeen` in App, as You's `youSeen`), when an album page opens,
  beside each MusicBrainz search (a 304 when nothing changed), and on a filing once anything has
  asked (`wanted`) - even an ask that failed (review: `held || asking` never asked again after a
  failed first ask). `search.sim.cjs` drives the store itself against a faked /library/owned (one
  ask out, ask again, what a refresh waits for, filing before and after a failed ask); app-rules
  holds where it is asked from (Search's `shown`, App's `searchSeen`, the page's `useOwned(true)`,
  beside each search) - the first cut claimed app-rules pinned it all, and it pinned neither
  `again` nor the ask beside a search. A failed ask keeps the last answer, or none: nothing is
  dropped from the MusicBrainz half without an answer, and the album page says neither "in" nor
  "not in your library".
- **The album you don't have** (`app/ReleaseGroupPage.tsx`, at `#/<tab>/group/<rgid>?release=<mbid>`):
  `pl-album-page`'s header (back, `ArchiveCover` - the Cover Art Archive's front for the pressing
  shown, then the group's, remembering which addresses failed as `Cover` does - title, artist as a
  plain `pl-hero-artist` like the album page's (since 2.0.0-player.17 both are links to the artist's
  page - here when one artist with an MBID is credited, drawn plain otherwise), and `metaLine`: "2008 · Album · not in your
  library", "in your library" when the group is held by its id OR any pressing's (`releaseIds`: an
  .m4a deadwax filed has a release id and no group id - Easy MP4 has no key for it - and the main
  page's card counts it through `registerGroupReleases`), nothing about the library until it has
  answered (`held` null: the first cut said "not in your library" for an album you have while the
  first /owned walked the library), and nothing at all on a cold link until something is known).
  The id in the address goes through `groupMbid()` (lowercased, MusicBrainz's pattern): anything
  else is `NOT_AN_ALBUM_LINK`, "That isn't a link to an album on MusicBrainz.", with no Try again
  and nothing asked - it was a 422 drawn as a URL with a Try again that could never work. `app-rg-actions` holds the `PressingPicker` where the album page has Play
  and Shuffle; **Get was left out entirely until S5** (an unusable button is worse than none), the
  column being where it goes under the picker - so the page had no solid purple button (app-rules
  pinned that; since 2.0.0-player.15 it pins Get as the ONE - see "Sources and Get"). Outside the
  Navidrome gate (App's `pageView` branches on `page.kind`).
  - Its pressings: NEW `GET /search_musicbrainz/release_group?release_group_mbid=` (an MBID or a
    422) = `get_releases(with_tracks=True)` - every pressing's tracklist, which the base and the
    differences need - cached by ResponseCache like every success. `getReleaseGroup` in
    api/musicbrainz.ts, through latestOnly; a `problem` (MusicBrainz failed, before or part way) is
    drawn as the problem with Try again, never as a short list. A module `Map` keeps the last
    `PRESSINGS_KEPT` (20) complete answers for the session, so Back (the page re-mounts: only a
    tab's top page is mounted) and a tab switch ask nothing; only complete answers - a broken-off
    list is never kept, so Try again and the page opened again ask afresh (group.sim). A cold link
    has no preview, so the header comes from the group the pressings carry (`release-group`,
    review: `/release_group` asks `inc=...+release-groups` - `get_releases(with_group=True)`, no
    extra request - so a reload or a link says "Album" and the group's own title), else from the
    pressings themselves (`pageHeader`: the chosen one's title and credit, the earliest year -
    MusicBrainz's first-release-date).
  - **`lib/pressings.ts`** (pure, `pressings.sim.cjs` on the real fixtures): `pressingsView` - the
    default is `representativeRelease` (the most common tracklist, Official, CD/Digital, no
    disambiguation, earliest, the id: the pressing a card's Find downloads as, and the one S5's Get
    will get); a pressing's kind is `usual` (chooseBase's titles in order, with nothing added, left
    out, renamed or another version - a length a few seconds off is not a difference, and never
    marked, where the main page shows an "N lengths" chip), `differs` or `none` (no tracks).
    **Every pressing is compared with the usual titles at the DEFAULT pressing's lengths**
    (`reference`, review): chooseBase lends the lengths of whichever pressing holding the usual
    titles MusicBrainz listed FIRST, so with the single mix first the default read "another version
    of Borderline" against itself and every other pressing differed. The default always holds the
    usual titles (representativeRelease picks from chooseBase's pool), so no order changes a word -
    pressings.sim puts every real pressing first in turn. Left-out lengths and "The usual version
    is …" are the default's: Dummy's It's a Fire is 3:49 here, where the main page's base row says
    3:48. The dropdown shows the default, ONE usual pressing of each other format,
    the chosen one if it was folded, every one that differs, then folds the rest of the usual ones
    under "N more pressings with the usual tracklist" - which EXPANDS (decisions.md left that open;
    a pressing you can't reach can't be got). Labels: formats in runs ('2×12" Vinyl', "Digital" for
    Digital Media), year, country (XW left out, XE "Europe"), then the disambiguation else the first
    label. Notes: "The usual tracklist · shared by 9 of 10 pressings" ("all N"), "Same tracklist as
    the usual one", "+1 bonus track: Patience", "Without It’s a Fire", "1 other version: Borderline,
    4:34", "N tracks renamed", "No tracklist on MusicBrainz". `summaryLine`: the default's "The usual
    tracklist, shared by …", "Same tracklist as the usual one", amber "This pressing adds 1 track"
    (leaves out / renames / has another version of, joined), "The only pressing MusicBrainz lists".
    `trackRows`: the pressing's own titles and lengths, numbered per disc, a Bonus mark ("Only on
    this pressing"), Other version ("The usual version is 3:58"), Renamed ('Usually "…"');
    `leftOut` lists what it leaves out after the list. Disc headings by `lib/discTitles.ts`'s rule
    (more than one disc, or any titled): "Disc 2 · Unreleased Tracks" from the medium's title.
  - **The pick is the address**: `onPick(group, release | null)` -> App's `pickPressing` ->
    `router.update` (appHistory.ts) -> `replaceTop` (appRoutes.ts) REPLACES the entry, so a reload or
    a link shows the same pressing and back leaves the page in one step; the default takes
    `?release=` out. `Page.release` is in the address but NOT the page's identity (`samePage` is kind
    and id) and not where its scroll is kept (`scrollKey`, which App now uses for every saved scroll,
    so a pick never jumps the page to the top). Back and forward land on the pressing their entry
    names (`followRoute` and `forwardTo` go through `replaceTop`). `routes.sim.cjs` drives it end to
    end.
  - **`app/PressingPicker.tsx`**, a listbox: the button (`aria-haspopup="listbox"`, `aria-expanded`,
    `aria-controls` an id of its own - a page stays mounted on every tab it was opened on), options
    `role="option"` with `aria-selected`, opening focuses the chosen one, arrows/Home/End move.
    Escape and a pick close it with focus back on the button; a tap outside (`useDismiss`) or Tab
    out just closes it, focus left where it went. The fold is a button OUTSIDE the listbox (only
    options belong in one), and expanding moves focus to the first pressing it revealed.
    **Focus going NOWHERE is not focus leaving** (review): WebKit - Safari, every iPhone browser -
    focuses no tapped button without a tabindex, so a press on "N more" or on the Pressing button
    blurred the focused option with no relatedTarget, the focusout closed the list and Preact hid it
    before the click: "N more" could never expand on the iPhone, and the Pressing button closed
    the list on its press and reopened it on its click (reproduced in a WKWebView). A focusout
    with no relatedTarget is ignored (a tap outside is useDismiss's), and the fold takes
    `tabIndex={-1}` like the options (WebKit focuses those since Safari 17), so a tap on it keeps
    focus inside. Chromium blurs a removed focused element with no relatedTarget too - the fold
    going as it expands. **Opening brings the list into view** (review): it opens downward, and at
    375x667 with something playing about 20px of it showed above the mini player, the chosen option
    focused out of sight (`preventScroll`). It is capped to the band between the page's bars
    (`--app-picker-band`, `-mini` with the mini player: 100dvh less the scroll-padding), the chosen
    option is scrolled into the list's own view, then the list into the page's
    (`scrollIntoView({block: 'nearest'})`, which honours html's scroll-padding). The list is a
    popover that scrolls itself (`overflow-x: hidden` - the overflow gotcha), under the album page's
    sticky bar (z 4 < 5); the fold is drawn in the accent as the app's text buttons are (it was
    tertiary grey, 3.6:1 at 12px). `group.sim.cjs` renders the page and the picker with the
    fake-Preact harness.
- **Two copies of tracklistDiff and owned, held to one answer.** The Docker UI stage copies only
  `ui/`, so the app can't import `interface/scripts/*.mjs`: `lib/tracklistDiff.ts` and
  `lib/owned.ts` are PORTS (same functions, same thresholds, same answers), and the `.mjs` stay for
  the main page until it retires. `tracklist.sim.cjs` and `owned.sim.cjs` run BOTH copies against
  shared fixtures in `tests/fixtures/pressings/`: The Slow Rush, Dummy and Third as MusicBrainz
  answered on 2026-09-30 (`/release?release-group=…&inc=media+recordings+labels+artist-credits`,
  trimmed to the fields read), each with what the `.mjs` answered recorded beside it (the base, the
  representative, every pressing's diff and chips), the Experience edition of Wish You Were Here
  for medium titles, and `owned.json`'s library and cases; tracklist also diffs every pair of real
  pressings through both copies (789 pairs), and holds the two to the same base and pressing with
  every real pressing put first in turn (47 orders), and on the two rules the real groups never
  test, in the hand-made suite both copies run: a tie for the most common tracklist goes to the one
  given first, and a CD with a disambiguation beats a plain vinyl (review: a drift in either passed
  every sim). A change to one copy that the other doesn't share fails by name. A Python port, if a native client ever wants pressings from the server, is pinned
  by the same files. Real data corrected the board in two places: Third has 17 pressings, 13 alike
  (not 4), and the Japanese CD's "Patience" is 4:53.
- **The server**:
  - `GET /deadwax/navidrome/search` (search3): declared `q` (at most 200 characters, empty allowed -
    Navidrome answers an empty search with everything, for S6's Songs), `artistCount`/
    `albumCount` (0-50), `songCount` (0-500), offsets (0+), defaults 20; answers `{artists, albums,
    songs}` as Navidrome sent them. `test_there_is_no_general_proxy` (and the turntable test's copy
    of the list) edited on purpose. `tests/test_navidrome_search.py` through `start()`: what reaches
    search3, a forged login, folder, format or client name never passed on, an encoded `&u=` kept
    inside the query, every bound a 422 with Navidrome asked nothing, the bounds themselves allowed.
  - **`client_for(request)`** (navidrome_endpoint.py): the seam for step 6's per-user Navidrome
    logins - every route in routes/navidrome.py and the turntable's internal getAlbum
    (`_navidrome_release(album, client)`) ask through it, so step 6 changes its body and no route.
    With logins off it returns the one shared client (the settings route still drops that one on a
    URL change). NOT through it, on purpose: the stream cache's make and the album context
    (player_cache.py, album_context.py) - one make serves every phone that asks, so step 6 must check
    a user's access at the route before handing them the cached answer - and the apply's
    getScanStatus, a question about the server. The test records every route's call.
  - `/search_musicbrainz/releases` passes `problem` through (it dropped it, so a broken-off list
    read as the album's pressings); `/release_group` also asks each pressing's group
    (`with_group`, `inc=...+release-groups`, its own cache key; `/releases` doesn't);
    `tests/test_musicbrainz_routes.py` runs a real MusicBrainzClient over a counting fake through
    `start()`: problem passed on, with_tracks and release-groups asked, paging, the cache (a second
    look asks nothing), a failure never cached (Try again asks), a part-way failure, and the MBID
    pattern (anchored both ends; uppercase, a suffix, a prefix, `&inc=` refused).
- **Style**: tokens only - `--dw-field`, `--dw-field-icon`, `--dw-popover*`, `--dw-selected-row`,
  STYLE.md's green and amber badges and row tints (`--dw-badge-green-*`, `--dw-badge-amber-*`,
  `--dw-tint-*`) new in theme.css section 10; the layout's `--app-search-*`, `--app-field*`,
  `--app-result*`, `--app-sweep-*`, `--app-picker*`, `--app-rg-*` in app.css. The page's classes are
  `app-rg-*` (`.app-group` was already the grouped list). The loading sweep (`.app-sweep`, STYLE's
  sunken track with a part of the purple fill going along it) stops for reduced motion. A marked
  row's tint reaches `--app-rg-mark-bleed` past the column with matching padding, so its number and
  length stay in line. `test_app_css.py` holds the field's 16px floor, the popover (scrolls itself,
  under the bar, no display of its own so `hidden` hides it, never taller than the band between the
  page's bars, mini player or not), the fold's accent, tap targets, ellipses, the tint and the
  sweep.
- **Not built, on purpose**: Get on the page and Get chips on rows (S5: an unusable button is worse
  than none - both came in 2.0.0-player.15, "Sources and Get"); artist pages and the top result as a link (S6); a held MusicBrainz group opening the
  album you have (S6's id bridge) - both built in 2.0.0-player.17; `#/search?q=` in the address (the root stays mounted, so the box
  keeps its text across tabs; a reload empties it); a visible type filter (none on the board, and
  never silently on); trimming `/release_group`'s payload on the server (the API keeps
  MusicBrainz's raw data, gzipped; a group of hundreds of pressings is several requests and a
  large answer, kept for the session).
- **After review**: twenty-one findings (two pairs the same), each confirmed by skeptics, fixed
  together, each with a test that fails without it: a scroll calling off Search's own album ask
  (`keep`); the pressing list closing under a tap in WebKit, and the Pressing button unable to close
  it (focus going nowhere); the page read backwards when MusicBrainz listed a single mix first (the
  default's lengths); the MusicBrainz half keeping a longer text's albums under a shorter box; a 422
  drawn as a URL (`maxLength`, `groupMbid`); a cold link without its kind, and "not in your library"
  before the library answered; the list opening under the mini player with its chosen option out of
  sight; rows vanishing from under a finger as the library answered; the library half's 20px Try
  again; the fold at 3.6:1; an .m4a deadwax filed called "not in your library" on its own page; the
  two tracklistDiff copies free to pick different pressings on a tie or a disambiguated CD; Search's
  and useOwned's wiring unpinned (and a filing never asking again after a failed first ask); a
  broken-off list free to be cached; `owned()` stealing `newImports()`'s doc comment; and five in the
  docs (troubleshooting's album-page wording, this file's route model and picker focus, "always
  agree" with the main page, and the m4a advice). `search.sim.cjs` is new for them.
- **Verified**: 1922 Python tests (44 new: `test_navidrome_search.py` 21, `test_musicbrainz_routes.py`
  15, eight in `test_app_css.py`), pyflakes, tsc, and all 31 sims (`searchQuery` 47 checks, `pressings`
  58, `group` 41, `search` 47 new; `tracklist` 94 and `owned` 49 on both copies; `routes` 140 and
  `app-rules` 95 extended); 78 mutations, one per rule pinned, each caught and restored byte for byte
  - four first got past (the MBID pattern's start anchor, the rename window, a group-only folder
  named as a guess, a stray trailing separator) and gained the tests that catch them - and after
  the review 38 more, one or more per fix, all caught (two first failed only to compile, and were
  made type-valid). The engine guard is empty and `player.sim.cjs` untouched.
  **NOT verified here**: the real page (the build workaround and a check against the stubs come
  after this change); search3 on a real Navidrome 0.64.2 (what it finds for "portishead third", an
  empty query); MusicBrainz live from the phone; and everything on the iPhone - a Search row's tap
  starting its album, the pressing list scrolling under a finger, the keyboard's Search key, and
  the Archive's covers over WireGuard.

### Sources and Get (2.0.0-player.15)

Slice 5 of the one app (`uplan/slices.md` S5, numbered .15 because the turntable took .11 and .14).
The boards are `Sources.dc.html` (the sheet and its cards, its tweaks the searching and failure
states), `Request.dc.html` (Get's place on the album you don't have), `Search.dc.html` (the rows'
Get chips), `Requests.dc.html` (where a Get lands) and `You.dc.html` ("Getting albums"). James
(2026-09-29): "Get the album" shows the SOURCES by default, picking one automatically is a setting,
OFF - "I don't think I can reliably trust automatically grabbing from the correct source"; sources as
CARDS, not a comparison table, with speed no longer buried; the pressing dropdown decides what Get
and the sources are for; "Get the album" is the screen's ONE solid purple button.

- **ONE payload builder: `ui/src/lib/releasePayload.ts`.** `buildDownloadRelease(group, release |
  null)` -> `{release, label}`: `groupContext(group)` (createReleaseGroupElement's context: the
  credit as credited, the current names, the ids, the group's title, its first-release year),
  `releasePayload(release, context)` (a pressing - the row Find's, and the card's), `groupFallback`
  (the album as a whole: no tracklist, no release id, so nothing is checked as held) and
  `downloadLabel` (the panel's heading). `ui/src/main.tsx` puts it on the bridge
  (`buildDownloadRelease`); main.js's two Find buttons call it through one helper (`findRelease`,
  with the raw release group riding in `releaseGroupContext.group`) and its own two builders -
  `buildExpectedFromRelease`, `buildExpectedFromReleaseGroup` - and `realYear` are DELETED, as is
  credits.mjs's `isVideoTrack` twin (release.ts's is the one rule; credits.sim asks it alone and
  checks credits.mjs keeps no copy). **The rule is now "anything added to a download's payload goes
  in releasePayload.ts"** - the old "add it to BOTH builders, and click both buttons" is gone with
  the second builder. It keeps main.js's quirks on purpose, since the main page still sends what it
  builds: "N/A" for a credit naming nobody (a track's empty credit too), `||` for the country (an
  empty ISO code falls through), a year four digits or null, the album's own year from the group.
  main.js's `EDITION_KEYWORDS` now only draws the grid's edition chips and facet: a download's
  `edition_tags` come from release.ts's copy (the three lists still stay in step).
  - **Held to the old page's own output**: `ui/test/payload.sim.cjs` deep-equals the builder against
    `tests/fixtures/payloads/find-buttons.json` - what main.js's Find buttons handed `openCandidates`
    at 2.0.0-player.14, captured in headless Brave against live MusicBrainz (the orchestrator's
    capture): Dummy's card and its GB CD row, the Experience edition row (two disc titles, 1975 vs
    2011), Donda's card (credited Kanye West, filed under Ye, DELUXE) and BULLY's, an undated
    bootleg (year and original_year null), a CD+DVD (20 tracks video) and an instrumental (tagged
    INSTRUMENTAL) - all eight bodies and labels; plus the quirks, the album-as-a-whole fallback, and
    that main.js has no builder of its own. **The undated case's inputs were wrong in the capture**:
    the card's Find fetched /releases, but the capture read its answers before its own fetch wrapper
    had recorded that one and fell back to the search's best-match-releases - another group's
    pressing (Live Weisen 1998). Its `pressings` were replaced with the group's one release as
    MusicBrainz answers it (fetched 2026-10-02, trimmed like the rest, `pressings_note` says so);
    `expected` and `label` - the old page's output - are untouched, and every other case is
    byte-identical to the capture. The orchestrator re-captures the changed old page and diffs it
    with the same file.
  - The type `DownloadRelease` (api/types.ts) is what `FindCandidatesRequest` extends and
    `EnqueueRequest.release` is: every field one the server declares, no index signature left.
- **Get, in two places, both in Search's tab.** "Get the album" on the album you don't have
  (`ReleaseGroupPage.tsx`): under the picker, in the space .13 reserved, the page's one solid purple
  button (`app-rg-get`, full width, the board's download icon `GetIcon` in player/icons.tsx); shown
  only once a pressing is chosen, and it gets THE CHOSEN PRESSING - from `answer.releases` (the
  page reads them through tracklistDiff's types), built with `getGroup()` (lib/pressings.ts: the
  group Search handed over, else the pressings' `release-group`, the chosen pressing's credit
  standing in for a bare group's, and with no group at all its title and the earliest date). And a
  **Get chip** on each "Not in your library yet" row (`Search.tsx`, the row now a `<li
  class="app-result-row">` holding the row's button and the chip - no button in a button): the
  usual pressing (`usualPressing` = representativeRelease) of `/release_group`'s pressings, through
  its own latestOnly (`getRequests`; "Get…" and aria-busy meanwhile), from the session's lists when
  the page or a chip already has them (`app/pressingLists.ts` - the album page's Map, moved to a
  module so both share it; still only complete answers, PRESSINGS_KEPT 20). MusicBrainz failing,
  or breaking the list off, is the album as a whole (`buildDownloadRelease(group, null)`), as the
  main page's card falls back, and the sheet's subtitle says "… · the album as a whole". A row the
  library turned out to hold has no chip. Both take their opener in the tap (`takeOpener`). A
  chip's lookup is called off (`standDown`: superseded, the chip back to "Get") when the box changes
  or Search's root stops being what shows - App's `active` prop, `searchActive` = the Search tab,
  no page on its stack, neither sheet open - so its late answer never opens the sheet over Now
  Playing, another tab or a page (review).
- **What is already here, under Get**: NEW `POST /download/store_state` = `_store_state(request,
  body)` with the Find's body - what find_candidates answers before deciding whether to search
  (held, downloading, downloading_part, other_pressings) and nothing more: no Soulseek search. Same
  pressing, same judgement as a Get. The page asks it for the chosen pressing through its own
  latestOnly (`stateRequests`), again as another is chosen, as an album is filed (`onAlbumsFiled`)
  and as the page shows again (`shown`, from App: its tab current, the Sources sheet closed, the app
  in front - so after a Get it says "Already downloading", and a download cancelled in Requests
  stops being said; out of view it asks nothing). Asked again for the SAME pressing the last
  answer stays until the new one lands (`known` never shows another pressing's), and it draws UNDER
  "Get the album" - above it, an answer landing late moved Get under a finger reaching for it (both
  review) - in a polite live region (`app-rg-store`, taking no room when empty but still drawn -
  VoiceOver reads a region only once it is already there) with
  `StoreState.tsx`: lib/candidates.ts's `storeStatus` (now taking where a download is cancelled:
  'Downloads' on the main page, 'Requests' in the app) and `storeNotes`, as a card and notes - the
  step-2 store's boxes in the app's look; paths break anywhere. `tests/test_store_state.py` (9)
  through start() with real FLACs: held, part held (fills_gaps), downloading with done_files, part
  downloading, another pressing, nothing, no release id, a store that won't open, and the
  same-origin guard - the fake slskd records every search, and every case asserts none.
- **The Sources sheet** (`app/Sources.tsx`, z 25 `--app-z-sources`, a sheet by `useSheet` with its
  own lock `app-sources-open`, focus in to Cancel and back to the Get; App holds it - `sourcesOpen`,
  `getting` (the last Get, kept as it slides away), a new `key` per Get so the same album got twice
  searches twice - and the page behind is inert while it shows: `covered = sheetOpen ||
  sourcesOpen` (since 2.0.0-player.19 `!desktop && (...)`: a desktop's side panel is not modal - see
  "The desktop frame"). It is never open with Now Playing: each covers what would open the other, a chip's
  late lookup is called off before it can open (above), and `openSources` refuses while Now Playing
  is open - `nowPlayingOpen`, a ref set in openSheet's tap and every render - the backstop). Cancel
  and "Choose a source" on one row (`1fr auto 1fr`, the title centred and one line at 320px), the
  subtitle ("Third · CD · 2008 · GB · Island") under them across the head's whole width, wrapping -
  its distinguishing part comes last, and the old ellipsis in an 80px-sided column took exactly that
  at 390, 375 and 320 (review); the chips; one scroller (`touch-action: pan-y`, as Info's).
  - **The search is `hooks/useCandidateSearch.ts`** - CandidatesPanel's orchestration repeated (the
    old panel is NOT refactored, so the main page and merges from main stay safe; the copy goes at
    retirement): one `CandidateSearch` value only the newest search becomes (latestOnly, the
    superseded one called off - and closing the sheet calls it off, which stops it in slskd: Cancel,
    the backdrop and Escape do it IN the gesture, `onClose` = `state.stop()` then the prop, as the
    old panel's close does; the `[open]` effect stays as the backstop. Left to the effect alone, an
    answer landing in the frame before it ran could still pick and queue a source after Cancel);
    each candidate downloads as the release IT was searched for; only an edited query overrides
    (queryOverride); up to ten runners-up as SHOWN; the format preference read per search (You's
    Format, kept on deadwax, since 2.0.0-player.41 - see "Get, as the main page had it"). The app
    has no format chips, so "clear the format chips per search" has nothing to clear - its chips are
    a floor's, a choice that holds. One download per search (`askedFor`): a second tap before the
    sheet goes asks nothing.
  - **A card** (`SourceCard.tsx`, words in lib/candidates.ts): the score (green from
    AUTO_GRAB_MIN_SCORE's 75 - scoreClass's good band, the one a pick needs - where the board's
    example data used 85; amber under), the folder (ellipsis), "from <peer>" ("· 2 disc folders"
    for a joined set), Get (`is-primary` on the BEST MATCH only - the top of the chips' list by
    score, `sortCandidates(passing, 'score')[0]`, wherever the sort puts its card - `is-tinted` on
    the rest, 32px reaching 44; named "Get <folder> from <peer>", since one peer's FLAC and MP3
    folders were two "Get from bob"s in VoiceOver's rotor - review). **Speed leads** (`speedFact`): `measured` - peer_speed's figure, green, "what you
    got from them", `~` for an average of several (measuredSpeed's hedge) - else `advertised`, the
    peer's own `upload_speed`, "their own average" (never presented as the download speed - the
    rule from "The peer's advertised speed is not your download speed"), else "Unknown", "no speed
    reported yet"; the bar is the speed / `SPEED_BAR_FULL` (3 MiB/s, formatSpeed's units), capped
    at 100. Then Tracks ("11 of 11" - against `audio_expected`, held = audio less missing - amber when tracks are missing), Quality (`qualityText`: "FLAC
    16/44.1", "FLAC 24-bit", "MP3 320k", "MP3 VBR 245k" - only what was reported), Size, Starts
    (`startsFact`: "now" with a free slot, "3 ahead" in their queue, "next" with no slot and nobody
    ahead - the board has only the first two; amber unless now). The amber **Missing** line
    (`missingLine`): 'Missing “Threads”', up to three named, "and N more".
  - **`missing_tracks` on a candidate** (server): `matching.missing_tracks(expected, mapping)`, in
    `score_candidate` where the pairing is - `track_mapping` is dropped before the page - every
    unpaired track in tracklist order as {position, disc, title}; a VIDEO track is never missing
    from a folder of audio, and a release that is all video keeps every track (audio_tracks'
    rule - `matching.audio_tracks`, shared). `_serialize_candidate` sends the first `MISSING_NAMED`
    (5), `missing_count` and `audio_expected` (how many tracks are audio). The card's Tracks counts
    against `audio_expected` (`tracksText`: audio less missing, of audio), so a CD+DVD shared whole
    is "14 of 14" agreeing with the missing line, not "14 of 34" with nothing missing (review); an
    answer without it counts matched/expected as the old panel does. The SCORE still counts every
    track (title_match, track_count - older than this slice; changing it re-ranks everything), so a
    CD+DVD folder still scores low. `tests/test_candidate_missing_tracks.py` (12).
  - **The chips**: Lossless - a new `lossless` flag on lib/candidates.ts's `CandidateFilters`
    (optional, so the main panel builds its filters as before): every file lossless by format, and
    a folder whose formats nobody could tell never passes - 24-bit (minBitDepth 24), Free slot, and
    the sort (a chip holding the platform's own `<select>`, invisible over it, 17px so iOS doesn't
    zoom; the chip shows the choice). They START as the quality floor (`floorFilters`) on every
    Get; a **320 kbps** chip, which the board hasn't, is drawn only while the floor is 320 (or it
    is on), so a floor is never a filter on out of sight. The settings landing after the sheet
    opened re-seed the chips unless they were tapped (`touched`).
  - **States**: asking (the sweep, `searchingLine`: 'Asking Soulseek for “Third” by Portishead…', or
    'by Kanye West or Ye…' - the names search_names asks under, "N/A" left out); slskd unable to
    search (`error`: the find route's 502 detail, i.e. the 409 explanation the server already
    builds, in amber, with Try again); nothing found (`queriesText`, the query to edit and
    Re-search, a `<form>` so Enter works); none passing the chips (Clear filters, shown only with
    some pressed); the store's box where the cards would be (held whole, downloading whole - the
    server searched nothing) and its notes above them; the cards and `searchedLine` ("Searched
    Soulseek for “Portishead Third” · 41 folders, 4 match your filters"). **A 409 from the enqueue**
    ("already downloading from bob", a peer offline) is the pending row in Requests reading
    "refused" with the server's words - the sheet has gone by then; that is .12's refused row.
  - **Get on a card**: `state.download(candidate, shown)` - `requestDownload` called in the tap,
    nothing awaited before it, so the downloads hook (App's one, which registers
    `handleDownloadRequests`) lays the pending row down in that call - then `onQueued`: App's
    `gotten` closes the sheet with its opener cleared (focus has nowhere to land) and
    `router.root('requests')`. Requests' root showing makes the hook poll fast (`watching`), so
    `useDownloadJobs(watching === 'requests' || stalled)` needed no change for Sources.
- **"When I tap Get" and the quality floor** (You > Getting albums, FIRST, as the board has it;
  `GettingChoices.tsx`: two radio groups like LookChoice - the board's disclosure rows made the list
  itself, one tap not two; nothing checked or choosable until deadwax answers). Stored PER USER ON
  THE SERVER: a `user_prefs(user, key, value, updated_at, PK(user, key))` table in store.py (only keys
  chosen have rows, plus routes/me.py's `SEEDED` (`_seeded`), which EVERY save writes, an empty one
  too - the answer's `seeded`, "something was saved for this user"; an old database gains the table
  through SCHEMA's CREATE IF NOT EXISTS) and `GET`/`PUT
  /deadwax/me/preferences` in routes/me.py, through `current_user` (a dependency, as `/me`): the
  allowlist `PREFERENCES` - `get_mode` sources|pick, `quality_floor` any|320|lossless|24bit, first
  the default - a pydantic model with `extra="forbid"` and Literals (anything else a 422, nothing
  written), a stored value no longer allowed read as the default, `stored` (which are set),
  `seeded` and `can_save`; a PUT is a write, so the same-origin guard refuses another site's. 503
  for an unwritable database, or a write it refused. `tests/test_me_prefs.py` (22) incl. a cross-origin PUT
  refused through start(), per user, and the three lists (here, the model, lib/getSettings.ts) read
  as one. The client store `app/useGetSettings.ts` (a module, as useOwned): asked when Search first
  shows, each time You's tab is opened (its new `current` prop) and on Check again, and each time
  the sheet opens (since 2.0.0-player.41 before every search it starts - see "Get, as the main page
  had it"), and since 2.0.0-player.49 each time an album page shows (its store line judges somebody
  else's download against the floor - notes/logins.md "Downloads per person") - never at start-up
  from a tab mounted hidden - an answer in hand ASKED AGAIN and standing meanwhile (a
  change made on another device arrives in a home-screen app left open for days - review); the
  defaults until the first answer (a Get then shows the sources: the safe way round); SEEDED ONCE -
  a read with `seeded` false and `can_save` PUTs `seedFromPreferences(readPreferences())`, which is
  ONLY what differs from the defaults (the main page's candidate floors in this browser: bit depth
  24 -> 24-bit, 16 -> Lossless, bitrate 320 -> 320 kbps, anything less `{}`; get_mode never -
  auto-grab is not carried over), saved even when empty since the save is the mark; never a default
  stored as if chosen (review: seeding both made a later change of default reach nobody). What
  shows is `confirmed` (the server's last word) with `pending` choices laid over it in order, and
  every read and save goes `inTurn` - each sent once the one before has answered - so answers come
  back in the order asked: an older choice's answer can't put a newer one back, a re-ask can't undo
  a choice being saved, a refused choice goes back to the server's word keeping later ones on top
  ("Not saved: …", in a live region always in You), and deadwax commits the choices in the order
  made (review: the arrow keys sent overlapping PUTs). The main page keeps its own copies
  (configuration.md says so).
- **Auto-pick** ("Pick the best source for me"): in the hook, read as the answer lands
  (`pickingNow`: getSettingsNow() and the chips then), only on a FRESH Get (`start`; Try again after
  a failed search is that Get again, so also fresh) - never a Re-search - and never when
  `autoPickBlocked(result)` (the answer's own store fields: downloading, held complete, a part
  downloading, a part held - another pressing held doesn't stop it); then `autoGrabPick(candidates,
  candidateFilters(chips), 'score')` at AUTO_GRAB_MIN_SCORE or more, asked for as a tapped Get is,
  and the sheet hands over. Otherwise the cards show with `notPickedLine` ("Didn't pick a source
  for you: …"). `autoPickBlocked(result, release)` also refuses a release with no tracklist ("with
  no tracklist to match the folders against, no score can be trusted") or no release id ("with no
  release id, deadwax can't tell whether you already have it"): the album as a whole, a chip's
  fallback, is scored on edition, format and peer alone - a two-track FLAC folder from a fast peer
  reaches 100 - and can't be checked as held, nor 409'd (review). The old panel's auto-grab has the
  same gap on its card fallback and is left as it is.
- **For VoiceOver** (review): the sheet has ONE live region, always there (visually hidden,
  polite, atomic), saying each outcome in a line (`sourcesAnnouncement` in lib/candidates.ts:
  asking, slskd's words, the store's title, nothing found, none passing, "4 sources", plus the
  not-picked line) - the pending block lost its own `role="status"`, which was inserted already
  filled and then removed. Try again, Re-search and Clear filters each end the state they sit in,
  so they first hand focus to the list (`keepFocus`: the scroller, `tabIndex={-1}`, no ring) -
  never to `<body>`, outside the dialog. A closed sheet's asking bar is paused in CSS.
- **app-rules.sim.cjs** (120): the sheets list gains Sources (its lock, inert, backdrop); the
  behind wrapper is `covered`; the page has exactly ONE `app-rg-get` and Search and the picker no
  primary (the chip is tinted); the page and Search reach App's `openSources` with the opener taken
  in the tap; `gotten`; a card's Get is download-then-hand-over in the click, `requestDownload`
  with nothing awaited before it and ten runners-up; the search, the store state and the chip each
  through a latestOnly of its own; a pick only fresh and never blocked; the settings read as the
  answer lands; in the sheet only the best match's Get is primary, the top by score whatever the
  sort; and, after review, the two sheets can't stack (`searchActive`, Search's `standDown`,
  `openSources`' Now Playing guard), Cancel lets the search go in the gesture, and the album page's
  `shown` (asked again as it shows, Get above the store line, no clearing). The pages memo is keyed
  on `sourcesOpen` and `pageShown` too, for that `shown` (since 2.0.0-player.19 also `desktop`,
  `sourcesGroup` and `sourcesPressing`, and `shown` reads `sourcesOver` - see "The desktop frame"). No playback action is reached from any
  new file (the allowlist is unchanged).
- **Style** (tokens only): theme.css section 10 gains `--dw-bar-green` (a measured speed's fill) and
  `--dw-best` (#7e4bb8, the best match's edge); app.css gains `--app-rg-get-*`, `--app-store-*`,
  `--app-result-get*`, `--app-z-sources`, `--app-sources-*`, `--app-chip*` and `--app-source-*`.
  Every control a tap target (the chips 30px, a card's Get and a row's chip 32px, each reaching 44
  from its padding box; the chip rows' reaches never overlap - row gap twice the reach - with room
  kept above and below); the sheet placed as Info is (`top: max(48px, safe-top + 8px)`, the insets
  placing it, never padding it). `test_app_css.py` holds all of it (45, seven new: after review
  the head's grid - `--app-sources-side` gone - the wrapping subtitle, the list's focus and the
  paused bar).
- **Not built, on purpose**: Get on the main page's own album pages beyond its Finds (they are
  untouched but for the builder); a Signals or size filter in the sheet (the board has none);
  per-card "Queued" states (the sheet goes as a Get is asked for); the old CandidatesPanel refactored
  onto the hook (merges from main stay safe); the desktop's sources table (S8). `useDownloadJobs`
  polling fast while the sheet shows (the plan suggested it; the hand-over to Requests makes it
  moot).
- **After review** (22 findings, each confirmed by skeptics, all fixed in this same slice and each
  marked "(review)" above): a chip's late lookup opening the sheet over Now Playing, another tab or
  a newer Get (`searchActive`/`standDown`, `openSources`' guard); Cancel leaving the search to an
  effect after the frame; auto-pick on the album as a whole; the store line stale after a Get and
  cleared on every re-ask, ABOVE Get so it moved the button (now under it, kept, asked again as the
  page shows); the settings read once a page and saved with no order (re-asked; `inTurn`,
  `confirmed` plus `pending`); seeding storing the defaults (`SEEDED`, only what differs); Tracks
  counting video (`audio_expected`); the best-match look following the sort; the subtitle's
  ellipsis; no announcement of the outcomes (one live region) or a failed save (a region in You);
  self-removing buttons dropping focus to `<body>` (`keepFocus`); two "Get from bob" buttons; and
  test gaps - which credit each payload field comes from (a synthetic case in payload.sim), the
  `touched` guard and Try again's fresh pick (sources.sim) - and stale words: the credit rules
  above and in the source comments, `getArtistIds` (deleted; credits.sim checks it is gone).
- **Verified**: 2048 Python tests (50 new: `test_candidate_missing_tracks.py` 12,
  `test_store_state.py` 9, `test_me_prefs.py` 22, seven in `test_app_css.py`), pyflakes, tsc, and all 34 sims (`payload` 53 and `sources` 65 new;
  `candidates` 106, `group` 68, `search` 66, `you` 61, `app-rules` 120 and `credits` 25 extended); 74
  mutations, one or more per rule pinned, each caught and restored byte for byte - four first got
  past (an untrimmed disc title, a superseded store answer for the same pressing, a chip's
  called-off answer landing anyway, a broken-off list kept) and gained the checks that catch them -
  and after review 48 more, one or more per fix, every one caught.
  The engine guard is empty, and `useDownloadJobs.ts`, `downloads.sim.cjs`, `CandidatesPanel.tsx`,
  `player.sim.cjs` and `test_enqueue.py` are untouched. (`test_player_cache.py::
  test_a_setgid_bit_is_no_bar` fails when pytest runs with TMPDIR pointed at the session scratchpad,
  as the sims need: macOS won't set setgid on a folder whose group, wheel there, the user isn't in.
  Untouched by this slice; it passes with the ordinary TMPDIR.)
  **NOT verified here**: the real page (the orchestrator builds the bundle and checks against a
  fake slskd serving Third's folders - a measured peer, a busy peer, a 24/96 rip, one missing
  "Threads" - and re-captures the old page's Find bodies to diff with find-buttons.json); a real
  slskd and real Soulseek folder names; and everything on the iPhone - the sheet scrolling under a
  finger with the page still, the sort's wheel, a tap above the sheet, a Get showing in Requests
  from the tap, VoiceOver on the cards, its live region and where its focus lands after Try again.
  After review, also for the real page: a chip's slow lookup with Now Playing opened meanwhile
  (nothing opens), the subtitle wrapping at 320/375/390, and the store line under Get coming back
  as "Already downloading" after a Get.

### Get, as the main page had it (2.0.0-player.41)

James (2026-10-14): "Finish the web app" - the app at /player/ replaces the main page, which retires once
the app covers what it does. The parity audit (`uplan/parity-audit.json`, the "find" rows) found five gaps
in finding and getting music, on phone and desktop, none needing a decision of James's; this closes them
(`uplan/slice-get-parity.md`). The main page is untouched: CandidatesPanel, its settings and its storage
keys read and write as before.

- **Another pressing of an album you hold** (v0.9.1's ask: "a way to see which editions are already in my
  library when I'm searching for new ones"). Search's MusicBrainz half still leaves held groups out
  (James's decision) and the artist page's held rows still open the album you have - app-rules pins both -
  so the way in is the album you have:
  - **"Other pressings ›"** ends the album page's chip row (`app-other-pressings`, after the Also chips),
    once the bridge's answer names the album's group (`otherPressingsGroup` in lib/idBridge.ts: the
    `release_group_mbid` the album's folders carry, lowercased, only an id as MusicBrainz writes one -
    an .m4a deadwax filed has none, and no chip). The row is drawn from the first frame, so it lands
    moving nothing below - and, after review, shown only once the bridge has answered or failed
    (`is-waiting`: its place held, nothing in it seen), so nothing in it slides either. It opens the group's page through App's new `openHeldGroup` - **with no
    preview**: Search's previews are real release groups, and a group built from Navidrome's name for
    the album would have given Get's payload no first-release-date and no credited ids (`getGroup` reads
    the preview first). The album's name is the page's `label`, and ReleaseGroupPage's new `title` prop
    shows it as the title until MusicBrainz's own arrives with the pressings (`header.title || title`) -
    never over it.
  - **The crowded row** (found in the real page): badge 134px + "Other pressings" 138px left an Also
    chip 62px at 390 ("A… ›") and nothing at all at 320 ("›"). Beside an Also chip, in a row too narrow
    for the three whole, the chip says **"Pressings"** (`app-other-short`; its name stays "Other
    pressings", an aria-label) and the "In your library" badge keeps its green tick and gives up its
    words (`app-held-badge-text`, the visually-hidden rule's declarations under
    `.app-album-chips:has(.app-also):has(.app-other-pressings)` - still read). The Also label then has
    85px at 320, 140 at 375, 155 at 390, measured. "Too narrow" is the ROW's own width since review - the
    row is a container (`container: app-album-chips / inline-size`) and the rules sit in
    `@container app-album-chips (max-width: 600px)`: the badge and "Other pressings" take 288px with
    their gaps, leaving an Also chip 312px of a 600px row (Dummy's whole is 285). It was the frame's (a
    phone shortened, app-desktop.css undid it), which crushed the Also chip to a bare "›" (26px) on a
    1280 desktop with the Edit panel's column open, cut it at 1024 with no panel and at 1440 with Edit, and gave up words
    on a phone on its side and a tablet that had 230px to spare. Measured since: rows of 280-524px
    shorten (Also label 85-244px - 115 at 1280 with Edit, whole at 1024 and 1440 with it), rows of
    780-940px (844x390, 820x1180, 1280 and 1440 with no panel) say every word. Where container queries
    aren't known (Safari before 16) every word shows and the Also chip gives way, as before the change.
    Without an Also chip nothing changes but the new chip. "Other pressings" never shortens (`flex:
    none`); the Also chips do, as before.
  - **The pressing list marks every pressing you hold** - "In your library" in the badge green under its
    note (`app-picker-held`) - from the page's one /library/owned answer (`ownedForGroup` by the group's
    id and every pressing's, the release ids lowercased, memoised on their sorted join), and
    `pressingsView(releases, asked, held)` keeps a held pressing out of the fold as it keeps the chosen
    one (`keptOut`), in the fold's own order. `PressingRow.held` is new; pressings.sim's existing checks
    read fields, so the shape change cost nothing.
  - **Get on a held pressing goes the way it always went**: the store line under Get says "Already in
    your library", and the Sources sheet shows the store's box with nothing searched (the find route
    answers `held` without asking slskd). group.sim pins Get still offered on one; the real page drove it.
- **The score's reasoning on every source card** (README :54 and :123, CLAUDE.md's "ranked candidates
  with visible reasoning"): `signalChips` (lib/candidates.ts, pure) - each judged signal in SIGNAL_LABELS's
  order (an unknown one after, by name), its word capitalised as the Signals chip names them, its value as
  a percentage, its band by scoreClass (good from 75, mid from 40, bad under; null left out, as the main
  panel leaves it) - and `editionTags`, the folder name's edition words in EDITION_TAG_COLORS' families
  (yellow amber, red red, main purple, green green, white plain). Drawn LAST on the card
  (`app-source-reasons`, a group named "Why it scored 92"), so opening them grows the card downward and
  moves nothing above - the real page measured the score and the speed well at the same y. **On a phone
  (`reasons` 'tap', the modal sheet) the score is the button**: aria-expanded, aria-controls the
  reasons (rendered always, `hidden` until open - the region has no display of its own, so `hidden`
  hides it; test_app_css holds that for both stylesheets), a chevron that turns, the board's box widened
  to hold it and reaching 44px. **On a desktop's panel ('shown')** the score stays a span and the
  reasons span the card's grid under the facts. Six chips need two lines at 390, hence the tap.
  Colours: STYLE.md's green and amber badges and a red one new in theme.css section 10
  (`--dw-badge-red-bg`, `--dw-badge-red-border`, text `--dw-danger-text`).
- **Format** - Any / Prefer lossless / Lossless only - in You > Getting albums, the third radio group
  (`FORMATS` in You's order; the server's tuple `("prefer_lossless", "any", "lossless_only")`, the
  default first, is `FORMAT_PREFERENCE_VALUES`, which test_me_prefs reads as one list with PREFERENCES
  and the PUT's model). Kept per user in `user_prefs` (key `format_preference`, the find route's own
  name). **The search sends it** in place of `readDownloadDefaults()`: useCandidateSearch takes a
  `formatPreference` getter, read as each search begins; Sources hands it `formatPreferenceNow`
  (useGetSettings.ts) - a promise of the answer to a read already out, if one is (after review: the
  sheet asks again just before each search it starts - `begin`, below - and the answer in hand went
  out with the search while the fresh one - a Format changed on another device - landed a moment
  later and changed nothing; the floor re-seeds and the pick rule is read late, but Format is sent
  once); else
  the store's value when the server has answered (or a choice is being saved), else a promise of it
  after one ask (the default if deadwax won't answer, never a rejection). The
  search already shows as asking while it waits, and a wait the sheet closed on asks Soulseek nothing
  (`request.current()` after the await). Without the wait, a Get reached without You or Search having
  shown - the album you have, from the Library, to its other pressings - searched by the default
  whatever was chosen. Separate from the floor: Format changes the score (score_format: 0.45 for a
  folder with no lossless file under Prefer lossless) and Lossless only leaves such folders out
  server-side; the floor only filters. A pick reads the same store as the answer lands, as before.
  - **Seeded once, per setting** (a builder's choice; the spec said "the existing seeding"): James's
    database was seeded at .15, so the existing gate (`seeded` false) would never have carried his
    main-page Format over - and his desktop browser's app, which until now sent that Format, would have
    silently gone back to Prefer lossless. So `_seeded` now LISTS the keys carried over (every save
    writes them all, `_seeded_value`); a row from before says "1", read as `SEEDED_BEFORE` (get_mode,
    quality_floor); the answer gains `unseeded`, and the store seeds when it is non-empty, passing it as
    `seedFromPreferences(main, keys)` - so Format alone is carried over for an older user, never the
    floor again over a choice made since, and still only what differs from the default (an empty save
    marks it). `readGetSettings` reads `unseeded` safely (known keys only; missing: every key before a
    first save, none after).
- **Confirm before cancelling** in You > Getting albums, under the three kept on deadwax - after their
  note and what went wrong keeping them (after review: between them, "deadwax can't keep these" read as
  being about it, and a refused Format said "Not saved" under it; the live region, always there, keeps
  the gap before it with `app-choice-gap`) - with its own note ("Kept on this device."): a checkbox leaf (`ConfirmCancelChoice.tsx`, WindDownChoice's shape),
  You's own state (`useState(readConfirmCancel)`, written in the tap) - App untouched for it, so the
  .42 merge stays small. `deadwax-player-confirm-cancel`: 'off' or 'on' when chosen; nothing stored -
  not carried over yet - reads `deadwax-preferences`.confirmCancel ONCE and writes 'off' if it said off,
  else **'default'**, which marks it carried over without storing the default as if chosen (reads as
  on, whatever the default becomes). Requests reads `readConfirmCancel()` at the tap; no app file but
  the seed reads the main page's preferences any more (app-rules).
- **Search again when folders were found**: under the footer saying what was searched - the board puts
  that line at the cards' foot - a "Search again" text button, a disclosure (aria-expanded,
  aria-controls the form, a second tap closes it) opening the nothing-found state's query form
  (`queryForm`, one copy drawn in place so the sims' trees hold it; `is-again` starts it without the
  state's top padding), its field focused as it opens - so its ring, drawn outside, shows every time:
  the form's label keeps room over the field for it (`calc(var(--app-ring-room) + var(--app-line-gap))`,
  6px; after review - at 2px the ring touched the label). Under "none pass your filters" too; never
  where the form already is, nor while asking, failing, or with the store's box. The edited-query rule
  is the hook's, unchanged. A Re-search (`requery`) and a new search (the request effect) close it
  explicitly - an effect watching for a pending search missed the sim's render-less path and would rely
  on an intermediate render.
- **Style** (tokens only): app.css `--app-source-score-*`, `--app-source-reasons-gap`,
  `--app-source-signal*`, `--app-source-tag-pad` (6px, the main page's tag's), `--app-sources-again-pad`;
  theme.css the red badge. test_app_css.py gains four (67): the score's reach (from the box's own height
  token, its border and border-box) and turning chevron and the reasons' hide-ability in both sheets,
  the bands' and edition words' colours and the words' padding, the crowded row (Pressings and the
  badge's words by the row's container query and nowhere else, the waiting row unseen), the picker's
  green mark, Search again's place and its field's room for its ring - and, after review, **every token
  a rule in the four stylesheets reads is defined** in one of them or set inline by the component named
  (`SET_INLINE`: the turntable's `--app-tt-aspect`, `--app-tt-fader-x` and `-from`, each checked to be
  set where it says).
- **Real page** (the builder's own deadwax on 8110, its own fake slskd on 8111 - a copy of
  app/slskd_sources.py - the stand-in Navidrome, live MusicBrainz, headless Chromium as `deadwax.test`
  over plain http; `work/get41-builder/drive.cjs`, 83 checks, all passing, no console errors): the chip
  row at 320, 375 and 390 with and without an Also chip (one line, on screen, every label whole or
  ellipsized as meant, no overflow); Dummy → Other pressings → its group, "Dummy" titled from the first
  frame, both held pressings marked and in view; Get on one you don't hold → cards with Prefer lossless
  sent; the score's tap opening the reasons with nothing above moving; Search again opening the query
  focused, an edited Re-search sent as typed and closing it; a held pressing's store line and the
  sheet's box; You's Format (default checked, Lossless only saved on deadwax, then sent with the next
  Get, the MP3 folders left out by the server); Confirm before cancelling carried over as 'default',
  turned off, and a card's Get to Requests whose ✕ cancelled with no question; and at 1440x900 the chip
  row whole, the marks, the panel's cards with their reasons always showing, Search again focused. Two
  harness traps on the way, not the app's: a tab keeps its pages mounted hidden, so the first `.app-rg-get`
  in the document can be another tab's (tap the visible one), and a cold group page from the Library
  may already be on a held pressing.
- **Verified**: 2406 Python tests (2404 passed, 2 skipped; 11 new: test_me_prefs.py 29 - three new and
  four refused bodies - and four in test_app_css.py), pyflakes, tsc, the build, and all 47 sims
  (`candidates` 122, `sources` 130, `you` 86, `settings` 77, `requests` 190, `pressings` 63, `group` 99,
  `artist` 128 and `app-rules` 304 extended; the counts after the second review). 48 mutations, one or more per rule pinned - the server's
  allowlist, default, legacy seed, every-key save and unseeded; the client's reading, the seed's keys and
  defaults, the store's gate, keys, carried Format and wait; the hook's Format and its superseded wait;
  the chips' rules and colours; the card's hidden reasons, button and aria-expanded; the sheet's tap or
  shown and Format; Search again's closes, place and toggle; the fold, the case, the page's held ids and
  title both ways; the picker's mark; the bridge's id; the album page's and App's wiring; the cancel
  setting's carry, once, reading and Requests; You's Format; and six CSS rules - each caught, the tree
  byte-identical afterwards (`work/get41-builder/mutate.py`). The engine guard is empty;
  `player.sim.cjs`, `useDownloadJobs.ts`, `CandidatesPanel.tsx` and the main page are untouched.
  **NOT verified here**: the iPhone - the score's tap and the chevron under a finger, the crowded row's
  tick on a real 390 and 320, Search again's field taking focus (WebKit shows the keyboard only for a
  focus in the gesture; Preact's render comes after it, so the field may take focus without the
  keyboard), VoiceOver on the reasons' group, the score button and the badge's hidden words; a real
  slskd's signals (the fake's are nearly all 100); James's own database's `_seeded` "1" carrying his
  main-page Format over once (pinned in test_me_prefs and you.sim, not run against his row).
- **After review** (15 findings, 10 once merged, every one fixed, each with a test that fails without it):
  - the edition words had no side padding - `--app-source-tag-pad` was read and never defined, so the
    declaration fell back to 0 (three reviewers); defined, and the general token check added above;
  - on a phone the badge slid ~73px sideways on nearly every album as "Other pressings" landed in the
    centred row - the row is now unseen until the bridge answers (`is-waiting`), its place held;
  - the shortening followed the frame, not the room (above);
  - You's server-setting errors sat under the device's Confirm before cancelling (three reviewers);
    put back under the three, as before the change;
  - a Get sent the Format in hand while the sheet's own fresh read was out (two reviewers) -
    `formatPreferenceNow` waits for a read already out;
  - Search again's focused field's ring touched its label - room made;
  - docs/player.md's phone list still said a home-screen app always asks before cancelling; store.py's
    schema comment and me.py's SEEDED comment still called `_seeded` a plain marker for the floor -
    both say what it holds now;
  - test_app_css's 44px "reach" assertion was an identity (hit >= hit) - it now reads the score's height
    rule, its border and border-box and evaluates the reach token (`length()`);
  - the group page's lowercasing of held release ids was unpinned - group.sim holds a capitals tag.
  Real page after the fixes (the fixer's own deadwax on 8112 and fake slskd on 8113;
  `work/get41-fixer/rows.cjs` 26 checks and `sources.cjs` 18, all passing, no console errors): the chip
  row at 320/375/390/844x390/820x1180 and 1024/1280/1440 with and without Edit; on every cold load the
  badge unseen for its first frames, then in one place and one width, the row's height held (from a
  Library tile nothing above the row moves either; a cold load from an address fills the title in, as
  ever); a Format set by another device meanwhile sent with the next Get (`lossless_only`, after the
  sheet's read answered) and the MP3 folders left out, at 390 and 1440; REMASTER 6px inside its border;
  Search again's ring 2px clear of the label; a refused Format's "Not saved" under the three's note and
  above Confirm before cancelling, clear of the tab bar at 390x844. **Still**: at 375x667 with the
  Format group centred, "Not saved" lands 2px under the tab bar's top edge (611 against 613) - the
  three's note above it runs to seven lines at that width; it is said in the live region all the same.
  14 more mutations, each caught (`work/get41-fixer/mutate.py`), the tree identical afterwards.
- **After a second review** (5 findings, each confirmed by skeptics, every one fixed):
  - a search reaching a desktop's Sources panel ALREADY OPEN - another Get, the page's next pressing
    (`again`), a Re-search, Try again - never asked deadwax: `useGetSettings(open)` asks only as `open`
    turns true, and the panel stays open across pages and Gets, so `asking` was null and
    formatPreferenceNow sent the Format in hand (the floor and "When I tap Get" had the same gap since
    .19). Every search the sheet starts now goes through `begin` (or `requery`), which calls
    `askGetSettings()` before the search reads the Format - set going synchronously, so the read is
    waited for; on a sheet just opened it joins the read useGetSettings began (one GET, measured with
    the real store under the real Sources: `work/get41-fixer2/repro-format.sim.cjs`). One GET
    /me/preferences per search on a panel already open. sources.sim logs the store's ask and the
    Format's read in order for each kind of search; app-rules pins `begin` as the one way to start one;
  - with Format Lossless only, an album shared only as MP3 said "Soulseek found nothing" and offered the
    query: matching.py drops every folder with no lossless file then, and the find route still sends
    `response_count`. The search now keeps the Format it was SENT with (`CandidateSearch.format`, null
    until deadwax's word is in), and `nothingLossless(result, format)` (lib/candidates.ts, pure) - Lossless
    only, no candidates, `response_count > 0` - makes the sheet and its live region say "Nothing lossless
    on Soulseek for …" with a note naming the Format and where it is; the query stays to edit.
    `response_count` counts peers' answers, not folders (one of only scans counts), so it never says how
    many lossy folders there were. troubleshooting.md and downloading.md say what to do; the main page's
    "no matches from N responses" is left as it is;
  - downloading.md said "Two places start" Get in the sentence this change rewrote - the artist page's
    row Get (since .17) is the third, now its own bullet;
  - You's Format radio shows the hook's own copy of the settings, which nothing read whole - a
    hard-coded field passed every sim; you.sim reads the whole object after a read where every setting
    is off its default;
  - ConfirmCancelChoice's check tapped only from on to off and never looked at the tick - a box that
    could never be turned back on, or never ticked, passed; settings.sim now taps back on and reads
    `is-on` both ways, as WindDownChoice's does.
  20 mutations, one or more per fix - `begin` asking nothing or asking after the search, each of its
  four callers bypassing it, the Re-search's ask; nothingLossless for any Format or with no answers, the
  announcement and the sheet not told the Format, the search forgetting or inventing it, the note and
  the query form dropped; the hook's three settings each made up; the checkbox only ever off and never
  ticked - each typechecking and each failing its sim on a check, not a crash, the tree identical
  afterwards (`work/get41-fixer2/mutate.py`). Real page (the second fixer's own deadwax on 8110 and fake
  slskd on 8111, a switch making Dummy's search answer its two MP3 folders alone;
  `work/get41-fixer2/checks.cjs`, 29 checks, all passing, no console errors): Lossless only at 390, 320
  and 1440 - "Nothing lossless on Soulseek for “Portishead Dummy”.", the note, the query and Re-search,
  the live region saying the same, nothing wider than the screen - and Prefer lossless then showing the
  two MP3 cards; on a 1440 desktop with the panel left open, the first Get one read shared then the
  search, and the page's next pressing (Lossless only set elsewhere: no MP3 card), a Re-search (Prefer
  lossless back: the MP3 cards back) and another album's Get (Third, held: its box) each asking deadwax
  and waiting for its answer before the search went.
- **Not built, on purpose**: per-pressing Also links inside the group page (it gets; the album page
  opens); Complete albums only, Min score, a sample-rate floor and more results from MusicBrainz (the
  audit's "should" rows - another slice: built in 2.0.0-player.50 but Min score, left to the desktop's
  Signals - see "Search extras"); the main page's own Format and Confirm before cancelling
  following the app's (the main page keeps its copies until it retires, configuration.md says so).

### Search extras (2.0.0-player.50)

James (2026-10-14), finishing the web app: the parity audit (`uplan/parity-audit.json`, the "find" area, the
critic's SHOULD list and its questions 7 and 8) found these in finding music, and James took its
recommendations - "More from MusicBrainz" rather than a limit stepper; a Complete albums only chip; a sample-rate
floor on a desktop; the size range dropped and README.md:123 corrected; Min score left to the desktop's Signals
(`uplan/slice-search-extras.md`). Phone and desktop alike unless said. The main page is untouched.

- **More from MusicBrainz.** The MusicBrainz half still asks for `MUSICBRAINZ_LIMIT` (12); under its rows a
  secondary `app-button` (`app-search-more`, the rows' width, a finger tall) asks for the next twelve of the SAME
  search by offset, appended below - nothing drawn moves (the real page measured the first twelve rows' places
  before and after, at 390 and 1440).
  - **The route** (`/search_musicbrainz/fully_search`) gains `offset: int = Query(0, ge=0,
    le=FULLY_SEARCH_OFFSET_MAX)` (1000): declared and bounded, a 422 outside with nothing asked of MusicBrainz.
    The client (`MusicBrainzClient.fully_search(..., offset=0)`) sends it ONLY when it isn't 0, so every
    existing first page - the main page's, the metadata editor's - is the same request and the same
    ResponseCache entry as before, and each later page is cached apiece. The answer gains MusicBrainz's
    `count` (how many groups match in all) when it is an int, nothing when MusicBrainz didn't say; a page past
    the end is `{}`, as a search that matched nothing always was. `tests/test_musicbrainz_routes.py` (11 new)
    through `start()` with a real client over a fake search: the first page with no offset, a page by offset,
    pages cached apiece, past the end, no count, four refused offsets (-1, 1001, words, a fraction), the
    bounds themselves, and the app's bound read out of lib/searchResults.ts as the route's.
  - **The app** (`api/musicbrainz.ts` `fullySearch(..., signal, offset = 0)`, the param only past 0). Search's
    `done` state keeps `query` (what MusicBrainz was asked - the words typed when a fielded read fell back to
    them, so the next page is of THAT search), `nextOffset` (every answer got, held and repeated ones
    included), `count`, `last` (the last page's size) and `more` (idle, asking, failed, or what the last page
    added). `askMore` goes through the half's own `musicRequests` latestOnly - a new search, or the box cut
    back below three characters, calls it off and its answer draws nothing - and appends by
    `appendPage(groups, shown, page, ownedNow()?.index)` (lib/searchResults.ts, pure): a group got twice
    (relevance ties shift between pages) drawn once, held albums left out as the first page leaves them.
    `morePages(nextOffset, count, last, limit)`: 'more' while the count says more match; with no count (an
    older server) only after a full page; 'end' after a page that brought nothing, whatever the count says;
    'far' past `MUSICBRAINZ_OFFSET_MAX`, the route's bound - "That's as far into one search as deadwax goes -
    add a word to narrow it." Busy, the button reads "Asking MusicBrainz…", aria-busy and aria-disabled (the
    tap refused in the handler, never `disabled`, which drops focus); failed, the reason ("MusicBrainz isn't
    answering just now…") over it and it reads Try again, asking the same page; a page whose NEW albums are
    all held says so by their number, "The next 12 albums MusicBrainz found are all in your library already."
    (`appendPage`'s `held`: the page's new groups the library holds, never a repeat), and a page that brought
    nothing new - none at all, or only rows already drawn - "MusicBrainz sent nothing new." (`morePageWords`,
    the words for both the note and the live region). One polite live region, drawn with the rows, says what
    a page brought ("12 more albums from MusicBrainz"). The button shows under "Everything MusicBrainz found
    is in your library already" too - more may match. When the page that ends it lands with focus on the
    button, focus goes to the first row that page brought, or to the note said in its place (tabIndex -1,
    no ring) - never left to fall to the page.
  - **Not built**: the main page's 1-100 stepper (James chose More); `#/search?q=` paging in the address.
- **Each pressing's facts.** `pressingFacts(release)` (lib/pressings.ts, pure): what the main page's releases
  grid had columns for and `pressingLabel` leaves out, as MusicBrainz gives it - its status ("Official",
  "Promotion", "Bootleg"), its full date when it says more than the year the label already does ("2008-04-28",
  "2008-04"), its labels when the label line shows a disambiguation in their place and any after the first one
  it shows, its catalogue numbers once each ("[none]", MusicBrainz's word for none, left out), its barcode,
  and "Worldwide" for an XW release (the label line leaves its country off) - "Official · 2008-04-28 · Cat. no.
  1764013 · Barcode 602517640132"; '' when there's nothing more. **No server change**: `/release_group` already
  asks `RELEASE_FULL_INC` (`labels` is what brings `label-info` and its catalogue numbers), and status, date,
  country and barcode are a release's own fields - read off a live answer (Mezzanine's 23 pressings). Language,
  script and packaging are in the payload too and aren't said (the spec didn't ask). `PressingRow.facts` is
  new; each option draws label, facts, note (`app-picker-facts`). **The chosen pressing's line**
  (`app-rg-facts`, with its whole in its tooltip) sits under the picker on a phone - between it and Get, two
  lines' room always (`--app-rg-facts-lines`, a fixed height, `-webkit-line-clamp`), so choosing a pressing
  with more or fewer facts moves nothing under it - and on a desktop under Get and the picker, the row's whole
  width, one line (`--app-desk-rg-facts-lines`): in the button it would have widened the picker until it
  wrapped under Get. The real page measured Get's place unmoved by a pick.
- **The dropdown's filter.** An album of more than `PRESSING_FILTER_MIN` (30) pressings gets a field at the top
  of the list (`app-picker-filter`, sticky over the options as they scroll, 17px so iOS doesn't zoom, outside
  the listbox - only options belong in one - named "Filter the pressings", `aria-controls` the list).
  `filterPressings(rows, typed)`: every word typed, folded (accents, case, anything not a letter or digit a
  space - so "uicb 1004" finds UICB-1004), found in a pressing's label, facts or note ("in your library" for a
  held one) as folded or with its gaps closed up (so "uicb1004" finds it too), folded pressings included and
  the fold stepped aside; "No pressing matches “…”." for none. What it left is said by one polite live region
  in the list for as long as it has a filter (`app-visually-hidden`, empty until a word is typed - VoiceOver
  reads a region only once it is already there): `pressingFilterWords(matching, typed)`, "4 pressings
  match.", "1 pressing matches.", or the "No pressing matches" words, the line drawn under the list having no
  role of its own. Its placeholder says what works, "JP, CD, a
  label or cat. no." - a country by its code, as the rows say it (no row says "Japan"). Opening still focuses
  the chosen pressing, never the field (on a phone that would put the keyboard up over the list); in the
  field only ArrowDown leaves it, for the first pressing (Home, End and the arrows across its text are its
  own); ArrowUp from the first pressing goes back to it; closing empties it, however it closes - the Pressing
  button's own press goes through `close(false)`. With the filter the list keeps its band clear by
  `scroll-padding-top: var(--app-picker-filter-block)` (`.app-picker-popover:has(.app-picker-filter)`), which
  the arrows' focus scrolling honours, and `reveal()` reads the same padding back for the list's own
  scrolling.
- **"Maybe in your library"** on the album you don't have: the page's `ownedForGroup` now passes the album's
  title and the names it could be filed under (the credit, `creditName`, and the name they go by now,
  `currentName` - the main page's card's `[artist, albumArtist]`), so a folder with NO MusicBrainz ids of
  that name is `guessed` when nothing is held by id; `holdingOf` says 'held', 'maybe' or 'not' (null until the
  library answers). A maybe draws the meta line as "1998 · Album · " and a dashed `app-rg-maybe` span, "maybe
  in your library" (`--dw-text-3` dashes, an inline box, so the line keeps its height - one line at 320,
  measured), its tooltip `describeGroupOwnership`'s words with the folders - as the main page's card says it.
  On a phone there's no tooltip, as on the main page. **Not built**: the maybe on Search's rows (the spec
  asked for the album page).
- **Links out**: at the page's foot (`app-rg-links`, after the tracklist - nothing moves), "On MusicBrainz",
  then "The album ↗" and "This pressing ↗" (three spans, a gap between, no punctuation) - `releaseGroupUrl(mbid)` (new in lib/pressings.ts) and the chosen pressing's
  `releaseUrl` (lib/albumProperties.ts, .44's) - each `target="_blank" rel="noopener"` (following one in the
  page would unload the player; app-rules' link rule lists the page now), a finger tall without moving its
  line (`--app-rg-link-reach`). None for an address that isn't an album's.
- **Complete albums only**, a chip on both frames - after Free slot in a phone's sheet, after Signals in the
  desktop panel (review: before it, it put Signals at the row's very edge - see "After review" below):
  `SourceFilters.complete`, off on every
  fresh Get (no setting presses it), kept on `again`, cleared by Clear filters, counted for it. It filters by
  a new optional `CandidateFilters.everyTrack` - `everyTrackPresent(candidate)` (lib/candidates.ts): no AUDIO
  track of the pressing missing, as the card's Tracks counts and its Missing line names (so the whole CD of a
  CD+DVD, "14 of 14", passes); an answer without `audio_expected` counts matched against expected; with no
  tracklist to count against (the album as a whole) a folder passes, as the main page's lets it. The main
  page's own `completeOnly` - counted against every track, a DVD's film included - is left as it is (the
  app's `candidateFilters` keeps it false).
- **The sample-rate floor**, a desktop's (the panel's, like Signals): `RateChip` in Sources.tsx after Signals
  and Complete albums only,
  a chip holding the platform's own select as the sort does (it reuses `app-sources-sort-select`; its ring is
  `.app-sources-rate:has(...)`), "Sample rate" for any, else "44.1 kHz+", "48 kHz+", "88.2 kHz+", "96 kHz+"
  (`SAMPLE_RATE_FLOORS` in lib/getSettings.ts), pressed while one is set. `candidateFilters(filters,
  minSignals, minSampleRate)` sets `quality.minSampleRate`, so lib/candidates.ts's own rule judges it: the
  folder's WORST file, a folder whose client reported no sample rate never passing. It filters only where it
  is drawn (`minRate = modal ? 0 : rate`): carried into a phone's sheet it filters nothing, and is back on the
  panel. Off on a fresh Get, kept on `again`, cleared by Clear filters, counted by `pressedCount`, and a pick
  goes by it.
- **The size range is dropped**: README.md:123 and docs/downloading.md no longer promise it (the board left it
  out of the app, "Not built, on purpose" in "Sources and Get"); downloading.md says the main page's Quality
  dropdown still has one, until it retires. Min score stays the desktop's Signals.
- **Style** (tokens only): app.css's own section, "search extras", with its own `:root` - `--app-search-more-gap`,
  `--app-rg-facts-lines`, `--app-rg-facts-gap`, `--app-rg-maybe-pad`, `--app-rg-links-*`, `--app-rg-link-reach`,
  `--app-picker-filter-gap`, `--app-picker-filter-z`, `--app-picker-filter-block`; app-desktop.css a block of
  its own with `--app-desk-rg-facts-lines` and More's foot. `test_app_css.py` gains seven (the More button and
  its note's focus, the facts' fixed height, the filter's 17px and sticky place, the filter's band kept clear,
  the dashed maybe, the links' reach, the rate chip's ring) and `test_app_desktop_css.py` two (the desktop
  facts line, More off the player bar).
- **Real page** (the builder's own deadwax on 8115, logins off, its own fake slskd on 8116 - get41's, Third's
  four folders: a 16/44.1 peer, a busy one, a 24/96 rip, one missing "Threads" - the stand-in Navidrome, live
  MusicBrainz, a hard-linked copy of the stub library plus one untagged folder, Massive Attack/Mezzanine;
  headless Chromium as `deadwax.test` over plain http; `work/srch50-builder/drive.cjs`, 47 checks, all
  passing, no console errors): at 390x844 "portishead" (90 groups) - twelve rows, More, offset=12 asked, 24
  rows with the first twelve where they were, the button back, clear of the tab bar at the foot; Mezzanine -
  "maybe in your library" dashed with its folder in the tooltip, the facts line under the picker with two
  lines' room, every option's facts, a pick changing the line with Get unmoved, the two links opening beside;
  at 320x568 the maybe on one line; Animals (90 pressings) - the filter at 17px, focus on the chosen pressing,
  "jp" leaving the twelve Japanese pressings with the fold aside, "zzzz" said, Escape closing; Third's
  Japanese CD - Complete albums only hiding the folder missing Threads; and at 1440x900 the facts one line
  under Get and the picker (on one row), the panel's sample-rate chip after Signals (96 kHz+ and 48 kHz+ the
  24/96 rip alone, 44.1 all four, with Complete albums only three), More from MusicBrainz, Mezzanine's maybe,
  and "gb vinyl" over Animals' pressings. Nothing wider than the window anywhere.
- **After review** (seventeen findings, thirteen once merged, all fixed):
  - **Signals kept its place** (major): in the desktop panel, Complete albums only (about 150px) before Signals
    put Signals at the row's very edge (1356-1418 of a content edge at 1420, at 1440 wide), so anything that
    widened the row's first line - the chip's own label becoming "Signals · 1" as a slider was first dragged,
    or Complete albums only pressed (semibold) - wrapped Signals to the second row, and its popover, anchored
    `right: 0` to it, jumped about 350px left and 42px down under the held mouse: a 26px drag from 0 set Titles
    to 100, and the popover hung 177px over the album page. The panel now draws Lossless, 24-bit, (320 kbps,)
    Free slot, Signals, Complete albums only, Sample rate, sort - the first line exactly as it was before this
    change, so Signals never moves; a phone's sheet keeps Complete albums only after Free slot. Measured on the
    real page: Signals at 1202-1264 at 1440 and 862-924 in the 1100 drawer whatever is pressed, a 26px drag
    from 0 setting 5, the popover on its row inside the panel. sources.sim pins both rows' order, with a
    minimum set and Complete pressed.
  - **The filter emptied by every close**: the Pressing button's own press only toggled `open`, so the words
    typed survived it; it now closes through `close(false)` (group.sim, app-rules).
  - **What a More page says**: `added === 0` had said "The next N albums MusicBrainz found are all in your
    library already" for a page of repeats, an empty page (a count running ahead - "The next 0 albums"), and
    with no library answer at all; now `appendPage` counts `held` (new groups the library holds) and
    `morePageWords` says that by its number, or "MusicBrainz sent nothing new." (searchQuery.sim, search.sim).
  - **The arrows never under the filter**: the browser's focus scrolling brought a pressing to rest at the
    list's top edge, under the 50px sticky filter (13 of 39 ArrowUps covered half a 72px option); the list keeps
    the band clear by scroll-padding, and `reveal()` reads it back (a list closed scrolled down and opened again
    put the chosen one under the filter too). Real page: 0 of 53 steps covered at 1440 and at 390.
  - **More's last page hands focus on**: the button unmounting with focus dropped it to `<body>`; when it had
    focus as the page landed, focus goes to the first row the page brought, or the note in its place - not on a
    WebKit tap (nothing focused), not over focus gone elsewhere. Real page: seven pages of "portishead" by Enter,
    focus on row 68 of 73, the first of the last page.
  - **Small ones**: a catalogue number typed without its dash ("uicb1004") finds UICB-1004; the placeholder says
    what works, "JP, CD, a label or cat. no." (no row says "Japan"; 190px of 244 at 320); More gets the main
    area's gap above the desktop's player bar; docs/finding-music.md quotes the links' line as drawn (three
    spans, no colon or dot). And tests for what was unpinned: a later page's count (grown keeps the button,
    shrunk ends it), the plural all-held words and a plain failure's own reason, accents folded in the filter,
    a label said once under three catalogue numbers (Wish You Were Here's 588ca0a5); sims.md's app-rules line.
  - **Real page** (the fixer's own deadwax on 8117, logins off, a fake slskd on 8118, the stand-in Navidrome,
    live MusicBrainz; `work/srch50-fixer/drive.cjs`, 28 checks, all passing, no console errors, nothing wider
    than the window).
- **After a second review** (three findings, all fixed):
  - **The filter said nothing to VoiceOver** (nit): "No pressing matches" was a `role="status"` paragraph made
    with its words, which VoiceOver doesn't read, and nothing said how many pressings a filter left. Now one
    polite region, always in the list while it has a filter (FolderPicker's "N folders match" did this
    already), says `pressingFilterWords`' words; the drawn line lost its role, so nothing is announced twice
    (group.sim: the region there and empty before a word is typed, its count, its none, emptied by a pick;
    pressings.sim: the words).
  - **The note check that read the label** (minor): pressings.sim's "a word of its note" typed "magic doors",
    which 7da10d5d's disambiguation puts in its label too, so a filter that stopped reading notes went
    unnoticed; it types "machine gun", 5add188d's bonus track, in neither its label nor its facts (checked in
    the same check, so the fixture can't drift under it).
  - **The first page's offset** (nit): only later pages' offsets were pinned, so a first page counting the rows
    shown rather than every answer got (one held album: offset 0 for 1) passed every sim; search.sim's
    all-held first page now checks More asks from offset 1.
  - **Real page** (the second fixer's own deadwax on 8115, logins off, a fake slskd on 8116, the stand-in
    Navidrome, live MusicBrainz; `work/srch50-fixer2/drive.cjs`, 22 checks, all passing, no console errors):
    Animals' 90 pressings at 1440x900, 390x844 and 320x568 - the region in the open list before a word is
    typed (1px, clipped, empty; a polite status in Chromium's accessibility tree), "12 pressings match." for
    "jp" with twelve shown, "No pressing matches “jp zzzz”." by the same region with the drawn line no role of
    its own, empty again once closed and opened; nothing wider than the window.
- **Verified**: 2657 Python tests (2655 passed, 2 skipped; 20 new), pyflakes, tsc, the build, and all 50 sims
  (`search`, `searchQuery`, `pressings`, `group`, `sources`, `candidates` and `app-rules` extended). 58
  mutations, one or more per rule pinned - the route's bounds and offset, the first page's request, the count;
  the app's bound, client and paging rules; More's busy tap, offset, fallback query, notes, button and
  latestOnly; every facts rule, the filter's words, threshold, keys, fold and emptying; the maybe, its
  artists, the facts' place and the links; the every-track rule, its no-tracklist case and named tracks; the
  chip, the floor, its count, its phone-sheet rule, fresh-Get and Clear-filters resets and the pick; six CSS
  rules - each caught on a check (ten first failed only to compile, and were made type-valid), the tree
  byte-identical afterwards (`work/srch50-builder/mutate.py`); and after review 25 more, every fix broken in
  turn (the chip order, the button's close, `held` and the words, the plain failure, a later page's count, the
  focus handoff's six conditions, the facts' one label, accents, the closed-up catalogue number, the
  placeholder, `reveal()`, four CSS rules) - all caught on a check, type-valid, the tree byte-identical
  afterwards (`work/srch50-fixer/mutate.py`); and after the second review 12 more (the filter's region made on
  demand, gone, not polite, drawn, counting every pressing, the drawn line a region again; the words' plural,
  their none, their nothing typed, their trim; a note not searched; the first page's offset by rows shown) -
  all caught on a check, type-valid, the tree byte-identical afterwards (`work/srch50-fixer2/mutate.py`).
  The engine guard is empty; `player.sim.cjs`, CandidatesPanel.tsx and the main page are untouched.
  **NOT verified here**: the iPhone - More under a finger and VoiceOver reading what a page brought (and where
  its cursor goes as the last page lands: VoiceOver's cursor is its own, not the page's focus), the
  filter's field and the keyboard over the list (and VoiceOver reading its region as the list narrows), the dashed maybe at 320 on a real screen, the links opening
  from the home-screen app (outside it, in Safari); a real slskd's sample rates (the fake's say 44.1 or 96);
  MusicBrainz's `count` for a search with no answers past the first page, and its paging of a very long tail
  (relevance ties shifting between pages - `appendPage` drops a repeat, nothing finds one skipped).

### Song search (2.0.0-player.53)

Step 7 of the multi-user plan (the plan doc's build order: "Song search: a MusicBrainz recording, then its
releases, then the request flow"; useful before multi-user). People often know a SONG, not the album it is
on. The Search tab's MusicBrainz half had albums only; it now has **Songs on MusicBrainz** too - find a song,
see the albums it is on, open one and Get it - on a phone and a desktop alike (`uplan/slice-song-search.md`).
The main page is untouched.

- **What a real recording answer holds** (asked 2026-10-15, gently - nine recording searches by hand, 2 s
  apart, with the app's own user agent, and the real page's own through a record-and-replay stand-in, each
  question once, 1.1 s apart; trimmed copies in `tests/fixtures/songs/`): `/ws/2/recording?query=` answers `count`,
  `offset` and `recordings`, each with its `id`, `title`, `length`, `disambiguation` (most live tapes: "live,
  2008-04-07: Heineken Music Hall, Amsterdam, Netherlands"), `first-release-date`, `artist-credit` (with
  aliases), and **`releases` - every release it is on**, each with its `id`, `title`, `status`, `date`,
  `country`, `release-events`, `artist-credit`, `track-count`, its **`release-group`** (`id`, `title`,
  `primary-type`, `secondary-types` - but no first-release-date and no credit of its own) and `media` holding
  only the medium the song is on, with its `track` (`id`, `number`, `title`, `length`) and `track-offset`. No
  `inc` is sent (a search takes none): the albums a song is on come in the one answer - Queen's
  studio "Bohemian Rhapsody" with all 353 of its releases in 133 groups (436 KB for 12 recordings). A recording
  on no release at all comes with an empty list.
- **What real answers look like** - and why the rows read as they do. A recording is ONE PERFORMANCE: every
  take is a recording of its own, and they tie at score 100 in no useful order. Fielded: "Roads" by Portishead
  is 45 recordings, the studio take (Dummy) fourth, ten live tapes around it; "Bohemian Rhapsody" by Queen 227,
  the studio take third; "Hey Jude" by The Beatles 219, the studio take not in the first dozen (bootlegs,
  medleys, compilation takes); "Miss Misery" by Elliott Smith 33, on no album or EP - a soundtrack, bootleg
  and promotional compilations, live tapes. A boost for Official releases (`+(...) status:official`), tried
  once, moved official takes up but still not Hey Jude's studio one (scores tie), so it isn't used. Words with
  no artist the library knows are matched against TITLES only: "hey jude" (114,731 recordings) is covers -
  tribute bands, string quartets, no Beatles on its first page (nor in any of the 300 answers a reviewer looked
  at: the first 200, and 400-499); "roads portishead" covers and mash-ups named after Portishead,
  never Portishead's Roads. Page 2 of Roads brought "Roads (live)", "Roads (Live UK 1998)", five remixes and
  two duets.
- **The rows are songs, not recordings** (`lib/songs.ts`, pure): one row per title by one credit (`songKey`:
  the credit's artist ids - two bands of one name stay two - else its words; `titleKey`: case, accents and
  punctuation folded, an aside naming another take or a mastering dropped - "(live)", "(Live UK 1998)",
  "(Remastered 2015)", "(2011 remaster)", "(mono)", "(stereo)" - but no other bracket, so "Roads (Max Cooper
  remix)" and "Sour Times (Airbus Reconstruction)" are songs of their own). Their albums are unioned, one per
  release group (`groupSongs`): its best status, its earliest date, its releases and recordings that have the
  song, the song's length there. One row per recording would be a dozen "Roads · Portishead" told apart by a
  length, the one on Dummy wherever it landed. The row's title is a take's plain title when any has one; a song
  on no release is left out (nothing to show or get). The albums are ordered (`sortAlbums`): Albums and EPs
  (no secondary type), then Singles, then everything else - any secondary type, a broadcast, nothing said -
  folded under one `foldLabel` ("On 1 compilation", "On 24 compilations, live albums, broadcasts and other
  records" - Roads' real first page - "On 11 compilations, live albums and soundtracks", "…and other
  records"), each folded album named as its own row names it (review: a live broadcast was counted a "live
  album" under a row saying "Live broadcast"): a live record is a live album only when it is an album or of
  no type, a broadcast is a broadcast, live or not, a live EP or single another record; within each Official,
  Promotion, Bootleg, anything else; the earliest first (a full date before its bare year, undated last); then
  by title. A song row: its title, then `songLine` - the credit, the song's length on the album it names, that
  album - naming the first album you have THE SONG on (yours before one only the store has), with "in your
  library" / "in the store" (`heldWords`, lib/whose.ts's words). An album row's line (`songAlbumLine`): its
  kind, its status unless Official, its credit when not the song's ("Various Artists"), its year, the song's
  length there when it is another version's against the row's (tracklistDiff's `isOtherVersion`), and where it
  is held (`songAlbumHolding`, review and second review). A folder of the group holds THE SONG (`song`) when
  its release is one the search found the song on (an .m4a deadwax filed has only a release id), when it has
  no release id at all (by the group's id, as every screen holds it), or when the album's pressings are
  already kept for the session (`SongEvidence.pressings` - app/pressingLists.ts's `kept`: its page opened, a
  Get chip, or the tap below) and its pressing's tracklist has the song (`songMatcher`: one of the song's
  recordings, or a track of its title). It holds it as **heard** when the library half's own songs (Navidrome's
  search3, as last answered - `SongEvidence.heard`) have one of the song's title (titleKey) by its credit
  (foldName) on an album named as the folder's own album tag (foldName; both names come from the same files'
  tags) - a song with no artist or no album id vouching for nothing - with that Navidrome album (`albums`) to
  open. Anything else of the group is **other**: "a pressing in your library" / "a pressing in the store"
  (`pressingHeldPhrase`, lib/whose.ts) on the album row, nothing on the song row. Holding The Slow Rush's
  usual CD had read as holding Patience (a bonus track on its Japanese CD alone), and its tap opened the
  12-track album you have; the dev library holds exactly that CD. The first fix called every such folder
  "another pressing" - which the docs said meant a pressing WITHOUT the song - and opened the album you don't
  have; **second review** found that backwards for the most common case: MusicBrainz keeps one song as several
  recordings across one album's pressings, and at the app's 25 a page "roads portishead"'s first page brings
  Dummy only through recordings ef37de8d (five pressings) and ab6cc25d (the 20th anniversary reissue,
  f5804905), while Dummy's 1994 XE CD (76df3287 - the dev library's "Dummy (1994)") has Roads as recording
  8a49dba0, on the second page alone with 13 other Dummy pressings. Holding only that CD read "another
  pressing in your library" right under the library half playing Roads from it, the song row claimed nothing,
  and the tap opened the album you don't have - on the usual pressing, which may be that very CD, marked "in
  your library" (the earlier code, by the group's id, had read it right). So the words for `other` are neutral
  now - "a pressing", never "another" - the two kinds of evidence above make it the song when they can, and
  the tap finds out (below).
- **The route**: `GET /deadwax/search_musicbrainz/songs?query=&limit=&offset=` (a user's route - in
  test_logins' table), declared bounds - `query` 1-1000 characters and not blank, `limit` 1-100 (MusicBrainz's
  own ceiling; default `SONG_SEARCH_LIMIT` 25), `offset` 0-`SONG_SEARCH_OFFSET_MAX` (= `FULLY_SEARCH_OFFSET_MAX`,
  1000, one bound for both halves) - each a 422 with nothing asked. `MusicBrainzClient.search_recordings`: one
  `recording/` request, offset sent only past the first page, cached in the ResponseCache (successes only), the
  answer `{recordings, count}` (count only when MusicBrainz said a number); a failed or shapeless answer raises
  MusicBrainzUnavailable, a 503 with the album search's words. No server twin of the box's reading exists: the
  app builds the query, as it does for albums.
- **The reading** (`lib/searchQuery.ts`): `songSearchQuery(text, plan)` - an artist you have at either end is
  `fieldedSongQuery` (`recording:"title" AND (artist:"A" OR artistname:"A")`, fieldedAlbumQuery's shape, so a
  renamed artist's songs are found as their albums are); anything else the words typed, never the albums' type
  filter; an artist's name ALONE asks nothing (every recording they made, in relevance order, live tapes and
  all, answers nothing - their albums are below). A fielded read that finds nothing is asked again as the
  words typed taken as ONE title (`songTitleQuery`: `recording:"the words"`, review) - not the words loose, as
  the albums fall back: a recording search matches loose words against titles alone, so "the slow rush tame
  impala" (Tame Impala known, no song titled "The Slow Rush") brought 11,924,330 recordings, the first three
  strangers' songs titled "Tame Impala", above The Slow Rush - 274 px at 390x844, the album's line under the
  tab bar at 375x667 and the album off the first screen at 320x568. As one title it still finds a title that
  starts with the name of an artist you have, which the box read as that artist (reasoned, not measured: the
  one fallback asked of MusicBrainz was "the slow rush tame impala"'s - count 0); free text is never asked
  twice.
- **In the Search tab** (`app/Search.tsx`): asked with the albums, from `askMusicBrainz` (the same pause, the
  same Enter, the same reading) through `askSongs` and a latestOnly of its own (`songRequests`); asked once
  for a text and how it read (`songsFor`: the albums' Try again, or Enter after the pause, asks no songs again,
  but Enter after the library named an artist it didn't know does). **Where**: a section of its own,
  **before** the albums' (`aria-labelledby="app-search-songs"`) - a phone shows it first - showing
  `SONG_ROWS_SHOWN` (3) songs, so an album's words still show the albums: at 390x844 the first album row of
  "portishead roseland" sat at 431-495 under two songs (the builder's run). A search that finds no song at
  all draws **no section** (review) - the albums answer for the words; "No songs on MusicBrainz for “…”." is
  said only in the slot below. **The album half is as it was** (review: the builder had the albums wait for
  the songs too - `Promise.all([ownedAnswered, songsAnswered])` raced against OWNED_WAIT_MS - which changed
  when they drew, and songs slower than that still pushed drawn albums down, ~274 px on a phone, a finger's
  tap landing on a song): its request goes first (`const first = fullySearch(...)`, then `askSongs`), the
  gate is HEAD's `Promise.race([ownedAnswered, wait(OWNED_WAIT_MS)])`, its requests and cache entries
  unchanged. **The slot**: while the songs are asked, the asking line sits in `.app-song-slot`, one fixed
  height (`--app-song-slot`, a 44px button with `--pl-gap-sm` above and below); songs landing AFTER the
  album answer was drawn (`late` - `albumsShown`, set by an effect, so only once the screen has had that
  answer; never for songs asked by their own Try again, which were asked for) are folded into it - **Show
  songs** (it opens SONG_ROWS_SHOWN, focus to the first song when it had focus), or one line: "No songs on
  MusicBrainz for “…”.", the no-release words, More songs for a bare page with more to come, or "MusicBrainz
  isn't answering." with a text-button Try again - each one line, ellipsised, so nothing drawn below moves;
  VoiceOver hears "N songs on MusicBrainz - Show songs to see them". Songs landing first draw at once. **A
  song's tap expands it in place** (a disclosure, `aria-expanded`/`aria-controls`, its container always there
  with `hidden` and filled only while open) - the PressingPicker fold's and More's way of growing in place; the
  Search root stays mounted, so Back from an album finds the song still open: its Albums, EPs and Singles,
  then the fold (an `app-text-button`, its own `aria-expanded`), or - nothing above it - the fold's words as a
  caption (`app-song-caption`) with its albums listed at once. **An album you don't have** opens through App's
  `openSongAlbum` with the song's recordings on that album (`album.recordings`); **one you have** the song on
  opens the album you have (Search's `openSongAlbum`, through the held rows' latestOnly - `heldRequests`, so
  the box changing or the tab no longer showing calls it off): a `song` folder's release through the id
  bridge (`songAlbumHeldReleases` - by release or kept tracklist only); a `heard` one's Navidrome album at
  once, nothing asked; and **only `other`** (second review) - the album's pressings asked first
  (`getReleaseGroup`, the row `is-busy`/`aria-busy`; a complete answer kept, so the album page then asks
  nothing - it is the page's own request, made before it opens rather than after), then the bridge for a held
  pressing whose tracklist has the song, else the album you don't have; the pressings already kept and none
  held having the song, the album you don't have at once. Navidrome not having it, the bridge failing or
  MusicBrainz failing: the album you don't have (whose page asks for the pressings again itself). **More songs** shows the songs in
  hand first (no request - "8 more songs" said), then asks the next page by offset (`appendSongs(recordings,
  page, drawn)`: every page's recordings regrouped, the songs DRAWN kept in their order - a later take adds its
  albums to its row in place - and every other song after them; review: a song whose takes on the drawn pages
  were on no release kept its first take's place in the regrouping and came back ABOVE rows drawn, focus
  landing on an old row - DJ Tripp's two takes of "Breathe Roads" in the real "roads portishead" answer, one on
  a release and one on none, are such a pair), busy and
  aria-disabled, a failure said with Try again on the same page, its words (`moreSongsWords`) - new songs said
  only to VoiceOver, "No new songs - 7 more albums for the songs above.", "MusicBrainz sent nothing new." - and
  `morePages` with the route's limit; its last page hands focus on as More from MusicBrainz's does. States:
  the sweep and "Asking MusicBrainz…"; recordings found but none on a release - "MusicBrainz has songs for
  “…”, but on no release yet - nothing to get." (review: it read "No songs", untrue - "Roads (Max Cooper
  remix)" by Portishead is one such recording), More and the bound's note drawn whether or not any row is
  (as the albums' More is); MusicBrainz away with a Try again of its own (`askSongsAgain`, the songs alone).
  A new search calls the old one off; the box emptied or cut back
  below three characters calls the songs off and empties them (`dropSongs`), as the albums' rules do.
- **The album opened from a song** (`app/ReleaseGroupPage.tsx`): App opens the group page with the recordings
  in the address (`#/<tab>/group/<rgid>?song=<id>,<id>`, `Page.song` - not the page's identity nor its scroll
  key, kept by `replaceTop` as a pressing is chosen, read back on a cold link; `songIds` keeps up to 8 MBIDs)
  and **no preview**: a recording search's release groups carry no year or credit, and a preview is what Get
  builds its download (and its folder's year) from - so the header and the download come from MusicBrainz's own
  group with the pressings, the title standing in meanwhile, as "Other pressings" opens one. The pressing
  shown (`asked`) is the address's, else `songPressing`: null (the usual pressing) when the usual one has the
  song, else representativeRelease over the pressings with one of its recordings, else over those with a
  track of its title; `songMatcher` marks a track of one of its recordings or one titled as those tracks are
  (track title or recording title, titleKey) - MusicBrainz often has the same song as another recording on
  another pressing (The Slow Rush's Borderline single mix: the usual pressing has Borderline, so it opens on
  that, Borderline marked). Patience, only on The Slow Rush's Japanese CD, opens that CD. A pick on a page from
  a song is written into the address even for the usual pressing (`songKey || picked !== view.defaultId`), so
  the song's choice never comes back over it. `trackRows(chosen, diff, isSong)` sets `TrackRow.song`; the
  phone's row and the desktop's table row take `is-song` and a visually hidden `SONG_WORDS` (", the song you
  searched for") in the title. Brought into view once (`songShown`), when its row is first found, only while
  the page shows (a page on another tab must not scroll this one) and only from the top (`scrollY` 0: a page
  scrolled meanwhile, or come back to with its scroll put back, is left alone), `block: 'nearest'` so a row in
  view stays still.
- **Style** (tokens only): app.css's "song search" section - `--app-song-indent` (the song's cover and gap, so
  its albums' covers line up with its title), `--app-song-cover` 40px, `--app-song-album` 56px, the chevron
  turning 180deg (still for reduced motion), the fold, the caption; the slot (review: `.app-song-slot`,
  `height: var(--app-song-slot)`, its lines one each with an ellipsis, `.is-row` for the failure and its
  Try again, `.app-song-show` the screen's width, no overflow of its own so a focused button keeps its ring);
  an album row's line under a song wrapping (review: "another pressing in your library" was cut to "another
  pressing in yo…" at 390), with `--app-song-gap` above and below inside the row's own height; the tracklist's `.app-rg-track.is-song`
  tinted `--dw-selected-row` (a Bonus track keeps its green, another version its amber), an inset accent bar,
  the title in the accent, semibold; app-desktop.css the table row's tint, the bar on its first cell and the
  title, inside the desktop query.
- **Tests**: 25 new Python tests (2894 in all: 2892 passed, 2 skipped) - `test_musicbrainz_routes.py` 19 for
  `/songs` (one request carrying the albums, paged and cached apiece, nothing found an empty list, no count,
  a 503 that says so and is never cached, a shapeless answer a failure, eleven refused bounds asking nothing,
  the bounds themselves, the app's page size and the shared offset bound read out of lib/songs.ts),
  `test_app_css.py` 5 (the slot's one height among them) and `test_app_desktop_css.py` 1. Sims: `songs.sim.cjs`
  new (82 checks), `search` (190), `searchQuery` (67), `group` (153), `routes` (284), `app-rules` (400),
  `whose` (98) extended - the counts after the second review; app-rules' pressingsView pin and whose's
  "pressing on screen" pin updated on purpose (the page's pressing asked is `asked`); app-rules' gate pin is
  HEAD's again, with the songs kept out of it; app-rules' held-open pin, whose's phrase check and songs/search's
  held-pressing checks updated on purpose by the second review ("a pressing", the evidence, the tap's look).
  The builder's **67 mutations** (`work/song53-builder/mutate.py`: the route's bounds, words and page size, the
  client's offset, failure and count; grouping, ordering, fold, held and line rules; the reading; the gate, the
  fallback, the few rows, More's reveal and merge and focus, the drop, the once-only, the held open, the songs'
  own Try again, the fold, the section's place; the page's pressing, its picks, its three scroll guards, both
  marks; the address's song four ways; App's no-preview and prop; the app client's offset; six CSS rules) were
  all caught, one only by failing to compile until made type-valid. **Review** found that list didn't reach
  every rule it named - the title tie-break (songs.sim's check of it had ids equal to titles), the first album
  only the store has, the length from a later release, "&" and "and", a duet's artists in either order, a
  track known by its recording's title, the songs' bound note, free text never asked twice, App's label and
  fresh scroll - and that the bridge answering nothing or failing, the drop's key, the albums' Try again after
  both failed, a second tap closing, and a new answer closing were unpinned. Each has a check now, and
  `work/song53-fixer/mutate.py` breaks every one of them and every review fix one at a time - **47
  mutations, all caught on a check** (a sim's FAIL line, or for the four CSS rules a pytest assertion - none
  by a compile failure), the tree byte-identical afterwards (`mutate.log`). The engine guard is empty.
- **After a second review** (six findings, each confirmed by skeptics, every one fixed; no Python changed):
  - **A held pressing with the song as a recording the page didn't bring** (major): the first fix's
    "another pressing" was backwards for Dummy's 1994 CD (above, under the rows) - it now reads "a pressing in
    your library" unvouched (`pressingHeldPhrase`), is made the song by the library half's songs or the kept
    pressings (`SongEvidence`, `heard`/`albums`), and its tap asks the album's pressings first (above, under
    the Search tab). Not done instead: a bare rewording (the tap would still have opened the album you don't
    have of a song you hold), nor asking every held album's pressings as the rows draw (a MusicBrainz request
    per album); the kept-pressings check is memoised per kept list and song (`pressedFor`, a WeakMap - each
    album row's line asks namedAlbum, so a big album's tracklists would otherwise be folded once per row per
    render; a speed-up, so no check pins it).
  - **The notes named the wrong Dummy pressing** (nit): "The cost, chosen" said the 20th anniversary
    reissue's Roads is on page 2 - at 25 a page the reissue (f5804905, recording ab6cc25d) is on the first,
    and the 1994 CD (76df3287, recording 8a49dba0) the one past it; songs.sim's comment said "on page 2" of a
    pressing the 12-recording fixture merely doesn't list. Both now say what the recorded answers show.
  - **search.sim's header** (nit) still said the albums wait for the songs and the fallback asks "the
    words": rewritten - the albums never wait, late songs fold into the slot, the fallback is one title.
  - **The best status and the recordings union were unpinned** (minor): songs.sim builds an album listed
    first by a bootleg, then a promo, then an official pressing (Official, placed by its earliest date among
    the Official albums) and one carrying two of the song's recordings (both kept). The notes' "its best
    status" is now pinned.
  - **Accent folding was unpinned** (nit): the check named accents but fed none; "Señor" / "Senor" and
    "Mañana" / "Manana" now - an accent MID-word, since one at a word's end folds even without dropping the
    mark (the mark is trimmed as punctuation).
  - **docs/player.md said a search finding no song draws no section** (nit) - a late empty answer stays as
    the slot's line; it says so now, as finding-music.md did.
  `work/song53-fixer2/mutate.py` breaks every fix one at a time - **32 mutations, all caught on a sim's FAIL
  line** (31 by songs or search behaviour; one - the tap's look taken out of the latestOnly - by app-rules'
  pin, search crashing on it), the tree byte-identical afterwards (`mutate.log`). New search.sim checks pin a
  broken-off pressings list (not kept, the next tap asking again, what it shows still counting) and an answer
  landing after the box changed (it opens nothing, asks the bridge nothing). The engine guard is empty.
- **Real page** (the builder's own deadwax on 8113, logins off; its own fake slskd on 5041; the stand-in
  Navidrome; MusicBrainz through a record-and-replay stand-in on 4541 - each question asked of
  musicbrainz.org once, 1.1 s apart, then replayed; a hard-linked copy of the stub library less The Slow Rush,
  plus a "Tame Impala/Currents" with no MusicBrainz ids, so Tame Impala is an artist the library knows;
  `work/song53-builder/drive.cjs`, 34 checks, all passing, no console errors; headless Chromium as
  `deadwax.test` over plain http): at 390x844 "roads portishead" - one row, "Roads · Portishead · 4:56 · Dummy
  · in your library", above the albums; opened, Dummy and "On 24 compilations and live albums" (a finger tall),
  the fold opening 24 more, official first; Dummy opening the album page you'd get from the Library; Back
  finding it all still open; More songs asking offset 25 - Roads in place with more albums (the "(live)" takes
  merged in), six remixes and duets after it, "6 more songs" said; "patience tame impala" - Patience and its
  remix, The Slow Rush then the single, The Slow Rush opening on the Japanese CD with Patience marked (Bonus,
  barred, said) and in view, Get's sheet for "The Slow Rush · CD · 2020 · JP · Caroline International" with
  six sources, the usual pressing chosen and written with the song, kept across a reload; "the slow rush tame
  impala" three songs at most in 274 px straight above the albums, "portishead roseland" the first album row
  whole on the first screen; MusicBrainz away - both halves saying so, the songs' Try again asking the songs
  alone; at 320x568 the lines' ellipses, nothing wider than the screen, a cold link to the song's album on the
  Japanese CD with Patience in view; at 1440x900 the songs above the albums from the sidebar's field, a click
  opening a song, the table's Patience row marked and in view, Get's panel for the Japanese CD. That run was
  before review: its "the slow rush tame impala" (three strangers' songs, 274 px) and its fold's words are
  what review changed.
- **Real page after review** (the fixer's own deadwax on 8116, logins off; its own stand-in Navidrome on 4553
  over a hard-linked copy of the WHOLE stub library - The Slow Rush's usual Australian CD among it - its own
  fake slskd on 5052; MusicBrainz replayed from the recorded answers on 4552, a `slow-songs` file delaying
  the recording answers, `away` answering 503; one new question asked of musicbrainz.org, `recording:"the slow
  rush tame impala"`: count 0; `work/song53-fixer/page/drive.cjs`, 25 checks, all passing, no console errors):
  "patience tame impala" - the row "Tame Impala · 4:53 · The Slow Rush", no claim, The Slow Rush "Album ·
  2020 · another pressing in your library" (whole - two lines at 320; "a pressing in your library" since the
  second review), "On 4 compilations, broadcasts and other
  records", the tap opening the album you don't have on the Japanese CD, Patience marked and in view, the
  store line "You also have another pressing"; "roads portishead" - Dummy held by its 20th anniversary
  reissue (a pressing page 1 has Roads on), "in your library", "On 24 compilations, live albums, broadcasts and
  other records", Dummy opening the album you have; "the slow rush tame impala" at 390, 375 and 320 - no songs
  section, no strangers; songs four seconds slower than the albums at 390 and 320 - the albums drawn first
  under the asking slot (60 px), the songs folding into it as Show songs, the first album row not a pixel
  lower, Show songs opening them; no song landing late at 320 - the slot's one line, ellipsised, the albums
  where they were; MusicBrainz away - both halves saying so; at 1440x900 the same Patience lines and the
  table's row marked.
- **Real page after the second review** (the second fixer's own deadwax on 8117, logins off; its own stand-in
  Navidrome on 4556 over a hard-linked copy of the stub library LESS Dummy's 20th anniversary reissue - Dummy
  held only as its 1994 CD, 76df3287 - with The Slow Rush's usual CD; its own fake slskd on 5055; MusicBrainz
  replayed from the recorded answers on 4557, `away` answering 503, plus one new question asked of
  musicbrainz.org: Dummy's pressings, `release/?release-group=48140466…` - one request, 20 pressings, the
  1994 CD's Roads recording 8a49dba0 as recorded; `work/song53-fixer2/page/drive.cjs`, 21 checks, all passing,
  no console errors): at 390x844 "roads portishead" - the library half "Song · Portishead · Dummy", the row
  "Portishead · 4:56 · Dummy · in your library", Dummy "Album · 1994 · in your library", its tap opening your
  Dummy (with Roads) at once, no pressings or bridge asked; with the library half's search blocked - the row
  claiming nothing, Dummy "Album · 1994 · a pressing in your library" (whole), its tap asking Dummy's pressings
  once and the bridge about 76df3287, the album you have opening, Back finding the row and Dummy "in your
  library", a second tap asking no pressings; "patience tame impala" - The Slow Rush "a pressing in your
  library", its tap with MusicBrainz away opening the album you don't have, with MusicBrainz back the album
  you don't have on the Japanese CD, Patience marked and in view, no bridge asked; at 320x568 Dummy's line
  whole on two lines, nothing wider than the screen; at 1440x900 the same row, Dummy's line, the click opening
  the album you have.
- **Not built**: a ranking of MusicBrainz's ties (a famous song's studio take can be a page or two in - Hey
  Jude's; More songs brings it into the one row); reading words with no known artist across title AND artist
  (`recording:(…) OR artist:(…)` would likely put Portishead's Roads first for "roads portishead" with no
  Portishead in the library - measured only for the title-only default, so not sent: the box's reading is the
  album half's); songs on the main page; a "get a better copy" (James, 2026-10-15: not now); the Search tab's
  songs in the address; saying of a held pressing nothing vouches for whether it has the song BEFORE a tap
  (the library's index has no track titles to look in, and asking each held album's pressings as the songs
  draw would be a MusicBrainz request per album - so it reads "a pressing in your library" until the library
  half, a kept list or the tap says); keeping
  the songs' empty answer from the slot when it lands just after the albums - an album's words beside an
  artist you have ask a second song request (the one-title fallback) and so often land after the albums, the
  slot then saying "No songs on MusicBrainz for “…”." where no section would have been.
- **NOT verified here**: logins on in a real page (the route is a user's - test_logins walks it; the words
  "in the store" and "a pressing in the store" are songs.sim's); the library half's evidence against a real
  Navidrome 0.64.2's search3 (its songs' `artist` and `album` as the stand-in gives them - track artist and
  album tag - assumed, read from the files as /library/owned reads them); the iPhone - the disclosure and the fold
  under a finger, VoiceOver reading "the song you searched for", More's region and "Show songs to see them",
  the slot under a finger as the songs fold into it, the album page's scroll to the song under the mini
  player on a real screen; how often real MusicBrainz answers the songs after the albums (so folded) - the
  recording search answers more (47-436 KB against 1-12 KB), and a fielded miss asks twice; a real Navidrome 0.64.2's id bridge for a song's held album; MusicBrainz answers for queries
  not recorded here, and its recording search on a bad day (a 436 KB answer for a big song).
