# Candidates, downloads and peers

The candidates panel, quality filters, retries, peers' speeds and the downloads panel.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### The candidates panel in Preact (v0.9.10)

One of the 1.0 items, and first because the quality filters and "retry with the next peer" build
on it. `components/CandidatesPanel.tsx` mounted into `#candidates-root` (`display: contents`, so
`#candidates-window` stays a child of `#main-container`); its logic is `lib/candidates.ts`, pinned
by `ui/test/candidates.sim.cjs`. About 500 lines left main.js, with the dead download-defaults
reader (`getSettings`) that only it used.

- **Same ids and classes as the vanilla markup**, so main.css applies unchanged and resize.js
  still moves it by `#candidates-header` - delegated from the document, so it never cared who
  drew it. **Verified with a real pointer drag**: 128px each way moved it exactly there, once
  transitions were off. With them on, the frame-starved preview pane left the entrance
  transition part-played and the drag landed half a window off-screen - the harness trap in
  "Tooling and environment", not a bug; measure only after a screenshot has forced a paint.
- **Opened through the bridge (`openCandidates`)** by the vanilla releases grid's two Find
  buttons. They built the release payload themselves (`buildExpectedFromRelease` and
  `buildExpectedFromReleaseGroup`) until 2.0.0-player.15, when both were deleted for the ONE
  builder, `ui/src/lib/releasePayload.ts`, which the bundle hangs on the bridge
  (`buildDownloadRelease`) - see "Sources and Get". `openCandidatesPanel` in main.js is a
  one-line forwarder.
- **Download goes through `lib/downloadRequests.ts`** to the downloads panel's `enqueue`, so the
  "asking slskd..." row still appears on the click. A module rather than the bridge, because
  both panels are in this bundle; the downloads panel registers its handler while mounted.
- **Everything the vanilla panel learned is kept**: one `Search` value only the newest request
  becomes (`lib/latest.ts`, and the aborted request now stops the search in slskd), each row
  downloading as the release it was searched for, filters applied to an answer that lands after
  they changed, format chips cleared per search, the query box cleared per album, and
  `queryOverride` (only an EDITED query overrides - an unedited Re-search searches every name
  again). Filter defaults are read once from preferences, as the vanilla module scope did.
- **One small addition:** Enter in the query box re-searches.
- **Verified in the real page** against the slow fake slskd: results, free-slot and format
  filters, the Signals dropdown (badge, outside-click close, reset), an edited and an unedited
  Re-search (override sent, then not), Download (the pending row at 60ms, "Queued ✓", enqueued
  as All Mine), Escape, and both 0.9.2 races - a filter ticked mid-search kept "Searching" up,
  and Glory Box-then-All Mine showed All Mine with slskd told to stop the Glory Box search.

### Filtering candidates by quality (v0.9.11)

James: "infrastructure to filter and search by bitrate and depth, maybe by file size". slskd
passes Soulseek's file attributes through - `bitRate`, `bitDepth`, `sampleRate`,
`isVariableBitRate` - when the sharer's client reports them; the candidate carried only the
bitrates. It now carries `bit_depths`, `sample_rates` (distinct values across the folder) and
`variable_bitrate`, and the panel filters and sorts on them (`lib/candidates.ts`, pinned in
`candidates.sim.cjs`).

- **Judged by the folder's WORST file.** A 320 album with one 128 track is not a 320 album.
- **Unknown never satisfies a minimum**, the rule the signal sliders already had: an empty list
  means the client didn't say, never "low", and a folder that might be 16/44 must not pass
  "24-bit". **One exception, bitrate only**: an all-lossless folder with no reported bitrate
  passes a bitrate floor, because any lossless file beats any lossy bitrate - hiding every
  unreported FLAC behind "at least 320" would be absurd.
