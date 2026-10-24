# Backend and data: gotchas discovered the hard way

Each of these cost real time. Don't rediscover them.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Backend and data

- **slskd answers a search with `409 Conflict` when it is not logged in to SOULSEEK**, which is
  nothing like what the status name suggests, and it was the first thing real infrastructure
  broke. `SearchesController.Post` maps `InvalidOperationException` to `Conflict`, and the only
  thing throwing one on that path is Soulseek.NET's own precondition - "The server connection
  must be connected and logged in to perform a search". Traced through slskd's and
  Soulseek.NET's source rather than guessed at, because the guess anyone would make from the
  word "Conflict" is a duplicate search id, and it is not that.
  **The reason was in the response BODY the whole time.** `requests` renders an `HTTPError` as
  its status line alone, so `409 Client Error: Conflict for url: ...` is what reached the user
  while slskd was spelling it out one layer down. `slskd_said()` reads that body - a bare JSON
  string (slskd declares `[Produces("application/json")]` and returns plain strings), a
  ProblemDetails object, or text - and `describe_search_refusal()` explains the status around
  it. **Any other slskd call that shows an error to the user should read the body the same way.**
  429 is the other status worth knowing: slskd STARTS one search at a time, behind a static
  `SemaphoreSlim(1, 1)` taken with `Wait(0)` and held while a search starts (searches already
  started run side by side), so a second start made while one is starting gets "Only one
  concurrent operation is permitted". Since 2.0.0-player.49 every start deadwax makes waits its
  turn at `slskd_endpoint.SEARCH_GATE` (notes/logins.md "Downloads per person"), so two tabs, two
  people or a retry inside deadwax no longer meet it; another client starting a search at that
  moment still can, and so can a start the gate lets through after its 30 s bound (a wait that
  long, or a start slskd hasn't answered in 30 s giving up its turn).
- **Pinging slskd's API says nothing about its connection to Soulseek, and the pill claimed
  otherwise.** `application.state()` answers 200 whenever the container is up and the key is
  right; slskd sits there logged out and serves it perfectly. So the connection pill read
  `connected` right up until the first search failed - and then the *search* took the blame for
  something that was already wrong before it ran, which is the exact failure those pills exist
  to prevent. Same shape as the `peer avg` relabel: a status that visibly doesn't match reality
  teaches you to distrust the ones that do. `ping()` now reads `server.isConnected` and
  `server.isLoggedIn` out of that same payload and reports `NOT_CONNECTED`, `NOT_LOGGED_IN` or
  `CONNECTING`.
  **An slskd too old to report `server` at all is treated as connected** - absence of the field
  is not evidence of a disconnection, and a red pill on a working install is the worse of the
  two mistakes. `connectionWatchdog.isAwaitingVpn` is named when set, because slskd here runs
  inside a VPN container and "it is waiting for its VPN" is the entire answer; it is newer than
  some slskd versions, so it is read defensively and omitted when absent.
  The state string (`"Connected, LoggedIn"`, `"Disconnected"`) is a .NET flags enum and is only
  ever QUOTED BACK, never parsed - the booleans beside it are the contract.
- **`@app.middleware("http")` made `request.is_disconnected()` a permanent False, app-wide.**
  That decorator is Starlette's `BaseHTTPMiddleware`, whose wrapped `receive` has to be awaited
  to learn anything, and `is_disconnected()` only peeks - inside an already-cancelled scope, so
  the peek is always cancelled before the disconnect can arrive. Found when the v0.9.8 abandoned-
  search fix did nothing live while its tests passed (they call the route directly, with no
  middleware). The cache-header middleware is plain ASGI now (`RevalidateInterfaceAssets` in
  app.py), and `test_no_middleware_hides_a_disconnect_from_the_routes` refuses any
  BaseHTTPMiddleware coming back. **Don't add another `@app.middleware("http")`** - write it as
  ASGI, touching `send` only.
- **A 409 costs one extra request, on the failure path only.** `_explain_refusal()` asks slskd
  how its connection is doing, because "not connected, and it is waiting for its VPN" is an
  answer and "not connected" is a shrug. If that request fails too it is dropped silently and
  slskd's original words are used - a diagnosis must never replace the error it explains.
  The sentence it builds is shown in TWO places, on its own in the event log and after
  "search failed: " in the candidates panel, so every branch of it names slskd as its subject.
- **slskd's `averageSpeed` is cumulative** (total bytes ÷ total elapsed), so it only ever
  creeps upward and never shows the current rate. Real speed is derived from `bytesTransferred`
  deltas between polls. Don't "simplify" back to `averageSpeed`.
- **`uploadSpeed` is BYTES per second, not bits.** Two comments claimed bits, which would invite
  someone to "fix" the display by a factor of eight. slskd's own web UI renders the same field
  as `formatBytes(response.uploadSpeed)/s`, and `score_peer()`'s thresholds only make sense read
  as bytes — 1 MB/s for a fast peer, 100 KB/s for a decent one; as bits those would be 125 and
  **12.5** KB/s. The display was always right; only the comments were wrong.
- **Hold a stale rate for a duration, never for a number of polls.** `speed.ts` kept the last
  measured rate across quiet polls (a zero delta usually means "slskd hasn't refreshed its
  counter", not "the transfer stopped") — but it counted four *polls*, and the poll cadence is
  not fixed: 500ms with the panel open, 5s in the background, and browsers throttle background
  tabs further. So the same constant meant ~2s when watched and 20s+ when not. Measured against
  a steady 1 MB/s transfer with slskd's counter refreshing every 5s, **the speed read blank on
  54% of polls**, in gaps of up to 5 seconds — a transfer moving at a perfectly constant rate,
  flickering between a number and nothing. It ages out on wall time now (`STALE_RATE_MS`), which
  put that back to 92% and bounded the lie at ~6s whatever the cadence.
- **The speed is measured over a one-second window, which is also how often it changes.** One
  constant (`SPEED_UPDATE_MS`), not a measurement plus a display throttle — a short window
  quantises badly against slskd's own counter, so publishing twice a second gave a figure that
  was both hard to read and noisier than the transfer really was. Measured on a transfer
  deliberately wobbling ±30%: 120 distinct figures a minute became 60, and the scatter fell
  (std dev 0.212 → 0.187 MB/s) while still tracking the real swing. **The poll cadence is
  independent of this** — the extra polls drive progress and status, and their bytes accumulate
  into the next window rather than being discarded, so changing `POLL_OPEN_MS` does not change
  how often the speed updates.
- **`ui/test/speed.sim.cjs` is the only frontend test in the repo, and it is a script.** There is
  no JS test runner here (adding one needs a newer Node than this repo builds on), and the
  sampler is the piece of frontend logic whose failure is *silent* — a wrong rate looks entirely
  plausible, and "no speed at all, intermittently" is invisible to any assertion about a single
  poll. It compiles `speed.ts` itself, simulates polling against a known true rate, and exits
  non-zero. Run it with `node ui/test/speed.sim.cjs`; it fails on the pre-fix code.
- **An unrecognised slskd transfer substate is a permanently stuck job.** This was predicted in
  "What the tests cannot tell you" below and then happened: `summarize_transfers` knew about
  `"Completed, Succeeded"`, `"Errored"` and `"Cancelled"`, so **`"Completed, Rejected"` counted
  as neither done nor failed**. A refused download sat at `queued` forever — the interface
  renders that as "hasn't started yet" — and because slskd *was* reporting the transfers, the
  unmatched-transfer grace period never applied either. Nothing could clear it but hand-editing
  the DB. Every terminal substate now lives in `TRANSFER_FAILURE_REASONS` in `store.py` with the
  sentence shown to the user. **If slskd grows another substate, add it there.**
- **Never take a word apart to build a search query.** `build_search_query` used to strip all
  punctuation to spaces, so Metallica's **`S&M2` was searched for as `S M2`** — and found
  nothing. If Soulseek tokenizes on non-alphanumerics (which is what the failure looks like),
  the folder `Metallica - S&M2 (2020)` holds `metallica/s/m/2` and there is **no `m2` token in
  it**, so we asked for a term that exists on neither side. The album name silently vanished
  from its own search.
  The rule now: **punctuation between two alphanumerics is part of the word and stays**
  (`S&M2`, `R&B`, `AC/DC`, `Jay-Z`, `That's`); punctuation standing on its own is dropped
  (`Simon & Garfunkel`, `(Deluxe)`, `Guns N'`). Whatever Soulseek does to `S&M2` in the query it
  does to `S&M2` in the folder name, and that is a far better bet than guessing on its behalf —
  splitting it ourselves is the one option that is wrong under *both* readings of how it
  matches.
  **A first attempt got this wrong in an instructive way**: it kept the splitting and dropped
  the one-character debris instead, which fixed nothing here (`S M2` → `M2`, still no match) and
  quietly turned `Vol. 2` into `Vol`. Length is not the signal — position is.
- **A failed releases fetch used to be indistinguishable from an album with no releases.**
  `get_releases()` read `data.get("releases", [])` straight off whatever `request_with_retries`
  returned — and that answers with an *error dict* rather than raising, so a MusicBrainz blip
  came back as `{"release-count": 0, "releases": []}`. The interface believed it. The top search
  result rendered with nothing to expand, and since the filter facets are built from whatever
  release grids are mounted, **an entire search came up with no filters at all**. It now returns
  a `problem` alongside, and says so in the event log.
- **`renderFacets()` has to be called by hand, and one call site didn't.** Fetching a release
  group's releases mounted a grid without telling the facets, so expanding a group left the
  filter column still reading "expand a release group to see filters" — and with the bug above,
  that was the *only* way to mount a grid, so the filters never appeared at all. This is exactly
  the hand-rolled render bookkeeping counted below (29 call sites that must remember). It goes
  away with the port, not before; until then, **anything that mounts or unmounts a release grid
  must call `renderFacets()` and `updateResultsSummary()`**.
- **A non-total branch in `createReleaseGroupElement` produced a dead card.** It tested
  `if (releases && releases.length)` then `else if (releases === null)`, so an empty array
  matched neither and the group rendered with no grid *and* no fetch button — unexpandable, with
  no way back. `processSearchResults` now passes `null` for an empty list and the second arm is
  a plain `else`. Watch for this shape: `[]` is neither truthy-with-length nor `null`.
- **A 400 from MusicBrainz is a rejected QUERY, and retrying it is pointless.** It used to fall
  through to the generic branch and go round the retry loop ten times, with rate-limit pacing
  between each, before reporting "MusicBrainz is unreachable" — about thirty seconds spent
  arriving at the same deterministic answer, and then blaming the network for a bad search. It
  breaks out immediately now and says the query was rejected. This matters more since the
  search view began composing type-filter clauses: a syntax mistake there has to be legible as
  a syntax mistake.
- **`request_with_retries` returns an error dict rather than raising.** Reaching straight for
  `["release-groups"]` produced a `KeyError` that surfaced as *"Error searching MusicBrainz:
  'release-groups'"* — which reads like a bad query, so an outage looked like user error.
  `MusicBrainzUnavailable` now distinguishes them. **This is also why the response cache stores
  only the success path** — caching that error dict would pin a transient outage in place for
  the whole TTL, turning a bad minute into a bad hour with no remedy but a restart (and on disk,
  since 2.0.0-player.54, a bad month - the same one place stores both; see below).
- **MusicBrainz's own result order cannot pick the album for you.** Searching
  `releasegroup:"Metallica" AND artist:"Metallica"` returns 25 groups of which the **first five
  all score exactly 100** — two live albums, an interview disc, a compilation, and only then the
  1991 album. The editor took `slice(0, 3)`, so it spent three requests on the wrong groups and
  **never fetched the right one**; no amount of ranking the releases underneath could have
  helped, because they were never retrieved. `scoreReleaseGroupMatch` now ranks groups first, on
  group-level signals only (year is worth 100, exact title 40, studio-album-ness 30, an unlikely
  secondary type −30, MB's score ÷10 as a weak tiebreak). Weighted, not filtered — tag the 1996
  live album as 1996 and it still wins, which was verified along with the two Black Album cases.
- **The "rate limit hit" warning was ours, not MusicBrainz's.** `RateLimit.wait()` logged a
  *frontend* warning every time it paced a request, which during any normal burst is constantly —
  so the app spent its time telling the user that its own politeness was a fault. It is at debug
  now. A real 429 from the server is still reported.
- **docker-compose: `environment:` beats `env_file`, and that is now a supported way to
  configure deadwax — but only with LITERAL values.** Both sources work and may be mixed
  (`load_dotenv()` does not override existing variables, so the environment wins; there is a
  subprocess test pinning that, because flipping it to `override=True` would invert the
  precedence with nothing to show for it).
  The trap is `SLSKD_URL=${SLSKD_URL}`: compose re-interpolates that from its *own* env, and an
  empty result **still counts as set**, so it beats `.env` and leaves the setting blank beside a
  `.env` line that looks perfectly correct. That produced an unusable empty `SLSKD_URL` once
  already. `shadowed_by_empty_env()` now detects exactly this and names it in the log, and
  `setting_source()` reports which source supplied each setting on startup — "check your .env"
  is useless advice to someone who configured everything in compose.
- **`.env` values must not have trailing `# comments`.** Compose and python-dotenv disagree
  about inline comments. Examples go on their own lines.
- **Two editions of one album used to silently not arrive.** `{album} ({year})` gave the
  standard and deluxe press identical paths; `execute_plan` correctly refused to overwrite,
  so every track was *skipped* — and the poller only reported a problem when
  `organized == 0 AND skipped == 0`, so an all-skipped job fell through to status
  `organized`. Green tick, album missing. Fixed in both places, and both are covered by
  tests. **This was the exact Lidarr complaint that motivated the fork**, reproduced here.
- **Cover art is fetched on apply, never on preview.** Previewing runs on every click in the
  release list, so downloading an image to describe it would be slow and rude to the Archive.
  `plan_art()` decides what *would* happen with no network call; the route fetches the bytes
  and hands them to `execute_retag`, which keeps `retag.py` free of network dependencies and
  testable without one.
- **Cover art is served with a five-minute cache, so its URL has to carry a version.** Without
  one, replacing a cover showed the old image for five minutes — precisely when you are looking
  at it, since you had just changed it. The version is the **art file's own mtime**, and the
  distinction matters: replacing `cover.jpg` in place does not touch the *directory's* mtime, so
  `album.modified_at` sits perfectly still through the one operation that must be noticed
  (measured: dir mtime unchanged, file mtime moved). `albumArtUrl()` is the only place that
  builds this URL — keep it that way.
  Note the corollary: the scan cache also keys on directory mtime, so an in-place cover
  replacement is invisible to it too. `forget_cached_album()` on the retag path is what makes
  the new art appear; a cover changed by anything else needs a rescan.
- **Retagging a file does NOT change its directory's mtime** — only adding, removing or
  renaming entries does. Measured, not assumed. The library cache keys on directory mtime,
  so an in-place retag is invisible to the scanner and the edit looks like it silently
  failed. `forget_cached_album()` exists for exactly this, and the retag endpoint calls it
  for both the old and new locations.
- **Embedded pictures have a TYPE, and files usually hold several.** Type 3 is
  `COVER_FRONT`, type 6 is `MEDIA` — a scan of the disc itself. EAC and dBpoweramp rips
  routinely embed both, in no guaranteed order, so `pictures[0]` showed albums illustrated
  with a picture of a CD. Selection goes through `PICTURE_TYPE_PREFERENCE`, never by order.
  The same trap applies to ID3 `APIC` frames (there can be several, keyed by description)
  and to loose files — a lone `disc.jpg` is not the cover.
- **`/library/art` was the first endpoint to turn user input into a filesystem read**, and
  `/library/tracks` and `/deletion_summary` copy its guard. It
  takes a path relative to LIBRARY_PATH, so `is_within()` containment is load-bearing, not
  decoration — without it `?album=../../..` reads anything the container user can. It
  answers 404 identically for "outside the library" and "no such album" so a probe learns
  nothing. Covered by tests including a symlink pointing out of the library. **If you add
  another endpoint taking a path, copy this pattern.** And **a guard on the FOLDER is not a
  guard on the FILE**: a file found in a contained folder's listing can itself be a symlink
  out, which is how `/disc_art` served one until v1.1.8. A route serving a file's own bytes
  checks the file resolves inside its folder too.

### MusicBrainz answers kept on disk (2.0.0-player.54)

Asked for by James (2026-10-15): "the first time I search an artist it asks musicbrainz, and when it
gets results it caches them so the next time I search that artist, it's instant. how much space would
that take?" Until then every answer lived in `ResponseCache` alone - in memory, an hour, 64 entries -
so a search repeated after an hour, after a restart (every image update) or after a few album pages
asked MusicBrainz again. The decision it reopens, with the measurements, is in notes/decisions.md
("MusicBrainz responses are cached, successes only").

- **One layer under the memory one, in the one place.** `request_with_retries` (still the only way any
  MusicBrainz request is made - `test_no_musicbrainz_request_goes_round_request_with_retries` reads the
  source: only `_ask` touches a connection, only `request_with_retries` calls `_ask`, no other module in
  src names MusicBrainz's web service) looks in memory, then on disk, then asks. A disk hit is put back
  in memory. A success is stored in memory and queued for the disk in the same line it always was
  stored in. So every caller - Search, the album pages, the artist page, the metadata editor, the
  download flow's tracklists, and the song search slice (2.0.0-player.53) with no change of its own -
  gets it.
- **The file** (`src/musicbrainz_cache.py`, `SavedAnswers`): SQLite of its own, `musicbrainz-cache.db`
  in the FOLDER `MUSICBRAINZ_CACHE_PATH` names, or in the database's folder (`config.musicbrainz_cache_path`:
  DB_PATH or `default_db_path()`'s choice, so the legacy `jimbrainz.db` folder too). **Always a folder**,
  like `PLAYER_CACHE_PATH` - James's addendum (2026-10-15, "a cache path variable in the compose file so
  I can put the cache on my ssd"): one `/cache` mount holds both caches, and the compose example and
  `.env.example` name it beside `PLAYER_CACHE_PATH` (a test reads both). The build first read the value
  as a FILE unless the folder existed or it ended in `/`, so a folder not made yet became a SQLite file
  of its name (which then shut the player's cache out of it), the same setting named another file once
  the folder appeared, and a typo naming somebody's file got that file set aside; the review caught
  it. A folder not there yet is made with the first answer saved; a file where the folder should be is
  refused by the settings tab (`that is a file`), and one set in the environment is never touched - an
  OSError at `makedirs`, the row saying `is a file, not a directory`. A `meta` table says what it is
  (`kind`) and its shape (`format`); `answers` holds the key (`json.dumps(ResponseCache.key(...))`),
  the answer's JSON zlib-compressed, its size, `fetched_at` and `used_at` (wall clock, since it
  outlives the process). Created on the first answer saved, with
  `auto_vacuum = INCREMENTAL`, **the tables and the meta rows in ONE transaction** (`_make_tables`, also
  the format reset): the build made them a statement at a time on the autocommit connection, so a file
  killed (SIGKILL, a power cut) or a disk filling between the CREATEs and the meta rows was left with
  tables and no `kind` - refused ever after as "a database, but not deadwax's saved answers", nothing
  saved until it was deleted by hand, with a message telling you to leave it alone (the second review's
  catch, reproduced by killing the process at the meta rows). Now a cut-short making rolls back - the
  journal played back on the next open - to an empty file, made afresh. **Never the job database**: a path that resolves to DB_PATH (the folder
  value itself, or the file in it) is refused by the settings tab and by the layer itself (the row says
  why), since Clear empties the file. A `musicbrainz-cache.db` that isn't a SQLite database at all (no
  header) is set aside - renamed `<name>.unreadable-<time>`, its `-journal`/`-wal`/`-shm` with it,
  BEFORE SQLite opens it, since SQLite would otherwise decide what to do with a journal lying beside
  it; and a new one is started, with one log line. One that breaks while in use (a `DatabaseError`
  that isn't an `OperationalError`) the same. Only by real use (a read, a write, Clear): **the settings'
  look (`stats`, the GET the Clear line reads as it draws) never sets anything aside nor makes a file**
  (`repair=False`), and **a file of any other name is never set aside** (`NotOurs`) - only one named
  `musicbrainz-cache.db` is deadwax's to rename and call deletable. A file that IS a database but not
  this one is left alone, nothing is saved, and the row says so. An `OperationalError` (locked, a full
  disk, read-only) only costs that answer: **a transaction it interrupts is rolled back** (the trim's
  own `BEGIN..COMMIT`, and `_with_file` for anything else - closing the connection if even that
  fails). SQLite doesn't roll back on SQLITE_BUSY, so before the review a trim whose DELETE or COMMIT
  another process's lock refused left its BEGIN open: every answer after it went into that
  transaction, never committed, the file's lock held, until a restart. A file that couldn't be opened
  is tried again after a minute, or at once after a settings save. **What a save found wrong (`problem`)
  stands until a file opens or the settings are saved** (`reset`): the build cleared it whenever a read
  found no file, so a folder that can't be made (`MUSICBRAINZ_CACHE_PATH=/cache` uncommented in the
  compose example with the `/cache` volume left out - deadwax runs as PUID and can't make `/cache`) was
  said for the minute after a failed save, then the Clear line's own look cleared it, the row read fine
  and the warning was logged again every minute of use (the second review's catch).
- **Never in the way.** One worker thread of its own (a one-thread `ThreadPoolExecutor`) holds the
  connection and does every read, write, trim and Clear in the order asked - never the event loop. A
  read not answered within `READ_TIMEOUT_SECONDS` (1 s - about what MusicBrainz's quickest answer
  costs at its request a second) is given up and MusicBrainz asked instead; writes and the "used now"
  touch are queued and never waited for. A disk hit is about 9 ms end to end through the route.
- **How big**: `MUSICBRAINZ_CACHE_MB`, 200 by default, 0 to 1048576, 0 off (nothing read or written;
  the file left as it is). Measured as the file's pages in use, `(page_count - freelist_count) *
  page_size`; past it, the answers used longest ago go until it is back under 90% (`TRIM_TO`, so a full
  cache isn't trimmed on every answer), and `incremental_vacuum` gives the pages back. An answer bigger
  than 90% of the budget isn't kept. "Used" is a disk read: an answer served from memory for its hour
  is touched on disk only when it is next read from there, so the order is right to within the hour.
- **Fresh enough**: a search (anything asked with a `query`) is old after 7 days, everything else after
  30. An old answer is answered AT ONCE (from disk) and one refresh is queued behind it, however often
  it is used (keyed like the cache, at most 100 waiting). The refresher (`_refresh_saved`, a task of
  the client's) waits until **nobody's question is on its way** (`asking`, counted from the memory miss
  on - the disk read included - until the answer) and **nothing at all has been asked of MusicBrainz
  for a whole window of the rate limiter** - 5 s, and never less than `REFRESH_QUIET_SECONDS` (2 s: a
  question chained on another follows it within milliseconds, so the quiet keeps a refresh from
  slipping between them) - checked by `RateLimit.quiet`, synchronous, so nothing slips in between the
  check and the refresh taking its turn. So **at most one refresh is ever in the limiter's window**:
  up to three questions asked together right after one go at once, and only a fourth waits for the
  refresh's turn to pass (at most 5 s); a hundred waiting take about nine minutes. The build paced them
  at the 2 s quiet alone, which let two or three refreshes sit in the window (4 turns per 5 s) and
  held a page's second and third requests after one for up to about 4.5 s - the review measured it.
  It asks ONCE (no retries), on **a connection of its own** (`get_refresh_client`: a slow refresh never
  holds the one connection a question is waiting for, and a network error closes only the connection
  it came on, either way), says nothing in the event log (its `HTTP <status>` line is info, not
  error), and replaces the stored answer - and the one in memory - only on success. A failure keeps
  the saved answer. **One for that question alone** - MusicBrainz answered 400 or 404
  (`REFRESH_ONE_QUESTION_FAILURES`; a refresh's failure carries `http_status` for this, seen by
  `_refresh_saved` alone) - drops only it, and the rest go on: before the review a 404 (something since
  deleted from MusicBrainz) dropped every refresh behind it as if MusicBrainz were away. The saved
  answer of a deleted thing stands (the spec: replaced only on success, any age keeps working). **Any
  other** (no connection, 503, 429, 403, another 5xx) means MusicBrainz is away, and drops every
  refresh waiting; each is queued again the next time its answer is read from disk - after its hour in
  memory, or a restart. A queue emptied while the refresher waits (Clear) ends it quietly. The screen
  showing the old answer is never redrawn.
- **Keys that mean the same question** (`same_question`): only a `query`'s runs of ASCII whitespace
  (space, tab, CR, LF - what Lucene's query parser splits terms on) become one space, and its ends are
  trimmed - never a whitespace character right after a backslash (an escaped space is part of a term),
  never a no-break space (Lucene reads it as part of a word), never the case (`AND`, `OR`, `NOT` are
  operators only in capitals), never another param. The memory layer keys the same way, so
  `Massive  Attack ` and `Massive Attack` are one question there too. Only the KEY is normalised: what
  is sent is what the caller wrote.
- **A paged browse is ONE answer** (`Browse`, `MusicBrainzClient._browse`): an artist's discography and a
  release group's pressings come a hundred at a time, each page its own question and key. The build
  saved and refreshed each page on its own, so a browse could be put together from pages of different
  ages - a refresh replacing the first page and failing (503) on the second, the size trim dropping one
  page and keeping the other, a look between two refreshes - and an edit on MusicBrainz that moved the
  page boundary meanwhile showed an album twice or not at all; the second review reproduced 150 release
  groups with 149 different, for up to a month. Now: every page of a browse is stored with the FIRST
  page's `fetched_at`, its stamp (`_ask(fetched_at=)`, `SavedAnswers.put(fetched_at=)`; memory entries
  carry it too, a disk hit put back with its own). A read takes pages from the caches only while their
  stamp is the first page's; a page of another stamp, or one in neither cache after pages that were, and
  the read is thrown away and made again from MusicBrainz, every page (`live`) - as it is when the first
  page itself comes from MusicBrainz. A stale page read from disk queues ONE refresh of the whole browse
  (`BrowseRefresh`, one place in the queue, never a page's own): `_browse(refreshing=True)` asks every
  page once, each after a quiet turn of its own (so still one refresh in the limiter's window), keeps them
  back (`keep=False`), and saves them together under one new stamp only when every page came - a
  failure saves nothing, the old pages stand together. The two loops are one pager now
  (`get_releases`, `get_artist_release_groups`), and their items are listed each id once
  (`_distinct`): pages asked seconds apart can still straddle an edit on MusicBrainz. A read thrown
  away costs what a browse cost before anything was saved. The app's own paging (Search's More, by
  offset) is the client's, and its `appendPage` already drops ids it has.
- **The connection check never reads or writes the file** (`ping` passes `disk=False`): it asks whether
  MusicBrainz can be reached, which an answer saved last week can't say. It keeps its hour in memory,
  as before.
- **Shared by everyone**, logins on or off: the key holds no user - MusicBrainz's data isn't anybody's.
- **Settings and Clear**: the two settings are their own group, "MusicBrainz's saved answers", on the
  Connections tab of both the main page's settings and the app's Server settings (`tabForGroup`),
  straight after the Connections group - whose last rows are Navidrome's three, after MusicBrainz's own
  (a group of its own can't sit among another group's rows; the build's notes said "right after
  MusicBrainz's own settings", which the second review caught). The path's row checks the folder the
  way the file will need it: a folder and writable when it is there, and **when it isn't, its nearest
  folder that is** (`_unmakeable_folder`), so a folder that can't be made is red from the start - after a
  restart, before any search - and for as long as it lasts. Both editable; a save of either closes the file
  (`SavedAnswers.reset`), so the next answer opens the file the settings now name, trimmed to the size
  they now allow. Under the rows, `components/MusicBrainzAnswers.tsx`: the count and size (`GET
  /deadwax/settings/musicbrainz_cache`) and **Clear MusicBrainz's saved answers** (`POST
  .../musicbrainz_cache/clear` - DELETE then VACUUM on the worker, the memory layer cleared and the
  waiting refreshes dropped, logged to the event log). Both admin routes (the settings router's
  `require_admin`), in test_logins.py's table; Clear is a write the same-origin guard refuses from
  another site. No confirmation: only speed is lost. Refused while the path is a draft (it clears the
  SAVED file), with nothing held, and while it goes - with **`aria-disabled` and the press refused,
  never `disabled`** (it refuses itself on its own press, and a focused button made disabled dropped the
  focus to the page - the review saw `document.activeElement` become BODY). Drawn afresh (keyed on the
  group's saved values) after a save, and **read again each time the app's page comes back into view**
  (`live`: the app keeps a hidden tab's page drawn, so the line said "Nothing saved yet." after a
  search until Back or a reload - the review's catch); not over a Clear on its way, whose answer still
  lands, since going out of view calls nothing off. The main page's tab is drawn afresh each time it
  opens, so it passes no `live`. Its row styles are the Re-time row's (`.settings-retime` selectors
  extended to `.settings-answers` in main.css, app-desktop.css and app.css), the refused look on
  `[aria-disabled='true']` (main.css's on a new theme token, `--disabled-opacity`, the 0.45 its
  `:where(button:disabled)` rule now reads too), tokens only.
- **Only the running app touches the real file**: `ResponseCache(disk=None)` is every test's unless it
  says otherwise, and the lifespan attaches `musicbrainz_cache.saved_answers` (reading the settings at
  every use) after the overrides and, as it ends, stops the refreshes, drops MusicBrainz's connections,
  closes the file (`close` writes what is queued first) and only then detaches it - a test holds the
  order. Two tests that enter the lifespan with a stand-in client (test_logins, test_personal_libraries)
  gave it a `cache` and `stop_refreshing`.
- **The HEALTHCHECK** is unchanged: /health reads the poller alone; the file and MusicBrainz count for
  nothing there.

Pinned by `tests/test_musicbrainz_disk_cache.py` (a fake transport; MusicBrainz never asked): a miss
asks once and saves; a restart (a new client and memory over the same file) answers with nothing
asked; byte-for-byte JSON; no failure saved (403, 400, 503, 500, 404, not-JSON, a network error); the
age rule (7 and 30 days, an old answer at once with one refresh, replaced only on success, a failed
refresh keeping it and dropping the rest - a 400 or 404 dropping only itself - and a refresh never
ahead of a waiting question: the limiter full, a question slower than the quiet, a question still
reading the disk - and `asking` back down after a question called off, while MusicBrainz is slow and
while the disk is); one refresh in the window, three questions after it at once; a refresh's failure
silent in the event log and closing only its own connection (and a question's only its own); a
refresher emptied while it waits ending quietly; a paged browse as one answer (refreshed halfway and
kept whole, refreshed whole under one stamp a turn a page, a page trimmed away - either one - and the
browse asked again whole, pages of different stamps never joined, an item on two pages listed once -
each for the discography and the pressings); the size bound and LRU order, the trim back under 90%
(not on every answer); too big not kept, between 90% and 100% of the budget too; 0 off; a file whose
making was cut short (a full disk at the meta rows, and a real SIGKILL there) made afresh; a corrupt
file set aside with its journal - by real
use, never by the settings' look, never a file of another name; one broken in use; a foreign database
left alone; a file of another shape made afresh; a trim refused by another process's lock, and any
failure mid-transaction, rolled back; the job database never the file; the path always a folder, made
when missing, shareable with the player's cache, a file refused and never touched, one that can't be
made said on its row from the start and still after the retry minute (and its warning logged once);
closing writes what is queued; the lifespan's attach and its order at the end; the default path
and the legacy folder; the compose example and .env.example naming both settings; a slow disk given up
within the timeout; the disk only on its thread; ping never from the file; the key rules; Clear (disk,
memory, refreshes) and its same-origin refusal, its refused look on `aria-disabled` in all three
stylesheets; the rows, the group's place, the refusals, a save applying from the next answer; the
bypass rule. `ui/test/mbanswers.sim.cjs` pins the component (aria-disabled only, the re-read as the
page comes back); `settingslog.sim.cjs` where both pages draw it, its key and `live`.

**Seen on a real page** (its own deadwax on 127.0.0.1:8120, a scratch database, real MusicBrainz -
six requests in all, seconds apart): a search of "Portishead" (releases off) took 0.51 s and saved one
answer (32 KB file); deadwax restarted, the same search took 0.009 s, the log saying "from the saved
answers on disk, nothing asked" and no request made, the answer identical as JSON. The saved search
aged by 8 days in the file and deadwax restarted: answered in 0.009 s, the log saying it was old, and
the refresh went behind it - the first time MusicBrainz answered 503 (another session shares this
address), and the refresh was dropped quietly, the saved answer kept, nothing in the event log; after a
restart the next one succeeded and `fetched_at` was now. Both settings pages at a non-local name
(`deadwax.test`, not a secure context): the group on Connections with its two rows, "1 answer in 32
KB saved, of 200 MB.", Clear emptying it ("Cleared. ..."), and at 390 px wide the button 44 px tall
with no sideways scroll. After the second review's fixes (its own deadwax on 8122, a scratch database,
five real requests, the launcher holding the limiter to one per 1.2 s): `MUSICBRAINZ_CACHE_PATH` a
missing folder under a mode-555 parent - the row red before any search ("nothing exists at ... and it
can't be made there: ... is readable but NOT writable"), a search saving nothing and the problem in
the Clear line's stats, both still there 62 s later, the warning logged once; and Massive Attack's
discography (107 release groups, two pages) saved under one stamp, a restart answering it from the file
in 0.02 s with nothing asked, and with its first page deleted from the file both pages asked again (the
kept second page never read) and saved under a new stamp, 107 different. NOT verified live: a file at
its size limit, a disk slow enough to time out, a corrupt file, a cut-short making, a browse refreshed
behind itself - those are the tests' alone.

**Verified**: 2969 Python tests (2967 passed, 2 skipped; 100 in the new file), pyflakes, tsc, all 53
sims (one new, mbanswers), the build; the engine files have no diff. Mutation checks: the build broke
41 rules one at a time, with one equivalent mutant (dropping `_queue_refresh`'s "already queued"
check changes nothing, the queue being a dict keyed the same way) - but the review found seven more
whose break no test noticed (`asking` three ways, a refresh's event-log silence, the 90% trim, a
refresh's connection closing alone, the emptied-queue re-check, the format reset, and the Clear line's
key and main-page drawing). After the fixes, 32 mutants in a copy (broken, the test file or sim run,
restored byte for byte): 31 failed their test; the one that survives is the trim's own ROLLBACK,
equivalent while `_with_file` rolls back too (both removed, both rollback tests fail). A second review
found six more (a folder that can't be made read as fine after a minute, a browse put together from pages
of different ages, a cut-short making refused for ever, `asking` after a question called off, the 90%
limit and the lifespan's order unpinned, the group's place misdescribed); after those fixes 19 mutants
in a copy - the problem cleared on a missing file, the row's parent check gone, the tables made outside a
transaction (twice: the full-disk test and the SIGKILL test each alone), a cached page's stamp
unchecked, page 0 from MusicBrainz not making the rest live, a later missing page asked alone, a
browse refresh saving page by page, browse pages queueing their own refreshes, no `_distinct`, a
browse refresh's pages taking no turn, its pages stamped one by one, live pages not given page 0's
stamp, a disk hit put back without its stamp, a cancel leaving `asking` up, `> budget` for `> 90%`,
the lifespan not stopping the refreshes, not closing the file, detaching before closing - every one
failed its test.

### Search what's saved (2.0.0-player.56)

James (2026-10-15), of the answers .54 keeps on disk: "and the cache includes songs and albums as well, correct? so i
can search it all?" It held every answer, but keyed on the exact request, so new WORDS asked MusicBrainz again:
search "portishead", open Dummy, type "glory box" - asked, though Glory Box is in Dummy's saved tracklist. He chose
**a searchable index of everything saved** (not a MusicBrainz mirror, offered and not wanted now): Search finds
anything you have come across before, under any words, at once, even with MusicBrainz down, and MusicBrainz's full
answer fills in after. The spec is `deadwax-scratch/uplan/slice-saved-search.md`; built on .54 (the disk layer)
and .55 (Search's one list, notes/app-requests-search-get.md).

- **The index** (`src/saved_index.py`, pure but for the connection it's handed): tables in the saved answers' own
  file, beside `answers`. `read_answer(endpoint, params, payload)` reads what an answer mentions from the key the
  disk layer stores it under (`json.loads` of `ResponseCache.disk_key` - no signature changed): `release-group/`
  (an album search, a discography page) its groups and their credits; `recording/` (a song search) its recordings,
  each release they are on and its group, and the track; `release/` with `release-group` (an album's pressings,
  with their tracklists) the group (each pressing's own, asked with release-groups, else the one asked for), the
  pressings and every track's recording - **the songs on the album**, so a song seen only on a saved album page is
  found by its title; `artist/` (a search) and `artist/<id>` (a page, or the aliases lookup) the artists. Nothing
  else: one release looked up alone (`get_release`) has no group to put its songs on, and ping is never saved. A
  payload of a shape it doesn't know reads as nothing.
  - **Artists**: name, sort name, aliases, disambiguation, type, country, years - from searches and pages, and the
    name, sort name and disambiguation every credit carries. **Albums**: title, types, first release date, the
    credit as the app renders it (`artists.credit_name`, the Python twin of `release.ts` creditName) and the
    credit itself, compact (`[name, joinphrase, id, artist name if not the credited one]` - an id is most of what a
    credit costs). A song search's release-group carries no credit: the release's is kept **weakly** - it fills an
    album nothing better has credited, never replaces one (a compilation's "Various Artists" never re-credits
    Dummy). **Songs**: title, length, credit, and `pressings` - `{release n: [track number, length, title when not
    the song's]}`, merged across answers whichever is read in first (a `union` field of `_upsert`: written as
    merged, never kept back by an older `seen`). **Releases**: their album, status, date, country, their title and credit
    only when not the album's. Pressings aren't rows Search lists.
  - **One row per thing** (`id BLOB UNIQUE` - a UUID's 16 bytes, `stored_id`/`given_id`; `n INTEGER PRIMARY KEY
    AUTOINCREMENT`); `_upsert`: the newest answer's fields win, one it doesn't carry (None) keeps the older's - a
    credit's partial artist never wipes the aliases their page gave.
  - **Mentions** (`saved_mentions(answer rowid, kind, thing n)`): a thing stays while a stored answer mentions it
    and goes with the last one (`unindex`) - the trim, Clear, a refresh replacing an answer (its old rowid's
    mentions dropped first, in the same transaction as the new answer and its own). A song's pressings naming a
    release since gone simply join to nothing.
  - **The words** (`saved_words`): ONE FTS5 table for the three kinds, `unicode61 remove_diacritics 2`,
    CONTENTLESS with `contentless_delete=1` (SQLite 3.43+; the words live in the things' own rows), its rowid `n * 4
    + kind`, no prefix index. Measured on the recorded answers: three self-content tables with `prefix='1 2 3'` took
    256 KB where this takes 84; numbering things by a hash of their id (tried, to drop the id index) took two and a
    half times the room in the full-text lists (their rowid deltas stopped being small), so AUTOINCREMENT n and the
    16-byte id index it is. A trim merges a little (`'merge', 64`) so deleted words free their pages.
  - SQLite without FTS5 (or before 3.43): the index can't be made - answers are saved as ever, Search finds nothing
    saved, said once in the log (`_index_said`).
- **Searching** (`search`): every word must match, the last as a prefix, each quoted (`match_expression` - nothing
  typed is FTS5 syntax; a word all punctuation dropped); per kind, bm25 (`ARTIST_WEIGHTS` 10/4 - an artist's name
  over the other names they go by; `TITLE_WEIGHTS` 10/2 - a title over its credit) over 100 candidates, then
  `_lifted`: named exactly as typed first (an alias counts: "kanye west" lifts Ye), then starting with it, bm25's
  order inside each. Björk was seventh by bm25 alone for "bjork" - her dozen spellings lengthen her other-names
  column. Songs of one title: the one on the most pressings first (a song search's covers are saved too; "glory box"
  means Portishead's). Bounded to the app's pages (10 artists, 12 albums, 25 recordings - `test_the_pages_are_the_apps_own`),
  each answered in its own route's shape: `artist_match` (so `matched_as` is /artists' own), a search's release
  group, a recording with `releases[]` as groupSongs reads them.
- **Kept in step**: the index's pages count toward `MUSICBRAINZ_CACHE_MB` (`_used_bytes` is the file's). The trim
  counted each answer's own bytes alone, which the index made a fraction of what dropping it frees - so it dropped
  nearly every answer to free the excess (a test found 6 answers of 82 left in a 1 MB file); now each answer's share of the index is
  counted by its mentions, at the file's own average per mention (`(used - answers' bytes) / mentions`), and the
  loop measures again. Clear empties the index in the same transaction as the answers. `0`: no search (`enabled()`).
- **The backfill**: `_ensure_index` (once per open, by real use - the settings' look only reads whether it's there)
  makes the index in one transaction with `index_format`, `index_at` 0 and `index_to` the answers' last rowid; then
  `_backfill_step` reads 25 answers or 256 KB at a time, each step in one transaction with how far it got, the next
  queued BEHIND anything asked meanwhile (the worker is one thread, FIFO) - so a search waits for one step at most -
  and says one line when done: "MusicBrainz's saved answers: N read into the saved-search index - Search finds what
  they hold under any words now". `warm()` (the lifespan, after attaching) opens the file if it's there, so it starts
  on the first start without waiting for a search; it never makes one.
- **The route**: `GET /search_musicbrainz/saved?words=` (1-200 characters; a user's - test_logins' table),
  `disk.search(words)` on the worker within READ_TIMEOUT_SECONDS (1 s), else `available: false` with every list
  empty and one log line - never an error. Shared: the index says nothing of who asked.
- **In Search** (`app/Search.tsx`, the rules in `lib/searchList.ts`):
  - Asked as the words settle - in the library's timer, for words MusicBrainz is to be asked for (3+ characters, or
    asked) - on Enter, and by askMusicBrainz; its own `latestOnly` (`savedRequests`), keyed by text, asked ONCE for
    the words whatever it answered (given up or failed, it stays so until the words change - after review); the box
    emptied calls it off.
  - **The library's moment waits for it** (`savedSettled`) at most `SAVED_WAIT_MS` (400) from its ask; past that
    it is given up for the words (`none`, called off) - a slow index means MusicBrainz alone - so a saved answer
    never lands after moment 1 and Top results' early decision stays sound. A cost said plainly: Enter on words not
    asked before now redraws a render or two later (after the saved answer, milliseconds) - search.sim's check
    waits for it.
  - **The pool** (`pool`'s `saved` block): what's saved, as the view reads the box (`savedFor` - only the kinds
    MusicBrainz is asked for; under the ARTIST reading only albums credited to the artist - from the route's
    `credited`, after review - the studio ones under the studio clause, studio-ordered, 12 at most; `shown` from the
    library's index as drawn, none before it is in), deduped against the library as MusicBrainz's are (newArtists over saved + MusicBrainz's
    together, so a library artist is brought in once and "answers to that name" counts both; heldUnlisted; newSongs);
    MusicBrainz's answer less what's saved, by key (MusicBrainz id; a song's key). `sectionRows`: saved first among
    MusicBrainz's rows, the preview's MusicBrainz cap over both. A held thing brought in by what's saved is in the
    yours block as ever.
  - **Top results**: `SOURCE` - yours 0, the store's 1, **saved 1.5**, MusicBrainz's 2 (and what each brought in, at
    its own). The phantoms stay MusicBrainz's (source 2), so a saved candidate at a phantom's tier beats it: "glory
    box" with nothing in the library decides Glory Box, Dummy, Portishead at the library's moment. The property
    check (searchList.sim) runs 1,200 combinations with saved answers in hand: a decided prefix is always the real
    answers' prefix - modelled, unlike .55's, with MusicBrainz answering only the kinds it is asked for (the artist
    reading's songs). A relative made of what's saved is marked saved (`familyOf`, Family.saved).
  - **Moment 2 and late kinds**: unchanged moments; a late kind's landing (`lateRows(pool, cap, drawn)`) leaves out
    what its section already drew, each part's cap less what it drew (`drawnCounts`), so MusicBrainz's answer adds
    only what isn't there, below - drawn in when last, folded when not - and when it adds nothing, *No more albums on
    MusicBrainz for "…"* (`nothingMoreWords`), never the empty words.
  - **The marks**: a saved row is MusicBrainz's row (`savedRow`: the same key, `saved: true`), its place "saved"
    unless it says you have it; a tile's third line "Saved from MusicBrainz". The region: "Saved from MusicBrainz:
    1 song." as the sections holding it are drawn, then "More from MusicBrainz: …" / "Nothing more from
    MusicBrainz." **Away**: a failed slot under saved rows says *Saved - MusicBrainz is away.* (busy: *Saved -
    MusicBrainz is busy.* - after review, to fit 320), the all-failed foot *MusicBrainz isn't answering just now - these are
    what deadwax has saved from it.* (`savedAwayWords`); a refusal keeps its words.
  - **Kind views**: what's saved after the view's library rows, as soon as they are, then MusicBrainz's states
    below (asking line, failure - in the saved words when saved rows are drawn - or its rows less what's saved);
    after review, MusicBrainz's rows held (the asking line) while what's saved is asked for the words, and what is
    drawn kept in place (`kindArea`).
  - With nothing saved for the words: today's draw exactly (search.sim's 315 earlier checks, unchanged but for the
    Enter one waiting a settle).
- **Measured** (2026-10-20, on answers recorded for this build - `work/saved56-builder/mb/answers/`, a request
  every 1.2 s, 38 answers - each artist explored the app's way: their artist search, the studio clause, their page,
  every page of their album discography, one album's pressings with tracks, one song search; added to ONE file in
  turn, the file's used pages before and after): Portishead 44 KB of answers / 68 KB with the index, Radiohead 64 /
  212, Tame Impala 44 / 72, Björk 108 / 200, Metallica 72 / 248 - **about 160 KB an artist on average, against 66
  KB for the answers alone**, so 200 MB holds about 1,100 artists explored (about 2,700 before); the index grows with
  a discography (Metallica's 539 albums, Radiohead's 405), less with songs. The empty index's tables: about 68 KB
  once (17 pages of 4 KB: 98,304 bytes used with them, 28,672 without, measured after review). Searches on that file 0.7-4.7 ms; on a synthetic 100,000 albums and 12,000 songs (36 MB, a 24-word
  vocabulary - every term common, the worst case for bm25) 11-25 ms, 68 ms for a one-letter prefix (asked only on
  Enter); indexing about 180 answers a second on the worker.
- **Tests** (as built; after review below): Python 3087 collected (3085 passed, 2 skipped; 51 more than .55's 3036): `tests/test_saved_search.py`
  (51 - each answer kind read, one row and newest-wins, the weak credit, a song only on an album page, every word /
  prefix / accents / quoting / no words, the exact lift and an alias's, title over credit, the most-released song,
  the bounds, a refresh, the trim (its words and its share), the index's room, Clear, 0, no file, the backfill (once,
  in steps, one line), a search between steps, no FTS5 said once, a slow search given up, the worker thread, the
  route's shapes against /artists, /fully_search and /songs, its `available`, its bounds, the pages the app's) with
  `tests/fixtures/saved/` (trimmed recordings); test_musicbrainz_disk_cache.py's tiny budgets raised to 512 KB (the
  empty index is ~68 KB, more than all of 64 KB), its meta checks reading past `index_*`, the lifespan's order with
  `warm` first; test_logins' row. Sims: `searchList.sim` (savedFor, studioGroup, the pool's blocks and dedupe, the
  cap over both, lateRows' drawn, the sources, the brought, the Nirvanas, the early decision, the family marks, the
  1,200-combination property, the words), `search.sim` (40 new: the library's moment, the mark and the tap, moment 2
  and the region, a late kind drawn in below and folded with nothing new, away (all and one), nothing saved = today,
  the artist reading, a saved artist's tap and dedupe, the Albums view, only the newest, given up, the box emptied,
  the real client's path), `app-rules` and `whose` (five pins moved to the new code: the frozen `shown` less what's
  saved, lateRows' call, the unmount's supersede list, heldUnlisted from both, the group place).
  `work/saved56-builder/mut/mutate.py` breaks 60 rules one at a time in the worktree, its test run, the file put
  back byte for byte (sha256 checked): 60 of 60 caught (the first pass caught 52 of 59; the missed seven - an alias's
  exact lift, title over credit, the words unindexed, the weak credit, the backfill's steps, the guard on a superseded
  saved answer, the box emptied - each got a test that fails without it).
- **Real page** (my own deadwax on 8116 from this worktree, logins off, the disk cache ON in a scratch folder; my
  stand-in Navidrome on 4547 over a hard-linked stub library with Third and not Dummy; fake slskd 5047; MusicBrainz
  through my record-and-replay stand-in on 4548; headless Chromium as `deadwax.test`, plain http, 50 ms of round
  trip; `work/saved56-builder/page/drive.cjs`, 16 checks, all passing): "portishead", Dummy opened (its tracklist);
  deadwax restarted; "glory box" - Glory Box from Dummy Top results' first at 287 ms after the last key ("Song ·
  Portishead · Dummy · saved"), then Dummy (saved) and Portishead (yours), before MusicBrainz's answer (sections at
  2,237 ms), nothing moved, Songs led by the saved row; MusicBrainz away ("glory box!", words never asked): Top results
  at 283 ms, the saved rows kept, each kind's place "MusicBrainz is busy - these are saved.", nothing moved; 320x568
  nothing wider than the window, the mark whole; 1440x900 a saved tile's "Saved from MusicBrainz"; no console errors.
  Live MusicBrainz: 40 requests for the recordings (38 answers, two 503s asked again after 3 s) and 6 through the
  stand-in (each once).
- **Verified after review**: the image's SQLite - `docker run python:3.14-slim` (the dockerfile's base, pulled
  2026-10-20): SQLite 3.46.1, and `fts5(a, content='', contentless_delete=1, tokenize='unicode61 remove_diacritics
  2')` made. **NOT verified**: a real file of months of answers being backfilled
  (steps measured only on 31 answers); VoiceOver on the saved mark; logins on in a real page.
- **Decisions this touches**, said plainly: Top results rank saved before MusicBrainz's answer (a new source between
  the store's and MusicBrainz's); the library's moment waits for what's saved, at most 400 ms; a song search is no
  longer the only way a MusicBrainz song shows under the free-text reading - a saved one shows without it; what
  MusicBrainz's answer brings that is the same thing as a saved row isn't drawn (the saved row stands for it, as it
  was saved - a renamed artist keeps its old name in that row until the saved answers refresh); and the default
  200 MB holds about 1,100 artists explored where it held about 2,700.
- **After review** (16 findings; each reproduced first - a test, a sim check or the code traced - and each fix has a
  test or sim check that fails without it, `work/saved56-fixer/mut/mutate.py`):
  - **A kind view moved what it drew** (two findings): its rows are drawn from what is in hand at every render, so a
    saved answer landing after MusicBrainz's rows - asked again by a chip's tap, Enter or Try again after it had been
    given up, or asked at the pause after a letter typed and taken back with Navidrome away - went ABOVE them,
    taking MusicBrainz's copies away. Now what's saved is asked once for the words whatever it answered;
    MusicBrainz's rows are held (the asking line) while it is being asked for the words - never once any is drawn;
    and `kindArea` (lib/searchList.ts, pure) keeps each drawn row in its place and as what it was drawn as - a late
    saved row goes at the foot, MusicBrainz's row of a thing saved stays MusicBrainz's, its line as it was.
  - **The artist reading's albums**: the route took its 12 albums by bm25 before the app kept the artist's own, and
    titles naming them fill the 12 first ("metallica" kept one album of a saved discography). The route now answers
    `credited` too - the albums whose credit is exactly the words (`name_key`, foldName's Python twin, held to it
    by the same names in test_saved_search and searchList.sim), found by their credit's words over up to 2,000
    candidates, studio-ordered, 50 at most - and `savedFor` draws the artist reading's from it, studio-ordered, 12
    at most. The section is still saved first, MusicBrainz's below: each block reads earliest first, not the whole
    (Dummy yours, Third saved, Portishead MusicBrainz's) - said in finding-music.md.
  - **An album you have drawn twice**: `shown` was worked out as the saved answer landed, before /library/owned had
    answered. Now `savedFor` works it out from the index as it is drawn, and draws no saved album before the index
    is in hand - waiting for it instead (as MusicBrainz's answers do, 1.5 s) would give what's saved up at 0.4 s on
    a first /library/owned walking a sleeping array, the restart case it exists for.
  - **The away words**: the slot's *MusicBrainz isn't answering - these are saved.* needed 280 px where a 375-wide
    phone gives 266 and a 320 one 211 (measured: real theme/player/app CSS, Noto Sans 13 px, headless Chromium);
    now *Saved - MusicBrainz is away.* (173 px) and *Saved - MusicBrainz is busy.* (170). The all-failed foot adds
    "What's in your library is above." only when a drawn row isn't what's saved (it is true when a saved song's
    artist is the library's: search.sim pins both).
  - **Stopping during the backfill set the whole file aside**: a step queued behind the close reopened the file on
    the old thread and queued the next on a NEW worker, whose use of the old connection raised ProgrammingError - a
    DatabaseError, so "broken": renamed `.unreadable-…`. Now `close()` sets `_closing` (nothing queued, a queued step
    does nothing; the next start goes on from `index_at`), and a ProgrammingError closes the connection, never sets
    a file aside.
  - **A rollback to .55 and forward again** left a stale index (things gone still found, new answers never indexed;
    a count and the highest rowid can't tell - .55's Clear then one answer saved leaves both as they were). Now the
    index's schema includes three triggers on `answers` (insert, delete, update of key or body) that mark the index
    stale in meta for ANY writer; this version clears the mark in the same transaction as each change it keeps the
    index in step with (`_in_step`) - unless it was there before (the trim on opening runs before the index is made
    sure of) - and `_ensure_index` makes the index afresh and reads everything in again when the mark or a trigger
    is missing, with one log line.
  - **A read-only file couldn't be read**: making the index failed (BEGIN IMMEDIATE), and the file was closed for
    it. Now the connection is kept for reads, Search finds nothing saved (said once), and the index is tried again
    after RETRY_OPEN_SECONDS on the file opened afresh (a connection opened read-only stays so).
  - **The index's own bookkeeping**: a song's pressings are a `union` field of `_upsert` (an older answer read in
    after a newer one - the backfill's normal case - lost the pressings it added); songs are ordered by the pressings
    that still join, worked out before the cap (a song's pressings keep the numbers of pressings gone with their
    answer); an unreadable answer `_get` drops is unindexed in the same transaction.
  - **Tests the docstrings claimed**: the artists and songs bounds, disambiguations answered, the settings' look
    writing nothing, a track's own title, pressings oldest first and capped at 100, a pressing's title kept only
    when not the album's, credit_name trimmed, each backfill's count its own, the trim's FTS merge.
  - **Figures**: the empty index is ~68 KB (17 pages; the notes said 40, the tests' comments 110); the image's
    SQLite checked (3.46.1, FTS5 with contentless_delete); the route added to docs/FRONTEND-MIGRATION.md's table.
  - Tests after review: Python 3114 collected (3112 passed, 2 skipped; 27 more, test_saved_search.py 78);
    searchList.sim +8 checks (kindArea, savedFor's index and `credited`, foldName's twin), search.sim 364 (+9: the
    kind view's late saved answer, the hold, asked once - after an answer and after `available: false` - the foot
    both ways). Mutations: 37 rules the fixes added or the review named broken one at a time, 37 caught (two missed
    on the first pass - the credited name filter, asked once after nothing to search - each test strengthened).
- **Second review** (4 findings, each reproduced first; `work/saved56-fixer2/mut/`):
  - **A kind view moved its Try again**: the hold and `kindArea` covered MusicBrainz's rows, not its failure. With
    Navidrome and MusicBrainz away, a letter typed and taken back drew the kept failure at once, then what's saved,
    asked at the pause, landed ABOVE it - Try again a row lower under the finger; and a 503 back before what's saved
    answered was drawn, then pushed down. Now the failure is held behind the asking line as the rows are (`mbHeld`
    counts `failed` as `done`), and once drawn `kindArea` takes below for it (`problem`, kept while it is asked
    again): a late saved row is drawn BELOW the failure (and below the asking line of its Try again), the failure's
    words as they were. search.sim pins both ways, searchList.sim the pure rule.
  - **The trim's `_in_step` untested**: the test's 60 "trimming" answers compressed to nothing and never trimmed.
    Now their titles don't compress, the file is checked trimmed with no stale mark, and reopened before Clear.
  - **The rollback test passed with the stale index kept**: .55's one answer after its Clear took rowid 1 again,
    and reading it in took the old rowid-1 mentions (Dummy's) away by coincidence. Dummy's answer is now rowid 2;
    and each trigger missing alone is shown to rebuild the index (three cases).
  - **`credited`'s 50**: tested - 60 saved albums of one artist, the 50 earliest kept, saved in reverse order.
  - Tests: Python 3118 collected (3116 passed, 2 skipped; test_saved_search.py 82); search.sim 371 (+7),
    searchList.sim +2. Mutations: 9 rules broken one at a time, all caught (the failure's `problem` kept while asked
    again is caught by searchList.sim alone).

### A short compose file, and every environment variable in one list (2.0.3)

James (2026-10-23): "can we prune the docker compose a bit so that most things default to a sensible value and can
be edited within the app? and then just a big list of available environment variables and what they do, how to use
them, etc." - right after the compose example lost its comment-only lines (2.0.0-player.68, notes/fixes-2.0.md),
whose rule still holds (`test_the_compose_example_has_no_line_that_is_only_a_comment`).

- **`docker-compose.example.yml` is what Docker needs and nothing else**: image, container name, restart,
  `env_file` (`.env`, `required: false` - after review, below), the three mounts (`/downloads`, `/music`, `/config`) and the optional `/incomplete` and `/cache`
  mounts commented out (each saying which setting to set to it, and on which Server settings page), the port. **No
  `environment:` block at all**: every setting Server settings can edit (Config.EDITABLE) starts at its default and is
  set there; and with no block, no line of it can beat `.env` - the empty-line trap (an empty `environment:` line
  beats `.env`) can't come from the example any more. compose refuses an `environment:` key with only a comment under
  it ("must be a mapping"), so the single commented pointer line the plan allowed for had nowhere to go; the pointer
  to the list rides on the `env_file` line's comment instead. Lines stay comment-on-the-line (.68's rule).
- **The image carries the two paths**: the dockerfile's ENV gains `SLSKD_DOWNLOAD_PATH=/downloads` and
  `LIBRARY_PATH=/music`, the container side of the example's mounts. Docker puts an image's ENV under the container's
  environment, so a value from `env_file:` or `environment:` replaces it, and Server settings' saved value beats both
  as for any setting - an install that mounted `/library` and set `LIBRARY_PATH=/library` reads `/library`
  (checked on a built image, below). The CODE keeps no default for either (`_env("LIBRARY_PATH")`, pinned by
  `test_the_code_keeps_no_default_for_the_two_paths_outside_the_image`): the dev setup and a plain
  `python -m src.main` stay as they were, organizing off until both are set. DB_PATH needed nothing - the code
  defaults it (and keeps an older jimbrainz.db). The entrypoint reads only PUID/PGID, and the HEALTHCHECK only the
  port, so neither moved. A setting the image sets shows in Server settings as "From the container environment" -
  true: the image's ENV is the container's environment, and nothing can tell it from a compose line of the same value.
- **An install without the mounts**: before, an image run with no `LIBRARY_PATH` had organizing off; now `/music` is
  set whether or not anything is mounted there. `ORGANIZE_MODE` still starts at `dry_run`, so nothing is written
  unless someone chose `copy`/`move`; then Settings → Library says "nothing exists at /music as seen from inside this
  container" and lists it among organizing's blockers, and filing would have to make `/music` at the root, which the
  unprivileged PUID can't: each file fails ("N file(s) failed to organize, no track was filed", the download left in
  slskd's folder) rather than landing in the container's own layer - checked on the test image, where
  `os.makedirs("/music/a/b")` as 1000:1000 is refused. Unless PUID is 0. Not guarded further, deliberately: a guard would change filing for anyone whose LIBRARY_PATH folder
  doesn't exist yet and is made by the first filing.
- **`.env.example` is the secrets and the environment-only settings**, every line commented out (an uncommented empty
  `LIBRARY_PATH=` is a value and would take the image's `/music` away): PUID/PGID, slskd's address and key, Navidrome's
  address, user and password, the three logins, TRUSTED_ORIGINS. **The two addresses ride with their secrets, beyond
  the plan's list, on purpose**: `_moved_without_secret` refuses a new address saved in the app without its secret
  typed in the same save, and refuses reverting a secret to the environment's while the address is not the
  environment's - so a key in `.env` with the address set in the app is a key that has to be typed into the app
  anyway. Kept together, both in `.env` or both in the app, it works either way; the file, getting-started and the
  README say so.
- **docs/configuration.md "Environment variables"**: how to give one (`.env`, or an `environment:` block you add;
  literal values; what wins; an empty value still counts as set, and beats `.env` and the image's default; a change
  needs the container recreated, not restarted), then
  three tables - set in the app (exactly Config.EDITABLE, each with its page and group), environment only (the
  logins, TRUSTED_ORIGINS, DB_PATH, the removed DEADWAX_ADMINS), the image's own (PUID/PGID; the two paths in prose).
  Each row: variable, default, where in the app, what it does, an example. `PYTHONUNBUFFERED` is the image's, for
  Python, and named in prose only.
- **Tests** (tests/test_compose_example.py, 9): the scan of what deadwax reads (`_env("X"`, `os.getenv("X"`,
  `os.environ`, the entrypoint's `${X:-`) finds every Config setting, TRUSTED_ORIGINS, DEADWAX_ADMINS and PUID/PGID;
  every variable read is a row of the list and every row is read; the tables split as Config.EDITABLE /
  NOT_EDITABLE do, the locked ones "shown, locked"; the list's defaults are the code's (nine read from config.py's
  source); no variable deadwax reads is set in the compose example, commented or not, and it has no `environment:`;
  the mounts' container sides are the image's ENV and DEFAULT_DB_PATH's folder; the code keeps no default for the
  two paths; `.env.example` names exactly its set, all commented. Rewritten on purpose: test_logins' example-files
  test (no environment: block, no login line in compose, the three in .env), test_musicbrainz_disk_cache's (the
  /cache mount names both settings and their pages, neither file sets them, the list carries both), and
  test_settings_words' AUTO_RETRY_PEER words (read from configuration.md's row now that `.env.example` doesn't carry it).
- **Verified**: Python 3666 collected (3664 passed, 2 skipped; 9 more than 3657); pyflakes, tsc, all 62 sims and the
  build clean; the engine files without a diff. `docker compose config` accepts the example with an empty `.env`
  (and, as first built, refused it with none - changed after review, below), and with `.env.example` copied in. A test image
  (`deadwax-compose203-test:local`, removed after) carries both ENV defaults; run from the example (paths swapped for
  scratch folders, port 8110) it came up healthy, Server settings showing `/downloads` and `/music` ok "from the
  container environment" and organizing blocked only by dry run; run with `LIBRARY_PATH=/library` and
  `SLSKD_DOWNLOAD_PATH=/data/downloads` under `environment:` it read those. Mutation-checked: 16 rules broken one at
  a time (an undocumented `_env`, a setting in compose set or commented, the image's ENV dropped, a code default, an
  uncommented or editable `.env.example` line, a wrong default, a row dropped or misspelled, a locked row as editable,
  a mount moved, `env_file` dropped, a login line, the /cache comment's names, the retry row's words), each caught,
  each file restored and compared. NOT verified: Komodo's own deploy of the new example (that its stack Environment
  lands in the `.env` the example's `env_file` reads is from Komodo's documented default, not watched here).
- **After review** (eight findings, each reproduced before its fix; tests/test_compose_example.py 9 -> 15):
  - **A restart keeps the old environment**, so every place that said "change it in compose and restart deadwax"
    now says recreate the container: configuration.md's Logins section and its DEADWAX_SECRET_KEY row (both link
    `#how-to-give-one`), troubleshooting's key and DB_PATH lines, sharing's key step - and the app's own words, which
    said the same: `LOGINS_LOCKED` (the locked logins rows), `auth.unusable()`'s missing key and
    `describe_logins_organizing()`'s two. `test_an_environment_change_is_never_said_to_need_only_a_restart` holds
    every doc sentence saying "restart deadwax" to also saying recreate, and those four messages to it.
  - **`env_file` is optional** (`- path: .env` / `required: false`, Compose 2.24+): a required one stops a deploy
    before deadwax can log a word when there's no `.env` - and a Komodo stack with an empty Environment may write
    none (whether it does is still NOT watched). `docker compose config` (v5.3.1) accepts it with no `.env`, an
    empty one and `.env.example` copied in, and a `.env` with values still reaches the container's environment. The
    "compose refuses a missing one" wording is gone from the README, getting-started, configuration.md and
    `.env.example` (`test_the_compose_example_s_env_file_is_said_to_be_optional_everywhere`); the README's Komodo
    paragraph says so too.
  - **Trimming an old compose file, in an order that works**: getting-started said to save each setting in Server
    settings first, then take its line out - but `editedEnvDraft` drops a draft equal to the value shown, so typing
    compose's value in saves nothing, and taking the line out then loses it (ORGANIZE_MODE back to dry_run, which
    with logins on 503s every route, Server settings included). Now: the line out, recreate, set it again; an address
    with its key; and with logins on ORGANIZE_MODE and the Navidrome lines stay (or logins off while trimming).
    The 2.0.3 release notes' Upgrading must say the same.
  - **.env.example's AUTH_MODE comment says to set Organizing (and Navidrome) BEFORE turning logins on** - with
    them on and organizing dry run, nothing can be reached; configuration.md's AUTH_MODE row likewise.
  - The README's settings paragraph named PUID/PGID as shown-but-locked; they aren't rows at all. It now names
    DB_PATH and the three logins as locked and PUID/PGID and TRUSTED_ORIGINS as environment only.
  - getting-started step 7 said to uncomment the Navidrome lines in `.env.example`; it's `.env`, then recreate.
  - The defaults test now also checks the defaults the code computes (PLAYER_CACHE_MB's and MUSICBRAINZ_CACHE_MB's
    constants, naming's DEFAULT_ALBUM_FOLDER, DEFAULT_DB_PATH) - before, a wrong PLAYER_CACHE_MB row passed.
  - This write-up's own summary said an empty value is not set; it is (os.getenv gives "" for `NAME=`).
  Python 3672 collected (3670 passed, 2 skipped); pyflakes, tsc, every sim and the build clean; the engine files
  without a diff. Mutation-checked: 18 of the fixes undone one at a time, each caught by its test, each file restored.
- **After review, second round** (one finding, reproduced first: `Config.check()` with SLSKD_URL and SLSKD_APIKEY
  only saved in Server settings logged both as missing): **slskd was judged before the overrides existed.**
  `check()` runs in `src/main.py` before the lifespan lays Server settings over the environment, so an slskd set up
  in the app - the way the short example now leaves it - was logged to the app's Log as "SLSKD_URL is unusable (not
  set) ... set it in your compose file" on every start while it worked, and troubleshooting.md then sent the reader
  back to compose. MusicBrainz and Navidrome were moved out of `check()` for this reason long ago; slskd was not,
  since it was normally in compose. Now `Config.report_slskd()` runs in the lifespan after `apply_overrides()`,
  beside `report_musicbrainz()` and `report_navidrome()`, and says the address, the key, the two paths and the
  organize mode there - with the source "Server settings" for a saved one, and Server settings named first in the
  "not set" lines. `check()` keeps only what is the environment's alone (empty values hiding `.env`, the legacy
  database, an unreadable ORGANIZE_MODE or COVER_ART_SIZE corrected in place). Tests in test_slskd_settings.py: no
  slskd line in the Log at start-up with slskd only saved, the "not set" line naming Server settings first,
  `check()` judging none of the five, and the lifespan's order.
  Python 3676 collected (3674 passed, 2 skipped); pyflakes, tsc, every sim and the build clean; the engine files
  without a diff. Mutation-checked: 5 of the fix undone one at a time (the lifespan call, the source, the words, the
  report back in check(), the key line), each caught.
