# Decisions that should not be re-opened

The full reasoning behind each settled decision. CLAUDE.md lists them in one line each.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

## Decisions that should not be re-opened

- **Matching is pure.** `matching.py` does no I/O so it's testable without slskd. Keep it that way.
- **Plan/execute split in the organizer.** `plan_organization()` is pure; `execute_plan()` acts.
  This is what makes dry-run trustworthy — it runs the *identical* plan and declines to execute.
- **The release is stored denormalized** in the job row, not as a bare MBID. MusicBrainz goes
  down often (it did, repeatedly, during development); organizing a finished download must not
  depend on it being reachable.
- **Progress is never persisted.** slskd owns it, it changes every second. Derived on read,
  divided by files *wanted* rather than files slskd currently reports.
- **`ORGANIZE_MODE` defaults to `dry_run`.** Organizing is the only thing that writes to the
  user's filesystem. A fresh install reports what it *would* do.
- **Edition matching is a weighted signal, never a filter.** See above.
- **The folder is named after the album's year, not the pressing's.** A 2011 remaster of a
  1975 record files under `Wish You Were Here (1975) [Remastered]`. The year identifies the
  album and the edition identifies the pressing; using the reissue year would file the same
  record under two different decades depending on which copy you got. It comes from
  MusicBrainz's release-GROUP `first-release-date` (`original_year` on the payload, written
  to the `originaldate` tag); the `date` tag still records this pressing's own year. Absent
  `original_year` the behaviour is exactly as before, so nothing already filed moves.
  **Downloads never sent it until v1.0.2** - only the metadata editor did. Neither builder in
  main.js set `original_year`, so every download of a reissue was filed under the pressing's year
  and flagged "no original year". Found while verifying the disc-folder fix: the Experience
  edition filed as `(2011)`. Both builders send the group's first-release year through
  `realYear()` (null, not 'N/A', when MusicBrainz has none) - the version of this fix
  player-spike made in its own review, kept over main's `albumYear()` when brought over in 1.0.4
  because it also stops 'N/A' going out as `year`; verified in the real page, a row's Find filing
  `Wish You Were Here (1975) [Experience edition]` with date 2011 and originaldate 1975, a card's
  `(1975)`.
- **The search type filter narrows the QUERY, not the results.** That distinction is the whole
  point: MusicBrainz spends the `limit` on whatever matches, so for a prolific artist it goes
  almost entirely on things nobody wanted. Measured — `releasegroup:"Metallica" AND
  artist:"Metallica"` returns 25 groups of which **15 are Live, 6 Compilation, 1 Interview and
  exactly 2 are the studio album**. Filtering the returned list would leave 2 results out of 25;
  filtering the query spends all 25 on studio albums.
  `primarytype` and `secondarytype` are MusicBrainz's own documented release-group fields.
  "Studio only" excludes secondary types **by name** rather than asking for "no secondary type
  at all" — a bare `-secondarytype:*` relies on how the index treats a wildcard against an
  absent field, and negating specific terms is ordinary Lucene that behaves the same anywhere.
  **The original query is parenthesised before the filter is ANDed on.** A title-only search is
  bare free text, and without brackets the `AND` binds to the last term alone — quietly turning
  `dark side of the moon` into something the user did not type.
  The active filter is shown in the button, in the results summary, and as a tooltip carrying
  the exact clauses sent, because a search that silently returns less than it could is a search
  you stop trusting.
- **The metadata editor searches with a FIELDED query**, like the search view, built from its
  artist and album fields. Free text matched a one-track 2013 release group for "Pink Floyd
  Wish You Were Here" — the song, not the album — and since the folder year comes from the
  group, matching the wrong group dated the folder wrong. Fielded found 127 releases where
  free text found 4. It falls back to free text when the fielded query returns nothing.
