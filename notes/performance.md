# Performance: profiled, not guessed

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Loading, audited (2.0.0-player.26)

James: "it seems like things aren't loading very quickly ... can we just do a full audit of loading times
and optimize as much as possible?" Measured first: every request the app makes across a cold launch, a
relaunch, the Library, an album, Play, Search and You, on a throttled link (60 ms a round trip), in
headless Chromium against the dev stand-ins (`/home/tokay/deadwax-scratch/work/perf/net.cjs`). Three
things it found, each fixed:

- **The hidden Library tab loaded at every launch.** It is mounted from the start (hidden, to keep its
  scroll), and asked Navidrome for its first 60 albums, whether songs can be listed, and - once drawn -
  their covers, beside what Home was waiting for. App now draws `<Library>` only once its tab has shown
  (`librarySeen`, as `searchSeen` and `youSeen`); a desktop's sidebar shows Songs until the probe has
  answered, as it did while it was pending. app-rules pins it.
- **One album's cover came down at up to seven sizes** - 96, 112, 120, 260, 300, 400, 512, 800, 1000 by
  where it was drawn - each its own download. `coverUrl()` (player/api.ts) now asks at one of
  `COVER_SIZES` (128, 400, 1024: the smallest that covers the size asked), so Home's tile is the Library's
  and the turntable's label, a row's is the mini player's, and the album page's is Now Playing's and the
  lock screen's (the engine asks 512 through the same function - usePlayer.ts has no diff). Opening an
  album and playing it fetched its cover four times; now twice (128 and 1024), the second from the
  browser's cache when the page was opened first. Home's tiles are 400 where they were 260: sharper,
  and a little larger each.
