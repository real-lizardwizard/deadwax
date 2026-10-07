# Already in the store (step 2)

The store index and the "already have it" checks.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Already in the store (step 2, 2.0.0-player.7)

Step 2 of the multi-user plan (the plan is a Claude Doc, linked from the agent's memory): "Store
index and the 'already have it' checks at Find and at queueing, with the per-release lock". One
library today, no logins, so "your library" and "the store" are the same thing; the index is built
so steps 4-5 can hang per-user state off it. The spec is the session scratchpad's `step2/SPEC.md`;
an adversarial review of the first cut found eleven real problems, and a second review of the fixes
eight more, all fixed before it was committed (see "After review" and "After review, round two"
below).

- **What changed for the person using it.** Find on a pressing already held complete doesn't
  search Soulseek: the candidates panel says "Already in your library" with the folder, "10 of 10
  tracks" and the formats, and offers no Download. Find on one already downloading WHOLE doesn't
  either: "Already downloading", the peer and the job's state ("queued", "4 of 10 files"), and to
  cancel it in Downloads for another peer - or, for a job past downloading, "Already downloaded ·
  being filed into your library now", with no cancel line (there is no other peer to cancel it
  for). A job for only PART of it (fewer files than the pressing's audio tracks - a lone disc
  folder) is a note ("A download of part of this pressing is already running: 5 files from bob ·
  queued."), the search runs, and it refuses nothing: it will never bring the rest. Held in part,
  the search runs with a note ("You have 9 of 10 tracks of this pressing, in <path>.") and what a
  download would do - see `fills_gaps` below. Another pressing of the same release group held is a
  note in every case. /enqueue answers 409 ("already in your library: <path>", "already
  downloading from <peer>", "already downloaded from <peer>, and being filed now"), which the
  downloads panel shows on the pending row as "refused: ...". The two retries answer
  `moved`/`retried` false with that problem, shown on the row while it is still failed or
  cancelled (a click that lost to auto-retry would otherwise have said "already moved on" in red
  over the new download's progress); AUTO_RETRY_PEER goes through the same refusal and puts it in
  the event log - except `MOVED_ON` and `CLEARED`, where a click or "clear finished" got there
  first and nothing failed. No new settings.
  A release without a release id (the card's fallback with no tracklist) is checked by nothing,
  exactly as before.
- **`store_album` is a table with stable ids, not the scan** (src/store.py). Step 5's per-user
  ledger keys on `store_album.id`, and both the path and the release id change when an album is
  re-filed or a release applied - so every writer UPDATES the row it moved, and nothing is ever
  deleted. An album that goes becomes a tombstone: `missing` when a scan stops finding it (usually
  an unmounted share), `deleted` when deadwax deleted it, `merged` (with `merged_into`) when a
  disc folder merged into its release's. One live row per (root, path), enforced by a partial
  unique index.
- **Which row a folder is.** `index_upsert` (what the writers use, through `index_folder`) takes the
  live row at the path, else the `missing` row at the SAME path with the same release id that went
  LAST (`gone_at DESC, id DESC` - the highest id is only the row made last, which can be an older
  copy's), else inserts - it never revives by release alone: a folder deadwax just wrote is that folder, and
  a fresh download of a release whose share was unmounted used to take the share's row. Only
  `missing` comes back, ever: a `deleted` or `merged` row stays what it is, and a deleted album
  filed again at the same path is a new row. Moves made outside deadwax are paired only in
  `index_reconcile`, which sees both ends: a found folder first takes its own `missing` row (same
  path, same release), then `pair_moved` pairs the rest with `missing` rows of the same release
  only unambiguously - one of each, or else one of each under the same folder basename, which a
  renamed artist folder leaves every album with - first against the rows THIS reconcile just
  marked missing, and older tombstones only for folders still unpaired (one stale tombstone of the
  release made every later rename of it ambiguous). A folder the poller is filing right now
  (`store_index.being_filed`: marked by `organize_job`'s `on_plan` hook before `execute_plan`,
  cleared after `index_folder`, casefolded) is never paired: a scan landing mid-copy found it with
  no live row, and handed the fresh download an unmounted share's id. Otherwise a new row. Before
  this, the discs of a set, or two copies, moved together swapped ids (ORDER BY id DESC picked the
  wrong one). `index_move` takes the row at the old path the same way, recent first, and does
  NOTHING when only a tombstone is left there and the new path's live row carries the moving
  album's release (`reindex_moved` reads it from the moved folder): a scan paired it already, and
  merging it into the tombstone - maybe some older album's - would hand the album that id.
- **Every writer keeps it in step** (`src/store_index.py`): each real scan through `_persist_cache`
  (`reconcile_scan`; never a snapshot - a snapshot is the last scan, not the disk); filing
  (`_organize_if_enabled`, whenever files were placed, the partial-failure branch included, and
  BEFORE the status leaves `organizing` - after it, the index has to say the album is here or a
  second download slips into the gap; since main's 1.1.2 came in at 2.0.0-player.8 it is one block
  with `note_library_changed()` and the review enrolment, and
  `test_filing_that_partly_failed_both_indexes_and_enrols` runs the real organizer with a copy
  failing to hold both); apply release (re-indexed in place right after the tags are
  written, BEFORE the rename pause - up to 90s with Navidrome, long enough to Find and download the
  pressing just applied - then moved or merged after it); artist refile; delete (a `deleted`
  tombstone); hand tag edits (names change). Art, CD art and lyrics change nothing it holds.
- **A scan is a picture of the past, and the reconcile treats it so.** The walk can take seconds on
  a NAS and no writer waits for it (`_scan_lock` is the scans' own). So before it writes anything,
  the reconcile asks the disk about exactly the folders where scan and index disagree - whether
  audio sits there now, AND whether every part of the path is in its parent's listing exactly as
  spelled (`_spelled_exactly`): on a case-insensitive disk (APFS, exFAT, CIFS) `Portishead/...`
  opens `portishead/...`, and a folder known under two spellings kept two live rows for good.
  `index_folder` records a folder as the disk spells it (`_as_on_disk`) for the same reason: a live row the scan didn't find isn't marked missing if its folder holds audio now (an
  album filed or renamed in while the walk went past), and a found folder with no live row isn't
  recorded if it no longer does (an album deadwax deleted or renamed out since - the stale scan
  used to bring a deleted row back, or leave a live row at the old name). A live row a writer
  updated after the scan began (`since`, from the scan's `scanned_at - scan_seconds`) isn't
  rewritten with the scan's older tags. After an ordinary scan none of this looks at anything. It
  marks missing only after a scan that found albums (forget_missing_albums's rule), marks BEFORE
  it records so a moved folder can take back its own row, and writes only rows that changed (a
  warm scan of a thousand albums is one read). `index_move` and `index_merge` also find the row
  when a Find or scan marked it missing in the moment between the folder leaving and the call.
  (A timestamp guard for missing-marking was tried and dropped: `updated_at` is whole seconds, so
  two scans in one second marked nothing. For UPDATES it is only ever conservative - a skipped
  refresh is the next scan's.)
- **Paths relative to the library, however they arrive** (`library_relative`): as given first
  (`relative_to(root)` - the writers hand over `Path(root) / ...`), and only when that fails and
  it isn't absolute, as already library-relative (the routes'); an absolute path against a
  relative root is compared with the root made absolute; anything climbing out is None. It joined
  root on first, so a RELATIVE LIBRARY_PATH made filing, apply and tag edits index nothing and the
  seed record `music/...` where the scan says `...`.
- **The index records the folder's own edition, not the scan's "Standard".** `_mark_multi_edition`
  labels an unlabelled folder "Standard" beside another edition, for display; `reconcile_scan`
  reads the folder's edition back instead, so the scan and `index_folder` can't take turns
  rewriting the row.
- **Seeded once, from the saved scan**, at start-up when the index for LIBRARY_PATH is empty -
  entries hold `Path(root)`-based keys, recorded relative the way read_album_dir does. Never walks
  the disk. An install that never opened the library tab starts empty and fills on the first real
  scan, which `/owned` makes beside the first search after a restart (the library is "behind").
- **Nothing counts as held on the index's word, and what is held is TRACKS.** For each live row of
  the release, the folder must exist and hold audio and `read_album_mbid` (its first audio file)
  must be this release. Then every audio file's folded title and (disc, track) are read as filing
  reads them (`organizer.existing_tracks`: tags, then deadwax's `NN - ` name), and each of the
  release's tracks is held (`held_tracks`) **by title first** - some file carries its folded title
  (`matching.normalize`) and no other track of the release shares it - else by number: its
  (disc, track) as filing keys it (`organizer.planned_key` - per disc on a multi-disc release,
  running otherwise), else its running position on the file's disc 1 or its own. Keyed on numbers
  alone, beets' across-disc numbering, deadwax's own running numbers with no disc tag from before
  v0.6.5, and a stray disc tag (Jackpot Juicer's "Untitled 2") each read a whole album as part
  held. A file titled as ANOTHER of the release's tracks never stands in by number (it is that
  one); a file whose title the release doesn't have at all ("(Remastered)") still counts by its
  number - the likelier case than an interview tagged into a gap, which would count too.
  `complete` is every track held, each once however many files hold it: counting files, the first
  cut let the same tracks twice (FLAC beside MP3, two part copies, an interview track) read as
  complete and refuse the download of the tracks nobody had. Files with neither a title nor a
  number are counted by name against the number of tracks; with no tracklist at all, whatever is
  there is all of it. Reading every file's tags is a mutagen open per track of each held folder, in
  a thread - fine locally, noticeable on a spun-down NAS the first time. A folder that's gone
  becomes `missing`; one whose first file isn't this release (shared with an untagged rip) simply
  doesn't count and the download goes ahead.
- **Video tracks don't count** (`store_index.audio_tracks`). Both payload builders mark a track
  `video` - with `isVideoTrack()` in ui/src/lib/release.ts, for the editor (flattenTracks) and,
  since 2.0.0-player.15, for a download (lib/releasePayload.ts; until then its twin in
  interface/scripts/credits.mjs, for buildExpectedFromRelease, which went with it) - when its
  medium is a video format (DVD-Video, Blu-ray, Blu-ray-R, HD-DVD, VHS, VCD, SVCD, Betamax,
  LaserDisc, CED, UMD, a DualDisc's DVD-Video side) or its recording is `video`. A plain "DVD" or
  "DVD-R" counts only by the recording's flag: it may be DVD-Audio, and an audio track taken for
  video would call a part held complete. `video` is DECLARED on the download `Track` (the pydantic
  trap again). The held check, the part-held note's count and `in_flight`'s covering all leave
  video tracks out, so a CD+DVD deluxe held whole is complete; a release that is ALL video keeps
  every track, or any one file of it would read as the whole. Data tracks were never a problem:
  MusicBrainz lists them in `data-tracks`, which neither builder flattens (the first cut's docs
  said otherwise).
- **`fills_gaps`: where a download would go, worked out as filing works it out.** Filing only ever
  fills the one folder `resolve_album_dir` picks, skipping tracks already THERE; a part held in a
  folder named any other way (Picard's `Artist/Album`, an old template, a pre-0.8.3 country
  suffix, an artist's old name) gets a whole second copy beside it. So for a part held, Find runs
  `resolve_album_dir(quiet=True)` (`quiet` so the event log isn't told an edition is being filed
  separately when nothing is) and answers `held.filed_to` and `held.fills_gaps` (that folder is one
  of the held ones). The note then says "Downloading it files only the tracks that folder doesn't
  have yet" or "A download would be filed separately, in <folder>, rather than fill in that
  folder" - never "fills in the missing ones": a download brings only what the folder picked
  holds.
  `FindCandidatesRequest` DECLARES `disambiguation`, `media_format`, `country`, `catalog_number`
  (and `edition_label`, which nothing sends yet) so the folder resolves as the download's would -
  the builders always sent them and pydantic dropped them, as it dropped `release_group_mbid`.
- **In flight** is a job with the release in `queued`/`downloading`; `organizing` updated in the
  last `FILING_IN_FLIGHT_SECONDS` (3600); or `complete` with no error updated in the last
  `COMPLETE_IN_FLIGHT_SECONDS` (120), and only while organizing is on. A job a restart caught
  mid-filing is settled when the poller starts (`settle_interrupted_filing`, main's 1.1.3, merged
  in at 2.0.0-player.8): it becomes `complete` WITH an error, which never counts. The organizing
  bound stays as the second guard, so a job stranded there any other way still can't block its
  release for ever. `complete` is the moment between the last file and the poller starting to
  file it, the same pass; one older than that finished while organizing was off, and nothing ever
  files it later - the first cut counted it for an hour once organizing was turned on, with no
  cancel button to free it. `idx_jobs_release` makes it one indexed read. **Only a job for the WHOLE pressing
  counts** (`covering`: at least as many files as the release has audio tracks - job files are
  audio only, `group_files_by_directory` drops the rest): a lone disc folder, or a 9-of-10 folder,
  will never bring the rest, so it neither stops Find (it is `downloading_part`, a note) nor
  refuses /enqueue. With no tracklist, any job counts.
- **`release_lock(release_mbid)`** - an asyncio.Lock per release, refcounted and dropped when
  nobody holds or waits for it (routes/library.py's `_APPLY_LOCKS` never shrinks; don't copy it).
  /enqueue holds it across the check, slskd's enqueue and `create_job`. The retries hold it across
  the check and their asks, and **re-read the job under it** (`poller._fresh_job`): the route read
  and checked the job before waiting, and auto-retry holds its copy from the poll, so a job another
  retry had moved meanwhile was asked for again and pointed back at the old peer - two downloads of
  one album. A job no longer failed or cancelled answers `MOVED_ON`; a row that has GONE ("clear
  finished" while the retry waited) answers `CLEARED` - slskd would fetch an album no job watches -
  unless the store is down, when the caller's copy is all there is. A retry of a job with no
  release id locks on the job (`poller._retry_lock`: `job:<id>`), so the re-read still stops two
  retries of it at once. Two enqueues, or two retries, at once with a slow slskd reach slskd once.
  An ENQUEUE with no release id takes no lock - two such provably run side by side.
- **Find's lookup costs little and runs before any search**: one indexed read for the release, one
  for its group, one for jobs, and per held folder a listing, the first file's release tag and each
  file's title and (disc, track); for a part held, one `resolve_album_dir`. For a download in flight it asks
  slskd for that one peer's transfers (bounded at 3s, `PROGRESS_BUDGET_SECONDS`) to say "4 of 10
  files". `FindCandidatesRequest.release_group_mbid` is DECLARED now - the browser always sent it
  and pydantic dropped it without a word, the trap once more.
- **Degrades to "not held"**, everywhere: a store that won't open, an index read that throws, a
  folder that can't be listed - each is logged and costs the check, never the download. A test
  feeds Find a store whose every index method raises; the search runs.
- **The panel** (CandidatesPanel.tsx; the words in lib/candidates.ts `storeStatus`/`storeNotes`,
  pinned in candidates.sim.cjs): held-complete and downloading replace the results area (no "no
  matches", no auto-grab - checked explicitly, not left to the empty list); a download of part of
  it, a part held and other pressings are notes above the results, in that order. `.candidates-store` / `.candidates-notes` in main.css,
  above the responsive blocks, tokens only; paths break anywhere so a stranger's one-word folder
  name can't push a phone's panel sideways.
- **Not built, on purpose**: a better copy replacing a held one (the plan says it replaces the old
  one for everyone - the first time deadwax would delete audio on its own, so it gets its own
  design and James's say); the split "in your library" / "in the shared library" chips (one
  library until step 5); `/library/owned` is unchanged.
- **Verified**: 107 tests in `tests/test_store_index.py` - the table (an old database gains it,
  upsert/tombstones, missing-only revive, the tombstone that went last, pairing incl. a set moved
  together, copies that can't be told apart and this scan's first, a stale scan after a delete, a
  rename and an in-place re-tag, move/merge keep ids incl. from a just-missing row and a move a
  scan already paired, seeding, a relative LIBRARY_PATH, nothing climbing out, two spellings of one
  folder on a case-insensitive disk, a folder being filed), the checks (distinct tracks: two
  formats, two part copies, extra audio, unkeyed files, split discs; titles over numbers, running
  positions, a title the release doesn't have, a file titled as another track; a DVD's tracks and
  an all-video release), in flight incl. both bounds and a job for part of a pressing, Find
  returning early without calling slskd's search, `fills_gaps` for the filing folder, a Picard
  folder and an edition, the 409s, two concurrent enqueues reaching slskd once, two no-id enqueues
  overlapping, the retries refusing incl. a job moved on, a job cleared, two retries at once (with
  and without a release id), and going on from the job as it is now, AUTO_RETRY_PEER (quiet when
  a click won), the rename pause, the poller marking a folder being filed, and every writer through
  its real route with real FLACs. The two spelling tests skip on a case-sensitive disk (they ran,
  on APFS). credits.sim.cjs asks both copies of `isVideoTrack` eight cases (one copy since
  2.0.0-player.15: credits.mjs's went with main.js's builders, and the sim checks it is gone);
  candidates.sim.cjs pins the part-downloading note.
  Mutation-checked, each failing a test: the early return, the 409, the lock, either retry's
  refusal, the empty-scan guard, the organizing age bound, the first-file tag check, the filing
  hook, the reconcile's second look, each writer hook; after review the unambiguous pairing,
  the still-there check before recording, missing-only revive, the retry re-read, the 120s bound,
  `fills_gaps`, and `quiet`; and after the second review title-first matching, the other-track
  guard, the running-position fallback, the video exclusion and its all-video fallback, `video`
  declared, either `isVideoTrack` copy (one since 2.0.0-player.15), the partial-job rule (in the store and in the covering
  count) and its note, the per-job lock, recency in `_missing_here` and `_moving_row`, the
  already-paired move, this-scan-first pairing, exact spelling and the on-disk spelling, the
  being-filed skip, the poller marking and clearing it, the cleared-job refusal, auto-retry's
  quiet, and the `..` guard.
  **Verified in the real page** (the first cut; a scratch copy of the tree on port 8082 with a
  scratch database and library of real FLACs, the bundle built by the rolldown workaround in
  "Tooling and environment", no slskd): a real scan filled the index with Dummy's edition as ""
  beside the scan's "Standard"; Find on Dummy drew "Already in your library", "3 of 3 tracks · FLAC"
  and the 2014 vinyl note without searching; Find on a release with a `downloading` job drew
  "Already downloading", "From alice · downloading"; curl got both 409s; a stale panel's Download
  on Dummy put "refused · already in your library: Portishead/Dummy (1994)" on the Downloads row;
  and at 375px a one-word 110-character folder name broke inside the box, the partial and
  other-pressing notes (find_candidates stubbed in the page, as there was no slskd to search) sat
  above a candidate row, with no sideways overflow anywhere. The review's fixes changed the notes'
  words and the being-filed status, pinned in the sim and the Python tests, not re-seen in a page.
  **NOT verified**: anything against a real slskd or a real library - "4 of 10 files" needs slskd
  to answer for the peer.

#### After review (step 2)

An adversarial review of the first cut, each finding reproduced by an independent verifier (the
review and its repro scripts are in the session scratchpad's `review2step/`). All fixed above; in
short, so none comes back:

- Reviving by release took the newest `missing` row - ids swapped between discs or copies moved
  together, and a fresh download took an unmounted share's row. Now: by path only in the writers,
  and unambiguous pairing only in the reconcile.
- A stale scan undid a writer: a deleted row came back, a renamed album left a live row at its old
  name, an in-place re-tag was rewritten with old tags. Now: the disk is asked first, `since`
  guards updates, only `missing` rows revive, and move/merge take a just-missing row.
- A relative LIBRARY_PATH was joined on twice; now taken as given first.
- Files were counted, not tracks: duplicates read as complete and blocked real gaps. Now distinct
  (disc, track) keys against the release's, keyed as filing keys them.
- DVD/data media never complete: left as a documented limit, the safe direction.
- The retries checked a stale copy of the job; now re-read under the lock.
- A `complete` job nothing would file read "Already downloading" for an hour; now 120s, and the
  being-filed text drops the cancel line.
- The index missed the new release for the whole rename pause; now re-indexed before it.
- "Downloading it fills in the missing ones" was promised when filing would make a separate copy;
  now `fills_gaps` from filing's own resolution, and worded for both.
- The docs said the row shows why AUTO_RETRY_PEER didn't retry; only the log does.
- Three tests proved less than their names: the snapshot test now makes the index differ first,
  the deleted-row test says what it tests, and the no-id enqueue test proves the two overlap.

#### After review, round two (step 2)

A second review, of those fixes (in the scratchpad's `verify2step/`), confirmed eight more:

- Numbers alone misread whole albums as part held (beets' across-disc numbering, running numbers
  with no disc tag, a stray disc tag): titles first now.
- A CD+DVD deluxe held whole was never complete: video tracks are marked and left out.
- A job for part of a pressing (a lone disc folder) counted as the whole pressing in flight, so it
  blocked Find and /enqueue for the rest: `covering` now.
- Retries of a job with no release id took no lock, so auto-retry and a click could both ask:
  locked on the job now.
- Tombstones were ranked by id, not by when they went, in the same-path revive and `_moving_row`;
  and every tombstone a release ever had took part in pairing, so one stale one made every later
  rename ambiguous: by `gone_at`, this scan's first, and a move a scan already paired is left be.
- `still_there` asked `is_dir`, which any spelling passes on a case-insensitive disk: exact
  spelling now, and `index_folder` records the disk's.
- A scan landing while the poller copied an album paired the new folder with an unmounted share's
  tombstone: a folder being filed is never paired.
- The snapshot test had lost its real-scan half, the same-path test called its `missing` row a
  tombstone of any kind, and some comments were stale (Find's cost, the data-disc claim, "fills in
  the gaps"): restored, renamed, rewritten.

**Known limits**, each small and each in the safe direction or bookkeeping only:
- A `complete` job counts as in flight for `COMPLETE_IN_FLIGHT_SECONDS` (120) whether or not the
  poller will file it - a job that finished just before organizing was switched off blocks its
  release for up to two minutes.
- Pairing by folder basename can still pick the wrong tombstone in a rare tie: a folder moved by
  hand, not paired with what this scan found gone, whose name matches an older copy of the release
  that went long ago under the same folder name, takes the older copy's id. Only the id is wrong,
  which step 5's ledger will care about and nothing in step 2 shows.
- `fills_gaps` compares path strings: on a case-insensitive disk a folder spelled differently from
  where filing would go is the same folder, and the note says "separately" when it isn't.
- With a RELATIVE `LIBRARY_PATH` (`music`), a library-relative path whose artist folder is named
  like the root (`music/...`) is read as root-joined. Absolute paths, the norm, are unaffected.
