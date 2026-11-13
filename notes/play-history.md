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
  nothing had sent it a start but the tests - the web records from 2.1.15 (below), the phone from its port.

### The web's Up Next (2.1.15)

- **The queue's id.** `UpNextState.id` (lib/upNext.ts): made by `queueId()` as a queue starts - the time in base 36
  and eight characters from `crypto.getRandomValues` (a plain http page has it; `randomUUID` it hasn't), Math.random
  only where there is no crypto - after the shuffle and never from startUpNext's `random`, so every seeded order is
  what it was. Every edit spreads `...state`, so Repeat's rounds, Play Next, a jump, the library shuffle's pages keep
  it. The snapshot carries it (lib/resume.ts `toSave`/`fromSnapshot`, `id` read back when it is `[A-Za-z0-9_-]{1,64}`,
  else a new one), so a queue picked up on another device is the same queue. The phone's snapshot has none until its
  port (0.6 drops it on save), and a new id for its save would make the WEB's own songs in that queue show twice -
  its starts under the old id drawn above, their entries drawn again by History's rows (the review). So
  `fromSnapshot(..., holding)` keeps the page's id when the snapshot has none and `sameQueue(holding, put)`: the same
  list in the same order, and at least one key both have, every such key the same song (keys are the queue's own
  numbering, carried on by whichever app edits it - another album tapped numbers from 0 again, with other songs under
  them; the same album tapped again is the one case it can't tell, and then the page's earlier starts in it are its
  rows). useResume's `take()` passes the queue it holds. Still open, while the phone is on 0.6: a page RELOADED since
  holds no queue to keep the id from, so its earlier plays in that queue show twice until the queue changes or they
  pass History's 50 (troubleshooting.md says so) - the phone's port carrying the id ends it.
- **Recording - the engine's one line.** `beginListen` in usePlayer.ts calls `started(track, listen.startedAt,
  state.queue)` where it called `scrobble(track.id, false)` (and imports it): player/api.ts `started()` sends that
  same "now playing", then hands `startOf()` - the song `bare()`, the queue's id, the entry's key - to
  player/historyOutbox.ts. `scrobble(id, true, time)` also marks its start counted there. No other engine change.
- **The outbox** (player/historyOutbox.ts, a module): this page's starts, the newest 500 (`OWN_KEPT`), drawn at once;
  the pending - at most `OWN_KEPT` too, the oldest let go past it, so one POST always holds them all - sent in one
  POST right after each start, one POST at a time. No answer, a 5xx, a 408 or a 429: again at the next start, and by
  itself after `retryAfter(failures)` - 30 s doubling to 10 min (`RETRY_MAX_MS`), from 30 s again once one is taken
  (the review: a fixed 30 s sent a deadwax with no database the same 500 starts every 30 s for ever). A 401: held for
  the next start, with no timer (each ask would bring the sign-in back; a different person signing in reloads the
  page, so pending starts are always the signed-in person's). Another 4xx: let go (`afterFailure`, the phone's
  `PendingPlays.after`) - and since 2.1.14's review the route answers a 4xx only for a body that isn't a batch at all,
  so a bad start never costs the rest. A start counted while on its way is a new object, so it
  stays pending and goes again counted. In memory only: a reload while deadwax is unreachable loses what's pending.
- **A continuation** (app/useResume.ts): deadwax's own queue (`answer.kept`) put back at a position over 0 calls
  `continuing(put)`; the outbox drops the next start if it is that queue's id and entry - the song played on was
  recorded when it began. Any start, and any other restore (`continuing(null)`), ends it. Another app's queue, or one
  at 0 s, records its start. Meant, and left so (the review asked): while the iPhone app keeps no history, a song it
  began that the web picks up mid-way is in nobody's - recording it here would draw it twice once the phone's port
  records its own starts.
- **Each start drawn once** (lib/playHistory.ts): `queueShows(queue, limit)` is the queue's id and lib/upNext.ts
  `shownKeys(queue, limit)` - exactly the entries upNextView's rows stand for, each with its copies: one run from
  History's floor (past a run of copies at it whose song is further back, or the song playing's unit if that is
  first) to the end of the list's `limit`-th row (UP_NEXT_DRAWN, 100). A start of one of them is the queue's; every
  other start is an older row: `pastRows` - oldest first, a run of starts of one song one row keyed by its first. As
  first built it claimed every key from the floor to the END of the marks, but Up Next draws neither Repeat All's
  later rounds (it sums them up in a line) nor list rows past 100 ("And N more"), and Previous can leave songs begun
  there - Repeat All into the next round's first song, Previous twice, and that start was drawn nowhere (the review's
  probe). history.sim now judges "drawn" by the view's own rows (it had counted any entry after the song playing as
  drawn, which is how it missed this), with a list limit of 8 for half its 1,500 runs so rows past the limit come
  up often, a reload's round trip and new queues among the moves (7.9 million starts looked at), plus the probe and a
  long album played on and gone back past the 100.
- **Up Next** (app/UpNext.tsx): above the card, ONE `<ul>` - the older rows (`data-past`, their keys `at:songId`) then
  History's (`data-key`) - in a `<section aria-label="History">`: no heading drawn (James), the song playing's title
  still the first heading. The older rows are built and drawn only while it is open (the review: Up Next stays
  mounted while closed, and a month scrolled back is thousands of rows rebuilt and re-diffed at every song's change);
  those drawn as it closes stay until the queue next changes, so nothing above the card moves as the sheet slides
  away. One Tab stop across both (`historyStop` a number or a past key). An older row's tap: the
  key Play Next will give (`nextKey`) read first, then `player.playNext(queued([row.track], 'songs'))`, then - unless
  that started the music (a queue played out) - `player.jumpTo(key)`, all in the click; held under the finger and said
  as History's tap is, `took()` also taking a new queue of that song. app-rules allows UpNext `playNext` and lists it
  among the calls through `queued()`. Hidden in Edit with History.
- **Pages** (app/usePlayHistory.ts, called once in App with `upNextOpen` and `pageShown`): the newest page as Up Next
  opens and as the page shows again while it is open (`withNewest`: joined, or started again from when it doesn't
  reach what is held - or when nothing is held: an empty first page then a full one, a first open after upgrading
  with a desktop's panel left open while the phone played, had kept `before` null and no older page could come until
  a reload, the review found); `older()` from the held cursor (`withOlder`; a cursor no longer held ignored), one at a time,
  each with its own `latestOnly()`. `older()` is asked from `measure()`'s scroll handler and after every restore when
  the scroller is within its own height of the top (`LOAD_WITHIN`), there is more, none is coming and the last didn't
  fail. A page landing above is a change above the card: the anchor's new `above` (the older rows' count and ends,
  the spinner, the error) makes `restore()` put the view back. At the top while a page comes, `pl-spinner` ("Loading
  earlier songs"); a failure, `errorNote(error, { failed: EARLIER_FAILED, retry: true })` in a `pl-notice` with Try
  again - and no ask from scrolling until it is pressed. No CSS added (the existing `.app-upnext-history` margin,
  `pl-spinner`, `pl-notice`, `pl-text-button`).
- **Known**: a key-adding edit the engine is holding (a Repeat top-up or a library shuffle's page, held while a seek
  lands) is applied with Play Next's and numbered first, so the key read before the tap names it: jumpTo then plays
  that entry if Up Next draws it (Repeat All's next round at a round's last song, the shuffle page's first song) - the
  window is one `timeupdate` after a seek lands; `took()` keeps it from being said. Not reproduced; the clean fix is an
  engine action of its own, which this change doesn't make. No windowing: a month of scrolling back is a few thousand
  rows (covers lazy) - unmeasured on a phone.
- **Verified**: history.sim (new: the property, the pure rules, the outbox on a virtual clock; since the review the
  property judged by upNextView's own rows with a list limit of 8 for half its runs, the two probes, a full page
  after an empty one, 408 and 429 retried, the backoff over an hour of 503s and back to 30 s once taken, at most 500
  waiting); upnext.sim (the list drawn, each start once, a start falling past the 50 and another queue, one Tab stop,
  the older row's tap, Edit, paging holding the view, the spinner, the failure, and - the review - the older rows
  not drawn while closed); player.sim (every scenario: a start sent for each "now playing" and nothing else, in
  order, each counted play's time a start's and marked counted, every start with its queue and entry and no level);
  resume.sim (the id round trip at every step, a missing or bad id, the continuation, and - the review - an id-less
  snapshot of the queue held keeping its id, of any other a new one); app-rules (the tap's calls in the click
  through `queued()`, usePlayHistory once, lib/playHistory pure); errors.sim (UpNext, usePlayHistory and the outbox
  among the listener files). Mutated back and caught: the old queueShows (the tightened property failed at run 17),
  the old withNewest, Up Next's older rows built while closed. After the rebase onto 7d02241 and the review's fixes:
  `npm run build` on Node 22, every sim (70), the whole pytest suite (4216 passed). And in a real Chromium - headless Brave over CDP, this worktree's deadwax against
  the lyrics harness's stand-in Navidrome (copied; logins off, every other host refused), opened as
  `http://deadwax.test:8121` (not a secure context), 250 earlier starts sent through POST /deadwax/me/history first:
  on the phone frame (390x844, touch) the album's Play sent its start with its queue and entry; Up Next opened on the
  song playing with 99 older rows above it (the first page's 100th was that start, the song playing) and no heading;
  a touch scroll up brought the two older pages from their cursors, the row at the top of the view holding its place
  as each landed above; tapping "Earlier 200" played it next to now from the stand-in, its start sent, the album's
  first song now the queue's own row just under "Earlier 250" with no seam (looked at in a screenshot); a reload put
  the queue back paused with its two starts drawn once, and playing on sent no start; the desktop frame (1440x900)
  drew the same list in the panel, a mouse wheel bringing every page in; nothing in the console - run again after the
  review's fixes, the same. **Not verified**:
  the iPhone and Safari (a pocket's starts reaching deadwax, months of rows scrolled, the tap while the one stream
  plays, VoiceOver through the list); a real Navidrome (the stand-in's shapes only).

### The phone (app 0.8, on the ios branch)

The phone's port is notes/ios.md "Play history on the phone": it keeps the queue's id (snapshot v1 with `id` second,
as the web writes it), records a start at its "now playing" with its queue and entry, keeps the ones deadwax hasn't
taken in the person's store (`start_pending`) and sends them in batches of at most `HISTORY_POST_MAX`, carries a
listen on through a queue put back mid-song (`continuing`, as useResume does), and draws the one list above Up Next's
History with the web's own rules (held to them by ios/scripts/export-history.cjs). So, once the phone runs 0.8, the
open items above that waited on "the phone's port" end: its plays are in the history, a song it began that the web
picks up mid-way is in it once, and a reloaded page reads the phone's snapshot as the same queue.
