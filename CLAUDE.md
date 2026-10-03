# deadwax — working context

Read this before doing anything. It records decisions and hard-won gotchas that aren't
recoverable from the code, so you don't re-litigate settled questions or re-discover
problems the expensive way.

## What this is

A fork of [LidBrainz](https://github.com/dual-shock/lidbrainz) that has diverged a long way.
Upstream sends releases to Lidarr. **This fork removed Lidarr entirely and talks to slskd
directly.**

Repo: `real-lizardwizard/deadwax` · owner is James Barnett (jamesambarnett@gmail.com).

**Where it runs: OpenMediaVault, with Komodo managing Docker.** So compose is the deployment path
that matters, and anything addressed to "your Unraid box" is wrong. **The Unraid template
(`my-deadwax.xml`) and the Unraid half of the README were CUT in v0.9.3, on James's instruction.**
They were inherited from upstream LidBrainz, whose author ran Unraid; nothing here had tested them
since the fork, and reading Unraid into the repo because they were in it produced a run of
confidently wrong deployment advice. Don't bring them back.

### Branches

| branch | what |
| --- | --- |
| `main` | **the one line that ships.** Every change that ships lands here, and since 1.0.5 only main takes version numbers. Each push is built as `:experimental`; a `v*` tag on it is a release. Until 1.0.0 it held the old Lidarr-based v0.2.1, still tag `v0.2.1`. |
| `player-spike` | the multi-user and phone-player work, begun from 1.0.0 (2026-09-27, asked for), which builds its own `:player` image. It numbered its commits 1.0.1-1.0.5 before the rules below, so those numbers mean different code there than on main; its two fix commits came to main as 1.0.3 and 1.0.4, and some sections below dated 1.0.1-1.0.5 (the 1.0.1 fixes, the phone player's port) use its numbering. From here it follows the rules: `1.1.0-player.1` to `.6`, then `2.0.0-player.N` once James decided it ships as 2.0.0 (2026-09-29), when every step of the multi-user plan is done - `2.0.0-player.7` is step 2, `2.0.0-player.8` its merge of main's 1.1.7, `2.0.0-player.9` the first slice of the one app (see "The one app"). |
| `player-spike-0.8` | the original player spike (`5f6711e`, 0.8.0, built on 0.7.2), kept for step 1's port - done, onto player-spike's 1.0.2 as its 1.0.3 (see "The phone player"), so it is kept only for reference now. Everything after it on that branch shipped on experimental. |
| ~~`experimental/slskdn-no-lidarr`~~ | **deleted after 1.0.4.** Where all the 0.x work happened: v0.3.0 to v0.9.2 were tagged from it, and every commit of it is in main's history. |

#### Branches and versions (v1.0.5, asked for)

James: "how can I set this up to work cleaner in the future so I don't have to go back and forth
between versions like this?" After 1.0.0, two lines numbered their own commits: player-spike took
1.0.1-1.0.5 while main took 1.0.1-1.0.4 - the same numbers for different code - and two fixes made
on the spike that main needed had to be cherry-picked across.

- **main is the one line that ships.** Don't start a second line that releases too.
- **Only main takes version numbers.** A commit on any other branch leaves `__version__` alone.
  A branch that publishes its own image needs a version to show, and takes a PRE-RELEASE of the
  version it will ship as - never a plain number, and always one that sorts AFTER main's latest
  release. player-spike began as `1.1.0-player.1`, `1.1.0-player.2`...; once main released 1.1.0
  itself (the disc titles, 2026-09-29) those sorted before a release they came after. James has
  decided player-spike stays a branch until it ships as **2.0.0**, when every step of the
  multi-user plan is done, so it numbers `2.0.0-player.N`, keeping the count: `2.0.0-player.7` is
  step 2 (it followed `1.1.0-player.6`), and `2.0.0-player.8` its merge of main's 1.1.7. The
  publish workflow never moves `:latest` for a version with a hyphen, so it can't pass for a
  release, and a plain number always means one commit on main.
- **A bug main has too is fixed ON MAIN first**, in its own commit with its own patch bump, and
  main is then merged into the branch. Fixing it only on the branch is what stranded 1.0.1 and
  1.0.2 on player-spike.
- **Merge main into a long-running branch often** (`git merge main`; the app's sync does it for a
  worktree session), so the merge back is small. When a branch merges into main, main gives it
  the next plain version then.
- **A release is a tag on main.** A push to main publishes `:experimental`; a `v*` tag publishes
  `:<version>` and moves `:latest`.
- **Every release gets written release notes (asked for, 2026-09-28: "always write release
  notes").** The tag's publish run creates the GitHub Release itself, with generated notes that
  are only a changelog link; once that run has finished, replace them:
  `gh release edit vX.Y.Z --title "deadwax X.Y.Z" --notes-file <notes>.md`. Same shape as
  v1.0.0, v1.0.2 and v1.0.4: **Fixed** (what changed for the person running it, in their words),
  **New settings** as a table of setting, default and what it does, **Upgrading** with anything
  they must do - anything that can break a working setup first, like 1.0.4's reverse-proxy note -
  and the changelog link last. Every name, default and behaviour in it checked against the code
  and docs. Part of tagging, not a follow-up.

### The name (v0.6.21)

It was called **jimbrainz** until v0.6.21, and git history before that says so. James asked for
"a more creative name" and picked **deadwax** from a shortlist: dead wax is the blank ring between
a record's last groove and its label, where the matrix number that tells one PRESSING from
another is scratched - which is exactly the thing this project exists to care about. Lowercase,
like slskd, and never sentence-case it.

What a rename has to carry across, because an install that upgrades must not notice:

- **Saved browser state.** Every localStorage key was `jimbrainz-*`. `interface/scripts/
  rename-storage.js` copies each to `deadwax-*` (a key already under the new name wins) and
  deletes the old one. It is a CLASSIC script in `<head>`, not a module, on purpose: module
  scripts run after parsing in document order and `resize.js` reads its key before `main.js`,
  so the move has to be finished before any of them start. The origin didn't change (it is host
  and port), so the old keys are there to be found. **Deleted in v0.9.18**, ahead of 1.0: the
  one install there is upgraded through it long ago. Anyone jumping straight from 0.6.20 or
  earlier to 1.0 starts with default browser preferences - nothing on the server is affected.
- **The database.** The default moved from `/config/jimbrainz.db` to `/config/deadwax.db`, and
  an install that never set `DB_PATH` has everything in the old one. `default_db_path()` goes
  on using the old file where it is while the new one doesn't exist, and says so in the log.
  It never MOVES the file - that would be a write into someone's config volume for nothing.
  An explicit `DB_PATH=/config/jimbrainz.db` in an existing compose file just keeps working;
  **don't "tidy" it by renaming the file** - that is the one change that loses the data.
- **The API prefix is `/deadwax/` with no alias for `/jimbrainz/`.** Only this page calls it,
  and `index.html` is served no-cache, so a reload picks up the new paths. A tab left open
  across the upgrade gets 404s until it is reloaded - accepted rather than kept forever.
- **The image name follows the GitHub repo name** (`IMAGE_NAME: ${{ github.repository }}` in
  docker-publish.yml), so the ghcr path only becomes `ghcr.io/real-lizardwizard/deadwax` once
  the repo itself is renamed. Everything up to 0.6.20 stays published under the old package
  name, and a Komodo stack has to be pointed at the new image by hand - nothing redirects it.
- **The user agent** is now `deadwax/<version> ( email )`, built as before.
- **Not renamed:** the local checkout folder (`~/Desktop/Code/jimbrainz`). The agent's memory
  directory is keyed on that path, so moving it strands the memory. Rename both together or
  neither.

### Why Lidarr was dropped

Not preference — a specific failure. Pick a *particular* release (the 2011 remaster, the
deluxe edition) and every distinguishing detail dies at Lidarr's API boundary:
`POST /command {name:"AlbumSearch", albumIds:[N]}` carries no tracklist, no edition, no year.
The plugin doing the actual Soulseek search rebuilds a generic query and grabs whatever
returns. Tubifarry's own maintainer
[confirms Custom Formats can't target a selected release variant](https://github.com/TypNull/Tubifarry/discussions/138).

deadwax already knows all of it, so it owns the search and the matching itself.

**Honest limitation, stated in the README and worth preserving:** this does not reliably
auto-detect remasters. Soulseek folder names are typed by strangers and often omit edition
text. Edition is a *weighted signal, never a hard filter* — filtering on it hides real
results. The promise is ranked candidates with visible reasoning, not magic.

## Architecture

Python 3.12+ / FastAPI backend, static frontend, SQLite for job state.

```
src/
  config.py        env + validation. describe_slskd_url() explains WHY a URL is unusable.
                   Also BUILDS the MusicBrainz user agent from MUSICBRAINZ_EMAIL and
                   __version__ - see "The MusicBrainz user agent" below.
  matching.py      PURE candidate scoring. No I/O. The heart of the project.
  naming.py        PURE. The album folder's name from ALBUM_FOLDER_TEMPLATE, and the edition read
                   back out of one - see "Naming album folders from a template".
  editions.py      PURE. Which edition a release is, in words. See below — it's why the
                   library can hold the deluxe and the standard press at the same time.
  metadata_health.py  PURE. What's WRONG with an album on disk, as issue codes. Backs the
                   metadata queue. Derived on every request, never stored — see below.
  library.py       scans LIBRARY_PATH with mutagen, cached per folder on mtime - and that
                   cache is SAVED to SQLite (library_cache), so a restart starts warm and
                   the tab can draw a snapshot before touching the disk. Also finds cover
                   art, and reads one album's files in full for the track viewer.
  store.py         SQLite job store + transfer reconciliation helpers. Also the store index
                   (store_album): every album folder under an id that survives a rename.
  store_index.py   keeps the store index in step with every scan and writer, and the "already
                   have it" checks Find, /enqueue and the retries make - see "Already in the
                   store".
  poller.py        background task: slskd transfers -> job status transitions.
  organizer.py     writes downloads into the library. Plan/execute split, dry_run default.
  retag.py         the metadata manager's write half - applies a chosen release to an album
                   already on disk. Same plan/execute split, for the same reasons.
  scan_wait.py     PURE. Whether Navidrome has finished a scan that began after an apply's
                   tags were written, so the folder can be renamed - see "The scan wait".
  resample.py      a hi-res FLAC resampled to 48/44.1 kHz, 24-bit FLAC, with its album neighbours' edges
                   on one grid so joins stay exact; numpy/soxr/soundfile, imported lazily. See
                   "Maximum quality: hi-res resampled to 48 kHz".
  album_context.py which songs sit beside a song on its album, the grid phase, and their edges, from
                   Navidrome - for resample.py.
  flac_mp4.py      PURE. A FLAC file as an MP4 of the very same frames, no ffmpeg - what makes
                   Safari's seeks land. See "FLAC in an MP4, for Safari". And as a FRAGMENTED
                   MP4, `fmp4_layout()`, for the gapless stream - see "One stream for FLAC".
  flac_window.py   PURE. A stretch of a song as a FLAC file of its own, cut from deadwax's own
                   MP4s, frames renumbered from 0 - the turntable's sound. See "The turntable,
                   part two".
  player_cache.py  those MP4s made from Navidrome's file and kept on disk (PLAYER_CACHE_PATH or
                   temp space, PLAYER_CACHE_MB), served with byte ranges; the stream route's
                   `wrap=mp4`, and `wrap=fmp4` for the gapless stream. One URL stays one
                   container - see "After review (the cache)". And the turntable's windows,
                   cut from them (`answer_window()`, the scrub route).
  track_tags.py    tags edited BY HAND, on one track or a selection at once. The fourth
                   writer, and the same plan/execute split again - see "Editing tags by hand".
  artists.py       PURE. What an artist page shows, and where artist pictures come from -
                   which is nowhere near as obvious as album covers. Also renders artist
                   CREDITS, which is why a split album no longer reads as a list.
  artist_refile.py an artist's albums moved under their current name. The EIGHTH writer, same
                   split - see "One artist under two names".
  artist_art.py    artist images written into the artist's folder. The FIFTH writer, same
                   plan/execute split - see "The artist page".
  lyrics.py        lyrics as a .lrc beside each track. The SIXTH writer, same split, and the
                   network is passed in so none of it needs one to test - see "Lyrics".
  disc_art.py      CD art as disc.<ext> / disc<N>.<ext>. The SEVENTH writer - choosing is pure,
                   writing is narrow - see "CD art and embedded pictures".
  tagkeys.py       tag names mutagen's Easy MP4 doesn't know (the disc title), registered once,
                   and easy_file() to open a file with them - see "Disc titles".
  users.py         current_user(), a FastAPI dependency: the implicit admin `local` while logins
                   are off - the seam step 3 fills in. routes/me.py answers GET /deadwax/me from it.
  api/             musicbrainz_endpoint.py, slskd_endpoint.py, coverart_endpoint.py,
                   artist_images_endpoint.py (Wikidata/Commons + TheAudioDB),
                   lrclib_endpoint.py (LRCLIB), navidrome_endpoint.py (Subsonic, for
                   the player - holds the login; client_for(request), the per-user seam),
                   app.py, same_origin.py (refuses
                   writes another website asks for - see "The 1.0.1 fixes")
  routes/          search_musicbrainz, download, monitor_slskd, interface_logs, library,
                   settings (editable since v0.5.1 - see "The settings tab"), navidrome
                   (the player's FIXED list of Subsonic calls - see "The phone player")
interface/         vanilla JS/CSS. Still the served page; main.js is shrinking as panels
                   are ported. main.css styles BOTH halves - see below.
  styles/theme.css THE TOKEN LAYER. Every colour, size, space, radius, shadow, duration and
                   easing in the application. Because both halves consume it, editing a
                   value here restyles the vanilla and Preact sides together. Raw values in
                   main.css or in a component are a bug. NOTE it is @import-ed, so it caches
                   separately - hard-refresh when verifying a palette change.
  player/          the app's page at /player/, manifest, icons, and two stylesheets: player.css
                   (the player; mechanics its own, look on theme.css section 10) and app.css (the
                   tab bar, Home, Requests, You) - see "The one app".
  dist/            BUILT from ui/, gitignored. Not present in a fresh checkout.
ui/                Preact + Vite + TypeScript. New work goes here — see below.
                   ui/src/player/ is the phone player, a second entry beside the main one;
                   player/streamSource.ts is its one-stream gapless engine, with the pure
                   lib/streamPlan.ts and lib/fmp4.ts - see "One stream for FLAC". Since
                   2.0.0-player.9 its main.tsx renders ui/src/app/App.tsx, the ONE app: five tabs
                   with the player inside them - see "The one app". player/deck.ts is the
                   turntable's platter and its own sound (lib/platter.ts, lib/deckVoice.ts) - see
                   "The turntable, part two".
tests/             2048 tests, all Python, all fixture-driven (+ ui/test/*.sim.cjs scripts)
```

API routes are prefixed **`/deadwax/`** (renamed from `/lidbrainz/`, then from `/jimbrainz/`
in v0.6.21 - see "The name").

### The flow

MusicBrainz search → pick a release → slskd search → rank candidates against that release's
real tracklist → enqueue → poller watches transfers → organizer tags and files the result.

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

### Interface details that cost time

- **`overflow-y: auto` silently promotes `overflow-x` to `auto` too.** A box cannot have
  `visible` on one axis and `auto` on the other. That is where the metadata editor's unwanted
  sideways scrollbar came from — nothing ever asked for horizontal scrolling. Declare
  `overflow-x: hidden` explicitly when you only want vertical.
- **A flex item defaults to `min-width: auto`, so `text-overflow: ellipsis` never fires.**
  The item refuses to shrink below its content, so the row grows instead and the container
  scrolls. `min-width: 0` on the flex child is the missing half of every ellipsis that
  "doesn't work".
- **`getBoundingClientRect()` returns the TRANSFORMED box; `offsetWidth`/`offsetHeight` do
  not.** The panels open with a `scale(0.98)` entrance, so measuring size with the rect during
  that animation bakes in the scaled value. Use the rect for POSITION (where it is on screen)
  and the offset properties for SIZE.
- **`style.left` on an absolutely positioned element is relative to its offsetParent, not the
  viewport.** Writing a `getBoundingClientRect().left` into it threw the log and downloads
  panels most of a screen sideways on the first resize. `resize.js` converts explicitly; fixed
  panels have no offsetParent and need no conversion.
- **A CSS `resize` grip does not track the cursor on a transformed element.** It drags in the
  element's own untransformed space, so with `translate(-50%, -50%)` the corner runs away at
  double speed. That is why resizing is done in JS now — see `interface/scripts/resize.js`.

- **An animation loop only looks smooth if its end state is pixel-identical to its start.**
  The loading sweep sets a tile width and travels exactly one tile; anything else pops on
  every cycle. Percentage `background-position` will not do this — it positions relative to
  (container − image), not to the image.
- **Capitalization: sentence case in the markup, and let CSS do any uppercasing.** Several
  labels are rendered uppercase by `text-transform`, so the source string still has to read
  correctly when that rule is not applied. Proper nouns keep their own casing, and **`slskd`
  and `deadwax` are lowercase brand names** — never sentence-case them, rephrase so they are
  not sentence-initial instead.

### Panels move as well as resize

- **Only the two DIALOGS move — the Downloads and Log dropdowns are anchored (v0.6.8, asked
  for).** They were in `DRAG_HANDLES` too, and James could drag them around "like a tab" when
  they should hang off their button. They are in `ANCHORED` in `resize.js` now: no drag
  handle, no `grab` cursor, and resizing only from the free edges — `edgeAt()` strips `n` and
  `e`, because the top is glued to the button and `right: 0` glues the right edge. A resize
  writes width/height only and never calls `freeze()`, so the CSS anchoring is never replaced
  by explicit left/top. A position saved from when they could be dragged is IGNORED by
  `applySavedSize()` rather than restored, so nobody's dropdown is stuck mid-screen from
  storage. Don't put them back in `DRAG_HANDLES`.
  - **Anchoring exposed an outside-click bug, fixed alongside.** A press inside a dropdown
    released outside it fires its click on the common ancestor — outside — so a habitual
    title-bar drag, or a text selection run off the edge, closed the panel. It never showed
    while the panels moved, because the pointer stayed on them. Both close handlers
    (Downloads' and the log's in `main.js`) now also track where the press BEGAN, and reset on
    every click so a keyboard click is judged by its target alone. On the Preact side that rule
    is `hooks/useDismiss.ts` since v0.9.23, shared with the candidate dropdowns.
  - **Verified** in the browser with real pointer drags, transitions disabled (the preview pane
    paints no frames while hidden, so the open animation sits at `scale(0.98)` and edges measure
    wrong): toolbar and title-bar drags leave both panels where they were and open; the left
    edge widened Downloads 520→620 with its right edge fixed at the button; the bottom edge
    grew both; the top-right corner does nothing; a stale saved `left`/`top` is ignored; a plain
    click outside still closes.
  - **Downloads and Log close each other, in BOTH directions.** Opening Downloads always closed
    the log (`closeOtherDropdowns`), but opening the log left Downloads open: the log's toggle
    calls `stopPropagation()`, which hides the click from the panel's outside-click listener.
    The panel now puts `closeDownloads` on the bridge and the log's toggle calls it when it
    opens. **Verified** with real clicks both ways. The page-level dropdowns (type filter,
    sort, columns, candidate signals) stop propagation the same way and so still leave
    Downloads open beside them — not asked for, left alone.
- **Moving is by a TITLE BAR, never by the whole panel.** These panels are full of lists you
  scroll, text you select and buttons you press; one that slides away when you try any of
  those is worse than one that never moved. `DRAG_HANDLES` names the bar per panel and
  `NOT_A_HANDLE` exempts the controls inside it.
- **The log gained a title bar rather than being made an exception.** It was the only floating
  panel that did not say what it was, so it wanted one anyway.
- **`.metadata-path` is exempt from the handle AND from `user-select: none`.** It is the album's
  full filesystem path and the one string in any title bar people actually copy — it is what
  you paste into a terminal when an album is misfiled. Making the bar unselectable would have
  quietly taken that away, so it keeps a text cursor and starts no drag.
- **Resize WINS over move where they overlap.** A title bar's own top and side edges sit inside
  the 6px resize zone. Resizing is the more precise gesture and the harder one to begin by
  accident, so it takes precedence and moving gets everything else.
- **Position is persisted now, and the old objection is answered by clamping, not by
  forgetting.** Position used to be deliberately discarded because a dialog pinned to absolute
  viewport coordinates can end up entirely off screen after the window shrinks, with no OS
  window list to recover it from. That held while position was only ever a side effect of
  `freeze()`; now that moving is deliberate, throwing it away every time is the worse failure.
  `clampToViewport()` keeps a 64px strip of the bar reachable. **Verified:** a position stored
  at (1300, 820) restores at (836, 536) in a 900×600 window — exactly the 64px strip on both
  axes.
- **`applySavedSize()` restores position through `freeze()`, not by writing `left`/`top`
  directly.** These panels are anchored with `right: 0`; setting `left` on top of that pins
  both edges and stretches the panel instead of moving it.
- **`thaw()` only deletes the frozen flag.** It used to wipe the inline geometry, which would
  now undo a move the instant the panel closed.
- **A gesture its panel didn't survive is dropped, not saved (v1.0.8).** Escape closes the
  Downloads panel (and the candidates dialog) in the middle of a drag, and `onPointerUp` then
  saved what a hidden panel measures: 0 x 0, so the panel opened at its 280 x 160 minimum for
  ever after - found in the preview pane's storage, reproduced with real input in headless Brave
  (press on the left edge, drag, Escape, release). A move abandoned the same way saved an
  off-screen spot (-550, 0). `endGesture()` saves only while `isShown()`, `saveSize` refuses a
  non-positive size, the observer ends a drag whose panel it sees hidden, and `applySavedSize`
  ignores a saved size of 0 or below the panel's CSS minimum, so a stored 0 x 0 recovers by itself.
- **"Hidden" is `isShown()`, never `offsetParent` (v1.0.8).** offsetParent is null for anything
  `position: fixed` - both dialogs - whether showing or not, so the observer took them for hidden
  every time and never ran `applySavedSize` on them: the candidates dialog opened at its default
  (70, 90) with a position saved, contradicting the note above. The dialogs also hide by
  `visibility: hidden` (kept laid out to fade), which has boxes, so `isShown()` checks visibility
  as well as boxes. **Verified in headless Brave**: a saved (1300, 820) now restores at exactly
  (836, 536) in 900 x 600, the 64px clamp above. **Not verified**: the metadata editor, which
  mounts only when opened and has no library in the scratch setup.
- **A press outside a panel's box is on no edge of it (v1.0.9).** James: comparing covers in the
  metadata editor, "the x highlights but doesn't do anything", while Close worked. The cover
  viewer was drawn INSIDE `#metadata-window`, so `panelFor()` called a press on it a press on
  the editor, and `edgeAt()` never asked whether the pointer was inside the box: "above the top"
  passed as the top edge. Once the editor had been moved (no centring transform, so the fixed
  viewer covered the screen) its ✕ sat above the editor; the press began a resize, the editor
  took pointer capture, and the click landed on `#metadata-window`. Close, below the editor,
  failed the bottom test's `>= scrollbar` half and escaped. Two fixes: `edgeAt` returns '' for
  a pointer outside the box, and the viewer renders BESIDE the editor's window (a fragment),
  which also makes it full screen when the editor is centred - inside the transform it had been
  the editor's 900 x 680. **A script's click can't show this**: a synthetic pointer can't be
  captured, so the click went through in every scripted test, in Arc too. **Verified with real
  input in headless Brave**: before, the moved editor's ✕ logged pointerdown on the button and
  then capture, pointerup and click on the editor; after, the ✕ closes the viewer centred or
  moved, the viewer is 1440 x 900, Escape, the scrim and Close each close only the viewer, and
  the editor still resizes from its top and left edges (60 and 50px) while a press just above
  it does nothing.

### One tracklist per release group (v0.8.2)

James: "instead of having a tracklist for each release, just having a base tracklist from the first
release and then each release shows the changes it would make to that tracklist" - tried in a
preview on Dummy and The Slow Rush first, then built with the MOST COMMON tracklist as the base.

- **The base is the most common tracklist, not the first release** (`chooseBase` in
  `interface/scripts/tracklistDiff.mjs`). The first release is whatever the sort put on top; on
  Dummy it was a vinyl whose lengths MusicBrainz lists ~10s short of every CD, and every CD read
  as ten changes. Chosen from ALL the group's releases, never the filtered rows, so it holds
  still while the filter column narrows the table. The release that stands for it is the first
  holding that tracklist, and its chip says "The tracklist above".
- **Tracks pair by folded title along the longest common run**, so a bonus track in the middle
  is one added track and shifts nothing after it; an added and a removed track of about the
  same length are one rename. Curly and straight apostrophes fold together - Dummy's pressings
  have both "It's a Fire" and "It’s a Fire", and half of them would otherwise show a rename.
- **Three bands of length difference**: within `LENGTH_TOLERANCE_S` (2s) is rounding and
  nothing; past it is a length change, summarised on one line; past `OTHER_VERSION_S` (15s) or
  8% is "another version" and listed like a track change. The Slow Rush's single-mix digital
  release is identical by title and differs only in "Borderline" being 36s longer - the case
  that band exists for. Lengths are the TRACK's (this pressing's), falling back to the
  recording's, because the track is what differs between pressings.
- **Chips ride in the EDITION cell, not a column of their own** (the title cell until v0.9.0) -
  they say what's different about the pressing, which is the edition's job, and edition LEADS
  the row, so they show on a phone, where the grid keeps only its first columns in view. With
  the edition column hidden they fall back to the title cell.
- **Edition is the first column (v0.9.0, asked for: "the title should be pretty much the same
  for every edition").** A layout is saved WHOLE the first time any column is resized, hidden or
  moved, so a new default alone never reaches anyone who has touched the grid.
  `COLUMN_ORDER_VERSION` (2) moves edition ahead of title ONCE, and only in a saved layout still
  holding the two in the old default's first places: one arranged by hand is left as arranged,
  and a deliberate "title first" saved afterwards is kept because the version has moved on.
  The column state's shape (with `orderVersion`) lives only in main.js now - the unused
  Preact reader went in the v0.9.19 audit; the grid's port has to carry `orderVersion` across.
  **Verified** with all four cases seeded in localStorage.
- **Still lazy**: a release's change list is built on first expand, and its own full tracklist
  (vinyl sides and all) on a second click - the 711ms rule. The diffs behind the chips are
  computed once per release and kept in a Map, since the body re-renders on every filter change.
- **Third-party text goes in with `textContent`**, never `innerHTML`: these are MusicBrainz's
  titles. (The older full-tracklist rows still build from a template string, and since v0.9.22
  every MusicBrainz value in them goes through `esc()` - see "Page start-up, the log, and escaping".)
- **The same clipping bug lived one level down**: `.release-tracks.expanded` was capped at
  `max-height: 5000px`, which a large box set's tracklist can exceed. `none` now, like the
  release list's own 1000px cap fixed in v0.8.1.
- **Verified in the real page** on both albums: Dummy "shared by 12 of 20", the 1995 UK CD and
  the US promo +1 track, the ten-track pressings −1 track; The Slow Rush "shared by 9 of 10",
  only the Japanese CD (+1 track) and the single mix (1 other version, 3:58 -> 4:34) differing.
  No horizontal overflow at 375px.

### What's already in the library, in the search (v0.9.1)

James: "I need a way to see which editions are already in my library when I'm searching for new
ones." A card says "In your library" (with "· N editions" past one), and each pressing held is
marked on its own row - an "In your library" chip in the edition cell and a purple edge on the
row. Matching is `interface/scripts/owned.mjs`, pure, pinned by `ui/test/owned.sim.cjs`.

- **Three ways to match, surest first**: the RELEASE id (this exact pressing - what marks a
  row), the RELEASE-GROUP id (some pressing of this album - what marks a card, before its
  releases are even fetched), and NAME, for folders with no MusicBrainz ids at all. A name
  match says "Maybe in your library", dashed: the name can't say which edition, or for certain
  that it is the same album. **A folder that IS tagged is never matched by name** - it has
  already answered by id, and a tagged album of another group must not be claimed because the
  title happens to agree. Names fold like the artist matcher's (accents, a leading "The", "&"
  vs "and", bracketed asides) and are tried under the credit AND the current name, since an
  old folder is called whatever the sleeve said.
- **The scan reads `musicbrainz_releasegroupid` now (SCAN_FORMAT 5).** Easy MP4 has no key for
  it, so an m4a album reads Picard's freeform atom (`MP4_RELEASE_GROUP_ATOM`) raw, once per
  album. An album with a release id and no group id is still caught at card level through the
  pressings the page has fetched (`registerGroupReleases`).
- **`/library/owned` answers from the SAVED SCAN unless deadwax itself changed the library.**
  A full scan per search would stat every folder on every search, which on a network share or
  a spun-down array is the whole wait - the reason the snapshot exists. So `library.py` keeps a
  `_behind` flag: set at start-up, by every `forget_cached_album()` (retag, art, lyrics,
  delete, tag edits) and by the poller as it files a job; cleared by a full walk. Behind means
  the next answer is a real scan. **The cost, stated in the README: an album copied in by
  another program is unmarked until a Rescan or the library tab's own scan**, the same rule
  the library tab already lives by.
- **Fetched BESIDE the search, never before it**, and laid onto what is already on screen when
  it lands - in place, never by re-rendering a grid, which would snap shut a tracklist you had
  just opened. A failed or unconfigured lookup leaves no marks at all rather than "nothing held"
  on every card. One request in flight at a time (`ownedRequest`), and one more after it when
  asked again meanwhile (`ownedAgain`, v0.9.2).
- **An album filed while you look marks itself.** `announceAlbumsFiled()` in
  `ui/src/lib/libraryEvents.ts` also dispatches `deadwax:albums-filed` on `window`, which
  main.js listens for. A window event rather than a bridge entry: it is a one-way notice the
  Preact half gives, not a call the vanilla half needs an answer from, and "an empty bridge
  means the migration is done" should stay true of it. Guarded on `typeof window` for the sims.
- **`.tracklist-chips` is a BLOCK now, not inline-flex** - fixed alongside, and a 0.9.0 bug.
  The edition cell is `nowrap` with `overflow: hidden`, so on a pressing with an edition TAG
  the chips ran inline after it and were clipped to "ANNIVERSARY ...". Nothing showed while
  only the base-tracklist chip and diffs sat alone in the cell.
- **On a phone the card's chip overflows its text column** into the empty space under Find -
  the column is ~80px at 375px beside the match chip and button. Measured: no document
  overflow, the chip ends at 274px of 375. Deliberate rather than wrapping the label over
  three lines.
- **Verified in the real page** on the scratch library: Dummy's card read "In your library · 2
  editions", its 2014 vinyl and 1994 CD rows marked and no others; an untagged "Old Rips/
  Radiohead - OK Computer" folder (made for the check, then removed) gave "Maybe in your
  library"; `deadwax:albums-filed` re-fetched `/library/owned` and re-laid the marks with no
  duplicates.

### Only the newest answer counts (v0.9.2)

James: "when a search function is loading, if I switch to another album or edition before the
search is completed, something breaks ... it's as if it can't handle more than one action at
once." It could; what it couldn't do was tell two apart. Everywhere below, an answer was drawn
without asking whether it still answered the question on screen.

- **The one rule: anything that fetches and then draws asks `current()` first.**
  `interface/scripts/latest.mjs` and its Preact copy `ui/src/lib/latest.ts` are ten lines:
  `begin()` starts a request, supersedes the one before (and ABORTS its fetch, which gives the
  browser its connection back - a Soulseek search holds one for as long as it takes), and
  returns `current()`. A superseded request that fails is dropped silently, catch and all.
  `ui/test/latest.sim.cjs` runs both copies with answers arriving in whatever order it says.
  **New async UI goes through one of these.** `useLibrary` already did the same with a counter;
  it was the exception.
- **The candidates panel was the reported case, and there were three bugs in it.** State was
  three loose globals - the release whose Find was pressed last (`currentExpected`), the last
  result that came back (`lastCandidateResult`), and whatever the screen said. So:
  1. ticking a filter mid-search called `renderCandidates()`, which drew the PREVIOUS search's
     result over "Searching";
  2. a slow search landing after another album's Find drew its candidates under the new
     album's label;
  3. and Download sent `currentExpected` as the release - **filing album A's folder as album
     B**. The worst of the three, since it writes to the library.
  It is one value now, `candidateSearch = {release, pending, result, error}`, which only the
  newest search becomes, and each row enqueues with the release IT was searched for.
  `renderCandidates()` draws whatever state that is, so a filter ticked mid-search redraws the
  "Searching" panel and the answer lands filtered. The format chips are cleared when a search
  begins (they were the last result's formats), and the query box is cleared on a new album's
  Find - left holding the old album's query, Re-search took it for an edit and searched it.
  Closing the panel supersedes its search: reopening always searches afresh.
  (**Ported to Preact in v0.9.10** - `components/CandidatesPanel.tsx`, the same rules as a
  `Search` state value and `lib/latest.ts`; see "The candidates panel in Preact".)
  **Reproduced before fixing** against a fake slskd that answers slowly on demand (8s for one
  album, 2s for another): the old main.js showed All Mine's peers under "Glory Box", and Glory
  Box's folder under "All Mine" - enqueued as All Mine. The fixed one shows each under its own.
- **The results area has one guard for search AND discography** (`resultsRequests`), because
  they share the screen: a search while a browse was loading used to draw and then have the
  browse land on it. Only the newest may put the Search button back (`setSearchLoading`). A
  superseded search is still CACHED - it is the right answer to its own query.
- **A card's Fetch releases** fires once (a second click threw, finding the button it removes
  already gone), skips drawing into a card a newer render has replaced (its grid would have
  joined `mountedReleaseGrids` and the facets while being on no screen), and - asked for in the
  same breath - shows the `.loading-blocks` sweep as "Fetching releases" while it waits.
- **The metadata editor was the dangerous one.** Pick a pressing, then another before the first's
  tracklist arrived, and the first landed LAST and became `selected` - what Apply writes - under
  the second's highlight. `releaseRequests` guards `loadRelease` (including its failure path,
  which would otherwise clear the selection you moved on to), `searchRequests` the search, and
  the retag preview effect gained a `live` flag: the debounce stopped a preview not yet SENT,
  not one already out when the fields changed. Verified: first pick delayed 5s, second pick
  highlighted, the only preview sent was the second's.
- **Also:** the artist page's refresh after saving pictures (the page is not remounted per
  artist, so it could draw the artist you'd left), the artist picker's search and pick, and the
  library's Get cover / Get lyrics / Get CD art buttons, whose results are keyed to the album
  they ran for and now only replace that album's own run. `refreshOwned()` re-asks once when
  asked during a request, since that request may predate the change it is being asked about.
- **Cancelled server-side too, since v0.9.8.** uvicorn doesn't cancel a handler when its client
  goes, so an aborted `find_candidates` used to run its slskd search to the full timeout and
  answer into a closed connection. `unless_abandoned()` (routes/download.py) now checks
  `request.is_disconnected()` every half second and cancels the work, and `search_all` answers a
  cancel by stopping and deleting every search it started (`_abandon`). **Verified live**
  against the slow fake slskd: hanging up 1.5s into an 8s search, slskd was told to stop and
  delete it at once. It needed the middleware fix below first - see the gotcha.
  **A cancel mid-START lost the search until v1.1.7.** Each start runs in a thread, which a cancel
  can't stop: the POST reached slskd, but the CancelledError came out of the await before the id
  was recorded, so `_abandon` never stopped that search. CI's slower runner found it - the test
  cancelled on a fixed 0.1s, during the second start. The start is now shielded, and a cancel waits
  for it and records its id before re-raising. The tests wait for a condition, never a fixed time,
  and one cancels on purpose while the second start is held in its thread.

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

### Albums stored one folder per disc (v0.9.13)

A 1.0 fix, from "Next up". `Album (Disc 1)` and `Album (Disc 2)` grouped as two editions of one
album, and applying the release to the second was refused - the first had already taken the
folder name, and `_resolve_target` never merged into an existing folder.

- **Recognised in the scan** (`split_disc_folders`, library.py): folders tagged with the same
  release id whose discs are ALL tagged and never overlap. The same id alone isn't enough - two
  copies of a release share one too - and an untagged folder is never counted. They get
  `split_discs` and a `disc_label` ("Disc 4", "Discs 1, 2, 3"), count ONCE in `edition_count`,
  and raise a `split_discs` issue in the metadata queue. `SCAN_FORMAT` 6 carries `discs`.
- **`edition` is NOT overwritten with the disc label.** The first cut did, and the editor - which
  seeds its edition field from `album.edition` - previewed the merge as `In Rainbows (2007)
  [Disc 4]`. Caught in the real editor, not by a test; the display goes through
  `editionName()`/`folderSummary()` in groupAlbums.ts instead ("2 disc folders" on the tree row).
  "Standard" is now given only beside another EDITION, not beside the other discs of a release.
- **Applying the release merges** (`_plan_merge`, retag.py) - the first thing allowed into an
  existing folder, and only when all three hold: every audio file there is tagged with THIS
  release id; the discs here (the tracklist's match, else the files' own disc tags - titles
  can't match `01.flac`) and the discs there don't overlap; and no audio file name collides.
  Otherwise the old refusal stands, with the reason. `_merge_into` moves file by file, never
  overwriting: a same-named cover or `.lrc` stays behind with its folder, and is reported. The
  folder goes by `rmdir` once empty. No cover is fetched into a folder about to join one that
  has one. The track-count warning is dropped for a merge - the folder SHOULD hold part of it.
- **The real order is two applies**: the first disc folder to the release is renamed to the
  proper folder, the second merges into it. **Verified in the real editor** on the test
  library's four-disc In Rainbows discbox, split into `(2007)` holding discs 1-3 and `(Disc 4)`:
  the tree said "2 disc folders", both were flagged, applying to discs 1-3 renamed them to
  `In Rainbows (2007) [Discbox]`, and applying to disc 4 previewed "Merge ... moves disc 4 in
  beside discs 1, 2, 3" and left one folder of 28 tracks with no issues.
- **A merge keeps the review row of the folder it joined (v1.1.4).** The retag route passes the
  existing folder as where the album went, and `mark_album_reviewed` used to clear the row there
  first, as for a rename - where a row at the destination describes a folder that has gone. For
  a merge that folder is still there and is the album now, so its first_seen, import source and
  accepted issues were replaced by the disc folder's. The route now passes `merged=True`
  (from `results["merged"]`), and the store keeps the destination's row, marks it reviewed and
  deletes the merged-away folder's; with no row at the destination, the moved row still moves.
  Only a merge: a plain rename's destination row is still stale and still replaced.

### One artist under two names (v0.9.14)

The last of the 1.0 fixes from "Next up": an artist who renamed ends up in two folders -
`Kanye West/` for albums filed before v0.6.18 (or by another tool), `Ye/` since - and the tree
showed two artists, which v0.6.18 left as "at least visible".

- **Noticed by the scan, with no network**: it reads `musicbrainz_albumartistid` now
  (`albumartist_mbids`, `SCAN_FORMAT` 7), and one id under two artist-folder names is the whole
  of the problem - `_mark_artist_under_two_names` sets `artist_folders` and the queue raises
  `artist_split` on every album involved. Which name is CURRENT can't be told without asking
  MusicBrainz, so it doesn't guess. Single-artist albums only: a collaboration's folder is its own.
  Albums without artist ids (anything filed before v0.6.15, older rips) can't be noticed this way.
- **Fixed from the artist page**, which already asks MusicBrainz and shows "Now: Ye": a "Move
  albums to Ye" button there, a previewed dialog, and `src/artist_refile.py` - the EIGHTH writer,
  plan/execute like the rest, the route recomputing the plan on apply. It rewrites only the
  ALBUM ARTIST tag (and writes the artist id where missing) - the same two fields a download
  filed today carries; each track's artist is the sleeve's credit and stays. Each album folder
  moves under the current name keeping its own name, never onto one already there (refused and
  shown), and never an album tagged as a different artist or a collaboration. A tag that won't
  write keeps that album where it is.
- **The old folder follows only when it is truly empty of albums**: its artist pictures
  (`artist.*`, `banner.*`... - `ARTIST_ART_STEMS`) move across where the new folder has none of
  that name, then `rmdir` - so a stray file of the user's keeps it, and an album left behind keeps
  the pictures with it too.
- **`_resolve_artist_mbid` asks the scan first**: an album by this artist alone has its id in
  `albumartist_mbids`, which answers without opening a file. It had read only the track-artist id,
  which an album tagged by Picard or an older deadwax may not carry.
- **Verified in the real page** against live MusicBrainz: `Kanye West/Donda` and `Ye/BULLY`, both
  tagged with Ye's id, were both flagged; the Kanye West page offered "Move albums to Ye", the
  dialog previewed `Kanye West/Donda (2021) → Ye/Donda (2021) · 2 tracks, 2 retagged`, and moving
  left one Ye with two albums, `Kanye West/` gone, album artist "Ye" and track artist still
  "Kanye West".

### Naming album folders from a template (v0.9.17)

One of the 1.0 features. `ALBUM_FOLDER_TEMPLATE` (Library tab -> Organizing, server setting)
names the ALBUM folder; `src/naming.py` is pure and holds all of it; `organizer.album_folder_
template()` is the one reader of the setting, beside `country_in_folder()`.

- **The default is byte-for-byte the old convention**, `{album} ({year}) [{edition}]`, and every
  existing organizer/retag/editions test passes under it unchanged - that is the proof, not a
  new test. Empty, unset or invalid all mean the default; an invalid one is refused on save and,
  from the environment, reported on the row and ignored.
- **The artist folder is not templated.** The artist page, `artist_refile`, the disc merge, the
  misfiled check and `_tidy_emptied_artist` all rely on album folders sitting directly inside an
  artist folder. A `/` in the template is refused with that reason.
- **Both directions.** `render_album_folder` fills it in, and a token that comes out empty
  takes its bracket pair (and the space before it) with it; a bare empty token leaves no doubled
  space or dangling separator. `edition_from_folder` reads the edition back with a regex made
  from the SAME template - bracketed tokens optional, a bracketed token unable to cross its own
  closing bracket, full match. It has to: the scan shows `edition` from the folder, and
  `metadata_health.expected_dirname` rebuilds the expected name from tags plus that edition, so a
  reader that only knew the old trailing `[...]` would flag every album under a template that
  moved it. Under the default it reads exactly as `edition_from_dirname` always did - including
  `Album (1994) [A] [B]` giving `B`.
- **A collision is always resolved**: the discriminator joins `{edition}` as it always did
  (`[Deluxe - 5b6c1a2d]`) and is appended in brackets when the template has no `{edition}`.
- **Tokens**: album, artist (current name), year (the album's - the long-standing rule),
  release_year (the pressing's), edition, format, country, catalog. Values are sanitized
  singly and the whole name again. No `{label}`: the release payload doesn't carry one.
- **Changing it moves nothing.** Albums already filed show as "folder off-convention" until a
  release is applied to them - said on the row.
- **Verified in the real page**: the row previewed `Pink Floyd/Wish You Were Here (1975) [2011
  remaster] and Portishead/Dummy (1994)`, then `1975 - Wish You Were Here [2011 remaster]` and
  `1994 - Dummy` once `{year} - {album} [{edition}]` was saved; `{year}` alone was refused
  ("it needs {album}"); reverting put the default back.

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

### Browsing a discography, and ordering results

- **The search cannot answer "everything this artist released, in order", and a sort control
  over its results cannot either.** MusicBrainz answers a search in relevance order and
  spends the `limit` on whatever matched, so sorting 50 results by year gives the oldest of
  the fifty most RELEVANT — for Portishead that is bootlegs, with the three actual albums
  scattered among them. This is the same trap as the type filter: the fix is to change what
  you ASK for, not to rearrange what came back.
- **So a discography is a BROWSE.** `/search_musicbrainz/discography` takes an artist MBID and
  pages `release-group?artist=…` until it has everything. Portishead: 3 studio albums.
  Dance Gavin Dance: 11, 2007 → 2025, in order. Neither is reachable by any search.
- **Filtering returned rows is wrong for a search and RIGHT for a browse**, which is worth
  stating because the two look identical in code. A search spends a limited budget on
  whatever matched, so discarding rows throws that budget away. A browse has already paged
  through everything credited to the artist, so `studio_only` is filtering the complete set
  rather than a sample. That is why it is applied after the fact here and inside the query
  there.
- **There is a 500-group cap (`DISCOGRAPHY_MAX`) and truncation is REPORTED.** The artist
  credited on a record is not always a person — "Various Artists" carries tens of thousands
  of groups, and paging that would hammer a rate-limited service to build a list nobody could
  read. When it caps, the summary says so and withdraws the completeness claim, because an
  incomplete discography presented as complete is the failure to avoid.
- **The pre-fetched `best-match-releases` are bound to their group BY ID, not by position.**
  They belong to whichever group MusicBrainz ranked first and arrive with no id attached, so
  the old `index === 0` check handed them to whatever sorted to the top once ordering existed
  — a different album's pressings, shown confidently. Verified after the fix: with the sort on
  and 50 results, the card carrying them was at position **45**, not 0.
- **`relevance` is a deliberate no-op, not a sort by score.** It IS the order MusicBrainz
  answered in; re-sorting on the score field would only reshuffle the many groups that tie on
  100 (see the note about the first five results all scoring exactly 100).
- **Undated groups sink whichever direction the sort runs.** Reading a missing date as year 0
  puts every bootleg MusicBrainz knows least about at the top of "oldest first". Pinned in
  `ui/test/sort.sim.cjs`.
- **`interface/scripts/sort.mjs` is `.mjs` for the TEST, not for the browser.** Node reads a
  bare `.js` as CommonJS unless a package.json says otherwise, so the sim could not import it.
  `.mjs` is unambiguous to Node and still serves as `text/javascript`.

### Alternate performances collide with the album they accompany

- **An instrumental release is a DIFFERENT KIND of edition from a deluxe, and it matters
  more.** A deluxe is more of the same album, so a collision loses some bonus tracks. An
  instrumental is a different *recording* — identical track titles, numbers and count — so a
  collision means every file matches one already on disk, all of them are skipped, and the
  job reports that nothing needed doing. You asked for an album and got neither.
- **Verified against the live API:** MusicBrainz holds Dance Gavin Dance's instrumental as a
  RELEASE inside the ordinary album's group, carrying `(instrumental)` in its **title** with
  an **empty disambiguation**. So every source `resolve_edition_label()` consults returned
  blank and it resolved to `Afterburner (2020)` — the standard album's own folder.
- **`resolve_album_dir()`'s escalation does not save you here**, and the reason is a
  deliberate decision documented above: it shares a folder when the existing one is
  UNTAGGED, which is the common case for any library that predates deadwax. The fix has to
  be that the two never resolve to the same name in the first place.
- **`instrumental`, `acoustic` and `a cappella` are therefore in the edition vocabulary**, and
  that vocabulary exists in THREE places which must stay in step: `EDITION_PATTERNS` in
  `matching.py` tags the Soulseek FOLDER being offered, `EDITION_KEYWORDS` in
  `ui/src/lib/release.ts` tags the RELEASE you picked - for a download (through
  `lib/releasePayload.ts`, the one payload builder, since 2.0.0-player.15; `main.js`'s copy did it
  until then) and in the metadata editor - and `EDITION_KEYWORDS` in `main.js` now only DRAWS the
  releases grid's edition chips and facet. The first two are scored against each other, so
  **a marker in only one of them is worse than one in neither** — the release would carry a tag
  no folder could match. **The third copy had none of the three markers until v0.6.9**, so
  applying "Jackpot Juicer (instrumental)" in the editor aimed it at the ordinary album's
  folder, where it could only be refused as "already exists". `ui/test/tags.sim.cjs` pins it.

### The mobile layout

Rebuilt in v0.5.3. It fitted on a phone since v0.3.x, which is not the same as being usable
on one — the whole thing was the desktop layout with `flex-wrap` turned on.

- **The header is one row, and that is where most of the win came from.** It wrapped to four
  — wordmark, connection pills, actions — for **161px of every screen** on a 375px phone,
  before the tab bar. It is ~47px now. Three changes did it, and each is worth keeping:
  the wordmark is set as TEXT on mobile rather than drawn as 350px of ASCII art (`#brand
  -compact`, which is also the accessible name at every size — figlet art read aloud is
  gibberish, so the `<pre>` is `aria-hidden`); **the connection pills only render when
  something is WRONG**; and the actions no longer claim a row.
- **A status that says "everything is fine" is not worth 71px of a phone.** The `ok` pills
  are hidden on mobile and the raw error code goes too — truncated to `UNKNOWN_…` it tells
  you nothing the red dot and the service name have not, and the log is one tap away with an
  unread badge on it. Which connection is down is the part that fits and the part that
  matters.
- **The search form was 450px, on top of that 161px header.** Between them they filled the
  viewport, so a result was never visible without scrolling past everything you had just
  typed. Type, Limit and Search share one row now; the two text fields keep full width
  because they hold the longest values. ~146px.
- **The release-group card header is a GRID on mobile, not a wrapping flex row.** As flex,
  the title wants 100% of `.shrinkable`, which makes it claim the whole row and pushes the
  match chip and Find onto a line of their own — ~55px per card for two small controls.
  Flex-basis percentages can force it back but only by guessing a ratio that breaks with a
  longer label. `grid-template-columns: minmax(0, 1fr) auto` states it directly. Cards went
  from ~280px to ~99px, which is five on screen instead of one and a half.
- **The title is `order: -1`** because the markup lists artist before album, and the album is
  the only part you read while scanning. Two lines then clip — a live bootleg's title is a
  date and a venue and will otherwise take four.
- **Measured, at 375px:** header 161→47px, search form 450→146px, result cards 280→99px,
  first result 770→343px from the top. No horizontal overflow anywhere, no control off-screen
  in any view, and desktop is untouched (checked at 1280px after the cascade move above).

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

### The phone pass (v0.9.31)

James: "mobile needs to be 1000% optimized and working well. no weird overflows or cutoffs,
everything should work exceptionally well". Every view and state was driven at 320, 375 and
390px, at 844x390 (a phone on its side) and at 800 and 1024px tablets, with an audit script run in
each. It flags anything past the screen edge that isn't inside a sideways scroller, text clipped
without an ellipsis, fixed panels running off screen, and tap targets under 32px. Everything it
found was fixed, and it now reports nothing anywhere, apart from 20px checkboxes whose labels are
the real targets. All the CSS is in one commented section at the end of the 768px block, "the
phone pass". What it changed, and why:

- **Every text field is 16px on a phone (`!important`).** Anything smaller makes iOS Safari zoom
  the whole page when you tap into it, and it doesn't zoom back. Every input in the app was
  12-14px.
- **`100dvh`, not `100vh`, for the app's height**, with `100vh` first as a fallback. iOS Safari's
  `100vh` is its height with the toolbar hidden, so the bottom of the page (the library's status
  bar) sat under the toolbar while it showed.
- **Search scrolls as ONE column on a phone** (`#middle-content` is the scroller; the results
  section and its box grow instead). Before, the results scrolled in a box under the form, the
  header and the tab bar, and those never moved: 40% of the screen on a form already used.
  **A screen under 520px tall gets the same** (`@media (max-height: 520px)`), because a phone on
  its side is wider than the breakpoint and so gets the desktop layout at 390px tall.
- **A release in the grid is a BLOCK on a phone, not a row of a 1,700px table.** `main.js` gives
  each cell a `data-label` and an `is-na` class (values MusicBrainz doesn't have); the phone CSS
  lays the row out as ▷, title and Find; then the edition and tracklist chips; then each other
  visible column as a small labelled value; with "N/A" left out and the header hidden. The values
  are `<h4>`s and go inline so a label shares their line - but NOT the Find cell's, which is a
  button that `min-height` must still reach.
- **The card's cover tucks into its header corner** (52px, `:has()` gives the header room only
  when a cover is there), so an expanded card's pressings use the full width. Its height now
  comes from a `--card-height` property that `loadAllCoverImages` sets, rather than inline, so
  the phone rule can square it. The " - " between artist and title, and the spaces around the
  type, are `.releaseGrpSep` spans a phone hides; " match" after the score is too. An undated
  group no longer shows "(N/A)" as its year, anywhere.
- **The results summary counts albums as well as pressings**, with plurals: "2 albums · 20
  releases listed". It said "1 releases" beside fifty cards, because it only ever counted the
  pressings in expanded grids.
- **Candidates**: a full-height sheet; each row a grid with the score, the folder and Download
  on the first line and every detail line spanning under it (`.candidate-body` is
  `display: contents` for this); details wrap BETWEEN items, never inside one ("busy-" / "peer"
  was the old way). The desktop panels' `min-width` floors (280-340px) are dropped on a phone:
  at 320px the metadata editor hung 10px off both sides.
- **Saved panel sizes aren't applied at phone width** (resize.js `PHONE`), and a window
  narrowed into it drops the inline geometry. A size saved at a desk is an inline style, beats
  every phone rule, and there's no way to resize it back on a phone.
- **The track list is a music app's on a phone**: tick, number, title, length, 44px rows, no
  sideways scroll. Body cells now carry `data-column` so CSS can pick them; the header can't be
  dragged or resized and the Fields button is hidden (the fields are a desktop table's). Its
  minimum width moved from inline `min-width` to a `--track-min-width` property for the same
  reason as the cover height; the resize drag writes the property too (checked with a real drag
  at 1440px). The editions table shows edition, year and tracks, with any issue on its own line.
- **Tree rows have a shrink order**: the issue chip and the edition count give way, ellipsized,
  before the album's name does - "Dummy" was drawn as "D." on a 375px phone. The weights are in
  the thousands, not a fraction on the name: when the chips reach their minimum the name is the
  only item left to shrink, and flex takes back space in proportion to the weights' SUM when
  that is under 1, so a 0.001 on the name left rows running off the screen.
- **Pinch to zoom a cover** (ArtViewer): the image takes `touch-action: none` for its drag, so
  the browser's own pinch never happened there. Each finger's listeners answer only their own
  pointer (every finger's hear every finger's events, and lifting one ended the other's gesture),
  the finger left after a pinch pans on without a jump, and a still finger lifted after a pinch
  isn't a tap. The hint says "tap … pinch" on a touchscreen (`hover: none`).
- **Also fixed at every size**, found by the same sweep:
  - The search row pushed Search 95px off the edge between 769 and about 940px; the fields
    now shrink, down to 7em.
  - The library toolbar pushed Rescan off at 800px; it wraps now.
  - The tag editor's Disc box grew to match the Track field beside it.
  - The editor's release rows could lose their title to a long detail line.
  - The artist page's links were the browser's default blue.
  - The facet checkboxes sat 4px from the edge at 420px, because side padding was dropped
    under a -8px margin.
  - The sort menu started 2px off the screen.
- **Verified in the real page** at every size above, with screenshots and the audit. On desktop,
  checked unchanged: 184px search fields, the release table with its header, the separators, 10
  track columns, and the Fields button.

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

### The library explorer (v0.6.5)

James asked for it by description: artists at the top, albums indented under an artist when
you click it, songs under an album, metadata in a pane on the right. It replaced the list of
full-width album cards (`LibraryAlbumRow`, deleted), whose middle was mostly empty space.

- **The tree is drawn FLAT** - one row per node, `--tree-level` for the indent, `aria-level`
  for assistive tech - from the pure `lib/libraryTree.ts::visibleRows()`. Keyboard navigation
  walks a flat order anyway. What is visible when is decided there and pinned by
  `ui/test/tree.sim.cjs`, not in a component's render.
- **The 711ms rule still holds, harder.** Nothing below an album exists until it is opened
  (pinned in the sim), and the details pane renders ONE album's track table at a time.
- **Click opens, the twisty toggles, arrows select without opening.** A click selects AND
  opens but never closes - "if you click on an artist, then the albums are listed below".
  The triangle toggles without selecting; the keyboard moves like Explorer's (right opens or
  steps in, left closes or steps out to the parent). Only the selected row is in the tab order.
- **The editions decision survives the tree.** An album you hold several pressings of says
  "N editions" on its OWN row, so the fact this view exists to show still needs no click; it
  opens to one row per edition, and each edition opens to its tracks. A single-edition album
  opens straight to tracks - one level per release, as before.
- **Filtering opens what it found.** Every artist with a match starts open (three matches under
  three closed artists would make you open each one); what you close is remembered until the
  filter changes. **The search matches song titles** from two characters, and an album opened
  only by a song match shows just the matching songs - opening it by hand shows them all.
- **Four arrangements, and three of them drop the artist level** (v0.6.6, asked for: release
  date, album name, artist name, date added). Sorting artist folders by an album's release date
  means nothing, so by album / release date / date added the tree lists albums directly under
  group headings - initial, year, month - the way Windows 7's music library did "Arrange by".
  Each sort starts its natural way round (names A-Z, release date oldest first like the search
  tab, date added newest first) and one button flips it; the choice is saved in
  `deadwax-library-sort` and validated on read. Undated albums sink in both directions.
- **"Date added" is the EARLIER of `first_seen` and the folder's mtime** (`albumAddedAt`).
  `first_seen` is exact for anything since install, but every album present on the first scan
  shares that one moment; the folder mtime spreads those out but moves when a cover is added.
  Neither alone is honest, and the earlier of the two is right in both cases. An album group
  takes its NEWEST edition's date, so a deluxe press that arrived today is news. The overview's
  "Recently added" shelf uses the same clock.
- **The selection index covers the whole library, not the filtered tree**, so what you picked
  stays in the pane while you narrow the tree instead of blanking the moment it stops matching.
- **Tree and pane share one selection, with two ways to follow it.** A keyboard move takes
  focus (`focusToken`); picking something in the pane opens the tree down to it and scrolls it
  into view WITHOUT taking focus (`revealToken`). Mixing them up yanks the keyboard out of
  whichever pane you were in.
- **Track details are read live by `/library/tracks`, never carried in the scan.** The scan is
  cached on folder mtime, which a retag by another tool doesn't move, and thirty-odd tags for
  every track would bloat the library-wide payload. The scan's copy fills the basic columns at
  once; tag-only columns show `·` until the files land, not a blank that reads as "no genre".
  `useTrackDetails` caches per album and **drops the cache on every library reload** - an
  in-place retag changes neither the path nor the mtime, so nothing else would notice.
- **`/library/tracks` is the third endpoint that turns user input into a filesystem read**
  (with `/art` and `/deletion_summary`), and copies `/art`'s guard exactly, identical 404
  included. Tested with the same traversal cases.
- **Field choices have their own storage key** (`deadwax-library-fields`) and one writer - the
  details pane's single `useTrackFields` instance, which the menu and the table both read.
  It stores `seen` beside `visible`, so a field added in a later version takes its own default
  instead of staying hidden for everyone who ever touched the menu. Pinned in the sim. Since
  v0.6.9 the same key and writer also hold the columns' `order` and `widths` - see "Arranging
  the track viewer's columns".
- **The splitter's width is persisted (`deadwax-library-pane-width`) and capped in CSS** at
  `100% - 340px`, so a width saved in a big window can't swallow the details in a small one.
- **What fits on a tree row depends on the TREE's width, not the window's.** `#library-nav` is
  a size container, and `@container` rules drop the issue chip, then the year, as it narrows.
  The album name is never what gets squeezed.
- **On a phone the details pane is a full-screen sheet**, opened by picking an album or a
  track (an artist just opens in place) and closed by the command bar's back button.

### The tree draws only what is in view (v0.9.30)

James: "build the tree windowing". A broad filter opens everything it touches, and the tree was
drawn whole: 12,720 rows for a song search on a thousand albums.

- **Rows are absolutely placed inside a tree as tall as all of them**; only those within
  `OVERSCAN_PX` (600) of the view are drawn. `ui/src/lib/treeWindow.ts` is pure and does the
  maths (offsets, the visible span, siblings), pinned in `tree.sim.cjs`; `LibraryTree.tsx` only
  measures and scrolls.
- **Heights are MEASURED, one per row kind** (`heightKey`), after every render. Labels never
  wrap, so every row of a kind is one height; measured, not assumed, because the phone's rows are
  36px and a narrow tree hides chips. Fractional, from `getBoundingClientRect` (nothing in the
  tree is transformed): `offsetHeight` rounds, and half a pixel over 12,000 rows is 6,000px.
  A width change re-measures. **So nothing in the tree may give a row a margin, or a height that
  depends on its neighbours**: `.tree-heading:first-child` became `.is-first`, set by index,
  because a positioned row's DOM neighbours aren't its list neighbours any more.
- **The selected row, the tab stop and the focused row are always drawn**, wherever they are
  (`rowsToDraw`'s `pinned`). That is what keeps keyboard focus alive when you scroll away, and
  what lets the existing `scrollIntoView` calls (a keyboard move, a pick in the details pane) find
  a row that was nowhere near the view.
- **`aria-posinset` and `aria-setsize` on every item**, since assistive tech can no longer count
  siblings that aren't in the page.
- **Measured on the generated library**: opening the tab now has no main-thread stall over 30ms
  (one of 300-400ms before); the 12,720-row "track" filter applies in 246ms, 200 of them the
  settle, with a single 36ms stall (340ms warm and up to 3s cold before); scrolling the whole
  result in 440 jumps never stalls; 61 rows are in the page at once.
- **Verified in the real page** on the scratch library, fully expanded: all 151 rows at exactly
  the positions and sizes the full render gave them (to 0.1px), the same tree height; every
  arrangement laid out gap-free, headings included; End and Home jump to the ends with focus;
  the focused row survives a scroll to the far end and the next ArrowDown carries on from it.

### The saved scan (v0.6.5)

- **Opening the tab makes two requests, on purpose.** `?snapshot=true` answers from the cache
  without touching the disk - instant however slow the storage - and is drawn at once, marked
  stale with its age; a real scan then runs underneath and replaces it. With nothing saved the
  snapshot request falls through to a real scan, so an unscanned library never draws as empty.
- **The in-memory cache is persisted to `library_cache`, keyed exactly as in memory** (absolute
  folder path) plus root and `SCAN_FORMAT`, and still validated against folder mtime before it
  is trusted. Losing the table costs one slow scan and nothing else - it is a cache, not a record.
- **Bump `SCAN_FORMAT` in library.py whenever `read_album_dir()`'s output changes shape.** A
  saved row outlives the process, so an old row for a folder nobody touched would be served
  forever without the new field. Other formats are ignored on load and swept on save.
- **Every forget reaches the disk as well** (`_persist_cache` after retag, art fetch and
  delete). An in-place retag doesn't move the folder's mtime, so a saved row left behind would
  load the pre-edit tags straight back in on the next restart - and they would match.
- **A snapshot never enrols or prunes review rows.** An album filed since the snapshot was
  taken is absent from it, and pruning would delete its new import row as an orphan before
  anyone had seen it. Pinned by a test that shows a real scan DOES prune it.
- **Scans hand out COPIES of the cached dicts.** Responses are decorated in place
  (`_mark_multi_edition`, `attach_issues`), and decorating the cached dict itself is how an
  album went on calling itself "Standard" after its only sibling was deleted - a latent bug
  that persistence would have written to disk. Fixed and tested.
- **Scans are serialised by `_scan_lock`; snapshots deliberately are not.** They exist to
  answer while a slow scan runs, and `dict.copy()` is atomic under the GIL.
- **Rescan is still the escape hatch, and now more often the only one.** A retag by another
  program is invisible to an mtime cache; a restart used to be the accidental fix for that, and
  no longer is. Rescan's tooltip says so.

### Disc numbers (v0.6.5)

- **Tracks carry both numberings.** `position` stays the RUNNING number across discs - the
  matcher keys on it and files are named after it, which keeps a two-disc set in order inside
  one folder - and `disc`/`disc_position` are MusicBrainz's own. `flattenTracks()` in release.ts
  (the editor's) and `tracksOf()` in `lib/releasePayload.ts` (a download's - `buildExpectedFromRelease()`
  in main.js until 2.0.0-player.15) both produce them; keep the two in step.
- **A multi-disc release is tagged per disc; a single-disc release writes no disc tag at all -
  unless the file claims some OTHER disc (v0.6.9).** Writing "1" everywhere would give every
  album in the library a discnumber diff, so an album that is already right could never again
  say "nothing to change". But the unconditional rule had a hole James found on Jackpot
  Juicer: its opening track, "Untitled 2", sat alone on "disc 2" of a one-disc album, and since
  a single-disc release writes no disc tag, re-applying the right release could never move it
  back. `tag_values` now takes the file's `current` tags and writes `discnumber=1` only when
  the file carries a disc number other than 1 ("1/1" and "01" count as 1). Both callers pass
  the same reading of the same file - `plan_retag` from `read_current_tags`, `write_tags` from
  the audio it already has open - so the preview still cannot disagree with the write.
  **How "Untitled 2" got there is not known.** MusicBrainz's group holds a Target-exclusive 2×CD
  whose disc 2 is the whole album again with "(instrumental)" titles, but the matcher walks the
  tracklist in order, so disc 1's exact "Untitled 2" claims the file first - pinned in
  `test_the_instrumental_disc_does_not_claim_the_opening_track`. The files may simply have
  arrived that way. The fix doesn't depend on knowing.
- **A missing disc number DISPLAYS as a dimmed 1 (v0.6.9, asked for: "defaults the disc number
  to 1 if there isn't another value").** It shows "1" in the tertiary grey with a tooltip
  saying the file carries no disc tag - `TrackField.inferred` is the hook, because a default
  that looks exactly like a tag is a small lie about what is on disk. Once a track's own
  details have been read they win outright, even when they say "none": a stale scan must not
  keep showing a disc number the file no longer has. `disc_count` is unchanged - it counts only
  TAGGED discs, 0 when none - so the "Disc N" headings are still driven by real tags. The tag
  editor's disc field shows the same default as its placeholder.
- **The download request's `Track` model declares `disc` and `disc_position`.** pydantic drops
  undeclared fields without a word, and downloads would have been tagged 1..20 with no discs -
  quietly unlike the same album corrected in the editor. Tested.
- **The scan reads `discnumber` and orders disc-first**, so a two-disc set stops interleaving
  (1, 1, 2, 2...). `disc_count` counts distinct TAGGED discs - 0 when untagged, never a guessed
  1 - and only `disc_count > 1` is split under "Disc N" headings.

### Disc titles (v1.1.0)

James: "is it possible to save cd titles? ... the dark side of the moon 50th anniversary box set,
it just says disc 1 2 3 4. I would like to make it where disc 4 actually says 'Live at Wembley -
From Pre-FM Master Tape'".

- **It is MusicBrainz's MEDIUM title, written as `discsubtitle`**: Picard's DISCSUBTITLE, ID3's
  TSST (a v2.4 frame), an MP4 freeform atom. Navidrome reads all three (its mapping lists `tsst`,
  `discsubtitle`, `----:com.apple.itunes:discsubtitle`) and returns them as OpenSubsonic
  `discTitles`. Every medium MusicBrainz sends has a `title`, '' for most. James's exact words are
  disc 4 of a 2018 GB BOOTLEG, "The High Resolution Remasters" (`74a781e4-...`), there as "TDSOTM -
  Live at Wembley - From Pre-FM Master Tape"; the official 2023 box calls its live discs "The Dark
  Side of the Moon Live at Wembley Empire Pool, London, 1974".
- **Carried per TRACK, as `disc_title`**, by both builders (`lib/releasePayload.ts` for a download -
  main.js's `buildExpectedFromRelease` until 2.0.0-player.15 - and `flattenTracks` in release.ts for
  the editor: the same trim-to-null rule; keep them in step) and declared on
  the download `Track` (the pydantic trap, a sixth time). Per track because `tag_values` already
  takes everything about the disc from the track. It reaches the file on both paths because the
  organizer and, since v1.0.10, `execute_retag` both hand `write_tags` the matched track whole.
- **Written whenever MusicBrainz has one, one disc or several**, unlike the disc NUMBER: that
  rule exists because "1" would land on every album, and a title lands only where somebody gave
  the disc one. An untitled disc writes nothing, so a title a file carries stays - the rule for
  every tag - which also means only a hand edit clears a wrong one. `read_current_tags` reads it
  back, or every titled disc would show a change for ever.
- **Easy MP4 had no key for it**, so an m4a could neither show nor take one. `src/tagkeys.py`
  registers the freeform atom `----:com.apple.iTunes:DISCSUBTITLE`, and the places that read or
  write it open files through `easy_file()`, which registers first. Four keys `tag_values` already
  wrote have the same m4a gap (originaldate, musicbrainz_releasegroupid, media, catalognumber: an
  m4a album never reads "nothing to change") - known, and left alone: James isn't worried about
  m4a for now.
- **The scan carries ONE map per album, `disc_titles`, keyed by the disc as a STRING** - the
  saved scan is JSON, which would hand number keys back as strings after a restart;
  `discTitle()` in libraryTree.ts looks up `String(disc)`. The commonest title per disc, untitled
  discs left out; the per-track `disc_title` is server-only on the wire. From the scan, not the
  live details, because the tree never loads details, and the table's headings would appear late
  and disagree with the tree's. The "Disc title" column (live, off by default) still shows what
  each FILE carries. `SCAN_FORMAT` 8, so the first visit after upgrading waits for one full scan.
- **Shown as "Disc 4 · <title>"** on the tree's disc rows, the track table's headings and a
  track's "disc 4 of 4" line; the editor's release rows list each disc's title in their tooltip.
  A folder holding ONE disc of a set kept one folder per disc has no headings (its `disc_count` is
  1), so `editionName()` names it there instead: "Disc 4 · <title>" on its tree and editions rows
  - found by the review, and the likelier shape of James's "it just says disc 1 2 3 4".
  The title is a `.disc-title` span in its own case beside the uppercase label. **`.tree-disc` is
  one line with an ellipsis**: the windowed tree measures one height per KIND of row, and a title
  that wrapped would run over the rows below. The whole title is its tooltip.
- **Hand-editable as "Disc title"** (`EDITABLE_TAGS` / `EDIT_FIELDS`), for the discs MusicBrainz
  leaves untitled, and for trimming a bootleg's "TDSOTM - ".
- **Verified in the real page** (headless Brave) on a scratch copy of the bootleg's 55 tracks
  tagged with its release and no titles: the editor's release row listed the four disc titles,
  the preview showed `discsubtitle - -> TDSOTM - Live at Wembley...` on disc 4's ten tracks, the
  apply wrote them and then read "Nothing to change", and the tree and table read "Disc 4 · TDSOTM
  - Live at Wembley - From Pre-FM Master Tape" at 1440 and 390px, no overflow, every disc row one
  height. Ticking disc 4 and setting Disc title by hand made it "Disc 4 · Live at Wembley - From
  Pre-FM Master Tape". A row's Find on that release sent all 55 tracks with their disc titles.

### Editing tags by hand (v0.6.9)

Asked for: "a way to manually edit metadata per-song with a selection option so I can also
mass-edit". It used to be on the "Deliberately not built" list, as "the metadata editor takes a
release's tracklist wholesale" - which stays true of the metadata editor. This is a separate
tool beside it.

- **`src/track_tags.py` is the fourth writer, with the same plan/execute split.**
  `plan_tag_edits()` reads each named file and reports only what would change;
  `execute_tag_edits()` writes that and nothing else. `/library/tags/preview` and `/apply` are
  separate endpoints, and apply RECOMPUTES the plan from the edits, never accepting one back.
- **A file is named by its bare filename, and must appear in a LISTING of the album's folder.**
  That is the whole containment story for files: nothing a caller sends is joined onto a path
  until it has matched an entry that was already there, so `../../etc/passwd` and
  `Disc 2/01.flac` are refused without ever being resolved. The album path gets the usual
  `is_within` guard. Tested with the retag's traversal cases plus a symlink.
- **Only `EDITABLE_TAGS` can be touched**: title, artist, album, album artist, track, disc,
  date, original date, genre, composer. The MusicBrainz ids are an album's identity and change
  by applying a release, where the preview can say what that means. The list exists twice -
  `EDITABLE_TAGS` in Python, `EDIT_FIELDS` in `ui/src/lib/tagEdit.ts` - and
  `test_the_editable_tags_are_exactly_the_ones_the_dialog_offers` reads the TypeScript to keep
  them in step.
- **Only EDITED fields are sent.** A field whose values differ across the selection starts empty
  and says "several values"; left alone it is in no edit, so each track keeps its own. Sending
  the form's value for every field would write the shared value - or a blank - over every
  track. `buildEdits` holds that rule and `tags.sim.cjs` pins it. An edited field left EMPTY
  removes the tag, and the preview says "removed".
- **The whole batch is refused if any of it is invalid** - a track number that isn't a number, a
  date that isn't a date, a file that isn't there - for the settings route's reason: half an
  edit, with no way to tell which tracks changed, is the worst outcome available. The same bad
  value sent to eighteen tracks is reported once.
- **A tag a format can't hold is NAMED, not swallowed.** Easy MP4 has no `originaldate`. The
  organizer's `write_tags` skips such keys silently, which is right for a bulk tag and wrong for
  a field somebody typed into. The rest of that file's edit still lands.
- **Tags only.** No file is renamed and no folder moves - re-filing is the metadata editor's
  job, and it previews it. Applying marks the album reviewed, as a retag does.
- **The selection lives in the details pane, per album.** A tick box on every row and a
  tri-state one in the header; Ctrl/Cmd-click and Shift-click tick (Shift runs a range to the
  clicked box's NEW state, as a mail client does); Space ticks the focused row; a plain click
  still opens the track, as it always has. Going to another album clears the ticks and closes
  the editor, whose files it could no longer see. The editor's file list is FIXED when it
  opens, so its preview is never recomputed against a selection changing underneath it - and
  so its effect's dependencies stay stable: a fresh array every render would re-preview forever.

### The MusicBrainz user agent (v0.6.9)

Asked for: "use the current version automatically ... and have the user only set the email".

- **`MUSICBRAINZ_EMAIL` is the setting; the user agent is BUILT, on every call**, as
  `deadwax/<__version__> ( email )` - MusicBrainz's documented shape. Nothing stores the
  finished string, so the version can't go stale and a contact changed in the settings tab
  applies at once. `Config.musicbrainz_user_agent()` is the only place it is made.
- **An old `MUSICBRAINZ_USERAGENT` keeps working.** `contact_from_useragent()` lifts the contact
  out (the last bracketed part, else a token with `@` or `://`) and the name and version are
  rebuilt around it, so an install nobody touched starts reporting the version it runs. With no
  contact to find, it is sent verbatim - it is what the install was already sending, and
  replacing it with nothing would be worse. The settings tab shows that row only while it is
  set, or overridden (which has to stay visible to be revertable).
- **An email that can't go in a header is passed over, not sent.** httpx refuses a non-ASCII
  header value while building the client, which would fail EVERY MusicBrainz request rather
  than this one field. `describe_contact()` refuses it on save, along with brackets, spaces,
  and anything with neither an `@` nor a `.`.
- **The Cover Art Archive client sets the header PER REQUEST.** It is built once for the
  process, so a header fixed at construction went on sending the old contact after a settings
  change - a latent bug with `MUSICBRAINZ_USERAGENT` too.
- **It is reported from the lifespan, after the overrides are applied** (`report_musicbrainz()`),
  not from `Config.check()`, which runs before them - an email set in the tab would otherwise
  be logged as missing on every restart.
- **Verified against the live API:** the dev `.env`'s hand-written user agent was rebuilt as
  `deadwax/0.6.9 ( dev-test@example.com )`, and MusicBrainz answered 200.

### Cover art size (v0.6.9)

- **`COVER_ART_SIZE`: 250 | 500 | 1200 | full, default 500 - the size it always was.** Asked
  for as "full-size album art ... maybe make it an option somewhere". A SERVER setting rather
  than a browser preference, because it decides what is written into the library, which every
  device should agree on. `full` is the Archive's bare `front`, the original upload and often
  several MB; when the original isn't an image (the Archive takes PDFs) it falls back to
  `front-1200`. A 404 is not retried at another size - no cover is a fact about the release.
- **Settings with a fixed vocabulary carry `choices`** (value -> label), and the tab draws a
  dropdown for any row that has them. `ORGANIZE_MODE` lost its special case in the component.
- **The editor says which size it will save**, from `plan.art.size`, which the preview route
  lays on so that `plan_retag` stays pure. The full-size comparison shows the original whatever
  the setting, so its save button's tooltip names the size that will actually be saved.

### Looking at a cover close up (v0.6.12)

Asked for: the zoom "doesn't follow the cursor at all. and it doesn't move either".

- **The viewer zooms about the cursor and is dragged to move**, instead of toggling between fit
  and actual size. The toggle was no use for the job the viewer exists for - deciding which of
  two scans to keep - because actual size put the image in a scroll box centred on its middle, so
  the corner you wanted to look at was reached by scrollbars if at all.
- **It is a transform, not a scroll box**: `translate(x, y) scale(z)` on the image, inside a
  stage that keeps `overflow: hidden`. A scroll position cannot be anchored on a point, and the
  old note still holds for why the scroll box was awkward - a flex container centring an
  overflowing child pushes its left and top edges out of reach of the scrollbars entirely.
- **Zoom holds whatever is under the cursor still.** The translation is measured from the stage's
  centre, which is where the image is anchored, so `x' = px - (px - x) * z'/z` with `px` the
  cursor's offset from that centre. **Verified in the browser:** at 3.3x the point under the
  cursor had drifted 2px (the rounding in the screenshot's coordinate frame), and a click-zoom to
  2x drifted 0 on both axes, with neither axis clamped.
- **The image cannot be dragged off its own pane.** Panning is clamped to the overflow, so an
  edge never comes inside the stage. The corollary is worth knowing before it reads as a bug: at
  a modest zoom, where the image is barely bigger than the stage, the clamp WINS over the
  anchoring and it re-centres, because there is nothing to pan into.
- **A click zooms to `max(2, actual size)`.** 1:1 on its own is not always a visible step: this
  album's cover is 600px shown at 570, so "actual size" zoomed it by five per cent and read as
  the click having done nothing. The wheel is for the sizes in between.
- **The wheel listener is added by hand, non-passive.** Preact's `onWheel` can't be marked
  `passive: false`, and a passive listener may not `preventDefault`, so the page behind the
  viewer scrolls instead of the cover zooming.
- **`offsetWidth` over the rect matters more than usual here**: the image is the transformed
  element, so its rect is the ZOOMED box, and feeding that into the clamp multiplies the zoom
  back in on every frame.

### Arranging the track viewer's columns (v0.6.9)

Asked for: "reorder and resize columns in the library metadata".

- **Drag a header to move its column, drag its right edge to size it**, double-click the edge to
  give the column its own width back. Reset in the Fields menu restores fields, order and widths.
- **The order covers EVERY column, hidden ones and the title included**, so a field you hide and
  show again comes back where you put it. The title moves like any other column but can't hide.
- **Same key and same single writer as the field choices** (`deadwax-library-fields`,
  `useTrackFields`). `order` is written only once it differs from the default, and `widths` only
  once there are some, so a later version's defaults still reach anybody who never arranged
  anything. `reconcileOrder` places a column the saved order has never heard of beside its
  default neighbour rather than at the end - the order's equivalent of `seen`. Pinned in
  `tags.sim.cjs`.
- **A sized column is exactly that many px; the rest keep their `fr` sizes** and share what is
  left. `min-width` is a `calc()` of the em minimums plus the fixed pixels.
- **A drag pins the flexible columns to its LEFT, and that is what makes the grip follow the
  cursor (v0.6.12, asked for).** A flexible column shares the row's spare space wherever in the
  row it sits, so widening a column took that space out of the title beside it: the column's own
  left edge travelled as far as its right edge did, its width barely changed, and the whole table
  reflowed under the cursor - "super janky", and it was. `startResize` now measures the flexible
  columns before the grip and pins them at the width they are already drawn at, which changes
  nothing on screen, and commits them with the drag so the release doesn't reflow either.
  Columns to the RIGHT still absorb, so the table goes on filling the pane; when none are left to
  absorb it grows past the pane and `.track-table-scroll` scrolls, as Explorer does. **Verified
  with real pointer drags:** 100px of pointer moved the artist column's right edge exactly 100px
  with its left edge still and the title unchanged, and 80px on the title did the same.
- **The grip keeps the offset it was grabbed at.** The grip is 7px wide and is taken hold of
  somewhere inside that; the edge holds that distance from the pointer for the whole drag, or the
  first move snaps the column onto the cursor by up to 7px.
- **Cell text is anchored LEFT, numbers included (v0.6.12, asked for).** Right-aligned numbers
  slide along as their column is sized, so the column you are dragging looks like it is shuffling
  its contents about. `TrackField.align` is deleted rather than left as metadata nothing reads -
  the `.track-cell.is-right` rule stays, because the album summary row still uses it.
- **While resizing, the template is written straight onto the table's style** - one write a
  frame rather than a render of every row - and committed once on release, which renders the
  same string. Nothing moves until a header drag has travelled 5px, so a click or the start of
  a right-click never rearranges anything, and only a change of landing spot causes a render.

### The artist page (v0.6.15)

Asked for: artist metadata "the same way" as albums, and "regular square images, banners, and
anything else I'd need for an artist page".

- **MusicBrainz hosts NO artist images.** The Cover Art Archive is releases only. What
  musicbrainz.org itself draws on an artist page is a Wikimedia Commons file reached through
  that artist's Wikidata link - so "get the image from MusicBrainz" is not a thing that can be
  done, and anyone who assumes otherwise will look for an endpoint that does not exist.
- **Three sources, and only the one that needs a key has what a page is made of.** An `image`
  RELATION (present for some artists, not others - Tame Impala and Portishead have one,
  Radiohead does not) and Wikidata's P18/P154, both of which resolve through Commons' bare
  `Special:FilePath`; and TheAudioDB, keyed by the same MusicBrainz artist id, which is the only
  one carrying wide shots and clear art; and **fanart.tv**, added on request, which has thumbs,
  banners, backgrounds (including 4K) and logos, and is the only source whose pictures were
  VOTED on by the people using them - so `from_fanarttv()` offers the most-liked of each kind
  first. Both are optional and everything degrades to "a photograph, where Commons has one".
  **fanart.tv's key is a PROJECT key, issued per application rather than per person**, so it
  cannot ship with deadwax and has to be registered by whoever runs it; `FANARTTV_PERSONAL_KEY`
  beside it is optional and only buys sight of images added in the last week.
- **The square image is written as `artist.*`, and that is the whole point of writing files at
  all.** Navidrome reads it with no configuration: `ArtistArtPriority` defaults to
  `"artist.*, album/artist.*, external"`. Writing it as `folder.*` - what Jellyfin and Kodi call
  an artist thumb - would be invisible to Navidrome AND sits in its COVER ART priority, so in a
  folder that turned out to hold audio it would be read as that album's cover. The other five
  (`banner`, `fanart`, `logo`, `landscape`, `clearart`) are what deadwax's own page is made of;
  Navidrome displays none of them, Kodi and Jellyfin read them, nothing else notices.
- **A folder holding TRACKS is refused.** That folder is an album to the scanner, and dropping
  `artist.*` into it means something else entirely to every reader of these files.
- **An artist has no folder in the scan, so it is derived** from where their albums are, and
  only when they agree. Albums in two places, or one sitting at the top of the library, get a
  message rather than a guess - a picture written into the wrong folder is not dangerous, just
  silently useless, which is worse to debug.
- **Applying only honours a URL the artist's own sources just offered.** The apply route
  recomputes the candidate list exactly as it recomputes the plan. Without it, `choices` could
  name any address - inside the network this container sits in - and deadwax would fetch it
  and write the answer into the library under a name other tools read. Pinned by a test.
- **Which artist this is comes from the TAGS first, and a name search is only believed when it
  is unambiguous** (one exact name match, MusicBrainz score >= 90). Several bands share a name,
  and the cost of getting it wrong is another band's photograph in this band's folder, where
  nothing would ever flag it.
- **The MusicBrainz half of the page is debounced by 400ms**, like the tag editor's preview.
  Arrowing down a list of artists must not fire a lookup per row at a rate-limited server, three
  hosts deep.
- **The picker searches, and any picture can go in any slot (asked for).** Two things
  a rule cannot settle. WHICH ARTIST, when the files carry no ids and the folder name means
  something else to MusicBrainz - the automatic match deliberately refuses to choose between the
  eight acts called Nirvana, and a search box with their disambiguations is the way past that;
  picking one hands its id to the same preview the tags would have. And WHICH PICTURE goes
  where: the sources are wildly uneven, so "use another picture" offers everything found for
  every slot. **Without a TheAudioDB key that is the difference between a usable dialog and a
  dead one** - the only candidates are Commons photographs, all of them of kind `thumb`, so
  every other row reads "none found" and the square is the only thing selectable. Which is
  exactly how it was reported.
- **Links that would share a label say where each goes (v0.9.34).** Portishead read "Official
  site Official site ... YouTube YouTube". `_tell_apart` in artists.py (pure) adds the host where
  the hosts differ, and the deepest path segment that differs where they don't (YouTube's
  `/channel/<id>` - the ids, cut to 10 characters; the tooltip has the whole address). A host the
  whole group shares is never added ("YouTube · youtube.com" says nothing), so what nothing else
  separates is numbered. A Wayback Machine address is read as the page it archived:
  "godiscs.co.uk (archived)", not "web.archive.org". A link alone under its label is untouched.
  The dedupe is on the PLACE now (host without www, path, query, archived), not the exact string:
  http and https, or a trailing slash, of one page is one link. Verified on the live Portishead
  record, at 1024 and 375px.
- ~~Known gap: on a phone the artist page is unreachable~~ **Closed in v0.9.31**: tapping an
  artist opens it in place, as before, and tapping it again, open, opens the sheet with its page
  (`activate` in LibraryView: `row.kind !== 'artist' || row.open`). The phone rules written for
  it apply now, and were checked at 375px.

### CD art and embedded pictures (v0.7.2)

James: "on the individual songs in amperfy, the cover art doesn't always match the album" - and,
once the answer was in, "add the view and let's add grabbing cd art".

- **Why songs show other pictures, read in Navidrome's source, not guessed.** `MediaFile.
  CoverArtID()` (model/mediafile.go): a file with an embedded picture is shown with THAT
  (`EnableMediaFileCoverArt`, default true); otherwise a song with a disc number gets the DISC's
  artwork, whose default priority is `disc*.*, cd*.*, cover.*, folder.*, front.*, discsubtitle,
  embedded` (conf/configuration.go). So two routes to a mismatch, and deadwax fed both: it never
  touches embedded pictures, and the organizer carries every image beside a download's tracks
  into the library - `cd.jpg` scans included - as companions.
- **The track view lists a file's pictures** (`describe_pictures` -> `pictures` on the track
  details, bytes served by `/library/tracks/picture`, the file matched against the folder's own
  listing like the tag editor's). `embedded_pictures()` is now the ONE reader of every container
  - FLAC blocks, Ogg's base64'd METADATA_BLOCK_PICTURE (which `read_embedded_art` had never
  read at all), ID3 APIC, MP4 covr - and `read_embedded_art` picks from it by type as before.
  Real pixel sizes are measured by the browser as the image loads, not parsed server-side.
- **The album's properties count tracks carrying their own picture**, from the live details, and
  a `Picture` field (default off) marks them in the table. Neither is in the scan, which would
  mean opening every file's picture blocks for a count.
- **CD art is written as `disc.<ext>`, or `disc<N>.<ext>` per disc of a set.** Navidrome's
  `fromExternalFile` (core/artwork/disc.go) matches a NUMBER after the glob's prefix to that disc
  and lets an unnumbered file stand in for any disc; Kodi and Jellyfin read `disc.*`. `disc`
  before `cd` in that order is also what makes a fetched image outrank a download's `cd.jpg`
  without deleting the scan - so a `cd*` file does NOT hide Get CD art; only deadwax's own
  `disc*` does.
- **Sources: the Cover Art Archive's "Medium" images for the EXACT release first**, then
  fanart.tv's `cdart` for the release group (needs the key already in settings). The release
  comes from the album's tags, as a cover's does, so it chooses nothing and needs no preview.
  Size follows `COVER_ART_SIZE`. The route computes every URL itself from the sources' own
  listings; nothing a caller sends is fetched.
- **Numbering a set's images is done only where it is safe**: by the image's own comment ("CD2",
  "Disc 1" - measured on In Rainbows' discbox), or in upload order when there are exactly as many
  images as discs; otherwise one unnumbered image stands for every disc. "DiscID: ..." (Third's
  comment) is deliberately NOT a disc number. A right picture on the wrong disc beats an
  invented order.
- **Never replaces CD art**: the route refuses an album with deadwax's own `disc*`, and the
  writer only writes names matching `disc\d*.(jpg|png|...)`, re-checking containment.
- **`disc_art` is in the scan (SCAN_FORMAT 4)** - listed from the directory the scan already
  reads, no file opened. `/library/disc_art` serves only names that count as disc art.
- **Not built: replacing or stripping embedded pictures.** That is the other real fix, and
  "embedding art" is still on the deliberately-not-built list - it writes into every audio file.
  The Navidrome settings in the README are the no-deadwax-change way to have songs always show
  the cover.
- **Verified in the real page** on the scratch library, with the live Archive: Dummy got
  `disc.jpg`; In Rainbows got `disc1.jpg` and `disc2.jpg` from its "CD1"/"CD2" comments; an album
  with only a `cd.jpg` scan and nothing on the Archive said so and pointed at fanart.tv; a track
  with Third's cover embedded showed "Front cover, 500 x 500", one with a disc scan "Media (the
  disc itself)".

### Lyrics (v0.7.0)

James: "I want to work on also grabbing lyrics" - and chose, from options put to him, a `.lrc`
beside each track, fetched as albums are filed, on demand from the library, and shown in the
track view.

- **LRCLIB, and only LRCLIB.** Free, no key, no account, and the only source with SYNCED lyrics
  at any scale. It is keyed on the tags - artist, title, album, duration - not on MusicBrainz ids,
  so an untagged library works too. It asks for a User-Agent naming the app, version and
  homepage, which `LrclibClient.user_agent()` sends.
- **A `.lrc` beside the track, never a tag inside it.** The audio is not touched, and Navidrome's
  `LyricsPriority` default (".ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded" - verified in its
  source) finds `<same name>.lrc` with no configuration, the way `artist.*` is found. What is
  written is LRCLIB's text untouched - synced when it has timings, plain otherwise - with NO
  header: an `[ar:]` line a player doesn't understand would be drawn as a lyric.
- **The DURATION is what keeps a match honest.** `/api/get` first (exact, LRCLIB's own ±2s);
  on a miss, `/api/search` held to the same 2s by `choose_result()`, with the album as a
  preference and never a requirement - a deluxe edition's longer album title is the usual reason
  the exact lookup misses. The track artist is tried before the album artist.
- **Near misses give WORDS, not timings.** A same-titled recording within 10%
  (`WORDS_ONLY_TOLERANCE`) is used as plain lyrics. Found on the scratch library: Dummy's 2014
  vinyl "Sour Times" is 245s where every LRCLIB copy is 247-254s, so the 2s rule refused all of
  them - right about the timings, wrong about the words. 10% keeps a live take or an extended
  mix, which can have different words, out.
- **Outcomes are kept apart, as with covers.** `missing` and `instrumental` are facts about the
  track; `failed` is LRCLIB not answering and is worth another go; `untagged` needs a title and
  artist first; `kept` already had a `.lrc`. An instrumental writes NOTHING - an invented
  "instrumental" line would be a lyric nobody sang. The price: an all-instrumental album is
  offered by the bulk run every time, and asks LRCLIB again.
- **LRCLIB answers 503 when leaned on** - measured, on a 118-track bulk run at three tracks at a
  time, and it looked exactly like lyrics being missing until the misses were probed by hand and
  most turned out to exist. So `CONCURRENCY` is 2 and the client waits and retries a 503/429
  (`RETRY_PAUSES`) before calling it a failure.
- **Filing fetches in a TASK, not an await** (`poller._fetch_lyrics_later`), held in a set
  because asyncio keeps only a weak reference to a task. The job is already organized; making
  the poller wait on LRCLIB would stall every other download's progress. Only reached for a job
  that really was organized, so dry run fetches nothing. `FETCH_LYRICS` (on | off, default on)
  gates it, and an unrecognised value counts as on - the settings row says so.
- **The scan counts `.lrc` files from the listing it already has** (`lyrics_count`,
  `SCAN_FORMAT` 3). It never opens a file for this, so lyrics another tool EMBEDDED aren't
  counted - which at worst offers to fetch a `.lrc` for an album that has words already. The
  track view does read embedded lyrics, as a fallback behind the `.lrc`.
- **The bulk run takes albums with NO lyrics, not albums missing some.** Otherwise one
  instrumental track keeps an album in the bulk run for ever. A partly-covered album is finished
  from its own Get lyrics button, which looks up only the tracks still without.
- **The album button keeps its result on screen** ("Lyrics · 9 of 10", the whole outcome in its
  tooltip) for as long as you stay on that album. Without it the button either vanished (all
  found) or came back looking untouched (some not on LRCLIB), and both read as the click having
  done nothing.
- **A track's own `.lrc` is left out of the delete confirmation's "other files".** That list
  exists to warn about a rip log that might be the only copy; thirty `.lrc`s would bury it. A
  `.lrc` with no track of its name is still listed.
- **Re-filing needs nothing**: `execute_retag` moves the whole folder, so each `.lrc` travels
  with its track. The hand tag editor renames nothing. If anything ever renames a TRACK file, it
  has to rename that track's `.lrc` too.
- **Verified against live LRCLIB** on the scratch library: Dummy's ten tracks all synced; after
  the retry and the words-only rule, every gap on the Portishead albums filled, and Boards of
  Canada's eleven instrumentals came back as instrumental rather than missing.

#### The lead (v0.7.1)

James, in Amperfy: "the lyrics I'm seeing are the lyrics from the line that was just sung" - and
"it varies, it's not always exactly one line", on Five Finger Death Punch's "American
Capitalist".

- **It was the DATA, and slightly.** Checked before touching anything: deadwax writes LRCLIB's
  text untouched; Navidrome's LRC parser reads LRCLIB's format exactly right (`model/
  lyrics_lrc.go` - trims the space after the stamp, `.37` is 370ms, keeps empty break lines);
  Amperfy picks the current line correctly and refreshes it ten times a second
  (`LyricsView.scroll(toTime:)`, `updateLyricsTimeInterval` 0.1s). And LRCLIB's twenty entries
  for that song agree to 0.16s. What's left is that LRCLIB is tapped along by people and lands
  a moment late - invisible on most songs, a whole line on one whose lines are under a second
  apart ("I'm a red blooded" 25.10, "Rough neck" 26.56, "Son of a bitch" 27.47). "It varies" is
  the tell: a fixed late offset, not an off-by-one.
- **`LYRICS_LEAD_MS`, global, default 0** (asked for as global). Moves every synced timestamp
  earlier as the file is written; negative moves them later; plain lyrics are untouched; held at
  zero at the start of the song; each stamp keeps its own precision. Validated as a whole number
  within 5000 either way, which is what catches seconds typed where milliseconds were meant.
- **Into the TIMESTAMPS, never an `[offset:]` tag.** Amperfy parses the OpenSubsonic `offset`
  and never applies it (it appears only in `SsLyricsParserDelegate`), and a player that did
  apply it on top of shifted stamps would move them twice.
- **Re-timing is stateless, and that is the design, not a shortcut.** Nothing records which lead
  a file was written at. `timing_delta()` asks whether the file is an LRCLIB entry's words with
  every timed line moved by ONE constant, and that constant is the lead it was written at - 0
  for 0.7.0's files, which recorded nothing either. Anything else - a line retimed by hand,
  different words, another source - is `custom` and left alone. So re-timing is idempotent
  (`unchanged` on a second run), moves from the old lead rather than on top of it, and can't
  touch a file deadwax didn't write. A hash table was considered and rejected: it would know
  nothing about 0.7.0's files, which are exactly the ones that need re-timing.
- **It matches against EVERY LRCLIB entry for the song, not just today's best.** Which entry
  `/api/get` answers with changes as entries are added: "Wandering Star" was written from one
  and answered with another an hour later, and was wrongly left alone. `candidates()` yields the
  exact entry and then the search's, in batches, and `_find_source()` stops at the first match -
  one request a track in the usual case, because two a track across a library is what makes
  LRCLIB answer 503.
- **Blank untimed lines are verse gaps, not "unsynced".** LRCLIB writes them into synced lyrics;
  counting them made every song with verses look hand-edited. `_timed()` drops them before
  comparing; a line with WORDS and no stamp still fails the test.
- **The re-time button lives in the settings tab, beside the lead** - that is the moment it is
  wanted - and is refused while the lead has an unsaved edit, since it re-times to the SAVED
  value. It walks the library album by album through `/library/lyrics/fetch?retime`, like the
  bulk covers. **It reads a REAL scan, not the snapshot**: writing a `.lrc` forgets that album
  from the saved scan, so a snapshot after an earlier run is missing exactly the albums that run
  touched - measured, 87 tracks of 104 on a second run.
- **Verified** in the real page on the scratch library: a 300ms lead re-timed 102 files written
  by 0.7.0 ("Roads" 50.30 -> 50.00), then both "Wandering Star"s once matching used every entry;
  a file edited by hand stayed byte-for-byte; a second and third run changed nothing and covered
  all 105; "abc" was refused on save. **Not verified: that 300 is the right number** for
  Amperfy - the tap test (tap a line, see whether it lands mid-word) is how to find out.

### The phone player (spiked at 0.8.0, ported in 1.0.3)

James: "mimic apple music, with a native ios player, but integrate jimbrainz and navidrome" - as a
web app, because an App Store app needs the paid developer programme. Built as a SPIKE on 0.7.2
(`player-spike-0.8`, `5f6711e`), then ported onto 1.0.2 as 1.0.3 - step 1 of the multi-user plan,
single-user, ahead of a week of real use on James's iPhone (plain http over WireGuard, Navidrome
0.64.2). The question it exists to answer is whether an iPhone home-screen web app plays well
enough, and the parts that answer it are the ones not yet verified (see the end of this section).
The user guide's page is `docs/player.md`.

- **deadwax holds the Navidrome login; the page never sees it.** Subsonic signs every request
  with md5(password + salt), so a page that can sign requests holds the account. Keeping it
  server-side also removes CORS (different origins) and mixed content (deadwax on HTTPS asking a
  phone to fetch audio from Navidrome on HTTP, which Safari refuses) in the same move. The phone
  only ever needs to reach deadwax.
- **A FIXED list of calls, never a general proxy.** `routes/navidrome.py` is one route per
  Subsonic call with its own parameters: status (ping), albums (getAlbumList2), one album,
  cover, stream, scrobble - and since 2.0.0-player.13 search (search3), for the app's Search tab:
  it only reads the library, every parameter declared and bounded (artistCount and albumCount at
  most 50, songCount 500, offsets from 0, q at most 200 characters; anything undeclared is never
  passed on) - and since 2.0.0-player.14 scrub, the turntable's window of a song: cut from
  deadwax's own MP4 cache, `at`, `seconds` and `max_rate` only and bounded, Navidrome asked nothing but the
  version check every MP4 answer makes (see "The turntable, part two"). The configured account MAY
  be Navidrome's admin and deadwax has no login, so a catch-all would hand out user management to
  anyone on the network - though the docs and the settings tab now say to use a non-admin account
  of your own: none of the eight calls
  needs admin, nor does `getScanStatus` (only `startScan` is adminOnly, server/subsonic/api.go).
  `test_there_is_no_general_proxy` pins the list - adding a call means changing that test on
  purpose. The login is laid over the params LAST, so nothing sent can stand in for it.
  `getScanStatus` (the rename wait, below) goes through the client's plain `call()` and is NOT a
  player route; keep it that way, and don't put an endpoint allowlist inside `call()`.
- **Subsonic reports a failed BINARY call as a 200 with a JSON body.** `NavidromeClient.open()`
  reads a JSON/XML answer to stream or getCoverArt as the error it is; passed on, it would be
  handed to the audio element as a "song" and surface as an undiagnosable decode error. Since
  1.0.3 it is stricter still - see "Ported onto 1.0".
- **Byte ranges are the whole game for audio.** Safari asks for bytes 0-1 before playing anything
  and gives up on a server that answers with the whole file, so `Range` is passed through and
  the 206, Content-Range and Accept-Ranges come back. **Through the real app that was false until
  1.0.3's gzip exemption** (below): the spike's tests mounted the router on a bare FastAPI, and
  CompressText was compressing every range. `aiter_raw()`, not `aiter_bytes()`, so the bytes and
  the Content-Length passed on describe the same thing. **httpx reads a plain `content=` response
  body the moment it is built**, which made `aiter_raw()` raise StreamConsumed in tests while
  working against a network - the tests use an `AsyncByteStream` body (`Streamed`) for exactly
  that reason; don't "fix" it by switching to `aiter_bytes()`.
- **The file as it is is asked for BY NAME, `format=raw`** (1.0.3; the spike sent no format). It
  is the only kind Navidrome can serve ranges of, and Navidrome's `ResolveRequest` answers `raw`
  before it consults anything set for the player (core/stream/legacy_client.go). With NO format,
  a transcoding or a Max Bit Rate on Navidrome's Players page applies to every stream - a bit
  rate alone forces the default downsampling format, Opus - and an uncached transcode goes out
  with `Accept-Ranges: none` and no Content-Length (core/stream/media_streamer.go). A transcode
  (`format=mp3`) is asked for only when `canPlayType()` says the browser can't play the file.
- **The spike's advice to set a mobile bitrate on Navidrome's Players page was WRONG, and is gone**
  from the README, this file and the code comment. The `deadwax` entry there is ONE row for every
  browser using the player: Navidrome matches a player on client, user agent and user, and every
  request comes from the deadwax container, so it can't tell Wi-Fi from mobile data. With
  `format=raw` the page's playable files never reach it; for the rest, a transcoding set there
  still REPLACES the page's explicit `format=mp3` (`applyServerOverride`) and could hand an
  iPhone Opus, which Safari can't stream. Leave that player's transcoding and max bit rate unset.
  If a mobile bitrate is ever wanted, the page has to ask for it itself (`format=mp3&maxBitRate=N`
  - the route already takes `max_bitrate`), with the no-ranges-on-first-play cost stated.
- **ONE audio element for the life of the page** (`usePlayer.ts`). iOS unlocks audio per ELEMENT
  from a tap, so the next song on a locked phone is the same element given a new `src` from the
  `ended` handler. A fresh element per song would have been started by nobody. And `play()` is
  called in the same turn as the tap - an `await` in between loses the gesture. The same goes for
  a song that fails: it is asked for again, then skipped, on that element from its `error`
  handler (see "After review (1.0.3)"), never left for the lock screen's next and then play.
  The gapless switch (off by default; since 2.0.0-player.10 a checkbox in You > Playback) adds
  exactly one more, unlocked by the same tap - see "Gapless (experimental, 1.1.0-player.2)"; with
  it off this is still the whole story.
- **No `seekbackward`/`seekforward` Media Session handlers, deliberately.** iOS shows EITHER
  track buttons or ±10s buttons on the lock screen, and setting those two replaces
  previous/next. Only play, pause, previoustrack, nexttrack and seekto are set.
- **Position is not React state.** It changes several times a second; `usePosition()` subscribes
  only the scrubber and the mini player's hairline, so the album grid doesn't re-render at 4 Hz.
  From a seek until 'seeked' it reports the seek's target - see "Seeking (1.1.0-player.2)".
- **A play counts on LISTENING, not position** (`lib/playQueue.ts`, pinned by
  `playqueue.sim.cjs`): Last.fm's rule (>30s long, heard for half or 4 minutes), with seeks
  adding nothing - skipping to the last second is not a play. How a step of listening is judged
  changed in 1.0.3 (below). "Now playing" (`submission=false`) goes when playback actually
  starts. "Previous" restarts past 3 seconds - and since the review a restart, or play on an
  ended song, is a new listen that can count again, dated from its first `playing` (`Listen`).
- **The album is in the hash** (`#/album/<id>`; since 2.0.0-player.9 `#/<tab>/album/<id>`, the old
  form rewritten to the Library's - see "The one app") so history and the back button work.
  Whether iOS's edge swipe goes back in a HOME-SCREEN app is unverified - standalone web apps have
  historically had none. The library stays mounted (hidden) under an open album, so pages loaded and scroll
  position survive; the scroll is saved and restored by hand because it is document scroll (kept
  for the status-bar tap-to-top, which a scroll container would lose). A retag that changes the
  release id changes Navidrome's album id, so a saved `#/album/<id>` then answers "nothing by that
  id" (code 70, a 404).
- **Its own stylesheet and scale** (`interface/player/player.css`): iOS's text styles (17px body,
  34px large title), iOS's dark palette, the phone's own face (SF), and theme.css imported only
  for the brand purple, the motion curves and the reduced-motion switch. Same rule as theme.css -
  every value a token at the top. **The look was re-pointed in 2.0.0-player.9** to theme.css
  section 10 (STYLE.md: Noto Sans, 3/4/6px corners, no blur); the scale and the mechanics stayed -
  see "The one app".
- **A new app icon** (`interface/player/icon*.png`, drawn as `icon.svg` and rasterised with
  `sips`, which reads SVG): a record with the dead wax ring picked out in purple. The favicon in
  `interface/assets/icon.svg` is still LidBrainz's, inherited; the player doesn't use it.
- **No service worker, on purpose, for now.** It is what offline would need, but a caching
  service worker is also the most reliable way to ship "I upgraded and nothing changed" - the
  bug the revalidate middleware exists to prevent. `/player/` is in `REVALIDATE_PREFIXES`. Nor
  does anything in the player need HTTPS, which is why plain http over WireGuard is the
  deployment - but whether iOS gives a plain-http home-screen app the Media Session is unverified.
- **Verified on the spike, at 0.7.2** (the settings page then had no tabs), in the browser pane at
  375px against `scratchpad/subsonic_stub.py`, a stand-in Navidrome over a scratch library that
  CHECKS token auth (so a wrong salt or md5 would fail there): covers and albums through deadwax;
  tapping a track streams it as 206 ranges; the Media Session metadata, artwork URL and
  playbackState; the SAME element moving to the next song by itself on `ended`; now-playing and
  played scrobbles (the latter only after half the song was heard at 4x speed, and not after a
  seek to the end); previous restarting then going back; pause shrinking the art; drag-down
  closing the sheet; library scroll restored exactly (420px); the unreachable-Navidrome screen;
  the password masked in settings; the main page still mounting from the two-entry build.
- **NOT verified, and they are the point of the spike:** anything on a real iPhone. (Since then
  James has used it on his for a week, on 1.1.0-player.1, and reports it plays locked and moves to
  the next song by itself while locked, with a pause of about a second at every change - which
  is what the gapless switch below is for.) Background
  playback with the screen locked, the next song starting while locked, the lock-screen
  controls, AirPlay, Add to Home Screen and the home-screen app over plain http, the safe areas
  (landscape included), the sheet gesture under a real finger, and whether the 1.5s retry of a
  song that failed fires on a locked phone, where nothing plays while it waits. The iOS
  Simulator was tried and removed, since the 8 GB Mac can't run it; iOS testing happens on
  James's iPhone. Nor has it met a real Navidrome: the stubs answer the way Navidrome's source
  says it does (read at 46c4327, a shallow clone of 2026-09-26 not confirmed line for line
  against 0.64.2), which is what the slskd stub did too before the first real slskd refused its
  first search.
- **Known gaps:** gapless playback (web audio on iOS gaps between tracks - the experimental switch
  below narrows it, unverified on the phone), CarPlay (impossible
  for a web app), offline, the queue surviving iOS killing the app, search, a mobile bitrate, a
  landscape layout for the now-playing sheet (the cover only shrinks to fit), and anything that
  reaches the REST of deadwax (search MusicBrainz and download from the phone - the integration
  the idea was actually about). Filing an album needs no rescan call: Navidrome's
  watcher picks it up about 5s after it lands (scheduled scans are off by default), and
  `startScan` is adminOnly (server/subsonic/api.go) and deliberately not used.

#### Ported onto 1.0 (1.0.3)

The port was driven by an audit of the merged spike, and most of what it found was invisible to
the spike's tests because they never went through the real app. What changed, and why:

- **Settings: three rows in the `connections` group**, which `tabForGroup` (SettingsView.tsx)
  puts on the Connections tab - an unknown group id would land on Library. `NAVIDROME_URL` is
  checked by `describe_navidrome_url()` (config.py): everything `describe_slskd_url()` refuses,
  plus a user name or password in it, a `?` or `#`, a space, a port that isn't a number, or no
  host. A PATH is allowed (a base path, a proxy's subpath). Only a URL change drops the client;
  the user and password are signed into each request's token, so nothing needs rebuilding.
  `Config.report_navidrome()` says at start-up which of the three is missing, what's wrong with
  the URL, or where it came from - never the password. It has to run from the lifespan AFTER the
  overrides, beside `report_musicbrainz()`, for that one's reason: from `check()`, a Navidrome
  set up in the tab was logged as off on every restart. **Two things this bullet used to claim
  were false until the review** (see "After review (1.0.3)"): a refused URL was NOT kept out of
  the messages - a scheme-less one went through `describe_slskd_url()`'s "use http://<value>",
  `me:pw@navidrome` and all - and "the player can't reach Navidrome" was untrue of an
  ENVIRONMENT value, which never meets the settings tab's check and was used anyway. Now
  `describe_navidrome_url()` judges the scheme itself and quotes nothing, `get_client` refuses an
  address that fails it (a 503 from `unusable_url()` naming the reason; nothing is sent), and
  `navidrome_usable()` - all three set AND that check passing - is what the apply and the
  `RETAG_RENAME_WAIT` row go by. Error text quoting the address goes through `without_login()`.
  (Since 1.0.5 the slskd and Navidrome checks are one, `_describe_address()`, and `without_login()`
  lives in config.py.)
- **A new NAVIDROME_URL takes the password again, in the same save**
  (`_navidrome_moved_without_password`, settings.py). The audit re-pointed `NAVIDROME_URL` with
  curl - a write with no Origin passes SameOriginWrites by design - and the next status call sent
  its listener a `t`/`s` pair, which Navidrome accepts for as long as the password stands (it
  never tracks salts). With `?x=` in the URL deadwax also fetched any path on that host and
  relayed the body as a cover. So: refused unless the batch carries a non-empty
  `NAVIDROME_PASSWORD`; saving the same address, clearing, reverting (the environment's address
  is the admin's) and "no password set yet" are allowed. The password row shows the reason in red
  while the URL holds an unsaved new address. ~~`SLSKD_URL` has the same shape and is NOT
  fixed~~ **Fixed in 1.0.5** - see "slskd's address takes the key again" under "The settings tab".
- **Audio and covers are never gzipped** (`serves_media()` in app.py, shared by CompressText and
  GuardMedia, plus `CompressText.BINARY` = fonts and `/player/icon-`). GZipMiddleware compresses
  any STREAMED body whatever `minimum_size` says and drops its Content-Length, so Safari's 2-byte
  probe came back as a gzipped 206 with no length, and a seek as a gzip body under a Content-Range
  counting uncompressed bytes. The library's picture routes are matched EXACTLY now
  (`MEDIA_PATHS`): as a prefix, `/deadwax/library/art` also caught every `/deadwax/library/artist*`
  route, whose JSON is gzipped since. `icon.svg`, `player.css` and `/player/` itself still are
  gzipped. `manifest.json` is NOT exempt either, but at 422 bytes it is under GZipMiddleware's
  `minimum_size` (1024), so it goes out plain (a 1.0.3 note here said otherwise; measured in the
  review).
- **The Navidrome login was in the container log, and is not any more.** httpx logs every request
  at INFO with its full URL - `u`, `t` and `s` included - and the root logger is at INFO, so each
  cover, range and scrobble wrote a replayable credential to what Komodo shows. `src/logger.py`
  sets `httpx` and `httpcore` to WARNING at MODULE level (not in `setup_logging()`, which is
  skipped when something already gave the root logger a handler). That also closed fanart.tv's
  `api_key` leaking the same way since v0.6.15. It never reached the page's log (SSEHandler only
  forwards `frontend` records). `test_the_login_never_reaches_the_container_log` first proves it
  can see httpx's line with httpx at INFO, so it can't pass by looking in the wrong place.
- **Media goes out only as media, and never as a page** (`COVER_TYPES`/`audio_type` in
  routes/navidrome.py; `GuardMedia` in app.py; the library's picture routes too). A Soulseek
  peer's audio file can carry an embedded "picture" that is really HTML; Navidrome sets no type
  on a cover (Go sniffs one) and serves bytes it can't decode as they are, and
  `/library/tracks/picture` and `/library/art` served the file's own MIME field. Either way that
  was `text/html` from deadwax's origin, where a script has everything SameOriginWrites trusts.
  Covers go out only as jpeg/png/gif/webp/avif/bmp (never SVG), streams only as `audio/*` or
  `application/ogg`, library pictures as jpeg/png/gif/webp/bmp (identified from the bytes where
  the label lies), anything else as `application/octet-stream`. `GuardMedia` adds
  `X-Content-Type-Options: nosniff`, `Content-Security-Policy: default-src 'none'; sandbox` and
  `Cross-Origin-Resource-Policy: same-origin` to every media answer, errors included - so no other
  website can embed deadwax's covers or audio either. `open()` passes on only a 200, 206 or 304
  that isn't text/JSON/XML; a proxy's login page, a redirect or a proxy's 401 becomes a 502 asking
  "is NAVIDROME_URL the address of Navidrome itself?", a plain 404 stays a 404, a 5xx says
  "Navidrome answered N", a 416 carries `Content-Range: bytes */N`, and Navidrome 0.64's
  transcode limit is a 429 with its `Retry-After`. That limit is off unless configured
  (`transcoding.maxconcurrent` and `maxconcurrentperuser` default to 0), and the phone never sees
  the 429's words: the audio element reads no body, so it lands as MEDIA_ERR_SRC_NOT_SUPPORTED -
  "Couldn't play this song", then the retry and the skip.
- **Covers are cached as Navidrome says** - `no-store` for a placeholder (what it serves before an
  album's art is resolved, which the spike's fixed day pinned on the phone), a year and
  `immutable` for an id carrying the picture's hash, `public, no-cache` otherwise - with the fixed
  day (`COVER_CACHE`) only when it sent none. `If-None-Match`/`If-Modified-Since` are forwarded,
  so a cover the phone holds is a 304 with no body.
- **Streams are `Cache-Control: no-cache`** and forward `Range`, `If-Range`, `If-None-Match` and
  `If-Modified-Since`: a retag rewrites a file in place under the same URL, and `If-Range` is what
  stops a resumed range splicing two versions of it.
- **`estimateContentLength=true` whenever the format isn't `raw`** (no format included, since the
  Players page can still turn that into a transcode). Without it an uncached transcode has no
  Content-Length at all. With it the length is Navidrome's ESTIMATE, and the transcode usually
  ends a little short - so `Relayed` (routes/navidrome.py) leaves the answer UNFINISHED when the
  upstream stops: h11 refuses to end a body short of its declared length (the spike printed that
  as a traceback), and a closed connection is how the phone learns the body was cut. A transcode
  (`accept-ranges: none` with a declared length) that ends at `TRANSCODE_END_SHARE` (90%) of its
  estimate or more logs one INFO line - the estimate runs a few per cent over for a CBR MP3.
  Anything further short, 0 bytes included (ffmpeg producing nothing, which Navidrome logs as an
  error of its own), and any break in a file with a real length, logs one WARNING. Until the
  review every estimated transcode took the INFO branch whatever it had sent. uvicorn adds its
  own `ERROR: ASGI callable returned without completing response` either way - expected after
  every transcoded song, and troubleshooting.md says so.
- **The page asks the browser about Ogg with its codec** (`playableType()` in player/api.ts):
  Navidrome gives `.ogg`, `.oga` and `.opus` the same `audio/ogg`, so `.opus` is probed as
  `audio/ogg; codecs="opus"` and `.ogg`/`.oga` as Vorbis, the way Navidrome's own web player does.
  `QueueTrack` gained `suffix`. A song with no known type is sent raw - MP3 would be a guess.
- **One song length** (`songLength()` in usePlayer.ts): the element's when finite and above 0,
  else the tags'. A stream with no Content-Length reports `Infinity`, which counted as truthy,
  asked four minutes of listening of every such song and left the lock screen with no scrubber.
- **The listening rule** (`listenedStep`): a forward step counts in full unless the element's own
  `seeking` event fired since the last update (scrubber, lock screen and "previous" seeks all
  count nothing), capped at wall-clock elapsed x playback rate + `LISTEN_SLACK_SECONDS` (0.5) on
  `performance.now()`; a step back adds nothing. The spike took any step of 1.5s or more for a
  seek, which would have counted NOTHING heard while locked if iOS throttles `timeupdate` there.
- **Smaller player fixes**: `Cover` remembers WHICH address failed, not a flag (the mini player
  and the sheet keep one mounted from song to song, and one failure blanked every later cover);
  a page of albums drops any already shown (`appendPage` - the list orders are live, and a
  scrobble moves an album to the front of "Recently played"), while the offset follows the
  server; the IntersectionObserver is re-armed after each page when more remain (a wide window
  stopped at 60); `--pl-safe-left`/`--pl-safe-right` and `--pl-edge-left`/`--pl-edge-right` for
  landscape under `viewport-fit=cover`; and `AlbumPage` and `Library` go through `latestOnly()`,
  with `get()` in http.ts taking a `signal`, so leaving an album or changing order aborts its
  request.
- **Two build entries** (`deadwax-ui`, `deadwax-player`; see docs/FRONTEND-MIGRATION.md). The
  shared chunk lives in `interface/dist/assets/`. The local rolldown workaround doesn't empty the
  folder the way vite's `emptyOutDir` does, so old hashed chunks pile up - harmless, and
  `rm -rf interface/dist` first keeps it tidy.
- **Tests through the real app.** `tests/test_navidrome.py`'s client is `TestClient(start())`
  without its lifespan (nothing connects), with the fake Navidrome injected into the module's
  client - so CompressText, GuardMedia and SameOriginWrites are all in the path.
  `test_media_headers.py` pins exactly which routes get the three headers,
  `test_navidrome_settings.py` drives the settings route through `start()`,
  `test_picture_types.py` the library's picture types, `test_scan_wait.py` the wait's rules, and
  `test_two_step_apply.py` the wait end to end with a fake Navidrome in the real client.
- **Not done:** HEAD on stream and cover answers 404 from the static mount (a GET route registers
  GET only, and the `/` mount is a full match). AVFoundation probes with a GET range, so it
  probably doesn't bite; don't misread it on the phone. And the server still passes "no format"
  on as none rather than treating it as `raw` - the page never sends none.

#### The scan wait (1.0.3)

1.0.1's two-step apply slept a fixed `RETAG_RENAME_WAIT` between the tags and the rename (see
"The 1.0.1 fixes"). With the Navidrome connection there to ask, the route now asks instead:
`getScanStatus`, which any account may call. `src/scan_wait.py` is the pure half (what one
answer says, and when the answers prove a scan happened); `_pause_before_rename` and
`_wait_for_navidrome_scan` in routes/library.py do the asking. From Navidrome's source
(scanner/controller.go, scanner.go, watcher.go):

- **`lastScan` moves only when a scan SUCCEEDS** - writing it is a scan's last step - and for
  every kind, the watcher's selective scans included. `scanning` is one flag for the process, and
  only one scan runs at a time.
- **Waiting for `scanning` to be false is NOT enough.** The watcher waits 5s after a change before
  it scans, so straight after the write nothing is running, and renaming then lands the rename in
  the very scan the two steps exist to avoid. So the wait is for `lastScan` to move past a
  baseline taken after the write.
- **The baseline is TWO reads** (`begin()`): Navidrome reads `lastScan` before the running flag
  when it answers, so a scan that began before the write and ended between the two reads would
  answer {old lastScan, not scanning} and its end be taken for a new scan. A scan running at the
  baseline is a STRADDLER - it may have read this folder before the write - so its own end proves
  nothing: the wait follows it to its end and then needs one more (`step()`). A `lastScan` going
  backwards can't lower the bar.
- **Seeing a straddler END takes the baseline's care too** (review). `step()` used to clear it on
  {old lastScan, not scanning}, which is a failed scan - or one that ended between Navidrome's
  two reads - so the next poll's {new lastScan} confirmed the rename on the straddler's OWN end:
  `begin(busy T0, busy T0)`, `step(idle T0)`, `step(idle T1)` gave CONFIRMED. Now that answer
  marks it `ending`, and the NEXT readable answer's `lastScan` (max with the old base) becomes the
  base without confirming, as `begin()`'s second read does; only a completion after that counts.
  A straddler seen with `lastScan` already moved goes straight to base = that, as before. The
  window was tiny (a Status goroutine stalled across ScanEnd and release()), but it was the race
  the two-read baseline exists for.
- **Polled every 0.5s** (`SCAN_POLL_SECONDS`), each question bounded at 5s on its own (the
  client's read timeout is a minute, for streams; a question that runs out counts as Navidrome
  unreachable), capped at 90s (`SCAN_WAIT_CAP_SECONDS`, and `SCAN_MAX_POLLS` so a test that makes
  sleeping instant still ends). It should rename about 6-7s after the write (the watcher's 5s and
  a folder's scan): against the stub, which scans 5s after a change as the watcher does, the
  Currents rename landed 6.8s after Apply. Not yet measured against a real Navidrome. Poll speed
  only narrows a window that ends in a hold-back, never a wrong rename; the audit's throwaway
  simulation of 60,000 random scan timelines found no wrong confirmation.
- **Outcomes** (`_wait_for_navidrome_scan`, acted on by `_pause_before_rename`): *scanned* -
  rename at once. *held* (a poll after the baseline was answered usably, and no qualifying scan
  within the cap) - the folder is LEFT where it is: `hold_back_rename()` adds `RENAME_HELD` to the
  problems and `rename_held: true`, and the hold is remembered (below). *unreachable* (review) -
  nothing there at all, at the baseline, or at a poll after it when no poll was answered usably: a
  transport failure (refused, no such host, a dropped connection, httpx's timeouts -
  `NavidromeError.unreachable`, set from `httpx.TransportError` in `unreachable()`) or no answer
  within the 5s bound. It HOLDS as well, with `RENAME_UNREACHABLE` and the log adding that
  Navidrome may be restarting: Navidrome scans on start-up by default (`scanner.scanonstartup`),
  and that scan would see new tags at a new path at once - a Komodo redeploy during an apply
  would do it. 1.0.3 as first written renamed here. *unanswered* (every poll after the baseline
  got an answer that couldn't be used - a refused login, an HTTP error, an unreadable `lastScan`
  - and none found Navidrome gone) - rename at the cap, as the fixed wait would have, and log it.
  *unreadable* (the baseline couldn't be taken, for one of those reasons) - sleep
  `RETAG_RENAME_WAIT`, then rename, and log why. Holding back rather than renaming is a judgement
  call: it costs a second click, and it doesn't hide a scan that never came.
- **A hold is REMEMBERED** (review; `_HELD_RENAMES` in routes/library.py, a `HeldRename` of the
  wait's state and when the id tags were written, keyed on the album's path in the library).
  Without it the hold was advice: afterwards the tags on disk match, so `changes_player_ids` is
  false and the next apply - a second click under the yellow text, or one queued on `_apply_lock`
  during the wait - renamed in one step with no `getScanStatus` at all, and a test pinned it. Now
  `_rename_pause` answers `"navidrome"` for a held album that still moves, and the wait takes its
  two baseline reads and asks `scanned_since_hold()`: a `lastScan` past the held state's base -
  or, with no state (unreachable at the hold), past the moment the tags were written, both being
  one host's clock - renames at once. A straddler unresolved at the hold proves nothing that way,
  so the ordinary wait from here decides (costing at most one more scan); unreachable again at the
  baseline keeps the record it had. An apply writing NEW id tags ignores the hold - they need a
  scan of their own. The record goes when the folder is renamed or an apply no longer moves it.
  In memory only,
  on purpose (a hold lasts until the next scan): a restart forgets holds, and such an album then
  renames in one step, as every apply did before 1.0.3 - as does one applied with Navidrome no
  longer usable or `RETAG_RENAME_WAIT` at 0. The held album's preview has `rename_by: "navidrome"`
  and the editor reads "The tags were written by an earlier apply. Renames the folder once
  Navidrome has scanned them..."; `RENAME_HELD` and `RENAME_UNREACHABLE` both end "deadwax checks
  with Navidrome first, and renames it then". **Residual**: with no state, "past the write" can't
  rule out a scan that began before the write and ended after it - reached only when Navidrome
  didn't answer at the hold.
- **When it runs**: only when the apply changes an id tag AND the folder (or follows up a hold),
  `RETAG_RENAME_WAIT` isn't 0 (0 still means one step, whatever Navidrome says) and
  `Config.navidrome_usable()` - all three set AND a URL `describe_navidrome_url()` accepts, since
  the client refuses any other and asking would only ever fall back (the settings row says so);
  otherwise the fixed sleep as before. The saved scan is still forgotten and persisted before the
  wait, and it is still one apply per album at a time. The preview and results keep `rename_wait`
  (the fixed seconds, or 90 when waiting on Navidrome) and gain `rename_by`: `"navidrome"`,
  `"timer"` (including a fallback) or null. The editor says "renames the folder once Navidrome has scanned
  them (usually a few seconds)" and Apply reads "Applying, waiting for Navidrome", with no
  countdown. It also shows, in yellow, any problem the apply reported that its preview didn't -
  the hold-back, and ones silently dropped before ("appeared while waiting", cover art not saved).
- **What it cannot prove, and the docs say so:** WHICH folders a scan read. A finished scan of
  somewhere else - an admin's targeted scan, or a second library (`lastScan` is the latest across
  all of them) - would count. For one library, where scans come from the watcher (which queued
  this folder when the tags were written, and keeps its targets across retries) or cover
  everything, that is sound. A blind or disabled watcher (a network mount without inotify,
  `WatcherWait` 0, the scanner off) means no scan ever comes, so EVERY such apply is held back -
  the truth, which the fixed wait hid. A scan schedule rescues a blind watcher, never a disabled
  scanner: `ND_SCANNER_ENABLED=false` skips `startScanWatcher` AND `schedulePeriodicScan`
  (cmd/root.go:98-103). A busy library can hold one back too: every change resets the watcher's
  5s debounce.
- **A held-back apply keeps its request open for up to ~100s.** A reverse proxy with a 60s read
  timeout would show an error while the server finishes correctly. James's setup has no proxy.

#### After review (1.0.3)

A review of the port found these, all fixed before it shipped. The scan wait's three - the held
rename forgotten after one click, the straddler's own end, and renaming while Navidrome was down -
are written up in "The scan wait" above.

- **A song that won't play no longer stops the queue** (`afterFailure()` in lib/playQueue.ts,
  `onFailure` in player/usePlayer.ts). The `error` handler only set the error, so the queue sat on
  the broken song; and since an error leaves `audio.paused` true, Next - the lock screen's
  nexttrack too - then loaded the following song PAUSED. On a locked phone, that is next AND play.
  Realistic here: WireGuard dropping at a change of song, a song whose album was re-applied while
  it was queued (its id gone, so a 404 or 502), a failed transcode. Now `state.intendsToPlay`
  decides, not the element: set by play, toggle-to-play, `playTracks`, the lock screen's play and
  the element resuming by itself; cleared by an explicit pause, the end of the queue, a stop after
  a failure, and a pause nobody asked for (a call, headphones out), so a later failure can't
  restart the music. A LOAD failure (MEDIA_ERR_NETWORK, or SRC_NOT_SUPPORTED, which is what any
  refused request looks like from the page) is asked for once more after `LOAD_RETRY_DELAY_MS`
  (1.5s) on the same element, resuming where it stopped. A second failure, or a decode error,
  moves to `nextIndex()` with autoplay as `ended` does, and the next song's line reads `Skipped
  "<title>" - it wouldn't play` (or `- its file couldn't be decoded`) for `SKIP_NOTICE_MS` (5s).
  At the end of the queue it stops, the error on screen and the lock screen paused; with nobody
  meaning it to play it only shows the error. Next and previous autoplay from the flag; play on a
  failed song reloads it. **Chromium sends `pause` AFTER `error`, with the error already set** -
  that is how the pause handler tells a failure's pause from a real one. Whether WebKit orders
  them the same way is unverified.
- **A second listen counts, dated from when it started** (`Listen`, `listenStarted`,
  `listenHeard`). The counters and `startedAt` were reset only in `load()`, so "previous" past 3s
  (a seek to 0) or play on an ended song never counted again, and `startedAt` was the LOAD time -
  Next pressed while paused and played hours later dated the play hours early, and Navidrome
  keeps the `time` it is sent. A restart or play-after-end is a new listen now, and `startedAt` is
  its first `playing`. A restart while playing begins its listen at once, since no `playing`
  follows a seek to a start that is already buffered.
- **The sheet's close arrow closed nothing in Chromium**: the grip took `setPointerCapture` on
  pointerdown, and a captured pointer's click goes to the element holding it, not the button
  inside. The grip captures once the pointer has moved `DRAG_START_PX` (6), and cancels
  `dragstart` - which was a second bug: a mouse drag on the cover started the browser's own image
  drag and cancelled the sheet's.
- **On its side the cover ran over the title and the scrubber** (`min(100%, 420px, 50vh)` square
  in an 85px grip at 667x375), and while paused its transform painted it above the scrubber, so it
  took the scrubber's touches. `.pl-sheet-art` may now shrink in height (`min-height: 0`), the
  cover is as tall as that box and exactly as wide, and the close button keeps its 44px target
  (`flex: none`). The price: the cover is small in landscape (41px at 667x375, about 20px with an
  iPhone's home-bar inset). A cover beside the controls is the real landscape layout, not built.
  A missing cover now shows a grey square in the sheet, and a cover that isn't square is cropped.
- **An environment `NAVIDROME_URL` the check refuses is refused by the client**, and no refusal
  quotes the value - see the settings bullet in "Ported onto 1.0".
- **A transcode that fails is a WARNING** - `TRANSCODE_END_SHARE`, in the same list.
- **The docs**: the README claimed the player says on screen why plays don't count (`scrobble()`
  only `console.warn`s); troubleshooting quoted "Navidrome is busy - try again shortly", which the
  phone never shows, for a limit Navidrome has off by default; "the button counts it down" (it
  names the wait, "Applying, renaming in 20s"); a scan schedule offered as the fix for
  `ND_SCANNER_ENABLED=false`, which turns off any schedule too; and this file's claims about
  `report_navidrome()` quoting nothing and `manifest.json` being gzipped.
- **Not fixed**: `GET /deadwax/settings` still returns `NAVIDROME_URL` as it is (it isn't a secret
  row), so a user name and password typed into an environment address show there. The client
  refuses such an address, so it is only shown, never sent.

#### Verified (1.0.3)

The full suite (1095) and all 12 sims pass, and `npm run typecheck` is clean. By tests:

- Mutation-checked: removing the gzip exemption, putting httpx back at INFO, finishing a cut
  answer, dropping the estimate parameter and dropping the media headers each fail their tests.
- The real app under uvicorn with h11, against a raw-socket fake Navidrome that closes
  connections the way Go does, with `Accept-Encoding: gzip`: `bytes=0-1` gave a 206 of length 2,
  `bytes=1000-` a 206 of length 9240, and a cover came back uncompressed with its length.
- The scan wait's rules in 25 table tests (idle then a finished scan, a straddler seen ending then
  another, the review's straddler sequence, an ending straddler waiting out an unreadable answer,
  a straddler seen with its end already written, a failed scan then an advance, unreadable
  answers, a `lastScan` going backwards, nanosecond and zero times, `scanned_since_hold`), and 26
  route tests with a fake Navidrome in the real client (the normal rename, a straddler, the
  hold-back at the cap; applying again before a scan holds again with `getScanStatus` asked,
  after a scan past the hold renames, and an apply queued on the lock asks too; the held preview,
  the hold cleared when the folder no longer moves or Navidrome is no longer set up; Navidrome
  unreachable at the baseline and after it holds, back and scanned renames, back but not scanned
  holds again, still away keeps the record; failed and unreadable baselines and a refused login
  mean the fixed wait, as does an address the client refuses; a timed-out question holds; answers
  that can't be used rename at the cap; Navidrome not set up, 0 renaming at once, the saved scan
  refreshed first, the previews). The new hold and straddler tests fail against the old code.
- The settings route through `start()`: a URL plus password saved (row written, client dropped and
  closed), a URL change without the password refused, same address / clear / revert allowed, a
  foreign Origin 403'd, 11 bad URLs refused and a base path allowed, the overridden password
  never in the payload, and no refusal quoting a password.
- An environment URL with `user:pass@` in it: `/status` gives the problem and `/albums` a 503,
  both carrying the reason and no password, with nothing requested; the scheme-less message
  quotes nothing; the start-up report for a scheme-less URL; the rename-wait row for an unusable
  address.
- A transcode ending at 0 bytes, 50% and just under 90% of its estimate warns; just over 90% is
  INFO.
- A FLAC whose picture says `text/html`, through both library picture routes.
- `playqueue.sim.cjs`: the listening rule (locked-phone update spacing, seeks, rates, the wall
  clock cap), the stream URL and codec probes, a listen and hearing a song again (13 checks), and
  a song that will not play (13 checks, including a walk through One, Two, Broken, Three).

In the real page, by the orchestrator at 375px against the stub Navidrome, before the review's
fixes:

- The album grid, and covers through deadwax: 200 `image/jpeg`, not gzipped, with a
  Content-Length, and nosniff, the sandbox CSP and same-origin CORP.
- Shuffle started on track 6 of Dummy, streamed as `format=raw` with 206 answers, and the Media
  Session metadata was set.
- No Navidrome URL or token in the server log.
- The metadata editor on a staged untagged rip of Currents previewed "renames the folder once
  Navidrome has scanned them"; Apply wrote the tags, the stub's watcher scanned 5s later, and the
  folder was renamed 6.8s after Apply.
- The settings tab refused a URL change without the password, a URL with a user name and password
  in it, and one with a `?`, each with its sentence; the Connections tab shows the three rows.

In the real `/player/` page (Chromium), by the review's player fixes, against a stub Navidrome
serving an undecodable "Broken" song and a "Flaky" one that fails once:

- Two ended into Broken, which was asked for again and then passed over, and Three played by
  itself. Flaky failed once and played on the retry. Next during the retry's wait played the next
  song with no late retry; play during the wait retried at once; a broken last song stopped the
  queue.
- In the stub's scrobble log: a song loaded while paused and played 5s later was dated at the
  play, not the load; a restart gave a second submission, and so did play on an ended song.
- The sheet: a click on the arrow closes it; a 200px drag from the cover or from the arrow closes
  it; a 60px drag springs back.
- Portrait unchanged to 0.1px at 375x812 (playing and paused), 375x667, 430x932 and 768x1024; at
  667x375 and 844x390 the cover no longer reaches the title or the scrubber, and the scrubber
  takes touches while paused.
- Not exercised: resuming a song that dropped part-way (the stub can't cut a stream mid-song).

#### Gapless (experimental, 1.1.0-player.2)

(Since 2.0.0-player.10 the switch below is a checkbox in You > Playback, and the readouts are
Info > Debug's rows, off the now-playing sheet: see "Now Playing as designed, with Info". The
engine it describes is unchanged.)

James, after a week on the iPhone: the player works, locked included, "except for a pause between
songs" - about a second on EVERY change, even between two songs both played before, so it is not a
first-load cost. It is the one-element design's own cost: on `ended` the element gets a new `src`,
and Safari asks for bytes 0-1 and then the rest - two round trips over WireGuard, through deadwax to
Navidrome - before AVFoundation starts from nothing. A research pass read WebKit's source (main, and
the Safari 17.4/18/18.5 branches) for what iOS allows, and the switch is built on what it found. The
guide's section is `docs/player.md#gapless-playback-experimental`.

- **Off by default, and off is the old player exactly.** `deadwax-player-gapless` ('on' or 'off',
  `readPlayerGapless` in persisted.ts) is the player's own, like its order: a home-screen app keeps
  its storage apart from Safari's, so a switch in the settings tab would never reach it. With it off
  no second element is made, `live()` is always the first, `handOver()` answers "off" and the song
  change is `load()` as it was. The only new work is timing the change for the readout. **The
  one-element rule still holds with the switch off**, and it isn't broken with it on either: the
  second element is unlocked by a tap too, and there are only ever those two.
- **Two elements that swap roles** (`usePlayer.ts`; the rules in `lib/gapless.ts`, pinned by
  `ui/test/gapless.sim.cjs`). The second is made by the switch (or at start, when it was left on). It
  is put through `load()` in the first tap that plays - `playTracks`, `toggle`, `next`, `previous` -
  or in the switch's own tap (`unlockSpare`, once), BEFORE the playing element's `play()`. A few
  seconds into each song (`PRELOAD_DELAY_MS`, 3s after `playing`) the STANDBY is given the next
  song, muted. On `ended`, `handOver()` swaps `state.active` (`activeAfter()`), mutes the outgoing,
  unmutes the incoming, calls `play()` on it in the same turn, and then `empty()`s the outgoing
  (`removeAttribute('src')` + `load()`, its blob handed back), which becomes the next standby.
  "Next" hands over the same way when the standby holds the next song and the music is playing.
- **The WebKit facts it rests on** (HTMLMediaElement.cpp, MediaElementSession.cpp, Document.cpp):
  - `<audio>` has no restrictions on iOS (MediaSessionManagerIOS `resetRestrictions()`; WebKit's own
    iOS expectation has `mediaSessionRestrictions["audio"] = ""`), and an element unlocked by a tap
    stays unlocked: `removeBehaviorRestrictionsAfterFirstUserGesture()` runs from `prepareForLoad()`
    - which `load()` and a `src` change both call - whenever `processingUserGestureForMedia()`. So
    `load()` in the tap is the unlock, with no play-then-pause blip.
  - An element unlocked by a tap that fires `ended` starts a one-second grace
    (`userActivatedMediaFinishedPlaying`; `maxIntervalForUserGestureForwardingAfterMediaFinishesPlaying
    { 1_s }`), in which the document counts as handling a tap. So `play()` on the standby from the
    `ended` handler is allowed twice over.
  - **Why the standby is MUTED.** The lock screen's Now Playing is elected by
    `preferMediaControlsForCandidateSessionOverOtherCandidateSession` - main content first, then the
    most recent user interaction, and NOT whether the element is playing - and
    `removeBehaviorRestriction(RequireUserGestureToControlControlsManager)` re-stamps
    `m_mostRecentUserInteractionTime` on every gesture-time load or play, the grace second included.
    Emptying the outgoing inside that second would stamp it newer than the song playing. A muted
    element is never a candidate (`canShowControlsManager()` returns false for `muted()`), so a muted
    standby can't take the lock screen whatever its stamp. At most one element is ever unmuted: the
    outgoing is muted before the incoming is unmuted, in the refusal path too.
  - **Why the next song goes into MEMORY.** iOS preloads before `play()` only after a tap, and only
    from Safari 18.5 (292087@main removed `AutoPreloadingNotPermitted` with the first gesture;
    cherry-picked to safari-7621, 18.5); and a paused element in a hidden document - a locked phone -
    gets `MakeResourcesPurgeable` (`MediaElementSession::preferredBufferingPolicy`), so what it
    buffered may be thrown away. A `blob:` copy is there whatever iOS does, and costs no trip.
  - Timers in a hidden page are aligned to a second (`DOMTimer::hiddenPageAlignmentInterval`) and
    `timeupdate` comes every ~250ms, so the handover is on `ended`, never a timer just before the end
    (Feishin plays the next track 65ms early and has two tracks playing at once after a wake, #2290).
- **What goes into memory** (`memoryPlan`): a file asked for as it is (`streamFormat()` 'raw'), typed
  `audio/*` or `application/ogg`, no bigger than `MEMORY_MAX_BYTES` (64 MiB: ten minutes of CD FLAC,
  few hi-res files) - a size not declared is counted as it arrives (`overMemoryMax`). Two are held at
  the peak, the song playing and the next. Anything else hands the standby the ADDRESS (stage
  'stream'), to buffer as iOS allows. A transcode is left out because its length is Navidrome's
  estimate and it may end short - and, since the review, is never FETCHED ahead either:
  `download()` sees `streamFormat()` isn't 'raw' before asking and goes straight to the address.
  (It used to fetch, start a transcode on Navidrome, read the headers, abandon it, and have the
  standby start a second.) iOS reloads a page that uses too much memory, which stops the music.
- **Nothing is got ready while AirPlaying** (review): `standbyPlan(..., wireless)` answers `none` or
  `clear` then, so `preloadSoon`/`preloadNow` do nothing, `download()` lets the standby go if AirPlay
  began while it waited (`wanted()`, after every await), and `webkitcurrentplaybacktargetiswirelesschanged`
  on the playing element re-fits the standby (dropped when AirPlay starts, got ready again 3s after
  it stops). It used to get every next song ready by address anyway, which `handoverDecision` then
  never used: each song asked for three times, a Navidrome transcode each for songs that need one.
  That also means a speaker is never handed a `blob:` it can't fetch, so `memoryPlan` lost its own
  AirPlay rule.
- **When it can't hand over, the one-element way** (`handoverDecision`): the switch off; "next" while
  paused; AirPlay (`webkitCurrentPlaybackTargetIsWireless` - AirPlay keeps the one element it has
  always worked with); nothing ready; another song ready (index AND id are compared, so a new album
  at the same position isn't handed over to); the standby's own `error` ("failed to get ready").
  **A standby still DOWNLOADING exactly the next song hands over BY ADDRESS** (source `'unfinished'`,
  review): `handOver` aborts the download, gives the standby `streamUrl` and plays it, as stage
  'stream' does - one fresh request, what the one-element way costs. It used to go the one-element way,
  which aborted the download (`fitStandby` then wanted the song after) and asked for the song again on
  the live element: the same gap, with part of every song sent twice. On a link where a whole song
  can't download while the one before plays, the switch still sends part of every song twice and
  closes nothing; the guide says so and says to turn it off when the readout keeps saying
  `download unfinished`. A standby holding the right song that failed is KEPT (`standbyPlan`), or every
  `playing` would download it again. `play()` refused on the standby (`NotAllowedError`) goes to
  `refusedHandover()`: back to the element that was playing, `load()`, the readout saying
  "refused". A song that fails FROM MEMORY is asked for from Navidrome at once, where it stopped,
  without using its one retry (`afterPlaybackFailure` 'stream'): a decode error would otherwise skip
  a song whose copy on Navidrome plays. `reload()` always goes to Navidrome for an element holding a
  `blob:`. After that, retry-then-skip is exactly as before.
- **Events** (`routeEvent`): everything from the element playing; from the standby only `error`
  (marks it failed); the rest is dropped, so its `pause`, `durationchange` or `timeupdate` can't
  stop the lock screen, shorten the song or count listening nobody did. **AirPlay availability is
  the exception, from EITHER element** (route `'availability'`, `airplayShown()`): WebKit keeps it
  PER ELEMENT (`MediaElementSession::m_hasPlaybackTargets`, false until a change is broadcast; a
  session made after monitoring started is never seeded; a broadcast reaches only a session whose
  answer it changes) and every element repeats its own value on each load (`createMediaPlayer`,
  `EnqueueBehavior::Always`). Each element's last answer is kept, and the button shows if EITHER
  says available. An answer can only be stale one way - "none" - so that is right both ways. Two
  wrong versions came first, each found by review: routing the standby's answer to the player hid
  the button as the switch went on (the new standby's first event said `not-available`) and made
  it come and go between songs; taking only the live element's then missed a speaker leaving
  while the SECOND element played, since only the first (now the standby) was told.
  `player.sim.cjs` models per-element sessions for both. Every other handler reads `live()`. The duration is set from the incoming element
  at the handover, since its `durationchange` came while it was standing by.
- **The standby lets go** when the queue moves to anything whose next song it doesn't hold
  (`fitStandby`, which also restarts the 3s wait from the new song's `playing`), when the switch goes
  off (whichever element is playing carries on alone: `activeAfter('switch off')`), and at a
  handover (the outgoing is emptied).
- **The readout** (`describeGaps`, at the TOP of the sheet's body since the review - see "After
  review" below - and hidden below 500px tall; since 2.0.0-player.10 it is off the sheet
  altogether, Info > Debug's **Gap** row - see "Now Playing as designed, with Info"): each song
  change that happened by itself, with the switch on or off, the last `GAPS_KEPT` (5), and how it was
  made - including the incoming element's `readyState` at a handover of what it held, where below
  HAVE_FUTURE_DATA (3) reads "had to load" (pinned at 3 and 2 in the sim). **Timed on the incoming
  song's media CLOCK** (`clockStep`, review): from `ended` (performance clock) to the first
  `timeupdate` whose `currentTime` has moved past where the song started (`Change.from`: 0, or where
  a seek landed), BACK-DATED by `(position - from) / playbackRate`, since `timeupdate` comes every
  ~250ms and further apart on a locked phone. Not to `playing`: WebKit queues `playing` from inside
  `play()` for an element with data (HTMLMediaElement::playInternal, `m_readyState >
  HAVE_CURRENT_DATA`), before session admission and before AVFoundation makes a sound, so every
  handover read 1-7ms whatever the silence - a purged buffer included, which is what the readout is
  for - while the one-element way's `playing` waited for the network. The same rule in both modes.
- **Only a change that goes straight from `ended` to sound is timed** (review). `state.change` is
  dropped wherever `intendsToPlay` goes false without `pause()` - `play()`'s `NotAllowedError`, the
  unasked `pause` handler (a call at the change), `onFailure`'s stop - and by the listener: `toggle()`
  to play, the lock screen's play, a seek from the scrubber or lock screen (`actions.seek`; the
  internal `seek()` a failed song's resume uses re-anchors `from` through `state.seeked` instead),
  next, previous, a new album. `CHANGE_MAX_MS` (30s) drops anything older, clock or no clock. Before,
  a refused next song tapped a minute later read as a 60,940ms gap. A song that FAILS before its clock
  moves marks the change `failed` ("…, failed before playing"), since the time then includes the
  reload, retry or skip.
- **Verified in the real page** (Chromium, 390x844, the pane hidden - audio and `timeupdate` run
  there) against a copy of the stub Navidrome serving 6-second FLACs, timed on the clock: switch off,
  one element, 142-149ms a change, and 262-275ms with 150ms added to every stream answer; switch on,
  every change a handover from memory at 95-99ms, delay or not (the download is long done). The
  first-`playing` figure the readout used to show was 3ms for those handovers and 22-64ms for the
  one element; most of the ~98ms left is Chromium starting its audio output, which every device
  does at its own speed - so the guide tells James to compare on and off, not read either alone.
  Fix by fix: a `play` hook pausing the incoming element at once (a call at the change) and
  `play()` patched to reject `NotAllowedError` (twice with the switch on - the standby and the
  fallback - once off) each left the readout unchanged through 3s of silence and a tap on play, in
  both modes, and the next change was timed as normal (99, 98, 144, 142ms); a broken last song that
  failed twice and stopped the queue, fixed and played 3s later, was not timed, while one whose
  retry played 1.5s later read "one element, failed before playing" at 1650ms; a synthetic `error` on the incoming
  element at its `play` read "handed over, from memory, failed before playing" at 144ms (it reloaded
  from Navidrome), the next 96ms; with `webkitCurrentPlaybackTargetIsWireless` stubbed true no
  download or standby source at all and "one element (airplay)", the standby got ready again 3s into
  a song after the change event said AirPlay stopped, and emptied at once when it said it started;
  with the stub trickling whole-file answers (no Range) over 20s, every change read "handed over,
  streamed (download unfinished)" at 143-147ms, the elements alternating on stream addresses, each
  download hung up part-way and each song asked for once by address.
  **From the first build** (its timings were on `playing`): handovers after a reload with the switch
  left on and a real tap as well as after turning it on; the elements alternate, the outgoing is
  muted and emptied, and the Media Session title, artist, album, artwork, position state
  and `playing` state follow each song; "now playing" and the submission once each per song (36s
  songs at 4x); Next while the standby held the next song handed over; "previous" restarted on the
  same element keeping the standby, then went back a song dropping it and getting the right one;
  a standby whose download failed was handed the address and handed over "streamed"; a refusal
  (`play()` patched to reject `NotAllowedError` once) fell back to the element that was playing in
  61ms; a failure from memory (a synthetic `error` on the playing element) moved to Navidrome's copy
  on the same element and played on, with no skip notice and no second "now playing"; with the
  switch on, a Broken song got ready failed quietly, went the one-element way and was retried then
  skipped, and a Flaky one failing three times was retried and played; switching off mid-album,
  whichever element was playing (the first, and in another run the second) played the rest alone,
  Broken and Flaky behaving as before.
- **Seen on the phone (1.1.0-player.2, James):** song changes on the iPhone read 96 ms and 94 ms;
  on his Mac, in Arc, "Last song change 236 ms, handed over, from memory · before: 581, 511, 2867,
  218 ms". Whether the phone's were locked, and how they were made, he didn't say.
- **NOT verified - the phone's to answer**, and the guide lists them for James: that `load()` in a tap
  unlocks the second element as read; whether a download or a buffer survives while locked (the
  readout's "had to load" and big numbers say no); the lock screen during a swap; AirPlay with the
  switch on; memory with hi-res albums (a page reload is iOS taking it back); Safari against the
  home-screen app; a call or Siri during a handover; whether AVFoundation plays FLAC from a `blob:`
  as it does from the address (WebKit serves ranges of a blob, so it should). WebKit bug 295518 (an
  iOS 26 home-screen app silent after reopening) is known and unrelated; don't blame this for it.
- ~~Not built~~ **Built in 1.1.0-player.5, after a lab page proved it on the iPhone** - see "One
  stream for FLAC". What this entry said then: ManagedMediaSource with FLAC repackaged as fragmented MP4 is the only
  sample-exact route that isn't Web Audio, but whether iOS plays FLAC through it at all is unknown
  (Safari has played FLAC-in-MP4 MSE as silence before, WebKit bug 198583, Shaka #2355), it needs
  `disableRemotePlayback` (so no AirPlay from it), and it evicts. Web Audio keeps playing locked only
  with `navigator.audioSession.type = 'playback'`, has regressed there before (bug 261554, 17.2-17.3),
  and a decoded 5-minute track is ~110 MB; Gapless-5 tells iOS users to turn it off for background
  play. None of Feishin, Gapless-5, jellyfin-web, Navidrome's web UI or Plex web is gapless on a
  locked iPhone.

#### Seeking (1.1.0-player.2)

James, on `:player` before gapless: "the seek bar seems a bit messed up, but worse on mobile. it
doesn't seem to always seek to where you put it." Two causes, measured before anything changed:
one in the page, fixed; one in Safari's engine, which deadwax can't fix yet and now shows.

- **How it was measured.** A test library (`scratchpad/seek/library`, served by
  `scratchpad/seek/navidrome_stub_seek.py`, the gapless stub plus `/arm-rate?kbps=N` to pace every
  audio answer) of FLACs whose audio SAYS what time it is: a sine at 300 + 5t Hz under noise
  high-passed above 3-4 kHz. "Varied" (300 s: the pilot alone for a minute, loud noise to 180 s,
  quiet after - frames 346 to 1956 bytes) and "Steady" (240 s), made with `flac -8`, each copy
  with a table from `metaflac --add-seekpoint=10s` and without, and one with an ID3v2 tag in front.
  In Chromium, Web Audio's analyser read the pilot 1.3 s after each seek; for Safari's engine,
  `scratchpad/seek/avlab.swift` plays the same stream through AVPlayer and reads it with an
  MTAudioProcessingTap. (swiftc needs `-sdk .../MacOSX26.5.sdk`: the CLT's 27.0 SDK is newer
  than its compiler.)
- **Chromium lands exactly, whatever the file.** Every seek, with and without a table, ID3 in front
  or not, fast or at 150 KB/s: `currentTime` at 'seeked' was the target and the audio matched the
  clock to 0.01 s. Without a table it bisects (its buffered ranges show the probes), costing 1-8 s
  a seek at 150 KB/s, against 0.3-3.5 s with one.
- **AVFoundation doesn't land, and says it did.** Seeking as WebKit's `currentTime` setter asks
  (`seekWithTolerance(time, 0, 0)`, then `seekToTime:toleranceBefore:toleranceAfter:` - read in
  `scratchpad/wk`): on Varied, up to 50 s early from a file, 32 s over HTTP through deadwax, 159 s
  on a first seek at 150 KB/s and up to 40 s LATE on later ones; on a song-like swing (about 1.3x
  in bit rate, quiet intro then verses and choruses) 2-8 s early; on Steady within 0.3 s.
  `currentTime` read exactly the target throughout, and so did the tap's own source time range.
  **A SEEKTABLE changed nothing** - runs with and without were identical error for error - so the
  troubleshooting entry explains tables without offering one as the fix. The errors depend on what
  it has read (the same target lands differently after other seeks), which fits estimating the
  byte offset from the bit rate parsed so far and taking the frame there to be the target: 90 s
  asked 0.5 s into the 15 KB/s intro landed at 64.4 s, where 90 x 15 KB/s falls in the file. The
  same FLAC frames in MP4 (`ffmpeg -c:a copy -f mp4`) and a CBR MP3 landed exactly. This is the
  Mac's AVFoundation; iOS shares CoreMedia, but no phone was measured.
- **The page's half was iOS's native range.** The scrubber was `<input type=range>`, which on iOS
  moves only when dragged BY ITS THUMB - the old CSS said so and made the thumb 28px to help - so a
  tap on the bar, or a drag begun beside the thumb, did nothing. Chromium's range takes both, and
  there the old scrubber measured right in everything asked of it: a tap, a drag, a drag while a
  seek was in flight, a seek straight after a song change with gapless on and off, the lock
  screen's `seekto` on the live element. The thumb never went back to the old time.
- **The new scrubber** (`Scrubber` in NowPlaying.tsx; the rules are `lib/scrub.ts`, pinned by
  `scrub.sim.cjs`, whose assertions fail under each of seven mutations tried): a `role="slider"` div,
  the full width and `--pl-hit` (44px) tall, with the track drawn across its middle.
  `touch-action: none`, no callout, no selection. `setPointerCapture` on pointerdown, so a drag
  that wanders off the bar (onto the cover, say) still follows and seeks. A tap seeks where it
  lands; a drag follows the finger and seeks ONLY on release. A cancel (pointercancel, or capture
  lost without an up) seeks nowhere and lets go - the old range's `dragging` stayed set for good
  if `change` never came. A second finger does nothing, and a drag begun on a song that has since
  changed is dropped. The drag lives in a ref as well as state, so a release arriving before the
  render after the last move seeks where that move put it. Arrows move 5 s, Page Up/Down 30,
  Home/End to the ends - WebKit sends VoiceOver's swipe up and down as arrow keys, and each key
  steps from what the bar SHOWS, so three quick presses go 15 s. `.pl-clocks` is drawn 8px up over
  the bar's tap target with `pointer-events: none`, which keeps the track and clocks where the
  28px range had them. The sheet's drag-to-close is on the grip, a sibling, and doesn't move.
- **The bar shows a seek's target until the element says it has landed** (`state.pendingSeek`,
  `reportedPosition()`): set by a seek that MOVES the element (readyState >= HAVE_METADATA and a
  target other than `currentTime` - see "After review" below), cleared on a 'seeked' with
  `seeking` false, by a new song and by a failure, and ignored after `PENDING_MAX_MS` (20 s) in
  case one never lands. Both engines already
  answer `currentTime` with the target while seeking (Chromium measured; WebKit sets
  `m_lastSeekTime` synchronously in `seekWithTolerance`), so it changes nothing there today; it is
  the guarantee, and what the keys step from.
- **The readout's "Last seek" line** (`seekStep()`, `describeSeek()`), under the gapless one (both
  at the top of the sheet's body since the review; Info > Debug's **Last seek** row since
  2.0.0-player.10):
  asked, and what the element's clock said at 'seeked' - which in Safari is the time asked, so on
  its own it proves nothing. The END of the song is what can: WebKit clamps its clock to the
  duration (`MediaPlayerPrivateAVFoundationObjC::currentTime`, `std::min(..., m_cachedDuration)`),
  so a seek that landed EARLY leaves the clock sitting at the end while the song plays on, until
  AVFoundation's end-of-item brings 'ended'; one that landed LATE brings 'ended' with the clock
  short of the length. (Its progress timer only schedules 'timeupdate'; 'ended' comes from
  `mediaPlayerTimeChanged`, which the player calls at the end of the item - read in
  `scratchpad/wk`, not seen on a phone.) So it notes when an update first sees the clock within
  `END_SLACK_S` of the length, and at 'ended' works out `short - played on` (the wall clock
  since, less what the clock still had to go), rounded to a tenth, "on time" within
  `LANDED_WITHIN_S` (1.5 s). Only the listener's own seeks (bar, lock screen) are followed; any
  other seek, a pause other than the end's own (both engines send 'pause' just before 'ended'),
  or a song change stops the judging. The line is there from the start ("No seek yet"): appearing
  under the first tap, it moved the bar 16px up the screen, and a quick second tap landed below
  it. (That fixed only 0-to-1 lines; the review found the 1-to-3 - see below.)
- **Verified in the real page** (Chromium, the pane displayed, real pointer events from the
  computer tool) at 800x600 and 390x844, against the seek stub at 150 KB/s: a tap at 60% seeked to
  179.74 and the bar held it through the 2.4 s seek; a tap at the bar's lower edge (18px below
  the track) seeked; a drag begun away from the thumb followed it (70.5 mid-drag) and seeked on
  release, one ending 130px above the bar included, with the sheet unmoved; a drag made while a
  tap's seek was still in flight landed where the drag let go; ArrowRight x3 went 128.13 -> 143.13 in steps of 5,
  then PageDown and Home; the lock screen's `seekto` (the handler, reached through Preact's hook
  state) showed "seeking…" and landed; Next then an immediate tap seeked the new song, one element
  (before its metadata, as a start position) and with gapless on (the handed-over element, from
  memory); a seek to 4:54 read "ended on time" at the end, into a handover too; and with the
  element's `currentTime` patched to act as WebKit's would after landing 7 s early or late, the
  line read "played on 7 s ... at about 3:38" and "ran out 7 s ... at about 3:52". At 844x390 both
  readouts hide, the bar stays 44px and the cover clears the title.
- **Not verified - the phone's to answer**: a tap and a drag under a real finger (the tool's
  pointers are a mouse's); where Safari on an iPhone lands (the readout is how James sees it);
  whether WebKit sends VoiceOver's adjustments to a custom slider as arrow keys in this version.
- ~~Not built: sending FLAC to Safari in an MP4~~ **Built in 1.1.0-player.3**, without ffmpeg -
  see "FLAC in an MP4, for Safari". (A CBR MP3 transcode lands exactly too, but Navidrome's
  transcodes carry no ranges and aren't lossless, so it was never the fix.)
- **Seen on the iPhone (1.1.0-player.2, James):** FLAC seeks landed 3 s and 8 s off by the
  readout's end-of-song judgement ("the song ended 8 seconds early the first time and 3 seconds
  early the second time") - the Mac's AVFoundation measurements, confirmed on the phone.

#### After review (gapless and seeking, 1.1.0-player.2)

An adversarial review of the two commits above confirmed seven findings, all fixed together:

- **The readouts moved the bar under the finger (the major one).** The sheet's body is
  `flex: none` against the bottom of a flex column (the grip takes the rest), so a change in the
  height of anything in it moves everything ABOVE that thing and nothing below. The two readouts
  were its last children and run 1-3 lines (a seek asked, then judged at its song's end; song
  changes piling up; 4 at 320px in the worst case), so a tap after a judged line dropped the bar
  and the transport 16-32px as the finger lifted, and a quick corrective tap landed above the
  bar. The "No seek yet" placeholder had fixed only 0-to-1. **They are the FIRST children of the
  body now** (`.pl-readouts`, above the title): nothing a finger goes to is above them, so their
  height moves only the cover (by half of it upright, where the cover is width-limited; on a
  320x568 phone, where it is height-limited, it shrinks instead - 197px to 116px in the 7-line
  worst case). Chosen over a reserved fixed height with an ellipsis, which on a phone would cut
  off the judgement ("...really landed at about 2:03") with no hover to read it; nothing is cut
  short. **Measured in the real page** with a MutationObserver recording the geometry at every
  real text change, and by setting every text variant directly (8 seek lines x 7 gapless lines,
  the longest real forms): the bar's top was ONE value per size across all 56 - 642 at 390x844,
  465 at 375x667, 366 at 320x568, 566 at 1024x768 - and so were the transport, the footer and the
  title, with no overflow anywhere. The review's own sequence, for real: "ended on time" (2
  lines) then a tap, "seeking…" then "said" (1 line), bar at 642.00 throughout. At 844x390
  `.pl-readouts` is `display: none` and the bar stays 44px. **Anything added to the sheet's body
  whose height can change goes above the title**, or reserves its height. (2.0.0-player.10 took
  the readouts off the sheet, into Info > Debug, and moved the failure line above the title by
  this rule.)
- **A seek the listener didn't make filled in "the player said".** `seekStep`'s 'other seek' only
  stopped the judging, so "previous" during a pending seek to 2:00 (which restarts: `currentTime`
  answers the target while seeking) had its seek to 0 fill `said` - "asked 2:00, the player said
  0:00". `SeekReading.closed` now: 'other seek', 'song change' and the new 'failed' close a
  reading, and a closed reading takes no 'seeked'. The element answers only the newest seek, so a
  later 'seeked' is never the closed one's.
- **A seek that never landed said "seeking…" for good** (a song change or a failure first).
  A closed reading with `said === null` reads "Last seek: asked 1:30, interrupted". `onFailure`
  raises 'failed' (and clears `pendingSeek`): a seek on its way never lands in a song that failed.
- **"previous", or a tap at 0:00, on a song still loading froze the bar at 0:00 for 20 s.** At
  HAVE_NOTHING a `currentTime` write is only kept as the default start position, and both engines
  seek there at the metadata only if it is past 0 - so neither 'seeking' nor 'seeked' ever came
  and nothing cleared `pendingSeek`. `seek()` now sets it only for a seek that moves the element
  (readyState >= HAVE_METADATA and a target other than `currentTime`; it clears a stale one
  otherwise), and returns whether a 'seeked' will answer (loaded, or a start past 0). The
  listener's seek that none will answer is `'other seek'` to the readout - it takes the place of
  the one before, so Home after a tap at 0:30 during a load reads "asked 0:30, interrupted" - and
  never 'asked'. `loadedmetadata` and `playing` also clear `pendingSeek` when no seek is in
  flight: a SECOND guard, reached by no current path (a failure clears it first), so no sim can
  make it matter - removing it alone passes everything, which is expected.
- **A transcoded next song was fetched and thrown away** - see "What goes into memory".
- **The standby's AirPlay availability drove the button** - see "Events". The first fix (the
  element playing only) left the button up after a speaker left while the second element played,
  and could still hide it when the second element reloaded; a verification pass found both. Each
  element's own answer, shown if either says available, closes both - an answer is only ever
  stale in the "none" direction. From WebKit's source; not seen on a phone either way.
- **No sim reached the wiring.** `ui/test/player.sim.cjs` drives the REAL `usePlayer.ts`,
  compiled with the repo's TypeScript beside a small preact/hooks with a cursor (rendering calls
  the hook again, so state is read through its own return value, not by slot index), through fake
  audio elements on a virtual clock: loads, play() refused without a tap or the grace second,
  seeks that take time, an optional clock that lags a seek and keeps sending updates, an engine
  that answers every seek, WebKit's start-position rule, a clock held at the song's length while
  a song that landed early plays on, failures in Chromium's order (error, then pause), blobs and a
  Navidrome that answers late. 56 checks: what the bar hears through a seek with updates of the
  old time and after it lands; a stray 'seeked' mid-seek; previous, next, a decode failure that
  stops the queue and a dropped connection that resumes, all during a seek; the readout across an
  on-time end and a 7 s early landing; the three load-time seeks; a gapless handover from memory
  (AirPlay button untouched by the standby) and one of a transcode (nothing fetched ahead).
  **Mutations**: dropping `state.pendingSeek = null` from 'seeked' fails 3 checks (the bar on the
  target a second after landing, twice, and after a resume); the 'seeked' guard, each of fixes 2,
  3, 4 (whole), 5 and 6, a failure not closing the reading, `load()` not closing it and `restart()`
  not closing it each fail at least one.
- **Also re-checked in the real page** (Chromium, 390x844 and 1024x768, the short-song stub): a
  real tap at 75% landed at 27.06 s of 36 and a drag to 50% at 18.01, on the handed-over element;
  at desktop size 14.43 and 9.00 (40% and 25% asked); arrows, Page Up/Down and Home stepped as
  before, including across a song's end; the switch turned on by a real click, and Seven handed
  over to Eight "from memory" at 97 ms, the first element muted and emptied; with the stub's
  stream answers slowed to 3 s, "previous" on Long One still loading left the bar following the
  clock (1.57 -> 1, 3.07 -> 3, 6.07 -> 6). NOT checked in a page: the AirPlay routing and the
  transcode path (Chromium sends no AirPlay events and plays every file in the stub) - the sim
  covers both; and nothing on an iPhone.

#### FLAC in an MP4, for Safari (1.1.0-player.3)

James: "go ahead and build the MP4 repackaging", after his iPhone confirmed FLAC seeks 3 and 8 s
off. Safari (and every iPhone browser) now gets each FLAC song as an MP4 holding the SAME FLAC
frames; Chromium, Arc included, keeps the file as it is. The guide's section is
`docs/player.md#seeking-and-where-safari-lands`.

- **Why an MP4 fixes it.** AVFoundation seeks a FLAC by estimating a byte offset from the bit rate
  it has parsed so far (see "Seeking"); an MP4 has a sample table (`stsz`/`stts`/`stco`) giving
  every frame's size and duration, so a seek is arithmetic. Measured with `avlab2` (AVFoundation,
  pilot-tone read) THROUGH deadwax on 8081 against the seek stub, same song, same targets:
  | file | FLAC as it is (`format=raw`) | FLAC in MP4 (`&wrap=mp4`) |
  | --- | --- | --- |
  | Varied (quiet minute, then loud) | -25.6, -22.9, +39.9, +17.9, +25.3, +38.1, +31.0; 275 s ran off the end | +0.01 on all 8 |
  | Song-like (a song's swing) | -11.8, -14.0, +3.0, -2.5, +1.7, +1.2, +1.9, +4.8 | +0.01 on all 8 |
  In Chromium the wrapped URL, set by hand on an `<audio>` with a Web Audio analyser, read the
  pilot at a constant -0.34 s from the clock on all 8 seeks - the analyser window's half, the
  same figure the raw FLAC gives - so Chromium plays and seeks the MP4 exactly too.
- **The muxer, `src/flac_mp4.py`, pure, no ffmpeg** (the image is python-slim and stays so).
  xiph's isoflac.txt layout: ftyp (`isom`, `iso2`, `mp41`), then `moov` BEFORE `mdat` (a player
  fetching by range seeks without reading to the end), one MP4 sample per FLAC frame, frames
  byte for byte, STREAMINFO in `dfLa` in an `fLaC` sample entry, sample rate as timescale, no
  `stss` (every frame is a sync sample), chunks of about a second. Deterministic (no timestamps),
  so the same file always makes the same bytes. `mp4_layout()` returns the head and where the
  audio is in the input, so the cache writes head + a slice of the FLAC it already holds rather
  than a second copy. Decoded PCM through ffmpeg was byte-identical for six real files; 57 ms for
  a 40 MB CD FLAC as first built, 51 ms since 1.1.0-player.5.
- **Splitting frames safely is the whole risk**, since FLAC has no frame index and the sync code
  turns up inside audio every ~90 KB. A candidate is taken as the next frame only if its header
  is right in every particular: every field agrees with STREAMINFO, reserved bits clear, CRC-8
  right, and exactly the NEXT frame (or sample) number, coded the shortest way - by chance once in
  2^40 bytes at worst, 2^48 past frame 127. And not left to chance: a false header taken for frame
  k leaves the real frame k's header before k+1's, carrying a number already used (and the real
  headers after it too, when several false ones were taken in a row) - so a header carrying ANY
  number already given to a frame is watched for, and the CRC-16 of the frame before that one
  decides which is real; neither or both checking out refuses the file. Only within a frame's
  reach of that frame, since 1.1.0-player.5: one numbered further back can't be real and is
  passed over. Every frame, the last included, must fit that reach - STREAMINFO's largest frame,
  or a frame of verbatim samples when it gives none. The LAST frame is always CRC-16 checked (how
  an ID3v1/APEv2 trailer is left out and a truncated file refused), block sizes must sum to
  STREAMINFO's total, a fixed-block stream's frames must all be one size, past one false sync per
  256 bytes the file is refused, and past 4 MiB of checksumming too (bounded work). Anything off
  raises `CannotRepackage` and the FLAC is sent as it is: a wrong MP4 would be worse than none.
  161 tests (`tests/test_flac_mp4.py`) with a verbatim FLAC encoder, no binary fixtures, planted
  false headers; see "After review (the muxer)" below.
- **The route: `wrap=mp4` on the EXISTING stream route**, honoured only with `format=raw` - no new
  route, `test_there_is_no_general_proxy` still pins the list. `player_cache.Mp4Cache.answer()`:
  1. **Which version** (`_version`): a `bytes=0-3` range of the file from Navidrome. Its type must
     be `audio/flac` or `audio/x-flac` (Navidrome's mime_types.yaml says `audio/flac`) AND its
     first bytes `fLaC` or `ID3`; the Content-Range gives the size, and Last-Modified plus any
     ETag the stamp. Remembered `VERSION_SECONDS` (30), since Safari asks two bytes, then the rest,
     then a range per seek. A 416 (an empty file) is a "no", not Safari's 416. Four bytes that
     Navidrome breaks off are NOT remembered: that request gets the FLAC, the next looks again.
  2. **The key is `sha256([FORMAT_VERSION, id, size, stamp])`**, and the file is named by it, never
     by the id (caller input). Navidrome's Last-Modified for a raw stream is its database's
     `UpdatedAt` (core/stream/media_streamer.go: `ModTime()` is `mf.UpdatedAt`), which moves once
     its scan has seen a change; the size is ServeContent's real one. **The MP4 carries no tags**
     - only STREAMINFO and the frames - so a retag makes the same MP4 again: a wasted repackage,
     never a wrong one. What the key must catch is a file whose AUDIO was replaced, and a
     same-size replacement is caught by the stamp (pinned). Bump `FORMAT_VERSION` whenever the
     muxer's output changes.
  3. **Miss**: the whole file (no Range) streamed to a `.part` file in 1 MiB writes, its bytes
     counted against the version's size (a length that disagrees, or too many or too few bytes,
     means it changed or broke: this request gets the FLAC, the next looks again - NOT remembered
     as a refusal, which would keep a good song out for good), then `_repackage` in a worker
     thread: read, `mp4_layout`, write `<key>.<token>.tmp`, `os.replace` into place, so a
     half-written MP4 is never served. The input is held once in memory (`WRAP_MAX_BYTES`, 512 MiB;
     bigger is refused from the probe's size, logged at info, nothing fetched).
  4. **Single flight**: one task per key in `_working`, awaited through `asyncio.shield` so a
     phone hanging up can't cancel what another request waits on; and one repackage at a time
     altogether (`_gate`, an asyncio.Lock made per event loop - TestClient runs each request on its
     own loop), which bounds memory; inside it the file is checked for again. **Verified**: ten
     requests at once on a cold song, one abandoned after 20 ms, made one MP4 and every range
     matched. (Since 1.1.0-player.4 the gate covers the repackage only, and a make nobody waits
     for any more is stopped - see "After review (the cache)".)
  5. **Refusals** (`CannotRepackage`, too big) are remembered per key (`REFUSALS_KEPT`, 256) and
     logged ONCE: `player: song X is sent to Safari as FLAC, not in an MP4 - <reason>`. Transient
     failures (Navidrome dropping the download, the disk) are logged each time and not remembered.
     ~~Every failure answers None and the route relays the FLAC~~ - not a request carrying on from
     an MP4, which the review found spliced two files; see "After review (the cache)".
- **Served by `ranged_file`, not Starlette's FileResponse**, which was read (0.50) and fails three
  ways: its 416 says `Content-Range: */N` without the unit, it refuses a suffix range longer than
  the file (RFC 9110 says the whole file, as a 206), and it stats the file only as it sends, so an
  eviction in between is a 500. `ranged_file` opens the file FIRST (an open file outlives its
  name; FileNotFoundError reaches the caller while it can still send the FLAC), answers one range
  (several, another unit or a malformed one get the whole file with a 200, which the RFC allows),
  and honours If-Range strongly against the ETag (the key) or exactly against Last-Modified (the
  MP4 file's own mtime - which is why LRU recency is kept in memory, `_used`, and never by
  touching the file: that would change the validator under a seek). `audio/mp4`,
  `Cache-Control: no-cache`, Accept-Ranges, exact Content-Length; GuardMedia and the gzip
  exemption apply by path already (`/deadwax/navidrome/stream/`), and a test checks both.
- **The cache: `tempfile.gettempdir()/deadwax-player`, 1 GiB, least recently served first**, never
  the file just made. Temp space, not /config: it is rebuilt on demand, the config volume is what
  gets backed up, and a new image starts it empty. Leftover `.part`/`.tmp` files older than 10
  minutes are cleared on first use. ~~No setting, decided~~ **Two settings since 1.1.0-player.4,
  asked for** (`PLAYER_CACHE_PATH`, so it can live on an SSD, and `PLAYER_CACHE_MB`) - see "After
  review (the cache)". Still never /config by default.
- **The page** (`lib/streamWrap.ts`, pinned by `wrap.sim.cjs`): `wrapsFlac()` once per page -
  WebKit that isn't Chromium (any iPhone/iPad UA, CriOS and FxiOS included; a "Macintosh" UA with
  touch points is an iPad in desktop mode, even one claiming Chrome; otherwise `AppleWebKit/`
  without `Chrome/`, which HeadlessChrome, Edge, Opera, Samsung and Arc all carry) AND
  `canPlayType('audio/mp4; codecs="flac"') !== ''`. Per song, `asksForMp4()`: a FLAC by suffix or
  type, and `format=raw` (a transcode has no FLAC in it). `streamUrl(track, canPlay, pageWraps)`;
  usePlayer's `addressOf()` is used for the element, the reload, the gapless download and the
  unfinished handover alike, so all four ask for the same URL and the server's cache serves them
  all. `memoryPlan` already took any `audio/*`, so the gapless download holds the MP4 unchanged.
- **The readout says how the song came**, since an element never shows what type it was sent and
  deadwax may have sent the FLAC: `checkWrapped()` asks the same URL for `bytes=0-1` at every song
  (`load` and `handOver`), reads the Content-Type, and drops an answer for a song no longer
  playing. The "Last seek" line ends ` · FLAC in MP4`, ` · sent as FLAC, not in an MP4`, or
  ` · asked for FLAC in MP4` until the answer lands; nothing in Chromium. It describes the song
  PLAYING, so after a song change it sits beside a seek judged on the song before. (Since
  2.0.0-player.10 it is Info > Debug's **Sent as** row, off the now-playing sheet: built on the same
  `describeWrap`, less "sent as" and its rate, with the depth and rate it was sent at on the end -
  `FLAC in MP4, 24-bit, 48 kHz` - and the resampling on a **Resampled** row of its own.)
- **First-request delay** (a cold `bytes=0-1` through deadwax on this Mac, the stub on
  localhost): 131-225 ms for a 4-minute CD-quality FLAC (29 MB, ~970 kbps; the repackage itself
  77-87 ms of it, the rest fetching from the Python stub), 91 ms for Varied (19 MB); a cached
  answer 1.2 ms, against 2.3 ms for the raw FLAC relayed. A NAS will be slower; a real Navidrome
  serves the file faster than the stub.
- **Verified in the real page** (Chromium, 8081, the seek stub): the page as it is - element on
  `format=raw`, the gapless download `?format=raw`, a handover "from memory" at 226 ms, the seek
  line with no suffix. Then with `navigator.userAgent`/`maxTouchPoints` overridden to an iPhone's
  and the player module re-imported: the element on `&wrap=mp4`, the next song downloaded as
  `&wrap=mp4` and played from its `blob:` after a handover "from memory", the line reading "No
  seek yet · FLAC in MP4" and, after a real tap at 50%, "Last seek: asked 2:30, the player said
  2:30 · FLAC in MP4", then "... the song ended on time ..." at the end; at 375x667 the line wraps
  above the title with nothing clipped. Every served byte and range (0-1, 1000-, a suffix, a
  middle, past the end, If-Range stale and current) compared equal to `flac_to_mp4()` of the file
  for Varied, the ID3-fronted Varied and the CD file.
- **Tests**: 32 through the real app in `tests/test_navidrome.py` (a fake Navidrome serving a
  FLAC from the muxer tests' encoder), and `wrap.sim.cjs` plus a Safari/Chromium section in
  `player.sim.cjs`. Mutations: 14 of the cache's (If-Range ignored, the suffix clamp, refusal
  memory, the stamp in the key, the LRU touch, LRU order, the cap, version memory, the bytes check,
  the size cap, the byte count, the 416's unit, the part file left, a weak ETag taken) and 8 of the
  page's (the answer-for-this-song guard, the download's URL, the handover's check, the iOS and
  iPad rules, the Chrome exclusion, the raw-only rule, the canPlayType ask) all caught - after
  the stamp, the byte count and the two iOS rules first went uncaught and tests were added.
- **NOT verified - the phone's to answer**: that the iPhone's AVFoundation lands in the MP4 as the
  Mac's does (the readout's end-of-song line is how James sees it); how long a first play waits
  over WireGuard from the NAS; that the gapless `blob:` of an MP4 plays on the phone (it plays in
  Chromium); memory on the NAS with hi-res files; and Safari's own request pattern against the
  cache (only curl, AVPlayer and Chromium have asked it).

#### After review (the muxer, 1.1.0-player.4)

An adversarial review confirmed three findings in `src/flac_mp4.py`, all fixed together:

- **Anything appended that checksums to zero went into the last MP4 sample.** FLAC's CRC-16
  starts at zero with nothing XORed at the end, so once a frame sums to zero, appended zero
  bytes keep it there, and so does a run of whole frames, each summing to zero. The end check
  took the end of the file on that alone: 16 zeros after a 60 s `flac -8` file made the last
  sample 1302 bytes instead of 1286, and AVPlayer (`avend`, from 50 s) posted
  FailedToPlayToEndTime at 57.7 s (-11800 / OSStatus -50) on a song it plays to 60.0 as FLAC -
  the same with 64 to 4096 zeros. `_last_frame_end` now refuses (the FLAC is served) when:
  the last frame checks out at more than one candidate end (a tag whose own CRC-16 is zero, 1
  in 65,536 - the longer was taken, tag and all); the sum, carried in the same pass to every
  sync code in the last frame, is zero at one (a frame's end with another after it); or three
  or more zero bytes come before the chosen end. **Don't strip zeros instead**: a real
  frame's CRC-16 ends in a zero byte in one file of 256 and that can't be told from one
  appended zero; a real frame ends in three only when its CRC-16 is 0x0000 and the byte
  before it is zero too. One or two appended zeros stay in the last sample, and AVPlayer
  played those MP4s to the end (measured). ~~Still let in: any other trailer whose CRC-16
  happens to be zero, 1 in 65,536~~ - not so: a whole frame of the OTHER blocking strategy got
  in every time, and anything built to sum to zero still can; see the second review below.
- **Each header repeating the number just used cost a whole-frame checksum, uncharged.**
  review4's `m/dup_dos.py` (a valid 397 KB FLAC, frame 1 full of copies of its own header):
  200 copies 1.8 s, 1,000 copies 8.8 s, packed with 21,800 copies 196 s - and through the app
  every other Safari song waited behind it on the cache's one gate (`m/gate_demo.py`: an
  ordinary song's first byte at 8.8 s). Now every such header is charged to
  FALSE_SYNC_BUDGET; `_Checksums` carries one running CRC-16 per origin and remembers every
  answer, so a frame is summed once, not once a copy; and CHECKSUM_BUDGET (1 MiB plus twice
  the file) bounds all checksumming, refusing past it. After: 0.01 s, 0.01 s, and refused in
  0.02 s; gate_demo's songs answer at once. A real file sums its last frame and any tag and
  nothing else - a test pins it with the budget set to exactly that. ~~The worst case is now
  linear, about twice the file at ~15 MB/s of pure-Python CRC~~ - and linear was the problem:
  one file with a long tail still held the gate for seconds. The budget is 4 MiB whatever the
  file since the second review, below.
- **A repeated number where BOTH readings check out kept the first**, splitting a valid FLAC
  in the wrong place with no error (`m/wrongsplit.py`: a start at 18580 where frame 2 really
  is at 32965; AVAssetReader failed on the MP4 with -50). Both checking out is refused now,
  as neither always was: in a real file it takes a false header (2^-40) AND a 1-in-65,536
  checksum. That held for one planted copy only: two in a row got past it (see the second
  review).
- **Measured**: the 40 MB CD FLAC maps in 55.2 ms against 55.0 before (median of 15). 112 of
  121 FLACs to hand (the review battery, the seek and gapless libraries, the big and hi-res
  files) give byte-identical MP4s; the nine that changed are six zero trailers, the two
  crafted wrong splits and the packed-copies file, all now refused. Through the real app
  s60 + 16 zeros answers `audio/flac`, and s60 itself `audio/mp4`, playing to 60.0 s in
  AVPlayer.
- **Tests**: 19 new in `tests/test_flac_mp4.py` (103 now); 14 fail on the old muxer, and the
  other 5 pin what must still be accepted (one or two appended zeros, a last frame whose own
  CRC-16 ends in one or two zeros). All 8 mutations of the new rules tried were caught.
- **`FORMAT_VERSION` is 2** (player_cache.py), bumped at integration. The muxer's output didn't
  change for any file it still wraps, but a cache kept since 1.1.0-player.3 holds MP4s of the
  files it now refuses, which AVFoundation stops in before the end; the new key means they are
  never served again, at the cost of one re-make of each song cached.

A second review, of those fixes, confirmed three more crafted files that got through, all fixed
in 1.1.0-player.5. Each was reproduced with its script in the scratchpad's `verify5` before the
fix and after it.

- **Two header copies in a row still split a valid FLAC in the wrong place.** Only a header
  repeating the number JUST used was watched for. So copies of frame 2's and frame 3's headers
  inside frame 1 were both taken, and the real frame 2's header, carrying a number no longer
  looked for, was passed over as a false sync. `verify5/twoplant.py` built two such files: A
  split at [.., 16571, 18580, 20580, 65753] and B at [.., 16571, 18580, 49359], where the real
  starts are [.., 16571, 32965, 49359, 65753]. `flac -t` passes both, and AVAssetReader failed on
  both MP4s (-11800 / -50).
  - `_frame_header` now reads the number, whatever it is, and the split watches for a header
    carrying ANY number already given to a frame. The rule is the old one at any slot: the frame
    before that one checks out either where the next was taken to begin or at this header, and
    everything taken in between was inside it.
  - A now wraps, split where it should be: AVAssetReader and ffmpeg both decode its MP4 to
    libFLAC's PCM exactly. (ffmpeg's own FLAC demuxer misreads the FLAC itself.)
  - B, where frame 1 checks out at the first copy as well, is refused as two readings. The old
    test of two copies in a row ("refused rather than guessed") now wraps correctly, for the same
    reason as A.
  - **Only within a frame's reach.** A real file carries a valid header with SOME earlier number
    far more often than one with the next number: past frame 127 its number byte has 128 chances
    instead of one. On random bytes for a CD stream 3,000 frames in, that was once in 2^33.6
    bytes (one per 13 GiB), roughly one 40 MB track in 300. Refusing those would cost real
    songs, and so would summing back to their frame (the whole file, for number 3 turning up in
    frame 3,000). So a header further from the start of that frame than any frame can reach is
    passed over unsummed: the frame couldn't be that long. The last number given is checked
    whatever the distance, as before.
- **A frame's reach** (`_reach`) is what makes that sound, and bounds everything below.
  - It is STREAMINFO's max_framesize when the encoder wrote one (libFLAC and ffmpeg write the
    true figure). Otherwise it is a frame of the largest block stored verbatim, the sum in
    ffmpeg's `ff_flac_get_max_frame_size`, which no encoder goes past.
  - No frame is taken that makes the one before it larger than that, and no last frame may be.
    A frame past it means the reach is wrong for this file, and so is everything it decided.
  - Of the 217 FLACs to hand (1.37 GB, 1.9 million frames), none has a frame past its reach.
    Two, in review4's battery, leave max_framesize 0.
  - **Residual**: the reach is only as honest as the file. A crafted file with a frame larger
    than its own STREAMINFO allows can still be split wrong. With no max_framesize given, the
    same goes for a frame larger than verbatim (legal FLAC that no encoder writes). Either needs
    two or more planted copies with checksum bytes solved as well, and costs one song in Safari.
    Middle frames are still never checksummed, so a whole frame slipped in between two others is
    caught only when its number was given within a frame's reach of it, or it makes a frame
    larger than the reach.
- **A whole frame of the OTHER blocking strategy after the last went into the last sample
  every time.** The last frame was searched for the stream's own sync code only, and such a
  frame sums to zero on its own. `verify5/s60_plus_fff9.flac` is a 60 s `flac -8` file plus its
  own frame 0 re-coded with 0xFFF9: its last sample was 2575 bytes where STREAMINFO says 1298,
  and AVPlayer stopped at 57.8 s (-11800 / -50) on a song it plays to the end as FLAC.
  - Both sync codes are looked for now.
  - A last sample larger than the reach is refused before anything is summed, which alone
    refuses this file: "the last frame would be 2575 bytes, larger than any frame of this stream
    can be (1298)".
  - One or two appended zero bytes still fit s60's reach and stay in. Sixteen don't.
  - **Still let in**: something appended that sums to zero and starts with no sync code, while
    the last sample stays within the reach. That happens one time in 65,536 by chance, and every
    time if built so. With no max_framesize the room is the verbatim bound's slack over the last
    frame.
- **The checksumming was still about twice the file.** `verify5/bigtail.py` (a valid FLAC and 64
  MiB appended with no sync code in it) took 9.2 s to refuse, 134 MB summed. Through the app an
  ordinary song asked for 0.5 s later got its first byte at 9.3 s, behind the cache's one gate.
  At WRAP_MAX_BYTES that is over a minute here.
  - An end further from the last frame's start than a frame can reach is ruled out before
    anything is summed. Tails of 16, 64 and 512 MiB are refused with nothing summed, in 0.0,
    0.0 and 0.3 s (the last is the search for sync codes through 512 MB).
  - `CHECKSUM_BUDGET` is 4 MiB whatever the file, about a quarter of a second here. Only a
    stream claiming frames megabytes long can reach it, since the reach bounds every sum.
  - Through the app (verify6's copy of gate_demo, 64 MiB tail) the ordinary song answers at
    0.5 s, when it is asked.
  - A real file's tag gets the same treatment: a 1 MiB APEv2 tag (a cover) after the audio used
    to be summed and now isn't.
- **Measured**: all 217 FLACs to hand (the seek, step1 and review4 libraries and the big files)
  against 1.1.0-player.4's muxer. 209 give byte-identical MP4s. The other 8, the review's zero
  and junk trailers, are refused by both, 6 of them now by the reach before anything is summed.
  The 40 MB CD file maps in 50.8 ms against 55.1 (median of 15, twice over).
- **Tests**: `tests/test_flac_mp4.py` has 161 now, 58 more, with the header and appended-frame
  tests rewritten. They cover:
  - chained copies resolved, and refused where both readings check out;
  - old numbers within and beyond reach;
  - frames larger than STREAMINFO allows, at the second, a middle and the last frame, and one
    with a copy halfway;
  - the other strategy's frame both ways, with the largest frame known and unknown, and
    `flac -8`'s own file with its frame 0 appended re-coded;
  - 16 MiB appended refused with nothing summed, a stream claiming 16 MiB frames stopped at the
    budget, a big tag left out unsummed, and verbatim frames of every shape within reach when
    STREAMINFO gives none.

  Sixteen mutations, each undoing one rule, are all caught. The first pass missed three. The
  reach on tag candidates and carrying a sum on from an earlier frame got tests. The third,
  checking every frame taken since the slot rather than only the one before it, turned out to
  add nothing, and was dropped.
- **`FORMAT_VERSION` is not bumped** here (it is player_cache.py's). Every real file's MP4 is
  unchanged. A 1.1.0-player.4 cache can hold a wrong MP4 only of a crafted file (twoplant A or
  B, a frame of the other strategy appended), and serves it until it is evicted. Bumping would
  clear those at the cost of re-making every cached song.

#### After review (the cache, 1.1.0-player.4)

The same review confirmed five findings in `src/player_cache.py` and the page, and one in the
docs; fixed together with two settings James asked for so the cache can live on an SSD. Each was
reproduced with review4's script before the fix and after it, and again after integration.

- **Skipping songs in Safari made the song landed on wait for every one skipped (major).** Each
  make was a shielded task nothing cancelled, one lock covered the download from Navidrome as
  well as the repackage, and `checkWrapped()`'s `bytes=0-1` was never aborted - so four Nexts on
  uncached songs downloaded and repackaged all four, in turn, before the fifth started.
  - `_Make` counts the requests waiting on a make, and the last to leave cancels it, its
    Navidrome download closed with it. A later request for that song starts afresh.
  - The route wraps `answer()` in `unless_abandoned()`, since uvicorn never cancels a handler
    whose phone has gone; a hang-up answers 204 into the closed connection.
  - `_gate` covers `_repackage` only, so downloads no longer queue behind each other.
    `_to_the_end` keeps it held until the worker thread finishes even when the make is cancelled:
    a thread can't be stopped, and a second song mustn't be held in memory beside it.
  - `checkWrapped()` has an AbortController, aborted at the next song and on unmount.
  - `review4/skip.py` at 100 MB/s, song 5's first byte: 2880-2897 ms before, 531-559 ms after
    (one song alone 546-630 ms), MP4s made 6 before and 2 after; uncapped 316-473 ms before,
    171-286 after. Live under uvicorn, the stub at 5 MB/s, four skips 150 ms apart: song 5 in
    5539 ms against 5513 ms for one song alone, four "was stopped" lines, and the stub saw each
    skipped download hang up part-way.
- **One URL could be answered as FLAC and then as MP4** (`test_splice.py`: a cut first download
  gave `bytes 0-1/200917` as FLAC, then `bytes 2-100/201415` from the MP4; the other way round
  after an eviction). The element splices the two into a decode error.
  - `_answered` remembers what each SONG was last answered as, and `continues()` tells a fresh
    start (Safari's `bytes=0-1` probe, or no Range) from a continuation (anything else).
  - A continuation of a FLAC answer stays FLAC, however long after. A fresh start stays FLAC for
    `VERSION_SECONDS` after one, so the readout's probe and the element are told the same.
  - A continuation of an MP4 answer re-makes the MP4 and waits for it, also when the file
    vanishes between being found and opened. If it still can't be had, it is a **503** with
    `Retry-After: 2` and `Cache-Control: no-store`, never FLAC bytes. The page's retry then
    starts afresh, and a fresh probe may get FLAC.
  - After: (a) both FLAC, the second body `FLAC[2:101]`; (b) MP4, then 503.
  - Costs, stated: a transient failure keeps that song on FLAC for its play; the memory is per
    song, not per phone (deadwax can't tell clients apart), so two clients on one song around a
    failure can still see a flip; and whether Safari always starts a song with exactly
    `bytes=0-1` is unverified on a phone - if it didn't, a retry after a failure would get a 503
    rather than the FLAC.
- **A disk short of space filled up and was never given back** (`enospc.py`: songs 3-6 sent as
  FLAC, 76 MiB held for good). `_make_room()` runs BEFORE the download now: the MP4s played
  longest ago are cleared until the new song fits under the cap, counting the songs being made
  (`_reserved`), and the disk has `MAKE_ROOM_FACTOR` (2) copies of it plus `DISK_SPARE_BYTES`
  (128 MiB) free. Short even then is FLAC, with nothing fetched. ENOSPC anyway (something else
  writing) clears twice the song and tries once more. After: all six wrapped.
  - The cap bounds the finished MP4s. The folder's peak is the cap plus one `.part` per song
    being made, and a song bigger than the whole cap is still made - kept on its own, the one way
    past the cap. The docs say both.
  - **Found at integration**: `_make_room()`'s loop variable was `size`, rebinding the song's own
    size that `fits()` reads, so the room was judged by whichever song was about to be cleared. A
    big song after small ones cleared nothing: a 50 MB song beside ten 9 MB ones under a 100 MB
    cap went 40 MB past it until `_evict` trimmed it after the make.
    `test_room_is_made_for_the_song_coming_not_the_size_of_the_songs_cleared` fails without the
    fix.
- **A read-only root filesystem stopped deadwax starting** (`ro_import.py`, `ro_app.py`): the
  cache folder was `tempfile.gettempdir()` at import, which raises when nothing is writable.
  Nothing is resolved at import now, and no usable folder means FLAC, logged once per distinct
  problem (`_said`).
- **The cache folder wasn't checked to be deadwax's own** (`plant.py` served a planted link's
  target as `206 audio/mp4 b'PRIVATE KEY MATERIAL'`). `_judge()` lstats `deadwax-player` before
  anything in it is listed, deleted or served: a real folder, not a link, owned by
  `os.getuid()`, with no group or other permission bits. Anything else is refused - FLAC, and one
  log line naming what to remove. **Only the permission bits count** (verification pass): the
  first cut demanded the mode be exactly 0700, and OpenMediaVault sets setgid on every shared
  folder (sharemgmt ORs in 02000), which Linux's mkdir passes on - so `deadwax-player` came out
  02700 on James's platform and was refused on every song, with advice ("remove it") that could
  only recreate it. macOS's mkdir doesn't inherit setgid, which is how the Mac tests missed it.
  Now `_judge` refuses `mode & 0o077`, and `_own` chmods a folder it has JUST made to 0700
  (never one it found). Made, chmodded and still open means a disk that keeps no permissions
  (CIFS, NTFS, exFAT), which gets its own message pointing at a Linux-formatted disk. Clean-up and eviction never follow links, and cached files are opened with
  `O_NOFOLLOW`. Residual: if the folder `PLAYER_CACHE_PATH` names can be written by another
  user and isn't sticky, they could swap `deadwax-player` between the check and the file
  operations.
- **The settings.**
  - `PLAYER_CACHE_PATH` (the Paths group, Settings → Library). Empty is
    `gettempdir()/deadwax-player`. Set, deadwax makes its OWN `<path>/deadwax-player` (0700),
    never chmods or chowns the folder named, and touches nothing else there - so it can name a
    shared folder. Read on every request (`Mp4Cache.directory`, `_folder()`), so a change needs
    no restart; a new folder clears `_used`. Not validated on save, like the other paths: the
    row adds `folder_problem()` (the same `_judge`, making nothing) to `_describe_path`'s
    exists-and-writable check.
  - `PLAYER_CACHE_MB` (after `DB_PATH`). Default 1024. `parse_player_cache_mb()` takes ASCII
    digits only, 64 to 1048576, and a trailing "MB"; anything else is refused on save. Read at
    every use (`player_cache_bytes()`). An unreadable environment value is an error row saying
    1024 is used.
  - Both are commented into `docker-compose.example.yml` (with a `/cache` volume line) and
    `.env.example`, and documented under Paths in docs/configuration.md.
  - **Verified in the real page** (Chromium with an iPhone user agent, the seek stub, 8081): the
    element played `&wrap=mp4` and the readout said "FLAC in MP4"; three real taps landed (the
    pilot read 210.51, 60.32 and 271.07 against clocks of 210.79, 60.79 and 271.56, the
    analyser's usual lag); the MP4s went into the configured folder's `deadwax-player` (mode
    700, "256 MB at most" logged); changing `PLAYER_CACHE_PATH` in the tab moved the next MP4 to
    the new folder with no restart.
- **The docs' MP3 claim was wrong.** player.md and troubleshooting.md said an MP3 is sent as it
  is because "Safari seeks those properly already", which holds for a CONSTANT-bit-rate MP3
  only. avlab2 on review4's `varied-vbr.mp3` (LAME V2 with a Xing header) landed -0.29, -2.29,
  +41.31, +8.31, -0.19 and +33.31 s off at 90, 250, 30, 150, 200 and 60 s, where the CBR
  `varied-320.mp3` landed +0.01 on every seek. WebKit's `createAVAssetForURL` doesn't set
  `AVURLAssetPreferPreciseDurationAndTimingKey`, so avlab stands for Safari. The docs now say a
  VBR MP3 can land seconds off in Safari and isn't repackaged, and that AAC and ALAC in `.m4a`
  are MP4s already. The test song swings its bit rate far more than music does, so how far off
  a real V0 album lands is unknown. Repackaging MP3 is not built.
- **Tests**: `tests/test_player_cache.py` is new (32 functions, 48 cases); three tests in
  test_navidrome.py changed, because they pinned the flip (the request after a cut download
  stays FLAC now, and wraps once `VERSION_SECONDS` have passed); `player.sim.cjs` checks that
  Next lets go of song 1's probe. Fifteen mutations, each undoing one fix, were all caught, and
  so is the make-room one.

#### One stream for FLAC (1.1.0-player.5)

James, with the second-player gapless still leaving ~100 ms on the iPhone: build "the method that
just worked on iOS" - a lab page (scratchpad, never in the repo) that played consecutive FLAC songs
through one ManagedMediaSource seamlessly on his iPhone, in Safari and in Arc, locked, fetching over
the network while locked. The second-player way stays, for every song the stream doesn't take. The
guide's section is `docs/player.md#one-stream-for-flac`.

- **The recipe is exactly the lab's; don't vary it without the phone.**
  - ManagedMediaSource on WebKit (the only MSE an iPhone has), plain MediaSource in Chromium, chosen
    once per page by `mediaSourceEngine()` (streamSource.ts). Type `audio/mp4; codecs="fLaC"` first
    (WebKit's ManagedMediaSource takes only the ISO fourcc), `"flac"` second.
  - Each song as a fragmented MP4 of its own FLAC frames, made by deadwax (`wrap=fmp4`).
  - Each song's init segment appended immediately before its media: without it WebKit clicked at
    the join.
  - Songs placed with `timestampOffset` = the run's earlier samples / rate. WebKit rounds it to the
    sample timescale (`roundTowardsTimeScaleWithRoundingMargin`), so a join lands on the exact
    sample however long the run.
  - `disableRemotePlayback = true` BEFORE attaching a ManagedMediaSource, or WebKit leaves it
    `closed` without a word (the open is deferred until AirPlay can't be asked of the element). It
    goes on as `srcObject`; Chromium refuses a MediaSource as srcObject, so a `blob:` URL there.
- **The server: `fmp4_layout()` in flac_mp4.py**, pure like the MP4 muxer and sharing its frame
  splitting: ftyp (iso5), a moov with mvex/trex, a sidx, then a moof and mdat per second of frames,
  every sample flagged sync (tfhd default flags 0x02000000). Byte for byte the lab's ffmpeg file,
  but for the sidx (added) and udta (left out). player_cache keeps them beside the MP4s as files of
  their own (`.f.mp4`, `FMP4_WRAP`, `FMP4_FORMAT_VERSION` in the key), with their own makes and
  refusals. `answer_fragmented()` answers byte ranges; a 415 JSON when this version can't be
  repackaged; a 503 with `scope` "song" (Retry-After 2) or "server" (30); never the FLAC, which a
  MediaSource can't take. The route takes `wrap=fmp4` only with `format=raw` (400 otherwise).
  **The If-Range pin** (`_pinned`, `PINS_KEPT` 1024): a range whose If-Range names the file the
  song was last served as is answered from it without asking Navidrome, so a Navidrome redeploy or
  a retag mid-song doesn't break the stream.
- **The page: `ui/src/player/streamSource.ts` owns the stream** (which songs are in it and where,
  fetching, appending, seeking, saying when it can't go on and for which song); usePlayer keeps the
  queue, the lock screen and the listening. The rules are pure in `lib/streamPlan.ts` (placing
  songs, what to fetch next, what an answer means, retries) and `lib/fmp4.ts` (reading a head),
  pinned by `stream.sim.cjs` and `fmp4.sim.cjs`; the wiring by `player.sim.cjs`, whose fake
  MediaSource parses the real fragmented MP4, places frames as WebKit does, evicts under Safari's
  cap, clamps seeks to `seekable` and waits at holes.
- **What the browser does NOT do for us**, each read in WebKit's or Chromium's source:
  - An iPhone holds about 5.26 MiB of audio in a SourceBuffer (Chromium 12 MiB). So pieces of at
    most 5 s or 1 MiB, fed 10 to 30 s ahead (`REFILL_BELOW_S`, `FILL_TO_S`) within 3 MiB (8 MiB
    plain); a QuotaExceededError clears what is behind (keeping a second), then splits the piece at
    a fragment boundary, then waits for the playhead - never on a playhead that is itself waiting.
  - What to fetch is worked out from `buffered` every time (`nextWant`), never from a cursor:
    eviction and seeks leave holes anywhere.
  - A seek is clamped to `seekable`, [0, duration] for a finite duration that grows only as data
    comes, so the duration is raised first; and Safari 27.0 evicts relative to where the playhead
    WAS, so a seek to unbuffered time removes every other range, appends only the target's piece,
    and appends nothing more until 'seeked' (the stages: wait, clear, place, append, land).
  - `endOfStream()` is a state: an append, a remove or a `timestampOffset` reopens an ended source,
    and an open one stalls at its end instead of ending - on a locked phone, the music stopping. It
    is called again whenever the run is all in.
  - An aborted append's 'updateend' arrives after whatever came next: nothing trusts an
    'updateend' while `updating` is true.
  - `srcObject` beats `src`, and any `load()` detaches a MediaSource for good: usePlayer's
    `detach()`, and `reload()` on a stream leaves the stream instead of reloading.
- **A new stream only in a gesture** (a tap, a lock-screen command): outside one - a song ending, a
  skip after a failure - a new MediaSource would have to open, fetch and append before iOS
  suspends a page that isn't playing. Those go the URL way, and the next tap streams again. No
  standby holds a song of the run (`standbyPlan`'s `live`).
- **What joins**: FLAC, up to 48 kHz, one or two channels, 16 or 24 bits (`formatStreamable`), in
  the same format as the song before (`joins`). A song kept out by its format only is `noStream`
  (it still gets its MP4 for Safari the URL way); one deadwax won't repackage, or whose bytes won't
  decode, is `refused` (the file as it is). A song that fails the stream plays the URL way from
  where it had got to, as the raw FLAC (`leaveStream`): deadwax relays that at once, where an MP4
  could mean a make first.
- **AirPlay**: a stream can't go to AirPlay. `showAirPlay()` leaves the stream in the same tap, then
  shows the picker (a Mac wants a second tap). Availability events are ignored while
  `disableRemotePlayback` is set - WebKit says "none" then - and no stream starts while wireless.
- **The readout**: a join reads `in one stream`, 0 ms, or the stall from 'waiting' to 'playing' if
  the stream waited there; the seek line ends ` · in one stream`.
- **Engine off**: three failures with no stream playing in between, or a 503 with scope "server",
  and no stream is tried for `ENGINE_OFF_MS` (10 minutes); the second player meanwhile.
- **Verified in the real page** (Chromium, the stub Navidrome, 8081): recorded through Web Audio, an
  album's signal ran 39.7776 s against 39.7777 expected, the largest residual 0.00004, no spikes;
  joins at 0 ms; the lock screen's title switched within 250 ms of each join; Mixed (FLAC then MP3)
  handed over to the MP3 on the standby in 46 ms and went on the URL way; hi-res went the URL way; a
  seek in song 2 landed exactly (19.100 = 16.3218 + 2.778); "previous" restarted at the song's own
  start on the same source; deadwax repackaged each song in about a millisecond; and, after the
  review, a 25 s pause then play carried on in the same stream.
- **NOT verified - the phone's to answer**: deadwax's own build on an iPhone at all (the lab proved
  the recipe, not this code); the lock screen's title and scrubber per song; seeks, Next and
  Previous from the lock screen; leaving for AirPlay; the fetching pattern against the real cache
  over WireGuard.
- **Play on the lock screen after a long pause does nothing until the app is opened** (James, on
  the lab and on the player as it was): iOS suspends a paused web page - WebKit releases the
  page's MediaPlayback assertion once nothing plays, and remote commands queue to the suspended
  web process until something wakes it. Not fixable cleanly from a page; the one loophole, never
  pausing (playing silence), keeps the phone awake and the lock screen claiming a song plays. So
  it's in troubleshooting, not worked around.

##### After review (the stream)

A review in four lenses (engine, player, server, tests), each finding checked by a skeptic who
wrote a failing scenario first. Everything confirmed was fixed:

- **A later song's trouble cut the song playing** (major). A piece of song N+1 answered changed,
  refused, fatal or engine-off, or an append error on its bytes, failed song N+1 at once, and
  usePlayer loaded it: up to ~28 s of song N lost. Now `pieceFailed` for a later song, while the
  playhead still has music (`!waitingOn`), ends the run before it (`endAt(index - 1)`) and removes
  whatever of it was appended (`cutAt`: `remove(start, Infinity)`), so `endOfStream` can't stretch
  the timeline over it; a 404 or 415 also marks it refused. An append error on a later song marks it
  refused and fails the song PLAYING as `'broken'`, which leaves the stream from where it was: both
  engines give up the whole source on an append error. `streamFailed` moves the queue on only with
  the playhead at the join (`songPosition() >= songLength() - 0.5`) and never for 'decode' - a
  second guard, which the engine fix means never fires. `endAt` now reports `runEnded` again
  whenever the end moves earlier; reported once, the standby kept the song after the OLD end.
- **A seek to a song's last moments stalled** when nothing was placed after it: both `covered()`
  checks asked for 50 ms past the song's end. Now `Math.min(target + 0.05, song.end)`.
- **Resuming after a pause was taken for stuck**: the watchdog's clock moved only with the
  position. `progressed()` refreshes while paused, and `play()` ticks the stream before
  `audio.play()`, for a locked phone whose timers haven't run.
- **The head's first fragments were fetched twice** for any CD song (the lead was used only when a
  whole piece fitted in it): they're appended from the lead, and the first ask starts after them.
- **A second split lost the first split's other half**: `rest` is a queue.
- **`get()` read a whole 200 before looking at it** (a changed song's entire file): the status
  first; only a 206, capped at what was asked, or a 503's first 4 KiB (its scope) is read.
- **"Three failed streams in a row" meant three without a crossing**: reset when the engine goes off
  and on 'playing' with a stream.
- **Next into the run's last song never readied the song after the run**, and `runEnded` started
  that download at once beside the stream's first fill: `preloadSoon()` in both.
- **The next song's head was asked a whole song early**, so with a small cap it looked idle (only
  its head served) when the song after it was made, was cleared, and its first piece got a 503.
  `lookAhead` now waits until the feeding is within `FILL_TO_S` of the last song's end, about a
  minute before the join; a song that can't join is still known at once.
- **Server: a made file bigger than its FLAC cleared the song being played.** Room is made at the
  FLAC's size, and `_evict` then trimmed the MP4's few KiB of boxes off whatever was served longest
  ago - with a small cap, the song on the playhead, and two songs played in turn re-made a whole song
  per piece. `_evict(over=)` never clears a song in use for that overhead.
- **Server: a disk short for ONE long song turned streaming off for 10 minutes and wiped the idle
  songs.** `Room.SHORT` (503, scope "song") when clearing every idle song still wouldn't be enough,
  and then nothing is cleared; `Room.DISK` (scope "server") only when even a small song
  (`SMALL_SONG_BYTES`, 16 MiB, or this one if smaller) wouldn't fit with everything cleared.
- **Kept as it was**: a first song whose head takes more than about 25 s is left for the URL way
  (the watchdog doesn't count a head on its way). Waiting out the 90 s header timeout would be longer
  silence, and on the NAS a make takes about a second.
- **Tests**: player.sim.cjs gained the skeptics' probes and a check per fix - a later song's 404,
  401, change and append error at two points in a 4-minute song, a run cut after its end was known,
  If-Range on every piece, a seek to the end with a minute left, pause and play just before a
  watch, slow first heads, when the next head is asked, moving inside the stream, the Opus song
  after a run, a last song too short to be seen, gestures, AirPlay, the lock screen, a stalled
  body, flaky pieces, 503s, failures not in a row, sample-exact joins, the lead, double splits -
  and `check()` shows a MediaSource by its kind instead of crashing on `JSON.stringify`. Sixteen
  mutations, one per fix, were each caught, three of them only together with a partner they back
  up: the seek's wait-stage check (the append stage), the append error's blame (`streamFailed`'s
  join rule), and the tick before play (progressed-while-paused, since the sim's timers run). Three
  new tests in test_player_cache.py catch the three server mutations.

#### Maximum quality: hi-res resampled to 48 kHz (1.1.0-player.6)

James, on 24/192 Dark Side of the Moon never going into the one stream (formatStreamable admitted 48
kHz and below): "let's transcode it down to 48khz and push that under one condition. I don't want to
lose any sound quality ... let's make it a setting in the app, a maximum stream quality." Then: "if
it's possible to keep 24/192, obviously that would be preferrable". The guide's section is
`docs/player.md#maximum-quality-hi-res-at-48-khz`. The design, the research and every measurement are
in the session scratchpad's `resample/` (SPEC.md, research_ios.md, research_libs.md, verify_audio.md,
review_confirmed.md); what matters is below.

- **The setting**: `deadwax-player-max-rate` ('48000', the default and anything invalid, or
  'original'), per device like the Gapless switch, in a sheet from the gear beside the Library title
  (`ui/src/player/Settings.tsx`, `role="radiogroup"`, focus kept and returned - WebKit doesn't focus a
  tapped button, so the gear focuses itself first). **Moved in 2.0.0-player.9** to You > Playback
  (`app/QualityChoice.tsx`, the same words, key and keys); the sheet and the gear are gone - see
  "The one app". It applies from the next song started or got ready; a stream keeps the setting
  it started with (its `urlOf`, `streamable` and format gate are fixed at `startStream`), and
  `fitStandby()` lets go of a standby readied at an address that changed.
- **What is resampled, and the one rule both sides share**: FLAC at 88.2/176.4/352.8 kHz -> 44.1 and
  96/192/384 -> 48 (whole ratios 2, 4, 8 only), 16 or 24 bits (libsndfile 1.2.2 can't open 20- or
  32-bit FLAC), 1-2 channels. `RESAMPLED_TO` exists in `src/resample.py` AND `ui/src/lib/streamWrap.ts`
  (`resamples()`); keep them in step. The page knows a song's rate from Navidrome's OpenSubsonic
  `samplingRate`/`bitDepth`/`channelCount` on getAlbum's songs (read in Navidrome's source:
  osChildFromMediaFile, sent to every client not listed as legacy) and asks with `max_rate=48000`:
  `wrap=mp4&max_rate=48000` in ANY browser (Chromium plays FLAC in MP4) and the stream's
  `wrap=fmp4&max_rate=48000`. A song with no rate from Navidrome is asked as before. The server reads
  STREAMINFO and decides; a song it doesn't resample is answered from the SAME file, same ETag, as
  without max_rate.
- **Why this keeps the condition (research_ios.md, with sources)**: Apple says an iPhone plays at most
  24/48 natively; speaker, AirPods (lossy AAC anyway), Apple's adapters and AirPlay run at 44.1/48, so
  iOS converts hi-res itself - and its conversion of a 96 kHz file was measured rolling off 3.5-4.5 dB
  near 20 kHz (older iOS). WebKit never calls setPreferredSampleRate, so whether a USB DAC ever gets a
  song's own rate from Safari is unknown - "Original" is for that. libsoxr VHQ in float64, measured
  independently (verify_audio.md): 20 Hz-20 kHz within 7e-9 dB and 6e-10 rad, no delay, polarity kept,
  -0.01 dB at 22.24 kHz (20.44 at 44.1), aliasing >= 184 dB down, 24-bit rounding +-0.5 LSB, matching
  a from-scratch float64 sinc and ffmpeg swr to the last bit. Undithered on purpose (deterministic,
  lowest total noise; spurs at -152 dBFS at worst, 30 dB under any DAC).
- **3 dB of headroom on every resampled song (`HEADROOM_DB`), never a per-song gain.** Removing the
  ultrasonics pushes a hard-clipped master's peaks past full scale: measured 0.77-1.73 dB at 6 dB of
  clipping, up to 2.87 at 12, one stretch of a real 24/192 recording clipped 18 dB at 3.11. The first
  cut lowered only the songs that went over, by exactly enough - and every join between a lowered
  song and an unlowered neighbour then stepped by that gain (about 11 % of the waveform at 1 dB, a
  tick). One fixed gain for every song keeps the joins exact and costs level only, which is what the
  phone's own float volume stage does when it converts hi-res itself. A song past even 3 dB gets a
  second pass, lowered exactly enough, and a WARNING naming the step at its joins. The headroom is in
  the cache key. Don't "tidy" it back to a per-song gain, and say so to James if he asks why 48 kHz
  is quieter: match levels before comparing.
- **The joins: context and one grid.** Resampling a song on its own treats the silence around it as
  music - measured -24 to -6 dB error at every join of continuous music. So each song is resampled
  with the last 16384 input samples of the album's song before and the first 16384 of the song after
  (enough at 8:1; 1024 does at 2 and 4), on ONE grid for the album: phase = `(-earlier) % ratio`
  (the NEGATIVE of the earlier same-rate tracks' total samples - the plus sign joins at -14.7 dB, one
  sample long), output count `ceil((N - phase)/ratio)` (soxr alone gives floor(N/ratio + 1/2), so
  zeros are flushed after), next phase `(phase - N) % ratio`. Then the songs concatenate to one
  resample of the whole album: -207 dB (float64), 31 of 32 joins 0 LSB within 10 ms, the rest 1 LSB.
  `src/album_context.py` finds the album through the client's internal calls (getSong, getAlbum,
  STREAMINFO by small range reads - NOT player routes; test_there_is_no_general_proxy is unchanged),
  single-flight per (version, cap), sticky when Navidrome hiccups, bounded on the cache's clock. A
  song Navidrome answers for but won't serve is off the grid; Navidrome not answering at all means
  the song is resampled alone, logged once.
- **A made file is keyed by the context it actually got.** The plan (phase, neighbours) is in the
  cache key; a neighbour read that failed during the make used to leave a clicking file under the key
  promising that context, for good, and a later re-make put different bytes under the same ETag.
  Now the file is stored under the plan with that side removed, and that make is remembered for
  `LOST_SECONDS` (10 minutes): every fresh start in that time is that file, with no context read,
  and a play after it tries again. Ten minutes, not VERSION_SECONDS, because the re-check found both
  ends of a 30 s memory wrong: a song got ready minutes ahead (the standby, the warm-up) began on
  the file made without the side, then the handover's readout probe made it again WITH the side and
  Safari's element carried on into the new file at the old offsets; and a neighbour whose reads
  always time out cost a 10 s wait at every song change. The pins keep up to `PIN_FILES_KEPT` (4)
  fragmented MP4s per URL, so two phones on the two files of one song each stay on their own. A
  stream copy that isn't whole (cut short) is cleared and the MP4 made the ordinary way, never
  refused for it.
- **Context decoding goes through soundfile's PUBLIC API**: whole frames found with flac_mp4's header
  rules plus next number plus CRC-16, put in a minimal FLAC of their own ('fLaC', STREAMINFO as the
  only block with total_samples = those frames' samples and the MD5 zeroed, the frames untouched and
  numbered wherever they are). A raw prefix or a tail with the original STREAMINFO fails in libsndfile
  ('lost sync', 'psf_fseek failed'); the rebuilt one was exact in 1120 randomised decodes. The frame
  search has a false-sync budget like flac_mp4's: without it a crafted neighbour made the search
  quadratic - measured 27 s at a 16 KB frame and days at what CONTEXT_READ_MAX allows, in worker
  threads that `wait_for` abandons but can't stop.
- **The make** (`src/player_cache.py`): download, context (outside both gates), the resample under its
  OWN lock (a resample holds a block, not the song, and can run a minute on a NAS - another phone's
  50 ms repackage mustn't wait behind it), then the repackage under the old gate; cancellable through
  a threading.Event set by `_to_the_end`. The resampled FLAC is written through Python's own file,
  since libsndfile by path raised RuntimeError mid-file on a full disk and NOTHING at the last frame
  (a truncated FLAC); refused writes surface as ENOSPC, so the old retry clears room and resamples once
  more. WRAP_MAX_BYTES and the cap's reservation are judged by the estimated OUTPUT (the source streams
  from disk). A song damaged part-way is refused and remembered. An MP4 of a resampled song whose fMP4
  is cached is made FROM the fMP4 ('fLaC' + dfLa STREAMINFO + the frames) - no download, no resample -
  which is what lets leaving the stream carry a resampled song on at the same level.
  `X-Deadwax-Resampled: 192000-48000` rides on every answer of a resampled file (200, 206, 416);
  `_answered`/`_pinned` are keyed by (song, cap), and Chromium's `bytes=0-` long after the URL's last
  answer is a fresh start, not a carry-on. numpy/soxr/soundfile are imported lazily: without them
  max_rate is ignored, logged once, and the resample tests skip - except one that fails when CI is
  set, so CI can't skip them silently.
- **The page**: the stream joins only across the same SOURCE rate (the header's `from`, else the head's
  own rate): a 96 kHz song and a 192 kHz one both come out 48 kHz with no context between them. Under
  "Original" hi-res FLAC (1-2 ch, 16/24, up to 384 kHz) joins the stream as it is - an iPhone holds
  ~8 s of 24/192, so it runs ~4-5 s ahead; a first-of-run decode failure at that rate keeps the song
  out of Original streams only, not refused. A resampled first song's pending head gets
  `RESAMPLE_HEAD_WAIT_MS` (60 s) before the stuck watchdog gives up. With the Gapless switch off or
  while AirPlaying, nothing got the next song ready, so every hi-res change waited for a whole make:
  `warmSoon()` holds a `bytes=0-1` ask for the next song's resampled copy from 3 s into each song
  (held, since a make nobody waits for is cancelled). The warm-up is kept while its song is next and
  resampled, whoever else asks for it, so the standby's download joins the same make; it is let go
  when a stream will play the song; and when AirPlay starts while the standby downloads, the warm-up
  takes the make over by asking AT ONCE (`warmSoon(0)` doesn't wait a tick), since deadwax may notice
  the standby's hang-up at any moment of its half-second check - the sim's `makeGraceMs: 0` pins that
  ordering. A refused resampled copy falls back to the
  song's ORIGINAL address (its MP4 in Safari), not the raw FLAC. Readout: ` · in one stream, 192 kHz
  resampled to 48 kHz`, ` · FLAC in MP4, 192 kHz resampled to 48 kHz`, ` · in one stream, 192 kHz`.
- **Found in the real page, fixed with it**: every album's LAST song fetched again the fragments its
  head had brought - lookAhead ends the run, endAt pumps, and the outer pump then acted on a stale
  want. `pump()` counts its calls and stops when another ran inside it; a sim check fails without it.
- **Reviewed**: four lenses and a skeptic per finding; 25 confirmed and fixed (the context-keyed
  files, the false-sync budget, the warm-ahead and the level jump on leaving the stream were the four
  major), each with a test that fails without it.
- **Verified in the real page** (Chromium, the stub Navidrome with a continuous 24/192 album split at
  non-multiples of 4 samples, deadwax with the audio libraries): under Up to 48 kHz every head asked
  `max_rate=48000` and came back `192000-48000`, each song resampled in about 0.1 s, the joins read
  0 ms, and recorded through Web Audio the tone came out at exactly -3 dB with the residual at both
  joins -93 dB, the same as mid-song (a click would be -10 to -30); under Original, full level, no
  header, joins -95.7 dB, the readout `in one stream, 192 kHz`. The settings sheet checked with real
  clicks and keys.
- **NOT verified - the phone's**: any of it on an iPhone; how long the first song waits on the NAS;
  whether an iPhone streams 24/192 FLAC at all under Original; the image's real size with the wheels
  (numpy 2.5.3, soxr 1.1.0, soundfile 0.14.0, cffi, pycparser: about 75 MB installed, measured
  outside docker - python:3.14-slim already has libstdc++6, libgcc-s1 and zlib1g).

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

### The one app (2.0.0-player.9)

James decided (2026-09-29) that the player and the requester become ONE app: five tabs, You at the
right end, Get showing sources by default, Home open. The plan that builds it slice by slice at
`/player/` was synthesized from three designs (the session scratchpad's `uplan/plan.md` and
`slices.md`). This is slice 1: the five tabs with the player inside them, the restyle to STYLE.md,
the `/deadwax/me` seam, and disc titles on the album page.

- **Where it lives: `/player/`, grown in place, for good.** The same page, `#player-root`, entry
  (`deadwax-player`) and manifest (`start_url` and `scope` `/player/`), so James's home-screen icon
  and its per-device settings (`deadwax-player-*`) carry on with nothing to add again.
  `player/main.tsx` renders `<App/>` from `ui/src/app/App.tsx`. Nothing changed in vite, rolldown,
  app.py's prefixes or the gzip exceptions: `/player/` was already revalidated. One new stylesheet,
  `interface/player/app.css`, linked after player.css. `tests/test_pages.py` holds, through
  `start()`: each hand-written page's `/dist/<name>.js` to a vite input (a mismatch was a silent
  blank page), every linked stylesheet and what it `@import`s to something served, the manifest to
  `/player/`, app.css to no-cache and gzip, and no page or stylesheet to a Google Fonts address
  (the boards link one; deadwax self-hosts Noto and runs offline). The main page at `/` is
  unchanged: it stays the desktop tool for searching, downloading, editing, the review queue,
  server settings and the log until the app covers them.
- **The route model** (`lib/appRoutes.ts`, pure, pinned by `routes.sim.cjs`). The hash, since
  StaticFiles has no fallback for page routes: `#/home|library|search|requests|you`, and pages
  pushed on a tab as `#/<tab>/album/<id>` - and, since 2.0.0-player.13, as
  `#/<tab>/group/<rgid>?release=<mbid>`, the album you don't have (`PageKind` 'album' | 'group').
  A group page's `release` (the pressing shown) is in the address but is NOT part of the page's
  identity (`samePage` compares kind and id) nor of where its scroll is kept (`scrollKey`), and a
  pick REPLACES the entry (`router.update` -> `replaceTop`), never pushes one - see "Search, and
  albums you don't have". A legacy `#/album/<id>` is rewritten with replaceState to
  `#/library/album/<id>`; an empty or unknown hash goes to `#/home`.
  - **Per-tab stacks, as in iOS.** A page is pushed on the tab that opened it (pushState, so the edge
    swipe and back work); switching tab replaces the entry with that tab's top page; re-tapping the
    tab you are on pops it to its root, and again at the root scrolls to the top; a double tap opens
    one page. Back labels name the page below: the tab, or the album under this one (`Page.label`,
    never part of the address or of what makes two pages the same).
  - **Going back is history's own back only when the entries below are exactly the pages below,
    made in this session.** Each entry the app makes carries `{n, load}` in history.state - its
    place, and which page load made it - and `HistoryNote.entries[n]` is the address it was given;
    `stepsBack` compares. Otherwise the address is replaced. That is what makes a cold deep link
    work, and what stops a back walking into another tab's page: open A in the Library, switch to
    Home (replaced), open B (pushed), switch back (replaced) - the entry under A is now Home's.
  - **The note survives a reload** (review): it is kept in sessionStorage under
    `deadwax-player-history:<load>` (`saveNote`/`readNote`), and a reload on an entry the app
    made reads its load's note back (`startHistory(place, address, saved)`). Without it, back
    after a reload replaced the address and left a copy of the entry below behind: the next swipe
    showed nothing and only the one after left the app. The LOAD is in the key because the n's are
    only one load's own - a tab that opens /player/ twice has two sets counting from 0, and reading
    the other's note would send `history.go(-n)` into the wrong entries. A load name is
    `Date.now()` and `Math.random()` (not `crypto.randomUUID`, which needs a secure context and
    deadwax is plain http on the LAN); a state from before loads were recorded, or storage
    refused, means entries below unknown, as before.
  - **The browser's own back or forward onto ANOTHER tab's entry is that tab chosen, as it was
    left** (`browserMoved`, review). Switching tab replaces the entry, so the entries below one
    tab's root are whichever tab showed when they were made: back from the Library's root lands
    on an entry Home wrote. Followed literally (`followRoute`) it emptied Home's stack - the entry
    names Home's root - and dropped the album opened there. Now the tab's stack is kept and the
    entry is rewritten to its top page. A web page can't stop that back from leaving the tab; it
    can stop it losing the tab it lands on. Within the tab showing, and for an address typed in
    (no place: it says where to go), `followRoute` as before - except going FORWARD in the tab
    showing (a place past the note's), which puts the pages passed back on top (`forwardTo`, the
    note's entries between of this tab, then the one landed on) and never searches the stack.
    Since 2.0.0-player.10's Go to album one album can be in a stack twice ([X, Y, X]), and the
    search took the lower X going forward, cutting Y and leaving the stack and the history apart
    (review). popstate and hashchange for one move are taken once (the address last shown).
  - **`lib/appHistory.ts` drives it** (`createRouter`): the only thing that touches the history,
    handed `window.history`, `location.hash` and sessionStorage by App, and heard back through
    `show`. It takes nothing from `window` itself, so `routes.sim.cjs` drives it end to end
    against a fake history that keeps entries and state across a reload, fires popstate then
    hashchange, and runs `history.go()` later, as a browser does - the reviewers' scenarios as
    they were reported. `app-rules.sim.cjs` holds App to it: no pushState, replaceState or
    `history.go` of its own.
  - **What stays mounted**: every tab's root, hidden while another shows (the document stays the
    scroller, for the status bar's tap-to-top), and each tab's top page. Scroll is saved per route
    as it is left and restored in a layout effect; a page opened afresh starts at its top. The
    roots are memoised elements, so the music playing re-renders the player's parts and not the
    grids. Sheets are state, not addresses.
- **The gesture rule, and `app-rules.sim.cjs`.**
  - `usePlayer()` is called once, in `App`, which never unmounts. `PlayerContext` carries the player
    (a new object on every change of `playing` and the rest), `ActionsContext` the engine's actions,
    which never change (`pickActions`). Only pages read the contexts; leaf components take props,
    because the fake-Preact sims have no `useContext`.
  - The playback actions (playTracks, toggle, next, previous, setGapless, showAirPlay) are reached
    only from an allowlist: AlbumPage (playTracks), MiniPlayer (toggle, next), NowPlaying (toggle,
    next, previous, showAirPlay), GaplessChoice (setGapless, since 2.0.0-player.10 moved Gapless to
    You), Turntable (toggle, the record's tap, since 2.0.0-player.11 - and since 2.0.0-player.14 a
    release with no coast to wait for, and the deck's two named moves, `holdSong` and `resumeSong`:
    pause as a hand takes the record, play at speed after a coast; app-rules pins those four by
    name, and the deck calls no action itself), Search (playTracks, a song
    found, its album in hand, since 2.0.0-player.13), and `app/context.ts`, which names them and
    calls none. Adding a file is a deliberate edit to the sim, like the Navidrome
    route list.
  - Nothing outside `app/` and `player/` imports usePlayer, the contexts or App.
  - Only App imports usePlayer as a VALUE, under any name (review: `usePlayer as useEngine`
    slipped past the call count), and `app/context.ts` calls none of the actions it names (a
    helper there that fetched and then played would start playback outside the tap for any page).
  - Nothing in `app/` contains setActionHandler, `new Audio`, `<audio`, `.src =`, srcObject or
    `.load(` - comments included, so don't name them in a comment there.
  - **A link out of the app opens beside it** (`target="_blank" rel="noopener"`, review): the
    Search card (until 2.0.0-player.13, and Requests' until .12), You's Managing row and the gate's settings link. Followed in the
    same page, `/` unloads the player - the audio element, any stream and the queue, which
    nothing keeps. From the home-screen app it opens outside the app's scope either way (Safari
    or a browser view over it; not seen on the phone). The sim fails on any `<a href>` in app/ or
    player/ that isn't a `#` link and doesn't open beside.
  - **While Now Playing is open, everything behind it is inert** (review): the panes, the mini
    player and the tab bar sit in one `.app-behind` wrapper with `inert` and `aria-hidden` while
    `sheetOpen`, so neither Tab nor VoiceOver reaches the five tabs under the sheet (activating one
    switched tabs out of sight). NowPlaying moves focus to its close button as it opens (a layout
    effect, before anything else can move it), and App gives it back to what had it (taken in the
    tap, before the page behind turns inert and the browser drops focus from it) - on iOS a tapped
    button never had focus, so nothing is given back there. No focus trap and no Escape: slice 2's
    shared sheet does those. (**Done in 2.0.0-player.10**: every sheet is `app/useSheet.ts`, with
    Escape, and the opener focuses itself in the tap, so there is something to give back on iOS
    too - see "Now Playing as designed, with Info".)
  - **Tiles navigate, never fetch-and-play.** Home's shelf and the Library grid open the album;
    they `prefetchAlbum()` on pointerdown (called off on pointercancel - the press became a scroll;
    taken once by `album()`, kept 30 s), so Play is usually live by the time the page opens, and
    Play is pressed on the page, in the tap.
- **The Navidrome gate narrowed** (`NeedsNavidrome`): drawn inside Home's shelf, the Library tab and
  the album pages only - and since 2.0.0-player.13 Search's library half. The tab bar, You,
  Requests, Search's MusicBrainz half and the album you don't have work with Navidrome unset or
  down. App asks `/navidrome/status` once for every gate.
- **You**: Maximum quality moved from the settings sheet (`player/Settings.tsx`, deleted with the
  gear) to You > Playback as `app/QualityChoice.tsx`: the words, the storage key and the keyboard
  handling unchanged, pinned by `settings.sim.cjs`, retargeted (it read the Gapless label from
  NowPlaying.tsx; from GaplessChoice.tsx since 2.0.0-player.10). Connections: the main page's two pings and Navidrome's status, asked the
  FIRST time You shows, not at start-up (the MusicBrainz ping is a real request to a rate-limited
  service), and on "Check again". About: the version and "logins are off" from `/deadwax/me`,
  asked WITH the pings, so "Check again" asks it again too (review: a first ask failing - deadwax
  restarting under Komodo - left "unknown" there until the app was killed; a failure clears as the
  next ask begins, and a failed ask after a good one keeps the version and says so). The identity
  line says only what deadwax said: nothing when it hasn't answered. Each connection row is its own
  polite, atomic live region (review: one region on the list read out a bare "Connected" with no
  service name, in whatever order the answers came). A row links to `/` for server settings, the
  review queue, the log and editing, in a new tab. Admin rows are gated on `me.admin` (true with
  logins off); Sign out isn't drawn while logins are off. Gapless stays on Now Playing until slice
  2 moves it here (it did, in 2.0.0-player.10: a checkbox above Maximum quality). `you.sim.cjs`
  renders You with deadwax faked and pins all of this.
- **Search and Requests were honest placeholders** ("On the main page for now", with a link),
  Search until slices.md's S4 (2.0.0-player.13, which deleted `app/Placeholder.tsx`; Requests keeps
  its `app-placeholder-*` card classes for its own empty and failed states) and Requests until S3. Home had only "Recently added"
  (getAlbumList2 `newest`, 20 albums): Arriving, Pinned and Not played in a while come in later
  slices and are NOT faked meanwhile. Requests and Arriving came in 2.0.0-player.12 (S3) - see
  "Requests, and what's arriving". **Future slices are named by their slices.md id (S4 Search, S5
  Sources and Get, S6 Artists and the id bridge, S7 Pins, S8 the desktop frame), never a version
  number**: the turntable went in as .11 outside the plan, so every slice after it took the next
  number up, and slices.md's own numbers no longer say which version a slice ships as.
- **`/deadwax/me` and `current_user`** (`src/users.py`, `src/routes/me.py`): a FastAPI DEPENDENCY
  returning `local` - never `@app.middleware("http")`, which hides disconnects. The answer is
  `{user, admin: true, auth: 'off', version}`. Step 3 changes `current_user`'s body and nothing
  else; `test_me.py` overrides the dependency to prove the route reads it.
- **The token section, theme.css section 10 (`--dw-*`)**: STYLE.md's "just a touch of Windows 7"
  as tokens, aliasing what exists - `--font-family` (the self-hosted Noto), `--font-mono`,
  `--accent-hover`, section 7's durations (so reduced motion still collapses them). Nothing in
  main.css reads a `--dw-*`, so the main page doesn't change by a pixel.
  - player.css keeps `--pl-*` for the MECHANICS (safe areas, edges, hit sizes, the sheet's motion,
    the scrubber's sizes, `100dvh`) and points its LOOK at `--dw-*`: Noto instead of SF, STYLE's
    palette, 3/4/6px corners (covers 3), the blur tokens `none` (the sheet's blurred-cover backdrop
    isn't drawn: `--pl-backdrop-display`), shadows no bigger than 0 1px 2px, the scrub track a sunken
    well (a hairline edge, an inset shadow, a grey gradient fill; the round thumb kept), and no
    uppercase or letter-spaced labels (the hero's meta line, the disc headings). The order chips
    are secondary and toggled, Play primary. Layout lives in the rules, so no hit area moved, and
    reverting the look is a token change.
  - The mini player keeps its 64px, its sides and its buttons, and moves up:
    `.app-shell .pl-mini { bottom: <the tab bar> + inset }`, with `.app-shell` padding for both.
    Stacking: the tab bar 8, the mini player 10, Now Playing 20 (and since 2.0.0-player.10 its •••
    menu and Info, 30; since 2.0.0-player.15 the Sources sheet, 25).
  - New chrome is `app-` classes in app.css, tokens only - line heights, the pressed opacity and
    the primary button's pressed filter included (`--dw-leading-*`, `--dw-pressed-cover`,
    `--dw-primary-pressed`, review). `tests/test_app_css.py` reads the rules and fails on a raw
    length, time, line height, opacity or filter outside :root. The Gapless switch is still iOS's
    pill until slice 2 makes it a checkbox in You (2.0.0-player.10 did; the `--pl-switch-*` tokens
    and rules went with it).
  - **Play and pause stay round** (`--pl-radius-round`, STYLE.md; the restyle had given the
    transport buttons the card's 6px, so a press flashed a rounded square).
  - **Focus rings**: one drawn outside what it marks only where there is room (a free button, a
    shelf tile - the shelf keeps `--app-ring-room` above and below its tiles); one drawn INSIDE
    (`--app-ring-inset`) for a row of a grouped list, the tab and the radio, since `.app-group`
    clips with `overflow: hidden` and a ring outside a row there was clipped away entirely.
  - **Keyboard focus scrolls clear of the fixed chrome**: `scroll-padding` on `html`, the tab bar
    (and the mini player, `html:has(.app-shell.has-mini)`) at the bottom and the album page's
    sticky bar at the top - the same room the shell's padding keeps (`--app-chrome-bottom*`). A
    browser counts a control under fixed chrome as in view and wouldn't scroll to it at all.
  - **A phone on its side gets iOS's compact tab bar** (`@media (max-height: 500px)`: the icon
    beside the label, `--dw-tab-item-compact` 32px), since at 844x390 the full bar and the mini
    player covered half the screen. Everything clearing the bar reads `--app-tabbar-height`, which
    is built from `--app-tab-item`, so it follows. The mini player keeps its size.
  - **Home as the board has it**: 12px from a heading to its shelf (`--app-shelf-heading-gap`;
    You's cards keep 6px), and a tile's title and artist in one block with nothing between.
- **The engine guard, on every slice**: `git diff --stat` is empty for `ui/src/player/usePlayer.ts`,
  `streamSource.ts` and `ui/src/lib/{playQueue,gapless,scrub,streamWrap,streamPlan,fmp4}.ts`, and
  `player.sim.cjs` and the engine sims pass untouched. `player/api.ts` may grow route wrappers (it
  gained `prefetchAlbum`/`dropPrefetch`, a `size` for `albumPage`, a `signal` for `navidromeStatus`
  and `discTitles` on the album type; and in 2.0.0-player.10 `rememberPlayed`/`playedAlbum`, the
  album answers Info reads, and `sentFormat`, streamFormat's question put to the engine's own
  element - none of them a route).
- **Disc titles from Navidrome** (James: "make sure the disc titles get picked up from navidrome").
  getAlbum's OpenSubsonic `discTitles: [{disc, title}]` - Navidrome's reading of the `discsubtitle`
  deadwax writes, passed through untouched by `/deadwax/navidrome/albums/{id}` - goes through
  `lib/discTitles.ts`: "Disc 4 · <title>", or "Disc 4" for a disc without one; headings show when
  the album has more than one disc OR any of its discs has a title, so an ordinary one-disc album is
  unchanged; no disc number is disc 1; a blank title, or one for a disc with no songs, is ignored.
  `discs.sim.cjs` pins it, and that AlbumPage reads `album.discTitles`. **A one-disc album deadwax
  filed shows no title** (review): Navidrome records a disc's title only for a disc number above 0
  (`ToAlbum` in model/mediafile.go; a missing tag reads 0), and `tag_values` writes no disc number
  for a one-disc release - so its `discsubtitle` never reaches `discTitles`. The guide says a
  one-disc album shows its title only when its files carry a disc number (Picard's "1/1", or Disc
  set with Disc title in the tag editor), and the sim holds the guide to it. Writing
  `discnumber=1` beside a title on a one-disc release would be a change on MAIN (every titled
  one-disc album gets a one-time disc-number diff) - James's call, not made here.
- **Verified**: 1825 Python tests, pyflakes, tsc, and all 23 sims (routes, app-rules, discs and
  you new); 33 mutations, one per rule pinned, each caught and restored byte for byte - and after
  the review, 27 more, one per fix (each a test failing without it). **NOT verified here**: the
  real page, which the build workaround and a check against the stubs cover after this change;
  and everything on the iPhone - the tab bar (compact on its side), the mini player above it and
  the safe areas under a real finger, a link to the main page from the home-screen app, whether
  Navidrome 0.64.2 sends `discTitles` for James's albums, and the home-screen icon opening the new
  app with its settings kept. The guide's "Not yet verified" list carries the same.
- **After review**: seventeen findings, each confirmed by skeptics, fixed together - the links
  opening beside the app, another tab's entry gone back onto, `/me` asked again, the one-disc
  title in the guide, the reload's note, the clipped focus rings, the live regions, the scroll
  padding, the inert page behind Now Playing, the compact tab bar, the round transport, Home's
  spacing, raw values, the two gaps in `app-rules.sim.cjs`, the unverified claims in the guide,
  the back label promise, and the troubleshooting wording (You shows **Not set up** or **Can't
  reach it**).

### Now Playing as designed, with Info (2.0.0-player.10)

Slice 2 of the one app (`uplan/slices.md` S2). James: "the 'in one stream' and the quality
shouldn't be displayed in the player, at least not by default, but I would like an 'info' tab in
the menu in the player that would show you everything", "I'd like the info to be more about the
song, album, and artist. with maybe a debug tab to show everything there now", and "gapless should
be a switch in the global settings".

- **Now Playing as its board draws it** (`NowPlaying.dc.html`): the cover, the title, "Artist —
  Album" as ONE line in the accent that goes to the album (a button; the same box as a `<p>` for a
  song with no album id, which nothing makes today), the scrubber, the transport, and a row of
  icons: AirPlay while there is a speaker, and ••• always, at the right end. Only what does
  something today: no Lyrics, Up next or turntable buttons, and no "Now Playing opens as" setting
  (the turntable came next - see "The turntable (2.0.0-player.11)"). The two readouts and the
  Gapless switch left it.
- **Nothing whose height can change sits below the title** - the rule from the 1.1.0-player.2
  review, which put the readouts ABOVE the title. With them gone, the one line that comes and goes
  is `player.error` (a failure, the skip notice), and it moved above the title too: it moves the
  cover, never the album line, the bar or the buttons. The album line is one `nowrap` line, a line
  tall even when empty; the icon row is `height: var(--pl-hit)` (not min-height) with or without
  AirPlay, `justify-content: flex-end` so ••• holds its place when AirPlay comes and goes.
  `app-rules.sim.cjs` pins the body's order, `test_app_css.py` the fixed row. The album line's tap
  target reaches 44px through `::before`: up over the lower half of the title (which takes no
  taps) and down into the gap above the scrubber, stopping short of the bar's own target
  (`--pl-byline-reach-*` against `--pl-scrub-gap`, held by the test). The ellipsis is on the span
  INSIDE the button, since clipping the button would clip that reach away.
- **The ••• menu** (`app/ActionMenu.tsx`): the board draws the button, not the menu, so it is a short
  sheet from the bottom over a dimmed Now Playing: Info, Go to album, Cancel. Pin joins it with
  pins (slices.md S7). Go to album is left out, not greyed, for a song with no album id.
- **Go to album** - the menu's row, the album line and Info's album card, one `toAlbum` in App:
  every sheet closes and the album opens on the tab showing, through the `openAlbum` a tile uses,
  drawn at once from the answer it was played from (`playedAlbum`) or the queue's name and cover.
  Focus is not sent back to ••• (its sheet is going): Now Playing gives it to its own opener.
- **Info** (`app/InfoSheet.tsx`, `NowPlayingInfo.dc.html`): a sheet whose top is
  `max(52px, safe-top + 8px)` - the board's 52px is from the top of the SCREEN, status bar
  included - with Done, a segmented control that is a real tab list (the arrows move the choice and
  the focus, one tab stop), and one scrolling panel. The board's grabber isn't drawn: nothing drags
  Info, and a grabber that doesn't is a dead control. Debug's rows follow the board, the label at
  the left and the value at the right end of its line, and a value too long for that goes whole to
  the line under it, at the left (flex-wrap, the LABEL taking the slack - `margin-right: auto` -
  so a value alone on its line has no margin pushing it right). Info stays mounted, hidden while
  closed, so its one scroller would keep its offset: a layout effect on `[open, tab]` puts it back
  at the top as Info opens and as the tab changes, never as it closes (it is still sliding away in
  sight); the tab itself is kept. The menu and Info are placed by the insets (`left`/`right` at
  `--pl-safe-*`, as the mini player is) and capped and centred inside that, their padding the
  board's alone (16px, the menu's 8) - padding by the inset as well put their contents 47px in
  from their own edge on a phone on its side. Each half of the segmented control reaches 44px to a
  finger: its `::before` sits against the half's PADDING box, `--app-segment-edge` (the well's
  border and padding and the half's own border, three hairlines) inside the well, so the reach is
  `--app-segment-reach` plus that edge (it was 38px).
  - **About** (`lib/aboutRows.ts`, pure) asks NO server anything. The queue's `QueueTrack` carries
    only what playing needs (and `lib/playQueue.ts` is the engine's, not to be touched), so the
    album answer a queue is played from is REMEMBERED at the tap: AlbumPage's play calls
    `rememberPlayed(album)` and then `playTracks`, in the same turn, nothing awaited
    (`player/api.ts` over `lib/playedAlbums.ts`, the last `PLAYED_KEPT` (8)). The song: its title,
    its artist, "Track n of N · length" (N counted on the song's OWN disc - numbers restart per
    disc on a set deadwax filed; a number past its disc's count is counted against the album, and
    past that N is left out), and its disc line, read off the album page's own `discHeadings()`
    so the two can't disagree ("Disc 2 · Unreleased Tracks", only where the album page draws
    headings). The album's card: cover, title, and "year · format · N songs" (`sharedFormat`
    moved to `lib/format.ts` for both), going to the album. The artist: the song's, with "The
    album is by X" when the album's own artist differs. **A field Navidrome didn't send is LEFT
    OUT** - no year 0, no "Track 0", no placeholder. With the album answer not in hand, only what
    the queue knows.
  - **Debug** (`lib/debugRows.ts`, pure): the readouts as labelled rows, BUILT ON
    `describeGaps`, `describeSeek` and `describeWrap`, so the phrases the guide explains and the
    engine sims pin ("handed over, from memory", "in one stream", "FLAC in MP4") are still the
    phrases shown - but not line for line: each row drops its line's opening words, and the seek
    line's tail (how the song came) is the Sent as and Resampled rows. Format (OpenSubsonic's
    samplingRate, bitDepth, channelCount; a part not given left out); Sent as (describeWrap's words
    with the depth and rate the song was SENT at - 24-bit at the new rate when resampled, whatever
    the source's depth); Resampled (`192 kHz to 48 kHz, 3 dB quieter`, `RESAMPLE_HEADROOM_DB` held
    to src/resample.py's HEADROOM_DB). **Asked for resampled and not answered yet**
    (`awaitingResample`): an MP4 before its headers (`got` null), or a stream song before its head
    is in (`got` 'stream', `resampled` AND `hiRes` both null - once the head is in, one of them is
    set for any song above 48 kHz) that `resamples()` under the setting - deadwax makes a
    resampled song whole before sending any of it, seconds on a NAS, and Debug is likeliest opened
    then. Sent as drops its depth and rate, Resampled says `Not known yet` and Why "Asked for
    resampled; deadwax hasn't answered yet", where they read "No", the file's own 192 kHz and "or
    deadwax sent it as it is". Why (the
    first reason that holds whatever the setting - the rate, the kind, the ratio, the depth,
    `resamples()`'s own tests, so the two can't disagree - and then the setting, by QualityChoice's
    names, held by the sim: a 44.1 kHz song under "Original" says the rate, not the setting); Gapless (Off, On, On in one stream); Gap (describeGaps less its first
    words, the changes before on an "Earlier" note); Last seek; and **Navidrome sent**: the sorted
    field NAMES of the playing song and of its album, as deadwax's route passed them through
    untouched - names, never values - so the fields slices.md's S6 and S7 want (musicBrainzId,
    played, playCount, composer) can be read off James's iPhone against 0.64.2 first. "Not known"
    without the album answer. **A name alone misled both ways** (review, read in Navidrome
    v0.64.2's responses.go and helpers.go): OpenSubsonic fields without omitempty are ALWAYS sent -
    `musicBrainzId` (song and album), `discTitles`, `displayComposer`, `bpm`, `bitDepth`,
    `channelCount`, `userRating` on an album - as "", [], 0 when the files have nothing; and
    `playCount`, `played` (set only when PlayCount > 0), `starred`, `userRating` on a song, `year`,
    `track`, `discNumber` are omitempty, gone whenever zero or unset. deadwax never writes a
    recording id, so every song it filed sends `musicBrainzId: ""`. So each row puts the names sent
    EMPTY ("", 0, null, [], {} - `isEmptyValue`; `false` is a value) on an "Empty: ..." note, and a
    third row, **On other songs** (`otherSongsFields`), names the fields another song of the album
    carries with a value and this one doesn't: where `playCount` shows for a song never played.
    The answer is the tap-time snapshot (`rememberPlayed`), so a song played since still lacks
    `playCount` until its album page is opened and played from again - the guide says so.
  - **Sent as asks the engine's own element.** Whether a song is asked for as the file or as
    Navidrome's MP3 (`streamFormat`) turns on `canPlayType`, which the engine doesn't expose and
    can't be changed to. `sentFormat()` in player/api.ts puts streamFormat's question to
    `document.querySelector('audio')`, the element the engine made - every element gives the same
    answer - and NEVER makes one (iOS unlocks audio per element), sets nothing and starts nothing.
    It is asked only while Debug is drawn.
  - The rows are worked out only while Info is open; what it last drew stays drawn as it slides
    away.
- **Every sheet is a sheet by one hook** (`app/useSheet.ts` - a hook, not a wrapping component, so
  the fake-Preact sims, which render one component and none inside it, run all of it): **its own
  scroll-lock class on `<html>`** (`pl-sheet-open`, `app-menu-open`, `app-info-open`: one shared
  class would be taken off by whichever closed first, with another still open), focus in to its
  first control before the paint, **focus back to its opener as it closes**, **Escape for the sheet
  on top only** (one with another over it - `covered` - doesn't listen, so one press closes one
  sheet), and, in the markup, `inert` while closed and a backdrop tap. **The opener focuses itself
  in the tap** (`takeOpener`): WebKit never focuses a tapped button, so without it there was
  nothing to give focus back to on an iPhone or in Safari (2.0.0-player.9 gave nothing back
  there). Now Playing is inert and hidden while the menu or Info is over it. The two are never open
  together: choosing Info closes the menu with no focus given back (App leaves the menu's opener
  out while Info is over), and Info gives focus to ••• itself when it closes. The mini player and
  ••• pass their click's event up for this. Stacking: the menu and Info at `--app-z-over` (30),
  over Now Playing's 20.
- **Touch.** `.app-layer`, the menu's and Info's, is `touch-action: none` like `.pl-sheet`, so no
  touch on them pans the page behind; Info's scroller opts out with `touch-action: pan-y` and
  `overscroll-behavior: contain`. A scroller starts its own count (Pointer Events: the touch
  behaviours are those of the elements from the one touched up to the nearest scroller; WebKit's
  style adjuster resets them at an element with scrollable overflow), so the panning comes back
  inside it and nowhere else. **Not seen under a real finger yet.**
- **Gapless is a checkbox in You > Playback** (`app/GaplessChoice.tsx`): the You board draws a
  checkbox, and the app's rule is "checkboxes, not switches". A `role="checkbox"` button, above
  Maximum quality, with a note under it. **Its tap is the
  gesture**: `setGapless` straight from the click, in the same turn - turning it on makes and
  unlocks the second audio element, and iOS unlocks per element from a tap - and a click, never a
  change event. It is the ONE new file on `app-rules.sim.cjs`'s allowlist; NowPlaying lost
  setGapless. You hands it the player itself and names no action of its own. The storage key is
  unchanged (`deadwax-player-gapless`), so an installed app keeps the setting. `settings.sim.cjs`
  renders it and holds the call to the tap, reads the label from GaplessChoice.tsx now, and holds
  Maximum quality's notes to "with Gapless on" (they said "the Gapless switch").
- **Docs**: player.md's "The readout" became "Info → Debug", with every row, and every "switch"
  went; troubleshooting has a new entry saying where the readouts went (and how the wording moved),
  and its Gapless and seek entries name the rows; configuration's device table and the README say
  where Gapless is. The skip notice is now said to sit above the title.
- **After review**: twelve findings, each confirmed by skeptics, fixed together. The two in
  Debug's words and the router's are above (Navidrome sent's empty and missing names, a stream
  song not answered yet, forward onto a duplicate page). Also: Info's list reopening where it was
  left; the segmented halves 38px to a finger, and a test whose arithmetic vouched for 44; the menu
  and Info padded by the notch inside a sheet already clear of it; `app-rules.sim.cjs`'s "one
  handler for all three" answered by the NEXT element's props (a lazy `[\s\S]*?` running past
  `/>` - now each element's own props, `propsOf`, and the opener and open checks the same way);
  debug.sim missing a 16-bit resampled source and an MP4 outside a stream with Gapless on; info.sim
  missing a track number past the album's count, the album's cover over the song's, and a song
  count with no songs; player.md's step 7 saying Original applies "from the next song" (a stream
  keeps its setting - start again from a tap); and the docs saying the rows keep the old lines'
  words, where they keep the phrases and moved the rest.
- **Verified**: 1833 Python tests, pyflakes, tsc, and all 25 sims (debug and info new); 59
  mutations, one per rule pinned here, each caught and restored byte for byte - four of them first
  got past a test (Why's order, the menu's backdrop) or failed it only by a crash (Info's backdrop,
  the checkbox's role), and the tests were tightened until each failed on a check - and after the
  review, one or more per fix, each failing a test without it. The engine guard is empty and
  `player.sim.cjs` untouched.
  **NOT verified here**: the real page (the build workaround and a check against the stubs come
  after this change) and everything on the iPhone - Info's scroll and the page not moving under a
  finger, a tap above Info closing it, focus coming back with VoiceOver, the Gapless checkbox
  unlocking the second element from its tap, and what the Navidrome sent row says against 0.64.2.

### The turntable (2.0.0-player.11)

(Part of this is superseded by 2.0.0-player.14 - see "The turntable, part two": the CSS spin and
`--dw-record-turn` are gone, the platter turned frame by frame by player/deck.ts; once the record can
sound where it is - the deck's audio context running, a voice ready to play it and a window of the song
there in it (2.0.0-player.16; until then it was only "the context runs", which was James's silent
turntable - see "After James's report") - a press pauses the song and its turn counts from where the
record was taken, the release lands where the platter's momentum says, and the record has its own
sound; a pause from the turntable winds down. Until it can, a press is exactly what is written below.)

James: "I would like to definitely build the turntable" - on the phone ("I don't think it makes a
lot of sense on desktop") - "as long as it has the disc art on the 'record'"; earlier, "the playhead
moved toward the center of the disc as the song plays, tapping on the disc and rotating it is how
you seek, and maybe the skip and other things are at the bottom", "a toggle somewhere to go between
the apple music style and the turntable style", and of the board's first-time hint, "the
instructions for how to use it are a little annoying". The boards are `NowPlaying.dc.html` and
`Turntable.dc.html` (its DCLogic is where the drag maths came from), and `You.dc.html`.

- **Two looks, one sheet.** A button at Now Playing's top right (`.app-look-button`, a 44px target
  holding the boards' 36px secondary box) switches the cover and the turntable - a record icon on
  the cover, a square on the turntable, labelled with the look it switches TO ("Show as a
  turntable" / "Show the cover", `lookButtonLabel`). You > Playback's **Now Playing opens as**
  (`app/LookChoice.tsx`, a radio group exactly like Maximum quality's, between Gapless and it) says
  which it opens as: Cover (the default) or Turntable, per device under `deadwax-player-opens-as`
  (`readPlayerOpensAs`: the turntable only when it says exactly that). **App keeps only the
  SETTING** (`opensAs`, handed to You and to Now Playing); **the look showing is Now Playing's own
  state**, reset to the setting by a layout effect as the sheet opens, every time - so the button
  never changes the setting, and switching re-renders the sheet and never App or the engine.
- **Gesture ownership: the record and the arm are OUTSIDE the grip.** On the turntable the grip is
  the top row alone (`.pl-sheet-grip.app-grip-top`, `flex: none`), and `<Turntable>` is drawn after
  the grip closes, as the grip's sibling - so neither starts the sheet's drag and the sheet's drag
  never starts from them, with no stopPropagation to forget. On the cover the grip is the top row
  and the cover, as before. `app-rules.sim.cjs` counts the divs to hold it; the turntable sim finds
  no Turntable inside the grip's tree.
- **The record's face is the album's CD art**: deadwax's own `disc.<ext>`, or `disc<N>.<ext>` for
  the playing song's disc (the disc number from the album answer the queue was played from -
  `playedAlbum`, `playingDisc`; 1 when unknown, since a one-disc album deadwax filed carries none),
  else the unnumbered `disc.*`. With none - a 404, or while it loads - plain black vinyl with the
  grooves and the album's COVER as the round label (the board's `discArt=false`). The label hides
  (`has-art`) only once the art has LOADED: CD art is often a transparent PNG, and the cover would
  show through its hole. An image that failed is remembered by ADDRESS, as `Cover` does, so the next
  disc's is still asked for - and only while Now Playing stays open: **each opening asks again**
  (an effect on `open`, not on mounting - with the setting on Turntable the turntable stays mounted
  across a close, and a failure kept by the mount alone made "close and open it again" in the docs
  untrue and latched a Navidrome blip until the look was switched twice).
  - **Only the `disc` stem, never a download's `cd.jpg`** (`disc_face` in src/disc_art.py): that is
    whatever its sharer scanned, and Get CD art is still offered beside it (a `cd*` file doesn't
    hide the button) - so the face is what Get CD art gives, and nothing else.
- **The route: `GET /deadwax/library/disc_art/navidrome?album=<Navidrome album id>&disc=<n>`**, with
  the library routes - NOT a Navidrome relay, and `test_there_is_no_general_proxy` is unchanged.
  The phone knows only Navidrome's id, so deadwax finds the file: getAlbum's `musicBrainzId` (the
  `musicbrainz_albumid` tag as Navidrome read it) through the internal `navidrome.call()`, as
  album_context.py calls it; every live folder the store index has for that release
  (`store.index_present` - two or more for a set stored one folder per disc, so disc N's own
  picture in any of them beats a shared one in an earlier one); and the picture from each folder's
  own listing. The id is only ever Navidrome's `id` parameter, never joined onto a path. Every guard
  `/disc_art` has - each folder `is_within` the library, resolved (a symlink out is refused), and
  only names `find_disc_art` counts, found in the listing - plus one: the chosen file must resolve
  inside its folder. **A folder the index has that is simply gone** (renamed or deleted outside
  deadwax, before a scan noticed) is NOT a refusal: the paths are deadwax's own index, never the
  caller's, and warning of one "outside the library" (as the first cut did, on every showing) sent
  whoever read the log hunting for a traversal. It is logged at debug and marked `missing`, as
  `held_copy` marks one (the next scan, or the folder coming back, revives it); only a folder that
  resolves OUTSIDE the library is warned of. **`/disc_art` itself follows a symlinked FILE out of the folder** (`_listed`
  takes `is_file()`, which follows links) - noticed here, a gap main has too, left for main per
  "a bug main has too is fixed on main first". Served by the same `_disc_art_answer` (typed by
  extension, `private, max-age=300`), and a media answer: `MEDIA_PATHS` in app.py (GuardMedia's
  headers, never gzipped). **404 for every "none"**: no LIBRARY_PATH, Navidrome unset or down or not
  knowing the album (a NavidromeError is caught), no release id, nothing indexed, no CD art - the
  page draws the plain record. A 404 carries no caching, so CD art saved meanwhile shows the next
  time Now Playing opens on the turntable (or the look is switched to it).
- **The drawing and the maths are one set of numbers** (`lib/turntable.ts`, pure): the board's
  geometry in the plinth's units (`STAGE` 372 x 368, `RECORD`, `PLATTER`, `GROOVES` 148 -> 64,
  `ARM` pivot and reach 205, `ARM_PARTS`), drawn as percentages inline and as two SVGs on the same
  viewBox (the platter under the record; the arm over it, `pointer-events: none`), with the record
  a real `<button>` and the arm's handle an HTML slider on top. The stage is as big as fits the room
  both ways (`container-type: size` on `.app-tt`, `min(100cqw, 100cqh * aspect, 440px)`, the aspect
  inline from `STAGE`), the width alone where container units aren't known.
- **The arm follows the song** (usePosition, like the scrubber - no timer of its own): the needle is
  where a circle of the groove's radius round the record's centre meets the arm's reach round its
  pivot (`needleAt`), about 99 to 122.5 degrees across a song. **Dragged, the angle says the time**
  (`armTimeAt`), held to the arm's sweep - past either end is the song's start or end, never the
  circle's far side where the reach meets the grooves again. The head lifts while held. **Nothing
  moves until the finger has travelled `TAP_SLOP_PX`**: the needle stays over the song as it plays
  (`time: null`), so a nudge shows nothing it won't go to. The first cut previewed the arm from the
  first move and seeked only past the slop - and the whole song is about 83 CSS px of needle on a
  390px phone, so 8px was 40 seconds shown and then silently dropped, the arm snapping back. **The
  move that crosses it takes hold** (`grab`): the song where it is THEN is put at the slop's edge
  along the finger's way, so the arm moves on from the song with no jump - not the 40 s a grab
  from the press would jump, and not losing the tens of px a quick finger's first move can cover
  (a grab at the crossing finger would). From there it keeps that grab, so it never jumps to the
  finger either.
- **Turning the record: 1.8 s a turn** (`SECONDS_PER_TURN`, 33 1/3 rpm), forwards clockwise and
  backwards too; each move's turn is the short way round (the atan2 seam at the left is a small
  turn, not a whole one); nothing counts inside `SPINDLE_SHARE` of the centre, where the angle
  swings wildly. The record turns with the hand (an inline rotate on `.app-tt-turn`, kept where the
  hand left it on release) around the CSS spin. **A turn is an OFFSET** (`offset`, seconds) **from
  wherever the song is when it lets go**, because the song PLAYS ON under the finger - only the
  record stops. The board anchored to the time at the press, which works on the board because its
  clock stops while the record is held; here it seeked back behind what was playing - three
  seconds for a finger that rested three seconds before turning, and short of the song for any
  forward turn slower than 33 1/3 rpm, which is most of them. The offset is clamped at each move
  against the song as it is then (turning back past 0:00 holds it there, and forward moves it at
  once - the board's behaviour).
- **Letting go seeks exactly what is shown**: `dragEnd` seeks `shownTime(preview(drag), position)`,
  the same sum the arm and the time line draw, from the song's position as last drawn
  (`drawnAt`, the render's usePosition). A record turned by nothing (round the spindle, or dragged
  straight out) seeks nowhere. **A drag is measured in the stage's box as the press found it**
  (`pressBox`): anything that moves the layout under a still finger moves nothing.
- **Seek on RELEASE only** (and, since 2.0.0-player.14, as a tap's pause winds down - to where it stops), through the player's own `seek` (the scrubber's path): the drag previews
  the time (the time line, "Scrubbing · 2:31 of 7:05" or "Needle up · ...") and turns the record,
  and the audio does not scrub - that is a later slice. Keys on the arm step as the scrubber's
  (`keyTarget`). A cancel seeks nowhere and a drag begun on a song that has since changed is
  dropped (`dragEnd`/`dragFor`); another finger moves and ends nothing (`recordMove`/`armMove`/
  `dragEnd` compare pointer ids) and STARTS nothing - `recordStart`/`armStart` take any pointer, so
  that rule is the component's (`pressable`: `isPrimary`, and no right-click). Both drags capture
  the pointer. `app-rules.sim.cjs` holds `player.seek` to `onRelease` and `onArmKey` alone.
- **A tap plays or pauses, from the CLICK, in the tap** - the transport's way, and the one new file
  on `app-rules.sim.cjs`'s allowlist (`player/Turntable.tsx: toggle`). A press that never travels
  `TAP_SLOP_PX` (8, the furthest it got, not where it ended) is a tap: it seeks nothing. A press that
  does is a drag, and the click after it is NOT a tap (`turned`). **The flag is set by the MOVE that
  takes a turn past the slop**, not only by its release: a drag dropped because the song changed
  under it has no release that says so, and a mouse's click still comes (Chromium sends it to the
  element holding the pointer) - so the first cut paused the new song. **It is cleared by the next
  primary press**, because not every drag has a click after it (WebKit synthesises none after a
  moved touch): cleared only by a click, it would swallow the next real tap. A second finger is no
  press, and doesn't clear it.
- **No per-frame work while the page is hidden.** (2.0.0-player.14 turned the platter frame by frame
  in player/deck.ts instead, under the same rule - no frame while closed or hidden.) The spin is a CSS animation on `.app-tt-face`,
  `animation-play-state: paused` unless `is-spinning`, which is `spinning()`: playing AND Now
  Playing open AND the page showing (`useVisible`, on `visibilitychange` - a locked phone) AND no
  finger holding the record. Paused, it stays where it is. Nothing runs from the engine's clock and
  there is no rAF loop (the sim fails on rAF, setInterval or setTimeout in Turntable.tsx). Reduced
  motion: `animation: none`. **`--dw-record-turn: 1.8s` is its own token**, never a section 7
  duration: reduced motion collapses those to 1ms, which would spin the record 1800 times faster
  instead of stopping it (theme.css's universal rule also clamps any animation to 1ms and one
  iteration). The sim holds the token to `SECONDS_PER_TURN`.
- **The time line replaces the scrubber** (`TurntableTime`, mono, centred, one `nowrap` line - the
  body sits against the bottom, so its height must not change), the title and album line centred as
  the board sets them; the transport and the icon row are the cover look's. Now Playing holds the
  preview (`onPreview`), which Turntable clears as it unmounts (pinned: unmounted mid-drag, the last
  word is null). **The failure line is laid over the plinth's foot on the turntable**
  (`.app-is-turntable .pl-sheet-error`: absolute above the title, two lines at most,
  `pointer-events: none`). In the flow, above the title, it took its height from `.app-tt`, and the
  stage (`100cqh`) shrank with it - on any height-limited phone (375x667, Safari with its bars, on
  its side) the record and the arm resized and moved when the skipped-song note came or cleared
  itself, and a finger holding the arm jumped about 14% of the song. On the cover that room is the
  cover, which no finger goes to; here it is controls.
- **The arm's handle is a tap target unless the plinth is too small to hold one**:
  `min-width: min(var(--pl-hit), var(--app-tt-handle-cap))`, the cap 30% of the stage. On a phone on
  its side (844x390) the plinth is about 45px and a 44px ring covered 52-85% of the record, its
  middle included: a tap there neither paused nor played, and a small turn dragged the arm and
  seeked minutes away. The cap bites only below a 147px plinth. A real landscape layout is still
  not built.
- **Accessibility**: the record is a `<button>` named for what a tap does ("The record: a tap pauses
  the song" / "plays"), Enter and Space included; the arm's handle is `role="slider"` with the
  scrubber's value and words, out of the tab order and disabled with no length; the look button is
  named for the look it switches to; You's radio group is described by the note under it
  (`app-look-note`: the button switches only until Now Playing closes - why the two can disagree),
  as Gapless is by its own.
- **No hint and no coach mark** (James, above): the board's `firstTime` tweak is not built, and the
  sim fails on its words.
- **Deliberately left out**: audible scrubbing (a later slice - built in 2.0.0-player.14); the desktop (James: phone only - the
  app has one layout until slice 8's desktop frame, which is where the button stays out); the
  board's Lyrics and Up next icons, as on the cover.
- **Verified**: 1853 Python tests (`test_turntable_disc_art.py` new: found for disc 1 and 2 of a set,
  the shared fallback, a one-disc album with no disc number, a set stored per disc, a `cd.jpg`
  refused, every 404, the id only ever Navidrome's, a folder and a file linking out refused and
  warned of, a folder gone since the last scan quiet and tombstoned, served as `/disc_art` serves
  one; four new CSS tests), pyflakes, tsc, and all 26 sims (`turntable` new, 127 checks;
  `settings`, `you`, `info` and `app-rules` extended); 51 mutations, one per rule pinned, each
  caught and restored byte for byte - and after the review, 20 more for its fixes (the arm's slop
  and its grab, the record's offset, the flag set on the move, the art asked for on opening, the
  quiet tombstone, the overlaid failure line, the handle's cap, the look note, the arm's capture,
  a second finger, the preview cleared on unmount, the press's box), all caught. The engine guard
  is empty and `player.sim.cjs` untouched.
  **NOT verified here**: the real page (the build workaround and a check against the stubs come
  after this change) and everything on the iPhone - the drags under a real finger with the sheet
  staying put, the spin's smoothness and its stopping while locked, whether VoiceOver drives the
  arm, and whether Navidrome 0.64.2 sends the album's `musicBrainzId` for James's albums (Info >
  Debug's Navidrome sent row answers that).

### Requests, and what's arriving (2.0.0-player.12)

Slice 3 of the one app (`uplan/slices.md` S3, numbered .12 because the turntable went in first).
The boards are `Requests.dc.html` and `Home.dc.html`'s Arriving card. James, of Arriving: "is it
possible to hide arriving when there isn't anything arriving? ... I don't know that I want it to be
persistent all the time".

- **`useDownloadJobs` is called ONCE, in App** - the hook the main page's downloads panel uses,
  unchanged, as is `downloads.sim.cjs`; the old page keeps its own instance (another page, another
  module instance). So the Requests tab, Home's Arriving and the tab's badge are one poll and one
  set of overlays. `app-rules.sim.cjs` holds it to one call there and in no other app file. Its
  `open` is `watching === 'requests' || stalled`. `watchingOf()` (requestsView.ts, pure, pinned)
  makes `watching` from the tab, the depth of its stack, Now Playing and the page being shown: the
  Requests tab's ROOT showing (`nav.stacks.requests` empty - Go to album can push an album on it),
  Now Playing not over it, and the page shown (App's own `usePageShown`, on `visibilitychange`;
  Turntable keeps its own `useVisible`, which app-rules reads there). So it polls every 500ms only
  then, every 5s (1s while filing) while something is active, and otherwise stops, as the hook
  always did.
- **A failed look while something is arriving keeps it asking** (`stallsOn`, review). The hook
  stops for good after one failed poll with `open` off - `hasActive` is false in its catch - so a
  Komodo redeploy or the phone off the VPN for a moment froze Home's Arriving and the badge on the
  last answer until a tab switch. App can't run a timer (app-rules), so `stallsOn(watching, error,
  view.arriving.length)` - on Home or another tab, the last look failed, something on its way - is
  put in state by an effect and ORed into `open`: the hook polls every 500ms until an answer clears
  the error, then the next render turns it off. Arriving says so meanwhile (`trouble`: "Can't reach
  deadwax just now: this is its last answer, and it keeps asking."). **The root fix belongs in the
  hook, on main first** (keep polling after an error when the last good answer had active jobs):
  main's Downloads badge freezes the same way; this is the app's side of it until that lands.
- **Asked again without a poll left running** (`asksAgain` in `lib/requestsView.ts`, pinned): App
  tracks what it shows as `Watching` - requests, home, other, hidden - and calls the hook's
  `refresh()` as Home comes into view (a tab switch, back to its root, Now Playing closing over it)
  and as the page comes back from hidden on any tab but Requests. Never for Requests itself, coming
  or going: `open` changing re-runs the hook's effect, which polls at once - a `refresh()` beside it
  would be a second request, throwing the first's answer away. Nothing on mount: the hook's own first
  poll is there. So a download started on another device shows when you look, which is what the
  plan's "refresh on visibility" was for.
- **App registers `handleDownloadRequests(enqueue)`**, so a Get hands its pending row to the one
  hook. Until Get existed nothing in the app enqueued, so "asking slskd…" and refused rows couldn't
  appear there; the words were pinned for when they did - and since 2.0.0-player.15 they do (see
  "Sources and Get").
- **The grouping and every word are `lib/requestsView.ts`** (pure; `requests.sim.cjs`, 149 checks):
  Downloading (downloading, organizing, and queued with progress - bytes moving before the poller's
  next look), Waiting (asking slskd first, then queued: "#4 in their queue", or "starting" as the
  board says, with "N failed" in amber when the peer has already refused some files - as the old
  panel's `jobDetailText` says it, or it reads as an ordinary wait right up until it fails), Needs
  attention (refusals, then failed and cancelled: the reason in red, "Next peer · N left" from
  `alternatives_left`, "Ask again" always, "Trying next peer…"/"Asking again…" on the button tapped
  with both aria-disabled, the retry's refusal as a second red line), Done (everything
  else, sorted by `updated_at`, newest first, so the ages read in order: "In your library · 12
  minutes ago"). "try N" from `attempt`. Each section only with rows; the page draws none empty.
  - **ONE solid purple button on the screen** (STYLE.md): only the first Next peer is `primary`;
    any after it is tinted. Two failed jobs with runners-up would otherwise be two primaries.
  - **Arriving is exactly what the badge counts, by construction**: App gives TabBar
    `view.arriving.length`, the list Home draws - one list read twice (review: it was the hook's
    `activeCount`, and nothing checked which number App passed). The sim holds `view.arriving.length`
    to downloadOverlay's `activeCount` across six scenarios, and pins where the two part: a retry's
    overlay left on a job that has since finished (`reconcile` drops `retrying` only once the job is
    active or gone, and no TTL covers it), which activeCount counts for good and the view draws under
    Done - the metadata queue's lesson ("the tab badge and the queue must never count different
    things"). Home shows the first three (`ARRIVING_MAX`), and NOTHING when there are none -
    `Arriving` returns null, no heading. The sim renders Home with Navidrome unset, down and unknown
    to hold Arriving outside the gate (a text check of Home.tsx passed with it inside).
  - **An Arriving card's state word gives way before the album's name**: the brief shrinks with an
    ellipsis and the body keeps `--app-arriving-body-min`; a retry's brief is "retrying…" either
    way (it was "trying next peer…", 133px at 320, leaving "The D…").
  - **Organizing has no ✕** (nothing in slskd is left to cancel, and filing can't be stopped; the
    old row offered one). **Waiting jobs have one** although the board draws none: giving up on a
    job at #40 in a queue is the commonest cancel, and the old panel allows it.
  - **"Already in your library, nothing filed"** for `already_there`, where the board says "nothing
    downloaded": the download DID happen - its files are in slskd's folder, which a move's clean-up
    keeps because duplicates count as skipped. The other Done words: "Partly filed: <the row's
    error>", "Interrupted while filing: check the library and slskd's folder", "Not filed: <error>"
    for an ending with no outcome (a dry run, nothing that could be filed, filing that raised, no
    track filed), "Downloaded, not filed" for one with no error (organizing off: `ORGANIZE_MODE`
    'off', or `LIBRARY_PATH` or `SLSKD_DOWNLOAD_PATH` unset - `organizing_enabled()` is all three).
    Warnings amber.
- **The server** (`/download/jobs`): each row gains `updated_at` and `release_mbid` (list_jobs
  always read them; the route dropped them), `release_group_mbid` and `edition`, and `outcome`.
  - The two read out of the stored release BY SQLITE in `list_jobs`' SELECT (`json_extract`, as the
    runners-up's usernames are), never decoded in Python - the v0.9.24 cost. `edition` is
    `COALESCE(NULLIF(TRIM($.edition_label), ''), NULLIF(TRIM($.disambiguation), ''))`: a blank label
    falls through. Both behind `json_valid`, so one bad row gives nulls instead of failing the poll
    (list_jobs answers [] on any error). Measured: fifty jobs with 4.7 KB releases, 1.14ms a poll
    before and 1.25ms after, on this Mac.
  - **`outcome`** is `poller.job_outcome(status, error)`: `filed` (organized), `failed` (failed AND
    cancelled - the two retries restart), `already_there` (complete, error starting
    `f"{ALREADY_THERE}:"`), `interrupted` (complete, error == `INTERRUPTED_FILING`), `partly_filed`
    (complete, error ending `f" {FAILED_TO_ORGANIZE}"`), and null for anything still going or any
    other ending - the client shows those in the row's own words. The constants are NAMED in
    poller.py and the poller builds its messages FROM them (the all-duplicates message is
    byte-identical to before: `ALREADY_THERE` is its old prefix), so the two can't drift; a test runs
    the real `_organize_if_enabled` with a faked organizer and reads each message back as its
    outcome. Free text that merely mentions one ("the peer said: already in the store") is not it.
  - **One message changed, on this branch only**: a filing where files failed and NO TRACK landed
    now says "N file(s) failed to organize, no track was filed" (`NO_TRACK_FILED`), so it isn't read
    as partly filed. Judged by `results["tracks_organized"]` - the test the enrolment makes - not
    `organized`, which counts a cover (review: a folder left with only a cover read "Partly filed"
    with none of the album in the library; troubleshooting.md promised it showed as New). A result
    without the count is taken as all audio (`.get("tracks_organized", organized)`; execute_plan
    always gives it, test fakes don't). `test_a_folder_left_holding_only_a_cover_is_not_enrolled` -
    main's test - now reads the new words and an outcome of None. Main's message isn't wrong there -
    nothing on main reads it as an outcome - so this isn't a main fix; a merge touching those lines
    will conflict, and should keep this. A row written before it, where nothing landed, can't be
    told apart and reads as partly filed (troubleshooting.md says so).
  - `tests/test_jobs_route.py` (16) through `TestClient(start())` with a real store and a fake slskd:
    every field, the edition's order and blanks, a row with broken JSON, `list_jobs` never handing
    the release to `json.loads` (the loads are watched for a marker only the release holds), each
    outcome from status and constant, free text refused, the poller's own messages end to end, a
    queued row's position, and the runners-up still counted only for a retryable job.
- **Re-rendering**: a poll re-renders App (the hook's state lives there). Home and Requests are
  memoised apiece on what they draw; the other roots as before; Home's shelf is memoised inside
  Home, and `NOTHING_ARRIVING` keeps Home's element still while nothing is arriving. **Each tab's
  top page is memoised on `[nav, status, playingId, player.playing]`** - what AlbumPage reads of the
  player (the playing song's id, whether it plays, and `playTracks`, one function for the page's
  life). Not on `player`: usePlayer returns a new object every render, so a memo keyed on it (the
  first cut's) held for no poll, and every mounted album page re-rendered twice a second while
  Requests showed (review). `app-rules.sim.cjs` holds AlbumPage to reading only `player.track?.id`,
  `player.playing` and `player.playTracks`, so reading more there fails until the memo has it too.
  The mini player, Now Playing, its menu and Info still re-render with App - at most 2 Hz, while
  Requests shows - since app-rules pins their JSX in App as it is.
- **Covers**: `https://coverartarchive.org/release/<release_mbid>/front-250` (`jobCoverUrl`, the id
  encoded), the phone fetching it itself; `JobCover` remembers which address failed, as `Cover`
  does, so offline or no picture is the plain tile (`--dw-empty-cover` with the board's edge), and
  the next pressing is still asked. Lazy: a hidden pane fetches nothing. Pending rows have none.
- **The ✕ asks first, IN the card - never `window.confirm()`** (review). This page plays the music,
  and a blocking dialog holds its JavaScript: a song ending while it was up waited for the answer
  (the engine starts the next one from `ended`), a stream stopped being fed, and on a locked phone
  the music stopped at the end of the song - the engine's first rule broken by a cancel. The main
  page could use confirm() because it never hosted the player. Now the ✕ (by the main page's
  `confirmCancel` preference, read at the tap - which a home-screen app, own storage and no
  Settings tab, always has on) opens a question in the card: "Cancel this download? You'll lose
  your place in this peer's queue.", **Keep it** (secondary) and **Cancel download** (secondary,
  red words - the one solid purple stays Next peer). The ✕ is `aria-expanded` with
  `aria-controls`, and a second tap on it closes the question; one card asks at a time (Requests'
  `asking`, by row key); a row whose cancel isn't `ready` any more draws no question.
  `app-rules.sim.cjs` fails on any confirm(), alert() or prompt() in app/ or player/. The docs say
  so, and configuration.md's label for the preference is fixed ("Confirm before cancelling", as the
  tab says; it read "Ask before cancelling").
- **Until deadwax first answers, a spinner** (review): the hook starts with `jobs = []` and no
  error, so a cold open on #requests (iOS reloads a tab it put aside) said "Nothing requested yet"
  for a round trip - longer with slskd slow to answer deadwax (no timeout on SlskdClient). App
  notes the first answer without touching the hook: `answered` turns true once `jobs` is no longer
  the hook's first array, or there is an error, or tracking is off, and Requests draws
  `pl-spinner` while the view is empty and nothing is known.
- **Taps answered for a screen reader** (review): busy buttons and the cancelling ✕ are
  `aria-disabled` with the tap refused in the handler, never `disabled`, which dropped the focus a
  keyboard or VoiceOver had on the button tapped. One polite, atomic live region, always in the
  page (iOS reads only a region already there), says what `changes(before, now)` found: a row under
  another heading ("Heligoland: waiting", "...: needs attention: <why>", "...: In your library ·
  just now"), a retry's refusal, a tap's answer starting ("trying next peer…", "asking again…",
  "cancelling…") - pure, pinned. A card that moved is drawn afresh in another list, so each `<li>`
  carries `data-row` and `tabIndex={-1}`, and a layout effect puts focus on the moved card when the
  focus was in it and fell to the page (only then: a deliberate tap elsewhere is left alone).
- **Clear done is the clear route**: it forgets every finished, failed and cancelled job (and the
  refused pending rows), the Needs attention ones included, exactly as "Clear finished" does. The
  label is the board's; the docs say what it clears. Disabled (`button:disabled`'s 0.4) with
  nothing to clear, rather than hidden, so the title row doesn't move.
- **The tab's badge**: `badgeText` (none at 0, "99+" past 99), drawn over the icon's corner,
  `aria-hidden`, with the button's `aria-label` "Requests, 2 arriving"; STYLE.md's purple badge laid
  over the tab bar's colour so no icon stroke shows through. **On a phone on its side it goes into
  the row**, between the icon and the label (`position: static` in the max-height block): the label
  is beside the icon there, and "12" over the corner covered the top of the R (review).
- **"See all" and the Arriving cards go to Requests' ROOT** (`router.root`, appHistory.ts; review):
  a tab tap shows a tab as it was left, so after Go to album on the Requests tab, See all showed the
  album. `root()` is the switch and then the pop-to-root, so the history is what tapping the tab
  twice makes; `routes.sim.cjs` drives it.
- **Style**: cards are `.app-card` (#24222c, 6px, inset highlight), the bar STYLE.md's sunken track
  (`--dw-bar` 6px, `--dw-radius-fill`), data monospace, tokens only (`--dw-amber-text`,
  `--dw-badge-purple-*` new in theme.css section 10; the layout's `--app-job-*`, `--app-done-row`,
  `--app-arriving-*`, `--app-tab-badge*` in app.css). Every control a tap target: the ✕ a 32px box
  in 44px (its bleed into the card's padding keeps the box where the board puts it), Next peer and
  Ask again 36px reaching 44 through `::before`, Clear done and See all text buttons 44px tall.
  **The buttons have no overflow of their own** (review): the button is its `::before`'s containing
  block, so `overflow: hidden` for the ellipsis clipped the reach back to 36px; the label is a
  `.app-job-action-label` span holding the ellipsis, as Now Playing's album line does, and the reach
  counts the button's 1px border (`+ var(--dw-hairline)`). **The pair stacks below
  `--app-job-action-min` (150px a column)**, `repeat(auto-fit, minmax(...))`: at 320px a column held
  105px of text and "Next peer · 2 left" (121px) lost its count; stacked, the row gap is twice the
  reach so the reaches don't overlap. **A row being cancelled fades its cover, title, bar and (on a
  Downloading card) who it's from**, never the words saying "cancelling…" (the whole card at 0.55
  put them at 2.7:1). `test_app_css.py` holds all of these, the bar, the opaque badge and its row
  on its side, a busy button's opacity, and the live region's hidden box.
- **Not built, on purpose**: the board's "Missing from artists you have" and "Only as MP3" (after
  step 4, per the plan); per-user requests (step 4); tapping a Done row to play its album (the id
  bridge, slices.md's S6 - Done rows are not links); Get (S5 - built in 2.0.0-player.15, "Sources and
  Get").
- **After review**: nineteen findings, each confirmed by skeptics, fixed together - the blocking
  confirm, the album-page memo that never held, "Nothing requested yet" before the first answer,
  Arriving and the badge freezing after one failed look (the app's side; the hook's is main's),
  See all landing on an album page, Waiting rows dropping "N failed", "Partly filed" for a cover
  alone, the clipped 44px reach, the badge over the label on a phone on its side, the primary
  button's count lost at 320px, taps silent to VoiceOver, the Arriving title squeezed by a long
  state word, the cancelling row's 2.7:1 words, the gate check that passed with Arriving inside it,
  the badge's unpinned wiring, the unpinned watching derivation, the drawn states unpinned at the
  component, "organizing off" naming one of its three causes, and the slice numbers above.
- **Verified**: 1878 Python tests (`test_jobs_route.py` new, nine new in `test_app_css.py`),
  pyflakes, tsc, and all 27 sims (`requests` new, 149 checks; `app-rules` and `routes` extended);
  50 mutations for the first cut, one per rule pinned, and 38 for the review, one or more per fix,
  each caught and restored byte for byte. The engine guard is empty, and the hook,
  `downloads.sim.cjs`, `player.sim.cjs` and the old downloads panel are untouched.
  **NOT verified here**: the real page (the build workaround and a check against the stubs and a
  fake slskd come after this change), and everything on the iPhone - the tab and its badge under a
  real finger (and beside the icon on its side), the ✕'s question in the home-screen app, Arriving
  coming and going, a download started elsewhere showing on coming back, VoiceOver reading the live
  region, and the Archive's covers over WireGuard.

### Search, and albums you don't have (2.0.0-player.13)

Slice 4 of the one app (`uplan/slices.md` S4, numbered .13). The boards are `Search.dc.html` and
`Request.dc.html` (its `album` tweak: Third with every pressing alike, The Slow Rush, and The Slow
Rush with the Japanese CD picked; RequestBonus merged into it). James: "One search box: library
first, then MusicBrainz; an album you don't have opens like one you do" - the canvas gives it the
SAME header as an album you have: back, centred cover, title, artist, meta line, then the Pressing
dropdown where the album page has its chips and "Get the album" where it has Play/Shuffle; "for
both, I'd like the album page to show the tracklist instead of the release list. Then there should
be a dropdown somewhere to pick which release you're viewing, with the most common as default";
and "show the bonus track differences on an album that has them".

- **The Search tab** (`app/Search.tsx`) replaced its placeholder: one box (17px, so iOS doesn't zoom
  as it is tapped; `role="search"`, `enterKeyHint="search"`, and Search on the keyboard blurs the
  field so the answers have the screen).
  - **The library half**: Navidrome's search3 through the new `/navidrome/search`
    (`searchLibrary` in player/api.ts, `SEARCH_COUNTS` 5 artists, 8 albums, 12 songs),
    `LIBRARY_SETTLE_MS` (200) after typing stops, inside the Navidrome gate. The **Top result** is an
    artist whose folded name IS what was typed (`topArtist`), drawn as a plain row - NOT a link:
    there is no artist page until S6, and a row going somewhere else would be a lie. Album rows open
    the album (prefetching on pointerdown, as a tile does); song rows, below.
  - **A song plays within its album once that album is in hand**: as the answer lands, the first
    `SONG_ALBUMS_PREFETCHED` (5) distinct albums of the songs (`albumsToPrefetch`) go through the
    album page's own `prefetchAlbum`, which now RETURNS its held promise (callers that ignored the
    void are unchanged; the album page still takes the ask once), and each landing album is kept in
    `ready` - only for the newest library search. **Asked with `keep`** (review): a tile's or an
    album row's press shares the one ask, and a press that turned into a scroll (`dropPrefetch`)
    aborted it - so a scroll starting on the Dummy row while Search's ask of Dummy was out left
    every Dummy song opening the album instead of playing, with nothing asking again. A kept
    entry (`Prefetched.kept`, set by whichever asked with `keep`, first or second) is never called
    off; a tile's own ask still is. `search.sim.cjs` runs the real api.ts for it. The tap: `rememberPlayed(album)` then
    `actions.playTracks(album.song.map(toQueueTrack), at)`, from `ActionsContext`, in the click,
    nothing awaited - the gesture rule; `app/Search.tsx: playTracks` is the one new file on
    `app-rules.sim.cjs`'s allowlist. Not in hand: the tap opens the album, where Play is. A ▶ on the
    row says which it will do.
  - **The MusicBrainz half, "Not in your library yet" / "From MusicBrainz"**: `lib/searchQuery.ts`
    (pure, `searchQuery.sim.cjs`) reads the box against the library's artist names (/library/owned's
    album artists plus the library half's artists, folded by owned's `foldName`): a leading or
    trailing artist is `fieldedAlbumQuery` (`releasegroup:"rest" AND (artist:"A" OR
    artistname:"A")`, the longest name first, the start before the end, separators like " - "
    dropped), an artist alone `artist:"A"`, `va`/"various artists" Various Artists, anything else
    the words as typed. `withTypeFilter` ALWAYS brackets the query before a type filter
    (`typeFilter` builds main.js's clauses; the sim reads main.js's NOISY_SECONDARY_TYPES to keep the
    lists one). **The app sends no type filter**: the board draws none, and a filter silently on (the
    main page's `searchStudioOnly` preference) is the search that quietly returns less. Asked on
    Enter, or `MUSICBRAINZ_SETTLE_MS` (700) after typing stops with `MUSICBRAINZ_MIN_CHARS` (3)
    or more, as `fully_search?releases=false&limit=12` (`MUSICBRAINZ_LIMIT`); `asked`/`libraryAsked`
    refs stop Enter and the pause after it asking twice. A fielded read that finds nothing is asked
    again as free text (the metadata editor's fallback: an artist's name starting a title).
    `notInLibrary` drops a group the library holds BY GROUP ID only - a "maybe" (an untagged folder of
    that name) stays on offer. **Worked out ONCE, as the answer is drawn** (`shown` in the state,
    review): the answer waits up to `OWNED_WAIT_MS` (1500) for the library's, asked beside it
    (`refreshOwned()` resolves once an ask made after it has landed), so a held album is left out
    BEFORE drawing; an answer landing later never takes a row away - the rows under the finger moved
    up and the tap opened another album - and marks it in place instead (`groupLine(group, held)`:
    "Album · 2008 · in your library"). **A box cut back below 3 characters** to anything not asked
    (`musicBrainzOnTyping`, pure: clear | settle | drop | keep) supersedes the MusicBrainz search,
    clears `asked` (or 'por' -> 'po' -> 'por' would keep an idle half saying nothing) and goes back
    to idle, which says how to ask: before, the longer text's albums stayed under a box reading
    "po" for good, and a search still out drew there. The box takes `maxLength` `SEARCH_MAX_CHARS`
    (200, the route's bound: a longer paste was a 422 shown as a URL, with a Try again that could
    never work). States: the sweep and "Asking MusicBrainz…"; MusicBrainzUnavailable ->
    "MusicBrainz isn't answering just now - it often goes away for a few minutes." with Try again;
    "Nothing on MusicBrainz for …"; "Everything MusicBrainz found is in your library already".
    The library half's failure is drawn the same way (`.app-search-problem`, a full-width 44px
    `.app-button` Try again; it was a bare 20px text button beside MusicBrainz's).
  - **Only the newest answer draws** in each half (`libraryRequests`, `musicRequests`, latestOnly;
    app-rules holds both, and the prefetch landing too). `/fully_search` still runs to its end on
    the server when the page gives up (no `unless_abandoned` there), which is why the page paces it.
- **`/library/owned` in the app** (`app/useOwned.ts`, a module store over `owned()` in
  api/library.ts and `lib/owned.ts`): one request in flight and one "ask again", so the newest
  answer lands last; `refreshOwned()` returns a promise resolved once an ask made AFTER it has
  landed (answered or not - what Search waits on), and `ownedNow()` is the store's answer for code
  that has awaited. **Never asked as the app starts** - Search is mounted, hidden, from the start,
  and the first /owned after a restart walks the whole library (`library_is_behind`); it is asked
  when Search first SHOWS (`searchSeen` in App, as You's `youSeen`), when an album page opens,
  beside each MusicBrainz search (a 304 when nothing changed), and on a filing once anything has
  asked (`wanted`) - even an ask that failed (review: `held || asking` never asked again after a
  failed first ask). `search.sim.cjs` drives the store itself against a faked /library/owned (one
  ask out, ask again, what a refresh waits for, filing before and after a failed ask); app-rules
  holds where it is asked from (Search's `shown`, App's `searchSeen`, the page's `useOwned(true)`,
  beside each search) - the first cut claimed app-rules pinned it all, and it pinned neither
  `again` nor the ask beside a search. A failed ask keeps the last answer, or none: nothing is
  dropped from the MusicBrainz half without an answer, and the album page says neither "in" nor
  "not in your library".
- **The album you don't have** (`app/ReleaseGroupPage.tsx`, at `#/<tab>/group/<rgid>?release=<mbid>`):
  `pl-album-page`'s header (back, `ArchiveCover` - the Cover Art Archive's front for the pressing
  shown, then the group's, remembering which addresses failed as `Cover` does - title, artist as a
  plain `pl-hero-artist` like the album page's, and `metaLine`: "2008 · Album · not in your
  library", "in your library" when the group is held by its id OR any pressing's (`releaseIds`: an
  .m4a deadwax filed has a release id and no group id - Easy MP4 has no key for it - and the main
  page's card counts it through `registerGroupReleases`), nothing about the library until it has
  answered (`held` null: the first cut said "not in your library" for an album you have while the
  first /owned walked the library), and nothing at all on a cold link until something is known).
  The id in the address goes through `groupMbid()` (lowercased, MusicBrainz's pattern): anything
  else is `NOT_AN_ALBUM_LINK`, "That isn't a link to an album on MusicBrainz.", with no Try again
  and nothing asked - it was a 422 drawn as a URL with a Try again that could never work. `app-rg-actions` holds the `PressingPicker` where the album page has Play
  and Shuffle; **Get was left out entirely until S5** (an unusable button is worse than none), the
  column being where it goes under the picker - so the page had no solid purple button (app-rules
  pinned that; since 2.0.0-player.15 it pins Get as the ONE - see "Sources and Get"). Outside the
  Navidrome gate (App's `pageView` branches on `page.kind`).
  - Its pressings: NEW `GET /search_musicbrainz/release_group?release_group_mbid=` (an MBID or a
    422) = `get_releases(with_tracks=True)` - every pressing's tracklist, which the base and the
    differences need - cached by ResponseCache like every success. `getReleaseGroup` in
    api/musicbrainz.ts, through latestOnly; a `problem` (MusicBrainz failed, before or part way) is
    drawn as the problem with Try again, never as a short list. A module `Map` keeps the last
    `PRESSINGS_KEPT` (20) complete answers for the session, so Back (the page re-mounts: only a
    tab's top page is mounted) and a tab switch ask nothing; only complete answers - a broken-off
    list is never kept, so Try again and the page opened again ask afresh (group.sim). A cold link
    has no preview, so the header comes from the group the pressings carry (`release-group`,
    review: `/release_group` asks `inc=...+release-groups` - `get_releases(with_group=True)`, no
    extra request - so a reload or a link says "Album" and the group's own title), else from the
    pressings themselves (`pageHeader`: the chosen one's title and credit, the earliest year -
    MusicBrainz's first-release-date).
  - **`lib/pressings.ts`** (pure, `pressings.sim.cjs` on the real fixtures): `pressingsView` - the
    default is `representativeRelease` (the most common tracklist, Official, CD/Digital, no
    disambiguation, earliest, the id: the pressing a card's Find downloads as, and the one S5's Get
    will get); a pressing's kind is `usual` (chooseBase's titles in order, with nothing added, left
    out, renamed or another version - a length a few seconds off is not a difference, and never
    marked, where the main page shows an "N lengths" chip), `differs` or `none` (no tracks).
    **Every pressing is compared with the usual titles at the DEFAULT pressing's lengths**
    (`reference`, review): chooseBase lends the lengths of whichever pressing holding the usual
    titles MusicBrainz listed FIRST, so with the single mix first the default read "another version
    of Borderline" against itself and every other pressing differed. The default always holds the
    usual titles (representativeRelease picks from chooseBase's pool), so no order changes a word -
    pressings.sim puts every real pressing first in turn. Left-out lengths and "The usual version
    is …" are the default's: Dummy's It's a Fire is 3:49 here, where the main page's base row says
    3:48. The dropdown shows the default, ONE usual pressing of each other format,
    the chosen one if it was folded, every one that differs, then folds the rest of the usual ones
    under "N more pressings with the usual tracklist" - which EXPANDS (decisions.md left that open;
    a pressing you can't reach can't be got). Labels: formats in runs ('2×12" Vinyl', "Digital" for
    Digital Media), year, country (XW left out, XE "Europe"), then the disambiguation else the first
    label. Notes: "The usual tracklist · shared by 9 of 10 pressings" ("all N"), "Same tracklist as
    the usual one", "+1 bonus track: Patience", "Without It’s a Fire", "1 other version: Borderline,
    4:34", "N tracks renamed", "No tracklist on MusicBrainz". `summaryLine`: the default's "The usual
    tracklist, shared by …", "Same tracklist as the usual one", amber "This pressing adds 1 track"
    (leaves out / renames / has another version of, joined), "The only pressing MusicBrainz lists".
    `trackRows`: the pressing's own titles and lengths, numbered per disc, a Bonus mark ("Only on
    this pressing"), Other version ("The usual version is 3:58"), Renamed ('Usually "…"');
    `leftOut` lists what it leaves out after the list. Disc headings by `lib/discTitles.ts`'s rule
    (more than one disc, or any titled): "Disc 2 · Unreleased Tracks" from the medium's title.
  - **The pick is the address**: `onPick(group, release | null)` -> App's `pickPressing` ->
    `router.update` (appHistory.ts) -> `replaceTop` (appRoutes.ts) REPLACES the entry, so a reload or
    a link shows the same pressing and back leaves the page in one step; the default takes
    `?release=` out. `Page.release` is in the address but NOT the page's identity (`samePage` is kind
    and id) and not where its scroll is kept (`scrollKey`, which App now uses for every saved scroll,
    so a pick never jumps the page to the top). Back and forward land on the pressing their entry
    names (`followRoute` and `forwardTo` go through `replaceTop`). `routes.sim.cjs` drives it end to
    end.
  - **`app/PressingPicker.tsx`**, a listbox: the button (`aria-haspopup="listbox"`, `aria-expanded`,
    `aria-controls` an id of its own - a page stays mounted on every tab it was opened on), options
    `role="option"` with `aria-selected`, opening focuses the chosen one, arrows/Home/End move.
    Escape and a pick close it with focus back on the button; a tap outside (`useDismiss`) or Tab
    out just closes it, focus left where it went. The fold is a button OUTSIDE the listbox (only
    options belong in one), and expanding moves focus to the first pressing it revealed.
    **Focus going NOWHERE is not focus leaving** (review): WebKit - Safari, every iPhone browser -
    focuses no tapped button without a tabindex, so a press on "N more" or on the Pressing button
    blurred the focused option with no relatedTarget, the focusout closed the list and Preact hid it
    before the click: "N more" could never expand on the iPhone, and the Pressing button closed
    the list on its press and reopened it on its click (reproduced in a WKWebView). A focusout
    with no relatedTarget is ignored (a tap outside is useDismiss's), and the fold takes
    `tabIndex={-1}` like the options (WebKit focuses those since Safari 17), so a tap on it keeps
    focus inside. Chromium blurs a removed focused element with no relatedTarget too - the fold
    going as it expands. **Opening brings the list into view** (review): it opens downward, and at
    375x667 with something playing about 20px of it showed above the mini player, the chosen option
    focused out of sight (`preventScroll`). It is capped to the band between the page's bars
    (`--app-picker-band`, `-mini` with the mini player: 100dvh less the scroll-padding), the chosen
    option is scrolled into the list's own view, then the list into the page's
    (`scrollIntoView({block: 'nearest'})`, which honours html's scroll-padding). The list is a
    popover that scrolls itself (`overflow-x: hidden` - the overflow gotcha), under the album page's
    sticky bar (z 4 < 5); the fold is drawn in the accent as the app's text buttons are (it was
    tertiary grey, 3.6:1 at 12px). `group.sim.cjs` renders the page and the picker with the
    fake-Preact harness.
- **Two copies of tracklistDiff and owned, held to one answer.** The Docker UI stage copies only
  `ui/`, so the app can't import `interface/scripts/*.mjs`: `lib/tracklistDiff.ts` and
  `lib/owned.ts` are PORTS (same functions, same thresholds, same answers), and the `.mjs` stay for
  the main page until it retires. `tracklist.sim.cjs` and `owned.sim.cjs` run BOTH copies against
  shared fixtures in `tests/fixtures/pressings/`: The Slow Rush, Dummy and Third as MusicBrainz
  answered on 2026-09-30 (`/release?release-group=…&inc=media+recordings+labels+artist-credits`,
  trimmed to the fields read), each with what the `.mjs` answered recorded beside it (the base, the
  representative, every pressing's diff and chips), the Experience edition of Wish You Were Here
  for medium titles, and `owned.json`'s library and cases; tracklist also diffs every pair of real
  pressings through both copies (789 pairs), and holds the two to the same base and pressing with
  every real pressing put first in turn (47 orders), and on the two rules the real groups never
  test, in the hand-made suite both copies run: a tie for the most common tracklist goes to the one
  given first, and a CD with a disambiguation beats a plain vinyl (review: a drift in either passed
  every sim). A change to one copy that the other doesn't share fails by name. A Python port, if a native client ever wants pressings from the server, is pinned
  by the same files. Real data corrected the board in two places: Third has 17 pressings, 13 alike
  (not 4), and the Japanese CD's "Patience" is 4:53.
- **The server**:
  - `GET /deadwax/navidrome/search` (search3): declared `q` (at most 200 characters, empty allowed -
    Navidrome answers an empty search with everything, for S6's Songs), `artistCount`/
    `albumCount` (0-50), `songCount` (0-500), offsets (0+), defaults 20; answers `{artists, albums,
    songs}` as Navidrome sent them. `test_there_is_no_general_proxy` (and the turntable test's copy
    of the list) edited on purpose. `tests/test_navidrome_search.py` through `start()`: what reaches
    search3, a forged login, folder, format or client name never passed on, an encoded `&u=` kept
    inside the query, every bound a 422 with Navidrome asked nothing, the bounds themselves allowed.
  - **`client_for(request)`** (navidrome_endpoint.py): the seam for step 6's per-user Navidrome
    logins - every route in routes/navidrome.py and the turntable's internal getAlbum
    (`_navidrome_release(album, client)`) ask through it, so step 6 changes its body and no route.
    With logins off it returns the one shared client (the settings route still drops that one on a
    URL change). NOT through it, on purpose: the stream cache's make and the album context
    (player_cache.py, album_context.py) - one make serves every phone that asks, so step 6 must check
    a user's access at the route before handing them the cached answer - and the apply's
    getScanStatus, a question about the server. The test records every route's call.
  - `/search_musicbrainz/releases` passes `problem` through (it dropped it, so a broken-off list
    read as the album's pressings); `/release_group` also asks each pressing's group
    (`with_group`, `inc=...+release-groups`, its own cache key; `/releases` doesn't);
    `tests/test_musicbrainz_routes.py` runs a real MusicBrainzClient over a counting fake through
    `start()`: problem passed on, with_tracks and release-groups asked, paging, the cache (a second
    look asks nothing), a failure never cached (Try again asks), a part-way failure, and the MBID
    pattern (anchored both ends; uppercase, a suffix, a prefix, `&inc=` refused).
- **Style**: tokens only - `--dw-field`, `--dw-field-icon`, `--dw-popover*`, `--dw-selected-row`,
  STYLE.md's green and amber badges and row tints (`--dw-badge-green-*`, `--dw-badge-amber-*`,
  `--dw-tint-*`) new in theme.css section 10; the layout's `--app-search-*`, `--app-field*`,
  `--app-result*`, `--app-sweep-*`, `--app-picker*`, `--app-rg-*` in app.css. The page's classes are
  `app-rg-*` (`.app-group` was already the grouped list). The loading sweep (`.app-sweep`, STYLE's
  sunken track with a part of the purple fill going along it) stops for reduced motion. A marked
  row's tint reaches `--app-rg-mark-bleed` past the column with matching padding, so its number and
  length stay in line. `test_app_css.py` holds the field's 16px floor, the popover (scrolls itself,
  under the bar, no display of its own so `hidden` hides it, never taller than the band between the
  page's bars, mini player or not), the fold's accent, tap targets, ellipses, the tint and the
  sweep.
- **Not built, on purpose**: Get on the page and Get chips on rows (S5: an unusable button is worse
  than none - both came in 2.0.0-player.15, "Sources and Get"); artist pages and the top result as a link (S6); a held MusicBrainz group opening the
  album you have (S6's id bridge); `#/search?q=` in the address (the root stays mounted, so the box
  keeps its text across tabs; a reload empties it); a visible type filter (none on the board, and
  never silently on); trimming `/release_group`'s payload on the server (the API keeps
  MusicBrainz's raw data, gzipped; a group of hundreds of pressings is several requests and a
  large answer, kept for the session).
- **After review**: twenty-one findings (two pairs the same), each confirmed by skeptics, fixed
  together, each with a test that fails without it: a scroll calling off Search's own album ask
  (`keep`); the pressing list closing under a tap in WebKit, and the Pressing button unable to close
  it (focus going nowhere); the page read backwards when MusicBrainz listed a single mix first (the
  default's lengths); the MusicBrainz half keeping a longer text's albums under a shorter box; a 422
  drawn as a URL (`maxLength`, `groupMbid`); a cold link without its kind, and "not in your library"
  before the library answered; the list opening under the mini player with its chosen option out of
  sight; rows vanishing from under a finger as the library answered; the library half's 20px Try
  again; the fold at 3.6:1; an .m4a deadwax filed called "not in your library" on its own page; the
  two tracklistDiff copies free to pick different pressings on a tie or a disambiguated CD; Search's
  and useOwned's wiring unpinned (and a filing never asking again after a failed first ask); a
  broken-off list free to be cached; `owned()` stealing `newImports()`'s doc comment; and five in the
  docs (troubleshooting's album-page wording, this file's route model and picker focus, "always
  agree" with the main page, and the m4a advice). `search.sim.cjs` is new for them.
- **Verified**: 1922 Python tests (44 new: `test_navidrome_search.py` 21, `test_musicbrainz_routes.py`
  15, eight in `test_app_css.py`), pyflakes, tsc, and all 31 sims (`searchQuery` 47 checks, `pressings`
  58, `group` 41, `search` 47 new; `tracklist` 94 and `owned` 49 on both copies; `routes` 140 and
  `app-rules` 95 extended); 78 mutations, one per rule pinned, each caught and restored byte for byte
  - four first got past (the MBID pattern's start anchor, the rename window, a group-only folder
  named as a guess, a stray trailing separator) and gained the tests that catch them - and after
  the review 38 more, one or more per fix, all caught (two first failed only to compile, and were
  made type-valid). The engine guard is empty and `player.sim.cjs` untouched.
  **NOT verified here**: the real page (the build workaround and a check against the stubs come
  after this change); search3 on a real Navidrome 0.64.2 (what it finds for "portishead third", an
  empty query); MusicBrainz live from the phone; and everything on the iPhone - a Search row's tap
  starting its album, the pressing list scrolling under a finger, the keyboard's Search key, and
  the Archive's covers over WireGuard.

### The turntable, part two: momentum and its own sound (2.0.0-player.14)

James, on the turntable of 2.0.0-player.11: "can we add momentum to the disc as well?", then "And the
audio will speed up and slow down with it?". Agreed with him: a flick keeps the record turning and it
coasts; the platter spins up and down on play and pause like a real deck; the sound follows the hand
and the coast, backwards too; a pause on the turntable winds the sound down over about a second, with
a switch in You to turn that off. The cover look is unchanged - its pause instant, nothing of this
running while it shows. PHONE ONLY, like the turntable. The spec is the session scratchpad's
`uplan/slice-turntable2.md`.

- **A SEPARATE SOUND PATH, and why.** The player's own audio element is NEVER connected to Web Audio
  and never touched by any of this but through the player's own actions: Turntable's `holdSong` and
  `resumeSong` (the player's toggle) and its seeks of what the deck returns. `createMediaElementSource`
  is what breaks locked playback on an iPhone (the audio-fidelity memory note), and normal playback
  had to stay exactly what it was. So the record's sound is its own: a decoded WINDOW of the song
  round the playhead, read by an AudioWorklet (`lib/deckVoice.ts`; since 2.0.0-player.16, on a page
  with no AudioWorklet, a ScriptProcessorNode running the same functions - see "After James's report")
  on an AudioContext of its own
  (`player/deck.ts`), and used only while the record is not at its own speed - under the hand, coasting,
  winding down. `app-rules.sim.cjs` holds `deck.ts`, `deckVoice.ts` and `Turntable.tsx` to touching no
  media element at all (no createMediaElementSource, no element looked up, nothing set, loaded, played
  or paused on one) and the deck to calling no playback action.
- **The voice** (`lib/deckVoice.ts`, pure): reads the window at a SIGNED, fractional rate with
  four-point (Catmull-Rom) interpolation - 1 the song, 0 silence, negative backwards - steering towards
  a position and a rate the deck posts each frame (`drive`: where the record is, how fast, and for a
  coast how fast that changes, `accel`, so it follows a curve between frames). The rate is smoothed per
  sample (SMOOTH_S 10 ms) and the steering is FOLLOW_S 40 ms, critically damped together, so what is
  heard stays within about a millisecond of real time of where the platter is (the sim measures it at
  four speeds). A drive runs out by itself (`until`, DRIVE_FOR_S 0.12 s): a stalled page never leaves
  a record whirring. A DC blocker at 10 Hz makes a record held still silent (it reads one sample over
  and over), fades at the window's edges and on take/fade/stop keep it from clicking. Its three
  functions (four since 2.0.0-player.16, with `voiceReport`) are SELF-CONTAINED - no imports, no module
  constants, nor one another - because the worklet module is made
  from their own `toString()` (`voiceWorkletSource()`, loaded from a Blob URL): a worklet runs in a scope
  of its own. A minified rolldown build of it was run in a fake worklet scope and plays (checked once,
  not in CI; again for .16's four - `deckVoice.ts` alone through rolldown, minified: its module played
  the same samples as its functions, with 32 reports in 400 blocks); `deck.sim.cjs` runs the module as
  the browser would and holds it sample for sample to the functions. It reports where it is 30 times a second (exactly: the count carries its remainder -
  `voiceReport`, shared by both hosts since 2.0.0-player.16), and the
  needle and time line show that - extrapolated - while it sounds.
- **The physics** (`lib/platter.ts`, pure): speeds in the platter's own (1 = 33 1/3 rpm = the rate the
  voice reads at, `voiceRate`), positions in song seconds. Free: friction, a constant part and a part
  that grows with the speed (FRICTION_DRY, FRICTION_VISCOUS), set so speed 1 stops in SPIN_DOWN_S
  (1 s, the wind-down) and a flick of 9 (five turns a second) coasts about 1.8 s. The motor: a constant
  pull from still up to speed (MOTOR_PULL, still to speed in SPIN_UP_S 0.4 s), braking above it (the
  pull and friction's speed part), and BACKWARDS the pull and the whole of friction together, a decay
  to still before the pull up - so a hard flick back (-9) is stopped in 0.86 s, as a forward one is
  braked in 0.84 (until review it had the pull alone: 3.6 s backwards, 16 s of the song rewound, longer
  than the same flick coasts with the motor off). Each phase has an exact answer, so where a coast lands and where a playing song is when the
  motor has it back at speed are known AT THE RELEASE (`coast`, `motor`); `deck.sim.cjs` integrates the
  same equations (`acceleration`) step by step for 54 flicks and holds every landing and every time to
  within a millisecond. A coast back past the start stops there; on past the end stops END_MARGIN_S
  (0.25 s) short and the song ends from there; a motor run back to the start spins up from it. The
  hand's speed is over its last VELOCITY_WINDOW_MS (90) ending at the RELEASE, so a finger that rested
  has none (`handSpeed`), held to MAX_SPEED (24).
- **The window, and where it comes from** - option (a) of the spec, a server route:
  `GET /deadwax/navidrome/scrub/{song_id}?at=&seconds=` (`answer_window()` in player_cache.py, cut by the
  new pure `src/flac_window.py`). A STANDALONE FLAC of the frames covering the stretch: 'fLaC', STREAMINFO
  alone and rewritten (total samples, its frames' smallest and largest sizes, MD5 zeroed; the song's block
  sizes, rate, channels, depth), the frames untouched and RENUMBERED from 0 - frame numbers, or sample
  numbers in a variable-block stream - each header's CRC-8 and each frame's CRC-16 made again. The CRC-16
  is carried over by arithmetic, not summed again: FLAC's is linear (zero start, nothing reflected), so a
  new header changes it by an amount that depends only on the two headers and the length after them
  (`_crc16_after`, multiplication by x^(8n) mod the polynomial) - 4 ms for 330 frames where re-summing in
  Python would be a quarter of a second. Renumbered because deadwax's own `find_frames()` refuses a first
  frame that isn't 0 and Apple's decoder wasn't known; macOS's AudioToolbox (afconvert - the family an
  iPhone's decodeAudioData is) turned out to decode both the renumbered window and one with the song's
  own numbers bit-exactly, as did libFLAC and ffmpeg (measured, not in CI; libFLAC is in the tests where
  `flac` is installed). It is cut from the copy of the song the PAGE PLAYS, from whichever MP4 of it the
  cache holds - Safari's plain one (its sample tables give every frame) or the gapless player's
  fragmented one (its sidx gives every fragment, a fragment's trun its frames): with `max_rate=48000` -
  which the page sends exactly when streamUrl() and fragmentedUrl() would (`resamples()`, Turntable's
  host `maxRate`) - the RESAMPLED copy, under the plan's key, the plan a neighbour-less make was kept
  under (`_lost_side`), or a fragmented MP4 this URL was served (`_pinned`), so its frames are what the
  phone hears: 48 kHz and HEADROOM_DB lower, the same level as the song; with none of those, the
  resampled plain MP4 made as Safari's would be; refused resampled (the page then plays it as it is),
  the song as it is. Without `max_rate` (or no audio libraries), the song as it is the same way. So an
  iPhone's songs cost nothing to make again. (Review: the first cut looked only for the song as it is,
  so under the default "Up to 48 kHz" every hi-res window downloaded the whole original again, kept a
  second full-size copy beside the phone's, and sounded 3 dB louder than the song.)
  `X-Deadwax-Window: <first sample>/<samples>/<rate>` says exactly where it sits (it starts on a frame or
  fragment at or before `at`). WINDOW_MAX_BYTES (8 MiB) bar the frame `at` falls in: 40 s of CD audio
  whole, about 13 s of 24/192 as it is. Only `at` (0 to a day), `seconds` (1-60, default 30) and
  `max_rate` (48000 or nothing, as the stream's) - anything else a 422, as out of bounds is; 415 for a
  song that isn't a FLAC ("it isn't a FLAC file", the cache's own words), too big to hold
  (WRAP_MAX_BYTES, judged before anything is fetched - `_mp4()` holds no cap itself, each caller does)
  or whose MP4 was refused; 416 past the end; 503 with `scope` when the cache can't. A media path (`MEDIA_PREFIXES`): never
  gzipped, under GuardMedia. On the fixed route list ON PURPOSE (`test_there_is_no_general_proxy` and its
  copy in test_turntable_disc_art.py edited); like the stream's wrap paths it asks Navidrome through the
  cache's own client, so step 6 checks a user's access at the route (`test_every_navidrome_route_asks_
  through_client_for` counts it). MP3 is NOT given a window (the spec's "can"): its time can't be placed
  without an ID3 size and a Xing table - a VBR MP3 lands seconds off - so non-FLAC songs are silent on the
  turntable (and since 2.0.0-player.16 have no momentum either: a press is .11's) and Debug says why. No server setting.
- **Kept ready while the turntable shows and the song plays** - once a tap has started the sound: no window
  is asked for without an audio context and a voice ready to put it in (`keep()`: the worklet, or since
  2.0.0-player.16 the script voice once it has played a block), since a window that can't
  be decoded is only fetched again (review: with no context - Now Playing opened onto the turntable from
  the mini player - it fetched a fresh 40 s window every 2 s; with the worklet failed it did the same and
  decoded each). `onAudio` asks once there is somewhere to put it. WINDOW_S (40) from WINDOW_BACK_S (4)
  before the playhead, on a WINDOW_GRID_S (2) grid so the phone's cache (`private, max-age=300`) answers a
  window asked again, refreshed once the playhead is within REFRESH_AHEAD_S (6) of its end, and fetched on
  demand when a hand or a coast goes outside it - and AT THE RELEASE over the whole of where a coast will go
  (`keepPath`: a backwards flick runs back past the window's start, and a sounding coast used to go silent
  there). ONE window is on its way at a time, from the ask until it is in the voice (`pending`, 'fetch'
  then 'held' while it decodes), so nothing asks for it again meanwhile; only the newest decode is handed
  on (`decodes`, a latestOnly); a hide lets go of a window still being fetched and keeps one in hand. A
  window deadwax cut short (a hi-res song as it is, at WINDOW_MAX_BYTES) shrinks the margins in proportion
  (`windowMargins`: 1.3 and 1.95 s for a 13 s window), so each new one still moves on by about three
  quarters of its length; a refresh ahead of a playhead the window still covers must start further on than
  it, and comes no more often than REFRESH_MIN_MS (3 s - a backstop: the move-on rule stops every loop
  first, so no check can show the floor alone). **Cost**: a window is fetched whole, so 40 s over the 30
  the playhead crosses before the next - a third more than the song's own stream while the turntable shows
  and plays; for a hi-res song played as it is about half as much again (13 s windows: about 7 a minute,
  where the first cut asked 29). **Measured** with the deck's own rules over the server's real cuts of a generated 4-minute
  CD-quality FLAC (pink noise and a tone, 500 kbps): 6 windows of 2.5 MB in 3 minutes, 5.0 MB a minute
  against the song's own 3.75 (1.33x; 1.36x cut from the fragmented MP4, whose cuts are whole fragments).
  A typical 900 kbps CD FLAC would be about 9 MB a minute. Info > Debug's row says what windows have cost
  since the turntable showed - how to read it off the phone. A failure is asked again after RETRY_MS (10 s); a 415 or a window the
  browser couldn't decode is never asked again for that song.
- **The audio context, only from a gesture** (WebKit counts click, pointerup and keyup - not pointerdown):
  `wakeDeckAudio()` makes it (once) and resumes it, from the record's click and release, the transport's
  three buttons and the look button switching TO the turntable; `resumeDeckAudio()` resumes one that
  exists, from the mini player's tap opening Now Playing (App's openSheet). `app-rules.sim.cjs` pins
  exactly those call sites by the handler each is in, and that the context is constructed only inside
  wakeDeckAudio. Suspended when the screen closes or the page hides - nothing of it runs on a locked
  phone - and closed when the turntable unmounts (the look switched to the cover). Never resumed without
  a gesture, so after a hide the next tap brings it back. Until it runs - since 2.0.0-player.16, until the
  record can SOUND where it is (a voice ready and a window there in it) - a press is EXACTLY 2.0.0-player.11's
  (`deck.live()` false at the press: silent, the song playing on under the finger, moved where it lets go,
  no momentum - and the record STOPPED under the finger, `deck.holdStill()`, as .11's paused CSS spin was;
  review: the first cut left the deck turning the face under a still finger) - the spec's "until it is
  running a press scrubs silently, exactly as .11 does".
- **What the hand does, live** (`Deck`): a press lets the song play on for a moment, so a tap is still a
  tap (play/pause from the click). The record is TAKEN as the press moves past TAP_SLOP_PX or rests longer
  than HOLD_MS (250): a playing song pauses (`holdSong`), the record's sound takes over at its position at
  speed 1 (or 0 if paused) and follows the hand - silent when it rests; the hand's turn counts from where
  it was taken (`anchor`), the click after it is no tap. A press on a coasting or winding-down record is
  also a possible tap (a quick double-tap pause-play works); taken, it is caught where the platter is.
  RELEASE (`release()`): the hand's speed becomes the platter's. A song that was playing: the motor plan;
  Turntable SEEKS AT THE RELEASE to where the platter will be at speed; at speed (a timer, not the frame
  loop, so a hidden page still gets there) `resumeSong` plays it, and the voice holds speed 1 until the
  song's own position has moved past that point (`onPosition`), then fades over HANDOVER_FADE_S (40 ms) -
  HANDOVER_MAX_S (3 s) at most. **Expect a short repeat at the handover**: the element starts where it was
  sought, while the record's sound has run on by the element's start-up latency; the spec accepts it. A
  coast back to speed of RESUME_IN_GESTURE_S (50 ms) or less plays in the release's own gesture. A song that
  was paused: the coast plan, sought at the release to where it stops, staying paused. A cancel drops it and
  seeks nowhere - a song it paused plays on (`resumeSong`, outside a gesture). A song change drops a press,
  a coast and the window, seeking nothing - and when the hand had taken the song from PLAYING (a press, or a
  coast back to speed: `meantToPlay`), the next song is played (`resumeSong`): usePlayer loads it paused,
  since the hand's pause cleared intendsToPlay, and the hand only scrubbed. Played SONG_CHANGE_SETTLE_MS
  (300 ms) later, and only if nothing has played it meanwhile: a song started some other way in that
  moment (a tap in Search) has its own play under way, and the player's `playing` follows the element's
  'play' a moment after - an immediate toggle would have paused it. A tap in that moment owns the play
  (`resuming()` and `pausing()` cancel the timer), and a press takes the song as meant to play. The turntable going mid-coast
  (the look switched to the cover: `destroy`) plays the song on from where the release sought it, the same
  way. The turntable mounting on the song already playing is no change (`songChanged` compares ids), so the
  window it began asking for isn't superseded and asked again. The arm, or the song sought by anything
  else meanwhile (a position more than SOUGHT_ELSEWHERE_S, 0.75 s, from where the deck had it sought:
  Previous restarting it, a key on the arm), makes the rest of a coast, run back to speed or wind-down
  QUIET (`quieten`): no sound, nothing shown, the arm's preview the time line's while it is held - and the
  handover's sound never holds speed 1 over a song playing from somewhere else (review: Previous mid-coast
  played two parts of the song together for 3 s). A coast back to speed still plays the song when it gets
  there, from wherever that put it.
- **That play() comes after the tap**, on an element a tap already started; usePlayer.ts's header says iOS
  allows it. If WebKit refuses, usePlayer's own refusal path says "Tap play to start" and the song stays
  paused where it was sought - and HANDOVER_MAX_S after it the platter spins down (planEnded's timer),
  rather than turning on beside a paused song - the fallback, unverified until James's iPhone says.
- **Pause on the turntable** (`pausing()`, from the record's tap and the transport's pause on this look) with
  "Pause winds the record down" on, the window covering the playhead and the voice ready: the song pauses in
  the tap as ever, the record's sound starts there at the SONG's own speed - what was heard, whatever the
  platter's 0.4 s spin-up had reached (review: it started at the platter's, an octave down mid spin-up) -
  and winds down with it over about a second (friction's braking curve - exponential with a constant part,
  not linear), and the song is SOUGHT to where the wind-down stops, so play carries on from there rather
  than repeating 0.3 s. A play in the tap while the record still coasts or winds down with its sound is
  sought first to where the record is (`resuming()`, from the record's tap and the transport's play), so
  nothing heard is skipped (review: it skipped up to 0.3 s, seconds after a hard coast). Otherwise a plain
  pause: nothing sought, never a wait - the platter still spins down visually. The lock screen's pause, the
  cover's and a song ending never wind down (only those two callers ask). Play: the toggle in the tap as
  ever; the platter spins up over 0.4 s - the sound starts as it always has (an audible spin-up would need
  play() after the tap; not in this slice).
- **The platter is turned by the deck**, frame by frame (requestAnimationFrame), writing the face's
  transform straight onto the element (never a render, never a style in Turntable's JSX): 33 1/3 rpm
  (DEGREES_PER_SECOND 200) while playing, the plans' angles while coasting, held while a hand has it (the
  hand's own turn stays on the wrapper as in .11). It stops when nothing moves, when Now Playing closes and
  when the page hides; a pause the deck didn't ask for (a song ending, the lock screen) spins it down only
  after PAUSE_SETTLE_MS (300), since a song change pauses for a moment. The CSS spin and `--dw-record-turn`
  are gone (test_app_css holds both gone). Reduced motion (`matchMedia`, read by the deck): it doesn't turn
  at all, a release lands at once - a playing song played in the release's own gesture - and nothing winds
  down; scrubbing under the hand still sounds.
- **The setting**: You > Playback's "Pause winds the record down" (`app/WindDownChoice.tsx`), a checkbox,
  on by default, beside "Now Playing opens as", with a note saying it is the turntable's only. App keeps it
  (`deadwax-player-wind-down`, `readPlayerWindDown`: off only when it says exactly 'off') and hands it to You
  and Now Playing. It governs the SOUND; the platter's visual spin-down is the deck's either way.
- **Info > Debug's "Turntable sound"** (`turntableRow` in debugRows.ts, a new section "The turntable"): ready,
  "0:42-1:22, FLAC, decoded at 48 kHz", or off and why - the turntable isn't showing; no Web Audio; no
  AudioWorklet (since 2.0.0-player.16: nothing to play it on, and the note names the voice); the sound
  couldn't start (the browser's words); "it isn't a FLAC file (it is MP3)" or
  deadwax's 415; "this browser couldn't decode its window - <its words>"; waiting for a tap to start the
  sound; deadwax didn't send it; past the end; loading; no window yet. A note with what windows have cost
  since the turntable showed, and when the last of them came (`lastFetchAt`: the report is made as things
  change, not as time passes, so that is the time the bytes are measured to - review: it read "fetched in
  0:00" for the first half minute). App is told of report changes (`onDeckReport`), never a frame at a
  time. This row is how James tells us what WebKit does.
- **NOT verified - until James's iPhone says**: that WebKit decodes the window (decodeAudioData on iOS -
  AudioToolbox on a Mac does); that an AudioWorklet from a Blob URL loads in the home-screen app; the
  out-of-tap play() at speed (and the "Tap play to start" fallback if refused); that the record's sound is
  heard with the ringer switch on silent (iOS has muted Web Audio there unless a media element plays - it
  is paused under the hand); that suspending the context leaves locked playback, the lock screen's
  controls and AirPods as they were; the feel of the physics under a real finger; and the bytes a minute
  over WireGuard. Nor the real page, which the orchestrator checks after this change.
- **Verified**: 1998 Python tests (76 in `test_scrub_window.py`: the coding of numbers, the carried
  CRC-16 against a re-sum, renumbering by frame and by sample, STREAMINFO rewritten, windows from both
  kinds of MP4 covering what was asked from a boundary, the budget, past the end, a foreign layout refused,
  libFLAC decoding a window to the song's own samples, and through `start()`: audio/flac never gzipped
  under the media headers, Safari's and the gapless player's MP4s cut from with nothing made, the plain one
  made once, a resampled song's window cut from the phone's resampled copy - either kind, or the one kept
  without a neighbour - with nothing downloaded, made resampled when there is none, the song as it is when
  that is refused or there are no audio libraries, the cap's 415 with nothing fetched, a refused MP4's
  415, 416/422/503); pyflakes; tsc; all 32 sims (`deck` new, 159 checks; `turntable` 167, `app-rules` 106,
  `settings` 61, `debug` 79, `info` 85, `you` 23 extended). Mutations, each restored byte for byte - one per
  rule the build made (79: 74 caught at once, four gained tests, one backed up by another) and one per rule
  the review's fixes made (41, server and page: 35 caught at once; four first got past and gained checks -
  a resampled make refused as it is tried falling back, a refresh that must move on (windows of 2 s),
  `resuming()` claiming its own seek, and a paused coast's window asked at the release; two are backed up
  by another layer: the refresh floor behind the move-on rule, and Turntable's arm-wins preview behind the
  deck going quiet as the arm is taken).
  Not every documented rule has its own check - the 3 s floor above has none that could show it alone. The
  engine guard is empty and `player.sim.cjs` untouched.

#### After review (2.0.0-player.14)

A review of the build found these, each confirmed by reproducing it against the real code, and each
fixed with a check that fails without the fix (the bullets above say the rules as they now are):

- **Windows fetched over and over** - with no audio context (the common first open, from the mini
  player, onto the turntable), with the worklet failed, and while a decode ran: the keeper counted a
  window only once it was IN the worklet. Now one is on its way from the ask to the worklet, nothing is
  asked without a worklet to put it in, and only the newest decode counts.
- **A hi-res song**: the server ignored the phone's resampled copy, downloaded the whole original again
  for the first window and kept a second full-size copy, cut 192 kHz windows 3 dB louder than the song,
  and the page re-fetched its 13 s windows 29 times a minute (about 230 MB). Now `max_rate` and the copy
  the page plays, and margins that shrink with a short window.
- **A sounding coast never asked for the window it ran into**, so backwards flicks went silent: now
  asked at the release, over the whole coast.
- **The motor ran a backwards flick back for seconds** (the pull alone, no friction): now both.
- **Outside the deck during a coast back to speed**: Next loaded the next song paused, switching to the
  cover left the song paused, Previous (restart) or a key on the arm played two parts at once for 3 s,
  and a refused play() left the platter turning beside a paused song.
- **The record turned under a still finger** before the sound ran: .11 stopped it.
- **The arm during a coast**: the needle and the time line followed the coast, not the finger.
- **The wind-down** started at the platter's spin-up speed, and a play mid wind-down skipped what was
  heard.
- **Debug's cost** read a time frozen at the last report: now named as the last window's.
- **Tests that could not fail**: the switch-off check (a zero-length wind-down made it pass whatever the
  setting) and the rested release's value (compared with itself) - both now hold a real value, with a
  control; and the deck's documented rules that no check held (the 10 s retry, a decode refused in three
  ways, nothing fetched for a paused song, a coast caught on its way back to speed, a pause near the
  window's end, RESUME_IN_GESTURE_S, PAUSE_SETTLE_MS), the route's cap and refused-MP4 415s, and the
  cover's previous and next waking nothing.
- **Not changed**: an outside PAUSE during a coast back to speed (a headset sending 'pause' to an element
  already paused) is invisible to the deck - no event fires, and seeing it would need the engine - so the
  coast still plays the song at speed. Rare: the lock screen and AirPods offer play then, as the Media
  Session says paused.

#### After James's report (2.0.0-player.16)

James, on his iPhone and then his Mac: "the audio doesn't follow the turntable when scrubbing", "it
doesn't work on my mac either". A fix to .14, not a feature; the spec is the session scratchpad's
`uplan/slice-turntable-fix.md`.

- **The cause, reproduced before anything changed.** `BaseAudioContext.audioWorklet` is a
  [SecureContext] API: a browser exposes it only on HTTPS or localhost, and James opens deadwax at a
  plain `http://` address on his network. So the worklet was never there, deck.ts set
  `missing = 'no-worklet'` and made no voice - and `Deck.live()` was only "the context runs", so a
  press still TOOK the record and paused the song, with nothing to sound: silence under the hand, the
  song back on release. Reproduced in headless Brave by loading the app as `http://deadwax.test:8081`
  (`--host-resolver-rules=MAP deadwax.test 127.0.0.1`); over `http://localhost` every check passes,
  which is why .14's verification never saw it. **The review of .14 raised exactly this** - "a press
  takes the record and pauses the song whenever the context runs, even when the record can't make a
  sound" - and its skeptics dropped it. It was this bug.
- **A second host for the same voice.** Where the context has no `audioWorklet` (or no
  `AudioWorkletNode`), or the worklet can't be made (the Blob URL), won't load (`addModule` refused)
  or its node won't construct, the deck makes a **ScriptProcessorNode** instead
  (`startScript`: `createScriptProcessor(SCRIPT_BUFFER 1024, 0, 2)`, to the destination) that runs
  THE SAME four functions of `lib/deckVoice.ts` on the main thread - `newVoiceState`, `voiceCommand`
  (each message applied to its state - held to the next block, see below), `renderVoice` and the new
  `voiceReport`. `voiceReport` is the worklet's report count moved out of its source string into a
  fourth self-contained function (the counter is `VoiceState.counted`), so both hosts say where they
  are REPORTS_PER_SECOND times a second by one rule. One DSP, two hosts. ScriptProcessorNode is
  deprecated, but it is in every current browser, iOS Safari included, and needs no secure page - which
  is the whole reason it is here; the worklet stays the first choice wherever it exists (its own audio
  thread: a busy page doesn't glitch it). Each block is rendered as of `event.playbackTime` - the
  context time it will play at, a block ahead of `currentTime` as the browser asks for it. A script
  voice is **ready only once it has played its first block**: a browser that never calls it stays not
  ready, and every press stays .11's rather than pausing the song over silence. Debug says "still
  starting" then. The buffer size is 1024 unmeasured on a phone.
  - **How its messages are timed (review of this slice).** The first cut applied each message straight
    to the state as of `currentTime` and rendered at `playbackTime`, a block or two on - and a `take`
    sets the read head, so every take started that far BEHIND the record and the steering raced to
    catch it up: measured with the real functions, 1.39x for one 1024-block's lead, 1.78x for two, for
    20-80 ms - a chirp of 6-10 semitones on every grab of a playing record and at the start of every
    wind-down (on by default), where the worklet's own lead gives 1.05x. "Sounds the same" was false
    on exactly the path James uses. Three parts, none of them a second DSP: (1) `voiceCommand`'s take
    now starts where the record IS as of the `now` it is applied at - `at + rate * (now - time)` - not
    at `at` (its `now` argument was unused); the worklet's own catch-up goes with it. (2) The script
    host HOLDS messages and applies them just before the next block, as of that block's `playbackTime`
    - the moment they are first heard - as the worklet applies each on the audio clock. (3) Every take
    and drive is heard `SCRIPT_LAG_BLOCKS` (2) blocks after it was said, its `time` and `until` both
    moved on by 43 ms: the most a message waits for the block it is first heard in. Without (3) the take
    was placed where the record had got to, and a grab's still hand - whose drives say the record
    stopped where it was taken - then pulled it BACK as far (-0.86x); with it, a take and the drives
    after it keep the spacing they were said with, and the voice plays what the worklet would, 43 ms
    later. Measured in `deck.sim` with frames and blocks on one clock: a wind-down and a grab, each with
    the take's block first and a frame first, never past 1.02x (1.41x before), and a grab's backward
    swing -0.15 at worst. A drive replaces the drive before it in the hold and a window every window
    before it, so a stalled page holds a handful, not a pile. NOT measured: what a real browser's
    `playbackTime` lead is (Chrome's is a block at the event, by its source; WebKit's is computed the
    same way) - a larger one only skips the first few ms of a take, still without a chirp.
- **`live()` needs the sound** - the context running AND a voice ready (`voiceReady()`) AND a window
  of this song covering where the record is (`recordAt()`: the platter for a coast, a run back to speed
  or a sounding wind-down, else the song - one rule, shared with `takeOver`). Anything less - no voice,
  a worklet still loading, a window still decoding or not yet asked, a refused one, an MP3 - is .11's
  path: the song plays on under the finger and is sought on release, no momentum. So an MP3 lost the
  silent momentum .14 gave it. Windows are asked once a VOICE is ready (`keep()`'s gate is
  `audio.voice?.ready`); the wind-down needs one too (`sounding()` is `voiceReady() && covers`). A
  paused song has no window until the record is turned, and its first press is now .11's - so a press
  the deck doesn't take asks for the window where the record is (`holdStill(true)` calls `keep`; the
  held record counts as busy), and the next press there is the deck's.
  - **Except a coast or a run back to speed (review of this slice).** The first cut judged those by
    the platter too, so once a flick ran it out of the window - a backwards flick past the window's 4 s
    back margin, the next window still being fetched and decoded, which is ordinary flick-and-catch -
    a press went .11's way, and `holdStill` only knew the spin's motions: the coast's timer ran on under
    the still finger (the face leapt up to 417 degrees at the release, the time line froze on the
    coast's last time, a window landing mid-hold sounded a burst of the coast's rate under a still
    hand), and a run back to speed's end PLAYED the song under the held finger. But .11's premise - the
    song plays on under the hand - can't hold there: the flick paused the song already. So `live()` is
    true for a coast or a run back to speed whenever a voice is ready, as .14 had it: `takeOver` catches
    it where the platter is, silently, and `handWindow` sounds it as the window arrives. Only those two
    roles - a wind-down with no sound (an MP3, the setting off) must stay .11's, or an MP3 would get
    silent momentum back. And `holdStill(true)` now ends whatever plan the deck still has when a press
    IS .11's (a silent wind-down; a coast whose context a hide suspended since): `quieten` it, then its
    end at once (`planEnded`) - still where it is held, or, a run back to speed, the song played now
    (.11's song playing on under the finger, from where the release sought it), the sound stopped
    rather than held at speed 1 for it.
  - **The first turn of a paused song before any tap (review).** With no context yet - Now Playing
    opened onto the turntable from the mini player, which only resumes one - the press's `keep` found
    no voice, and by the time the release's `wakeDeckAudio` had one ready, `holdStill(false)` had let
    go of the press: nothing asked, so it took two silent turns, not one, and the docs' "the next turn
    has its sound" was wrong. `keep` now remembers a held press refused for want of a voice
    (`wanted`, the song's id), counts it busy, and asks as soon as `onAudio` has a voice; the first pass
    of the voice gate lets it go, so it is one ask, not a paused song kept in windows.
- **The silent switch** (part three of the spec): while the record's sound plays the song's element
  is paused, and WebKit then gives the page's Web Audio the 'ambient' kind, which an iPhone's ring/
  silent switch mutes. `holdAudioSession()` sets `navigator.audioSession.type = 'playback'` (Safari
  16.4+) as wakeDeckAudio makes the context - in the gesture - and `releaseAudioSession()` puts the
  kind it found back in closeDeckAudio, as the turntable goes; only a kind it really changed is put
  back, and both are guarded (absent elsewhere: nothing; a set that throws: nothing).
  `app-rules.sim.cjs` holds `createScriptProcessor` and `audioSession` to deck.ts alone.
- **A hide while a tap's resume is still settling (review, a nit older than this slice).**
  `sleepDeckAudio` only suspended a context already 'running', and nothing looked again once the
  resume settled, so a tap followed at once by the page hiding left the context running, hidden, until
  the next show and hide - on the script voice that is `renderVoice` and `voiceReport` on the main
  thread ~47 times a second for nothing. A hide that finds the context not running now marks it
  (`sleepOnceRunning`) and `audioChanged` suspends it the moment it runs; a gesture asking for the
  sound (`resumeDeckAudio`, which every wake goes through) and the turntable showing again let the mark
  go - the mini player's tap resumes the context a moment BEFORE the turntable shows, and must not be
  suspended for a hide that came before it.
- **Debug's "Turntable sound"**: the report gained `voice` ('worklet' | 'script' | null) and
  `voiceWhy`; the context state 'no-worklet' became 'no-voice' (neither host). The note names the
  voice - "On its own audio thread (an AudioWorklet)", or "On the main thread - this page isn't on
  HTTPS, so the browser has no AudioWorklet" (or "this browser has no AudioWorklet", or "the
  AudioWorklet wouldn't load (<its words>)") - before the cost. Every way the record can't sound reads
  Off, since a press then is .11's: "Off: still starting - …", "Off: its window is loading - …", "Off:
  no window yet - …" (they were "Starting:", "Loading the sound", "No window yet:").
- **NOT verified - James's iPhone list**: that WebKit calls a ScriptProcessorNode with no inputs
  (if it never does, Debug stays on "still starting" and every press is .11's - say so); the record
  heard over plain http on the phone; that 'playback' keeps the silent switch from muting it; and that
  setting it leaves locked playback, the lock screen's controls and AirPods as they were after a
  scrub. The real page (the orchestrator, from `http://localhost` - worklet - and
  `http://deadwax.test:8081` - script) is checked after this change.
- **Verified**: 2048 Python tests (none new: the change is the page's), pyflakes, tsc, and all 34 sims,
  3232 checks (`deck` 222 - 30 of them from the review, below; before it 192, 33 more than .15: the script voice made where there is no AudioWorklet and where
  `addModule` is refused, its arguments and connection, ready only after a block; its output held
  sample for sample, block by block, to `renderVoice` fed the same messages at each block's
  `playbackTime` through a take, a turn and a flick, with the four functions spied on where deck.js
  reaches them; 32 reports in 50 blocks of 1024 as the worklet's 32 in 400 of 128, each reaching the
  deck; `live()` false with no voice, a worklet loading, a window decoding, outside the window, a
  suspended context, neither host, a paused song, an MP3, a 415 - and judged by the platter on a coast
  (until the review: a coast is the deck's whenever a voice is ready);
  a press the deck doesn't take asking for the window; the audio session set, kept, put back, a stubborn
  one and an absent one; `debug` 84, 5 new and the changed words; `app-rules` 121, one new; `info`'s
  fixture given the new fields). Mutations, each restored byte for byte - 33, every one caught: 31 by a
  failing check (one, a Debug branch, first written as a comparison tsc refused as impossible and redone
  as a wording change), two by the sim crashing (the worklet's module made without `voiceReport`, and
  `voiceReport` reaching a module constant - the vm throws, as a worklet scope would). Not pinned: that a
  session set which throws isn't put back (harmless either way). The engine guard is empty and
  `player.sim.cjs` untouched.
- **Its review** found the four things above marked "review" - the script voice's chirp, a .11 press
  leaving a coast running under the finger (raised four times), the paused song's two
  silent turns, the hide mid-resume - and two weak checks, both fixed: the audio-session checks read
  `contexts.at(-1)`, which was the PREVIOUS block's context closed the same way, so with the session's
  try/catch removed (no context made at all, the turntable silent) they still passed - each wake is
  held to a context of its own now, running, the report not 'failed'; and the script voice's teardown
  compared `onaudioprocess` through `check()`'s JSON, which writes a function as null - a boolean now.
  The 30 checks: a late take's anchor (and an early, backwards one); the script voice's takes with
  frames and blocks on one clock (`together()`: a frame every 16 ms, a block every 1024 samples
  played a block later), a wind-down and a grab, each with its block first and a frame first - never
  past 1.03x (the first cut gave 1.41x here), a grab's backward swing above -0.3 (-0.86x without the
  lag); drives held as the last over twenty frames with no block, the newer of two windows held, a
  drive heard 43 ms on for its whole 0.12 s; a coast out of the window caught where the platter is,
  silently, nothing played in 3 s held, sounded as the window lands, sought where caught; a run back
  to speed out of the window caught and nothing played under the hand; .11 presses on a coast and a
  run back to speed whose context a hide suspended (no leap at the release; the song played, the sound
  stopped, not held) and on an MP3's silent wind-down (no leap - it was 20-35 degrees); the paused first
  turn with the worklet and on the main thread, asking once and only once; a hide mid-resume suspended
  as it runs, the mini player's tap and a hide undone before it settled left running. Mutations, each
  restored byte for byte on a copy: the first cut's lists rerun on the fixed code, all caught but one -
  `live()` by the song's position rather than the platter's, equivalent now (they differ only on a
  coast or a run back to speed, which the review's rule makes the deck's before either is asked, and on
  a sounding wind-down, whose whole path its window covers) - three re-aimed at code the fixes moved;
  and 22 for the fixes, every one caught (one - a drive's `until` not moved with its `time` - only once
  a check for it was added). NOT measured anywhere but the harness: the chirp's absence and the 43 ms
  lag by ear, on a phone - James's list.

### Sources and Get (2.0.0-player.15)

Slice 5 of the one app (`uplan/slices.md` S5, numbered .15 because the turntable took .11 and .14).
The boards are `Sources.dc.html` (the sheet and its cards, its tweaks the searching and failure
states), `Request.dc.html` (Get's place on the album you don't have), `Search.dc.html` (the rows'
Get chips), `Requests.dc.html` (where a Get lands) and `You.dc.html` ("Getting albums"). James
(2026-09-29): "Get the album" shows the SOURCES by default, picking one automatically is a setting,
OFF - "I don't think I can reliably trust automatically grabbing from the correct source"; sources as
CARDS, not a comparison table, with speed no longer buried; the pressing dropdown decides what Get
and the sources are for; "Get the album" is the screen's ONE solid purple button.

- **ONE payload builder: `ui/src/lib/releasePayload.ts`.** `buildDownloadRelease(group, release |
  null)` -> `{release, label}`: `groupContext(group)` (createReleaseGroupElement's context: the
  credit as credited, the current names, the ids, the group's title, its first-release year),
  `releasePayload(release, context)` (a pressing - the row Find's, and the card's), `groupFallback`
  (the album as a whole: no tracklist, no release id, so nothing is checked as held) and
  `downloadLabel` (the panel's heading). `ui/src/main.tsx` puts it on the bridge
  (`buildDownloadRelease`); main.js's two Find buttons call it through one helper (`findRelease`,
  with the raw release group riding in `releaseGroupContext.group`) and its own two builders -
  `buildExpectedFromRelease`, `buildExpectedFromReleaseGroup` - and `realYear` are DELETED, as is
  credits.mjs's `isVideoTrack` twin (release.ts's is the one rule; credits.sim asks it alone and
  checks credits.mjs keeps no copy). **The rule is now "anything added to a download's payload goes
  in releasePayload.ts"** - the old "add it to BOTH builders, and click both buttons" is gone with
  the second builder. It keeps main.js's quirks on purpose, since the main page still sends what it
  builds: "N/A" for a credit naming nobody (a track's empty credit too), `||` for the country (an
  empty ISO code falls through), a year four digits or null, the album's own year from the group.
  main.js's `EDITION_KEYWORDS` now only draws the grid's edition chips and facet: a download's
  `edition_tags` come from release.ts's copy (the three lists still stay in step).
  - **Held to the old page's own output**: `ui/test/payload.sim.cjs` deep-equals the builder against
    `tests/fixtures/payloads/find-buttons.json` - what main.js's Find buttons handed `openCandidates`
    at 2.0.0-player.14, captured in headless Brave against live MusicBrainz (the orchestrator's
    capture): Dummy's card and its GB CD row, the Experience edition row (two disc titles, 1975 vs
    2011), Donda's card (credited Kanye West, filed under Ye, DELUXE) and BULLY's, an undated
    bootleg (year and original_year null), a CD+DVD (20 tracks video) and an instrumental (tagged
    INSTRUMENTAL) - all eight bodies and labels; plus the quirks, the album-as-a-whole fallback, and
    that main.js has no builder of its own. **The undated case's inputs were wrong in the capture**:
    the card's Find fetched /releases, but the capture read its answers before its own fetch wrapper
    had recorded that one and fell back to the search's best-match-releases - another group's
    pressing (Live Weisen 1998). Its `pressings` were replaced with the group's one release as
    MusicBrainz answers it (fetched 2026-10-02, trimmed like the rest, `pressings_note` says so);
    `expected` and `label` - the old page's output - are untouched, and every other case is
    byte-identical to the capture. The orchestrator re-captures the changed old page and diffs it
    with the same file.
  - The type `DownloadRelease` (api/types.ts) is what `FindCandidatesRequest` extends and
    `EnqueueRequest.release` is: every field one the server declares, no index signature left.
- **Get, in two places, both in Search's tab.** "Get the album" on the album you don't have
  (`ReleaseGroupPage.tsx`): under the picker, in the space .13 reserved, the page's one solid purple
  button (`app-rg-get`, full width, the board's download icon `GetIcon` in player/icons.tsx); shown
  only once a pressing is chosen, and it gets THE CHOSEN PRESSING - from `answer.releases` (the
  page reads them through tracklistDiff's types), built with `getGroup()` (lib/pressings.ts: the
  group Search handed over, else the pressings' `release-group`, the chosen pressing's credit
  standing in for a bare group's, and with no group at all its title and the earliest date). And a
  **Get chip** on each "Not in your library yet" row (`Search.tsx`, the row now a `<li
  class="app-result-row">` holding the row's button and the chip - no button in a button): the
  usual pressing (`usualPressing` = representativeRelease) of `/release_group`'s pressings, through
  its own latestOnly (`getRequests`; "Get…" and aria-busy meanwhile), from the session's lists when
  the page or a chip already has them (`app/pressingLists.ts` - the album page's Map, moved to a
  module so both share it; still only complete answers, PRESSINGS_KEPT 20). MusicBrainz failing,
  or breaking the list off, is the album as a whole (`buildDownloadRelease(group, null)`), as the
  main page's card falls back, and the sheet's subtitle says "… · the album as a whole". A row the
  library turned out to hold has no chip. Both take their opener in the tap (`takeOpener`). A
  chip's lookup is called off (`standDown`: superseded, the chip back to "Get") when the box changes
  or Search's root stops being what shows - App's `active` prop, `searchActive` = the Search tab,
  no page on its stack, neither sheet open - so its late answer never opens the sheet over Now
  Playing, another tab or a page (review).
- **What is already here, under Get**: NEW `POST /download/store_state` = `_store_state(request,
  body)` with the Find's body - what find_candidates answers before deciding whether to search
  (held, downloading, downloading_part, other_pressings) and nothing more: no Soulseek search. Same
  pressing, same judgement as a Get. The page asks it for the chosen pressing through its own
  latestOnly (`stateRequests`), again as another is chosen, as an album is filed (`onAlbumsFiled`)
  and as the page shows again (`shown`, from App: its tab current, the Sources sheet closed, the app
  in front - so after a Get it says "Already downloading", and a download cancelled in Requests
  stops being said; out of view it asks nothing). Asked again for the SAME pressing the last
  answer stays until the new one lands (`known` never shows another pressing's), and it draws UNDER
  "Get the album" - above it, an answer landing late moved Get under a finger reaching for it (both
  review) - in a polite live region (`app-rg-store`, taking no room when empty but still drawn -
  VoiceOver reads a region only once it is already there) with
  `StoreState.tsx`: lib/candidates.ts's `storeStatus` (now taking where a download is cancelled:
  'Downloads' on the main page, 'Requests' in the app) and `storeNotes`, as a card and notes - the
  step-2 store's boxes in the app's look; paths break anywhere. `tests/test_store_state.py` (9)
  through start() with real FLACs: held, part held (fills_gaps), downloading with done_files, part
  downloading, another pressing, nothing, no release id, a store that won't open, and the
  same-origin guard - the fake slskd records every search, and every case asserts none.
- **The Sources sheet** (`app/Sources.tsx`, z 25 `--app-z-sources`, a sheet by `useSheet` with its
  own lock `app-sources-open`, focus in to Cancel and back to the Get; App holds it - `sourcesOpen`,
  `getting` (the last Get, kept as it slides away), a new `key` per Get so the same album got twice
  searches twice - and the page behind is inert while it shows: `covered = sheetOpen ||
  sourcesOpen`. It is never open with Now Playing: each covers what would open the other, a chip's
  late lookup is called off before it can open (above), and `openSources` refuses while Now Playing
  is open - `nowPlayingOpen`, a ref set in openSheet's tap and every render - the backstop). Cancel
  and "Choose a source" on one row (`1fr auto 1fr`, the title centred and one line at 320px), the
  subtitle ("Third · CD · 2008 · GB · Island") under them across the head's whole width, wrapping -
  its distinguishing part comes last, and the old ellipsis in an 80px-sided column took exactly that
  at 390, 375 and 320 (review); the chips; one scroller (`touch-action: pan-y`, as Info's).
  - **The search is `hooks/useCandidateSearch.ts`** - CandidatesPanel's orchestration repeated (the
    old panel is NOT refactored, so the main page and merges from main stay safe; the copy goes at
    retirement): one `CandidateSearch` value only the newest search becomes (latestOnly, the
    superseded one called off - and closing the sheet calls it off, which stops it in slskd: Cancel,
    the backdrop and Escape do it IN the gesture, `onClose` = `state.stop()` then the prop, as the
    old panel's close does; the `[open]` effect stays as the backstop. Left to the effect alone, an
    answer landing in the frame before it ran could still pick and queue a source after Cancel);
    each candidate downloads as the release IT was searched for; only an edited query overrides
    (queryOverride); up to ten runners-up as SHOWN; the format preference read per search. The app
    has no format chips, so "clear the format chips per search" has nothing to clear - its chips are
    a floor's, a choice that holds. One download per search (`askedFor`): a second tap before the
    sheet goes asks nothing.
  - **A card** (`SourceCard.tsx`, words in lib/candidates.ts): the score (green from
    AUTO_GRAB_MIN_SCORE's 75 - scoreClass's good band, the one a pick needs - where the board's
    example data used 85; amber under), the folder (ellipsis), "from <peer>" ("· 2 disc folders"
    for a joined set), Get (`is-primary` on the BEST MATCH only - the top of the chips' list by
    score, `sortCandidates(passing, 'score')[0]`, wherever the sort puts its card - `is-tinted` on
    the rest, 32px reaching 44; named "Get <folder> from <peer>", since one peer's FLAC and MP3
    folders were two "Get from bob"s in VoiceOver's rotor - review). **Speed leads** (`speedFact`): `measured` - peer_speed's figure, green, "what you
    got from them", `~` for an average of several (measuredSpeed's hedge) - else `advertised`, the
    peer's own `upload_speed`, "their own average" (never presented as the download speed - the
    rule from "The peer's advertised speed is not your download speed"), else "Unknown", "no speed
    reported yet"; the bar is the speed / `SPEED_BAR_FULL` (3 MiB/s, formatSpeed's units), capped
    at 100. Then Tracks ("11 of 11" - against `audio_expected`, held = audio less missing - amber when tracks are missing), Quality (`qualityText`: "FLAC
    16/44.1", "FLAC 24-bit", "MP3 320k", "MP3 VBR 245k" - only what was reported), Size, Starts
    (`startsFact`: "now" with a free slot, "3 ahead" in their queue, "next" with no slot and nobody
    ahead - the board has only the first two; amber unless now). The amber **Missing** line
    (`missingLine`): 'Missing “Threads”', up to three named, "and N more".
  - **`missing_tracks` on a candidate** (server): `matching.missing_tracks(expected, mapping)`, in
    `score_candidate` where the pairing is - `track_mapping` is dropped before the page - every
    unpaired track in tracklist order as {position, disc, title}; a VIDEO track is never missing
    from a folder of audio, and a release that is all video keeps every track (audio_tracks'
    rule - `matching.audio_tracks`, shared). `_serialize_candidate` sends the first `MISSING_NAMED`
    (5), `missing_count` and `audio_expected` (how many tracks are audio). The card's Tracks counts
    against `audio_expected` (`tracksText`: audio less missing, of audio), so a CD+DVD shared whole
    is "14 of 14" agreeing with the missing line, not "14 of 34" with nothing missing (review); an
    answer without it counts matched/expected as the old panel does. The SCORE still counts every
    track (title_match, track_count - older than this slice; changing it re-ranks everything), so a
    CD+DVD folder still scores low. `tests/test_candidate_missing_tracks.py` (12).
  - **The chips**: Lossless - a new `lossless` flag on lib/candidates.ts's `CandidateFilters`
    (optional, so the main panel builds its filters as before): every file lossless by format, and
    a folder whose formats nobody could tell never passes - 24-bit (minBitDepth 24), Free slot, and
    the sort (a chip holding the platform's own `<select>`, invisible over it, 17px so iOS doesn't
    zoom; the chip shows the choice). They START as the quality floor (`floorFilters`) on every
    Get; a **320 kbps** chip, which the board hasn't, is drawn only while the floor is 320 (or it
    is on), so a floor is never a filter on out of sight. The settings landing after the sheet
    opened re-seed the chips unless they were tapped (`touched`).
  - **States**: asking (the sweep, `searchingLine`: 'Asking Soulseek for “Third” by Portishead…', or
    'by Kanye West or Ye…' - the names search_names asks under, "N/A" left out); slskd unable to
    search (`error`: the find route's 502 detail, i.e. the 409 explanation the server already
    builds, in amber, with Try again); nothing found (`queriesText`, the query to edit and
    Re-search, a `<form>` so Enter works); none passing the chips (Clear filters, shown only with
    some pressed); the store's box where the cards would be (held whole, downloading whole - the
    server searched nothing) and its notes above them; the cards and `searchedLine` ("Searched
    Soulseek for “Portishead Third” · 41 folders, 4 match your filters"). **A 409 from the enqueue**
    ("already downloading from bob", a peer offline) is the pending row in Requests reading
    "refused" with the server's words - the sheet has gone by then; that is .12's refused row.
  - **Get on a card**: `state.download(candidate, shown)` - `requestDownload` called in the tap,
    nothing awaited before it, so the downloads hook (App's one, which registers
    `handleDownloadRequests`) lays the pending row down in that call - then `onQueued`: App's
    `gotten` closes the sheet with its opener cleared (focus has nowhere to land) and
    `router.root('requests')`. Requests' root showing makes the hook poll fast (`watching`), so
    `useDownloadJobs(watching === 'requests' || stalled)` needed no change for Sources.
- **"When I tap Get" and the quality floor** (You > Getting albums, FIRST, as the board has it;
  `GettingChoices.tsx`: two radio groups like LookChoice - the board's disclosure rows made the list
  itself, one tap not two; nothing checked or choosable until deadwax answers). Stored PER USER ON
  THE SERVER: a `user_prefs(user, key, value, updated_at, PK(user, key))` table in store.py (only keys
  chosen have rows, plus routes/me.py's `SEEDED` (`_seeded`), which EVERY save writes, an empty one
  too - the answer's `seeded`, "something was saved for this user"; an old database gains the table
  through SCHEMA's CREATE IF NOT EXISTS) and `GET`/`PUT
  /deadwax/me/preferences` in routes/me.py, through `current_user` (a dependency, as `/me`): the
  allowlist `PREFERENCES` - `get_mode` sources|pick, `quality_floor` any|320|lossless|24bit, first
  the default - a pydantic model with `extra="forbid"` and Literals (anything else a 422, nothing
  written), a stored value no longer allowed read as the default, `stored` (which are set),
  `seeded` and `can_save`; a PUT is a write, so the same-origin guard refuses another site's. 503
  for an unwritable database, or a write it refused. `tests/test_me_prefs.py` (22) incl. a cross-origin PUT
  refused through start(), per user, and the three lists (here, the model, lib/getSettings.ts) read
  as one. The client store `app/useGetSettings.ts` (a module, as useOwned): asked when Search first
  shows, each time You's tab is opened (its new `current` prop) and on Check again, and each time
  the sheet opens - never at start-up - an answer in hand ASKED AGAIN and standing meanwhile (a
  change made on another device arrives in a home-screen app left open for days - review); the
  defaults until the first answer (a Get then shows the sources: the safe way round); SEEDED ONCE -
  a read with `seeded` false and `can_save` PUTs `seedFromPreferences(readPreferences())`, which is
  ONLY what differs from the defaults (the main page's candidate floors in this browser: bit depth
  24 -> 24-bit, 16 -> Lossless, bitrate 320 -> 320 kbps, anything less `{}`; get_mode never -
  auto-grab is not carried over), saved even when empty since the save is the mark; never a default
  stored as if chosen (review: seeding both made a later change of default reach nobody). What
  shows is `confirmed` (the server's last word) with `pending` choices laid over it in order, and
  every read and save goes `inTurn` - each sent once the one before has answered - so answers come
  back in the order asked: an older choice's answer can't put a newer one back, a re-ask can't undo
  a choice being saved, a refused choice goes back to the server's word keeping later ones on top
  ("Not saved: …", in a live region always in You), and deadwax commits the choices in the order
  made (review: the arrow keys sent overlapping PUTs). The main page keeps its own copies
  (configuration.md says so).
- **Auto-pick** ("Pick the best source for me"): in the hook, read as the answer lands
  (`pickingNow`: getSettingsNow() and the chips then), only on a FRESH Get (`start`; Try again after
  a failed search is that Get again, so also fresh) - never a Re-search - and never when
  `autoPickBlocked(result)` (the answer's own store fields: downloading, held complete, a part
  downloading, a part held - another pressing held doesn't stop it); then `autoGrabPick(candidates,
  candidateFilters(chips), 'score')` at AUTO_GRAB_MIN_SCORE or more, asked for as a tapped Get is,
  and the sheet hands over. Otherwise the cards show with `notPickedLine` ("Didn't pick a source
  for you: …"). `autoPickBlocked(result, release)` also refuses a release with no tracklist ("with
  no tracklist to match the folders against, no score can be trusted") or no release id ("with no
  release id, deadwax can't tell whether you already have it"): the album as a whole, a chip's
  fallback, is scored on edition, format and peer alone - a two-track FLAC folder from a fast peer
  reaches 100 - and can't be checked as held, nor 409'd (review). The old panel's auto-grab has the
  same gap on its card fallback and is left as it is.
- **For VoiceOver** (review): the sheet has ONE live region, always there (visually hidden,
  polite, atomic), saying each outcome in a line (`sourcesAnnouncement` in lib/candidates.ts:
  asking, slskd's words, the store's title, nothing found, none passing, "4 sources", plus the
  not-picked line) - the pending block lost its own `role="status"`, which was inserted already
  filled and then removed. Try again, Re-search and Clear filters each end the state they sit in,
  so they first hand focus to the list (`keepFocus`: the scroller, `tabIndex={-1}`, no ring) -
  never to `<body>`, outside the dialog. A closed sheet's asking bar is paused in CSS.
- **app-rules.sim.cjs** (120): the sheets list gains Sources (its lock, inert, backdrop); the
  behind wrapper is `covered`; the page has exactly ONE `app-rg-get` and Search and the picker no
  primary (the chip is tinted); the page and Search reach App's `openSources` with the opener taken
  in the tap; `gotten`; a card's Get is download-then-hand-over in the click, `requestDownload`
  with nothing awaited before it and ten runners-up; the search, the store state and the chip each
  through a latestOnly of its own; a pick only fresh and never blocked; the settings read as the
  answer lands; in the sheet only the best match's Get is primary, the top by score whatever the
  sort; and, after review, the two sheets can't stack (`searchActive`, Search's `standDown`,
  `openSources`' Now Playing guard), Cancel lets the search go in the gesture, and the album page's
  `shown` (asked again as it shows, Get above the store line, no clearing). The pages memo is keyed
  on `sourcesOpen` and `pageShown` too, for that `shown`. No playback action is reached from any
  new file (the allowlist is unchanged).
- **Style** (tokens only): theme.css section 10 gains `--dw-bar-green` (a measured speed's fill) and
  `--dw-best` (#7e4bb8, the best match's edge); app.css gains `--app-rg-get-*`, `--app-store-*`,
  `--app-result-get*`, `--app-z-sources`, `--app-sources-*`, `--app-chip*` and `--app-source-*`.
  Every control a tap target (the chips 30px, a card's Get and a row's chip 32px, each reaching 44
  from its padding box; the chip rows' reaches never overlap - row gap twice the reach - with room
  kept above and below); the sheet placed as Info is (`top: max(48px, safe-top + 8px)`, the insets
  placing it, never padding it). `test_app_css.py` holds all of it (45, seven new: after review
  the head's grid - `--app-sources-side` gone - the wrapping subtitle, the list's focus and the
  paused bar).
- **Not built, on purpose**: Get on the main page's own album pages beyond its Finds (they are
  untouched but for the builder); a Signals or size filter in the sheet (the board has none);
  per-card "Queued" states (the sheet goes as a Get is asked for); the old CandidatesPanel refactored
  onto the hook (merges from main stay safe); the desktop's sources table (S8). `useDownloadJobs`
  polling fast while the sheet shows (the plan suggested it; the hand-over to Requests makes it
  moot).
- **After review** (22 findings, each confirmed by skeptics, all fixed in this same slice and each
  marked "(review)" above): a chip's late lookup opening the sheet over Now Playing, another tab or
  a newer Get (`searchActive`/`standDown`, `openSources`' guard); Cancel leaving the search to an
  effect after the frame; auto-pick on the album as a whole; the store line stale after a Get and
  cleared on every re-ask, ABOVE Get so it moved the button (now under it, kept, asked again as the
  page shows); the settings read once a page and saved with no order (re-asked; `inTurn`,
  `confirmed` plus `pending`); seeding storing the defaults (`SEEDED`, only what differs); Tracks
  counting video (`audio_expected`); the best-match look following the sort; the subtitle's
  ellipsis; no announcement of the outcomes (one live region) or a failed save (a region in You);
  self-removing buttons dropping focus to `<body>` (`keepFocus`); two "Get from bob" buttons; and
  test gaps - which credit each payload field comes from (a synthetic case in payload.sim), the
  `touched` guard and Try again's fresh pick (sources.sim) - and stale words: the credit rules
  above and in the source comments, `getArtistIds` (deleted; credits.sim checks it is gone).
- **Verified**: 2048 Python tests (50 new: `test_candidate_missing_tracks.py` 12,
  `test_store_state.py` 9, `test_me_prefs.py` 22, seven in `test_app_css.py`), pyflakes, tsc, and all 34 sims (`payload` 53 and `sources` 65 new;
  `candidates` 106, `group` 68, `search` 66, `you` 61, `app-rules` 120 and `credits` 25 extended); 74
  mutations, one or more per rule pinned, each caught and restored byte for byte - four first got
  past (an untrimmed disc title, a superseded store answer for the same pressing, a chip's
  called-off answer landing anyway, a broken-off list kept) and gained the checks that catch them -
  and after review 48 more, one or more per fix, every one caught.
  The engine guard is empty, and `useDownloadJobs.ts`, `downloads.sim.cjs`, `CandidatesPanel.tsx`,
  `player.sim.cjs` and `test_enqueue.py` are untouched. (`test_player_cache.py::
  test_a_setgid_bit_is_no_bar` fails when pytest runs with TMPDIR pointed at the session scratchpad,
  as the sims need: macOS won't set setgid on a folder whose group, wheel there, the user isn't in.
  Untouched by this slice; it passes with the ordinary TMPDIR.)
  **NOT verified here**: the real page (the orchestrator builds the bundle and checks against a
  fake slskd serving Third's folders - a measured peer, a busy peer, a 24/96 rip, one missing
  "Threads" - and re-captures the old page's Find bodies to diff with find-buttons.json); a real
  slskd and real Soulseek folder names; and everything on the iPhone - the sheet scrolling under a
  finger with the page still, the sort's wheel, a tap above the sheet, a Get showing in Requests
  from the tap, VoiceOver on the cards, its live region and where its focus lands after Try again.
  After review, also for the real page: a chip's slow lookup with Now Playing opened meanwhile
  (nothing opens), the subtitle wrapping at 320/375/390, and the store line under Get coming back
  as "Already downloading" after a Get.

### Artists who have renamed (v0.6.18)

James: "so Ye shows up as Kanye, that seems like a gap somewhere" - and then "I want to make
sure there won't be a ye folder and a kanye folder ... there should just be one folder with the
most up-to-date name".

- **MusicBrainz keeps ONE current name per artist and every other name as an alias, while each
  release keeps the name it was CREDITED under.** Those two disagree for everyone who has ever
  renamed, and deadwax writes the credit into the tags and the folder - rightly, the album
  really was credited that way - so **the name on disk is the one MusicBrainz no longer answers
  to**. Ye is credited "Kanye West" on all but two of his own albums.
- **`artist:"..."` matches the current name ONLY.** Measured against the live API:
  `artist:"Kanye West"` returned "Kanye West Tribute Band" (score 100) and "Kanye West &
  Hatsune Miku", and **Ye was not in the answer at all**. So the artist page could not resolve
  him, and the picker's search box - the documented escape hatch for exactly this - offered a
  tribute band as the first thing to click. `artist_query()` asks
  `(artist:"X" OR alias:"X")` now, which puts Ye back at 100. Bracketed, so anything ANDed on
  later cannot split the OR - the same trap as the type filter.
- **The exactness test had to learn the same thing, and the query alone would not have been
  enough.** `_resolve_artist_mbid` compared against `a["name"]`, which is "Ye" - so even with
  the artist found, "Kanye West" != "Ye" and it still refused. `answers_to()` compares against
  every name they go by (name, sort-name, aliases). **This makes the guard refuse MORE often,
  not less**: a second artist answering to the same name fails the `len(exact) == 1` test
  exactly as two bands called Nirvana always did. Verified live - Nirvana and Cat Stevens (the
  musician and a photographer) are both still refused and offered as a choice.
- **How a name was TYPED is not a difference.** MusicBrainz sets names properly: JAY-Z is
  `JAŸ‐Z` and is credited `Jay‐Z`, both with a U+2010 HYPHEN, while any folder a person typed
  has a plain hyphen-minus. MusicBrainz's own index folds this (it answers the search at score
  100); only our comparison missed. `_fold()` strips combining marks and maps the dash and
  quote families to ASCII before comparing, so `Motorhead` finds Motörhead and `Bjork` finds
  Björk. It is still WHOLE names only - "Bjork Gudmundsdottir" matches nothing - because the
  refusal-on-ambiguity guard is what makes an automatic match safe at all.
- **The match rows carry `matched_as`**, the name that matched in its own spelling, and the
  picker shows it when it differs from the artist's current name. Search for Kanye West, get an
  artist called Ye, and without it nothing on screen connects the two.
- **The artist page says "Now" when MusicBrainz calls them something else** than your folder
  does. Rendered only on a difference - unconditionally it would print the folder's own name on
  the page twice.
- **`facts["aliases"]` no longer lists the artist's own name**, and ranks MusicBrainz's "Artist
  name" aliases ahead of its "Search hint" ones (which are deliberate misspellings, there to be
  found by). It read "Ye, KanYeWest, Donda, Kanye, K. West, Kayne West" - their own name, then
  two typos, before "Kanye West" ever appeared. It reads "Kanye West, カニエ・ウェスト, Kanye,
  Yeezy" now.
- **An album is FILED under its artist's current name, and the credit stays where it is read.**
  Filing by the credit gave one artist a folder per name: Donda (credited "Kanye West") went to
  `Kanye West/` and BULLY (credited "Ye") to `Ye/` - and the library tree, which groups on the
  albumartist tag, showed two artists too. MusicBrainz carries both names in every credit:
  `artist-credit[].name` is the sleeve, `artist-credit[].artist.name` is the artist now. So the
  payload carries both, and they go to different places on purpose:
  - `artist` - AS CREDITED. The Soulseek search is built from it and the matcher scores against
    it, because a sharer's folder is called "Kanye West - Donda", never "Ye - Donda". It is also
    the track `artist` tag (via each track's own credit), which is what the sleeve says.
  - `album_artist` - the CURRENT names, joined with the credit's own join phrases. It names the
    folder AND the `albumartist` tag, through `filed_artist()` in organizer.py.
  **Those two must move together**: `_is_misfiled` compares the folder with the album artist,
  so renaming only the folder would put every renamed artist's whole discography in the queue.
  **Verified with live MusicBrainz payloads through the real `credits.mjs`**: Donda, BULLY and
  The College Dropout all file under `Ye/`, while Soulseek still searches "Kanye West".
- **There are TWO ways a download starts, and the first cut of this missed one.** Find on a
  release ROW goes through `buildExpectedFromRelease`; Find on the release-group CARD goes
  through `buildExpectedFromReleaseGroup`, which builds its own payload from the group's
  context and had never carried anything but the credit - not even the artist ids, so a
  download started from a card was tagged with no `musicbrainz_albumartistid` at all. Every
  test passed with the gap open, because no test reaches main.js: it was found by clicking Find
  on a card in the real page and reading the request, which had no `album_artist`. The group
  context now carries `albumArtist` and `artistMbids` from the group's own credit. **Anything
  added to a download's payload has to be added in BOTH builders** - and checked by clicking
  both buttons, since only one of them is on the path any sim can see. **Superseded in
  2.0.0-player.15: there is ONE builder now, `ui/src/lib/releasePayload.ts`**, used by both of
  main.js's Finds (through the bridge's `buildDownloadRelease`) and the app's Get, and pinned by
  `ui/test/payload.sim.cjs` to the bodies the two Finds sent before the move - anything added to a
  download's payload goes THERE (see "Sources and Get").
  **Verified in the real page** (scratch database and library, slskd stubbed as logged out):
  both Finds send `artist: "Kanye West"` and `album_artist: "Ye"` with Ye's id; the row's
  carries all 32 tracks, each still credited "Kanye West".
- **`album_artist` is DECLARED on `EnqueueRelease` and `RetagRelease`** - the pydantic trap a
  third time (after `disc` and the track artist). A job queued before it existed has only
  `artist` and files exactly where it always would have; `filed_artist()` falls back.
- **The editor seeds its artist field with the current name when a release is PICKED**, so a
  correction lands where a fresh download of the same release would. Only then - an album's
  own release auto-selected on opening still seeds nothing, so opening the editor never
  rewrites what is on disk by itself. **This is the only way an album already filed under an
  old name moves**; nothing finds them automatically (see below).
- **...which broke the editor's own search, and had to be fixed with it.** `artist:` on a
  RELEASE GROUP matches the credit only, so once the field held "Ye", `releasegroup:"Donda" AND
  artist:"Ye"` could no longer find the Donda credited to Kanye West - measured, through
  deadwax's own client: the old query found 2 groups and not that one. `fieldedAlbumQuery()`
  asks `(artist:"X" OR artistname:"X")`, and `artistname:` is what matches the current name:
  10 groups, the real Donda among them. Without it every album filed by its current name could
  no longer find its own release group. The placeholder shows the same string.
  **Verified in the real editor** on a legacy `Kanye West/Donda (2021)`: opening it changed
  nothing, picking a release seeded "Ye" and previewed `Kanye West/Donda (2021) → Ye/Donda
  (2021)`, and re-searching with "Ye" in the field still listed Donda's releases.
- **The rule for the current name lives in TWO places, and a sim holds them to one answer**:
  `getCurrentArtistNames()` in `interface/scripts/credits.mjs` names a download's folder and
  `currentName()` in `ui/src/lib/release.ts` seeds the editor's. The credit helpers moved out
  of main.js into `credits.mjs` for this - main.js touches the DOM at module scope and cannot
  be imported by a test, the same reason `sort.mjs` exists - and `ui/test/credits.sim.cjs` asks
  every case of BOTH copies. If they drift, one album goes to one folder when downloaded and
  another when corrected. **Superseded in 2.0.0-player.15**: a download's folder now comes from
  release.ts's `currentName()` too, through `lib/releasePayload.ts` (the one payload builder), so
  a download and a correction are one function and can't part. credits.mjs's
  `getCurrentArtistNames()` is left only DRAWING - it is a name the main page's card tries for
  its "in your library" match - so a drift between the two copies now marks a card wrong and
  files nothing anywhere. The sim still asks both.
- **Collaborations still get their own folder**, in current names: Watch the Throne files under
  `JAŸ‐Z & Ye/`. That was always so (it was `Jay‐Z & Kanye West/`); only the names changed.
- ~~NOT built: finding albums already filed under an old name~~ **Built in v0.9.14** - the scan
  reads the album-artist ids and notices, and the artist page moves them. See "One artist under
  two names".

### Searching Soulseek under every name (v0.6.19)

James: "make sure the same logic with ye works with the slskd search".

- **The matcher never looks at the artist; the QUERY is the only place a name decides
  anything.** `score_candidate` scores tracks, count, durations, edition, format and peer - not
  one signal reads the artist - so a share filed as `Ye/` and one filed as `Kanye West/` score
  identically once found. Finding them is the problem: Soulseek needs EVERY word of a query in a
  share's path, so "Ye BULLY" cannot find `Kanye West/BULLY` at all, and "Kanye West Donda"
  cannot find `Ye/Donda`.
- **So it searches under every name a share might carry**: the CREDIT (what the album said when
  the sharer got it), the CURRENT name (what deadwax and Picard's standardised names file
  under), and FORMER names (what someone who never re-filed still uses). `search_names()` in
  routes/download.py orders and dedupes them; an artist who never renamed is exactly one search.
- **A former name is one MusicBrainz itself marks as former: an ENDED "Artist name" alias.**
  Ye's record says exactly that of "Kanye West" (ended 2024). The rest of his aliases are not
  folder names - "Kanye" and "Yeezy" are live nicknames, "Kanye Omari West" is a legal name, the
  zh/ja entries are other languages' spellings - and each name costs a Soulseek search, so
  `former_names()` is deliberately that narrow. Where editors never marked a name as ended there
  is nothing to find and it degrades to credit + current, never to worse. Single-artist credits
  only: a collaboration's names multiply, and its credit and current names are searched anyway.
- **The alias lookup runs BESIDE the first round of searches, not before it.** It is a
  MusicBrainz request, and MusicBrainz takes 30-60s on a bad day; looked up first, every search
  of every album would have waited on it. Beside the first round (credit + current, which take
  their full search timeout anyway), an artist who never renamed pays nothing even when
  MusicBrainz is slow. A former name the first round didn't already cover is a SECOND round -
  the only case that costs a second search's wait. `FORMER_NAMES_BUDGET_SECONDS` bounds the
  lookup; past it, the search goes on without former names. `get_artist_aliases()` is its own
  light request (`inc=aliases`) rather than the artist page's heavy one, and its own cache key.
- **The searches in a round run side by side** (`SlskdClient.search_all`). slskd's
  one-at-a-time limiter covers only STARTING a search - `StartAsync` returns once the search is
  under way - so the starts go strictly in turn and the waiting is shared: two names cost barely
  more than one. A refusal with nothing running is the answer (a logged-out slskd refuses every
  search alike, so the rest are not asked); a refusal once one IS running narrows the search and
  is logged, rather than failing it. `search(query)` is now the one-query case of this.
- **The same file can come back from two searches**, from a share whose path holds both names
  (`Kanye West/Ye - Donda`). `group_files_by_directory` keeps each (user, file) once - otherwise
  the album counts its tracks twice, scores on a count it doesn't have, and is enqueued with
  every file requested twice.
- **`FindCandidatesRequest` had been DROPPING `album_artist` and `artist_mbids`** since v0.6.18:
  the browser sent them and pydantic discarded them without a word - the trap a fourth time.
  Both are declared now.
- **Re-search only overrides when the query was EDITED.** The box shows the first of possibly
  several queries, and re-searching sent the box's contents as an override - so pressing it
  unchanged would have quietly searched one name of several. Hovering the box lists the others,
  and "no matches" says every name it tried. That message is built with `textContent`: the
  queries are MusicBrainz's names, third-party text. (The vanilla half has `esc()` since v0.9.22
  for what still goes in as markup; text is still the better way where it fits.)
- **Verified** over real HTTP against a stub slskd holding one share of BULLY filed under
  `Kanye West/`, which matches the way Soulseek does, with the alias lookup going to LIVE
  MusicBrainz: before, "Ye BULLY" and nothing; after, MusicBrainz gave "Kanye West" as a former
  name, the second round searched "Kanye West BULLY", and the share came back scoring 1.0.
  **NOT verified: a real Soulseek network.** Whether its matching tokenises the way the stub
  does is inferred from the S&M2 failure (see "Never take a word apart"), and whether a
  two-letter term like "Ye" is honoured, ignored or too broad is unknown.

### A filed album appears on its own (v0.6.19)

James: "when a new album gets organized, it takes quite a while for it to actually appear".

- **It did not take a while; it never appeared at all until Rescan or a page reload.**
  `useLibrary` loads once, when the tab is first opened, and deliberately never on a timer or on
  switching tabs (a scan stats every folder). Nothing told it an album had been filed, and the
  tab's "new" badge polled once a minute. Meanwhile the downloads poll - running in the
  background whenever anything is downloading - watched the job turn `organized` and told nobody.
- **The downloads poll says so now**, through `ui/src/lib/libraryEvents.ts`:
  `newlyOrganized()` compares each poll with the last, and `announceAlbumsFiled()` tells the
  library (which scans, if it has been opened) and the badge (which recounts). Three rules that
  are pinned in `downloads.sim.cjs` because each is easy to break:
  - **`organized` only.** The poller marks a job `complete` and THEN organizes it, so reacting
    to `complete` would scan for an album that isn't there yet.
  - **The first poll after the page loads only seeds.** Otherwise every album filed before you
    arrived announces itself on every page load.
  - **It must be caught on the tick that sees it.** With the panel closed the poll STOPS once
    nothing is active, so the tick that sees `organized` is usually the last one. The previous
    statuses live in a ref at the hook's level, not inside the effect, because the effect
    restarts whenever the panel opens or a download is enqueued.
- **A module, not a bridge entry.** Every Preact root renders from one bundle and so shares
  module state; the window bridge is for reaching the VANILLA half, and adding Preact-to-Preact
  signals to it would muddy "an empty bridge means the migration is done". (`refreshNewImports`
  predates this and still goes through the bridge.)
- **The library still never scans unasked**: it hears the announcement only once it has been
  opened, and waits `FILED_GATHER_MS` so several albums landing together are one scan.
- **The downloads poll quickens to 1s while a job is `organizing`** (`POLL_FILING_MS`). At the
  5s background cadence the album appeared up to five seconds after landing. It costs nothing
  against slskd: the server asks slskd only about queued and downloading jobs, so these polls
  are one read of deadwax's own job table.
- **Measured in the real page** (scratch database and library, the job driven through the same
  store calls the poller makes, downloads panel closed): never, before; 5.6s with the
  announcement alone; **1.5s** with the quicker poll while filing. No Rescan in any run.

### Artist credits, and the ids behind them (v0.6.15)

Asked for as "better handling for multi-artist albums and tracks", and "get artist ID in the
metadata as well".

- **A credit's JOIN PHRASES are its punctuation.** MusicBrainz says "A / B" for a split, "A & B"
  for a collaboration, "A feat. B" for a guest spot, and it says so in `joinphrase` between the
  names. Joining on ", " - which every part of this interface did - invents punctuation nobody
  chose and flattens a duet into what reads as two separate acts. The rule lives in TWO places
  that must agree: `creditName()` in `ui/src/lib/release.ts` and `getArtistNames()` in
  `interface/scripts/credits.mjs` (moved out of main.js in v0.6.18 so a sim can reach it). One
  names a folder, the other writes the tag inside it - both in the browser, which sends the
  server names already joined. (A third copy, `credit_name()` in `src/artists.py`, was called by
  nothing but its own tests and went in the v0.9.19 audit.) Since 2.0.0-player.15 a download's
  artist comes from release.ts's `creditName()` (through `lib/releasePayload.ts`), and
  credits.mjs's `getArtistNames()` only draws the main page's card credit; its `getArtistIds()`,
  which only the deleted builders used, went in the review.
- **A track keeps its OWN artist.** `tag_values` gave every track the release's artist, so
  applying a release to a compilation rewrote eighteen artists into one. The track's credit wins
  where it has one; `albumartist` stays the release's, which is what the two tags are for.
  **Until v1.0.10 that held for downloads only.** `execute_retag` rebuilt each track from its
  plan entry's title, number and disc, so the editor PREVIEWED each track's own artist and then
  wrote the release's on every one - Various Artists over a whole compilation. A plan entry now
  carries the matched `track` whole and the apply writes that. `test_credits.py` had tested
  `write_tags` alone, which is why it never showed; the new test goes through plan and apply.
- **The artist ids are written at last**: `musicbrainz_albumartistid` and `musicbrainz_artistid`.
  Nothing deadwax filed had ever recorded WHO an artist was, only which release - which is why
  the artist page has to fall back to searching by name at all.
- **One id is a string, several are a list**, and `read_current_tags` reads back the same shape.
  Get that wrong and a file disagrees with itself on every preview: a bare string on one side, a
  one-item list on the other, and an album that can never again say "nothing to change". Pinned
  by a round-trip test that writes a file and re-previews it.
- **`Track` in the download request declares `artist` and `artist_mbids`.** Same trap as
  `disc`/`disc_position` before it: pydantic drops undeclared fields without a word, so a
  compilation would arrive correct from the browser and be filed under one artist anyway.

### The settings tab

- **More settings in v0.9.16**, all on the Downloads tab: where the candidates panel's Quality
  floors (bitrate, bit depth) and its sort START (`candidateMinBitrate`, `candidateMinBitDepth`,
  `candidateSort` - browser preferences, validated against exactly the values the dropdowns
  offer), and `SLSKD_SEARCH_TIMEOUT` (server, 3-60s, default 8 as it always was; a new
  "Soulseek searches" group, `max_wait` = timeout + 17).
- **Auto-grab had been wired to NOTHING - found while laying out the tabs.** "Auto-grab best
  match" was a checkbox, stored and read (`getSettings().autoGrab` in main.js), and no code ever
  acted on it; the reader then went with the vanilla candidates panel in v0.9.10. CLAUDE.md's
  own rule is that every preference is genuinely wired to behaviour. It is now (`autoGrabPick`
  in lib/candidates.ts): on a fresh FIND only, never a Re-search; the top of the list through the
  default filters and sort; only at `AUTO_GRAB_MIN_SCORE` (75, the "good" band) or better, since
  a weak best match is exactly when you want to choose; and the panel says it did it. The pick
  goes through the same download path, runners-up and all. **Verified in the real page**: with
  auto-grab on and a 24-bit default, a Find queued the 24/96 peer by itself - pending row in the
  downloads panel, "Queued ✓", the note - with the Quality badge at 1 and the sort on quality.
- **Tabs since v0.9.15** (asked for: "some tabs for settings organization instead of a long
  list"): Search, Downloads, Library, Connections, Interface, in a strip outside the scroller
  so it never scrolls away. Server groups are placed by `tabForGroup()` - `connections`,
  `downloads`, and everything else (paths, organizing, cover art, lyrics, and any group added
  later, so nothing is ever unreachable) under Library. `tabMarks()` puts an amber mark on a tab
  with a setting whose status is `error` (Library also when organizing is blocked) and an
  accent dot on one holding an unsaved edit - drafts span tabs and the save bar still saves all
  of them, so an edit must not hide behind a tab you've left. The last tab is remembered in
  `deadwax-settings-tab` (the literal id, validated on read). The server's AUTO_RETRY_PEER group
  is labelled "When a download fails", beside the client's own "Downloads" section on that tab.
  **Verified in the real page**: each tab showed its sections, an edit on Search marked Search
  while Library was open, the choice survived in storage, and at 375px the strip wrapped to two
  rows with no overflow.

- **The server half is EDITABLE as of v0.5.1**, via exactly the persistence story the
  previous version of this note said it would need: a `settings` table in the sqlite DB, with
  the environment as the fallback. It is NOT written to `.env` — editing that from inside the
  container would not affect the running process and would be discarded on the next
  `docker compose up`.
- **A stored override WINS over the environment, and that is the only honest precedence.**
  The alternative — environment wins — means an edit made in the tab silently reverts on the
  next restart for anyone configuring through compose, which is most people and everyone whose
  stacks are managed for them. So the override wins, the row says it is overriding, and it offers to revert.
- **Reverting DELETES the row rather than writing the environment's value back.** Copying the
  value back would pin whatever compose said that day, so a later compose change would
  silently stop taking effect. Absence is the only representation of "follow the environment"
  that stays true.
- **`Config.ENV_VALUES` is captured ONCE and must stay that way.** `apply_overrides()` mutates
  the class attributes, so re-capturing on a later call reads back values a previous call
  already overwrote — and the real environment value is gone for good. That bug shipped
  briefly and made "revert" delete the row and then change nothing, because there was nothing
  left to restore. Both directions are now tested.
- **What cannot be edited, and why, is rendered rather than hidden.** `DB_PATH` is the
  database the overrides live in; `PUID`/`PGID` are consumed by `docker-entrypoint.sh` before
  Python starts. A disabled control with no explanation reads as a bug.
- **Validation splits DEFINITIONALLY wrong from ENVIRONMENTALLY wrong.** An `ORGANIZE_MODE` of
  "sideways" is refused because it can never work. A path that doesn't resolve is STORED and
  reported, because it may be a volume you are about to mount — and refusing it would mean the
  only way to fix a broken setup is to edit compose, which is what this tab exists to avoid.
- **So the endpoint's job is DIAGNOSIS.** It answers the three questions someone actually
  has: what value did the container receive, which file do I edit to change it, and what is
  wrong with it. The middle one is the one that is genuinely hard from outside — once
  `load_dotenv()` has run, a compose value and a .env value are indistinguishable in
  `os.environ`. `config.py` captures that at import time and `setting_source()` reports it.
- **Paths are RESOLVED, not echoed.** `_describe_path()` stats every configured path and
  checks readability, and writability where it matters. A path that exists on the host but
  not inside the container is the most common first-run failure in this project and it is
  completely invisible from the string — which looks correct, because it is correct, just
  not from in here.
- **The API key never reaches the browser.** The row reports `set` or nothing. `THEAUDIODB_KEY`
  (v0.6.15) is declared `secret` for the same reason and is masked the same way. This payload
  renders on a page people screenshot into bug reports. A test asserts the key's value does
  not appear anywhere in the payload.
- **slskd's address takes the key again, and holds no login (1.0.5)** - the rule 1.0.3 made for
  Navidrome, asked for. Anyone who can reach deadwax can PUT a new `SLSKD_URL` (a write with no
  Origin passes SameOriginWrites by design), and the next ping or search would have carried the
  saved `SLSKD_APIKEY` - full control of slskd - to it.
  - `SECRET_FOR_ADDRESS` (settings.py) pairs each address with its secret and the sentence a
    refusal gives; `_moved_without_secret()` refuses a batch that changes either address from its
    current value (stripped) without a non-empty secret beside it. The exceptions are
    Navidrome's: the same value, reverting (the environment's address is the admin's), and no
    secret set yet. Clearing is too, though an empty `SLSKD_URL` is refused anyway, as required.
    Reverting or blanking the secret is not typing it. An address that fails validation is told
    that, not this.
  - **One URL check for both**, `_describe_address()` in config.py, each caller passing its own
    words: no login, no `?`/`#`, no space, a numeric port, a host; a PATH is allowed (slskd's URL
    base survives slskd_api's urljoin - measured). That urljoin quietly DROPS a `?` or `#`, so for
    slskd they are refused for reading as something they aren't, not for swallowing a path as
    they do in httpx. **Nothing quotes the value back** - slskd's old "use http://<value>" did.
    `get_client` already ran `describe_slskd_url()`, so an environment value is refused by the
    client with no change there (the pill reads `UNKNOWN_ERROR`, the Log says why).
  - **The cost:** a reverse proxy in front of slskd with a login in the URL no longer works
    (requests sent it as basic auth, beside the key). Point deadwax at slskd directly.
  - **The payload masks a login in an address** (`_setting(address=True)`: `LOGIN_MARK`, `•••@`,
    in `value` and `env_value`, for SLSKD_URL and NAVIDROME_URL). One can only come from compose
    or .env now, and it is still a password. Marked rather than dropped, so the row's "has a user
    name or password in it" has something to point at. `without_login()` moved to config.py and
    reads the authority by hand: urlsplit finds no host in a scheme-less `me:pw@host` and handed
    it back whole.
  - The tab's note beside the secret is `retypeSecretNote()` (SettingsView.tsx), from a table
    mirroring `SECRET_FOR_ADDRESS`; it replaced `navidromePasswordNote`.
  - **Verified in the real page** against two listeners logging `X-API-Key`: a new address with
    no key showed the red note on the key's row, Save gave the refusal in the save bar and the
    collector received nothing; with the key typed, one save stored both ("Set here") and the
    next ping reached the collector carrying only the typed key.
- **Only `error` is decorated.** An unset OPTIONAL setting renders plain. When every row
  carries a colour, the row that needs attention stops standing out, which is the list's
  whole job.
- **The organizing verdict is derived server-side and stated once**, with every blocker
  listed at the same time. "Why did nothing get filed" has four possible causes across two
  groups; discovering them one at a time is how people conclude the feature is broken rather
  than misconfigured.
- **Client preferences are a separate storage key (`deadwax-preferences`), not more fields
  on `deadwax-download-defaults`.** That older blob is read and rewritten wholesale by
  `main.js` too, so any field it did not know about would survive only until the next time it
  saved. New key, one writer.
- **Every preference is genuinely wired to behaviour**, and the vanilla half reads them at
  the point of use rather than caching at load — so a change in the settings tab applies to
  the next action without a reload. `PREFERENCE_FALLBACK` is duplicated in `main.js` because
  the two files are separate ES modules that cannot import each other; **keep the two copies
  in step** until the search view is ported and the duplicate goes away.
- **"Studio only" as a default still shows in the button label.** A filter that is silently
  on is a search that quietly returns less than you asked for, which is the exact failure the
  visible label exists to prevent — see the search-type-filter decision above.

### The v0.5 design system

The brief was "snappy, and modernise the dated aesthetic". The direction chosen was **modern
foundation, keep the signature**: the ASCII wordmark, the purple accent and monospace data
stay; the CRT overlay, the text-glow and the ░▒▓ chrome go.

- **`theme.css` is the token layer and the only place raw values belong.** Colours, type
  sizes, spacing, radii, shadows, durations and easings are all defined there once. This is
  load-bearing *because the migration is unfinished*: `main.css` styles the vanilla half and
  the Preact half, so one token edit restyles both together and the two can't drift apart
  while they coexist. A hex code or a px size typed into a rule defeats that.
- **The type scale is REM, and that is the whole point.** The old sheet was ~15 unrelated
  `em` sizes, which COMPOUND through nesting — the same `<h4>` rendered at different sizes
  depending on where it sat, and each value had been hand-picked to look right after
  whatever compounding applied at that spot. That is also why it could never be fixed by
  setting a base size on `body`: the headings scaled with it. rem resolves against the root,
  so a step means one thing everywhere and the interface can be rescaled from one line.
- **The glow tokens still exist and resolve to `transparent`.** ~23 `text-shadow` rules
  reference them. Neutralising the tokens switched every one of those off without editing
  them, which makes the CRT bloom one edit to restore and one edit to remove. That is why
  they weren't deleted — resist tidying them away.
- **The bundled scene font is unreferenced, not deleted.** All 30 `@font-face` rules went and
  the UI uses the platform's own stacks; the `.otf` files are still on disk and in git. This
  app is self-hosted and often runs with no internet at all, so a webfont CDN was never an
  option — local stacks are the only honest choice, and they cost nothing to load.
  **Superseded in v0.6.7: the files are DELETED, on James's instruction.** Their name table read
  "TX-02" and "Berkeley Mono ... Copyright 2022-2024, U.S. Graphics LLC. All Rights Reserved",
  and the `SCT.nfo` beside them was a scene release note - a commercial font with no licence to
  redistribute, sitting in a public repo. **They are still in git history** before v0.6.7;
  scrubbing that means rewriting and force-pushing the branch, which has NOT been done and
  should not be done without asking. Don't bring any of it back. The interface face is now a
  bundled, openly licensed Noto Sans - see the entry on it below.
- **The wordmark is figlet-style ASCII art and therefore needs `--font-mono`.** It used to
  inherit a *proportional* face, which is why the letterforms never quite lined up.
- **The foundation layer at the top of `main.css` is written with `:where()`, so it carries
  ZERO specificity.** The ~3,500 legacy lines below beat it on any property they actually
  set, and it only fills in what they never mention. That is what made it safe to add a
  baseline to a stylesheet whose own header calls it an abomination: it cannot take anything
  away. Keep new baseline rules inside `:where()`.
- **Overlays animate via `@starting-style` + `transition-behavior: allow-discrete`.** Every
  dropdown here is toggled by swapping `display`, which is a discrete property — the panel
  simply existed on one frame and not the one before, and that hard cut was most of why the
  app read as abrupt despite never being slow. Browsers without support ignore both and get
  the instant show/hide it always had, so there is no fallback to write.
- **`prefers-reduced-motion` is handled once, in `theme.css`, by collapsing the duration
  tokens** rather than by redefining animations. One block therefore covers every transition
  in both halves — including ones written after it.
- **v0.6.5 took a step back from "modern", on request: "a touch more of a Windows 7 feel".**
  A TOUCH - the dark palette, the purple accent and the monospace data stay. What came back is
  Aero's shapes: radii pulled in to 2/3/4/6px, glossy two-tone fills with a hard midline,
  a 1px top highlight on anything raised, gradient toolbars/captions/status bar, and
  Explorer's selection (translucent gradient in a thin border; grey when the list isn't
  focused). All of it is section 9 of theme.css plus ONE block in main.css ("A TOUCH OF
  WINDOWS 7", just above the responsive blocks) - so it can be dialled back from the tokens,
  the same arrangement as the glow tokens. A full light-and-blue Aero palette would be a
  different theme, not a touch; don't drift there without being asked.
- **The interface face is Noto Sans, bundled (v0.6.7).** Picked by James from six candidates
  set side by side (system UI, Segoe UI, Tahoma, Verdana, IBM Plex, JetBrains Mono). It is
  SELF-HOSTED woff2 in `interface/styles/font/noto-sans/`, served by the app itself, which is
  what squares it with the no-CDN rule: it works with no internet, like everything else here.
  One variable-weight file (300-700) per script, split by `unicode-range` exactly as Google
  Fonts splits it, so a browser fetches only the Latin file (~the only one most pages need)
  unless a name on screen is Cyrillic, Greek or Vietnamese. Devanagari was deliberately left
  out. Noto Sans is used on EVERY device - not "Segoe UI first", which was the option's label -
  because what James saw and liked was Noto (his Mac has no Segoe), and Segoe-first would make
  Windows look different from the choice. The mono data face is unchanged. `OFL.txt` ships
  beside the files, as the licence requires. The "0 font bytes on load" figure in the
  performance table below is therefore now one 35 KB Latin file, cached; all seven together
  are 342 KB, of which Latin Extended (164 KB) is the one a European name will pull in.
- **Checkboxes, not switches (v0.6.6), for every checkbox in the app.** The settings tab's
  sliding switches were the one phone idiom left; they are plain checkboxes now, drawn by one
  `input[type="checkbox"]` rule in the Windows 7 block (a sunken square, a gloss on hover, a
  drawn tick) so the vanilla candidate filters and the editor's boxes match them. In a settings
  row the box sits BEFORE its label (`.settings-row:has(.settings-check)`), where a desktop
  checkbox lives. Radios got the same well, round with a dot, so the settings tab's format
  choice matches. The old `accent-color` rules on individual inputs are inert now. The
  `#format-preference-select` rules (and the rest of that dead profile-popover block) were
  deleted in v0.9.18.
- **Accent is spent, not sprinkled.** Solid purple fills appear on exactly three controls:
  Search, the metadata editor's Apply, and the tag editor's Apply (v0.6.9). Both Applies write
  tags to disk with no undo, so they must not look like the Cancel button beside them.
  Everything purple used to be purple — three accent-coloured boxes sat in the top bar — and
  when everything is accented the accent marks nothing.

## Gotchas discovered the hard way

Each of these cost real time. Don't rediscover them.

### Interface and CSS

- **`theme.css` is `@import`ed from `main.css`, so it caches independently.** Editing the
  palette and reloading shows the OLD colours. Bust it explicitly when verifying, and
  hard-refresh after deploying.
- ~~Text colour classes are element-scoped~~ **Fixed at the root.** Colour was an element ×
  colour matrix (`h4.default`, `h5.white`, `span.white-secondary`…), so every unforeseen
  pairing inherited instead — `<div class="text white-secondary">` had no rule and rendered
  black on black. There are now element-agnostic `.white`, `.default-secondary` etc. at lower
  specificity than the legacy rules, so old pairings are untouched and new ones just work.
  **`body` also sets `font-family` and `color`**, so a missed element now degrades to looking
  ordinary rather than disappearing. Prefer the generic classes for new markup.
- **Nothing had set a font on `body`**, so any element without its own rule fell back to
  Times at 16px. That is how the releases-grid `▷` arrows and `#results-summary` shipped in
  a serif face. Fixed by the `body` baseline above.
- **A Preact `useEffect` that writes to a DOM node outside its own tree is unreliable.** The
  tab bar set `data-tab` on `#main-container` from an effect; when the tab was changed by a
  click originating in the *library* tree, the effect didn't fire and the button highlighted
  while the panes never swapped. Cross-tree DOM writes belong in the shell (`main.tsx`),
  done synchronously. Symptom to recognise: the component looks right, the page doesn't.
- **The layout had no media queries at all until v0.3.x.** On a 375px phone it produced
  1131px of content — 756px unreachable off the right edge, with the entire top-bar actions
  row off-screen. Three causes: `#top-bar` was a nowrap flex row of `flex-shrink: 0`
  children, `#main-content` put a fixed 220px filter column beside the content leaving 155px,
  and the dropdown panels were 440–460px wide. **Anything new with a fixed px width needs a
  mobile rule**, and the responsive block at the bottom of `main.css` is where it goes.
- **THE RESPONSIVE BLOCKS MUST BE THE LAST THING IN `main.css`, and they had stopped being.**
  About 460 lines of unmediated rules were appended after them across several changes, and
  any of those with equal specificity beats the mobile rule *at mobile widths*. The failure
  is horrible to spot because it is completely silent: the mobile rule is present, it reads
  correctly, and it simply never applies. It cost real time in v0.5.3 — one-field-per-row in
  the metadata editor was written, confirmed present in the sheet, and did nothing, because
  `.metadata-fields > .metadata-field { flex: 1 1 45% }` sat a hundred lines below it. Both
  blocks now live at the end under a comment saying so. **New rules go above that comment.**
  The 420px block also has to stay after the 768px one, since a 375px screen matches both.
- **Right-align the library toolbar from the SUMMARY, not from each button.** Every trailing
  control used to carry its own `margin-left: auto` plus a rule cancelling the one before it,
  so adding a third button meant adding another override — and two live auto margins split the
  free space instead of pooling it, putting a gap in the middle of the group. `#library-summary`
  takes the slack with `margin-right: auto` and any number of controls after it stay together.
- **The filter column and the library's views collapse on mobile, and the class is inert on
  desktop.** The vanilla `#filter-column` and the library's `#library-views` both carry
  `collapsed`; only the `max-width: 768px` block acts on it. Don't "tidy" that by removing the
  class on desktop — it's what keeps one code path.
- ~~The loading indicator animates `content`~~ **Replaced in v0.5.** It swapped ░▒▓█ on
  `steps(1)`, justified as using "the same glyphs the filter headings use". Those headings
  are plain words now, so that justification expired with them — and animating `content`
  replaces a text node twelve times a second, each swap a layout and a paint. It is a
  gradient sweep over a 2px bar instead. Still deliberately not a rotating arc: a horizontal
  sweep suits an interface built out of rows and tables.
- ~~Decorated headings wrap if you let them~~ **Moot in v0.5 — the ░▒▓ chrome is gone.**
  Worth knowing why it was ever a rule: `░ ▒ ▓ filters ▓ ▒ ░` measured 138px in a 190px
  header that also holds a "clear" button, so a lone `░` wrapped to a second line and the
  column read as broken. The general lesson survives the decoration: **anything in a
  fixed-width column needs measuring at that width**, not eyeballing.
- **Removing a UI element leaves references behind, and a module-scope `ReferenceError`
  aborts the REST of the handler.** The download-profile dropdown went in v0.5 but two
  `profileControl.classList.remove('open')` calls stayed, referencing a binding that no
  longer existed anywhere. The damaging one was in `closeOtherDropdowns()` — the bridge
  function the Preact downloads panel calls as it opens — where it threw on the *first* line,
  so the `setLogOpen(false)` beneath it never ran and **opening downloads left the log open**,
  defeating the one invariant that function exists to hold. The other, in the log toggle, threw
  *after* `setLogOpen()` and so did nothing visible at all, which is why both survived several
  releases. Found in the console while verifying something unrelated. **After deleting an
  element, grep for its variable — and note that a dead reference positioned late in a handler
  is invisible, while the same reference one line earlier is a broken feature.**

- **`hidden` did nothing to any badge.** `.log-unread-badge` and `.signals-badge` both set
  `display`, which beats the browser's `[hidden] { display: none }` — so all three badges sat
  on screen showing `0` while their JS believed it had hidden them. Found by checking
  `getBoundingClientRect()` after `el.hidden` read back `true`; it is invisible to any check
  that trusts the property. `main.css` now forces `[hidden]` to win. **`hidden` reading
  `true` is not evidence an element is hidden — measure it.**
- **The downloads panel vanishes if `ui/` hasn't been built.** `interface/index.html` loads
  `dist/deadwax-ui.js`, which is gitignored and generated. Running from source without
  `npm run build` leaves it 404ing and that panel simply absent. Check this first. **And
  `/player/` is a blank black page**, with no error on screen: it loads `dist/deadwax-player.js`,
  the second entry. A build that emits only the first (an old local rolldown config) does it too.
- **Don't derive an overlay's subject from a list that a write reloads.** The metadata editor
  originally resolved its album by looking `review.paths[index]` up in `albums` on every
  render. Applying a release renames the folder, so the reloaded library and the queue's record
  of where the album now lives land in *two separate state commits* — and for the render
  between them **neither the old path nor the new one resolves**, so the editor unmounted
  mid-queue every time a rename was applied. It now holds the album itself and is updated once,
  explicitly, from the array `reload()` resolves with (never from `albums`, which the caller's
  own `await` has not necessarily committed yet). One value updated once cannot disagree with
  itself.
- **The editor is keyed on a step counter, and that is load-bearing in both directions.** It
  must NOT reset when its album prop changes — that happens after an apply, where the release
  list on screen is still right and re-searching MusicBrainz would be waste. It MUST reset when
  the queue moves to a different album, since nothing about the previous one applies. A `key`
  that changes only on navigation is what buys both; keying on `album.path` or `album.key`
  would break the first, because an apply changes them.
- ~~New chips in the album rows do not shrink~~ **The rows are gone (v0.6.5), the lesson isn't.**
  Adding issue chips to the old nowrap album rows pushed the edit and delete buttons off a 375px
  screen and took "Selected Ambient Works 85-92" from 84px to **9px**, because chips carry
  `flex-shrink: 0` and titles don't. The tree rows drop their chips by `@container` query as
  the tree narrows, for exactly that reason. **Anything added to a tree row needs measuring at
  the tree's narrowest width (260px)**, not eyeballing.
- **An id containing NUL can never be found by `querySelector`.** Album group keys are built
  with a `\u0000` separator (the source writes that escape, so the file stays plain text; the
  string itself still holds one real NUL), and
  `CSS.escape()` turns NUL into U+FFFD, as the spec requires. So `[data-node="${CSS.escape(id)}"]`
  silently matched nothing for every album and track: arrow keys moved the selection while
  focus stayed on the row you left, and only artist rows (no NUL) worked. The tree now compares
  `dataset.node` directly. The same misreading built a group id by hand with a space, which
  resolved to nothing - **never rebuild a node id by hand; go through `lib/libraryTree.ts`.**
- **A grid resolves `em` track sizes against ITS OWN font-size, so two grids meant to line up
  have to share one (v0.6.13).** The track viewer draws its header and every row as separate
  grids from one `--track-columns` template, and the header was a type step smaller with
  `--text-2xs` set on the CONTAINER. Every em column then came out about 9% narrower up there -
  `2.6em` was 28.6px in the header against 31.2px in a row - so the two grids' boundaries drifted
  further apart the further right you looked, and a value sat up to 10px right of its own label.
  James reported it as "a weird space before the text in the columns", which is exactly what it
  looks like. The smaller label type belongs on the header's CELLS; both grid containers stay on
  the table's own size. A px track is immune, which is why a column already dragged to a width
  was the one thing that lined up, and why this hid for so long.
  **It also quietly bent the resize**, which measures HEADER cells to pin the flexible columns to
  the left of the grip: while the two disagreed, it pinned a body column to a width 9% short of
  the one it was actually drawn at. Nothing about the drag changed to fix that - the grids
  agreeing is what fixed it.
  The rows also carry a 1px transparent border for their hover and selection outline, so the
  header carries a matching transparent one on each side; without it everything sits one pixel
  out. **Verified:** both grids resolve identical tracks, and every column's value now starts at
  exactly the same x as its header label, before and after a resize drag.
- **Current Chrome ignores every `::-webkit-scrollbar` rule on an element that sets
  `scrollbar-width` or `scrollbar-color`.** `.scrollable` set both, so the Windows 7 scrollbars
  applied in Safari only. The Windows 7 block resets both to `auto` first; if the scrollbars
  ever look flat again in Chrome, look for one of those two properties having crept back.

### Backend and data

- **slskd answers a search with `409 Conflict` when it is not logged in to SOULSEEK**, which is
  nothing like what the status name suggests, and it was the first thing real infrastructure
  broke. `SearchesController.Post` maps `InvalidOperationException` to `Conflict`, and the only
  thing throwing one on that path is Soulseek.NET's own precondition - "The server connection
  must be connected and logged in to perform a search". Traced through slskd's and
  Soulseek.NET's source rather than guessed at, because the guess anyone would make from the
  word "Conflict" is a duplicate search id, and it is not that.
  **The reason was in the response BODY the whole time.** `requests` renders an `HTTPError` as
  its status line alone, so `409 Client Error: Conflict for url: ...` is what reached the user
  while slskd was spelling it out one layer down. `slskd_said()` reads that body - a bare JSON
  string (slskd declares `[Produces("application/json")]` and returns plain strings), a
  ProblemDetails object, or text - and `describe_search_refusal()` explains the status around
  it. **Any other slskd call that shows an error to the user should read the body the same way.**
  429 is the other status worth knowing: slskd runs ONE search at a time, behind a static
  `SemaphoreSlim(1, 1)` taken with `Wait(0)`, so two tabs or a retry on top of a slow search get
  "Only one concurrent operation is permitted".
- **Pinging slskd's API says nothing about its connection to Soulseek, and the pill claimed
  otherwise.** `application.state()` answers 200 whenever the container is up and the key is
  right; slskd sits there logged out and serves it perfectly. So the connection pill read
  `connected` right up until the first search failed - and then the *search* took the blame for
  something that was already wrong before it ran, which is the exact failure those pills exist
  to prevent. Same shape as the `peer avg` relabel: a status that visibly doesn't match reality
  teaches you to distrust the ones that do. `ping()` now reads `server.isConnected` and
  `server.isLoggedIn` out of that same payload and reports `NOT_CONNECTED`, `NOT_LOGGED_IN` or
  `CONNECTING`.
  **An slskd too old to report `server` at all is treated as connected** - absence of the field
  is not evidence of a disconnection, and a red pill on a working install is the worse of the
  two mistakes. `connectionWatchdog.isAwaitingVpn` is named when set, because slskd here runs
  inside a VPN container and "it is waiting for its VPN" is the entire answer; it is newer than
  some slskd versions, so it is read defensively and omitted when absent.
  The state string (`"Connected, LoggedIn"`, `"Disconnected"`) is a .NET flags enum and is only
  ever QUOTED BACK, never parsed - the booleans beside it are the contract.
- **`@app.middleware("http")` made `request.is_disconnected()` a permanent False, app-wide.**
  That decorator is Starlette's `BaseHTTPMiddleware`, whose wrapped `receive` has to be awaited
  to learn anything, and `is_disconnected()` only peeks - inside an already-cancelled scope, so
  the peek is always cancelled before the disconnect can arrive. Found when the v0.9.8 abandoned-
  search fix did nothing live while its tests passed (they call the route directly, with no
  middleware). The cache-header middleware is plain ASGI now (`RevalidateInterfaceAssets` in
  app.py), and `test_no_middleware_hides_a_disconnect_from_the_routes` refuses any
  BaseHTTPMiddleware coming back. **Don't add another `@app.middleware("http")`** - write it as
  ASGI, touching `send` only.
- **A 409 costs one extra request, on the failure path only.** `_explain_refusal()` asks slskd
  how its connection is doing, because "not connected, and it is waiting for its VPN" is an
  answer and "not connected" is a shrug. If that request fails too it is dropped silently and
  slskd's original words are used - a diagnosis must never replace the error it explains.
  The sentence it builds is shown in TWO places, on its own in the event log and after
  "search failed: " in the candidates panel, so every branch of it names slskd as its subject.
- **slskd's `averageSpeed` is cumulative** (total bytes ÷ total elapsed), so it only ever
  creeps upward and never shows the current rate. Real speed is derived from `bytesTransferred`
  deltas between polls. Don't "simplify" back to `averageSpeed`.
- **`uploadSpeed` is BYTES per second, not bits.** Two comments claimed bits, which would invite
  someone to "fix" the display by a factor of eight. slskd's own web UI renders the same field
  as `formatBytes(response.uploadSpeed)/s`, and `score_peer()`'s thresholds only make sense read
  as bytes — 1 MB/s for a fast peer, 100 KB/s for a decent one; as bits those would be 125 and
  **12.5** KB/s. The display was always right; only the comments were wrong.
- **Hold a stale rate for a duration, never for a number of polls.** `speed.ts` kept the last
  measured rate across quiet polls (a zero delta usually means "slskd hasn't refreshed its
  counter", not "the transfer stopped") — but it counted four *polls*, and the poll cadence is
  not fixed: 500ms with the panel open, 5s in the background, and browsers throttle background
  tabs further. So the same constant meant ~2s when watched and 20s+ when not. Measured against
  a steady 1 MB/s transfer with slskd's counter refreshing every 5s, **the speed read blank on
  54% of polls**, in gaps of up to 5 seconds — a transfer moving at a perfectly constant rate,
  flickering between a number and nothing. It ages out on wall time now (`STALE_RATE_MS`), which
  put that back to 92% and bounded the lie at ~6s whatever the cadence.
- **The speed is measured over a one-second window, which is also how often it changes.** One
  constant (`SPEED_UPDATE_MS`), not a measurement plus a display throttle — a short window
  quantises badly against slskd's own counter, so publishing twice a second gave a figure that
  was both hard to read and noisier than the transfer really was. Measured on a transfer
  deliberately wobbling ±30%: 120 distinct figures a minute became 60, and the scatter fell
  (std dev 0.212 → 0.187 MB/s) while still tracking the real swing. **The poll cadence is
  independent of this** — the extra polls drive progress and status, and their bytes accumulate
  into the next window rather than being discarded, so changing `POLL_OPEN_MS` does not change
  how often the speed updates.
- **`ui/test/speed.sim.cjs` is the only frontend test in the repo, and it is a script.** There is
  no JS test runner here (adding one needs a newer Node than this repo builds on), and the
  sampler is the piece of frontend logic whose failure is *silent* — a wrong rate looks entirely
  plausible, and "no speed at all, intermittently" is invisible to any assertion about a single
  poll. It compiles `speed.ts` itself, simulates polling against a known true rate, and exits
  non-zero. Run it with `node ui/test/speed.sim.cjs`; it fails on the pre-fix code.
- **An unrecognised slskd transfer substate is a permanently stuck job.** This was predicted in
  "What the tests cannot tell you" below and then happened: `summarize_transfers` knew about
  `"Completed, Succeeded"`, `"Errored"` and `"Cancelled"`, so **`"Completed, Rejected"` counted
  as neither done nor failed**. A refused download sat at `queued` forever — the interface
  renders that as "hasn't started yet" — and because slskd *was* reporting the transfers, the
  unmatched-transfer grace period never applied either. Nothing could clear it but hand-editing
  the DB. Every terminal substate now lives in `TRANSFER_FAILURE_REASONS` in `store.py` with the
  sentence shown to the user. **If slskd grows another substate, add it there.**
- **Never take a word apart to build a search query.** `build_search_query` used to strip all
  punctuation to spaces, so Metallica's **`S&M2` was searched for as `S M2`** — and found
  nothing. If Soulseek tokenizes on non-alphanumerics (which is what the failure looks like),
  the folder `Metallica - S&M2 (2020)` holds `metallica/s/m/2` and there is **no `m2` token in
  it**, so we asked for a term that exists on neither side. The album name silently vanished
  from its own search.
  The rule now: **punctuation between two alphanumerics is part of the word and stays**
  (`S&M2`, `R&B`, `AC/DC`, `Jay-Z`, `That's`); punctuation standing on its own is dropped
  (`Simon & Garfunkel`, `(Deluxe)`, `Guns N'`). Whatever Soulseek does to `S&M2` in the query it
  does to `S&M2` in the folder name, and that is a far better bet than guessing on its behalf —
  splitting it ourselves is the one option that is wrong under *both* readings of how it
  matches.
  **A first attempt got this wrong in an instructive way**: it kept the splitting and dropped
  the one-character debris instead, which fixed nothing here (`S M2` → `M2`, still no match) and
  quietly turned `Vol. 2` into `Vol`. Length is not the signal — position is.
- **A failed releases fetch used to be indistinguishable from an album with no releases.**
  `get_releases()` read `data.get("releases", [])` straight off whatever `request_with_retries`
  returned — and that answers with an *error dict* rather than raising, so a MusicBrainz blip
  came back as `{"release-count": 0, "releases": []}`. The interface believed it. The top search
  result rendered with nothing to expand, and since the filter facets are built from whatever
  release grids are mounted, **an entire search came up with no filters at all**. It now returns
  a `problem` alongside, and says so in the event log.
- **`renderFacets()` has to be called by hand, and one call site didn't.** Fetching a release
  group's releases mounted a grid without telling the facets, so expanding a group left the
  filter column still reading "expand a release group to see filters" — and with the bug above,
  that was the *only* way to mount a grid, so the filters never appeared at all. This is exactly
  the hand-rolled render bookkeeping counted below (29 call sites that must remember). It goes
  away with the port, not before; until then, **anything that mounts or unmounts a release grid
  must call `renderFacets()` and `updateResultsSummary()`**.
- **A non-total branch in `createReleaseGroupElement` produced a dead card.** It tested
  `if (releases && releases.length)` then `else if (releases === null)`, so an empty array
  matched neither and the group rendered with no grid *and* no fetch button — unexpandable, with
  no way back. `processSearchResults` now passes `null` for an empty list and the second arm is
  a plain `else`. Watch for this shape: `[]` is neither truthy-with-length nor `null`.
- **A 400 from MusicBrainz is a rejected QUERY, and retrying it is pointless.** It used to fall
  through to the generic branch and go round the retry loop ten times, with rate-limit pacing
  between each, before reporting "MusicBrainz is unreachable" — about thirty seconds spent
  arriving at the same deterministic answer, and then blaming the network for a bad search. It
  breaks out immediately now and says the query was rejected. This matters more since the
  search view began composing type-filter clauses: a syntax mistake there has to be legible as
  a syntax mistake.
- **`request_with_retries` returns an error dict rather than raising.** Reaching straight for
  `["release-groups"]` produced a `KeyError` that surfaced as *"Error searching MusicBrainz:
  'release-groups'"* — which reads like a bad query, so an outage looked like user error.
  `MusicBrainzUnavailable` now distinguishes them. **This is also why the response cache stores
  only the success path** — caching that error dict would pin a transient outage in place for
  the whole TTL, turning a bad minute into a bad hour with no remedy but a restart.
- **MusicBrainz's own result order cannot pick the album for you.** Searching
  `releasegroup:"Metallica" AND artist:"Metallica"` returns 25 groups of which the **first five
  all score exactly 100** — two live albums, an interview disc, a compilation, and only then the
  1991 album. The editor took `slice(0, 3)`, so it spent three requests on the wrong groups and
  **never fetched the right one**; no amount of ranking the releases underneath could have
  helped, because they were never retrieved. `scoreReleaseGroupMatch` now ranks groups first, on
  group-level signals only (year is worth 100, exact title 40, studio-album-ness 30, an unlikely
  secondary type −30, MB's score ÷10 as a weak tiebreak). Weighted, not filtered — tag the 1996
  live album as 1996 and it still wins, which was verified along with the two Black Album cases.
- **The "rate limit hit" warning was ours, not MusicBrainz's.** `RateLimit.wait()` logged a
  *frontend* warning every time it paced a request, which during any normal burst is constantly —
  so the app spent its time telling the user that its own politeness was a fault. It is at debug
  now. A real 429 from the server is still reported.
- **docker-compose: `environment:` beats `env_file`, and that is now a supported way to
  configure deadwax — but only with LITERAL values.** Both sources work and may be mixed
  (`load_dotenv()` does not override existing variables, so the environment wins; there is a
  subprocess test pinning that, because flipping it to `override=True` would invert the
  precedence with nothing to show for it).
  The trap is `SLSKD_URL=${SLSKD_URL}`: compose re-interpolates that from its *own* env, and an
  empty result **still counts as set**, so it beats `.env` and leaves the setting blank beside a
  `.env` line that looks perfectly correct. That produced an unusable empty `SLSKD_URL` once
  already. `shadowed_by_empty_env()` now detects exactly this and names it in the log, and
  `setting_source()` reports which source supplied each setting on startup — "check your .env"
  is useless advice to someone who configured everything in compose.
- **`.env` values must not have trailing `# comments`.** Compose and python-dotenv disagree
  about inline comments. Examples go on their own lines.
- **Two editions of one album used to silently not arrive.** `{album} ({year})` gave the
  standard and deluxe press identical paths; `execute_plan` correctly refused to overwrite,
  so every track was *skipped* — and the poller only reported a problem when
  `organized == 0 AND skipped == 0`, so an all-skipped job fell through to status
  `organized`. Green tick, album missing. Fixed in both places, and both are covered by
  tests. **This was the exact Lidarr complaint that motivated the fork**, reproduced here.
- **Cover art is fetched on apply, never on preview.** Previewing runs on every click in the
  release list, so downloading an image to describe it would be slow and rude to the Archive.
  `plan_art()` decides what *would* happen with no network call; the route fetches the bytes
  and hands them to `execute_retag`, which keeps `retag.py` free of network dependencies and
  testable without one.
- **Cover art is served with a five-minute cache, so its URL has to carry a version.** Without
  one, replacing a cover showed the old image for five minutes — precisely when you are looking
  at it, since you had just changed it. The version is the **art file's own mtime**, and the
  distinction matters: replacing `cover.jpg` in place does not touch the *directory's* mtime, so
  `album.modified_at` sits perfectly still through the one operation that must be noticed
  (measured: dir mtime unchanged, file mtime moved). `albumArtUrl()` is the only place that
  builds this URL — keep it that way.
  Note the corollary: the scan cache also keys on directory mtime, so an in-place cover
  replacement is invisible to it too. `forget_cached_album()` on the retag path is what makes
  the new art appear; a cover changed by anything else needs a rescan.
- **Retagging a file does NOT change its directory's mtime** — only adding, removing or
  renaming entries does. Measured, not assumed. The library cache keys on directory mtime,
  so an in-place retag is invisible to the scanner and the edit looks like it silently
  failed. `forget_cached_album()` exists for exactly this, and the retag endpoint calls it
  for both the old and new locations.
- **Embedded pictures have a TYPE, and files usually hold several.** Type 3 is
  `COVER_FRONT`, type 6 is `MEDIA` — a scan of the disc itself. EAC and dBpoweramp rips
  routinely embed both, in no guaranteed order, so `pictures[0]` showed albums illustrated
  with a picture of a CD. Selection goes through `PICTURE_TYPE_PREFERENCE`, never by order.
  The same trap applies to ID3 `APIC` frames (there can be several, keyed by description)
  and to loose files — a lone `disc.jpg` is not the cover.
- **`/library/art` was the first endpoint to turn user input into a filesystem read**, and
  `/library/tracks` and `/deletion_summary` copy its guard. It
  takes a path relative to LIBRARY_PATH, so `is_within()` containment is load-bearing, not
  decoration — without it `?album=../../..` reads anything the container user can. It
  answers 404 identically for "outside the library" and "no such album" so a probe learns
  nothing. Covered by tests including a symlink pointing out of the library. **If you add
  another endpoint taking a path, copy this pattern.**

### Capturing screenshots

The README's images are captured from the running app; `interface/_shot.html` and a CDP driver
do it. Both are temporary and neither is committed — **the harness must not ship**, it is
same-origin with the app by design.

**v0.6.21 did it more simply, and that is the way to do it again when there is network.**
Playwright's Python package (the driver only - no browser download) in a scratch venv, launched
against the Brave already installed (`executable_path`), `device_scale_factor=2` at 1440x900 and
390x844. The server ran from a `.claude/launch.json` entry with an `env` block pointing
`DB_PATH`, `LIBRARY_PATH` and `SLSKD_URL` into the scratchpad - `load_dotenv()` never overrides
what is already set, so the dev `.env` can't leak in. The LIBRARY was generated: MusicBrainz
releases fetched by id, filed and tagged through `organizer.build_target_path()` and
`write_tags()` so it is exactly what deadwax files, ffmpeg writing quiet pink noise of each
track's length as FLAC (~200 kbps, so 1 GB for ten albums), covers from the Archive. Two
things to know: `build_target_path()` called directly gave every non-XE/XW pressing a country
suffix (`[GB]`, `[AU]`) - that WAS what deadwax named them until v0.8.3 made the country opt-in
(`COUNTRY_IN_FOLDER`), and the capture renamed them by hand for tidier pictures; and a wait on
`.track-table-row` is what says the library pane has drawn.

**v0.9.33 recaptured all six and added six (twelve in `assets/images/`, also embedded in `docs/`),
the same way, on the same generated library.** What it took beyond the above:

- **The candidates and downloads shots need a fuller fake slskd** than the one-endpoint stub: one
  that answers EVERY search with the same handful of realistically named Dummy folders (exact
  rips, a 24/96 remaster, a 320, one missing a track, one of bare `Track NN` names), sized from the
  real track lengths so the scores and chips are the matcher's own; and that reports an enqueued
  download's transfers as moving, with a head start so the bar is part-way.
- **The panel's other rows are SEEDED**: a fresh database with an organized, a failed (with
  runners-up, so "next peer" shows) and a queued job inserted straight into `jobs`, the queued
  one's transfers handed to the fake as waiting at queue #4; plus one `import` review row (the
  NEW chip and the tab badge) and one `peer_speed` row (the green "you got"). The live one is a
  real Download click. Reseed before the final run - a second run adds a second Dummy job.
- **The editor shot is STAGED and undone**: a copy of an album moved to the library root as a
  stranger's rip, its MusicBrainz tags, original date and cover stripped, then the real folder
  put back. Opened on an album deadwax filed itself, the editor has nothing honest to show - and
  on a vinyl pressing it proposes a `[12_ Vinyl]` folder, which is real behaviour and reads as
  a bug in a picture. Pick the release whose preview renames to the plain folder.
- **The artist page's picture is a saved `artist.jpg`**, so the capture saves the Commons photo
  through Artist images first; the page shows a placeholder until something has.
- Driving it: a tab button's text includes its badge, so match it with `has_text`, not an exact
  text; on a phone, tapping an album of several editions opens the sheet over the tree, so the
  phone library shot opens a single-edition album; and `glob` reads `[FLAC]` in a folder name as
  a character class (`glob.escape`).

**v1.1.6 recaptured `library.png` for disc titles**, with the same harness and library. The generated
Experience edition carried no disc titles, so MusicBrainz's for its release (`588ca0a5`, "2011
Remaster" and "Unreleased Tracks") were written straight into its FLACs as `discsubtitle`, as an
apply would. A library generated afresh needs the same, or the shot shows bare "Disc 1", "Disc 2".

- **`--screenshot` and `--virtual-time-budget` cannot do this, and two attempts hung proving
  it.** The flag fires once load settles, which is before any driving has happened. Virtual
  time is the usual answer and it does not work here either: deadwax polls continuously, so
  the network never goes idle and virtual time never drains. What works is driving over CDP
  and waiting on a REAL condition — the harness sets `document.title` to `READY` when it has
  finished, and the driver polls for that.
- **The harness must assert its own success.** It first set READY unconditionally, so a search
  that had not returned was captured as a spinner reading "Asking MusicBrainz…" and reported
  as a pass. It now collects reasons and sets `FAILED: …`, which the driver raises. A picture
  of a loading state is worse than no picture, and far worse when nothing complains.
- **Check for spinners by VISIBILITY, not by selector.** The tab panes are `display: none`
  rather than unmounted, so a search left mid-request is still in the DOM while you look at
  settings — which failed the settings capture, a view that touches MusicBrainz not at all.
  `offsetParent !== null` is the test.
- **MusicBrainz can take 30–60s a request on a bad day**, and this session had one: a ping
  took 57s. Timeouts of 15–30s gave up on requests that were perfectly in flight. 90s per wait
  and a pause between views.
- **slskd is stubbed for the capture** (`scratchpad/slskd_stub.py`, one endpoint). Without it
  the pill reads UNKNOWN_ERROR, which is true of the laptop and a lie about the product —
  a reader would conclude the app errors. Nothing else is faked: the MusicBrainz data and the
  library scan are real, and no screenshot claims a download happened.
- **No third-party packages were available** — there is no network here to install from, so
  the driver hand-rolls the WebSocket client CDP needs. Only what is required: masked text
  frames out, unmasked in, with 64-bit lengths because a screenshot's base64 is megabytes.

### Tooling and environment

- **A test on localhost can't see a SecureContext-only API fail (2.0.0-player.16).** Browsers treat
  `http://localhost` and `127.0.0.1` as secure, so AudioWorklet (and `crypto.subtle`, service workers,
  `navigator.clipboard`) is there in every local check - and missing on the plain `http://` address
  James actually opens deadwax at on his network. That is how .14's turntable shipped silent for him
  while every check passed. Test any feature that might lean on one from a non-local hostname too:
  headless Brave or Chrome with `--host-resolver-rules="MAP deadwax.test 127.0.0.1"`, loading
  `http://deadwax.test:<port>` (the orchestrator reproduced the turntable's bug that way). And know
  which APIs are SecureContext before relying on one: MDN marks them "Secure context".
- **The browser preview pane is not a reliable witness.** Two distinct failure modes, both
  of which read as product bugs:
  - **It doesn't paint when it isn't fronted.** `loading="lazy"` images never start loading,
    so `img.complete` is false and `currentSrc` empty even though the bytes serve fine —
    cover art looked broken twice this session and wasn't. `useEffect` also flushes late, so
    a mount effect can land *after* a synthetic input and clobber it. **Take a screenshot to
    force a paint before measuring either.** (That second one is why the metadata editor's
    re-seed effect skips its mount run — which made it genuinely robust, not just testable.)
  - **A hidden pane freezes every CSS transition mid-flight, and it reads exactly like a
    layout bug.** This cost real time while verifying the panel drag: a restored panel sat
    permanently at `scale(0.98)`, 12px off its saved position, with `getAnimations()`
    reporting `playState: "running"` forever on a 0.14s transition. It looked like `freeze()`
    fighting the `@starting-style` entrance. It was not — `document.hidden` was `true` and
    **rAF fired 0 frames in 3 seconds**, so the transition simply never advanced. One
    screenshot to force a paint and it settled to `transform: none` at exactly the saved
    610×520 / (434, 394). **The tell is a transition stuck at its FROM value with playState
    "running"** — check `document.hidden` and count rAF frames before believing any
    transform, position or size you measured mid-transition. Note the tab being *fronted* via
    `tabs_select` was not sufficient here; the screenshot was.
  - **It serves stale composites.** It has shown a panel as transparent, and shown pre-fix
    state after a reload, more than once.

  So: **verify against computed styles and DOM state rather than screenshots** — except when
  the thing you are checking needs a paint, where you need the screenshot first and the
  measurement second.
- **A transient upstream failure must never latch into a permanent dead end.** The `get art`
  button first disabled itself after a failed fetch, on the reasoning that the Archive simply
  has no cover for that release. That is usually true and sometimes badly wrong: the Archive
  goes away for minutes at a time exactly like MusicBrainz, and the two are indistinguishable
  from a single 404. It now says `retry art` and stays clickable. Same shape as the rejected
  download and the empty release list — **when an upstream answer could mean "never" or "not
  right now", leave the user a way to ask again.**
- **fanart.tv's API is on `webservice.fanart.tv`, not `api.fanart.tv`** - and their own API
  repository documents the latter. `api.fanart.tv` is the website: it sits behind Cloudflare and
  answers a bot check with 403 and an HTML challenge page whatever key you send, which reads
  exactly like a rejected key. The webservice host answers properly, and a bad key there gets
  `401 {"error":"invalid API key"}` - which is how this was told apart.
- **Wikimedia serves THUMBNAILS to robots and refuses ORIGINALS**, and the refusal is a 403
  whose body reads "Please honor our robot policy". So every Commons image here is fetched
  through `Special:FilePath?width=N`, never bare. The trap underneath that is worse: MediaWiki
  does not upscale, so asking for a width at or above the file's own resolves to the ORIGINAL
  and is refused - a 367px-wide photograph served at `width=300` and 403'd at `width=366`. That
  is why `safe_thumb_width()` asks Commons how wide the file actually is (one small API call per
  picture) and then stays under it. **Symptom to recognise:** the picker shows the image
  perfectly and saving it fails, because the preview asked for 600 of a large file and the save
  asked for the original. An SVG has no such limit - it is rasterised to a PNG at whatever width
  is asked - so logos are exempt and keep their full size.
- **MusicBrainz and the Cover Art Archive go unreachable for minutes at a time**, repeatedly,
  from dev machines. A failing search is far more often that than a bug — retry before
  concluding anything; the 503 path is deliberate and says which it is. It also produced a
  memorable false lead once: two consecutive runs gave opposite results and looked like
  case-sensitivity. It is *not* case-sensitive — all four casings of "The Slow
  Rush"/"Tame Impala" were verified to return identical results.
- **npm silently skips native binaries when Node is too old.** Vite 8 needs Node
  `^20.19.0 || >=22.12.0`; on 20.12.2 `npm install` merely *warns*, drops the unsupported
  optional `@rolldown/binding-*` package, and the failure only appears at build time as
  "Cannot find module './rolldown-binding.darwin-arm64.node'". The lockfile still records
  every platform, so Docker's node:22 stage is unaffected — this is a local-only trap.
- **On 20.12.2 the build now fails before it starts, and the error names none of this.** It
  dies as `TypeError [ERR_INVALID_ARG_VALUE]: The argument 'format' must be one of: ...
  Received [ 'underline', 'gray' ]` from `node:util`. `styleText()` only learned to take an
  ARRAY of formats in a later Node, rolldown calls it at module scope, so vite cannot even be
  imported — it is not a code error and no flag (`NO_COLOR`, `--logLevel`) avoids it, because
  it happens at import. **`npm run typecheck` still works and still checks everything**;
  `npm run build` needs the Node upgrade. The one thing to not do is go looking for the bug in
  `ui/`.
- **Past that, on this machine, `vite build` HANGS - and bare rolldown doesn't.** A preload shim
  that teaches `util.styleText` to take an array (and calls `syncBuiltinESMExports()`) gets vite
  imported, but the build then sat at 0% CPU for seven minutes with every `rolldown-worker`
  thread parked. Running rolldown's own CLI on the same input finished in **68ms**:
  `node --import <shim>.mjs node_modules/rolldown/bin/cli.mjs -c <config>.mjs`, with a config of
  `input: src/main.tsx`, `tsconfig: tsconfig.json` (it reads jsx/jsxImportSource from there),
  `platform: 'browser'` and `output.file: ../interface/dist/deadwax-ui.js`. **Since the phone
  player (spiked at 0.8.0, ported in 1.0.3) there are TWO entries**, so the config is `input: { 'deadwax-ui':
  'src/main.tsx', 'deadwax-player': 'src/player/main.tsx' }` with `output: { dir:
  '../interface/dist', entryFileNames: '[name].js', chunkFileNames: 'assets/[name]-[hash].js' }`
  - a single `output.file` cannot hold two entries and a shared chunk. Rolldown doesn't empty
  the folder as vite's `emptyOutDir` does, so old hashed chunks pile up in `interface/dist/assets/`;
  harmless, and `rm -rf interface/dist` first keeps it tidy. The Preact preset
  only adds dev-time plugins, so a production bundle loses nothing. It is a LOCAL workaround -
  Docker builds on node:22 through vite as normal, and the real fix is still the Node upgrade.
- **This checkout lives in iCloud-optimised storage, and much of it is evicted.** `ls -lO`
  shows `compressed,dataless` on files across `node_modules/` and `.venv/`, so the first read
  of each one is a download: the pytest suite took **125s** cold and **1.4s** warm, and a
  faulthandler dump caught it 25s into importing mutagen. A tool that seems hung here is far
  more often fetching than stuck - check `ps` for CPU before killing it. (The vite hang above was
  NOT this: 0% CPU and parked threads, where a fetch shows I/O.)
- **Which `launch.json` the browser preview tool reads depends on the session's working
  directory.** Sessions started in `~/Desktop/Code` read THAT folder's `.claude/launch.json`;
  the v0.6.9 session, started in this repo, read this repo's own `.claude/launch.json` - and when asked
  for a name that wasn't in it, it started the plain `deadwax` config instead of failing:
  against the REAL `.devdata` database, with no library. **Check the name `preview_start`
  reports back before doing anything that writes.** The pattern is otherwise unchanged: a
  throwaway library of real FLACs with real tags and a throwaway database, both in the
  scratchpad, so `.devdata` is never touched. The server's port is fixed at 8080 in
  `src/main.py`, so only one runs at a time.
- **The `ui/test/*.sim.cjs` scripts fail inside the agent sandbox unless `TMPDIR` points
  somewhere writable.** They compile TypeScript into `os.tmpdir()`, which the sandbox refuses,
  and every sim - including ones nothing touched - dies identically, with only Node's version
  footer on its last line. `TMPDIR=<scratchpad> node ui/test/tags.sim.cjs` and they all pass.
  **Don't give pytest that TMPDIR, though** (nor run it with TMPDIR unset, which falls back to
  `/tmp`): `test_player_cache.py::test_a_setgid_bit_is_no_bar` then fails every time. The scratchpad
  and `/tmp` belong to group wheel, a new folder takes its parent's group on macOS, and chmod by a
  user outside that group silently drops the setgid bit, so the test's own `chmod(0o2700)` never
  holds. Under the shell's own TMPDIR (`/var/folders/...`, group staff) it passes. Found in the
  2.0.0-player.14 review, after it had read as "fails 3 runs in 22, cause unknown".
- **Installing Xcode breaks `git` until its licence is accepted.** `/usr/bin/git` is a shim that
  defers to the selected developer directory, and once `xcode-select -p` points into
  `/Applications/Xcode.app` it refuses with "You have not agreed to the Xcode license
  agreements" (exit 69) - which fails `test_source_bytes.py`'s `git ls-files` for reasons that
  look nothing like its subject. `sudo xcodebuild -license` fixes it and needs James's password;
  until then `PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH` gets a working git.
  (Since then the iOS Simulator was tried and removed - the 8 GB Mac can't run it - and
  `xcode-select -p` points at `/Library/Developer/CommandLineTools` again, so git works as is.)
- **The agent's file tools write a `\u0000`-style escape to disk as the RAW character**, and a
  NUL in a file's first 8000 bytes makes git store the whole file as binary - GitHub then shows
  no diff for it at all. `\n` and `\\` survive as typed; only the four-hex-digit `\u` form becomes
  the character it names. It bit twice in v0.6.9 - the control-character regex in `tagEdit.ts`,
  then the sim check written to pin that fix - and was caught only because `git diff --stat`
  said `Bin`. It is exactly how `libraryTree.ts`, `tree.sim.cjs`,
  `LibraryTree.tsx` and `groupAlbums.ts` came to be binary - all five separators were respelled
  as escapes in 0.6.10. Nothing else notices, because a raw control character is legal in a JS
  string or regex and the code runs the same. Write such escapes with a byte-level replace.
  `tests/test_source_bytes.py` now fails on any raw control byte in a tracked source file, so
  catching this no longer depends on noticing `Bin` in `git diff --stat`.

## Known performance problems (profiled, not guessed)

Measured with 148 releases × 12 tracks:

| finding | measurement |
| --- | --- |
| Expanding one release group | **711 ms** freeze |
| DOM nodes, two groups expanded | 22,905 |
| Track `<div>`s built while `display:none` | 2,832 |
| `scrollHeight` read after a DOM change | 23 ms → **962 ms** worst case |
| Filter keystroke | 9–62 ms (fine) |

**Opening the metadata editor, measured against the live API and now FIXED.** It cost ten
MusicBrainz requests for one album; it costs four. Three things were wrong, and the middle one
was the expensive one:

| | before | after |
| --- | --- | --- |
| requests to open the editor on Metallica's *Metallica* | 10 | **4** |
| requests for one release group's releases | 5 | **1** |
| payload for that group | 1446 KB | **101 KB** |

1. `fully_search` eagerly walked the best group's whole release list as `best-match-releases`.
   The editor never reads that field — it ranks the groups itself — so those requests bought a
   payload that was dropped on the floor. `?releases=false` turns it off; the search view, which
   does render them, still gets them by default.
2. `inc=…+recordings` carried every track of every pressing purely so a list could show a count
   that `media[].track-count` already gives. That is what made MusicBrainz return 36, then 4,
   then 5, then 11 releases for a `limit=100` — it was capping on size, not count. Without it
   the same 58 releases arrive in **one** request. `?tracks=false` opts in, and the tracklist of
   the release you actually pick is fetched on its own.
3. Both defaults are unchanged, because the download flow matches Soulseek folders against a
   release's real tracklist. Losing that would gut the matching quietly rather than break it
   loudly — so the saving is opt-in and the caller that needs correctness gets it by doing
   nothing.

**The trap this creates, which is worth stating plainly:** a release fetched for the *list* has
no tracklist, and building a retag payload from one applies no titles and no track numbers —
writing nothing, and reading exactly like the edit silently failed. The editor therefore keeps
`selectedId` (what you clicked, drives the highlight and the cover art) apart from `selected`
(that release *with* its tracks, the only thing a payload is ever built from), refuses to plan
while the tracklist is in flight, and clears the selection outright if the fetch fails. Do not
collapse those two pieces of state back together.

**Both interface causes are now FIXED.** Measured in the running app, not estimated:

| | before | after |
| --- | --- | --- |
| expanding a release row | 711 ms freeze | **1.2 ms** |
| track `<div>`s built while `display:none` | 2,832 | **0** |
| forced synchronous layouts per expand | 1 (up to 962 ms) | **0** |
| font bytes fetched on load | 1.6 MB / 30 faces | **0** |

1. **`renderBody` builds a release's track list on FIRST EXPAND, not up front.** It used to
   build every track of every release eagerly into a container that is `display:none` until
   clicked — roughly half of every node in the document, for markup nobody had asked to see.
   A `tracksBuilt` flag makes it once-only and a DocumentFragment makes it one insertion.
   **Keep it lazy.** This is the single largest interaction win in the app and it is one
   `if` away from being undone.

2. **`checkScrollability()` is gone entirely**, along with its resize listener and all six
   call sites. It read `scrollHeight`/`clientHeight` on two containers — forcing a
   synchronous full-document layout, on every expand toggle — to toggle a class whose whole
   effect was **ten pixels of right padding** to clear the scrollbar. `scrollbar-gutter:
   stable` on `.scrollable` does that in CSS, always, for nothing. It also removed the
   layout shift the probe caused, where content jumped sideways the instant it grew past the
   fold. **Do not reintroduce a JS scrollbar probe** — reserve the space in CSS.

**Neither was a framework problem**, and both are reintroducible in Preact verbatim. When the
releases grid is finally ported, port the laziness with it.

**Three more came out of the design overhaul**, all of them things that cost nothing to keep
fixed:

- **The 30 bundled OTF faces are no longer referenced.** Only 7 ever loaded and `main-font-semi`
  (10 faces) was referenced by nothing at all. The interface uses the platform's own UI and
  monospace stacks now, so the page fetches **no font files whatsoever** — verified in the
  network log. (The `.otf` files lingered on disk until v0.6.7, when they were deleted as an
  unlicensed commercial font; and since v0.6.7 the page does fetch one font file again - the
  bundled 35 KB Noto Sans Latin subset.)
- **The loading indicator no longer animates the `content` property.** Swapping `content`
  twelve times a second replaces a text node, and each swap is a layout plus a paint. It is a
  gradient sweep now, over a 2px-tall element.
- **The full-viewport fractal-noise overlay is gone.** It was a repeated SVG the compositor
  repainted on scroll, for an effect set to 5.5% opacity.

### What the library tab sends (v0.9.20, the audit)

Measured on a generated library of 1,060 albums (the scratchpad's `biglib.py`). Opening the tab
fetched the album list TWICE (the snapshot, then the scan), each 4.3 MB, uncompressed, every visit.

| | before | after |
| --- | --- | --- |
| `/library/albums`, raw JSON | 4,320 KB | **1,900 KB** |
| on the wire, first visit | 4,320 KB (nothing was gzipped) | **63 KB** |
| on the wire, an unchanged library revisited | 4,320 KB | **~300 bytes** (a 304) |
| warm scan (every folder cached) | 69 ms | **45 ms** |

- **Gzip, for text only.** `CompressText` in app.py wraps Starlette's `GZipMiddleware` and skips
  the picture and font routes, which are compressed already - and, since 1.0.3, the player's
  stream and cover relays and its PNG icons. The relays are skipped for CORRECTNESS, not CPU:
  GZipMiddleware compresses any streamed body whatever its size and drops its Content-Length, so a
  206 came back gzipped with no length. The list is `serves_media()` (shared with `GuardMedia`)
  plus `CompressText.BINARY`, and the library's picture routes are matched exactly: the old
  `/deadwax/library/art` PREFIX also caught every `/deadwax/library/artist*` JSON route, which is
  gzipped now. See "Ported onto 1.0". It is plain ASGI, like the other
  middleware here: `BaseHTTPMiddleware` would break `request.is_disconnected()`, which the
  search cancellation relies on. GZipMiddleware already leaves `text/event-stream` alone, so the
  log stream is untouched.
- **Tracks travel compact** (`compact_for_wire` in library.py, undone by `expandTracks` in
  `ui/src/api/library.ts`). The fields that repeat on every track of an album (artist, album,
  album artist, dates, release id, format) go once per album as `track_defaults`, and a track
  carries only what DIFFERS, which is the mis-tagged file the track viewer is there to show.
  Two fields the interface never reads are dropped. It builds NEW dicts: a scan's albums are
  copies, but their track lists are the cache's own, and trimming them in place would strip the
  cache. **Anything that reads `/library/albums` other than `listAlbums()`/`rescan()` must go
  through the same expansion.**
- **An unchanged library is a 304.** `_json_with_etag()` hashes the body and answers
  `If-None-Match` with no body, with `Cache-Control: no-cache` so the browser always asks. That
  only works if the body is the same when the library is, and a scan's body never was:
  `scanned_at`, `scan_seconds`, `cached` and `stale` change on every scan. **They are headers
  now** (`X-Scanned-At` etc., `_SCAN_HEADERS`), and a 304's headers freshen the browser's
  stored copy (RFC 9111 §4.3.4). So "Scanned just now" stays true on a 304. **Verified in the
  real page**: 300 bytes per request on a revisit, with the summary still fresh.
  **Don't put a per-scan value back in the body**; it would quietly make every answer a 200
  again, and nothing would fail. `/owned` lost `stale` for the same reason (nothing read it).
  The first scan after a restart still differs from later ones, because it enrols `first_seen`
  for new albums; the test warms up first.
- **The warm scan's cache pruning** compared every cache key with a pathlib `relative_to()`
  round trip, which was half of a warm scan. It compares cache keys as they are now.
- **`naming.validate_template` and `folder_pattern` are memoised.** The scan reads every
  album's edition back out of its folder name, and it rebuilt the regex each time.

### Page start-up, the log, and escaping (v0.9.21-0.9.22, the audit)

- **The pings wait for the log stream to OPEN, not for a fixed sleep.** The MusicBrainz ping
  writes "Connection successful" to the log, and the stream keeps no history, so a line logged
  before the page is listening is lost. `sleep(100)` was a guess at that. `init.js` now awaits
  the EventSource's `open` (or `error`, capped at 2s), after drawing the pills as pending.
  **Measured:** the pings start 3ms after DOMContentLoaded. Before, they waited for a config
  fetch, the stream, and then 100ms.
- **...which exposed a 0.9.20 regression: Starlette's gzip holds a response's HEADERS until its
  first body chunk, whatever the content type.** It doesn't compress `text/event-stream`, but it
  still holds the stream's start back, so the log stream didn't open until the first event or
  the 15s keepalive. Events still arrived, so nothing looked broken. The stream now yields a
  comment the moment it connects, which also gets through any buffering reverse proxy.
  `tests/test_log_stream.py` drives the whole app, middleware included, and fails without it.
  **Any other streaming response behind `CompressText` needs the same first chunk.**
- **Log lines are built as TEXT.** `appendEvent` used to set them as innerHTML, and the log
  quotes MusicBrainz titles, Soulseek queries and folder paths, all typed by strangers.
  **Verified:** a search for `<b id="injected">` logs the markup literally and creates no
  element. No server message carries markup (checked), so nothing is lost. The connection
  pills set their code as text too.
- **Removed as unused:** `/monitor_slskd/config`, which startup fetched only to log "Loaded
  server config" and whose answer nothing read (the settings tab has `/deadwax/settings`);
  `utils.js`; the connector-line element the pills made and the CSS then hid.
- **Everything MusicBrainz sends is escaped on its way into markup (v0.9.22).** The search
  view's cards and release grid were built from template strings holding titles, artist
  names, labels, catalogue numbers and disambiguations straight from MusicBrainz, some of them
  inside `title="..."` attributes, where a straight quote ends the attribute (MusicBrainz's own
  format names carry one: `12" Vinyl`). `esc()` in main.js wraps every such value.
  **Verified** by stubbing the search's fetch with a group whose every field held an `<img>`
  and quotes: no element was created, every tooltip read in full, including the full-tracklist
  rows. **A new `${...}` in main.js markup takes `esc()`** unless it is our own constant; the
  Preact half has no raw HTML at all. The two "Specific releases" toggles, one for a card that
  came with its releases and one for a card that fetched them, were the same code twice and
  are one `mountReleases()` now.
- **One outside-click rule on the Preact side: `useDismiss` (v0.9.23).** The candidates panel's
  Signals and Quality dropdowns were the same shell written twice (open state, outside-click
  effect, toggle, badge), and closed on a plain outside click, so a press on a label inside that
  slipped off it closed the dropdown. That is the bug Downloads fixed in v0.6.8, and Downloads
  now uses the same hook. They are one `FilterDropdown` now. `close` goes through a ref so a
  re-render can't re-subscribe mid-press. **Verified with real pointer drags**: a press on the
  "titles" label released outside the panel closed the old dropdown and leaves the new one
  open; a plain click outside still closes it; Downloads still closes on Escape and on an
  outside click. **A range slider's own drag was never affected**: Chrome keeps the pointer on
  the slider, so its click lands on the slider. Measured by dragging one on the OLD build,
  because the first draft of this change assumed otherwise.
- **The downloads poll reads only what the panel shows (v0.9.24).** `list_jobs()` runs twice a
  second with the panel open, and decoded every job in full: the stored release, and up to ten
  runners-up with their whole file lists. 50 jobs came to 1.4 MB of JSON and 7.2ms a poll on
  this Mac (a NAS CPU is several times slower). The panel reads neither. It now selects no
  release, and extracts the runners-up's usernames in SQL, and only for failed or cancelled
  jobs, the only rows that show "next peer". It sends `alternatives_left` for those rows only.
  Even that extraction costs 3ms over fifty rows, which is why it is gated. **1.3-1.6ms now.**
  `get_job()` still returns the whole row, so the retry and the organizer are unchanged.
  `RETRYABLE_STATUSES` moved into store.py, where both the route and the query read it.
  **Verified end to end**: a download queued from the candidates panel and then cancelled
  showed "next peer, 2 other peers left", and the older failed rows with no peers left showed
  no button.
- **The library tab on a thousand albums (v0.9.25).** Measured in the real page against the
  generated library (1,060 folders, 980 albums, 12,720 tracks), with a timer heartbeat for
  main-thread stalls, since the pane's long-task observer reports nothing:
  - **An unchanged scan is not read.** Opening the tab drew the snapshot, then parsed, rebuilt
    and re-rendered the scan behind it: a second stall of 150-200ms for a body that was
    byte-identical. The ETag is a hash of the body, so `loadScan(mode, shownEtag)` compares it
    with the one on screen and, on a match, cancels the body and updates only the scan fields
    from the headers. That is the usual case. `useLibrary` keeps what's on screen in `shown`;
    `listAlbums()` stays for the settings tab's re-time, which has nothing to compare against.
  - **`expandTracks` fills in place**: 35ms of object spreads became 3ms, with identical content
    (checked). `tree.sim.cjs` pins that a track's own value still wins.
  - **The filter settles for 200ms** (`FILTER_SETTLE_MS`) before the tree follows it; emptying
    it applies at once. A broad match opens everything it touches, and "t", "tr", "tra" each
    rendered that tree for nobody.
  - **The tree is a memoised element**, with its three callbacks made stable (they only set
    state). The view re-renders on every keystroke, and with 12,720 rows on screen each key
    diffed all of them: **65ms a key, now 5-7ms.** Preact skips a component whose element is
    the one it rendered last, so this needs no `preact/compat`.
  - ~~Still slow: the first render of a HUGE result~~ **Windowed in v0.9.30, asked for** -
    see "The tree draws only what is in view". (`content-visibility: auto` had been tried first:
    it cut layout but added render time, a net 20%, with paint containment and guessed heights.)
- **A line logged from a worker thread never reached the page (fixed v0.9.26).** `SSEHandler`
  fell back on `asyncio.get_event_loop()` outside the loop, which from a worker thread raises or
  finds a loop that isn't running, and the handler swallowed that. Six page-bound lines run
  inside `asyncio.to_thread` and were all lost: "re-filed X as Y", "wrote cover.jpg", "deleted
  ...", an artist's albums moving, CD art saved, and the download cleanup naming what it removed,
  which the v0.6.20 entry above promises it says. The handler now hands the line to the loop the
  streams registered from. **Verified on 3.12 and 3.14**, and `test_log_stream.py` fails
  without it. **Anything logged with `frontend: True` from a thread relies on this.**
  logger.py also lost a TZ block that computed a time and discarded it, a formatter whose
  output was overwritten, and an `event_time` field the page never read (it stamps lines
  itself). `TZ` still sets the container's clock, because libc reads it, not this code.
- **Ten packages nothing imports are out of requirements.txt (v0.9.26)**: aiohttp and its seven
  helpers, musicbrainzngs (the client is hand-written on httpx), and colorama, which click only
  wants on Windows. Found by walking every import in src/ with `ast`. The HTTP/2 trio (h2,
  hpack, hyperframe) stays, because the MusicBrainz client asks httpx for `http2=True`.
  **Verified** by installing the trimmed list into a clean Python 3.14 venv (the image's
  version): `pip check` clean, 868 tests passing, none of the ten pulled back in.
- **`.dockerignore` is tracked again.** Upstream deleted it and gitignored the name ("rm
  dockerignore", no reason given), so a local build sent `.git`, `.venv`, `.devdata` and `.env`
  to the builder, and `COPY ui/ ./` would lay a local macOS `node_modules` over the Linux one `npm
  ci` had just built. CI builds from a clean checkout and never had either problem.
- **pyflakes found a bug the tests couldn't (v0.9.27).** `read_artist_mbid` called
  `mutagen.File` without importing mutagen, from the day it was written (v0.6.15). The
  NameError fell into its `except Exception: continue`, which reads as "no id on this file", so
  it returned None for every album. Until v0.9.14, when the scan began carrying album-artist
  ids, every artist page therefore resolved by a NAME SEARCH, the path the artist-page entry
  warns can match the wrong band. Since then it mattered only where the scan can't answer: a
  collaboration, or files tagged with a track-artist id alone. The import is added and
  `test_the_artist_id_is_read_from_the_tags` pins it (it fails without it). The same run
  cleared 31 f-strings with nothing to format, unused imports and `as e` bindings, and a
  `logger.info("talking heads!")` on every MusicBrainz ping. **CI now runs `pyflakes src
  tests` before pytest.** An undefined name inside a try/except passes every test that
  doesn't reach it, and this one hid for twenty versions.
  The vanilla scripts got the same treatment with `tsc --allowJs --checkJs --noUnusedLocals`,
  keeping only its unused-name diagnostics (the type errors are noise on untyped code): an
  `img` created and never used, and an `artistId` that `buildReleasesGrid` took and ignored.
- **Ranking candidates is four times faster, with identical results (v0.9.28).** 97% of it was
  `match_tracks_to_files`: every expected track against every file of every folder, each pair a
  fresh `SequenceMatcher` over names normalised again for every pair. On 300 folders of 12 tracks
  that is 25,650 of them, 278ms, and it ran ON the event loop, holding up every other request.
  Now each file's name is normalised and indexed once, and only the title changes per
  comparison. A perfect 1.0 ends the search for that track, since the first one found was
  always the one kept. A pair that difflib's cheap upper bounds (`real_quick_ratio`,
  `quick_ratio`) rule out is never fully compared. **68ms, and the whole ranking of the
  benchmark came out byte-identical** (every folder, score and signal).
  `test_the_fast_matcher_pairs_exactly_as_title_similarity_would` holds it to the pair-by-pair
  definition on 200 awkward random cases, and fails when mutated to keep the last tie. The
  ranking also runs in `asyncio.to_thread` now. `title_similarity` stays as the definition.
- **slskd is asked for the downloads of the jobs' own peers, not all of them (v0.9.29).** The
  poller, `/jobs`, cancel and the cancelled-transfer tidy all fetched slskd's WHOLE download
  list, which is every transfer it has kept and only shrinks when somebody clears it. 300
  finished albums is 2.3 MB of JSON a poll (8ms to parse here, several times that on a NAS,
  plus slskd building it), twice a second with the panel open. `get_downloads(usernames)` asks
  slskd's per-user endpoint for each peer side by side; one peer's is a few KB. A 404 means
  slskd holds nothing for that user, which is exactly what absence from the full list meant.
  Any other failure answers NOTHING, not a partial list, because a job missing from a partial
  answer would look like its peer had vanished and walk toward the unmatched grace limit. The
  username is encoded whole, since slskd_api's own `quote()` leaves `/` as a path separator.
  The raw `/download/downloads` debug route, which nothing called, went with it. **Verified live
  against the fake slskd**, taught slskd's per-user answers and 404: a queued download matched,
  with its queue position; cancel found and cancelled all ten transfers; and the fake logged
  no full-list request at all. The test fakes for the poller and `/jobs` answer only for the
  users they're asked about, so a caller that forgets a peer fails.

## Frontend migration (in progress)

**Preact + Vite + TypeScript, in `ui/`.** Adopted incrementally: the vanilla app still serves
the page, and ported panels mount into it via one extra module script.

**→ Full plan, API surface, port order and traps: [docs/FRONTEND-MIGRATION.md](docs/FRONTEND-MIGRATION.md).**

| ported | still vanilla |
| --- | --- |
| Downloads panel, tab shell, library explorer (tree + details pane), metadata editor, metadata queue, delete dialog, cover viewer, tag editor (v0.6.9 - born in Preact), candidates panel (v0.9.10) | search bar, releases grid, filter column, log |

**Beside the port, the one app** (2.0.0-player.9): the page at `/player/` is growing into the app
that will replace the main page - five tabs with the player inside them, born in Preact, with
Search and Requests linking to the main page until they are built. See "The one app"; when it
covers everything the main page does, the vanilla half retires in one commit.

**How the two halves coexist:**

- `interface/index.html` provides empty mount points (`#downloads-root`, `#tabs-root`,
  `#library-root`) and loads `dist/deadwax-ui.js` after `main.js`. The mount points are
  `display: contents` where they sit inside a flex row, so the layout is untouched.
- Ported components reuse the **existing class names and IDs verbatim**, so `main.css` applies
  unchanged. A visual difference means a porting mistake, not a restyle.
- Both files are ES modules and can't call each other, so cross-boundary calls meet on
  `window.deadwax` (`ui/src/bridge.ts`). Entries today: `refreshDownloads`,
  `openCandidates` (v0.9.10), `buildDownloadRelease` (2.0.0-player.15 - the one payload builder,
  for the releases grid's Find buttons), `closeDownloads`, `closeOtherDropdowns`, `runSearch`,
  `refreshNewImports`. **An empty bridge means the migration is done.**

Why, from measurements of the original code:

| hand-rolled machinery | count |
| --- | --- |
| render/refresh/notify functions | 12 |
| call sites that must remember to call one | **29** |
| `innerHTML` assignments | 43 |
| separate mutable state objects | 7 |
| `buildReleasesGrid` (unreusable table) | 312 lines |
| hand-written keyed reconciliation | 81 lines → **deleted**, replaced by `key={job.id}` |

Those 29 call sites *are* the "things not updating" complaint.

**Don't expect the port to shrink the codebase — it doesn't.** Downloads went from 260 lines
of `main.js` to 507 across six files. Roughly half is comments and types, and the reusable
parts get spent again by later panels. The return is the deleted reconciler, compile-time
checking, and rows that can't silently stop updating — not fewer lines.

Preact over React: same API, ~4 KB vs ~45 KB, `preact/compat` keeps the React ecosystem
available. TypeScript would have caught the real `releaseGroupContext is not defined` bug at
compile time.

## Conventions

- **Commits must set the author explicitly**, git defaults to a local placeholder here:
  `GIT_AUTHOR_NAME="James Barnett" GIT_AUTHOR_EMAIL="jamesambarnett@gmail.com" git commit …`
- Commit messages explain *why*, and name what was verified vs assumed.
- **Every commit on main bumps the patch version and leaves the README current** (a commit on
  any other branch doesn't - see "Branches and versions"). Both in the same
  commit as the change itself, not swept up afterwards — the point is that the history reads
  as a clean progression rather than as a pile of work with a version bolted on at the end.
  The README is the only description of this project most people will ever read, so a commit
  that changes behaviour and leaves it stale has made the docs wrong, not merely incomplete.
  If a commit genuinely changes nothing a user could notice (a comment, a test, a refactor),
  say so in the message rather than inventing a README edit for it.
- **`docs/` is the user guide (v0.9.32), and it is kept current like the README.** One page per
  part of the app (getting started, configuration, finding music, downloading, organizing, the
  library, the phone player since 1.0.3, matching, troubleshooting), written for someone seeing
  deadwax for the first time and checked against the code rather than memory: every setting,
  default, label and limit in it was read from the source. A change a user would notice updates
  the page describing it in the same commit. **A new setting goes in configuration.md**, and a new failure a user could
  hit goes in troubleshooting.md with what to do about it.
- **Bumping the patch version is not the same as tagging it, and the difference matters
  here.** `docker-publish.yml` builds and publishes an image for every pushed `v*` tag, and
  moves **`:latest`** for any version without a hyphen in it. So tagging every commit would
  move `:latest` on every commit, which is exactly what `:experimental` exists to prevent —
  see the image-tag note below. Bump the version as you go; tag when you mean to ship.
- Versions: `v0.x` tags until **1.0.0, released on 2026-09-27** when James called it polished,
  as the first release on `main`. The patch bump per commit carries on from there; the MINOR
  moves when James says so - 1.1.0 (2026-09-29, disc titles) was "push it as 1.1".
- Image tags: `:experimental` = main, rebuilt on every push (the experimental branch's until
  1.0.5); `:latest` = the newest real release. `:latest` only ever moves for a real release, never a branch or prerelease —
  the workflow enforces this by skipping `:latest` for any version containing a hyphen.
  **As of v0.3.0 `:latest` is the slskd-direct line, not the Lidarr one**, and since 1.0.0 `main`
  is too - the repo's default branch showed the old Lidarr README until then. The example
  compose file points at `:latest` from 1.0.0, not `:experimental`.
  **`:player` = the `player-spike` branch (1.0.4, asked for)**, the phone player's trial build:
  its own explicit case in docker-publish.yml (the generic branch fallback would have named it
  `:player-spike`), tested through the workflow call like experimental, so tests.yml's own push
  trigger ignores that branch too. It moves neither `:latest` nor `:experimental`.

## Local development

```bash
.venv/bin/python -m src.main          # needs .env; the dev one sets DB_PATH=.devdata/jimbrainz.db
.venv/bin/python -m pytest tests/ -q  # 2048 tests (the audio ones skip without numpy, soxr and soundfile)
```

Frontend, from `ui/`. **Needs Node `^20.19.0 || >=22.12.0`** — see the npm gotcha above:

```bash
npm install
npm run build      # tsc --noEmit && vite build -> interface/dist/, required to see downloads
npm run typecheck  # tsc alone; runs on older Node when the build won't
npm run dev        # harness on :5173, proxies /deadwax + /styles to :8080 (start the backend first)
```

```bash
node ui/test/speed.sim.cjs      # the derived download rate, simulated against a known truth
node ui/test/queue.sim.cjs      # the tab badge and the review queue agreeing on what's outstanding
node ui/test/downloads.sim.cjs  # optimistic overlays incl. the wrong-prediction paths, and announcing filed albums
node ui/test/sort.sim.cjs       # result ordering - undated groups, ties, and relevance-as-no-op
node ui/test/tree.sim.cjs       # the library tree - what's on screen when, filtering, discs, field choices, compact tracks, windowing
node ui/test/tags.sim.cjs       # hand tag edits (only edited fields sent), ticking, column order/widths, disc default
node ui/test/credits.sim.cjs    # credited vs current artist names - release.ts's (a download's folder and the editor's) held to the main page's drawing copy in credits.mjs; isVideoTrack's cases
node ui/test/tracklist.sim.cjs  # one base tracklist per release group, and what each pressing changes - the .mjs and its TS port, on real groups
node ui/test/owned.sim.cjs      # which search results the library already holds - by pressing, by album, "maybe" by name - both copies
node ui/test/latest.sim.cjs     # only the newest answer counts - both copies of the guard, answers arriving out of order
node ui/test/candidates.sim.cjs # the candidates panel's filters, the edited-query rule, and what a row says; the app's source cards' words, the Lossless chip, when a pick is made, the quality floor (lib/getSettings.ts)
node ui/test/playqueue.sim.cjs  # the phone player's queue - what previous does, shuffle's first song, what counts as a play
node ui/test/gapless.sim.cjs    # the gapless switch - what the standby holds, hand over or not, which events count, memory
node ui/test/scrub.sim.cjs      # the player's scrubber - a point on the bar, fingers and keys, a seek on its way, where it landed
node ui/test/player.sim.cjs     # the REAL usePlayer through a fake DOM - seeks on their way, the readout across song ends, a handover
node ui/test/wrap.sim.cjs       # which browsers ask for FLAC inside an MP4 (WebKit, not Chromium), which songs, what the readout says
node ui/test/fmp4.sim.cjs       # reading a fragmented MP4's head as the stream does - init, fragments, what it refuses
node ui/test/stream.sim.cjs     # the stream's pure rules - joins, placing songs, what to fetch next, answers, retries
node ui/test/settings.sim.cjs   # You > Playback - Maximum quality's keys and notes word for word, Gapless a checkbox whose tap calls the player, Now Playing opens as and its key, Pause winds the record down and its key
node ui/test/routes.sim.cjs     # the app's routes - the hash, per-tab stacks, back labels, and the router against a fake history
node ui/test/app-rules.sim.cjs  # the app's gesture rules - usePlayer once, playback actions only from allowed files, no audio in app/, the turntable's audio context only from gestures (never the cover's), nothing touching the player's element
node ui/test/discs.sim.cjs      # disc headings from Navidrome's discTitles - "Disc 4 · <title>", and when headings show
node ui/test/you.sim.cjs        # the You tab - asked when it first shows, /me asked again, what it says, the live regions, Getting albums and their store (seeded once, asked again, saves in turn)
node ui/test/debug.sim.cjs      # Info > Debug's rows - Format, Sent as, Resampled, Why, Gapless, Gap, Last seek, Turntable sound, Navidrome sent
node ui/test/info.sim.cjs       # Info > About's rows, and every sheet (Now Playing, •••, Info): locks, focus in and back, Escape
node ui/test/turntable.sim.cjs  # the turntable - the arm, turning the record 1.8 s a turn, tap vs drag, seek on release, when it spins, the look button; with the deck's sound, the press, release, wind-down and the arm during a coast
node ui/test/requests.sim.cjs   # the Requests tab and Home's Arriving - grouping, every row's words, one primary, Arriving = the badge, asking again, the ✕'s question, what a screen reader hears
node ui/test/searchQuery.sim.cjs # the app's one search box - an artist at either end, an artist alone, va, the brackets before a type filter, what's left out
node ui/test/pressings.sim.cjs  # the album you don't have - the default pressing, the dropdown's list and fold, the line above the tracklist, Bonus rows, disc titles
node ui/test/group.sim.cjs      # that page and its dropdown rendered - asking, Try again, the session's cache, a pick, the listbox, focus going nowhere, Get and what's already here of the pressing (under Get, asked again as the page shows)
node ui/test/payload.sim.cjs    # the ONE download payload builder, deep-equal to what the main page's two Find buttons sent before the move (8 captured cases, labels too), and which credit each field comes from
node ui/test/sources.sim.cjs    # the Sources sheet and its cards rendered - only the newest search, Cancel letting it go in the gesture, a Get from the tap with its runners-up, the best match whatever the sort, the chips, a pick for you and when it isn't made, Re-search, slskd's words, the store's box, the live region, focus kept in the sheet
node ui/test/search.sim.cjs     # the Search tab rendered - both halves, a song's tap, the gate, held albums left out once, a box cut back; useOwned; the real prefetch; the rows' Get chips, and their lookups called off when you move on
node ui/test/deck.sim.cjs       # the turntable's momentum and sound - the physics against an integration, the voice, the worklet from its source, the main-thread voice where there is no worklet, the deck against fakes (its windows, coasts, handovers, wind-downs, when a press is its own)
```

`npm run dev` serves `ui/index.html`, a harness for working on one component in isolation with
HMR — **not** the real page. The real page is still `interface/index.html` served by FastAPI on
8080, and it only picks up frontend changes after `npm run build`.

`.env`, `.devdata/`, `run_dev.sh`, `.claude/`, `node_modules/`, `interface/dist/` are gitignored.

**CI (v0.9.4): `.github/workflows/tests.yml`** runs pytest on Python 3.12 (the oldest this claims)
and 3.14 (what the image ships), `npm run build` on Node 22 (typecheck included, as the image
does it) and every `ui/test/*.sim.cjs`, each on its own so a failure names itself.
**`docker-publish.yml` calls it and its build `needs:` it**, so a tag whose tests fail publishes
no image and moves no `:latest`. To keep one push from being tested twice, `tests.yml`'s own push
trigger ignores `main` - pushes to it, and `v*` tags, are tested through the publish
workflow's call instead. **A new sim is picked up by the glob; a new Python test dependency has
to be added to the workflow's install step** - `requirements.txt` is the image's, and pytest is
deliberately not in it.

## What the tests cannot tell you

All 2048 tests are fixture-driven, and **nothing in the suite has ever talked to a real
slskd** - the application now has, once, and the first search it tried was refused. The parts
most likely to break on deployment are exactly the parts tests can't reach:

- slskd transfer `state` strings. **This one already came true**: `"Completed, Rejected"` was
  not in the recognised set, so a refused download sat at `queued` indefinitely — see the
  gotcha above. `TRANSFER_FAILURE_REASONS` in `store.py` now holds every terminal substate, and
  is the first place to look if a job never leaves `queued` or `downloading`.
- Whether slskd is in a state where it can search at all. **This one came true too**, on the
  first live run: the search failed with a 409, which slskd uses to mean its Soulseek connection
  is down. No fixture could have produced it, because nothing here had ever seen slskd REFUSE a
  search - only answer one. `SEARCH_REFUSALS` in `slskd_endpoint.py` now names every status it
  refuses with, and `tests/test_slskd_errors.py` rehearses each against slskd's own documented
  payloads.
- slskd's on-disk download layout — `find_local_file()` searches by basename rather than
  reconstructing paths, precisely because the layout isn't guaranteed.
- Whether `SLSKD_DOWNLOAD_PATH` actually resolves to the same files slskd writes. This is the
  most likely first-run failure, and the app now says so explicitly instead of pretending.
- Navidrome, the same way (1.0.3). Every Navidrome in the suite is a fake shaped from its source
  as read at 46c4327, not recorded from a real 0.64.2: what a transcode really sends, what
  `getScanStatus` really answers mid-scan, and how the watcher really times its scans are the
  first places to look when the player or the scan wait misbehaves.

A green suite here means the logic is sound, not that it works against real infrastructure.

## Next up

1. **Run it against real infrastructure. STARTED in v0.6.17, and it broke immediately** - the
   first live search came back `409 Conflict`, which is slskd's way of saying its own Soulseek
   connection is down (see the gotcha above). By v0.6.19 albums were being downloaded AND
   organized for real - James reported them filing, just appearing late - so the search,
   enqueue, completion and filing path has run end to end at least once. Still unwatched: the
   derived download speed (byte deltas, not `job.speed`), queue position, and cancel.
2. ~~Merge to `main`~~ **Done for 1.0.0** - a fast-forward, since `main` had nothing the
   experimental branch lacked.
3. Continue the port in the order in [docs/FRONTEND-MIGRATION.md](docs/FRONTEND-MIGRATION.md):
   ~~candidates panel~~ (done, v0.9.10), filter column, releases grid, top bar.
4. ~~A Settings tab~~ **Done in v0.5.** It landed exactly as this entry predicted — one
   `TABS` entry, a `#settings-root` pane, one `[data-tab]` rule, no structural change. It
   also replaced the "download profile" dropdown, which is gone from the top bar.
   Naming templates are still not in it: they'd be the first *writable* server setting and
   there is nowhere to persist one yet (see the decision below).
5. ~~Fix the two performance bugs~~ **Done in v0.5** — see the performance section above.
   When the releases grid is ported, carry the laziness across with it.
6. ~~A type scale~~ **Done in v0.5.** The scale, and the spacing/radius/shadow/motion scales
   beside it, live in `theme.css`. What is NOT done is applying it exhaustively: the
   foundation and every surface touched in the overhaul are on it, but `main.css` still holds
   legacy `em` sizes in corners nothing has revisited. Convert them as you touch them —
   a mechanical sweep of 3,800 lines would be a large untestable diff for little gain.
7. **The candidates panel has now been SEEN, but still not against a real slskd.** It was
   rendered by stubbing the `find_candidates` fetch in the browser and driving the real
   `renderCandidates()` path with three fabricated peers — the chrome, the score column, the
   signal chips, the filters and the mobile layout all check out at 1440px and 375px. What
   that cannot tell you is anything about real Soulseek data: whether real directory names
   overflow, what genuine `signals` distributions look like, or whether the query box and
   re-search behave against a live search. **Stubbing the fetch is a cheap way to look at
   this panel again** — it needs no slskd and takes one `window.fetch` override.
8. ~~Recapture `assets/images/library.png`~~ **Done in v0.6.21**, with the other four, for the
   rename, and **all of them again in v0.9.33**, with six new ones. See "Capturing screenshots".
9. ~~An album stored one folder per disc shows as "editions"~~ **Done in v0.9.13** - see
   "Albums stored one folder per disc".
10. **Upgrade the local Node to 22** so `npm run build` works again without the rolldown
    workaround in the tooling notes.
11. **A week of the phone player on James's iPhone, locked** (spiked at 0.8.0, ported in 1.0.3):
    plain http over WireGuard, against Navidrome 0.64.2. Everything it exists to find out is on
    the NOT-verified list in "The phone player", plus the port's own open questions - how Safari
    takes a transcode (an estimated length and no ranges: play an Ogg file and seek in it),
    landscape insets, `timeupdate` while locked, which Ogg codecs it says it plays, whether a
    failed song's 1.5s retry fires on a locked phone (and whether WebKit sends `pause` after
    `error`, as Chromium does), how long the scan wait really takes against a real Navidrome, and
    where seeks land in Safari on the phone (Info > Debug's "Last seek" row, the readout's line
    until 2.0.0-player.10), and now the one
    stream as deadwax builds it (the list under "One stream for FLAC"). **The week gates step 2 of the multi-user
    plan.** If the next song won't start with the screen locked, that is the answer to "can a web
    app do this", and native is back on the table.

### Deliberately not built

Worth knowing before someone "fixes" one of these:

- ~~Per-track editing~~ **Built in v0.6.9, because James asked for it** - "a way to manually
  edit metadata per-song with a selection option so I can also mass-edit". The metadata editor
  still takes a release's tracklist wholesale, and files it doesn't reach still keep their own
  title and number; hand edits are a separate tool beside it. See "Editing tags by hand".
- **Embedding art into the audio.** Only a cover file is written; it's what `find_cover_file()`
  prefers and it's one write instead of one per track.
- **Undo.** For retag or delete. The preview is the safety net for the first, and the
  confirmation dialog for the second — so keep both honest.
- ~~Persisting the scan cache~~ **Built in v0.6.5, because James asked for it** - "so the scan
  doesn't take so long and I can still see what's in the library without a full scan every
  time". The old objection (the per-folder mtime cache makes a rescan cheap) was right about
  tag reads and wrong about the walk: on a network share or a spun-down array, statting every
  folder IS the wait, and a restart threw away every tag read on top. See "The saved scan".
- **Bulk apply in the metadata queue.** Considered and deliberately declined for the first cut.
  Auto-matching releases across many albums at once would write tags to albums nobody looked
  at, and **there is no undo** — the preview is the safety net, and a bulk action is precisely
  the case where nobody reads it. The queue makes reviewing *fast* (facets narrow it, the
  editor steps through it with its search already running) rather than making it automatic.
  The bulk operation that would be genuinely safe is folder renames to match the convention,
  since those are fully determined by the tags and need no MusicBrainz guess: `misfiled` is
  already its own facet, so that is where it would hang.
- ~~Retrying a rejected download~~ **Built in v0.9.12, one of the 1.0 items** - the candidates
  are stored with the job now. See "Trying the next peer".
