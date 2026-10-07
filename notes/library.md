# The library, the editors and the files deadwax writes

The library explorer and its scan, disc numbers and titles, the editors, artist pages, CD art and lyrics.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

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
  reads, no file opened. `/library/disc_art` serves only names that count as disc art, and
  **(v1.1.8) only a file that resolves inside its album's folder.** The listing's `is_file()`
  follows a symlink, so a `disc.jpg` linking out of the library passed on its name alone and
  was served; it is now the same 404 as a disc image that isn't there. Found building the
  player's turntable route on player-spike, which had the check from the start.
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
