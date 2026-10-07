# Search, releases and what's already held

The search view, the releases grid, discographies, and the "in your library" marks.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

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