- **Size is the folder's total**, a min and a max in MB.
- **"Search by" became a SORT** - best match (the server's order), highest quality (lossless,
  then the worst file's depth, rate and bitrate; unreported sorts below reported), largest,
  smallest. Soulseek searches can't be narrowed by quality - slskd's search options are peer
  and count limits, nothing about the files - so filtering and ordering the answer is the whole
  of it. Ties keep the match order.
- **The row says what it knows**: `flac 24-bit 96kHz 3000kbps`, ranges for mixed folders,
  `VBR` where any file said so, and nothing invented for a file that reported nothing.
- **Phones: Signals and Quality hang off the whole filter row.** Right-anchored under a button
  near the left of a 375px row, the dropdown ran off the screen (-107px measured). That was true
  of Signals since it was built; nobody had opened it on a phone.
- **Verified in the real page** against a fake slskd offering a 24/96 FLAC, a 16/44.1 FLAC and a
  320 MP3: 24-bit kept only the first, a 320 floor kept all three (the FLACs by rule), a 500 MB
  ceiling dropped the 858 MB hi-res folder, and the quality sort put hi-res, CD, MP3 in that order.

### Trying the next peer (v0.9.12)

One of the 1.0 fixes, long on the "deliberately not built" list because the candidates weren't
kept after enqueueing. They are now.

- **A job keeps the rest of the list AS IT WAS SHOWN** - the user's filters and sort, not the
  server's ranking - up to `MAX_ALTERNATIVES` (10), in `alternatives_json`; `tried_json` records
  every (username, directory) it has been downloaded from. The filters say what they'd accept,
  so the next peer respects them. `EnqueueRequest.alternatives` is DECLARED (the pydantic trap,
  a fifth time avoided rather than hit) and optional.
- **The first schema change to `jobs` since it shipped.** `CREATE TABLE IF NOT EXISTS` never alters
  an existing table, so `JobStore.init` adds any column in `JOB_COLUMNS` that `PRAGMA table_info`
  doesn't list. Keep `JOB_COLUMNS` and SCHEMA in step; a test builds an old table and opens it.
- **The next peer is a different PEER** (`untried_alternatives`): a peer who refused or went
  offline once is the likeliest to again, so every username already tried is skipped, whatever
  the folder.
- **`retry_next_peer` (poller.py)** asks slskd to queue runners-up in turn until one accepts, at most
  `RETRY_ASKS` (3) per retry - each ask can take seconds while slskd connects - and records every
  peer asked, accepted or not. On success the SAME job moves (`store.move_to_peer`): new peer,
  folder and files, back to `queued`, error cleared - it reads as the download carrying on, not a
  second one beside a dead one. The old attempt's settled transfers leave slskd's list and its
  partials go where `SLSKD_INCOMPLETE_PATH` is set (another peer's, so nothing resumes from them).
- **Button always, automatic only when asked.** `POST /download/jobs/{id}/retry` (failed or
  cancelled only, 409 otherwise; a refusal from every peer is a 200 with `moved: false` and a
  `problem`, shown on the row). `AUTO_RETRY_PEER` (off by default, a new Downloads group in the
  settings tab) has the poller do the same on both of its failure paths. Off because the next
  peer down may be a different pressing or a worse rip, a choice somebody should see being made.
- **The row**: "↻ next peer" on a failed or cancelled job with `alternatives_left`, "trying next
  peer…" from the click (a `retrying` overlay, reconciled when a poll shows it active), "try N"
  once moved, and the retry's problem in red when nothing would take it.
- **Verified in the real page** against the slow fake slskd: a job picked from three peers stored
  the other two in the order shown; marked failed, "next peer" asked the offline one (refused),
  then the MP3 peer (accepted), and the row read "queued · mp3-peer · try 3"; failed again with
  nothing left, the button was gone.

### Asking the same peer again (v1.0.7)

James: "a button next to the next peer button to retry the same peer". **↻ retry** on any failed or
cancelled row - it needs no runners-up, so it shows where "next peer" doesn't - calls
`POST /download/jobs/{id}/retry_same`, which runs `retry_same_peer` (poller.py).

- **Only the files that didn't arrive are asked for.** It reads the peer's transfers first
  (`get_downloads([username])`) and leaves out any file slskd lists as succeeded; asking for it
  again would fetch it a second time. When that read fails it answers nothing, and every file is
  asked for, which at worst fetches one twice.
- **slskd supersedes the old record itself.** Read in its source: `DownloadService.EnqueueAsync`
  accepts a file whose previous transfer has ENDED and marks that record removed. So nothing is
  tidied first, unlike next-peer, and no partial file is deleted: slskd resumes from it when
  `retry.partial` is Resume. A test fails if `remove_incomplete_downloads` is reached.
- **A transfer slskd hasn't finished stopping is not asked for.** EnqueueAsync refuses a file
  whose transfer hasn't ended as "Skipped: Already in progress", inside a 201 whose body deadwax
  doesn't read per file. Straight after a cancel that is the usual case, so the route checks
  first and answers `retried: false` with "slskd is still stopping the last attempt - try again
  in a moment", leaving the job as it was.
- **The job carries on as itself**: `move_to_peer` with the same peer, folder and files - back to
  `queued`, error cleared, `tried` unchanged. With every file already there it just goes back to
  queued, and the poller files it.
- **The row**: "asking again…" while it asks (the `retrying` overlay, with `retryingSame` saying
  which kind), the refusal in red, and both buttons in one `.download-job-retries` group.
  **Two buttons didn't fit a 280px panel** (`min-width`, reachable by resizing): the title
  collapsed to nothing and the head overflowed. The head wraps now and the title keeps 5em, so
  on a narrow panel the pair drops to a line of its own at the right; at the 440px default and on
  a phone's full-width panel a row is unchanged.
- **Verified in the real page** against a fake slskd holding bob's failed Dummy (01 arrived, 02
  timed out, 03 refused): the button asked slskd for 02 and 03 only, the row read "asking
  again…" then "queued · 1/3 files · queue #2", and the log "asking bob again ... (2 of 3
  file(s))". Measured at 280px, 440px and 375px: no overflow, the pair adjacent at the right.

