# Last.fm

The design is `~/Desktop/Code/deadwax-plans/lastfm.md` (2026-11-24): its decisions, its sections 0-2 (Last.fm's API
as read, the setting, the server) and its slices. This file is what was built, slice by slice, and why it differs
where it does. James asked (24 Nov 2026) for an artist's ten most popular songs in the iPhone and Mac app; after
comparing Deezer, ListenBrainz and Last.fm for Tame Impala and Dance Gavin Dance: "last.fm looks great, let's use
that" - and, with a key in deadwax anyway, listeners, similar artists, radio from similar songs, albums by plays, and
Last.fm's descriptions first. His answers to the design's questions: Autoplay is off by default; About (descriptions
in the app) is built.

## S1 - the setting, the client, the keeping (2.1.36)

Nothing in 2.1.36 asks Last.fm: no route calls the client yet (`/deadwax/lastfm/artist` is S2, 2.1.41 - the manual
search took 2.1.37-2.1.40). What is
here is everything those routes stand on, and the recorder that settles what Last.fm really answers before S2 draws
anything.

### The setting: `LASTFM_API_KEY`

- **config.py**: `LASTFM_API_KEY = _env(...)` beside the fanart.tv keys; `EDITABLE["LASTFM_API_KEY"] = "lastfm"`;
  `Config.lastfm_key()` is the key stripped, or None - so a saved blank is no key, everywhere.
- **The row** (`_lastfm_row()` in src/routes/settings.py): Connections, after `FANARTTV_PERSONAL_KEY` and before
  MusicBrainz's rows; secret (only "set"); not in `ADMINS_ONLY` - like fanart.tv's key, it controls nothing.
  - `status: "error"` with Last.fm's words while the client holds a refusal: "Last.fm refused this key at {HH:MM}
    (error {n}: {message}) - check it's the API key, not the shared secret". HH:MM is the server's clock.
  - otherwise `status: "error"`, "doesn't look like a Last.fm API key (32 letters and digits) - check you copied the
    API key, not the shared secret" for a key that isn't 32 hex digits. **Stored all the same**: that keys are 32 hex
    is believed, not read anywhere official, so a wrong guess costs a flag, never a refusal. (A shared secret is 32
    hex too, so the flag can't catch that mix-up; only Last.fm's error 10 can.)
- **`_validate`** refuses only what can never be a key: a space or a control character inside it (after trimming the
  ends, so a paste's newline is fine) - "a Last.fm API key is one word - letters and digits, no spaces". `one_word()`
  counts anything `str.isprintable()` refuses, so a zero-width space is refused too.
- **The save hook** (`"lastfm"` in `update_settings`): any change - a save, a revert - lets a held refusal go; one that
  leaves no key (a blank saved, or a revert to an environment with none) empties `lastfm_kept`.
- **The app**: both Server settings draw every row the server sends. The iPhone app's `ServerSettingsGroupScreen`
  is a `ForEach(group.settings)` over Core's `ServerSetting` (ios/DeadwaxKit/Sources/DeadwaxCore/ServerSettings.swift,
  checked on `ios` at fcbb3bc), a secure field for any `secret` row, with no per-key list for third-party keys; the
  web's ServerSettings.tsx the same. So the row needed no app or ui/ change.

### The pure half: src/lastfm.py

- `classify(status, body, now, secret)` reads Last.fm's error JSON before the status, since Last.fm sends its errors
  with varying statuses. 3xx is Unreachable (never followed), 429 Limited; then `error` 6 NotKnown, 10 and 26 Refused,
  29 Limited, any other code Unreachable; then a non-200 Unreachable, and anything but a JSON object Unreachable.
  An `error` given as a string of digits is read as its number.
- The outcomes are frozen dataclasses returned, never raised: `Answer`, `NotKnown`, `Refused(error, message, at)`,
  `Limited`, `Unreachable(why)`. `why` is always deadwax's own words.
- `cleaned()` is how a Last.fm message is kept: the key taken out (should Last.fm ever echo it) in any case -
  `without()` replaces it case-insensitively since 2.1.41's review, a key being hex Last.fm could quote back in
  capitals - control characters out, one line, at most 200 letters.
- **The match keys** (the design's 2.4), with the contract `tests/fixtures/lastfm/match-vectors.json`: 66 titles
  (57 until 2.1.43's dotted and dotless i - S4), 27 names. `stripped` and `first` are hand-written in `tests/fixtures/lastfm/export-vectors.cjs`; each `key` is what
  the web's own TypeScript answers - songs.ts `titleKey(stripped)`, owned.ts `foldName(name)` - compiled as the sims
  compile it. `tests/test_lastfm_vectors.py` holds `strip_title`, `title_key`, `match_key`, `name_key` and
  `first_credit` to it, and asserts the iPhone app's copy (on `ios`, under
  `ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lastfm/`) is byte-equal - skipped where there is none, as on main.
  - `title_key`/`name_key` port the TypeScript line for line. JavaScript's `\s` (its WhiteSpace and LineTerminator
    set) and `\b` (ASCII word letters, plus U+017F and U+212A under the `iu` flags) are spelled out, since Python's
    differ; `\p{L}`, `\p{N}`, `\p{M}` are `unicodedata.category`. Characters outside ASCII are written as `chr()` in
    the source, never escapes the file tools would turn raw.
  - Steps 1-3 (`strip_title`) exist only in Python (and later Swift), so they use Python's own `\s` and `\b`. Two
    things the design left open, decided here and pinned by vectors: a feature tail (" feat. X") is dropped only
    outside brackets ("Elephant (Remix feat. Someone Else)" stays whole), and dash takes are dropped **from the end,
    one segment at a time, outside brackets**, while the last segment holds a take word - so "Elephant - Live at
    Wembley - 2011 Remaster" is "Elephant", "Elephant - Part 2 - Live" is "Elephant - Part 2", and the first segment
    is never dropped ("Live Forever - Remastered" is "Live Forever").
  - Nothing runs `export-vectors.cjs --check` in CI yet: a change to titleKey or foldName needs the script run by
    hand, and the vectors then fail Python where it differs. A sim that runs `--check` would close that (it would
    touch ui/test, so it wasn't added in this slice).
- `LASTFM_SHAPE`: the first part of every kept row's key - 1 from 2.1.36, 2 from 2.1.43 (S4).

### The client: src/api/lastfm_endpoint.py

One `httpx.AsyncClient` (8 s, 5 s to connect, redirects not followed), `GET https://ws.audioscrobbler.com/2.0/` with
`method`, the method's parameters, `api_key` and `format=json`; `User-Agent: deadwax/<version>` and nothing of
MusicBrainz's agent, whose email Last.fm doesn't ask for. The answer is read a piece at a time and refused past 512 KB.

- **The key never leaves the request.** The client never `str()`s an httpx exception (its words carry the URL);
  `Unreachable` says the exception's class name. Its log lines name the method and deadwax's own reason. httpx's own
  request lines are kept out by src/logger.py's WARNING level on `httpx`. A refusal's message is `cleaned()` of the
  key. `tests/test_lastfm_client.py` runs 14 kinds of answer - an answer, not known, refused 10 and 26, limited 29 and
  429, error 8, a 5xx, not JSON, a redirect, too big, a connect error, a timeout, a fault - with a sentinel key
  echoed in every message, header, page and exception Last.fm (the fake) can put it in, and searches every log record,
  the event log, the outcome's words, the settings answer and `/deadwax/me` for it.
- **Pace**: at most 5 requests begun in any one second and 4 under way; a request waits its turn up to 2 s, then is
  `Unreachable("busy")`. **Departure**: a sliding window of start times, not a token bucket. A bucket of 5 refilling
  5 a second lets up to 9 begin inside one second (5 at once, then one each fifth of a second); the window never lets
  a sixth begin within a second of the first, which is what "at most 5 a second" means. The wait looks again every
  50 ms (`TURN_TICK_S`); nothing is awaited between looking and taking a turn, so two asks can't take one.
- **Each answer as a whole is bounded at 8 s too** (`FETCH_DEADLINE_S`), beyond httpx's per-read timeout, so an answer
  trickling in can't hold one of the 4 turns. The design says "8 s"; this reads it as the whole answer, as the AutoEq
  client does.
- **Limited** (29, 429): nothing goes out for 60 s, each ask `Unreachable` at once; said once per pause, at info, in
  the container's log only.
- **Refused** (10, 26): held in memory as the `Refused` itself (error, message, when). While held - an hour, or until
  the key is saved, reverted or removed (`forget_refusal`, the save hook) - each ask is that `Refused` at once, nothing
  sent. After the hour, **one** ask tries again (`_retrying`); the rest are still `Refused` until it answers. An
  answer or a not-known lets the refusal go ("Last.fm takes LASTFM_API_KEY again", info); a refusal again holds it
  another hour and says so at info only. The event log hears it **once**, as the refusal is first held:
  "Last.fm refused LASTFM_API_KEY (error {n}: {message}): top songs, similar artists and radio are off until it's
  fixed in Server settings." (the design's words, ahead of those features).
- **An answer for a key since replaced** changes nothing: `ask()` settles an outcome only while the key it was asked
  with is still the key. Otherwise a slow refusal of the old key, landing after a save, would mark the new key refused.
- `state()` is `/deadwax/me`'s `lastfm`: "off" with no key, "refused" while a refusal is held, "on" otherwise. After the
  hour it reads "on" again before the retry, since the retry is what the app's next ask would make.

### The keeping: src/lastfm_kept.py and store.py's `lastfm_kept`

- **The table** `lastfm_kept(key TEXT PRIMARY KEY, body TEXT, fetched_at REAL, used_at REAL, size INTEGER)` in
  deadwax's own database. `body` is deadwax's JSON, never Last.fm's raw answer (from S2 each route's parse); NULL is a
  kept "not known". `size` is the key's bytes plus the body's.