- **An album's folder carries its edition, and identity lives in the tags.**
  `{artist}/{album} ({year}) [{edition}]`, with the suffix omitted for ordinary
  single-edition albums so the common case stays clean. The label is resolved by
  `editions.py` from MusicBrainz's own `disambiguation` first, then detected edition tags,
  then a notable format (the COUNTRY only when `COUNTRY_IN_FOLDER` is on - off by default since
  v0.8.3, asked for) — and a collision with a *different* release escalates to the
  catalogue number and finally the release id. `release.edition_label` overrides all of it
  and is the hook for the planned metadata manager: choosing an edition by hand should mean
  writing that field, not changing how editions are resolved.
  **An untagged folder is never treated as a different release** — libraries predating
  deadwax have no MBIDs, and forking every one of those albums would be far worse than
  sharing a folder.
- **Deleting an album is the only thing here that removes data the user did not just
  download, and it has no undo**, so `delete_album()` carries every guard: inside
  LIBRARY_PATH, never the root itself, and **audio must sit DIRECTLY in the folder**. That
  last one is not cosmetic — a recursive check happily accepts an artist folder and takes
  the whole discography, which a test caught. The confirmation is a real dialog rather than
  `confirm()` because it names the track count, the size and any non-audio files, which
  might be the only copy of a rip log or cue sheet.
- **Getting a cover must not require applying a release.** `/library/art/fetch` writes one
  file and touches nothing else — no tags, no rename, no companions. Applying a release is a
  lot to agree to when the only thing missing is the picture, and an album whose tags are
  already right shouldn't have to be re-tagged to gain a sleeve.
  **It chooses nothing**, which is what makes it safe to fire with no preview: the release id
  comes from the album's own tags, so it asks the Archive for art belonging to the release the
  album already claims to be. An untagged album is told to match a release first rather than
  guessed at, and an existing cover is never replaced unless asked.
  The `get art` button appears only on albums that have a release id and no art — exactly the
  set it can help — which also keeps it off the already-tight mobile rows.
  **Replacing art lives in the editor, not on the row.** Overwriting a sleeve you chose
  yourself is not recoverable, and the editor is where you are looking at both covers as you
  decide — that comparison is the point. The cheap, additive direction gets the one-click
  button out in the list; the destructive one sits behind a preview. The editor also sends an
  explicit `release_mbid`, since it is showing you that release's cover at the time; the plain
  path sends none and uses the album's own tags, which is what makes it need no decision.
  **The bulk run is driven from the client, one album at a time**, so you can watch it, stop
  it, and have every album go through the identical tested route a single click does. A
  server-side loop would be one long opaque request that either finishes or doesn't. It is
  scoped to what is on screen, so the facets compose with it, and it reports "no cover on the
  Archive" separately from "the request failed" — the first is a fact about the release and
  nothing can be done, the second is worth trying again.