### A set shared one folder per disc (v1.0.1)

James, on the Experience edition of Wish You Were Here: a peer had every track, in `CD 1` and
`CD 2` folders "like it should be", and the panel showed two results from that peer that "both
look wrong" - 5 tracks called "CD 1" and the rest called "CD 2". A candidate was one (user,
folder), so each disc was scored alone against the whole two-disc release.

- **`join_disc_folders` (matching.py, pure) makes the set one candidate**: the same peer's
  folders, named as discs (`disc_folder()`: "CD 1", "cd2", "Disc 02", "Disc One", "[CD2]"; or
  "Album CD1" / "Album CD2" side by side), in the same folder, and each a different disc. It
  takes the album folder's name (or, for siblings, the name they share) and carries
  `disc_folders`, which the row shows as "2 disc folders". Left alone when unsure: two folders
  that are the same disc, or an album folder with tracks of its own beside its disc folders.
- **Joined unless the picked release is known to be ONE disc** (`is_single_disc`). A peer's
  "CD 1" of a two-disc deluxe can be exactly the standard album that was picked, and joined to
  its "CD 2" it would rank below itself. Only a Find with no tracklist at all is offered the set
  regardless: since v1.0.3 a card's Find stands for a real pressing, so that is the fallback for
  when MusicBrainz can't say which pressings the album has.
  A disc folder left alone is named with the album folder above it: "Wish You Were Here / CD 2".
- **A track pairs only with files from its own disc's folder** (`file_disc` in
  `match_tracks_to_files`), when some folder names that disc. Discs repeat titles, and a
  containment match took whichever came first: disc 1's "Have a Cigar" took disc 2's
  "Have a Cigar (alternative version)" with disc 2 listed first. That was a bug for the
  organizer even before joining, since it pairs the same way. A test fails without it.