- **The keys**: `{LASTFM_SHAPE}|{method}|mbid|{mbid}` (lowercased), `...|name|{name_key(artist)}`, albums
  `...|name|{name_key(artist)}|{name_key(album)}`, tracks `...|name|{name_key(artist)}|{match_key(title)}` -
  `artist_key`, `album_key`, `track_key`, reading `LASTFM_SHAPE` at each call.
- **Standing** (`standing()`, pure): found under 7 days fresh; 7-30 days answered at once and asked again behind;
  over 30 asked first. Not known under 3 days fresh, then asked first. **Whatever is kept is answered when asking
  fails** - Unreachable, Limited or Refused - at any age: the design's table says so for over 30 days, and its
  section 2.9 says kept answers of any age are served while Last.fm is down or refusing; applied to "not known" past
  3 days too, which the table left as "-".
- **One ask per key**: `Keeper.asking` holds each key's ask as a task; a second ask, or a refresh behind, joins it.
  So "a refresh behind runs at most once per key" is read as **at most one at a time**, the same mechanism; a refresh
  behind that fails is said at info and changes nothing, and the next read of the still-stale row starts another.
  Callers wait through `asyncio.shield`, so a page that stops waiting (S2's 4 s deadline, a closed connection) doesn't
  cancel the ask: its answer is still kept. `stop()` cancels what is under way, in the lifespan's shutdown.
- **Never kept**: Unreachable, Limited, Refused. A fault in deadwax reading an answer (S2's parsers) is logged at
  warning and answered `Unreachable`.
- **Size**: a row over 32 KB isn't kept (still answered). At start-up and every 100th answer kept, the table is
  trimmed past 50 MB (`LASTFM_KEPT_BYTES`) down to 45 MB, used longest ago first - so between trims it can pass 50 MB
  by at most 100 rows of 32 KB (3.2 MB). `lastfm_get` moves `used_at` to now when it is an hour
  or more old - "used" means read, and the hour keeps a page's every part from being a write each visit.
- **Emptied**: at start-up with no key (`at_start`, after the overrides); by the save that leaves no key. At start-up
  with a key, rows of any other shape are dropped - **an addition**: the design only has old shapes never read; this
  also gives their bytes back instead of waiting for a trim.

### `/deadwax/me` and the sign-in

`/deadwax/me` answers `lastfm`. **So does the sign-in's answer** (src/routes/auth.py), which documents itself as "what
GET /deadwax/me answers" - an addition the design didn't name, to keep that true.

### The recorder: tests/fixtures/lastfm/record.py

Built from `~/Library/Caches/deadwax-build/topsongs/lastfm.py`. Standard library only, and loads on the Mac's own
Python 3.9 (`from __future__ import annotations`). James runs it once:

    LASTFM_API_KEY=<key> python3 tests/fixtures/lastfm/record.py

It records 32 answers into `tests/fixtures/lastfm/recorded/`: the four artist methods by MusicBrainz id and by name
(autocorrect) for Tame Impala, Dance Gavin Dance and Portishead; album.getInfo for Portishead's Dummy;
track.getSimilar for "Let It Happen"; an unknown name (getInfo, getTopTracks); an unknown MusicBrainz id
(getTopTracks); a misspelling ("Tame Impla", with and without autocorrect). Each file holds the method, the
parameters (never `api_key`), the status, `Cache-Control`, `Expires` and `Content-Type`, and the answer as it came -
errors too, since what an unknown artist answers is one of the questions. The key, and its address-encoded forms, are
replaced by `<LASTFM_API_KEY>` wherever they appear; each file is checked before it's written and every file read back
at the end, and if the key is in any of them every file written is removed and the run fails. At the end it prints
the Cache-Control and Expires values it saw: the design's one number allowed to move after recording is the fresh
time, if Last.fm's headers say less than 7 days. **It follows no redirect** (`NoRedirects`, in place of urllib's
own): the key is in the address, so a 3xx is recorded as it came - its `Location` with the key taken out - and the
run stops there, saying so, exit status 3. `tests/test_lastfm_record.py` runs it offline through its real opener,
with Last.fm as a urllib handler ahead of urllib's own that echoes the key in answers, error messages, headers and a
non-JSON page - and answers 301, 302, 303, 307 and 308 to an http:// address and to Last.fm's own.

The recorded files are committed with S2; until then every test here uses answers shaped from Last.fm's API pages,
said so in each test file.

### After review

A review of the first commit found seven things, each fixed with a test seen failing on the fault first:

1. **The recorder followed redirects with the key.** urllib's default opener follows 301-308, https to http included.
   Now `NoRedirects` refuses them all, the 3xx is recorded and the run stops (above). Its tests run the recorder's own
   opener, so they can't pass while the default follows one.
2. **Asks waiting their turn ignored a 29 or a refusal** that came while they waited: 8 at once, the first answered
   29, and the 4 waiting went out anyway. Each look for a turn now asks `_stopped()` first, with nothing awaited
   before the turn is taken: the pause, a refusal (the retrying ask aside) or a key removed or replaced since the ask
   began, and nothing is sent.
3. **A lone surrogate in an answer made `kept()` raise** (`.encode()` of the `ensure_ascii=False` text, outside any
   try). Answers are written as ASCII now - a lone surrogate survives the round trip - and all of keeping is inside
   one guard: whatever fails is said at warning and the answer still answered. `store.lastfm_put` measures inside its
   own try. A refresh behind whose keeping fails is said too (it was silent).
4. **The 50 MB cap held only within one run**: the trim counts answers in memory and deadwax restarts with every
   update. `at_start` trims too.
5. **An answer arriving after the key was removed was still kept.** The keeper reads the key as it asks and keeps
   nothing if the key has changed (removed or replaced) by the time the answer comes; and one being written as the
   key is removed is emptied again after the write, since the save's emptying runs on a thread of its own and can
   land first.
6. **The pace used the wall clock.** The one-second window, the 60 s pause and the hour's hold are timed on
   `time.monotonic` (`monotonic`, `refused_since`). The wall clock (`clock`) is only the refusal's `at`, its HH:MM in
   Server settings. The tests' wall clock starts on an epoch of its own, as far from the monotonic one as
   `time.time()` is in production, so any clock mixed up anywhere fails.
7. **A failed refresh behind was logged once per visit it served**: each stale read added its own callback. The
   callback is now the new task's alone.

### Verified, and not

- Verified, by the tests (no Last.fm was asked; there is no key here): everything above against httpx's
  MockTransport and fake clocks - the pace with a virtual clock that only moves when every task waits, so the
  per-second and in-flight counts are exact rather than timing-dependent.
- **Not verified**: anything about real Last.fm. That error 6 is what an unknown artist answers; that keys are 32 hex;
  how Last.fm sends its errors' HTTP statuses; its cache headers; its real rate limit (5 a second is the older terms'
  figure, remembered). The recorder settles the first four.

## S2 - an artist's listeners and top songs: `GET /deadwax/lastfm/artist` (2.1.41)

For the iPhone and Mac app's artist page (slice A1 draws it). The web app doesn't call it, and nothing on the web
changes. `src/routes/lastfm.py`, a user's route (tests/test_logins.py ROUTES), included under `/deadwax/lastfm` with
`current_user`; the pure half in `src/lastfm.py`.

### The answer

    {"enabled": true, "unavailable": false, "why": null,
     "url": "https://www.last.fm/music/Tame+Impala", "listeners": 4724887,
     "top_songs": [{"title": "The Less I Know the Better", "playcount": 51995043, "listeners": 2955438,
                    "url": "https://www.last.fm/music/Tame+Impala/_/The+Less+I+Know+the+Better"}, ...]}

- **Query**: `mbid` (MBID_PATTERN) and/or `name` (1-200, trimmed), at least one, else a 422 in words. Both declared,
  so neither is dropped; an undeclared `artist=` alone is a 422, as the tests show.
- **Two parts, asked at once**, each through `kept()`: artist.getInfo (`url`, `listeners`) and artist.getTopTracks
  (`limit=50`). By mbid first (no autocorrect); a `NotKnown` by mbid asks by name with `autocorrect=1`, kept under the
  name. With no mbid, by name. **The parameters are exactly record.py's**: the tests' stand-in Last.fm answers only a
  request whose method and parameters match a recorded file, so a request record.py doesn't record fails the test.
