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
  Settings tab, always has on) opens a question in the card: "Cancel this download? You'll lose
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
    (queryOverride); up to ten runners-up as SHOWN; the format preference read per search. The app
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
  the sheet opens - never at start-up - an answer in hand ASKED AGAIN and standing meanwhile (a
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