- **There are now EIGHT writers to the user's filesystem**, and all but the smallest use the same
  plan/execute split: `organizer.py` files downloads in, `retag.py` corrects albums already
  there (and since v0.9.13 merges a disc folder into its release's), `artist_refile.py` moves an
  artist's albums under their current name (v0.9.14), `track_tags.py` writes tags edited by hand (v0.6.9), `artist_art.py` writes an artist's
  pictures into their folder (v0.6.15), `lyrics.py` writes a `.lrc` beside each track (v0.7.0),
  `save_disc_art()` writes CD art (v0.7.2), and `save_cover_art()` writes a single cover (narrow enough not to need a plan/execute split, but it re-checks containment at
  the write rather than trusting the plan, for the same reason the retag endpoint recomputes its
  own). A preview that disagrees with the write it previews is worse than no preview, so the
  first two derive the tags from one shared `organizer.tag_values()` rather than computing them
  twice, and the hand editor compares against `library.named_tags()` - the same reading of the
  file the track viewer shows. Every apply endpoint **recomputes the plan** rather than
  accepting the previewed one back — a plan is a list of file operations, and taking one over
  the wire would let a caller name arbitrary paths to write to.
- **MusicBrainz responses are cached in memory, successes only.** One bounded TTL cache for the
  process (`ResponseCache`), shared like the rate limiter and for the same reason: both are
  about what this application asks of MusicBrainz as a whole. It is what makes the review queue
  usable — stepping back to an album you already looked at costs nothing — and it turns a
  guaranteed duplicate into a hit, since `fully_search` fetches the first group's releases as
  `best-match-releases` and the editor then asks for that same group again. Bounded because a
  release list with recordings is a large payload. **Never cache the failure path** — see below.
- **Ask MusicBrainz for the least that answers the question.** Two flags, both defaulting to
  the expensive-but-correct behaviour so that a caller who does nothing cannot lose data:
  `fully_search(include_releases=False)` skips the eager best-match-releases walk, and
  `get_releases(with_tracks=False)` drops `inc=recordings` from a listing. Together they took
  opening the editor from ten requests to four, and one group's releases from five requests and
  1.4 MB to one and 101 KB — see the measurements below. `get_release()` is the other half:
  the tracklist of the pressing actually chosen. **Never make trackless the default** — the
  download flow matches Soulseek folders against a real tracklist, and losing it would weaken
  the matching silently instead of failing loudly.
- **The metadata queue stores only what you IGNORED.** What is *wrong* with an album is
  derived from the scan on every request by the pure `metadata_health.py`, never written down.
  A "needs attention" flag that is stored is a flag that goes stale the moment something fixes
  the album without clearing it; deriving it means a fixed album leaves the queue on its own.
  The `album_review` table therefore holds four things and no verdicts: when an album was first
  seen, whether deadwax filed it or merely found it, whether you've looked at it, and which
  issue codes you've accepted.
  **Ignores are per issue, not per album** — accepting that a bootleg will never be in
  MusicBrainz must not also silence the day its cover art goes missing.
  **`album_review` is keyed on the album's path**, not the scan's `key`: that key is the
  release MBID when there is one, and two folders holding the same release deliberately share
  it, so ignoring one would silently ignore the other. The cost is that a rename orphans the
  row, which is why `mark_album_reviewed()` takes a destination and the retag endpoint passes
  it.
- **The tab badge and the queue must never count different things.** They did, and it produced
  a notification that named no album: the badge counts albums deadwax *filed and you haven't
  looked at*, the queue counts albums with *outstanding issues*, and a freshly imported album
  with perfect tags is the first without being the second. It appeared in no facet, carried no
  chip, and the whole metadata section was hidden when nothing else was wrong — and it could
  never be cleared either, because there was nothing to apply, nothing to ignore, and it wasn't
  in the walkthrough. `queueAlbums()` now includes new imports whatever their state, there is a
  `newly added` facet and a `new` row chip, and **stepping past one is what marks it seen**.
  A notification you cannot act on is worse than no notification.
- **Prune review rows for albums that are gone.** A row is keyed on the album's path, so a
  folder renamed or deleted outside deadwax orphans it — and an orphaned *import* row is
  counted by the badge while being in no scan, so it can be neither named nor cleared. The scan
  drops them, but **only after a scan that actually found albums**: an empty library is far more
  often an unmounted volume than a deleted collection, and wiping every ignore the moment a
  mount goes missing would be a rotten trade.
  **deadwax's OWN delete removes the row itself (v1.1.5)**, with `store.forget_album_review()`
  once `delete_album` has succeeded, and the page's `onDeleted` recounts the tab badge, as
  ignoring an album does. Left to the scan, it went only when a full scan next found albums -
  the page's reload after a delete usually is one, but deleting the LAST album leaves a library
  that never prunes, and the badge said "1" for an album that was gone, for good (reproduced in
  the real page with the old route); and even when pruned, the badge kept the old count until
  its own minute poll. A refused delete forgets nothing. Any future writer that REMOVES an album
  should do the same.
- **The new-import prompt is recorded at import time, not derived from a scan.** The library is
  deliberately not read until its tab is opened, so a badge that had to diff two scans would
  need a scan to exist — absent at exactly the moment it has something to say. The poller writes
  one row as it files each download, and `/queue/new_imports` is a single indexed count that
  touches no filesystem. This is the only reason the import source is recorded at all.
  **A PARTLY filed download is announced too (v1.1.2).** Some files failing to file ends the job
  `complete` with "N file(s) failed to organize", and until 1.1.2 only a clean `organized` called
  `note_library_changed()` and enrolled the album - so the tracks that did land were in the
  library, `/library/owned` answered from a snapshot without them, and the badge never counted
  them. Both now happen whenever `organized` is non-zero outside a dry run, whatever the status,
  and BEFORE the status is written (the page reacts to `organized` by re-asking both). Enrolling
  also needs `tracks_organized` (execute_plan's count of audio files among `organized`): a folder
  left holding only a cover is no album to the scan, and a badge naming it could never be
  cleared. `tests/test_poller.py` fails a copy on purpose to cover both.
- **A move-organize clears the slskd folder out, and the line it will not cross is AUDIO**
  (v0.6.20, asked for: "I'd like the album folder to be deleted when the songs are").
  `cleanup_source_dirs` used `rmdir`, which refuses a non-empty folder by construction - so
  every share that came with a `Thumbs.db`, a checksum or a `Scans/` folder kept its folder for
  ever, emptied of music and reported in the log. It removes the folder and what is left in it
  now, and NAMES what it took, because the sidecars worth keeping (art, cue, log, nfo, txt, m3u,
  sfv - `COMPANION_EXTENSIONS`) have already moved into the library with the tracks, and what
  remains is the part nobody chose to keep. A `Scans/` folder is the real cost of this and it is
  the trade James asked for.
  **Audio anywhere beneath it stops the delete dead**, which is the guard a plain `rmtree` would
  not have: music still there was never filed - a second job downloading into the same peer
  folder, its files still arriving, or tracks of it nobody asked for - and no library has a copy
  of it. Those folders are kept and reported exactly as before. Every other guard is unchanged,
  and the "nothing failed or was skipped" one matters MORE now: a skip means files of this
  download never reached the library.
- **The artist folder a re-file empties is removed too** (v0.6.20).
  `_tidy_emptied_artist` after the move in `execute_retag`, with `rmdir` and never `rmtree`, so
  another album or anything else kept in there means it stays and nothing is weighed up. Filing
  under an artist's CURRENT name (v0.6.18) is what made this common: the last album leaves
  `Kanye West/` for `Ye/` and the old folder stayed behind, empty, for ever. `delete_album` has
  always done the same thing; this is the other half of it. The plan carries `library_root` so
  the move can apply the same two guards - inside the library, never the library itself.
- **Cancelling a download can remove its partial file, but only if you asked for it.**
  slskd keeps partials *deliberately*: it writes them to
  `<incomplete>/<username>/<remote path>/<file>` and, with `retry.partial` set to `Resume`,
  starts the next attempt at the partial's length instead of at zero. So a leftover is a
  feature for a transfer that failed and junk only for one you meant to abandon — which is why
  `remove_incomplete_downloads()` runs on cancel alone, and does nothing at all until
  `SLSKD_INCOMPLETE_PATH` points at that folder. Setting it *is* the opt-in.
  It matches by basename under the root rather than rebuilding slskd's path (slskd sanitizes
  the remote path into the on-disk name — `C:` becomes `C_` — and that mapping is its
  business), but it is **stricter than `find_local_file`**: that one guesses because a wrong
  guess misfiles a track, whereas here a wrong guess deletes somebody else's download. An
  ambiguous basename, or one whose parent folder isn't this job's, is skipped and reported.
  Every other guard mirrors `delete_album()`.
- **The EMPTY folders in slskd's incomplete folder are slskd's, and deadwax clears them (v0.9.6).**
  James found them piling up. From slskd's source: a download is written under
  `<incomplete>/<user>/<remote path>/`, every level created for it, and on completion
  `FileService.MoveFile(deleteSourceDirectoryIfEmptyAfterMove: true)` deletes only the ONE folder
  the file sat in. Every level above stays, empty, for every download ever finished.
  `remove_empty_incomplete_dirs()` (organizer.py) sweeps them at poller start and every
  `EMPTY_DIR_SWEEP_POLLS` (ten minutes), under the same opt-in, `SLSKD_INCOMPLETE_PATH`.
  It can't delete a file - `rmdir` only, links never followed, never the root - and it leaves a
  folder modified in the last `EMPTY_DIR_MIN_AGE_SECONDS` (10 min) alone, because slskd creates
  a download's folders and THEN opens its file, and an rmdir between the two fails the download.
  **Ages are read before anything is removed**: removing a child moves the parent's mtime, and
  judging the parent by that would stop the sweep one level up on every pass. A failed
  download's partial, and the path holding it, is never touched - slskd resumes from it.
- **A cancelled job leaves slskd's list too, and it takes a SECOND ask (v0.9.5).** deadwax had
  always cancelled with `remove=true` and slskd always answered 204 - and removed nothing, so
  cancelled jobs piled up in slskd's UI. Read in slskd's source, not guessed:
  `TransfersController.CancelDownloadAsync` calls `TryCancel(guid)` then `Remove(guid)` on the
  next line; `TryCancel` on a live transfer only signals its cancellation token (the transfer
  reaches `Completed, Cancelled` when its task notices), and `DownloadService.Remove` filters on
  `TransferStateCategories.Completed`, so it updates zero rows and nobody says so. A transfer with
  no token is cancelled synchronously and WAS removed - which is why it worked some of the time.
  So `tidy_cancelled_transfers()` (poller.py) asks again - the same call - for each of a
  cancelled job's transfers once slskd lists it in any `Completed` state
  (`store.settled_transfer_ids`). Three callers: a task after every cancel
  (`tidy_cancelled_later`, 1s looks for up to `TIDY_WAIT_SECONDS`), once at poller start, and
  "clear finished" just before it deletes the rows - after which nothing can match those
  transfers to a job again. Only CANCELLED jobs are consulted: an organized job names the same
  kind of files, and a finished download's history is the user's to clear. Removal is slskd's
  soft delete (`Removed = true`); the record stays in its database.
- **A job a stop caught mid-filing is settled when the poller starts (v1.1.3).** `organizing` is
  written as filing begins and only filing moves it on; stopping the container cancels the poller
  task mid-organize, and a CancelledError is not an Exception, so `_organize_if_enabled`'s handler
  never saw it. The job stayed `organizing` for ever: not in OPEN_STATUSES (never polled), not in
  CLEARABLE_STATUSES ("clear finished" left it), and counted ACTIVE by the page, so the Downloads
  badge stayed lit and the panel polled every second. `settle_interrupted_filing()` moves every
  such job to `complete` with `INTERRUPTED_FILING` ("deadwax stopped while filing this - check the
  library and slskd's folder") before the first poll; nothing else writes the status and one
  process runs one poller, so at start-up every one was interrupted. It is NOT filed again: a move
  may have taken half the tracks, and re-running the organizer over that unattended is a guess.
- **The image's HEALTHCHECK judges deadwax ALONE (v0.9.7).** `GET /deadwax/health` is 200 while
  the download poller runs and 503 once it has stopped - it catches every error per pass, so it
  only ends if something is badly wrong, and without it nothing is tracked or filed while the
  page looks fine. slskd logged out and MusicBrainz down deliberately do NOT count: an
  orchestrator restarting deadwax for another service's outage fixes nothing. The check is a
  Python one-liner (the slim image has no curl) against the fixed port 8080.
- **Errors degrade rather than crash.** Unwritable DB → downloads still work, untracked.
  Unreachable slskd → stored jobs still listed, no live progress. Unwritable DB → the metadata
  queue still works, it just stops remembering what you ignored.
