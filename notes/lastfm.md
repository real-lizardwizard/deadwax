# Last.fm

The design is `~/Desktop/Code/deadwax-plans/lastfm.md` (2026-11-24): its decisions, its sections 0-2 (Last.fm's API
as read, the setting, the server) and its slices. This file is what was built, slice by slice, and why it differs
where it does. James asked (24 Nov 2026) for an artist's ten most popular songs in the iPhone and Mac app; after
comparing Deezer, ListenBrainz and Last.fm for Tame Impala and Dance Gavin Dance: "last.fm looks great, let's use
that" - and, with a key in deadwax anyway, listeners, similar artists, radio from similar songs, albums by plays, and
Last.fm's descriptions first. His answers to the design's questions: Autoplay is off by default; About (descriptions
in the app) is built.

## S1 - the setting, the client, the keeping (2.1.36)

Nothing in 2.1.36 asks Last.fm: no route calls the client yet (`/deadwax/lastfm/artist` is S2, 2.1.37 on). What is
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
- `cleaned()` is how a Last.fm message is kept: the key taken out (should Last.fm ever echo it), control characters
  out, one line, at most 200 letters.
- **The match keys** (the design's 2.4), with the contract `tests/fixtures/lastfm/match-vectors.json`: 57 titles, 27
  names. `stripped` and `first` are hand-written in `tests/fixtures/lastfm/export-vectors.cjs`; each `key` is what
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
- `LASTFM_SHAPE = 1`: the first part of every kept row's key.

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