- **`ARTIST_DEADLINE_S` = 4 s.** A part not in by then is `null` with `unavailable: true`. The part is left running,
  never cancelled by the page, so its answer is kept when it lands, and so is a by-name ask it still has to make. The
  tasks are held in a set (asyncio keeps only weak references). `routes/lastfm.stop()` cancels them in the lifespan,
  before `lastfm_kept.stop()`.
- **`similar` and `top_albums` are S4's**: until then they aren't in the answer at all. A `null` would say "couldn't
  be had", which isn't what they are. (In the answer since 2.1.43: "S4" below.)
- **`why`** follows Explained's rule: words for whoever runs deadwax, sent to everyone, drawn by the app only for
  `seesDetail`. With no key it is the design's "No Last.fm API key is set - add LASTFM_API_KEY in Server settings >
  Connections (a free key from last.fm/api/account/create)." While the client holds a refusal (`lastfm.held()`, or
  a part that came back Refused) it is "Last.fm refused deadwax's API key (error {n}: {message}) - check
  LASTFM_API_KEY in Server settings > Connections: it's the API key, not the shared secret." Otherwise `null`: a blip
  has none.
- **`url`** is getInfo's, else the top tracks' artist's. Every address passed on is https on last.fm or a host under
  it (`lastfm.lastfm_url`), and since the review also printable ASCII with no space, no `\` (a browser reads it as
  `/`, so `https://evil.example\.last.fm/x` is evil.example's page, though urlparse's host ends `.last.fm`) and no
  `@` (whatever is before it a user name), at most `URL_MAX` = 2048 letters. Last.fm's are percent-encoded: all 1,702
  addresses in the recordings (every `url` and `href`) pass as they are, the longest 117 letters. That is now the ONE
  rule: `descriptions.from_navidrome` uses it in place of its own inline check. The behaviour is the same, except
  that a non-string `lastFmUrl` or an unparseable address no longer raises, and the new letters are refused there too.

### Decided here (the design left these open)

1. **An artist Last.fm doesn't know** has `top_songs: null`, not `[]`: `[]` is "known, but lists nothing" (2.5).
   `unavailable` stays false, since a `NotKnown` is a definite none. Its `listeners` and `url` are null too.
2. **Refused with nothing kept**: `enabled: false`, and `unavailable: true`, so the app keeps the answer only a moment
   and a fixed key shows at the next visit. With something kept, `enabled: true`, the kept parts, and `why` still in
   refused words.
3. **A failure by mbid isn't a "not known"**: Unreachable, Limited or Refused by id asks nothing by name, since Last.fm
   is the trouble, not the id.
4. **A name that folds to nothing** (`name_key("!!!")` is `""`) is never asked by: every such name would share the one
   kept row `1|method|name|`. With an mbid, the id is still asked.
5. **An answer that can't be read** (a 200 without `artist` or `toptracks`) is Unreachable and never kept, logged at
   info. A fault in parsing is the keeper's warning, and still a part not had. Nothing reaches a 500.

### The kept shapes, and LASTFM_SHAPE

**Not bumped: still 1.** Nothing was kept before 2.1.41 (S1 had no route), so no row has another shape.

- **artist.getInfo**: `{url, listeners, bio: {summary, content}}`, the bio as Last.fm wrote it (HTML). The bio isn't
  in any answer yet. It is kept now so S3's Last.fm descriptions read this same row, as the design's 2.8 says ("the
  same kept row as 2.5"), rather than bump the shape. Kept rows, measured over the recordings (the JSON as
  lastfm_kept writes it, plus its key): **201 bytes to 4.7 KB** - the misspelling's page 201 B (no bio content),
  Portishead's 1.7 KB, Dance Gavin Dance's 4.3 KB, Tame Impala's 4.7 KB (its content cut from 10,843 letters).
- **The bio's cuts, and why a getInfo row always fits** (the review): the content at most `BIO_MAX` = 4000 letters
  and the summary at most `SUMMARY_LETTERS` = 1500 (descriptions.MAX_LETTERS, the most S3 shows) - and each then by
  what it takes WRITTEN, since a kept row is ASCII JSON, where a letter outside ASCII takes 6 bytes and one outside
  the BMP 12: `CONTENT_BYTES` = 13 KB and `SUMMARY_BYTES` = 9 KB (1500 letters of any script in the BMP; 768 of one
  outside it, 1,109 of content). Whole letters only, never half a pair. With the address at most 2 KB and the key at
  most 6,622 bytes - a name of the route's 200 letters folds to at most 33 bytes a letter (U+FDFA is 18 letters in NFKD;
  `test_a_getinfo_row_always_fits_the_keeping` tries every letter NFKD changes) - and under 100 bytes of the rest,
  the largest row there can be is 31,269 bytes (30.5 KB), under ROW_MAX_BYTES' 32 KB. `test_the_largest_info_row_there_can_be_is_kept`
  runs that row through the route and finds it kept. The first cut, 4000 letters each by letters alone, could have
  made a row of 96,000 bytes of letters outside the BMP: answered, but never kept.
- **artist.getTopTracks**: `{artist_url, top_songs}`, **already folded** - the design's "parsed to deadwax's shape
  (2.5)", and a row of 1.2-1.7 KB instead of Last.fm's 53 KB. So **a change to the fold (TOP_SONGS, match_key, the
  vectors) is a change of the kept shape, and must bump LASTFM_SHAPE**: src/lastfm.py says so beside each.
  `test_the_kept_shape_has_not_moved` pins the fields, and **`test_what_is_kept_changes_only_with_lastfm_shape`**
  pins what they hold: `KEPT_SHAPES` pairs each shape with a digest of what is kept - artist_info and top_tracks over
  every recording, the fold over a list of titles it has to decide (`FOLD_CASES`), a bio cut by its bytes, TOP_SONGS
  and the caps. A change to any of them without a bump fails, saying to bump LASTFM_SHAPE and add the new pair. A
  recording made again changes the digest too, with nothing to bump: the message says to replace that shape's.
- A kept row is read back as carefully as an answer: counts through `count()`, addresses through `lastfm_url()`.

### The fold: `top_songs()`

Last.fm's order. A track whose name trims empty, or whose `match_key` is empty ("???"), is dropped. A repeat of a
`match_key` is dropped, the higher rank winning. The first `TOP_SONGS` (10). Titles as Last.fm wrote them, ends
trimmed. Counts are read loosely by `count()`: an int, an integral float, or a string of ASCII digits (at most 18).
Never a bool, a negative, a fraction or words, and nothing that makes `int()` raise.

**What it gives for the recordings (2026-11-25), title and playcount** - by mbid and by name alike:

- **Tame Impala**: The Less I Know the Better 51,995,043 · Borderline 31,962,438 · New Person, Same Old Mistakes
  26,439,766 · Let It Happen 28,648,847 · Feels Like We Only Go Backwards 20,213,973 · Eventually 21,238,581 · Nangs
  14,543,108 · Elephant 12,610,679 · Yes I'm Changing 13,095,273 · Dracula 14,724,597. **Nothing folded**: the 50
  have 50 different keys.
- **Dance Gavin Dance**: We Own the Night 4,457,241 · Uneasy Hearts Weigh The Most 3,868,294 · And I Told Them I
  Invented Times New Roman 2,696,274 · Lemon Meringue Tie 2,355,705 · Death of a Strawberry 2,189,374 · Blue Dream
  2,172,176 · It's Safe to Say You Dig the Backseat 1,265,400 · The Backwards Pumpkin Song 1,270,182 · Betrayed by
  the Game 1,412,033 · Open Your Eyes and Look North 1,004,431. **Nothing folded** either, and no feature credit in
  the 50: the case the design feared for DGD doesn't arise in its top tracks.
- **Portishead**, the one recording with repeats: "Glory Box - Live" (#34), "Sour times - Live" (#45) and "All Mine -
  Live" (#50), 47 songs in its 50. All three are past the ten, so they fall away with the rest and the fold never
  shows. Its ten: Glory Box, Roads, Sour Times, Mysterons, Wandering Star, Strangers, It Could Be Sweet, Numb, The
  Rip, All Mine.
- So **in every recording the ten are Last.fm's first ten tracks as they are**: no recording shows the fold at work.
  The inline tests do: `test_ten_songs_not_ten_tracks` (12 tracks, #3 a "- Live" take of #1, so #11 is the tenth
  song - the review found nothing failed when the fold ran over the first ten tracks only), and the case, feature,
  remix and edit tests.

The plays aren't in order because **Last.fm ranks top tracks by listeners, not plays**: listeners descend down all
three lists of 50, plays don't (Let It Happen has more plays than New Person, Same Old Mistakes but fewer
listeners). deadwax keeps Last.fm's order. So the README and docs say "most popular", not "most played".

### What the recordings settled (record.py, 2026-11-25)