- **Nothing static was kept.** Every stylesheet, the bundle, the font and the icons were `no-cache`, so
  every launch of the installed app re-asked about each - ten round trips to be told nothing changed.
  Now (src/api/app.py): `/player/` is served by `stamped_page()`, which appends `?v=<mtime>-<size>` (the
  FILE's own, read per request, so a new build needs no restart) to each stylesheet and script the page
  names; a request under `/player/`, `/dist/` or `/styles/` carrying `v=` is `immutable` for a year. The
  page itself and the manifest are still `no-cache`, so an upgrade is seen at the next launch - a file
  that changed has another stamp and so another address, which is what keeps "I upgraded and nothing
  changed" from coming back. **Don't make the page cacheable, and don't stamp with the version**: a dev
  build changes files without changing the version. theme.css is LINKED by the page now (stamped, and
  loading beside the others) instead of `@import`-ed from player.css (fetched only after it, unstamped);
  the Latin font file is preloaded; `/styles/font/` is immutable (a changed font would be a new file) and
  `/player/icon*` kept a day. The main page at `/` is unchanged.
- **Measured** (same link): a relaunch re-checked 10 static files and now re-checks 1 (the manifest), and
  fetches 0 of the Library's requests where it made 3 plus its covers; album-then-play cover downloads
  4 -> 2. The lab's covers are tiny (7 KB) and its Navidrome local, so the seconds saved on James's
  phone are NOT measured - only the requests and round trips.
- **Looked at and left**: the 110 KB (gzipped) bundle holds the desktop's visualizer and editors too -
  splitting them out would save a phone's first-ever download only, since it is now kept; Home's "Not
  played in a while" asks for 500 albums at launch (one request, last on the page); a cover that is a
  404 is asked for again on each screen; `/library/owned` and `/me/preferences` are each asked twice as
  Search first shows; and the first play of a FLAC in Safari waits for deadwax to make its MP4 (see
  "FLAC in an MP4, for Safari").
- **Verified**: 2354 Python tests (four new in tests/test_pages.py: the stamps, another address for a file written again, what is kept
  and what is still asked about), app-rules.sim (the deferred Library, the three sizes), and the real
  page before and after with the request log above.

## Known performance problems (profiled, not guessed)

Measured with 148 releases × 12 tracks:

| finding | measurement |
| --- | --- |
| Expanding one release group | **711 ms** freeze |
| DOM nodes, two groups expanded | 22,905 |
| Track `<div>`s built while `display:none` | 2,832 |
| `scrollHeight` read after a DOM change | 23 ms → **962 ms** worst case |
| Filter keystroke | 9–62 ms (fine) |

**Opening the metadata editor, measured against the live API and now FIXED.** It cost ten
MusicBrainz requests for one album; it costs four. Three things were wrong, and the middle one
was the expensive one:

| | before | after |
| --- | --- | --- |
| requests to open the editor on Metallica's *Metallica* | 10 | **4** |
| requests for one release group's releases | 5 | **1** |
| payload for that group | 1446 KB | **101 KB** |

1. `fully_search` eagerly walked the best group's whole release list as `best-match-releases`.
   The editor never reads that field — it ranks the groups itself — so those requests bought a
   payload that was dropped on the floor. `?releases=false` turns it off; the search view, which
   does render them, still gets them by default.
2. `inc=…+recordings` carried every track of every pressing purely so a list could show a count
   that `media[].track-count` already gives. That is what made MusicBrainz return 36, then 4,
   then 5, then 11 releases for a `limit=100` — it was capping on size, not count. Without it
   the same 58 releases arrive in **one** request. `?tracks=false` opts in, and the tracklist of
   the release you actually pick is fetched on its own.
3. Both defaults are unchanged, because the download flow matches Soulseek folders against a
   release's real tracklist. Losing that would gut the matching quietly rather than break it
   loudly — so the saving is opt-in and the caller that needs correctness gets it by doing
   nothing.

**The trap this creates, which is worth stating plainly:** a release fetched for the *list* has
no tracklist, and building a retag payload from one applies no titles and no track numbers —
writing nothing, and reading exactly like the edit silently failed. The editor therefore keeps
`selectedId` (what you clicked, drives the highlight and the cover art) apart from `selected`
(that release *with* its tracks, the only thing a payload is ever built from), refuses to plan
while the tracklist is in flight, and clears the selection outright if the fetch fails. Do not
collapse those two pieces of state back together.

**Both interface causes are now FIXED.** Measured in the running app, not estimated:

| | before | after |
| --- | --- | --- |
| expanding a release row | 711 ms freeze | **1.2 ms** |
| track `<div>`s built while `display:none` | 2,832 | **0** |
| forced synchronous layouts per expand | 1 (up to 962 ms) | **0** |
| font bytes fetched on load | 1.6 MB / 30 faces | **0** |

1. **`renderBody` builds a release's track list on FIRST EXPAND, not up front.** It used to
   build every track of every release eagerly into a container that is `display:none` until
   clicked — roughly half of every node in the document, for markup nobody had asked to see.
   A `tracksBuilt` flag makes it once-only and a DocumentFragment makes it one insertion.
   **Keep it lazy.** This is the single largest interaction win in the app and it is one
   `if` away from being undone.

2. **`checkScrollability()` is gone entirely**, along with its resize listener and all six
   call sites. It read `scrollHeight`/`clientHeight` on two containers — forcing a
   synchronous full-document layout, on every expand toggle — to toggle a class whose whole
   effect was **ten pixels of right padding** to clear the scrollbar. `scrollbar-gutter:
   stable` on `.scrollable` does that in CSS, always, for nothing. It also removed the
   layout shift the probe caused, where content jumped sideways the instant it grew past the
   fold. **Do not reintroduce a JS scrollbar probe** — reserve the space in CSS.

**Neither was a framework problem**, and both are reintroducible in Preact verbatim. When the
releases grid is finally ported, port the laziness with it.

**Three more came out of the design overhaul**, all of them things that cost nothing to keep
fixed:

- **The 30 bundled OTF faces are no longer referenced.** Only 7 ever loaded and `main-font-semi`
  (10 faces) was referenced by nothing at all. The interface uses the platform's own UI and
  monospace stacks now, so the page fetches **no font files whatsoever** — verified in the
  network log. (The `.otf` files lingered on disk until v0.6.7, when they were deleted as an
  unlicensed commercial font; and since v0.6.7 the page does fetch one font file again - the
  bundled 35 KB Noto Sans Latin subset.)
- **The loading indicator no longer animates the `content` property.** Swapping `content`
  twelve times a second replaces a text node, and each swap is a layout plus a paint. It is a
  gradient sweep now, over a 2px-tall element.
- **The full-viewport fractal-noise overlay is gone.** It was a repeated SVG the compositor
  repainted on scroll, for an effect set to 5.5% opacity.

### What the library tab sends (v0.9.20, the audit)

Measured on a generated library of 1,060 albums (the scratchpad's `biglib.py`). Opening the tab
fetched the album list TWICE (the snapshot, then the scan), each 4.3 MB, uncompressed, every visit.

| | before | after |
| --- | --- | --- |
| `/library/albums`, raw JSON | 4,320 KB | **1,900 KB** |
| on the wire, first visit | 4,320 KB (nothing was gzipped) | **63 KB** |
| on the wire, an unchanged library revisited | 4,320 KB | **~300 bytes** (a 304) |
| warm scan (every folder cached) | 69 ms | **45 ms** |

- **Gzip, for text only.** `CompressText` in app.py wraps Starlette's `GZipMiddleware` and skips
  the picture and font routes, which are compressed already - and, since 1.0.3, the player's
  stream and cover relays and its PNG icons. The relays are skipped for CORRECTNESS, not CPU:
  GZipMiddleware compresses any streamed body whatever its size and drops its Content-Length, so a
  206 came back gzipped with no length. The list is `serves_media()` (shared with `GuardMedia`)
  plus `CompressText.BINARY`, and the library's picture routes are matched exactly: the old
  `/deadwax/library/art` PREFIX also caught every `/deadwax/library/artist*` JSON route, which is
  gzipped now. See "Ported onto 1.0". It is plain ASGI, like the other
  middleware here: `BaseHTTPMiddleware` would break `request.is_disconnected()`, which the
  search cancellation relies on. GZipMiddleware already leaves `text/event-stream` alone, so the
  log stream is untouched.
- **Tracks travel compact** (`compact_for_wire` in library.py, undone by `expandTracks` in
  `ui/src/api/library.ts`). The fields that repeat on every track of an album (artist, album,
  album artist, dates, release id, format) go once per album as `track_defaults`, and a track
  carries only what DIFFERS, which is the mis-tagged file the track viewer is there to show.
  Two fields the interface never reads are dropped. It builds NEW dicts: a scan's albums are
  copies, but their track lists are the cache's own, and trimming them in place would strip the
  cache. **Anything that reads `/library/albums` other than `listAlbums()`/`rescan()` must go
  through the same expansion.**
- **An unchanged library is a 304.** `_json_with_etag()` hashes the body and answers
  `If-None-Match` with no body, with `Cache-Control: no-cache` so the browser always asks. That
  only works if the body is the same when the library is, and a scan's body never was:
  `scanned_at`, `scan_seconds`, `cached` and `stale` change on every scan. **They are headers
  now** (`X-Scanned-At` etc., `_SCAN_HEADERS`), and a 304's headers freshen the browser's
  stored copy (RFC 9111 §4.3.4). So "Scanned just now" stays true on a 304. **Verified in the
  real page**: 300 bytes per request on a revisit, with the summary still fresh.
  **Don't put a per-scan value back in the body**; it would quietly make every answer a 200
  again, and nothing would fail. `/owned` lost `stale` for the same reason (nothing read it).
  The first scan after a restart still differs from later ones, because it enrols `first_seen`
  for new albums; the test warms up first.
- **The warm scan's cache pruning** compared every cache key with a pathlib `relative_to()`
  round trip, which was half of a warm scan. It compares cache keys as they are now.
- **`naming.validate_template` and `folder_pattern` are memoised.** The scan reads every
  album's edition back out of its folder name, and it rebuilt the regex each time.

### Page start-up, the log, and escaping (v0.9.21-0.9.22, the audit)

- **The pings wait for the log stream to OPEN, not for a fixed sleep.** The MusicBrainz ping
  writes "Connection successful" to the log, and the stream keeps no history, so a line logged
  before the page is listening is lost. `sleep(100)` was a guess at that. `init.js` now awaits
  the EventSource's `open` (or `error`, capped at 2s), after drawing the pills as pending.
  **Measured:** the pings start 3ms after DOMContentLoaded. Before, they waited for a config
  fetch, the stream, and then 100ms.
- **...which exposed a 0.9.20 regression: Starlette's gzip holds a response's HEADERS until its
  first body chunk, whatever the content type.** It doesn't compress `text/event-stream`, but it
  still holds the stream's start back, so the log stream didn't open until the first event or
  the 15s keepalive. Events still arrived, so nothing looked broken. The stream now yields a
  comment the moment it connects, which also gets through any buffering reverse proxy.
  `tests/test_log_stream.py` drives the whole app, middleware included, and fails without it.
  **Any other streaming response behind `CompressText` needs the same first chunk.**
- **Log lines are built as TEXT.** `appendEvent` used to set them as innerHTML, and the log
  quotes MusicBrainz titles, Soulseek queries and folder paths, all typed by strangers.
  **Verified:** a search for `<b id="injected">` logs the markup literally and creates no
  element. No server message carries markup (checked), so nothing is lost. The connection
  pills set their code as text too.
- **Removed as unused:** `/monitor_slskd/config`, which startup fetched only to log "Loaded
  server config" and whose answer nothing read (the settings tab has `/deadwax/settings`);
  `utils.js`; the connector-line element the pills made and the CSS then hid.
- **Everything MusicBrainz sends is escaped on its way into markup (v0.9.22).** The search
  view's cards and release grid were built from template strings holding titles, artist
  names, labels, catalogue numbers and disambiguations straight from MusicBrainz, some of them
  inside `title="..."` attributes, where a straight quote ends the attribute (MusicBrainz's own
  format names carry one: `12" Vinyl`). `esc()` in main.js wraps every such value.
  **Verified** by stubbing the search's fetch with a group whose every field held an `<img>`
  and quotes: no element was created, every tooltip read in full, including the full-tracklist
  rows. **A new `${...}` in main.js markup takes `esc()`** unless it is our own constant; the
  Preact half has no raw HTML at all. The two "Specific releases" toggles, one for a card that
  came with its releases and one for a card that fetched them, were the same code twice and
  are one `mountReleases()` now.
- **One outside-click rule on the Preact side: `useDismiss` (v0.9.23).** The candidates panel's
  Signals and Quality dropdowns were the same shell written twice (open state, outside-click
  effect, toggle, badge), and closed on a plain outside click, so a press on a label inside that
  slipped off it closed the dropdown. That is the bug Downloads fixed in v0.6.8, and Downloads
  now uses the same hook. They are one `FilterDropdown` now. `close` goes through a ref so a
  re-render can't re-subscribe mid-press. **Verified with real pointer drags**: a press on the
  "titles" label released outside the panel closed the old dropdown and leaves the new one
  open; a plain click outside still closes it; Downloads still closes on Escape and on an
  outside click. **A range slider's own drag was never affected**: Chrome keeps the pointer on
  the slider, so its click lands on the slider. Measured by dragging one on the OLD build,
  because the first draft of this change assumed otherwise.
- **The downloads poll reads only what the panel shows (v0.9.24).** `list_jobs()` runs twice a
  second with the panel open, and decoded every job in full: the stored release, and up to ten
  runners-up with their whole file lists. 50 jobs came to 1.4 MB of JSON and 7.2ms a poll on
  this Mac (a NAS CPU is several times slower). The panel reads neither. It now selects no
  release, and extracts the runners-up's usernames in SQL, and only for failed or cancelled
  jobs, the only rows that show "next peer". It sends `alternatives_left` for those rows only.
  Even that extraction costs 3ms over fifty rows, which is why it is gated. **1.3-1.6ms now.**
  `get_job()` still returns the whole row, so the retry and the organizer are unchanged.
  `RETRYABLE_STATUSES` moved into store.py, where both the route and the query read it.
  **Verified end to end**: a download queued from the candidates panel and then cancelled
  showed "next peer, 2 other peers left", and the older failed rows with no peers left showed
  no button.
- **The library tab on a thousand albums (v0.9.25).** Measured in the real page against the
  generated library (1,060 folders, 980 albums, 12,720 tracks), with a timer heartbeat for
  main-thread stalls, since the pane's long-task observer reports nothing:
  - **An unchanged scan is not read.** Opening the tab drew the snapshot, then parsed, rebuilt
    and re-rendered the scan behind it: a second stall of 150-200ms for a body that was
    byte-identical. The ETag is a hash of the body, so `loadScan(mode, shownEtag)` compares it
    with the one on screen and, on a match, cancels the body and updates only the scan fields
    from the headers. That is the usual case. `useLibrary` keeps what's on screen in `shown`;
    `listAlbums()` stays for the settings tab's re-time, which has nothing to compare against.
  - **`expandTracks` fills in place**: 35ms of object spreads became 3ms, with identical content
    (checked). `tree.sim.cjs` pins that a track's own value still wins.
  - **The filter settles for 200ms** (`FILTER_SETTLE_MS`) before the tree follows it; emptying
    it applies at once. A broad match opens everything it touches, and "t", "tr", "tra" each
    rendered that tree for nobody.
  - **The tree is a memoised element**, with its three callbacks made stable (they only set
    state). The view re-renders on every keystroke, and with 12,720 rows on screen each key
    diffed all of them: **65ms a key, now 5-7ms.** Preact skips a component whose element is
    the one it rendered last, so this needs no `preact/compat`.
  - ~~Still slow: the first render of a HUGE result~~ **Windowed in v0.9.30, asked for** -
    see "The tree draws only what is in view". (`content-visibility: auto` had been tried first:
    it cut layout but added render time, a net 20%, with paint containment and guessed heights.)
- **A line logged from a worker thread never reached the page (fixed v0.9.26).** `SSEHandler`
  fell back on `asyncio.get_event_loop()` outside the loop, which from a worker thread raises or
  finds a loop that isn't running, and the handler swallowed that. Six page-bound lines run
  inside `asyncio.to_thread` and were all lost: "re-filed X as Y", "wrote cover.jpg", "deleted
  ...", an artist's albums moving, CD art saved, and the download cleanup naming what it removed,
  which the v0.6.20 entry above promises it says. The handler now hands the line to the loop the
  streams registered from. **Verified on 3.12 and 3.14**, and `test_log_stream.py` fails
  without it. **Anything logged with `frontend: True` from a thread relies on this.**
  logger.py also lost a TZ block that computed a time and discarded it, a formatter whose
  output was overwritten, and an `event_time` field the page never read (it stamps lines
  itself). `TZ` still sets the container's clock, because libc reads it, not this code.
- **Ten packages nothing imports are out of requirements.txt (v0.9.26)**: aiohttp and its seven
  helpers, musicbrainzngs (the client is hand-written on httpx), and colorama, which click only
  wants on Windows. Found by walking every import in src/ with `ast`. The HTTP/2 trio (h2,
  hpack, hyperframe) stays, because the MusicBrainz client asks httpx for `http2=True`.
  **Verified** by installing the trimmed list into a clean Python 3.14 venv (the image's
  version): `pip check` clean, 868 tests passing, none of the ten pulled back in.
- **`.dockerignore` is tracked again.** Upstream deleted it and gitignored the name ("rm
  dockerignore", no reason given), so a local build sent `.git`, `.venv`, `.devdata` and `.env`
  to the builder, and `COPY ui/ ./` would lay a local macOS `node_modules` over the Linux one `npm
  ci` had just built. CI builds from a clean checkout and never had either problem.
- **pyflakes found a bug the tests couldn't (v0.9.27).** `read_artist_mbid` called
  `mutagen.File` without importing mutagen, from the day it was written (v0.6.15). The
  NameError fell into its `except Exception: continue`, which reads as "no id on this file", so
  it returned None for every album. Until v0.9.14, when the scan began carrying album-artist
  ids, every artist page therefore resolved by a NAME SEARCH, the path the artist-page entry
  warns can match the wrong band. Since then it mattered only where the scan can't answer: a
  collaboration, or files tagged with a track-artist id alone. The import is added and
  `test_the_artist_id_is_read_from_the_tags` pins it (it fails without it). The same run
  cleared 31 f-strings with nothing to format, unused imports and `as e` bindings, and a
  `logger.info("talking heads!")` on every MusicBrainz ping. **CI now runs `pyflakes src
  tests` before pytest.** An undefined name inside a try/except passes every test that
  doesn't reach it, and this one hid for twenty versions.
  The vanilla scripts got the same treatment with `tsc --allowJs --checkJs --noUnusedLocals`,
  keeping only its unused-name diagnostics (the type errors are noise on untyped code): an
  `img` created and never used, and an `artistId` that `buildReleasesGrid` took and ignored.
- **Ranking candidates is four times faster, with identical results (v0.9.28).** 97% of it was
  `match_tracks_to_files`: every expected track against every file of every folder, each pair a
  fresh `SequenceMatcher` over names normalised again for every pair. On 300 folders of 12 tracks
  that is 25,650 of them, 278ms, and it ran ON the event loop, holding up every other request.
  Now each file's name is normalised and indexed once, and only the title changes per
  comparison. A perfect 1.0 ends the search for that track, since the first one found was
  always the one kept. A pair that difflib's cheap upper bounds (`real_quick_ratio`,
  `quick_ratio`) rule out is never fully compared. **68ms, and the whole ranking of the
  benchmark came out byte-identical** (every folder, score and signal).
  `test_the_fast_matcher_pairs_exactly_as_title_similarity_would` holds it to the pair-by-pair
  definition on 200 awkward random cases, and fails when mutated to keep the last tie. The
  ranking also runs in `asyncio.to_thread` now. `title_similarity` stays as the definition.
- **slskd is asked for the downloads of the jobs' own peers, not all of them (v0.9.29).** The
  poller, `/jobs`, cancel and the cancelled-transfer tidy all fetched slskd's WHOLE download
  list, which is every transfer it has kept and only shrinks when somebody clears it. 300
  finished albums is 2.3 MB of JSON a poll (8ms to parse here, several times that on a NAS,
  plus slskd building it), twice a second with the panel open. `get_downloads(usernames)` asks
  slskd's per-user endpoint for each peer side by side; one peer's is a few KB. A 404 means
  slskd holds nothing for that user, which is exactly what absence from the full list meant.
  Any other failure answers NOTHING, not a partial list, because a job missing from a partial
  answer would look like its peer had vanished and walk toward the unmatched grace limit. The
  username is encoded whole, since slskd_api's own `quote()` leaves `/` as a path separator.
  The raw `/download/downloads` debug route, which nothing called, went with it. **Verified live
  against the fake slskd**, taught slskd's per-user answers and 404: a queued download matched,
  with its queue position; cancel found and cancelled all ten transfers; and the fake logged
  no full-list request at all. The test fakes for the poller and `/jobs` answer only for the
  users they're asked about, so a caller that forgets a peer fails.
