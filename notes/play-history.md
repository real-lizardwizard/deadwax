# Play history that lasts

James, 2026-11-13: **"I'd like it if the play history was persistent, so you can always look back and see what you
played yesterday."** His answers, to the design (kept outside the repo at deadwax-plans/play-history.md, its
section 9 overruling the rest):

- **Where: in Up Next, Apple Music's way.** Scroll up past the current queue's History and it keeps going; a tap plays
  the song (since 2.1.18 a tap rolls back to it - "Roll back to a song" below). No separate History page.
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
  away. One Tab stop across both (`historyStop` a number or a past key). An older row's tap (until 2.1.18, which
  rolls back to it instead - below): the key Play Next will give (`nextKey`) read first, then `player.playNext(queued([row.track], 'songs'))`, then - unless
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

### Roll back to a song (2.1.18)

James, 2026-11-14: **"Need a change to the history. Instead of just playing a song in the history, I want to roll back
to that point. Everything between the selected song and the current song should be added to queue so it just moves
back up the list."** His answers: songs added with Play Next and still waiting - **"Keep their place"** (D playing,
tap B: B, C, D, then the songs added, then the rest); the older rows - **"Roll back everywhere"** (everything played
after the row tapped moves back down into Up Next, skips included, even hundreds).

- **The rule.** Up Next is one list - the older rows, History, the song playing, what plays after - and it keeps its
  order: a tap on a row above the song playing moves the playing point up to it, and every row below it is then to
  come, as drawn, the song that was playing among them (from its start, when it comes round). Nothing is copied twice,
  reshuffled or rewritten; deadwax's log is never edited - each song re-enters history as it plays again, a new start.
  This replaces 2.1.3's "a History tap plays the song again: a new song added after the copies" and 2.1.15's older
  row's Play Next then jumpTo (and their claims in the sims).