James ran the recorder twice. The **first run used a key Last.fm didn't accept**: all 32 answers were **HTTP 403**,
`{"message": "Invalid API key - You must be granted a valid key by last.fm", "error": 10}`. One is kept as
`tests/fixtures/lastfm/refused-invalid-key.json`, which the second run's overwrite doesn't touch. The tests hold that
the client classifies it as Refused, and that the route answers it `enabled: false` with the refused `why`. **The
second run** (02:25Z, the right key) is `tests/fixtures/lastfm/recorded/`, 32 files, checked to hold no key, committed
with S2:

- **Every answer is HTTP 200, errors included.** An artist Last.fm doesn't know answers **HTTP 200 with error 6**,
  `{"error": 6, "message": "The artist you supplied could not be found", "links": []}`. That holds for an unknown name
  (getInfo, getTopTracks) and an unknown mbid (getTopTracks). So **NotKnown for error 6 is confirmed**. classify()
  reading the error before the status was right twice over: 6 comes with a 200, 10 with a 403.
- **No `Cache-Control` or `Expires` at all**, only `Content-Type`. So the design's 7 days fresh stands: the one
  number allowed to move after recording doesn't move.
- **Numbers are strings** (`"listeners": "4724887"`), as the design read them.
- **Sizes**: top tracks about 53 KB raw (50 tracks); getInfo 8.7-18.7 KB (Tame Impala's bio content is 10,843
  letters); the largest file is 135 KB (track.getSimilar, S5's). All are under the client's 512 KB.
- **A track's `mbid`** is filled for 49 of Tame Impala's 50, 46 of Dance Gavin Dance's and of Portishead's, and none of
  the misspelling's 9 (the design's open question; the match stays by title, decision 7).
- **`autocorrect=1` doesn't correct "Tame Impla"**: Last.fm has a page under the misspelling (9 listeners, no mbid,
  nine songs scrobbled as typed - "eventually", "let it happen"), and answers it with autocorrect or without. So by
  name, deadwax gets whatever page Last.fm has under that exact name. The app asks by the MusicBrainz name, so this
  bites only for a name misspelt there, or an artist with no mbid whose tags are misspelt.
- **By mbid and by name** gave the same answers for all three artists.
- **For S3**: a bio's `summary` ends `<a href="https://www.last.fm/music/...">Read more on Last.fm</a>`, and its
  `content` ends "... Read more on Last.fm</a>. User-contributed text is available under the Creative Commons By-SA
  License; additional terms may apply." That is the licence sentence as the design remembered it. A content past
  BIO_MAX is kept without that tail.

### Fixtures

