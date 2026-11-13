# Play history that lasts

James, 2026-11-13: **"I'd like it if the play history was persistent, so you can always look back and see what you
played yesterday."** His answers, to the design (kept outside the repo at deadwax-plans/play-history.md, its
section 9 overruling the rest):

- **Where: in Up Next, Apple Music's way.** Scroll up past the current queue's History and it keeps going; a tap plays
  the song. No separate History page.
- **What counts: every song started, skips included** - not only the plays that counted.
- **Which apps: web and iPhone**, kept by deadwax per person, so plays on either show on both; the phone's offline
  plays appear once it reconnects.
- **Kept for ever** (a guard of 1,000,000 rows a person stays). **One continuous list, no headings at all** - no
  Today, Yesterday or dates, and no separate "History" heading for the current queue: scrolling up from what's
  playing reads as one unbroken list of everything played, newest nearest. **No times** on rows. **Skips drawn like
  plays.** **No Clear** in this build.

### The server (2.1.14)

- **What a start is.** One person beginning to hear one song: the moment both apps already send "now playing" - a
  listen's first sound (the web's `beginListen` with `nowPlaying`, the phone's `ListenTracker.began`/`join` giving
  `.nowPlaying`). Pause and play, a seek, a wait for the network and a retry from where it stopped are the same
  listen, so never a start; a restart (Previous early, Play on a song that ended), each Repeat One copy, each Repeat
  All round and a History tap are each a new one. Dated by the listen's `startedAt`, whole ms by the DEVICE's clock -
  exactly the `time` the counted scrobble carries, so the two share a key.
- **`play_history`** (store.py SCHEMA): `(user, started_at, song_id)` the primary key, `WITHOUT ROWID`; the song as
  the queue holds it (lib/resume.ts `bare()`: title, artist, album, albumId, coverArt, duration, contentType, suffix,
  sampleRate, bitDepth, channels - QueueTrack without its level), so a row reads and plays again after a rescan or a
  delete with nothing fetched first; `counted`; `queue` and `entry` (the queue's id and the entry's key - only the app
  reads them, to draw each start once); `recorded_at` (the server's ms: a late offline send tells itself). The
  primary key serves the page read (`(started_at, song_id) < (?, ?)`, `SEARCH ... USING PRIMARY KEY` in EXPLAIN),
  the counted mark and the person's delete - no other index. **Measured** (a scratch SQLite 3.53, 54,750 rows - 150 a
  day for a year - realistic titles and 22-character ids, VACUUMed): 11.8 MB a year for one person, 216 bytes a row;
  a page of 100 read in 0.24 ms; a page is 42 KB of JSON (11 KB compressed).
- **The same start twice is one row**: `INSERT ... ON CONFLICT DO UPDATE SET counted = MAX(counted, excluded.counted)`
  - a retry whose answer was lost, the phone's offline batch sent again - `counted` ORed in, never taken back, the
  rest as first kept.
