# Candidates, downloads and peers

The main page these describe retired in 2.0.0-player.66 (see "The main page retired" in notes/app.md); the reasoning is kept as history.

The candidates panel, quality filters, retries, peers' speeds and the downloads panel.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

**With logins on, downloads are per person** (2.0.0-player.49): who sees which, joining a download
somebody else asked for, cancel as leave, retry by any requester, Clear finished as hide, and one
Soulseek search starting at a time - notes/logins.md "Downloads per person (2.0.0-player.49)".

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

### Manual search (2.1.37, 2.1.38)

James (2026-11-24): "let's add a manual search in the requests tab" - chosen as **Soulseek by artist + album**:
type an artist and an album, including ones MusicBrainz doesn't have, see the folders people share ranked by
how well they fit, then by format and speed, and Get one. The iPhone and Mac app only, never the web. The
whole design, with the app's half and the checks for James's devices, is
`~/Desktop/Code/deadwax-plans/manual-search.md`; this is the server's half as built. One flag, `manual`,
declared on `FindCandidatesRequest` (2.1.37) and `EnqueueRelease` (2.1.38) - no new route, no schema change.

**Why the ranking had to change (2.1.37).** A question with no release id and no tracklist - the web's "album
as a whole" Get, and a manual search - has every track signal None, so the score renormalised over edition,
format and availability: **nothing scored the folder's name against the words**, and a wrong album the same
words found scored the same as the right one. So `matching.name_match(directory, files, artist, album)`, a
seventh signal, pure, 0..1:

