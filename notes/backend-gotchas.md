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