- **History's row** (lib/upNext.ts `jumpedTo(queue, key, repeat)` -> `rolledBack`, a `Jump` with `back: true`): the
  place moves back to the row's unit; nothing added or copied, the same tracks - Previous's move, many rows at once
  (upnext.sim: "tap 3 with 7 playing" is JSON-identical to Previous four times), and Previous from there plays the row
  above. Outside Repeat One every Repeat One copy after the row goes - a row plays once, as drawn (a copy left would
  replay a song the list draws once; History's row was one row for the run). Under Repeat One each row keeps its
  copies. Playing Next's songs stay where they are, after the song that was playing (James's first answer). `startedAt`
  is untouched (History's rows are at or after it); History's floor (the index less HISTORY_BACK) moves back with the
  place, so songs that had fallen past the 50 are History's again, taken back from the older rows by the join.
- **An older row** (`broughtBack(queue, rows, repeat)`; app/UpNext.tsx `replayPast` with lib/playHistory.ts
  `rowsFrom`): the rows from it down to History's, oldest first, come in AHEAD of History's songs. Each `Brought` is
  the row's song through `queued(…, 'songs')`, the moments of its starts and the entry of THIS queue its first start
  was begun in (`PastRow.entry`, when it was). Each row is one entry: that entry MOVED back with its own mark and track
  (its level, its round) when the queue still holds it before History's floor, it isn't a copy, the song is the same
  and it comes after the last one moved - so the list's songs keep their order and their rounds never go down after
  the song playing - else a new song added ('added': played once, never in a later round). Each carries
  `Mark.starts`. What stood before History's floor and wasn't moved goes (never drawn; the older rows are tapped,
  never walked), the queue from the floor on stays (less copies outside Repeat One), `index` and `startedAt` 0, and the
  id, the list, Shuffle, `left`, `paged` and `pagedRounds` are as they were. Previous from the song tapped starts it
  again: the queue holds nothing before it. New entries sit straight after it, so Up Next draws them under Playing
  Next (Clear takes them); moved ones are the list's.
- **`UpNextState.reached`**: the key of the furthest unit played before the playing point moved back up the list -
  set by both taps and by `wentBack` (Previous is the same move a row at a time); meaningful only while after the song
  playing (`reachedPlace` -1 otherwise, `furthest` keeping a further one). With it, `layout`'s list runs on to the
  reach's own list end (`layoutAt(reach)`), so every row moved back down is drawn where it plays, whatever its time
  round (Repeat All's next round's songs in the one list); `shownKeys` runs to `unitEnd(reach)` even past the list's
  `limit` ("And N more songs" counts them; their starts are the queue's, never drawn above); `withRepeat` judges by
  the later of the round playing and the reach's, so Repeat off or One keeps the rounds moved back down (they played)
  and lets go only of what follows; `withoutKey` hands it to the unit before in its group, `movedKey` to whichever of
  the units at or before it is now last. Before this, Previous back across a Repeat All round left the next round's
  songs undrawn (2.1.15's probe drew their starts above as older rows); they are now the queue's rows to come.
- **Two fixes the property found.** `passPlaying` with no list song at or before the index (rows brought back ahead of
  the list) answers the round of the first list song after it, which they lead into - it answered -1, and a Repeat
  change let go of every round. `movedKey`'s `recast`: Edit's Move in a list that now spans rounds keeps each PLACE's
  round, whichever song is moved there - a song moved up out of the later round is this round's now ("pass 0 after 1").
- **Each start drawn once** (lib/playHistory.ts): `QueueShows.held` is `heldStarts(queue, limit)` - the starts on the
  marks of the entries the queue's rows stand for (shownKeys, the same limit), as `at:songId`; `heldByQueue` is
  shownByQueue or held; `pastRows` skips both, and now keeps every start of a row (`starts`, oldest first) and its
  `entry`. A brought-back entry falling past History's 50 (or put past the rows drawn by Shuffle) lets its starts go
  back above, as the queue's own would. A reload and another device read the same snapshot, which keeps them.
- **The snapshot** (lib/resume.ts; `v: 1`, or `v: 2` for the queues below - "After review"): `reached` (written only
  while it is after the song playing in the window - a queue never rolled back, or played on past where it had got,
  saves exactly as before) and
  `starts: [key, moments][]` for the window's marks carrying any - after `pagedRounds`, in that order; the marks stay
  four apiece, which the iPhone app reads. `fromSnapshot` is strict: each `starts` key a window entry, not a copy,
  given once, with whole moments at or above 0, else null (a plain list) as for every bad field; `reached` must be a
  whole number, and is kept only for an entry after the song playing that isn't a copy.
- **The engine** (usePlayer.ts - spec'd and covered here; streamSource.ts and lib/{playQueue,gapless,scrub,streamWrap,
  streamPlan,fmp4}.ts have no diff): `jumpTo(to: number | readonly Brought[], floor?: number)` - a key through
  `jumpedTo` with `state.repeat`, rows through `broughtBack` with the `floor` Up Next drew them against (After review).
  A `back` jump is moved to as Previous moves: `intendsToPlay`, `change` null, `unlockSpare()`, then
  `moveInStream(jump.queue, true)` - a seek in the one stream when the tracks are the same and it holds the song
  (History's tap with no copies to drop, Gapless on) - else `load(jump.queue, true, true)`, a new stream (or with
  Gapless off the song's URL) made in the tap. Never `replaceUpcoming`: what changed is before the song playing, so
  there is nothing to replan - and so a roll-back is never refused, even with a seek on its way (2.1.3's History tap, an
  edit, could be). Paused, it plays. Everything in the click, nothing awaited; one audio element (two with Gapless), no
  `createMediaElementSource`. Audio unchanged: the same streams, levels and seeks as Previous and a song's tap.
- **Up Next** (app/UpNext.tsx): `replay` is `player.jumpTo(row.key)`; `replayPast` is `jumpTo` with the rows
  `rowsFrom(past, row.key)` gives, their songs through `queued()` as songs, and the floor (History's first row's key, or
  the song playing's) - no `playNext` (app-rules takes it off UpNext's list). Both through `rolledTo`: the card - the
  row tapped, now playing - held where the row was under the finger (a row in view, `seen`; else the card to the top),
  focus to what plays next once taken (`'next'` -> `nextRow()`: Playing Next's first, else the list's, else Done),
  "Playing <title>" said. `took()` knows an older row's tap taken by its entry moved back or an entry newer than the
  tap's `nextKey`. Hidden in Edit with History. Labels unchanged ("play again" on History's rows still reads true: they
  play again).
- **Settled, as asked**: *Shuffle* - no reshuffle at the tap; what comes back keeps the order it played in. Shuffle
  turned on after it shuffles the list's songs to come, the moved-down ones among them, songs added staying first, as
  Shuffle always has - a later Repeat All round's moved down on its own, after (After review); off, the list's order
  from the song playing. *Repeat One* - History's tap brings each row's copies back with it; an older row's brings none
  (Repeat One then repeats the song playing, as ever). *Repeat All* - the rounds moved down are kept by any Repeat
  change; songs brought back new play once. *A library's shuffle* - its pages carry on: `paged` kept, and the feed asks
  when fewer than FEED_BELOW (50) of the list's songs follow the song playing, so after a roll-back it waits until the
  moved-down songs have played to within 50 of the end, then pages on from its cursor - nothing asked twice, nothing
  skipped (upnext.sim). *startedAt* - History's tap leaves it, Previous lowers it as before, an older row's sets 0.
  *HISTORY_BACK* - History's 50 counted from the new place. *Normalization* - History's roll-back keeps the same track
  objects (the same levels); a moved-back entry its own; a new one the setting's song level, as 2.1.15's older-row tap
  queued it.
- **Every bound** (decision: no cap on how far back - James: "even hundreds"):

  | bound | what it is | at a roll-back |
  | --- | --- | --- |
  | the engine | none | all of it plays |
  | UP_NEXT_DRAWN (100) | the list's rows drawn, then "And N more songs" | shownKeys runs on to the reach past 100: every start moved down is the queue's, none drawn above |
  | HISTORY_BACK (50) | History's rows | a brought-back entry past them lets its starts go above again |
  | RESUME_MAX 2000, RESUME_BEFORE 50 (lib/resume.ts and src/play_queue.py; savePlayQueueByIndex takes at most 2000 ids) | a reload keeps 50 before the song playing and up to 1,950 from it | the songs past it go; their starts show above again (the queue no longer holds them), drawn once |
  | RESUME_SNAPSHOT_MAX (262,144) | over it the snapshot is left out: a reload puts back a plain list of the 2,000 | measured with Navidrome-shaped songs (scratch, not a sim): a list over 2,493 songs already went over before 2.1.18 (`extra` holds the list's songs outside the window); a roll-back pushes list songs out of the window, so list plus rows brought back past about 2,500 does the same - a list of 1,000 songs keeps up to 1,510 rows, 1,500 up to 1,006, 2,000 up to 500, an album any number. Then Up Next's account goes (Shuffle, the list's order), and the brought-back starts show above as well as to come. Left as it is, documented. (2.1.22) A library's shuffle no longer counts here: its list is saved as the window's own songs (notes/app.md "A library's shuffle saved however long it plays") |
  | BEACON_MAX (60,000) | the keepalive save as the page goes | about 1,500 rows brought back (some 40 bytes each) pass it: that save goes as a plain request, as any long queue's does; the full save 2 s after the tap carries it |
- **After review** (the same commit, amended):
  - *Old readers dropped the queue* (HIGH). Every reader before 2.1.18 - the web's 5e3460c, which a tab opened before
    the upgrade runs until it is reloaded, and the iPhone app's 0.9 (DeadwaxCore, a port of it) - reads a v1 snapshot
    it can't follow wrong: a roll-back to an older row from another queue puts a song added at index 0, its
    `passPlaying` answers -1, and restoreQueue's `toppedUp(withRepeat(saved, repeat), repeat)` with Repeat off or One
    lets go of every list song after it (`[X] Y A B C D E F` came back `[X] Y`); across Repeat All's rounds
    (`A0 [B0] C0 A1 B1 C1`) the later round went. **Read first, before building on it** (5e3460c's `fromSnapshot`
    and `savedLevels`, the ios branch's Resume.swift - `case .number(1)? = made["v"]` in both - and its
    QueueController.restoreQueue): both read v1 alone; any other version makes `fromSnapshot` null and `resumed`'s
    exact branch puts back `plain(tracks, kept.index, savedLevels(...))` (`plainQueue` on the phone) - the window's
    songs in order at kept.index and kept.position, every mark the list's at pass 0, which withRepeat and toppedUp
    keep whole under every Repeat. The cost, said in docs/player.md: Playing Next, the Shuffle chip, `starts`,
    `reached` and the levels - `savedLevels` refuses the version too, so `relevel(undefined, setting)`: Automatic
    gives the song level, the others their own, as for another app's list. **So `toSave` writes `v: 2`**
    (`snapshotVersion(marks, index, reached, starts)`, the window's marks) whenever the window holds `starts` or
    `reached`, or no list song is at or before the song playing; every other queue is v1, read by old and new alike
    as before. The new reader reads v2 exactly as v1. **The server** (src/play_queue.py `snapshot_problem`) refused
    any `v` but 1 with a 422, which would have refused the whole save: it takes 1 or 2 now (a bool still not a
    number) - the page and the server ship in one image, and old pages write v1. Found doing it: 2.1.17 itself put
    back its own v1 of an album's first song with 60 played next, the 55th of them playing, without the album's 2
    and 3 (Repeat off or One) - no list song in the window at or before it; the web reads that v1 whole since b38d557
    (passPlaying's fallback), and the phone gets a v2. resume.sim runs the old reader itself:
    **ui/test/fixtures/resume-2.1.17/** holds 5e3460c's lib/resume.ts, upNext.ts and playQueue.ts, transpiled to
    CommonJS by TypeScript (`transpileModule`, comments removed, the requires between them named `.cjs`; nothing in
    the app loads them) - given each kind 2.1.18 writes, it puts back every song in order at the song playing under
    Repeat off, One and All, a v1 whole with its account, and the same snapshots forced to v1 lose songs.
  - *Shuffle dropped the songs a roll-back moved down from a later Repeat All round* (MEDIUM): `withShuffle` let go
    of every list song after the song playing but the round's, so Repeat All on A B C, the second round's B playing,
    History's first A tapped, then Shuffle on gave `[A0] C0 B0`, losing A1 B1 C1 (off the same). Now the units after
    the song playing whose round is after its own and up to the furthest played's (`reached`, as withRepeat keeps
    them) stay after the round playing's songs, each with its copies: each round shuffled on its own with Shuffle on
    (the rounds never go down), never starting with the song just before it (toppedUp's rule - over 200 orders,
    none); in the list's order with it off (the round playing's from the song playing's place, as ever). `reached`
    moves to whichever of the units it had moved down is placed last (never the song playing's copies), as movedKey
    hands it on, so the list Up Next draws and the starts it holds still run past all of them (past Up Next's 100
    too) - resume.sim's property found that a copy of the song playing could be named.
  - *A tap racing catchUp lost one song* (LOW): with History at its 50 (s10-s59, s60 playing), an older row's tap
    in the ~250 ms before the timeupdate after s61 began: jumpTo's catchUp moved on first, History's floor with it,
    and broughtBack let go of s10 - drawn in History when the rows were read, neither moved nor kept. **Fixed the
    first way offered**: the tap carries the floor it was drawn against - `broughtBack(queue, rows, repeat, floor)`
    keeps the queue from the earlier of History's floor now and the floor's entry (a key it hasn't, or one after
    History's floor, changes nothing); UpNext passes `view.history[0]?.key`, or the song playing's key with no
    History. Not the second (skipping catchUp on the rows path): catchUp is what keeps the engine's own account -
    the song crossed into gets its start, its scrobble and its place - and the rows path would then roll back from a
    song that had already begun.
  - *Test gaps*: removing `unlockSpare()` from the back path passed player.sim - a case now taps History's row as
    the first gesture on a queue put back paused on an iPhone with Gapless on (one stream), the second element locked
    before and unlocked in it. `broughtBack` taking `row.track` for a moved entry passed every sim - the rows'
    songs are now copies at a level of their own, as `queued(..., 'songs')` makes them (upnext.sim's property and its
    older-rows case, resume.sim's runs), and the moved entries are pinned to their own track and level.
- **The iPhone app** (not touched here): until its port, it reads any queue a roll-back left as v2 - the plain list,
  nothing lost (above). A queue it saves drops `reached` and `starts`, so after it has saved one, songs brought back can
  show above as well as to come, and tapping one there brings it back a second time. (Its own Previous never sets
  `reached`, as before 2.1.18.) Its port, on the ios branch: DeadwaxCore's UpNext*.swift (Mark.starts, `reached`,
  layoutAt/reachedPlace/furthest, passPlaying's fallback, withRepeat's round, withoutKey's and movedKey's reach and
  recast, jumpedTo with Repeat and rolledBack, broughtBack/Brought, Jump.back, shownKeys' reach, heldStarts, wentBack's
  reached, withShuffle's later rounds and their reach, broughtBack's floor); PlayHistory (QueueShows.held, heldByQueue,
  PastRow's starts and entry, rowsFrom); Resume.swift and SnapshotJSON (`reached` and `starts`, written in the web's key
  order and read as strictly; snapshotVersion's v2 written, and v 1 or 2 read); QueueController.swift (`actions.jumpTo`,
  a hashed hand-ported piece: the back path, and the floor passed through); its Up Next's taps (an older row's passing
  History's first row's key). Then ios/scripts/export-traces.cjs
  - its `jumpedTo` calls take Repeat, `referenceSnapshot` writes the two keys, its generators follow this change's
  sims (upnext.sim's first draw spent after seeding, a long album one run in twenty, the older-row op; resume.sim's
  1,000 runs with older rows on even runs) - run, and the traces committed; iostraces.sim fails on that branch until
  then, naming upNext.ts, resume.ts and usePlayer.ts's jumpTo.
- **Verified**: upnext.sim (the property over 2,000 runs, now tapping History's rows and older rows; James's B-C-D
  walk; Repeat One's copies kept and dropped; Repeat All across rounds with Repeat off, One and Edit's Move; Shuffle;
  a long album past HISTORY_BACK; older rows moved and new, out of order; a library's shuffle; the view: the card held
  under the row, the oldest row out of view, an older row's tap and its starts), history.sim (each start drawn once at
  every step, taps and brought-back rows among the moves; the probes now drawn as the queue's rows; another queue's
  rows held, then let go past the 50), resume.sim (1,000 runs - 500 before - the account back at every step; the
  snapshot written as before for a queue never rolled back; `starts` and `reached` read strictly), player.sim (a seek
  in the stream; a new stream when it doesn't hold the song; Repeat One's copy dropped; an older row's tap; Gapless off;
  from pause; during a seek, never refused; on a queue put back), app-rules (the two taps in the click, `queued()`, no
  playNext). On Node 22: every sim (70) - upnext 263 (228 before), history 47 (44), resume 142 (135), player 758
  (746), app-rules 520; `npm ci` and `npm run build`; the whole pytest suite (4220 passed). **Mutated back, one at a
  time, 20 of 20 caught**: copies kept outside Repeat One, passPlaying without its fallback, heldByQueue without
  `held`, layout's and shownKeys' reach, withRepeat by the round playing alone, the snapshot without `starts` or
  `reached`, movedKey without recast, movedKey's and withoutKey's reach not handed on, broughtBack without the `last`
  order, furthest forgetting a further reach, wentBack without `reached`, heldStarts at the default limit, pastRows
  keeping a run's first start only, rolledTo holding a row out of view, took() not knowing an entry moved back, the
  engine's back jump never a seek, and with no back path at all. Four got through the first time (passPlaying's
  fallback, both reach handoffs, took()), so upnext.sim gained the checks that catch them: the list's heading after
  rows brought back ahead of it ("again" without the fallback), Edit removing and moving the furthest song played
  across Repeat All's rounds, and an older row of the queue's own moved back, said and focused. **In a real
  Chromium** - headless Brave over CDP, this worktree's deadwax against the stand-in Navidrome harness of 2.1.15
  (logins off, every other host refused), at `http://deadwax.test:8121` (not a secure context), 250 earlier starts
  sent first, the phone frame (390x844, touch): album playing on to song 3 by its row; History's song 1 tapped - song
  1 playing from the stand-in, History empty, 2, 3, 4, 5 to come with nothing under Playing Next, the card exactly
  where the row was (448 to 449 px), focus on 2's row, song 1's new start sent with the queue and its entry, none of
  the queue's songs above; "Earlier 249" tapped - it playing (so-4), "Earlier 250" under Playing Next, the album's 1-5
  after, two fewer older rows above with "Earlier 248" the newest, the card where the row was; a reload - put back
  paused in the same order, neither brought-back start drawn above again; nothing in the console.
  **After review**, on Node 22: every sim (70) - upnext 274, history 47, resume 155, player 760, app-rules 520;
  `npm run build`; the whole pytest suite (4222 passed). The review's fixes mutated back one at a time, **18 of 18
  caught** by the sims: snapshotVersion's three conditions, toSave always v1, fromSnapshot and savedLevels refusing
  v2, withShuffle dropping the later rounds, not shuffling them, without the seam rule, off not in the list's order,
  not moving the reach, its reach able to name a copy, broughtBack ignoring the floor, the engine and UpNext not
  passing it, UpNext's floor the song playing's, the back path without `unlockSpare()`, a moved entry taking the
  row's track - one (not shuffling them) only once upnext.sim counted each round's orders over 200 seeds; and the
  server's version check by pytest. The 20 above run again: 20 of 20 caught. The review's fixes were not driven in a browser:
  each is reached by the sims (the lib functions; the engine's jumpTo through player.sim's real usePlayer; UpNext's
  tap through upnext.sim's render).
  **Not verified**: the iPhone and Safari (the seek in the one stream on iOS, the tap locked, VoiceOver through a
  roll-back); the desktop frame in a browser (the same component, drawn by upnext.sim); a real Navidrome; the old
  readers on a real device - the web's run from its frozen copy, the iPhone's Resume.swift read, not run.

### Gone back twice: the reach saved while it plays (2.1.23)

The iPhone port's review (HIGH; in main's 2.1.18 as much as the phone's port): a second roll-back could be saved by its
position alone, and deadwax's record lost `reached`.

- **How.** rolledBack and wentBack set `reached` only when the furthest unit differs from it, keeping the same
  `upNext` object otherwise; changedSince compares the queue's objects, so a move that keeps them is a song change
  (`'song'`), saved by its position - deadwax's record is then the last full save's snapshot at the new index. And
  toSave wrote `reached` only while it was AFTER the song playing. So: roll back (reached set, saved in full); play on
  until the reach's song plays; any full save then (an Up Next edit, Repeat's top-up) left `reached` out; tap History
  or press Previous again - furthest() the same key, the state unchanged, the index alone saved. The record: a v1
  snapshot with no reach, at a song before it. The reviewer's Core probe: Repeat All, 3 songs, the second round's 2
  playing; the first 1 tapped; played back to that 2; Play Next x; the first 1 tapped again - read back under Repeat
  off as `1 2 3 x` (the later round's 1 and 2, moved back down, gone; a full save gives `1 2 3 1 2 x 3`), and under
  Repeat All Up Next drew `2 3` with the later round summed in one line. Another device, the web and the phone after a
  relaunch all take deadwax's record.
- **The fix, the writer's** (lib/resume.ts toSave): `reached` is written while it names the song playing's own unit
  or a later one - `found >= unit`, the unit's first entry found by walking back over Repeat One's copies - and
  snapshotVersion follows it (v2). Played past the reach it is still left out: a move back from there names a new
  furthest - a new `upNext`, a change saved in full. So every index a position save can move the record to is one the
  snapshot already describes. The reader is unchanged: it keeps `reached` only while it is after the song playing,
  so read at the song it was saved at it reads as before.
- **Why the writer and not changedSince** (the review's other way: a full save when the reach has come into place
  since the save measured from): changedSince would have to know what the record's snapshot left out - an index-
  dependent rule of toSave's - in useResume.ts and in the phone's ResumeController alike; the snapshot itself is the
  thing a position save reinterprets, so it is the one made to hold at every index it can be moved to. The cost: a
  queue saved while its reach plays is v2 where it was v1, so a reader before 2.1.18 puts back the plain list - as it
  does for every roll-back - instead of reading at the new index a v1 that loses the songs moved down.
- **resume.sim**: the reviewer's probe, step by step (the second tap a `'song'` change; the save between carrying the
  reach, v2; the record put back at the song tapped equal to a full save under Repeat off, One and All, Up Next under
  All drawing `2 3 1 2 x 3`; 2.1.17's frozen reader the plain list; played past the reach, left out). And a property
  over the 1,000 seeded runs, drawing nothing of `random`: at every step History's first row tapped and Previous, and
  each move changedSince calls a song change (9,611 of them, every one back before the reach - any other move back
  names a new furthest) read back from that step's snapshot as a full save of the move would: the reach, Up Next's
  songs to come, and what restoreQueue keeps under each Repeat (All's time round shuffled by one seeded draw each).
  Four mutations, each caught: 2.1.18's rule (the property and the probe), the song playing alone instead of its unit
  (the property alone: a copy of the reach's song playing), written whenever it is in the window, and the version not
  following it.
- **Not changed**: the iPhone app's Resume.swift has the same rule; its port is on `ios`.