- **The organizer finds each file by ITS folder, not the job's.** A joined job's directory is
  the album folder, but slskd names a download's folder after the file's own remote folder (its
  default `{source_directory}` pattern, read in slskd's `DownloadService.DeriveDestination`) or
  after the whole remote path. `find_local_file` now prefers the match agreeing on the most
  folders counted up from the file; `remove_incomplete_downloads` checks each file's own folder.
  Both discs can hold a file of the same name (`Pink Floyd - Wish You Were Here.flac`).
- **Verified end to end in the real page**, against live MusicBrainz and a fake slskd sharing
  the Experience edition three ways: `CD 1`/`CD 2` with no track numbers in the names and disc 2
  listed first; "... CD1"/"... CD2" siblings; and a lone `CD 2`. The first two scored 100 and 99
  as "11/11 tracks · 2 disc folders", the lone disc 61 as "Wish You Were Here / CD 2". Downloaded
  and filed in copy mode, all eleven tracks landed on the right disc and number, both "Wish You
  Were Here"s (335s on disc 1, 374s on disc 2) and both "Have a Cigar"s included.

### The peer's advertised speed is not your download speed

- **`upload_speed` is the peer's average upload rate over their whole history, to everyone —
  not a prediction of this transfer.** Soulseek reports it per user, so it is divided among
  however many people they are serving at once and averaged over conditions that no longer
  apply. It reads high far more often than it matches, which is what prompted this.
- **It used to render as `▼ 1.2 MB/s`, and a download arrow is a promise.** It now reads
  `peer avg 1.2 MB/s` with a tooltip saying what it is and is not. This is a correctness fix,
  not a cosmetic one: a number that visibly never matches teaches you to distrust every other
  number on the row, including the match score, which is the one worth trusting.
  **Do not "simplify" the label back to a bare rate.**
- **`has_free_slot` and `queue_length` are the better predictors and are already on the row**,
  which is why the fix was to relabel rather than to hide anything.
- **The units comment stays.** BYTES/sec, not bits — see the note in `matching.py`. Two
  separate things were once wrong here: the units (fixed earlier) and the meaning (fixed now).
  An older comment calling it "our download speed" is what the interface then went and claimed.
- **deadwax already weights it correctly**, and that did not need changing: `score_peer()`
  grants at most 0.2 for speed, and `peer` carries **0.08 of 1.0** in `WEIGHTS` — the lowest
  of the six signals. It is an availability tiebreaker, never a ranking criterion.
- **`.candidate-peer` had to gain `flex-wrap: wrap`.** The three chips fitted while the speed
  was `▼ 1.2 MB/s`; the longer label overflows a 159px row at 375px, and the panel is inside a
  fixed-width window with nowhere to overflow to. Measured after: `scrollWidth === clientWidth`
  on every row, document scroll width 375, two lines per row.

### Measuring what a peer actually gave you

Added in v0.6.4. `src/peer_speed.py` is pure and holds all of it; the poller feeds it and the
store keeps one row per peer.

- **There is NO way to know a transfer's speed before it starts.** Nothing in the Soulseek
  protocol probes throughput without moving bytes, so the only honest number is one you
  measured. That is what this is, and it is why the answer to "can you predict it" is no and
  will stay no.
- **Measured in the POLLER, not in the browser.** `ui/src/lib/speed.ts` already derives a live
  rate and reusing it was the obvious first idea. It is wrong: downloads run server-side and
  most finish with nobody watching, so a browser-side measurement records nothing for exactly
  the transfers you did not sit through.
- **It cannot be backfilled, and that is not laziness.** Deriving a rate from existing job rows
  means `created_at` -> `updated_at`, which spans the queue wait — a job queued 20 minutes and
  transferring in 2 computes a tenth of its real rate. Believable, consistently wrong,
  invisible by inspection. The existing data genuinely cannot produce this.
- **THE MEASUREMENT RULE, and two wrong versions of it that the tests caught.** What is
  measured is the span between consecutive MOVEMENTS of the byte counter, counted only when
  those movements are close enough together to have been one continuous transfer.
  1. *Bytes over wall-clock* is wrong for the queue reason above.
  2. *"Count an interval only if the previous interval also moved"* is wrong and **worse**,
     because it fails on the ordinary case rather than the rare one. We poll faster than slskd
     refreshes its counter, so movement and stillness ALTERNATE during a perfectly healthy
     transfer — the same fact `speed.ts` exists to handle — and that rule discarded every
     interval, measuring nothing at all. It passed the queue test and failed reality.
  So a still counter is judged by HOW LONG it stays still. Short (`MAX_COUNTER_LAG_SECONDS`,
  12s) is refresh lag and the span counts; longer is a queue or a stall and the measurement
  re-anchors past it.
- **`measured_rate()` returns None, never 0.0, and callers must not coerce it.** "We never got
  a good look at this peer" and "this peer gives you nothing" are opposite claims, and the
  second would render on a candidate row as measured fact.
- **Recorded on FAILURE as well as success.** A peer that half-sends gave you a real rate while
  it was sending and is exactly one you want a number for. A refusal that moved no bytes
  measures nothing and writes nothing — that is `measured_rate()` returning None, not a
  special case.
- **The average is capped at `SAMPLE_WEIGHT_CAP` (10) effective samples**, becoming an EMA past
  that. A plain running mean would hold a peer's first hundred transfers against them forever,
  through a house move and a new ISP.
- **On the row, the measured figure LEADS and the advertised one follows**, in green, because
  it is a different kind of thing rather than a second opinion of equal standing. **On mobile
  the advertised one is hidden when a measurement exists** — same principle as the connection
  pills, only render what earns its space, and it is strictly superseded there. It still shows
  when there is no measurement, which is most peers.
- **Absence is the ordinary case and renders as nothing.** Most peers have never been
  downloaded from. `_attach_measured_speeds()` therefore fails silently: a degraded read looks
  exactly like a peer nobody has met, which is the correct thing for it to look like.

### The downloads panel's optimistic overlays

- **Cancel and "clear finished" update the screen BEFORE the server answers, not after.**
  Both actions cost two sequential round-trips — one to deadwax, which itself calls on to
  slskd, and then a poll to see the result — and until v0.5.2 the row was pixel-identical for
  the whole of both. That is what "the buttons feel laggy" actually was: not slowness, but a
  UI that showed nothing at all while it waited to be told it was allowed to.
  Measured after: **3ms** to a visible change on cancel, **1ms** on clear, against ~1.6s and
  ~2.4s for the server to come back.
- **The overlay is laid over the polled data, never merged into it.** `jobs` from the poll
  stays authoritative and is never edited, so the worst case is a prediction that turns out
  wrong rather than corrupted state. `ui/src/lib/downloadOverlay.ts` is pure and holds all of
  it; the hook only decides when to call it.
- **Reconcile against the DATA, not against the request completing.** A cancel request
  returns before the job's status has necessarily changed, so dropping the overlay on
  completion flips the row back to "downloading" for one poll before it finally reads
  "cancelled". Waiting for the server's own answer to agree removes that flicker. The sim
  pins this case specifically.
- **A cancelling row stays in the list.** It is dimmed and reads "cancelling…", but it is not
  removed, because the transfer really is still running until slskd stops it. It does stop
  counting as active, which is what drops the badge and the toolbar summary on the click.
- **There is a 15s expiry on every overlay** (`OPTIMISTIC_TTL_MS`). If the server never
  confirms, the prediction is abandoned and the truth reasserts itself. An optimistic state
  that outlives its request stops being a prediction and becomes a lie — a row stuck on
  "cancelling…" while the file is still arriving is worse than never having said it.
- **A download is in the panel from the CLICK (v0.9.9, asked for: "I would like it if the
  downloads showed up in the downloads pane a bit quicker").** A job is recorded only once slskd
  accepts the enqueue - kept, so a refusal never leaves a phantom job - and slskd doesn't answer
  until it has looked the peer up and CONNECTED to them (`DownloadService.EnqueueAsync`:
  `GetUserEndPointAsync`, then `ConnectToUserAsync`), seconds for a firewalled peer. The panel
  had nothing to show for all of it. Now the Download button goes through the panel's own
  `enqueue` (through `lib/downloadRequests.ts` since the candidates panel was ported in v0.9.10 -
  a bridge entry, `enqueueDownload`, until then),
  which lays a `PendingDownload` overlay - "asking slskd…", the loading sweep along its empty
  track, counted as active so the badge moves too - and hands over to the real row when a poll
  brings the job (`visiblePending` hides it on that same poll, so both are never drawn). A
  refusal turns it into "refused" with slskd's own words and it stays, like any finished row,
  until "clear finished". Measured with a fake slskd taking 4s to enqueue: row in the panel at
  52ms, real row ~250ms after slskd answered.
  **slskd's reason needed its own fix**: slskd_api's `transfers.enqueue` returns `response.ok`
  and drops the body, and its session RAISES on a non-2xx (a response hook calling
  `raise_for_status`), so `SlskdClient.enqueue` posts on that session itself and reads the
  body off the `HTTPError` - "User bob appears to be offline" rather than "refused".
- **`/jobs` asks for queue positions side by side** (v0.9.9) - one after another, every queued
  job added a slskd round trip to every poll of the panel.