- every word set is `normalize(text).split()`. **Noise**: all-digit words, `\d+(bit|khz|k|kbps)`,
  `FORMAT_WORDS`, disc markers (`_DISC_MARKER`, matched on the normalized TEXT, so "disc one" is both its
  words) and the, a, an, and. **Edition words**: every word an `EDITION_PATTERNS` match touches (so "super
  deluxe" and "box set" are both their words), plus "edition" - the edition signal's alone, never counted twice;
- A (the typed album) and B (the typed artist) lose their noise and edition words unless that empties them
  ("1989", "The The", Harmonia's "Deluxe");
- D is `folder_label(directory)`'s words ("Album / CD 1" for a disc folder) - or, when every word is noise
  (a "FLAC" inside "OK Computer"), the folder above the label's, once. Cleaned: B's words out - all of them
  when A hasn't the word; when A has it (a self-titled album), ONE occurrence, counted, and only the artist's
  own: before a dash (`_artist_prefix`: the name opens with B's words and a spaced dash or an en/em dash -
  "Weezer - Pinkerton", not "Jay-Z") or where the name has the word more often than the typed album does
  ("Weezer Weezer"); a name left with nothing is the self-titled album's and keeps it ("Weezer - 1994
  [FLAC]"). Noise out unless in A, edition words out **unless in A** (a departure:
  the plan takes them out unconditionally, which would score Harmonia's "Deluxe" folder 0 against its own
  typed name; A keeps an edition word only when it has nothing else, so "edition words don't lower the fit"
  is unaffected);
- `album_fit = |A ∩ D| / |A ∪ D|` ("OK Computer" against "OK Computer OKNOTOK" is 0.67); `artist_fit` is the
  share of B's words found in the path's words, or - per word - in at least half the audio files' names;
  `name_match = 0.65 album_fit + 0.35 artist_fit` (`ALBUM_FIT_SHARE`). A field with no words left (punctuation
  only) has no opinion, as a None signal has none: the other alone, and 0 with neither.

`score_candidate`, when `expected["manual"]`: `signals["name_match"]` first (the app draws the reasons in
order), and the score is `MANUAL_NAME_WEIGHT (0.80) x name_match + 0.20 x` the usual weighted blend of the
active signals - so fit comes first and format and availability sort folders that fit equally. The plan's worked
examples hold (prefer_lossless): a perfect fit in MP3 from a slow peer 0.92, a 0.67-fit FLAC from a fast one
0.83, a perfect FLAC 1.00, a perfect INSTRUMENTAL 0.95 (ranked under the plain one, its edition tag shown).
lossless_only still filters, the limit is still 50. **Without `manual` nothing changes**: no `name_match` key,
the same score - held by `test_a_question_without_manual_scores_exactly_as_before`, whose numbers were computed
from matching.py as it was at 2.1.35. **The 0.80 and 0.65 are reasoned, not measured**: check M3 settles them
on James's own searches.

The route: `find_candidates` answers **400 "Type an artist and an album."** for a manual question with either
field blank after stripping (the app never sends one), before anything is searched, and `expected` carries
`"manual": body.manual`. The search itself is any Find's - the typed words under `search_names`, no MusicBrainz
lookup (no artist id), `_store_state` silent (no release id); `query_override` is searched as typed and still
scored against the two fields.

**Review (2026-11-24), the artist's word in a self-titled search.** As first built, a word both the artist's
and the album's was kept in every folder name, so typed Weezer / Weezer gave `Weezer - Pinkerton` 0.675 and
`Weezer/Weezer (Blue Album) [FLAC]` 0.567, and `Peter Gabriel - So (1986)` tied `Peter Gabriel 3 (Melt)` at
0.783. The review proposed counting one occurrence of each artist word out of every name; that alone ties
"Weezer (Blue Album)" in `Weezer/` with "Weezer - Pinkerton" (both lose their one Weezer) and Melt with So,
so the occurrence counted out is the artist's own - before a dash, or one too many - as above. Pinkerton is
now 0.35, the Blue Album 0.567, Melt 0.783 and So 0.35;
`test_a_self_titled_search_ranks_the_album_above_the_artists_others` holds five such pairs at equal format
and peer (seen failing before the fix, and with the plain one-out-of-every-name rule).

Tests: tests/test_matching.py's "a manual search" section (fit, order, bounds, unchanged), and
tests/test_manual_search.py through the whole app with real JSON (the flag reaches the ranking - it fails with
the field undeclared - the 400, and no `name_match` without it). Every fault the plan lists was put in and seen
failing, then restored.

**Filing by its own tags (2.1.38).** What happened to a release-less, trackless job was the opposite of what
a manual search wants: the folder named from the TYPED words (a lowercase "radiohead" made a second artist
folder), shared with any folder of that name (a known pressing's folder got an unknown pressing's tracks),
album/albumartist/artist overwritten with the typed words on every file (a compilation's artists lost), a
CD1/CD2 set with "01.flac" in each colliding ("two files map to the same destination"), and - the surviving
date tag making the expected name "OK Computer (1997)" - every tagged share flagged `misfiled`. All of it is
now changed only when `release.get("manual")`; every other job plans and writes exactly as before
(`test_a_release_less_job_without_manual_is_planned_and_tagged_exactly_as_before`, the group fallback's plan
and tags spelled out).

- `EnqueueRelease.manual` declared, reaching release_json through `model_dump()` - **only when true**
  (`exclude={"manual"}` otherwise), so every other job's stored release is byte for byte what it was.
- `plan_organization` finds every source FIRST (`located`, once per file - the loop used to find each as it
  went; same calls, same results), then for a manual job `_manual_names` reads each with
  `library.read_track` (imported inside: library imports organizer at its top) - an unreadable file is
  `{}`, untagged, and reading never raises - and `own_tags_release(release, tags)` (pure) names it:
  `_commonest(albumartist) or _commonest(artist) or` the typed artist, `_commonest(album) or` the typed
  album, `_commonest(date)[:4]`, `_commonest(originaldate)[:4]` - **library._commonest over the tags in the
  scan's own running order** (`track_order`, with each file's filed name), so the folder is named from
  exactly what `read_album_dir` reads back and `expected_dirname` agrees, ties included. No edition fields,
  no ids, `manual: True`. The plan carries `manual` and `naming` (only on a manual plan).
- `resolve_album_dir(..., manual=True, job_id=...)` -> `_resolve_unmatched_dir`: the plain name, then
  `[unmatched]`, then `[unmatched-<job id>]` (then `-2`, `-3`…, never back to a pressing's
  folder), sharing a folder only when no audio file in it holds a release id (`holds_album_id`, which reads
  every file, and counts a folder it can't list as holding one) - an untagged folder (the settled rule), its
  duplicate titles skipped by `find_duplicate` as for any id-less job. `UNMATCHED` goes through the
  template's discriminator, so `edition_from_dirname` reads it back and the folder isn't misfiled; Apply
  release renames by the release and drops it (retag's merge when that pressing is already held - read, not
  run).
- Files keep their sharer's names; when the job's audio spans more than one disc, a `<disc>-` prefix, the
  disc from the file's own disc tag else its folder's marker (`matching.file_disc`) - from the file's facts,
  no number made up, and none on one disc. A disc is a number from 1 (a `-1` or `0` tag is none); when the
  tags name one disc or none but the folders' markers several, the folders' are used. Names that still meet
  (compared case folded, as a case-insensitive disk would) take their own folder's name before them
  (`Side A-01.flac`), and anything left is numbered (`01 (2).flac`): no two sources are ever planned to
  one name.
- Each audio operation carries `fill` (`own_tags_fill`, pure): `album` when the file has none; `artist` and
  `albumartist` only when it has NEITHER (a compilation's per-track artists without an albumartist get no
  albumartist). `execute_plan` calls `write_own_tags(path, fill, drop=MANUAL_DROPPED)` for a manual plan
  instead of `write_tags`: only the fill set, `musicbrainz_albumid` and `musicbrainz_releasegroupid` deleted
  (the v1.0.1 rule, extended to the group), the artist ids kept (they say who; Apply release rewrites them),
  failures logged and tolerated. Easy MP4 has no name for the group, so for an m4a the raw atom the scan reads
  (`library.MP4_RELEASE_GROUP_ATOM`) is deleted too. The plan writes nothing (`test_a_manual_plan_touches_nothing`).
- The poller's `_enrol_for_review` labels a manual plan's review row with `naming`'s artist and album, not
  the typed words. `grant_job` is untouched: same_release is always False without an id, so a filing is
  ADDED and everything already there FLAGGED (logins on), as for any id-less job. Library care's flag keeps
  the typed words as its label.
- Find's answer gains `"manual": true` for a manual question (left out otherwise) - the app's gate: an older
  server would drop the flag and file by the typed words. `/jobs` reads `json_extract(release_json,
  '$.manual')` beside the group and edition, and a row gains `"manual": true` only when true.

What stays as it is, on purpose (the plan's 2.4): no "already have it" check by name, no lock for a manual
Get (two at once are two jobs; the second files its new tracks or is FLAGGED), `_store_state`, `already_have`,
`in_flight`, `held_copy` and `other_pressings` untouched.

Tests (real mutagen FLACs, and the tiny m4a): tests/test_organizer.py's "a manual search, filed by its own
tags" - Picard-tagged FLACs, typed lowercase, untagged, mixed, a two-album folder, every collision, CD1/CD2,
the binding check (`inspect_album` of the SCANNED album holds `no_release` and neither `misfiled` nor
`artist_split`, four shares), the golden job, grants, errors degrading, the m4a; tests/test_poller.py (the
review row's label, unreadable files through the whole poller); tests/test_jobs_route.py (`manual` on a manual
row only); tests/test_manual_search.py (stored as declared, nothing stored otherwise, Find's echo). Every
fault the plan lists for S2 was put in and seen failing, then restored.

Not verified: a real slskd and Navidrome (the poller's path for a release-less job ran only against the
suite's fakes); Soulseek's real tag habits; whether Navidrome shows an `[unmatched]` album beside a matched one
of the same name as one album or two (M9 - it decides S3's "exactly one" rule).

**Review (2026-11-24), what it found and what was fixed.** Three things, each with a test seen failing first:
- *Filing safety.* `read_album_mbid` answers from the first readable file, so a matched pressing's folder
  whose first file was untagged (a hidden track sorted first) read as untagged, and a manual download was
  filed into it. A manual job now asks `holds_album_id`, every file read; read_album_mbid's other callers
  were left as they are (the non-manual `resolve_album_dir` shares the same blind spot for a matched job -
  reported, not changed then; fixed in 2.1.39, below). `test_a_folder_naming_a_pressing_in_any_file_is_never_shared_though_its_first_is_untagged`.
- *Ranking.* The artist's word in a self-titled search - in 2.1.37's write-up above.
- *Filing.* The disc prefix trusted the disc tag over the folder: CD1/01.flac and CD2/01.flac, both tagged
  disc 1, met on one name and 2 of 4 files were filed with `failed: 0`; a `-1` disc tag named `-1-b.flac`.
  Now the folders' markers when the tags can't tell discs apart, a disc from 1, and no two sources to one
  name (the bullet above).

Known limits, kept on purpose:
- Under an `ALBUM_FOLDER_TEMPLATE` without `{edition}`, the discriminator is appended as ` [unmatched]`, which
  `edition_from_dirname` doesn't read back, so Needs a look flags that folder "Folder name doesn't match the
  tags" until a release is applied.
- An INSTRUMENTAL (or any other edition) of the album scores 0.95 to the plain one's 1.00: only 0.20 of a
  manual score is left to edition, format and the peer, so a plain MP3 from a busy peer falls under an
  instrumental FLAC from a free one. Edition is weighted, never a filter; its tag shows on the row.
- A manual download of a pressing deadwax already holds is filed as a second copy, under `[unmatched]`: the
  sharer's ids are dropped before filing and a manual job never compares them, so nothing says it's the
  same. Applying that release to it later goes through retag's merge (read, not run).
- A CD1/CD2 set whose files are all tagged disc 1 keeps that tag (a file gets only what it lacks): the
  files are filed apart, but the scan reads every track as disc 1 and orders them by number, then name -
  1-01, 2-01, 1-02, 2-02, the discs interleaved - until a release is applied.

### Every file's release id (2.1.39)

James, 24 Nov, on the blind spot manual search's review found: "Yes, fix it first". `read_album_mbid` read the
first readable audio file and stopped - "every track in a folder belongs to the same release". Not so: a hidden
track or a bonus rip with no tags, sorted first by name, made a folder of one pressing read as untagged, and the
untagged rule ("never treat unknown as different") then shared it with a download of ANOTHER pressing. Its
tracks went in, and the scan, which keys a folder on its commonest id, counted them as the first pressing.

- **`organizer.folder_release_ids(directory)`** reads every audio file with the scan's own reader
  (`library.read_track`), in the scan's running order (`track_order`), "" for a file with none. A folder that
  can't be listed raises, as before - the caller decides, nothing is guessed.
- **`read_album_mbid` is the commonest of them** (`library._commonest`, the scan's rule, ties to the first in
  running order), None when no file has one. So a folder is the release the scan will call it - for every caller
  at once: `resolve_album_dir` (sharing a folder), the plan's `same_release` (duplicates by number or by title),
  the store index's `_look` ("tagged") and `_moved_to`, and Artwork's lookup by the album's own release.
- **`holds_album_id`** (a manual search's: any id at all) reads the same list; an unlistable folder still counts
  as holding one.
- **What changes for a folder mixing untagged files with one release's**: it now counts as that release for
  sharing a folder and for Find's "already have it". Untagged files don't vote, so ONE tagged file among ten
  untagged ones makes the folder that release - an old rip that one deadwax download filled in. Before, it
  depended on which file sorted first.
- **Duplicates are judged file by file** (the review, below): `existing_tracks` carries each file's own id
  (`_read_track_and_release`, the same open), and `find_duplicate(existing, key, title, release_mbid)` matches a
  file tagged with this release by (disc, track), any other file - untagged, another pressing's, or all of them
  for a job naming no release - by title. It returns the entry, not its name.
- **The plan's `same_release`** (what grant_for gives on a filing that placed nothing) is the folder's commonest
  id being this release AND every track found already there being found in a file of this release. A twin in an
  untagged rip's file makes it False: FLAGGED, nobody's on a guess.
- **Cost**, N audio files in the folder (each open parses the tags, embedded pictures included):

  | path | before | now |
  | --- | --- | --- |
  | Find, `/enqueue`, retries, Add to my library (`_look`), per held folder | N+1 | 2N |
  | Find on a part-held album (`filing_folder` -> `resolve_album_dir`), per candidate folder | +1 | +N |
  | the filing plan on an existing folder (resolve, `existing_tracks`, `same_release`) | about N+3 | up to 4N |
  | an artist's re-file (`reindex_moved`), per album | 1 | N |
  | Library care's bulk Get covers, per album without art | 1 | N |

  Nothing runs per track or inside a scan; the bulk run waits on the network anyway. Not measured on a NAS.
  Left for later: `_look` and the plan could take the commonest from `existing_tracks`' own pass, but it is in
  name order with the filename's number as a fallback, so a tie could differ from the scan's.

Tests (`tests/test_editions.py`), each seen failing on 2.1.38's code:
`test_a_folder_is_known_by_its_files_though_its_first_is_untagged` (a hidden untagged "00" first, the rest
another pressing: kept apart by its catalogue number; the same pressing still shares it) and
`test_a_folders_release_is_its_commonest_as_the_scan_reads_it` (a stray id outvoted; a 1:1 tie goes to the
first in running order, not by name, exactly as `read_album_dir` - seen failing with the sort taken out; no ids
is None). One test pinned the old accident and was restated: tests/test_store_index.py's
`test_a_folder_whose_first_file_is_not_this_release_is_not_held` (this release's two tracks and an untagged
"00 - Intro" read as not held, where a "99 - Outro" would have been held) is now
`test_a_folder_is_this_release_by_most_of_its_files_not_by_its_first`: held, complete; not held once three files
name another release, nor with every file untagged. It fails on 2.1.38's code.

**The review (one agent, 24 Nov).** No folder where `read_album_mbid` and the scan disagree (same files, order,
tie-break, stripping; an unlistable folder raises as before; `read_track` is more forgiving per file than the old
unguarded `audio.get`). No import cycle (store_index imports library at its top). Found and fixed:
- *A gap-filled rip judged as the pressing.* With the folder's commonest id deciding `same_release`, a rip of ten
  untagged tracks plus deadwax's bonus track 6 of the eleven-track pressing read as that pressing, and a second
  download's "Closing" (its 11) found no file numbered 11 and was filed beside the rip's "Closing" (its 10) - one
  song twice; and a filing that placed nothing there was granted, not flagged. Fixed by judging duplicates file
  by file (above). tests/test_no_second_copy.py's `test_an_untagged_rips_numbers_never_say_which_song_it_is`
  (seen failing with the folder judged as a whole, and its `same_release` line with the grant change taken out)
  and `test_everything_already_in_this_pressings_files_is_the_same_release`.
- *The docs said "most of its files"*; untagged files don't vote. README, organizing.md and downloading.md say
  "its tagged files name most often" now, and organizing.md's second-copy rule is file by file.
- *Cost understated* ("once more"): the table above.
- Noticed, not changed: disc_art.py (around 220) takes the first file that has an id, not the commonest; a
  folder whose first file is untagged now gets Library care's bulk Get covers (bulkTargets picks by the scan's
  id, which the art lookup now agrees with).
