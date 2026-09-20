# jimbrainz — working context

Read this before doing anything. It records decisions and hard-won gotchas that aren't
recoverable from the code, so you don't re-litigate settled questions or re-discover
problems the expensive way.

## What this is

A fork of [LidBrainz](https://github.com/dual-shock/lidbrainz) that has diverged a long way.
Upstream sends releases to Lidarr. **This fork removed Lidarr entirely and talks to slskd
directly.**

Repo: `real-lizardwizard/jimbrainz` · owner is James Barnett (jamesambarnett@gmail.com).

**Where it runs: OpenMediaVault, with Komodo managing Docker.** So compose is the deployment path
that matters, and anything addressed to "your Unraid box" is wrong. The Unraid template
(`my-jimbrainz.xml`) and the Unraid half of the README are INHERITED from upstream LidBrainz,
whose author did run Unraid and wrote those first-person notes; they came through the fork
untouched and nothing here has tested them since. **Don't read Unraid into the repo because those
files are in it** - it produced a run of confidently wrong deployment advice before James said so.

### Branches

| branch | what |
| --- | --- |
| `main` | the old Lidarr-based line, v0.2.1. Untouched by the rewrite, and now behind it. |
| `experimental/slskdn-no-lidarr` | **all the work below.** slskd-direct, no Lidarr. Releases are tagged from here — v0.3.0 onward. |

### Why Lidarr was dropped

Not preference — a specific failure. Pick a *particular* release (the 2011 remaster, the
deluxe edition) and every distinguishing detail dies at Lidarr's API boundary:
`POST /command {name:"AlbumSearch", albumIds:[N]}` carries no tracklist, no edition, no year.
The plugin doing the actual Soulseek search rebuilds a generic query and grabs whatever
returns. Tubifarry's own maintainer
[confirms Custom Formats can't target a selected release variant](https://github.com/TypNull/Tubifarry/discussions/138).

jimbrainz already knows all of it, so it owns the search and the matching itself.

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
  editions.py      PURE. Which edition a release is, in words. See below — it's why the
                   library can hold the deluxe and the standard press at the same time.
  metadata_health.py  PURE. What's WRONG with an album on disk, as issue codes. Backs the
                   metadata queue. Derived on every request, never stored — see below.
  library.py       scans LIBRARY_PATH with mutagen, cached per folder on mtime - and that
                   cache is SAVED to SQLite (library_cache), so a restart starts warm and
                   the tab can draw a snapshot before touching the disk. Also finds cover
                   art, and reads one album's files in full for the track viewer.
  store.py         SQLite job store + transfer reconciliation helpers.
  poller.py        background task: slskd transfers -> job status transitions.
  organizer.py     writes downloads into the library. Plan/execute split, dry_run default.
  retag.py         the metadata manager's write half - applies a chosen release to an album
                   already on disk. Same plan/execute split, for the same reasons.
  track_tags.py    tags edited BY HAND, on one track or a selection at once. The fourth
                   writer, and the same plan/execute split again - see "Editing tags by hand".
  artists.py       PURE. What an artist page shows, and where artist pictures come from -
                   which is nowhere near as obvious as album covers. Also renders artist
                   CREDITS, which is why a split album no longer reads as a list.
  artist_art.py    artist images written into the artist's folder. The FIFTH writer, same
                   plan/execute split - see "The artist page".
  api/             musicbrainz_endpoint.py, slskd_endpoint.py, coverart_endpoint.py,
                   artist_images_endpoint.py (Wikidata/Commons + TheAudioDB), app.py
  routes/          search_musicbrainz, download, monitor_slskd, interface_logs, library,
                   settings (editable since v0.5.1 - see "The settings tab")
interface/         vanilla JS/CSS. Still the served page; main.js is shrinking as panels
                   are ported. main.css styles BOTH halves - see below.
  styles/theme.css THE TOKEN LAYER. Every colour, size, space, radius, shadow, duration and
                   easing in the application. Because both halves consume it, editing a
                   value here restyles the vanilla and Preact sides together. Raw values in
                   main.css or in a component are a bug. NOTE it is @import-ed, so it caches
                   separately - hard-refresh when verifying a palette change.
  dist/            BUILT from ui/, gitignored. Not present in a fresh checkout.
ui/                Preact + Vite + TypeScript. New work goes here — see below.
tests/             635 tests, all Python, all fixture-driven (+ ui/test/*.sim.cjs scripts)
```

API routes are prefixed **`/jimbrainz/`** (renamed from `/lidbrainz/`).

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
  then format/country — and a collision with a *different* release escalates to the
  catalogue number and finally the release id. `release.edition_label` overrides all of it
  and is the hook for the planned metadata manager: choosing an edition by hand should mean
  writing that field, not changing how editions are resolved.
  **An untagged folder is never treated as a different release** — libraries predating
  jimbrainz have no MBIDs, and forking every one of those albums would be far worse than
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
- **There are now FIVE writers to the user's filesystem**, and all but the smallest use the same
  plan/execute split: `organizer.py` files downloads in, `retag.py` corrects albums already
  there, `track_tags.py` writes tags edited by hand (v0.6.9), `artist_art.py` writes an artist's
  pictures into their folder (v0.6.15), and `save_cover_art()` writes a single cover (narrow enough not to need a plan/execute split, but it re-checks containment at
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
  seen, whether jimbrainz filed it or merely found it, whether you've looked at it, and which
  issue codes you've accepted.
  **Ignores are per issue, not per album** — accepting that a bootleg will never be in
  MusicBrainz must not also silence the day its cover art goes missing.
  **`album_review` is keyed on the album's path**, not the scan's `key`: that key is the
  release MBID when there is one, and two folders holding the same release deliberately share
  it, so ignoring one would silently ignore the other. The cost is that a rename orphans the
  row, which is why `mark_album_reviewed()` takes a destination and the retag endpoint passes
  it.
- **The tab badge and the queue must never count different things.** They did, and it produced
  a notification that named no album: the badge counts albums jimbrainz *filed and you haven't
  looked at*, the queue counts albums with *outstanding issues*, and a freshly imported album
  with perfect tags is the first without being the second. It appeared in no facet, carried no
  chip, and the whole metadata section was hidden when nothing else was wrong — and it could
  never be cleared either, because there was nothing to apply, nothing to ignore, and it wasn't
  in the walkthrough. `queueAlbums()` now includes new imports whatever their state, there is a
  `newly added` facet and a `new` row chip, and **stepping past one is what marks it seen**.
  A notification you cannot act on is worse than no notification.
- **Prune review rows for albums that are gone.** A row is keyed on the album's path, so a
  folder renamed or deleted outside jimbrainz orphans it — and an orphaned *import* row is
  counted by the badge while being in no scan, so it can be neither named nor cleared. The scan
  drops them, but **only after a scan that actually found albums**: an empty library is far more
  often an unmounted volume than a deleted collection, and wiping every ignore the moment a
  mount goes missing would be a rotten trade.
- **The new-import prompt is recorded at import time, not derived from a scan.** The library is
  deliberately not read until its tab is opened, so a badge that had to diff two scans would
  need a scan to exist — absent at exactly the moment it has something to say. The poller writes
  one row as it files each download, and `/queue/new_imports` is a single indexed count that
  touches no filesystem. This is the only reason the import source is recorded at all.
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
  and `jimbrainz` are lowercase brand names** — never sentence-case them, rephrase so they are
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
    (`DownloadsPanel.tsx` and the log's in `main.js`) now also track where the press BEGAN,
    and reset on every click so a keyboard click is judged by its target alone.
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
  UNTAGGED, which is the common case for any library that predates jimbrainz. The fix has to
  be that the two never resolve to the same name in the first place.
- **`instrumental`, `acoustic` and `a cappella` are therefore in the edition vocabulary**, and
  that vocabulary exists in THREE places which must stay in step: `EDITION_PATTERNS` in
  `matching.py` tags the Soulseek FOLDER being offered, `EDITION_KEYWORDS` in `main.js` tags
  the RELEASE you picked for a download, and `EDITION_KEYWORDS` in `ui/src/lib/release.ts` tags
  the release you pick in the metadata editor. The first two are scored against each other, so
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
- **jimbrainz already weights it correctly**, and that did not need changing: `score_peer()`
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
  Both actions cost two sequential round-trips — one to jimbrainz, which itself calls on to
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
  `jimbrainz-library-sort` and validated on read. Undated albums sink in both directions.
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
- **Field choices have their own storage key** (`jimbrainz-library-fields`) and one writer - the
  details pane's single `useTrackFields` instance, which the menu and the table both read.
  It stores `seen` beside `visible`, so a field added in a later version takes its own default
  instead of staying hidden for everyone who ever touched the menu. Pinned in the sim. Since
  v0.6.9 the same key and writer also hold the columns' `order` and `widths` - see "Arranging
  the track viewer's columns".
- **The splitter's width is persisted (`jimbrainz-library-pane-width`) and capped in CSS** at
  `100% - 340px`, so a width saved in a big window can't swallow the details in a small one.
- **What fits on a tree row depends on the TREE's width, not the window's.** `#library-nav` is
  a size container, and `@container` rules drop the issue chip, then the year, as it narrows.
  The album name is never what gets squeezed.
- **On a phone the details pane is a full-screen sheet**, opened by picking an album or a
  track (an artist just opens in place) and closed by the command bar's back button.

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
  and `buildExpectedFromRelease()` in main.js both produce them; keep the two in step.
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
  `jimbrainz/<__version__> ( email )` - MusicBrainz's documented shape. Nothing stores the
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
  `jimbrainz/0.6.9 ( dev-test@example.com )`, and MusicBrainz answered 200.

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
- **Same key and same single writer as the field choices** (`jimbrainz-library-fields`,
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
  cannot ship with jimbrainz and has to be registered by whoever runs it; `FANARTTV_PERSONAL_KEY`
  beside it is optional and only buys sight of images added in the last week.
- **The square image is written as `artist.*`, and that is the whole point of writing files at
  all.** Navidrome reads it with no configuration: `ArtistArtPriority` defaults to
  `"artist.*, album/artist.*, external"`. Writing it as `folder.*` - what Jellyfin and Kodi call
  an artist thumb - would be invisible to Navidrome AND sits in its COVER ART priority, so in a
  folder that turned out to hold audio it would be read as that album's cover. The other five
  (`banner`, `fanart`, `logo`, `landscape`, `clearart`) are what jimbrainz's own page is made of;
  Navidrome displays none of them, Kodi and Jellyfin read them, nothing else notices.
- **A folder holding TRACKS is refused.** That folder is an album to the scanner, and dropping
  `artist.*` into it means something else entirely to every reader of these files.
- **An artist has no folder in the scan, so it is derived** from where their albums are, and
  only when they agree. Albums in two places, or one sitting at the top of the library, get a
  message rather than a guess - a picture written into the wrong folder is not dangerous, just
  silently useless, which is worse to debug.
- **Applying only honours a URL the artist's own sources just offered.** The apply route
  recomputes the candidate list exactly as it recomputes the plan. Without it, `choices` could
  name any address - inside the network this container sits in - and jimbrainz would fetch it
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
- **Known gap:** on a phone the details pane is a sheet that opens for albums and tracks, and an
  artist "just opens in place" (v0.6.5's decision). So the artist page is desktop and tablet
  only. The phone rules for it are written and inert until that decision changes.

### Artists who have renamed (v0.6.18)

James: "so Ye shows up as Kanye, that seems like a gap somewhere" - and then "I want to make
sure there won't be a ye folder and a kanye folder ... there should just be one folder with the
most up-to-date name".

- **MusicBrainz keeps ONE current name per artist and every other name as an alias, while each
  release keeps the name it was CREDITED under.** Those two disagree for everyone who has ever
  renamed, and jimbrainz writes the credit into the tags and the folder - rightly, the album
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
  both buttons, since only one of them is on the path any sim can see.
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
  jimbrainz's own client: the old query found 2 groups and not that one. `fieldedAlbumQuery()`
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
  another when corrected.
- **Collaborations still get their own folder**, in current names: Watch the Throne files under
  `JAŸ‐Z & Ye/`. That was always so (it was `Jay‐Z & Kanye West/`); only the names changed.
- **NOT built: finding albums already filed under an old name.** The scan never talks to
  MusicBrainz, so it cannot know `Kanye West/` is out of date. It COULD spot two artist folders
  whose albums share a `musicbrainz_albumartistid` - but only for albums tagged with artist ids,
  which nothing filed before v0.6.15 is, and the scan does not read that tag yet (it would mean
  bumping `SCAN_FORMAT`). Until then such an album moves when its release is picked in the
  editor, and the tree shows the old name as a second artist, which is at least visible.

### Searching Soulseek under every name (v0.6.19)

James: "make sure the same logic with ye works with the slskd search".

- **The matcher never looks at the artist; the QUERY is the only place a name decides
  anything.** `score_candidate` scores tracks, count, durations, edition, format and peer - not
  one signal reads the artist - so a share filed as `Ye/` and one filed as `Kanye West/` score
  identically once found. Finding them is the problem: Soulseek needs EVERY word of a query in a
  share's path, so "Ye BULLY" cannot find `Kanye West/BULLY` at all, and "Kanye West Donda"
  cannot find `Ye/Donda`.
- **So it searches under every name a share might carry**: the CREDIT (what the album said when
  the sharer got it), the CURRENT name (what jimbrainz and Picard's standardised names file
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
  queries are MusicBrainz's names, third-party text, and the vanilla half has no escaping helper.
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
  are one read of jimbrainz's own job table.
- **Measured in the real page** (scratch database and library, the job driven through the same
  store calls the poller makes, downloads panel closed): never, before; 5.6s with the
  announcement alone; **1.5s** with the quicker poll while filing. No Rescan in any run.

### Artist credits, and the ids behind them (v0.6.15)

Asked for as "better handling for multi-artist albums and tracks", and "get artist ID in the
metadata as well".

- **A credit's JOIN PHRASES are its punctuation.** MusicBrainz says "A / B" for a split, "A & B"
  for a collaboration, "A feat. B" for a guest spot, and it says so in `joinphrase` between the
  names. Joining on ", " - which every part of this interface did - invents punctuation nobody
  chose and flattens a duet into what reads as two separate acts. The rule now lives in THREE
  places that must agree: `credit_name()` in `src/artists.py`, `creditName()` in
  `ui/src/lib/release.ts`, and `getArtistNames()` in `interface/scripts/credits.mjs` (moved out
  of main.js in v0.6.18 so a sim can reach it). One names a folder, another
  writes the tag inside it.
- **A track keeps its OWN artist.** `tag_values` gave every track the release's artist, so
  applying a release to a compilation rewrote eighteen artists into one. The track's credit wins
  where it has one; `albumartist` stays the release's, which is what the two tags are for.
- **The artist ids are written at last**: `musicbrainz_albumartistid` and `musicbrainz_artistid`.
  Nothing jimbrainz filed had ever recorded WHO an artist was, only which release - which is why
  the artist page has to fall back to searching by name at all.
- **One id is a string, several are a list**, and `read_current_tags` reads back the same shape.
  Get that wrong and a file disagrees with itself on every preview: a bare string on one side, a
  one-item list on the other, and an album that can never again say "nothing to change". Pinned
  by a round-trip test that writes a file and re-previews it.
- **`Track` in the download request declares `artist` and `artist_mbids`.** Same trap as
  `disc`/`disc_position` before it: pydantic drops undeclared fields without a word, so a
  compilation would arrive correct from the browser and be filed under one artist anyway.

### The settings tab

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
- **Only `error` is decorated.** An unset OPTIONAL setting renders plain. When every row
  carries a colour, the row that needs attention stops standing out, which is the list's
  whole job.
- **The organizing verdict is derived server-side and stated once**, with every blocker
  listed at the same time. "Why did nothing get filed" has four possible causes across two
  groups; discovering them one at a time is how people conclude the feature is broken rather
  than misconfigured.
- **Client preferences are a separate storage key (`jimbrainz-preferences`), not more fields
  on `jimbrainz-download-defaults`.** That older blob is read and rewritten wholesale by
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
  `#format-preference-select` rules in main.css are DEAD - that element left with the v0.5
  profile dropdown and exists nowhere in the markup or scripts - so they don't need to stay
  in step with the shared rule; they need deleting when someone next tidies that corner.
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
  `dist/jimbrainz-ui.js`, which is gitignored and generated. Running from source without
  `npm run build` leaves it 404ing and that panel simply absent. Check this first.
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
  configure jimbrainz — but only with LITERAL values.** Both sources work and may be mixed
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

- **`--screenshot` and `--virtual-time-budget` cannot do this, and two attempts hung proving
  it.** The flag fires once load settles, which is before any driving has happened. Virtual
  time is the usual answer and it does not work here either: jimbrainz polls continuously, so
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
  `platform: 'browser'` and `output.file: ../interface/dist/jimbrainz-ui.js`. The Preact preset
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
  the v0.6.9 session, started in this repo, read `jimbrainz/.claude/launch.json` - and when asked
  for a name that wasn't in it, it started the plain `jimbrainz` config instead of failing:
  against the REAL `.devdata` database, with no library. **Check the name `preview_start`
  reports back before doing anything that writes.** The pattern is otherwise unchanged: a
  throwaway library of real FLACs with real tags and a throwaway database, both in the
  scratchpad, so `.devdata` is never touched. The server's port is fixed at 8080 in
  `src/main.py`, so only one runs at a time.
- **The `ui/test/*.sim.cjs` scripts fail inside the agent sandbox unless `TMPDIR` points
  somewhere writable.** They compile TypeScript into `os.tmpdir()`, which the sandbox refuses,
  and every sim - including ones nothing touched - dies identically, with only Node's version
  footer on its last line. `TMPDIR=<scratchpad> node ui/test/tags.sim.cjs` and they all pass.
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

## Frontend migration (in progress)

**Preact + Vite + TypeScript, in `ui/`.** Adopted incrementally: the vanilla app still serves
the page, and ported panels mount into it via one extra module script.

**→ Full plan, API surface, port order and traps: [docs/FRONTEND-MIGRATION.md](docs/FRONTEND-MIGRATION.md).**

| ported | still vanilla |
| --- | --- |
| Downloads panel, tab shell, library explorer (tree + details pane), metadata editor, metadata queue, delete dialog, cover viewer, tag editor (v0.6.9 - born in Preact) | search bar, releases grid, filter column, candidates panel, log |

**How the two halves coexist:**

- `interface/index.html` provides empty mount points (`#downloads-root`, `#tabs-root`,
  `#library-root`) and loads `dist/jimbrainz-ui.js` after `main.js`. The mount points are
  `display: contents` where they sit inside a flex row, so the layout is untouched.
- Ported components reuse the **existing class names and IDs verbatim**, so `main.css` applies
  unchanged. A visual difference means a porting mistake, not a restyle.
- Both files are ES modules and can't call each other, so cross-boundary calls meet on
  `window.jimbrainz` (`ui/src/bridge.ts`). Four entries today: `refreshDownloads`,
  `closeOtherDropdowns`, `runSearch`, `refreshNewImports`. **An empty bridge means the
  migration is done.**

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
- **Every commit bumps the patch version and leaves the README current.** Both in the same
  commit as the change itself, not swept up afterwards — the point is that the history reads
  as a clean progression rather than as a pile of work with a version bolted on at the end.
  The README is the only description of this project most people will ever read, so a commit
  that changes behaviour and leaves it stale has made the docs wrong, not merely incomplete.
  If a commit genuinely changes nothing a user could notice (a comment, a test, a refactor),
  say so in the message rather than inventing a README edit for it.
- **Bumping the patch version is not the same as tagging it, and the difference matters
  here.** `docker-publish.yml` builds and publishes an image for every pushed `v*` tag, and
  moves **`:latest`** for any version without a hyphen in it. So tagging every commit would
  move `:latest` on every commit, which is exactly what `:experimental` exists to prevent —
  see the image-tag note below. Bump the version as you go; tag when you mean to ship.
- Versions: `v0.x` tags. **1.0.0 is reserved for when this is genuinely polished** — a
  deliberate choice, don't jump to it.
- Image tags: `:experimental` = this branch (rebuilt on every push); `:latest` = the newest
  real release. `:latest` only ever moves for a real release, never a branch or prerelease —
  the workflow enforces this by skipping `:latest` for any version containing a hyphen.
  **As of v0.3.0 `:latest` is the slskd-direct line, not the Lidarr one.** It was tagged from
  `experimental/slskdn-no-lidarr`, so `main` still holds v0.2.1 and anyone visiting the repo's
  default branch sees the old Lidarr README. Merging this branch to `main` is still owed.

## Local development

```bash
.venv/bin/python -m src.main          # needs .env; DB_PATH=.devdata/jimbrainz.db
.venv/bin/python -m pytest tests/ -q  # 635 tests
```

Frontend, from `ui/`. **Needs Node `^20.19.0 || >=22.12.0`** — see the npm gotcha above:

```bash
npm install
npm run build      # tsc --noEmit && vite build -> interface/dist/, required to see downloads
npm run typecheck  # tsc alone; runs on older Node when the build won't
npm run dev        # harness on :5173, proxies /jimbrainz + /styles to :8080 (start the backend first)
```

```bash
node ui/test/speed.sim.cjs      # the derived download rate, simulated against a known truth
node ui/test/queue.sim.cjs      # the tab badge and the review queue agreeing on what's outstanding
node ui/test/downloads.sim.cjs  # optimistic overlays incl. the wrong-prediction paths, and announcing filed albums
node ui/test/sort.sim.cjs       # result ordering - undated groups, ties, and relevance-as-no-op
node ui/test/tree.sim.cjs       # the library tree - what's on screen when, filtering, discs, field choices
node ui/test/tags.sim.cjs       # hand tag edits (only edited fields sent), ticking, column order/widths, disc default
node ui/test/credits.sim.cjs    # credited vs current artist names - the folder a download and a correction both file under
```

`npm run dev` serves `ui/index.html`, a harness for working on one component in isolation with
HMR — **not** the real page. The real page is still `interface/index.html` served by FastAPI on
8080, and it only picks up frontend changes after `npm run build`.

`.env`, `.devdata/`, `run_dev.sh`, `.claude/`, `node_modules/`, `interface/dist/` are gitignored.

## What the tests cannot tell you

All 635 tests are fixture-driven, and **nothing in the suite has ever talked to a real
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

A green suite here means the logic is sound, not that it works against real infrastructure.

## Next up

1. **Run it against real infrastructure. STARTED in v0.6.17, and it broke immediately** - the
   first live search came back `409 Conflict`, which is slskd's way of saying its own Soulseek
   connection is down (see the gotcha above). By v0.6.19 albums were being downloaded AND
   organized for real - James reported them filing, just appearing late - so the search,
   enqueue, completion and filing path has run end to end at least once. Still unwatched: the
   derived download speed (byte deltas, not `job.speed`), queue position, and cancel.
2. **Merge to `main`.** It still holds v0.2.1, so the repo's default branch shows the old
   Lidarr README to anyone who visits, while `:latest` has been the slskd line since v0.3.0.
3. Continue the port in the order in [docs/FRONTEND-MIGRATION.md](docs/FRONTEND-MIGRATION.md):
   candidates panel, filter column, releases grid, top bar.
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
8. **Recapture `assets/images/library.png`.** It still shows the pre-v0.6.5 album-row library;
   the README text describes the explorer. Use the screenshot harness described above.
9. **An album stored one folder per disc shows as "editions".** The scan treats every folder
   holding audio as an album, so `Album (Disc 1)` and `Album (Disc 2)` group as two editions of
   one album - and applying the release to each tags them correctly (the title matcher finds
   each disc's tracks) but then wants to re-file both into the same `Album (Year)` folder, and
   the second is refused as "already exists". Now that the scan reads `discnumber`, folders
   sharing a release MBID but holding different discs are detectable; nothing acts on it yet.
10. **Upgrade the local Node to 22** so `npm run build` works again without the rolldown
    workaround in the tooling notes.

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
- **Retrying a rejected download.** The job now reaches `failed` and says the peer refused it,
  but picking a different peer is still a manual re-search. The candidates are not kept after
  enqueueing, so "try the next one" would mean storing them with the job.
