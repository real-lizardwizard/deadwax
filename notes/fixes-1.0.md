# The 1.0.1 fixes and their review (1.0.2)

Step 0 of the multi-user plan: the same-origin guard, held releases, a card's Find, the two-step apply.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### The 1.0.1 fixes (step 0 of the multi-user plan)

Four problems found while planning multi-user deadwax (the plan is a Claude Doc, linked from
the agent's memory), each affecting the single-user install as it stands. Shipped together.

- **Writes another website asks for are refused** (`src/api/same_origin.py`, plain ASGI and the
  OUTERMOST middleware). A page elsewhere could make the browser POST to deadwax: FastAPI reads
  a JSON body with no Content-Type, and body-less routes (cancel, retry, clear, rescan) take a
  form post. A cookie can't fix that later either, because every port on one host is the SAME
  site to a browser, so Navidrome's, slskd's and the NAS's own pages count as same-site. So the
  guard checks what browsers attach to every cross-origin POST and can't be told to forge:
  `Origin` (falling back to `Referer`) must name the host:port deadwax is reached at, via `Host`
  or `X-Forwarded-Host` (a cross-site page can't set that without a preflight). Scheme is
  ignored so TLS-terminating proxies work; `null` is refused; a request with neither header
  (curl, scripts, the HEALTHCHECK's GET) passes. `TRUSTED_ORIGINS` is ENVIRONMENT-ONLY on
  purpose: it guards the settings tab's own save. **Residual risk: DNS rebinding** (Origin and
  Host both the attacker's name) gets past it; logins will close that, since a session cookie
  is bound to deadwax's own host name. **Verified** in the real page: its own Rescan passed, and
  a page on another port POSTing to rescan and enqueue got 403 on both, logged.
- **A second copy of a held release isn't filed beside the first** (`existing_tracks`,
  `_planned_track`, `find_duplicate` in organizer.py - renamed in 1.0.2, see below). `resolve_album_dir` shares a folder holding the same
  release, and `execute_plan` only refused an exact existing filename, so a FLAC and then an
  MP3 landed side by side (one album, each track twice in Navidrome); a grab without a
  tracklist keeps the sharer's filenames and did it even in one format. Now a planned track
  whose (disc, track) is already in the folder gets `duplicate_of` and is skipped. Keys come
  from the files' own tags, with the `NN - ` name as a fallback. A matched track is numbered
  exactly as `tag_values` numbers it (per disc on multi-disc, running otherwise), and an
  unmatched file is asked its own tags. A MISSING track still files, so a later download
  fills gaps. Skipped duplicates count as skipped, so a move's clean-up keeps the slskd folder
  (unfiled music is in it), and an all-duplicate job ends "already in the store: all N
  track(s) were already there".
- **A card's Find downloads a real pressing** (`representativeRelease` in tracklistDiff.mjs,
  pinned in `tracklist.sim.cjs`). It sent `release_mbid: null` and `tracks: []`, so the album
  filed untagged (or kept the sharer's release id) and no "already held" check could ever match
  it. It now uses the card's pressings (or fetches them, with a sweep on the button). It picks
  the group's most common tracklist (chooseBase), then Official, then CD or Digital Media only,
  then the earliest date. It builds the payload with the ROW's builder, `buildExpectedFromRelease`
  (since 2.0.0-player.15 both go through `lib/releasePayload.ts`, the one builder), so both Finds
  send the same shape. MusicBrainz unreachable falls back to the old group-level
  payload, which now carries `release_group_mbid`. A `findRequests` latestOnly guard means a
  slow lookup never opens over a newer Find. `write_tags` also deletes a sharer's
  `musicbrainz_albumid` when the job names no release, since `tag_values` skips empty values.
  **Verified** in the real page: Dummy's card sent an 11-track Official CD pressing; the
  2009 box set's card fetched first and sent its EU 2xCD pressing.
- **Apply-release is two steps when it has to be** (`changes_player_ids`, `move_retagged` in
  retag.py; the route in library.py). Navidrome keeps every user's plays, ratings, favourites
  and playlist entries across a retag in place, or a rename with the same tags, but NOT both in
  one scan (phase 1 maps old to new album ids only at the same path; phase 2 pairs missing
  tracks only by the same PID). A one-step apply was exactly that. When an apply changes an id
  tag (`musicbrainz_albumid`, title, track or disc number) AND moves or merges, the route writes
  the tags, sleeps `RETAG_RENAME_WAIT` seconds (default 20: the watcher reacts after 5s, a
  one-folder scan takes about a second), then renames. The preview carries `rename_wait`, so the
  editor says it up front and Apply reads "Applying, renaming in Ns". ~~A fixed wait is the
  stopgap~~ **Replaced in 1.0.3 wherever Navidrome is set up**: the route polls `getScanStatus`
  until a scan that began after the write has finished, and holds the rename back if none comes -
  see "The scan wait" under "The phone player". The fixed wait remains without Navidrome (or with
  a `NAVIDROME_URL` the check refuses), and as the fallback when Navidrome answers but not usably;
  a Navidrome that doesn't answer at all holds the rename back too. **Verified** in the real page
  with a 6s wait: tags written, then the wait, then "re-filed Third rip as Third (2008) [...]".

#### After review (1.0.2)

A review of 1.0.1 found seven real problems in it, all fixed together:

- **Another pressing is judged by TITLE, not number.** `resolve_album_dir` shares a folder with
  an UNTAGGED one (a pre-deadwax rip) as well as one holding the same release, and numbers mean
  nothing across pressings: the US *Dummy* inserts "It's a Fire" at 6, so by number it was a
  "duplicate" of the UK CD's "Numb" and was left out, while US 11 "Glory Box" filed beside UK 10.
  `find_duplicate` matches by (disc, track) only when the folder's `musicbrainz_albumid` IS this
  job's release (`same_release`); otherwise by folded title (`matching.normalize`), same disc when
  both sides know it. A title comes from tags or an `NN - Title` name only, never a bare stem:
  "01" as a title made false duplicates, caught by the poller tests.
- **An unfiled copy keeps its sidecars.** With any track a duplicate, no companion is planned:
  the FLAC rip's log and cue would otherwise have filed beside the MP3s they don't describe,
  and a cover-only "organized" count would hide an all-duplicate job. The poller's "already in
  the store" message counts `duplicates`, not `skipped` (which a cover could pad).
- **`write_tags(drop_stale_release_id=True)` only from the organizer.** 1.0.1 dropped a file's
  `musicbrainz_albumid` whenever the release had none - including the editor's apply of a
  hand-built release, which would silently un-tag an album. The retag path leaves it.
- **The rename looks again after the pause.** Two copies of one release applied back to back
  both planned a plain rename, and the second `shutil.move`d its folder INSIDE the first's.
  `move_retagged` refuses a target that exists by then (the album keeps its new tags where it
  is), and `_retag_apply` holds a per-album `asyncio.Lock` (`_apply_lock`) so one album can't
  be applied twice at once.
- **The pause covers albums with no release id.** Navidrome's album PID falls back to
  albumartistid, album, version and date, so for a release without an MBID those tags are ids
  too (`NO_MBID_ID_TAGS`); `changes_player_ids(plan, release)` takes the release to know.
- **The saved scan is refreshed BEFORE the pause**, not after: a container stopped mid-pause
  restarted onto a snapshot of the old tags at the old path, which matched on mtime.
- **The editor followed a stale album after an apply.** `onApplied` set the editing album and
  the queue's paths from whatever the closure held; both are functional updates keyed on the
  OLD path now, so an apply landing after you stepped on can't pull the editor back.
- **Downloads carry `original_year`** (main.js, both builders - one, `lib/releasePayload.ts`,
  since 2.0.0-player.15 - through `realYear()` - `getYear()`
  says 'N/A' for display, which the group fallback sent as a year: "Album (N/A)"). A card's Find
  standing for a real pressing made it matter: Wish You Were Here's card picks a 1985 CD, which
  without it files as `(1985)`. **Verified in the real page**: that card now sends year 1985,
  original_year 1975.
- **`representativeRelease` is deterministic**: a disambiguation ranks after none (it becomes
  the folder's edition label), a year-only date sorts after full dates in that year (as
  strings "1994" beat "1994-08-22"), and a full tie goes to the release id.
- **The guard, twice more**: `X-Forwarded-Port` fills in a port the Host left out (nginx's
  `$host` drops it; the docs now say `$http_host`), and the Vite dev proxy keeps the Host
  (`changeOrigin: false`), since the string shorthand rewrote it and every harness write was
  refused.