- `tests/fixtures/lastfm/recorded/` (Last.fm's own) is what tests/test_lastfm.py's `ANSWERS` points at, and what the
  route tests' stand-in Last.fm answers from.
- **No shaped files are left.** S2 was first built over files shaped from the API pages (`shaped/`). Once the
  recordings came they were removed, since every case they held is either in a recording now or held inline. What no
  recording shows is inline, marked `SHAPED` or `shaped_track`:
  - the fold's own cases: a case variant, an exact repeat, a feature aside or tail, a "with" aside, a remix or an edit
    kept apart, an empty or punctuation-only name, one track given as an object;
  - bad fields: counts missing, in words or otherwise odd, and a plain-http address;
  - Last.fm down (503), limiting (29), answering junk or not JSON, slow;
  - a refusal that echoes the key;
  - getInfo for an unknown mbid, which record.py doesn't record. It is given Last.fm's recorded not-known answer for an
    unknown name (`NOT_KNOWN`).
- `tests/test_lastfm.py test_the_recorded_answers_fold_to_these_songs` pins the lists above, the one test a new
  recording changes. The others assert what holds for any answer: first of each key, Last.fm's order, at most ten,
  counts and addresses read as the parse reads them.

### The app's fixtures: `tests/fixtures/lastfm/answers.py`

The plan's S2 exports the shared answers for the app (`ios/.../Fixtures/lastfm/answers/`). On main nothing is
written under `ios/`. The exporter lives beside record.py, and **is run on the `ios` branch** after merging main:
`.venv/bin/python tests/fixtures/lastfm/answers.py` writes
`ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lastfm/answers/artist.json`. `--out DIR` writes elsewhere; `--check`
compares, exit 1 when it differs. Its nine cases each run the whole app with a fresh store, over the recorded
answers:

1. Tame Impala by id
2. Dance Gavin Dance by id
3. Portishead by id (ten top songs, its three live takes past them)
4. an unknown id asked again by name
5. an artist Last.fm doesn't know
6. getInfo failing
7. Last.fm down
8. the real refusal
9. no key

The file says `"fixtures": "recorded"`. tests/test_lastfm_routes.py checks that it runs, that every case is a 200 in
the route's shape, and that `--check` passes on what it just wrote and fails on anything else. It holds the app's copy
byte-equal to a fresh run, a test skipped where the copy is absent, as on main.

### Tests, and the mutations they catch

- tests/test_lastfm.py: the parse and the fold, over the recordings and inline.
- tests/test_lastfm_routes.py: the route, through start() with a real store and the module's client and keeper.
- tests/test_logins.py: ROUTES gains the route as `user`, plus a signed-out 401 test with a key set, in which Last.fm
  is never asked.

The plan's S2 mutations, and a few more, were each put in alone and the Last.fm, logins and describe tests run; all
are caught:

- **fold**: a duplicate kept; a case variant kept; a feature not folded; a remix folded into its song; an empty name
  kept; more than 10.
- **fallback**: mbid's NotKnown not asking by name.
- **parse**: listeners as a string not read; listeners read with `int()`, crashing on absent or words.
- **degrade**: one part failing taking the answer down; one part failing being a 502.
- **deadline**: none (the page waits for every part); 8 s not 4; a late part cancelled. The first run missed the last
  one: cancelling a part whose by-id ask was still out changed nothing, since that ask is shielded and is kept anyway.
  `test_a_late_part_goes_on_to_ask_by_name_and_that_is_kept_too` now catches it - what a cancel loses is the by-name
  ask after a late NotKnown.
- **no key**: asked anyway; no `why`.
- **refused**: `enabled` with nothing kept; no `why`.
- **addresses**: any host passed on.

The review's six (2.1.41, before its commit), each with its test. Their mutations were put in alone, the Last.fm,
logins and describe tests run, and every one caught:

- **the fold over the first ten tracks** (`for track in tracks[:TOP_SONGS]`), which passed every test before:
  `test_ten_songs_not_ten_tracks`, and the digest test.
- **what is kept changed with LASTFM_SHAPE left** - TOP_SONGS 11; a song's plays read from its listeners;
  `CONTENT_BYTES` 12 KB, which only `test_what_is_kept_changes_only_with_lastfm_shape` catches - each failing that test
  with its "bump LASTFM_SHAPE in src/lastfm.py, and add 2: '...' to KEPT_SHAPES".
- **a `\` let through**, and **an `@` let through**: `test_an_address_is_passed_on_only_when_it_is_https_on_last_fm`.
- **the key taken out in its own case only**: `test_the_key_is_taken_out_in_any_case`, and the client's leak test's
  new `refused 10, in capitals` (which now looks for the key in any case).
- **the bio cut by letters only**: `test_a_bio_is_cut_by_what_it_takes_written_too` and
  `test_a_getinfo_row_always_fits_the_keeping`.

The sixth was CLAUDE.md's map, which now names src/lastfm.py, src/lastfm_kept.py, src/api/lastfm_endpoint.py and
src/routes/lastfm.py.

### Verified, and not

- **Verified by the tests**: everything above, over Last.fm's recorded answers through httpx's MockTransport. That
  covers the parse and fold of real answers, the request parameters (exactly the recorded ones), the real 403 refusal
  and the real error-6 not-known.
- **Not verified**:
  - deadwax asking the real Last.fm through this route. No call was made here; only record.py, on James's Mac, has
    asked it;
  - how long a cold `/lastfm/artist` takes, which decides how often A1's Top Songs lands below the albums;
  - Last.fm's real rate limit;
  - getInfo's answer for an unknown mbid (believed error 6, as its getTopTracks answered).

## S3 - descriptions, Last.fm first (2.1.42)

The web's artist page, album page and album you don't have: with `LASTFM_API_KEY` set, their description is
Last.fm's own words first, then Wikipedia's, then Navidrome's - James's order of 2026-10-24 ("Last.fm FIRST, Wikipedia
(via MusicBrainz) as the fallback"), which 2.0.13 could only meet through Navidrome's agents. The subtitle is
Wikidata's, as ever. **Without a key nothing changes**: `describe()` takes the very path it took before (the two sides,
`answer_of`, the same lookups), and tests/test_describe.py passes unchanged - its file has no diff. **ui/ has no diff**
either: `source` is "lastfm" for Last.fm's own words as for Navidrome's, so the link still reads "More on Last.fm" and
the answer's shape is the same.

### The route: src/routes/describe.py

- `describe()` asks `Config.lastfm_key()` first. With none it is 2.1.41's code, line for line. With one,
  `_described_lastfm_first()` gathers three sides at once - Navidrome's and the Wikipedia side as before, and
  `lastfm_side()` - and answers `descriptions.answer_lastfm_first(heard, row, said)`.
- **`unavailable`** is true if any side failed, Last.fm's included: down, limiting, refusing the key, or MusicBrainz
  failing the lookup the names come from. A "not known" (error 6), Last.fm's empty page, or an album with no names to
  ask by is a definite none, not a failure. None of them takes the description down: the others' words are said.
- **An artist**: S2's own `artist_part(store, INFO, mbid, None)` - the kept getInfo row the app's artist page uses, by
  id (no autocorrect), so one ask serves both, either way round (tested). A "not known" by id asks by the name
  `get_artist` gives - the Wikipedia side's own lookup, asked only then - with `autocorrect=1`, kept under the name.
- **An album**: album.getInfo by the release group's `title` and its artist credit as `artists.credit_name()` says it,
  `autocorrect=1` - exactly record.py's parameters - kept in `lastfm_kept` **under the release group's id**,
  `release_group_key("album.getinfo", mbid)` (`1|album.getinfo|group|<mbid>`; 7 days, a "not known" 3). **Fixed after
  review**: it was first kept under `album_key(...)`, the names folded by `name_key` - which drops a bracketed aside
  and a leading "The", so "Fearless" and "Fearless (Taylor's Version)", "Live" and "Live [Bonus]", "The Wall" and
  "Wall" shared one row: the first asked was shown for both for a week, and before a right Wikipedia paragraph. The
  album side always has its group's id, so the names are only what Last.fm is asked by. A title or artist that is
  empty, or longer than S2's `NAME_MAX` (200), isn't asked; one that folds to nothing ("!!!") now is - it shares no
  row any more. (Albums one artist gave one title - a band's self-titled ones - still get Last.fm's one page for
  it: that is Last.fm's page, asked by the same names.)
- **A deadline**: the Last.fm side is waited for `LASTFM_DEADLINE_S` (4 s, S2's `ARTIST_DEADLINE_S`) at most
  (`by_the_deadline`). **Added after review**: a Last.fm that takes the connection and doesn't answer held the whole
  description back 16-20 s, while Wikipedia's words were long ready. Past the deadline the side answers none and
  `unavailable`, and goes on: it is started through src/routes/lastfm.py's `started()` (S2's `_started`, made public,
  its log line made "a part of a page"), held in the same set and stopped with S2's late parts as deadwax stops - so
  it is never cancelled by the page, and what Last.fm answers is kept when it comes (the keeper's ask is shielded
  too). The next visit has it.
- **One MusicBrainz lookup** between the Wikipedia and Last.fm sides (`_once`): the first side that needs it starts it,
  the other awaits the same task. `request_with_retries` doesn't join two identical requests in flight, so without
  this a cold album asked both at once - two turns of the limiter for one answer (the test makes MusicBrainz take
  0.2 s, so a doubled ask can't hide behind the memory cache). With a key the album's lookup is
  `get_release_group_urls(mbid, credits=True)`, `inc=url-rels+artist-credits`: one lookup, a new cache key, so each
  album is asked once more, then kept a month as every lookup is. **Decided here**: the design has the inc change for
  everyone; it is asked only with a key, because without one "nothing changes" - and tests/test_describe.py pins
  `inc=url-rels` (`test_an_album_s_is_its_release_group_s_with_url_rels_alone`).
- An id of Navidrome's alone has no Last.fm side (artist or album): nothing to ask Last.fm by without MusicBrainz.
- `_asking` and `_part` in src/routes/lastfm.py are now `parsed_ask` and `artist_part`, the descriptions' too. No
  change to what they do.

### The words: descriptions.from_lastfm(body, kind), pure

Reads the kept shape: an artist's `bio`, an album's `wiki`; its `content`, else its `summary` (the first that has
words). Each field: cut at the **last "Read more on Last.fm" link** (descriptions.READ_MORE) - what follows it is
Last.fm's footer; the licence sentence dropped wherever it is anyway (`LICENCE`, any case, any spaces); read as text
(`_unmarked`, plain_text's own reading, split out of it with no change to plain_text); its prose only (`_prose`); a
field the keeping cut short ended at a sentence (`an_end`); `clean_text`, cut at MAX_LETTERS. None for no words, or a
disambiguation page. `url` is the answer's own page through `lastfm_url`.

**What the recordings show** (tests/fixtures/lastfm/recorded/, 2026-11-25 - all three artists by id and by name, the
misspelling twice, Dummy):

- **The licence sentence is as the design remembered it**, word for word: every content ends `... <a
  href="https://www.last.fm/music/...">Read more on Last.fm</a>. User-contributed text is available under the
  Creative Commons By-SA License; additional terms may apply.` - once, at the end. Every summary ends at the link: an
  artist's ` <a ...>Read more on Last.fm</a>`, an album's (Dummy's) with a full stop after it, `</a>.`; no summary has
  the licence. READ_MORE's existing `\.?` already took the album's full stop.
- **The link is Last.fm's plain `<a href="...">`**, never Navidrome's `target='_blank'` form, and the only tag in any
  of them.
- **The summary isn't 300 letters** (the design's 0.2, as read): 541-576 letters with its link (Dummy's 561). Each
  artist's is a whole-sentence prefix of their content; Dummy's is all of its content's words (a paragraph break
  made a space). Content first, as designed: the same start, longer.
- **The misspelling's page has no words**: summary ` <a ...>Read more on Last.fm</a>`, content `""`. from_lastfm
  says None, so Wikipedia's (or Navidrome's) words are said.
- **Dance Gavin Dance's content is two paragraphs of prose, then lists**: "Discography:" (a release a line),
  "All of Dance Gavin Dance's records...", "Band members:", "Touring members:", "Former Members:", "Former touring
  members:". Made one line and cut at 1500, as the design's rule has it, that read "... guitar licks and riffs.
  Discography: November 14, 2006 - Whatever I Say Is Royal Ocean May 15, 2007 - ... Tree City Sessions 2 (Live…".
  **Decided here, beyond the design**: `_prose` keeps the paragraphs (Last.fm parts them with a blank line) up to the
  first list that follows a real amount of prose, so DGD's says its two paragraphs (696 letters). **A list** (`_a_list`)
  is a paragraph of `LIST_LINES` (3) lines or more, two in three of them short (`LIST_LINE_LETTERS`, 80) and ending no
  sentence - DGD's discography is 26 such lines of at most 62 letters, its line-ups 3 to 11 ending in ")" - and it
  ends the words only after `PROSE_BEFORE_A_LIST` (200) letters. **Fixed after review**: as first written, any line
  break in any later paragraph stopped the words, so "Mogwai.\n\nMogwai are a Scottish post-rock band ...\nThey
  released ..." was said as "Mogwai." alone - and, Last.fm first, that beat Wikipedia's paragraph. A line break inside
  prose is no list now, and a list after a line or two doesn't end the words (they go on past it). A field whose FIRST
  paragraph is a list is said as it is. Tame Impala's (22 paragraphs, all prose) and Portishead's (two) aren't touched.
- **What is said**: Tame Impala 1,464 letters (its first paragraph and as much of the second as ends a sentence,
  from the content kept at BIO_MAX), Dance Gavin Dance 696, Portishead 812 (all of it), Dummy 482 (all of it).
- **No recording is a disambiguation page.** The rule is the design's and the review's, unverified against a real
  page. **Fixed after review**: as first written (`there (are|is|were) (at least X|multiple|...|N) (artist|band|act)s?`)
  it dropped real bios - "There were two band members in the first line-up" (`band\b` before " members"), "There are
  18 artists on this compilation", "There are many acts of kindness" - and missed "There are several different
  artists with this name: 1) ..." and a page that starts "1) ... 2) ...". Now (`DISAMBIGUATION`, `NUMBERED`), either:
  first words `there (are|is|were|have been)`, then artists, bands, acts, groups, musicians, singers, rappers or
  projects - plural, or "more than one" of them - **sharing a name**: `with / by / of / under / sharing / using /
  going by` + `this / that / the same / one / a` + `name`, or `named`, or `called`; OR numbered from its start, read
  with its lines before they are made one: `1)` (or `1.`) first, after one heading line ending ":" at most, then a
  `2)` (the same mark) after a space or a line break. Its tests are inline, marked WRITTEN FROM THE DESIGN and
  WRITTEN FROM THE REVIEW.
- **Last.fm's album mbid isn't the release group's**: Dummy's is `00163fb1-5ab7-4fec-b0dd-a915e2722340`, the group
  `48140466-cff6-3222-bd55-63c27e43190d` - so asking by names, as designed, was right. (Whether it is a release's id
  isn't checked: nothing here asked MusicBrainz.)
- **MusicBrainz takes `inc=url-rels+artist-credits`** on a release group: the review's one live GET for Dummy answered
  its `artist-credit` and all 9 of its relations (2026-11-25). The tests' credit is still SHAPED from the documented
  `artist-credit`, not recorded.
- **Album wikis come**: Dummy's has `wiki` (published, summary, content), which the API page's sample lacked.

**A field the keeping cut short**: S2 keeps a content's first BIO_MAX (4000) letters, or what fits CONTENT_BYTES
(1,109 letters outside the BMP), with no tail. Such a field has no link, so it may end mid-sentence or inside a tag;
its words would stop there whenever they are under MAX_LETTERS (an HTML-heavy content, or one outside the BMP).
`an_end` ends them at their last whole sentence in the second half (else the last word and "…" - trimmed()'s rule),
after `_HALF_A_TAG` drops a tag the cut went through. (Python 3.12.13's and 3.14.7's html.parser drop such a tag
themselves, so on them that line changes nothing - its mutation isn't caught there; it is kept so the words don't
rest on the parser's reading of a broken tag.)
A field with its link is whole: never cut back.

### Kept shapes

- **The artist side needs nothing more than S2 keeps**: the content's first 4000 letters give at least the 1500
  said for every recording (Tame Impala's 10,843-letter content is the only one cut). `artist_info` is untouched;
  LASTFM_SHAPE stays 1 and KEPT_SHAPES' digest is unchanged.
- **`lastfm.album_info()`** is new: `{url, wiki: {summary, content}}`, each field cut as a bio is (`_bio_text`,
  the same caps). **Not bumped**: no album.getinfo row was ever kept before 2.1.42, at any shape, so none can be read
  wrongly. It is pinned from here like the rest: tests/test_lastfm.py `KEPT_ALBUM_SHAPES` (`{1: digest}`) and
  `test_what_is_kept_of_an_album_changes_only_with_lastfm_shape`, beside KEPT_SHAPES rather than in it - put in it,
  shape 1's digest would change and the rule says to bump, which would have emptied every row 2.1.41 kept for
  nothing. A later bump adds an entry to both.
- **An album row's size**: the same 24.1 KB of fields at most, plus a key of under 100 bytes (its release group's
  id - below), so it always fits the keeping's 32 KB.

### Tests, and the mutations they catch

- tests/test_describe_lastfm.py (70): the recordings' tails, from_lastfm over every recorded bio and wiki and inline
  (summary fallback, licence in capitals, a content the keeping cut inside its licence, links, a cut field, a half
  tag, lists and line breaks, the disambiguation wording, pages that only begin like one), the order, and the routes
  with a key through the whole app - test_describe.py's MusicBrainz (made slow, giving an artist credit only when
  asked for one), Wikidata, Wikipedia and Navidrome, beside test_lastfm_routes.py's Last.fm answering only
  record.py's requests - and without one. After review: the three pairs that fold alike (album.getInfo's answers
  for them WRITTEN FROM THE REVIEW: Dummy's recorded answer, its names and words replaced), "!!!" asked, Mogwai and a
  soft line break, the review's five disambiguation cases, the deadline (a held answer; a lookup outlasting it), a
  side that raises, and the review's gap - a kept Wikipedia side with MusicBrainz down is `unavailable`.
- tests/test_lastfm.py (4 new): album_info over Dummy, sparse and junk answers, its cuts, its kept-shape digest
  (KEPT_ALBUM_SHAPES: the recorded wiki, a wiki at the byte caps, one at the letter caps, a sparse one).
- tests/test_describe.py: unchanged, all passing.

S3's mutations, each put in alone, the Last.fm, describe, logins and player-as-you tests run, and reverted - 38
after review, 37 caught:

- **The order** (Navidrome's or Wikipedia's before Last.fm's; the subtitle not Wikidata's): the order tests.
- **The words**: the licence kept (no LICENCE.sub) - the recordings' tails; the licence kept with no cut at the link -
  only the content the keeping cut inside its licence (". User-contributed text is avail"), since LICENCE and the
  link's own removal cover every recording; "Read more on Last.fm" kept; DISAMBIGUATION off, or put back as first
  written (the review's cases both ways); NUMBERED off (the numbered pages); an address off last.fm; the prose rule
  off (DGD's lists said); the prose rule as first written, a list after any amount of prose, a list line that ends a
  sentence (Mogwai, the soft break); a cut field not ended at a sentence; the summary read first.
- **The asking**: an album asked by its group's mbid (the stand-in answers only record.py's names); **an album kept
  under its names again** (the folding pairs, "!!!"); the lookup not shared, or the Wikipedia side doing its own
  (SlowMusicBrainz counts one release-group ask); an unknown id not asked by name; an artist name past NAME_MAX
  asked; an empty album name asked.
- **Failing**: unavailable false when Last.fm failed; unavailable false when the lookup failed for the Last.fm side
  alone (the review's gap); a refused Last.fm raising, with the deadline's wrapper letting a raise through (the two
  together: the wrapper alone makes any raise a failure) - and the wrapper letting a raise through alone (a side that
  raises).
- **The deadline**: none (the held answer, and the lookup outlasting it); the late side cancelled (the lookup
  outlasting it - the cancel reaches the lookup the Wikipedia side shares); a deadline other than S2's.
- **Without a key** (the Last.fm path taken, Last.fm's order, artist credits asked, the shared lookup): the no-key
  tests here and test_describe.py, unchanged.
- **The album's kept shape** (a summary cap, a content cap, a field renamed, none bumped): the album digest.
- **Not caught: the half tag kept** (`_HALF_A_TAG` not stripped). Python 3.12.13's and 3.14.7's html.parser drop a
  tag cut off at the end of the input themselves, so on them the line changes nothing; it is kept so the words don't
  rest on that parser behaviour.

### Verified, and not

- **Verified by the tests**: everything above over Last.fm's recorded answers, through httpx's MockTransport.
- **Not verified**: deadwax asking the real Last.fm for a description (no call was made here); a real disambiguation
  page's wording; a real album Last.fm doesn't know (its error 6 for an album is shaped from the errors page:
  record.py recorded none); that deadwax reads a real `artist-credit` as the fake's (MusicBrainz's taking the inc
  is verified above, by the review; its credit here is shaped from the documented one); a description page drawn in a browser with Last.fm's words
  (ui/ didn't change, so only its words differ); how many artists' bios put a list straight after one paragraph.

## S4 - similar artists and top albums (2.1.43)

`GET /deadwax/lastfm/artist` gains the design's last two parts (its 2.5), for the app's Similar Artists row and the
albums' "Most played" order (slice A2 draws them). Nothing on the web changes. No route, setting or table is new.

### The answer, now

    {..., "top_songs": [...],
     "similar": [{"name": "Pond", "mbid": "69ac44f7-c80d-47b4-9bc8-fcc758d209e6", "match": 1.0,
                  "url": "https://www.last.fm/music/Pond"}, ...],
     "top_albums": [{"title": "Currents", "mbid": "031ecbde-35e1-4d3a-917f-f89f31aca1c9", "plays": 197990342,
                     "counted": "plays"}, ...]}

- **Four parts, asked at once**, each through `kept()` with S2's fallback (by mbid, then by name with autocorrect=1):
  getInfo, getTopTracks (limit 50), **artist.getSimilar (`limit=30`) and artist.getTopAlbums (`limit=50`)** - exactly
  record.py's parameters, since the tests' stand-in answers only those. The one `ARTIST_DEADLINE_S`, 4 s, covers all
  four. A part not in by then is `null` with `unavailable`, and goes on and is kept, as S2's did. Four parts take all
  four of the client's in-flight slots, so a second page's asks wait for the first's.
- **Each part stands alone**: `null` when it couldn't be had (failed, late, Last.fm doesn't know the artist), `[]`
  when Last.fm knows the artist and lists nothing. One failing leaves the other three as they are.
- **An older app keeps decoding it**: the app's `LastfmArtist` (ios Lastfm.swift) reads its six fields by name and a
  Decodable ignores keys it doesn't know. So the two new keys change nothing for A1's app.

### `similar`

- `similar_artists(body)` keeps `{artist, similar}`. `artist` is Last.fm's `@attr.artist`, the name it answered
  for. `similar` is Last.fm's list in its order (match descending, as answered), each entry as follows:
  - `name`: as Last.fm wrote it, ends trimmed; an entry with no name is dropped;
  - `mbid`: `mbid_of()`, trimmed and lowercased, and only of MBID_PATTERN's shape, else `null`;
  - `match`: `similarity()`, a float from 0 to 1. Last.fm writes it as a string ("0.706669"); words, "nan", a bool,
    or a number past 1 or below 0 give `null`;
  - `url`: `lastfm_url()`'s rule.

  At most `SIMILAR_MAX` = 30. **Various Artists** (by MusicBrainz's id 89ad4ac3-... or by `name_key`) is dropped as
  the answer is parsed. No images: Last.fm's are placeholders, and the design's 3.4 draws Navidrome's.
- **The asked artist is dropped when the answer is made, not when it is parsed** (`similar_of(kept, mbid, name)`).
  The kept row is shared by every page that asks by that id or name, so the asker's id and name aren't the row's to
  hold. Dropped: an entry with the page's `mbid`, or one whose `name_key` is the asked name's or `@attr.artist`'s. A
  name that folds to nothing ("!!!") drops nobody. The row is read back entry by entry through the same checks, at
  most 30. No recording lists the artist among their own similar artists. The tests make one that does, an
  "Impala, Tame" that only the id can drop.

### `top_albums`

- `top_albums(body)` keeps `{top_albums}`, in Last.fm's order, each `{title, mbid, plays, counted}`:
  - `title`: ends trimmed, whole(); an album whose title folds to nothing (`name_key`) is dropped - see "After
    review";
  - `mbid`: `mbid_of()`. Last.fm's album ids are releases', not release groups': the app matches by title as well;
  - `plays`: `count()`'s, never `int()`'s;
  - `counted`.
- **One count for the whole list**: the design's fork. With any album carrying a readable `playcount`, every
  album's `plays` is its playcount, `counted: "plays"`. With none, it is each one's `listeners`, `counted:
  "listeners"`. An album without the list's count is left out rather than set beside the others with another kind
  of number. With neither count anywhere, `[]`. The read-back (`_kept_albums`) keeps only the first readable
  entry's kind, so a kept row can't mix them either. At most `TOP_ALBUMS_MAX` = 50.
- **What the recordings settled**: every getTopAlbums answer carries `playcount` (a JSON number, unlike every other
  count Last.fm sends, which is a string) and **no `listeners` at all**, whereas the API page's sample shows listeners. So `counted` is "plays" for all three artists. The listeners
  branch is held by inline cases written from the API page (`SHAPED`). Last.fm's order **isn't by plays**: 20 of
  Tame Impala's 49 neighbours, 21 of Dance Gavin Dance's and 17 of Portishead's are out of order (Deadbeat 23.6M
  before 29.9M). It is presumably by listeners, as with top tracks. deadwax keeps Last.fm's order and the plays, and
  the app's "Most played" sorts by them.

### What the recordings give (2026-11-25), by mbid and by name alike

- **Similar**: 30 each, the first at match 1.0.
  - Tame Impala: Pond, Melody's Echo Chamber, GUM, Temples, The Holydrug Couple.
  - Dance Gavin Dance: Royal Coda, Eidola, Secret Band, Wolf & Bear, Emarosa.
  - Portishead: The Funky Lowlives, Pati Yang, Hird, Soma Sonic, Marsmobil.

  Two of each have no mbid: Melody's Echo Chamber and King Gizzard & The Lizard Wizard; Hail The Sun and Ghost
  Runner On Third; Martina Topley-Bird and Dzihan & Kamien. The app drops theirs with no mbid (its 3.4). None
  lists Various Artists or the artist themselves.
- **Top albums**: 50 each, all counted by plays.
  - Tame Impala: Currents 197,990,342 · The Slow Rush · Lonerism · Deadbeat; 38 with an mbid.
  - Dance Gavin Dance: Downtown Battle Mountain 13,211,300 · Instant Gratification · Dance Gavin Dance · Downtown
    Battle Mountain II; 33 with an mbid.
  - Portishead: Dummy 64,559,236 · Third · Portishead · Roseland NYC Live; 22 with an mbid.
- **Kept rows**: similar 3.9-4.0 KB, top albums 4.5-5.3 KB, against Last.fm's 32-50 KB answers.
  `test_a_second_visit_is_answered_from_what_was_kept_and_asks_nothing` holds Tame Impala's under 6000 bytes, with
  no `image`. Since the review each is bounded, so it always fits the keeping ("After review").

### The dotted and the dotless i (match_key, from S2's review)

songs.ts `SAME_SONG_ASIDE` is `/.../giu`. Python's port used `re.IGNORECASE`, which also folds **İ (U+0130) and ı
(U+0131) into i**, both in the words ("live", "remaster") and in a class. JavaScript's `/iu` folds only **ſ
(U+017F) into s and K (U+212A) into k**; nothing else becomes an ASCII letter. Both facts were read off Node and
Python by trying every code point. So "Roads (LİVE)" keyed `roads` here and `roads (live)` in the TypeScript and
the app's port. That is a song that matched on one side only.

- **Fixed in Python**, to the vectors' (JavaScript's) behaviour. The pattern has no flag. Each word is spelled by
  `_js_iu()` as `[lL][iI][vV][eE]`, with `[sSſ]` and `[kKK]`. `_B`'s class was already JavaScript's `\w` under `/iu`
  (ASCII, ſ and K). A fuzz over 200,000 titles in the scratch dir (never committed) found 201 that the old pattern
  keyed differently from the compiled songs.ts, and none with the new one.
- **Steps 1-3 (`strip_title`) keep `re.IGNORECASE`**: they are Python's own, the app's port mirrors Python there,
  and the vectors pin it ("Roads - Lİve" strips to "Roads").
- **The vectors**: 9 titles added, written with `String.fromCharCode` in export-vectors.cjs, 66 in all:
  - the five that failed on the old pattern: (LİVE), (lıve), (Lİve at Roseland), (Remasteredİ), (Remasteredı);
  - what `/iu` does fold: (Remaſtered), and (LiveK) with the Kelvin sign;
  - the two step 1-3 cases.

  `test_the_folds_that_matter_most` asserts the dotted-I and dotless-i keys and the long s by hand.
- **The app's copy must be recopied**: `ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lastfm/match-vectors.json`
  is held byte-equal (`test_the_app_s_copy_is_this_one`, on ios after merging main). Read off the ios branch (not
  run), the Swift `SongTitle.key` folds only ASCII case and ſ, and its word letters are ASCII, ſ and K. That is
  JavaScript's, so the new vectors should pass there unchanged.
- **LASTFM_SHAPE 1 -> 2.** A top tracks row folded by 1 can hold one song where 2 makes two, which is the rule's
  case. The bump empties every kept row once at start-up (`at_start`): getInfo, top tracks and album.getInfo are
  each asked again once.
  - `KEPT_SHAPES` gains 2's digest, which now also covers similar_artists and top_albums over every recording, the
    S4 inline cases, SIMILAR_MAX and TOP_ALBUMS_MAX, FOLD_CASES with the dotted and dotless i and the long s, and
    **each FOLD_CASES title's match_key**. Nothing in 1's held them, so the fix alone left the digest where it was.
    The keys were added after the first mutation run: the fold stops at TOP_SONGS, the new cases sit past its tenth
    song, and so re.IGNORECASE put back failed the vectors but not the digest. With the keys it fails both.
  - `KEPT_ALBUM_SHAPES` gains 2 with 1's digest, since album_info didn't change.
  - tests/test_lastfm_kept.py reads `LASTFM_SHAPE` instead of a literal 1.

### The app's fixtures

answers.py's nine cases are unchanged in number and prefix (the app's LastfmDecodeTests counts 9), and each answer
now carries `similar` and `top_albums`. The refused case refuses all four methods, since refusing two let the other
two race it. **Run it on `ios` after merging main**: `artist.json` there is 2.1.41's.

**The ios branch's `tests/test_ios_contract.py test_lastfms_answer_is_what_the_app_decodes` fails once main is
merged.** It calls `artist_answer(info, tracks, refusal)`, which is now `(info, tracks, similar, albums,
refusal)`, and it asserts the answer's keys are exactly `LastfmArtist`'s six. A2 updates it with the model.

### After review (before 2.1.43's commit)

The review found no fault in S4's own logic. It found one older fault that S4 widens, a bound S4 lacked, and a gap in
which titles are dropped. Each is fixed and mutation-checked, and the digest covers them.

- **A lone surrogate in a name 500'd the route on every visit.** JSON's `"\ud800"` with no pair after it is a lone
  surrogate in Python. The parse and the keeper took it, and the keeper writes it back as it came (ASCII JSON).
  Starlette's JSONResponse encodes UTF-8 and raised UnicodeEncodeError: a 500 at every visit while the row stood.
  That was a week without asking Last.fm at all, then up to 30 days answered from the row while it was asked again
  behind (lastfm_kept's standing). That held for top songs since 2.1.41, and S4 adds two more lists of names.
  Fixed in layers:
  - `lastfm.whole()` turns each lone surrogate into U+FFFD. A letter outside the BMP is one letter in Python (JSON's
    pair is read as one), so it is never touched.
  - `whole()` runs in `_name` (song titles, similar names, `@attr`, album titles) and `_bio_text` (getInfo's bio,
    album.getInfo's wiki), so no row is kept with one.
  - The read-back runs the same: `_kept_songs` and `_kept_albums` read titles through `_name`, and `similar_of`
    through `_similar_entry`.
  - descriptions.py's text exits do the same: `clean_text` (every paragraph: Last.fm's, Wikipedia's, Navidrome's)
    and `english_description` (the subtitle). The description rows are kept 30 days, so the same fault was there for
    every source.
  - **The last guard**: `lastfm.answerable()` makes every string in an answer whole, keys included. It wraps the
    artist route's answer and both describe routes'. Text any parse lets through degrades to U+FFFD rather than a
    500.
  - `why` was already safe: `cleaned()` turns anything unprintable into a space, and a surrogate is unprintable.
  - Tested through the routes:
    - `test_a_lone_surrogate_from_last_fm_is_answered_and_kept_whole`: a song, a similar artist and an album, kept
      whole and answered from the row;
    - `test_a_lone_surrogate_in_last_fm_s_bio_is_said_whole_and_kept_whole`;
    - each guard alone, with the layers before it monkeypatched away:
      `test_a_text_the_parse_let_through_is_still_never_a_500` and
      `test_a_text_the_reading_let_through_is_still_never_a_500`.

    The stand-in Last.fm sends a body given as bytes as it is, because httpx's `json=` can't send a lone surrogate.
- **The rows are bounded.** A similar or top albums row is at most `LIST_ROW_BYTES` = 24 KB as kept. `_fitted()`
  drops entries from the end until the row fits, working out each entry's size once.
  - The bound plus the longest key there is, 6,827 bytes (a name of the route's 200 letters, each folding to at most
    33 bytes, as `test_a_getinfo_row_always_fits_the_keeping` found), is under ROW_MAX_BYTES' 32 KB. So a row is
    always kept, never asked again at every visit. lastfm.py can't import lastfm_kept (it imports lastfm), so the
    bound is a constant and `test_a_similar_and_an_albums_row_always_fit_the_keeping` proves it.
  - `@attr.artist` is the one field the bound couldn't drop. It is kept only up to `ANSWERED_NAME_MAX` = 200 letters,
    the route's NAME_MAX; a longer one is no name a page asks by.
  - One entry too big for any row on its own leaves `[]`, said as "lists nothing". The recordings are 4-5 KB and keep
    every entry. `test_the_largest_similar_and_albums_rows_are_kept` runs 30 and 50 names of letters outside the BMP,
    asked by the longest-key name, through the route.
- **Album titles that fold to nothing are dropped** (`name_key` empty), in the parse and the read-back. "(null)" is
  the case the review gave. The list's count is decided after the drop, so a "(null)" alone with plays decides
  nothing.
  - This takes **Sigur Ros's "( )"** and **!!!'s "!!!"** with it: `name_key` drops a bracketed aside and keeps only
    letters and digits, so both fold to "".
  - On their artist pages those albums get no plays from Last.fm, and the app's "Most played" puts them among the
    albums with none, after those with plays, newest first.
  - Kept, they would have met the page only by mbid. Last.fm's album mbid is a release's, as Navidrome's
    musicBrainzId is. The app's title match is `Fold.key`, which folds them to "" too, so the title could never
    place them.
  - Keeping a nothing-title only when it has an mbid would save them. It wasn't done: the review asked for the drop.
    Similar artists keep such names ("!!!" the band is a real similar artist, with an mbid).
- **The upgrade re-asks every description row once.** The bump to shape 2 empties every kept row, the descriptions'
  getInfo and album.getInfo rows among them. So the first visit to each artist or album description after the upgrade
  asks Last.fm again, once.
  - That's bounded by the client's pace (PER_SECOND 5, IN_FLIGHT 4, TURN_WAIT_S 2 s).
  - An ask past it is Unreachable ("busy"), said without Last.fm's words and `unavailable`, so the app asks again
    soon. Nothing is kept from it.
- **Four parts can fill the client's four slots.** An artist page's four parts each take one of the client's
  `IN_FLIGHT` = 4. While a slow page holds them (each up to FETCH_DEADLINE_S, 8 s), another Last.fm ask waits
  TURN_WAIT_S and is then "busy": an album's description, another artist's page or description.
  - It is answered without Last.fm, `unavailable`, and asked again on the next visit.
  - The same artist's own description joins the page's getInfo ask (one ask per key), so it takes no slot.
- **The dotted and dotless i in FEATURE_TAIL and CREDIT_CUT aren't covered.** Both use `re.IGNORECASE`, as Python's
  own steps 1-3 do, so "One More Hour featurıng X" drops its tail and "Tame Impala FEATURİNG X" is cut at it. No
  vector pins either. The vectors hold ı and İ only in FEATURE_ASIDE ("(Featurıng Someone Else)") and the dash takes'
  TAKE_WORD ("Roads - Lİve"). So the app's port could differ there unseen. Two vectors would close it; they need the
  app's copy recopied with them.
- The docs said each album shows "how many times it has been played". That is untrue for a list counted by listeners,
  and both now say "its plays on Last.fm, or its listeners where Last.fm gives no plays".

### Tests, and the mutations they catch

- tests/test_lastfm.py, 102 -> 174 (5 of them the review's). The S4 parses are tested over the recordings (the first five similar artists and
  four albums of each pinned, the ones with no mbid named) and inline (`SHAPED`). Also covered: `mbid_of`,
  `similarity`, the self-drop, Various Artists, the caps, one count per list, kept rows read back, the four-part
  answer, and the digest.
- tests/test_lastfm_routes.py, 38 -> 49 (3 the review's). Every recorded artist through the app, with each part failing alone (x4), a
  late similar part kept, the artist among their own similar artists (`SHAPED`: kept 30, answered 28), albums by
  listeners (`SHAPED`), and empty lists kept and not `unavailable`. Unrecorded asks, each marked `SHAPED`: getSimilar
  and getTopAlbums for the unknown id and name are given the recorded not-known answer, and the misspelling empty
  lists.
- tests/test_lastfm_vectors.py, 87 -> 96 (the nine titles). tests/test_describe_lastfm.py, 70 -> 73 (the
  review's surrogates). It and tests/test_lastfm_kept.py follow the bump and the four parts.
- The whole suite: 5145 passed, 2 skipped. pyflakes is clean.

Each was put in alone, then the Last.fm, describe and logins tests were run (652 tests). Each file was restored
byte for byte afterwards. All 18 were caught:

- **the artist themselves in `similar`**, three ways (no drop; by id only; by name only):
  `test_the_asked_artist_is_never_similar_to_themselves` and the route's
  `test_the_artist_is_never_among_their_own_similar_artists`.
- **more than 30**, with both caps off or the read-back's alone: `test_no_more_than_thirty`.
- **an mbid of the wrong shape passed on** (`mbid_of` taking any text): `test_an_mbid_of_any_other_shape_is_none` (13
  failed).
- **`top_albums` without `playcount` crashing** (`int(album["playcount"])`):
  `test_top_albums_without_a_playcount_are_counted_by_listeners_and_never_crash`, the route's listeners test, and
  the digest.
- **`counted` wrong**, three ways (always "plays"; listeners chosen first; a mixed list): `test_one_count_for_the_whole_list`,
  the listeners tests, `test_a_kept_row_read_back_carefully`, and the digest.
- **Various Artists kept**, **a match not range-checked** and **a similar url not checked**: their parse tests, the
  kept-row read-back, and the digest.
- **a late part cancelled**: `test_a_late_part_goes_on_to_ask_by_name_and_that_is_kept_too`.
- **one part failing taking the others down**: 13 tests.
- **only S2's two parts asked**: 26 tests.
- **SAME_SONG_ASIDE back to re.IGNORECASE**: the five vectors, `test_the_folds_that_matter_most`, and (after the keys
  were added) the digest.
- **LASTFM_SHAPE left at 1**: both digest tests.

The review's 14, the same way (661 tests), each restored afterwards, all caught:

- **`_name` not whole**, and **`_bio_text` not whole**: the surrogate parse tests, the route tests (artist and
  describe), and the digest;
- **the artist route's guard off**, and **the describe routes' guard off**: the two last-guard tests, and only
  they, as the layers before the guard are monkeypatched away there;
- **`clean_text` not whole**, and **the subtitle not whole**: `test_a_lone_surrogate_in_any_side_s_words_is_said_whole`;
- **kept songs, or kept albums, read back not whole**: `test_a_kept_row_with_a_lone_surrogate_is_answered_whole`;
- **the bound off**, **by letters not bytes**, and **at 32 KB**: `test_a_similar_and_an_albums_row_always_fit_the_keeping`,
  the route's largest-rows test, and the digest;
- **the answered name not capped**: the fit test;
- **a title that folds to nothing kept**, in the parse (with the digest) or in the read-back:
  `test_an_album_title_that_folds_to_nothing_is_left_out`.

### Verified, and not

- **Verified by the tests**: everything above, over Last.fm's recorded getSimilar and getTopAlbums answers through
  httpx's MockTransport, with the request parameters exactly as recorded.
- **Not verified**:
  - deadwax asking the real Last.fm for these (no call was made here);
  - how long four parts take cold;
  - a getTopAlbums answer with listeners and no playcount (the API page's sample; no recording has one);
  - getSimilar and getTopAlbums for an unknown artist (their error 6 is shaped from getTopTracks', recorded);
  - the Swift port against the new vectors (not run: the ios branch wasn't checked out).