- **`src/play_history.py` (pure)**: `clean_start` (a start as its row, or None - SKIPPED), `play_of`, `page`, the
  bounds. A start dated more than 10 minutes past the server's clock or before 2020-01-01, or with no song id or one
  over `ID_MAX` (256, routes/navidrome.py's), is skipped and the rest of the batch taken - the phone drops a batch
  answered with a 4xx (DeadwaxCore `PendingPlays.after`), so one bad clock reading must not lose a week of offline
  plays. Text over 500 characters is cut, numbers clamped, a queue id that isn't `[A-Za-z0-9_-]{1,64}` or an entry
  that isn't a key kept as none.
- **The routes** (`src/routes/play_history.py`, included at `/deadwax/me/history` with `current_user` beside pins;
  ROUTES: both `user`). deadwax's own data: Navidrome is asked nothing, so it isn't a Navidrome route and
  `test_there_is_no_general_proxy` is untouched.
  - `POST` - `{starts: [{at, counted, queue, entry, song: {...}}]}`, 1 to 500 -> `{taken, skipped}`, no-store.
    **Each start is validated on its own** (`HistoryStart.model_validate` per item; the batch's model checks only that
    `starts` is a list of 1 to 500): one of a wrong type - a string for `at`, a song with no id, not an object at all -
    is skipped and counted in `skipped`, the rest taken, since both apps let a batch answered with a 4xx go. Only a
    body that isn't a batch (no `starts`, not a list, none, too many) is a 422. Every field the apps send is declared
    (the standing rule: pydantic drops an undeclared one without a word); **a field deadwax doesn't know is ignored**
    (`extra="ignore"` at every level), never refused - a newer phone app talking to an older deadwax must not have its
    plays refused for a field it added. (2.1.14 first had `extra="forbid"` and one model for the batch - the review
    caught that one bad start, or one new field, would 422 the batch and the outbox would drop every start in it.)
    One `BEGIN IMMEDIATE`. Then the guard (in memory, per person): the oldest past `HISTORY_KEPT_MAX` (1,000,000, ~18
    years at 150 a day, ~216 MB) go - looked at once a day after a write, and **sooner once `HISTORY_TRIM_AFTER`
    (10,000) starts have been taken** for that person since the last look, so a client gone wrong can't write
    without limit for a day before it is looked at.
  - `GET ?limit=100` (1-500) `&before_at=<ms>&before_id=<song id>` - newest first; `next` is the last play's own
    `{at, id}` when there is more, else null; `shared` with logins off. `before_at` alone is "before that moment"
    (a later "go to a date" needs no new route); `before_id` alone is a 422, and so is a `before_at` below 0 or past
    SQLite's INTEGER (`HISTORY_AT_MAX`, 2^63 - 1) - which would otherwise overflow in SQLite and answer a 503. **By count, not by day**: the day is the
    device's own calendar's, which the server doesn't know (the phone and a desktop can differ; a trip moves it),
    and a day may hold none or 500.
  - No database: GET answers no plays, POST a 503 - the apps keep their starts and send them later. A database
    failing just now is a 503 either way.
- **The counted mark**: `POST /navidrome/scrobble/{id}?submission=true&time=<ms>` first marks the start of that
  moment counted (`store.mark_counted`), whatever Navidrome then answers - it is a fact about listening, not about
  Navidrome - and never in the way (a database that can't is logged). A resend `_counted_once` doesn't pass on still
  marks it; "now playing", or a play with no `time`, marks nothing. A count arriving before its start (the start's
  POST failed and is retried after) misses - each app's outbox sets `counted` on its own pending start, which the
  insert ORs in.
- **Per person**: `current_user`'s name; with logins off `local`, one history for everyone, `shared: true` (as the
  play queue's). Break-glass's are kept under `deadwax` like anything else - unlike `/queue`, no Navidrome account is
  in play. `play_history` joins `PERSON_TABLES` (People's Remove and Forget), `known_users` counts it (`history`), so
  a name with only plays left is offered Forget rather than silently blocking a new account; People's words gain
  "the songs they played" and "1,234 songs they played". **adopt_local** hands `local`'s rows to the first admin
  (`INSERT OR IGNORE ... SELECT`, a start they already have keeping theirs) - deadwax's own, like the pins; unlike
  the play queue, which mirrors the shared Navidrome account's. `local_has_anything` gains the table.
- **Verified**: tests/test_play_history.py (51) - the pure half; kept and paged back newest first across 250 starts
  and three pages; two songs begun the same millisecond paging; the same start twice one row, counted never taken
  back, the title kept as first sent; skipped against taken; five 422 bodies; ten bad starts each skipped from a
  batch of three, the other two taken; fields deadwax doesn't know, at all three levels, kept exactly as without
  them; a full batch; the page's bounds (`before_at` 10^30 and 2^63 a 422, 2^63 - 1 answered); the scrobble's mark
  (with time, a resend, another person's, Navidrome refusing, no database); each person their own, logins off
  `local`'s and shared, break-glass's own; no database and a failing one; forget, known_users, the take-over, an
  existing database gaining the table, the guard once a day and sooner past `HISTORY_TRIM_AFTER` (per person, only
  starts taken counted). people.sim's new words. **Not verified**:
  nothing has sent it a start yet but the tests - the apps record from 2.1.15 (the web) and the phone's port.
