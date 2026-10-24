# deadwax — working context

Read this before doing anything. It holds what the project is, the rules that hold everywhere, the
decisions not to re-open, and the map - and points to `notes/`, where the detail of every area is
kept, so you don't re-litigate settled questions or re-discover problems the expensive way.

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
| `player-spike` | the multi-user and phone-player work, begun from 1.0.0 (2026-09-27, asked for), which builds its own `:player` image. It numbered its commits 1.0.1-1.0.5 before the rules below, so those numbers mean different code there than on main; its two fix commits came to main as 1.0.3 and 1.0.4, and some sections below dated 1.0.1-1.0.5 (the 1.0.1 fixes, the phone player's port) use its numbering. From here it follows the rules: `1.1.0-player.1` to `.6`, then `2.0.0-player.N` once James decided it ships as 2.0.0 (2026-09-29), when every step of the multi-user plan is done - `2.0.0-player.7` is step 2, `2.0.0-player.8` its merge of main's 1.1.7, `2.0.0-player.9` the first slice of the one app (see "The one app"). **Shipped: merged into main as 2.0.0 (2026-10-23)**, at 2.0.0-player.68; the last version with the old main page is the tag `last-main-page`. |
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

### The name

Called **jimbrainz** until v0.6.21. **deadwax** is lowercase, like slskd: never sentence-case it. An
install that upgraded must not notice the rename: `default_db_path()` keeps using an old
`/config/jimbrainz.db` while no `deadwax.db` exists, and **never "tidy" an explicit
`DB_PATH=/config/jimbrainz.db` by renaming the file** - the one change that loses the data. The API
prefix is `/deadwax/`, with no alias for the old one. The whole story: `notes/history.md`.

### Why Lidarr was dropped

A particular pressing can't be asked of Lidarr: its search command carries no tracklist, edition or
year, so the plugin doing the Soulseek search grabs whatever a generic query returns. deadwax owns the
search and the matching. **It does not reliably auto-detect remasters** - folder names are typed by
strangers - so the promise is ranked candidates with visible reasoning, not magic; the README says so,
and keeps saying so. `notes/history.md`.

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
  navidrome_listing.py  which album folders Navidrome lists - "Not in Navidrome" in the queue: a pure
                   match and a cache asking getScanStatus and getAlbumList2 internally - see
                   "Navidrome required (2.0.0-player.46)".
  library.py       scans LIBRARY_PATH with mutagen, cached per folder on mtime - and that
                   cache is SAVED to SQLite (library_cache), so a restart starts warm and
                   the tab can draw a snapshot before touching the disk. Also finds cover
                   art, and reads one album's files in full for the track viewer.
  store.py         SQLite job store + transfer reconciliation helpers. Also the store index
                   (store_album): every album folder under an id that survives a rename - and,
                   per user, the app's preferences (user_prefs) and pins (pins), with
                   adopt_local() (an admin's first sign-in) - who is signed in (sessions), and
                   who asked for each download (job_requests - see "Downloads per person"); each
                   person's library (library_membership, user_credentials, library_flags,
                   library_seed, store_index_scanned - see "Personal libraries").
  pins.py          PURE. What a pin to the app's Home keys on (store:<store_album.id>, mb:<mbid>)
                   and the PUT's list - see "Pins, and a finished Home". Never Navidrome stars.
  playlists.py     PURE. Playlists (2.0.0-player.58), Navidrome's own: whose (mine by owner, case-
                   folded; listed; editable), the Playlist shape, hidden songs, duplicates, the
                   rearrangement rule, names cleaned - see notes/playlists.md.
  store_index.py   keeps the store index in step with every scan and writer, and the "already
                   have it" checks Find, /enqueue and the retries make - see "Already in the
                   store".
  musicbrainz_cache.py  MusicBrainz's answers kept on disk (2.0.0-player.54), under ResponseCache's
                   hour in memory: a SQLite file of its own, successes only, an old answer answered
                   at once and refreshed behind it - see "MusicBrainz answers kept on disk".
  saved_index.py   what those answers mention, indexed in the same file (FTS5) and searched under any
                   words - GET /search_musicbrainz/saved, Search's saved rows - see "Search what's
                   saved (2.0.0-player.56)".
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
                   Navidrome - for resample.py; and copy_plan(), the plan of a copy resampled, levelled or both.
  loudness.py      PURE but measure_file(). A song's loudness (BS.1770-4 / EBU R128, streamed, a histogram)
                   and the gain that levels it under its peak - the player's Normalization (2.0.0-player.62);
                   levels.py measures (on demand, at filing), keeps it in SQLite (`loudness`) and resolves
                   each copy's gain, applied by resample.py. See "Normalization (2.0.0-player.62)".
  flac_mp4.py      PURE. A FLAC file as an MP4 of the very same frames, no ffmpeg - what makes
                   Safari's seeks land. See "FLAC in an MP4, for Safari". And as a FRAGMENTED
                   MP4, `fmp4_layout()`, for the gapless stream - see "One stream for FLAC".
  flac_window.py   PURE. A stretch of a song as a FLAC file of its own, cut from deadwax's own
                   MP4s, frames renumbered from 0 - the turntable's sound. See "The turntable,
                   part two".
  flac_ranges.py   PURE. The same window read straight out of the FLAC on Navidrome, a byte
                   range at a time - steps that yield the reads they need. Byte for byte
                   flac_window's. See "Windows cut straight from the FLAC".
  player_cache.py  those MP4s made from Navidrome's file and kept on disk (PLAYER_CACHE_PATH or
                   temp space, PLAYER_CACHE_MB), served with byte ranges; the stream route's
                   `wrap=mp4`, and `wrap=fmp4` for the gapless stream. One URL stays one
                   container - see "After review (the cache)". And the turntable's windows,
                   cut from them (`answer_window()`, the scrub route) - or, with none kept of
                   the song as it is, straight from the FLAC by ranges (`_from_flac`).
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
  users.py         current_user(), the FastAPI dependency every router is checked by: the implicit
                   admin `local` while logins are off, the signed-in user (or 401) with them on;
                   is_admin (Navidrome's admin flag since 2.0.0-player.61, and break-glass);
                   permissions/can and require(permission), the 403 of a route a permission's
                   (an admin has them all). routes/me.py answers GET /deadwax/me.
  permissions.py   (2.0.0-player.61) what an admin ticked for an ordinary person, by category -
                   the `permissions` table held in memory, bound to the Navidrome account's id,
                   fail closed - see "Managing accounts - People, and Navidrome's admins as
                   deadwax's".
  people.py        PURE. People's rules: names, passwords, the guards (refusals) and each row.
  auth.py          logins (AUTH_MODE, 2.0.0-player.48): sign-in through Navidrome's getUser, the
                   session cookie and table, the re-check, break-glass (`deadwax` since .61), the
                   throttle - see "Logins and roles"; and (2.0.0-player.61) the role, getUser's
                   adminRole kept per session and per user (role, set_role), and ending a person's
                   sessions (end_user_sessions) - see "Managing accounts".
  library_ledger.py  personal libraries (2.0.0-player.51): the rules - what each way a download ends
                   gives its requesters, the backoff, the words - and the grants a filing writes. See
                   "Personal libraries".
  stars.py         each user's library starred AS THEM in Navidrome (found, starred, confirmed,
                   retried), their stars read back (two-way with Amperfy) - a lifespan worker with
                   logins on. See "Personal libraries".
  play_queue.py    PURE. Resume what was playing (2.0.0-player.64): the window kept, GET /queue's
                   answer from Navidrome's play queue and deadwax's record (store.py play_queue) -
                   see "Resume what was playing".
  api/             musicbrainz_endpoint.py, slskd_endpoint.py, coverart_endpoint.py,
                   artist_images_endpoint.py (Wikidata/Commons + TheAudioDB),
                   lrclib_endpoint.py (LRCLIB), navidrome_endpoint.py (Subsonic, for
                   the player - holds the login; client_for(request) asks as the signed-in
                   user with logins on, SHARED_ACCOUNT_USES lists what asks as the shared one),
                   navidrome_admin.py (2.0.0-player.61: Navidrome's NATIVE account API for People,
                   as the signed-in admin with their own JWT, a fixed list of six), app.py, json_etag.py (JSON with an ETag and the 304, shared by the library scan and
                   /album_index), same_origin.py (refuses
                   writes another website asks for - see "The 1.0.1 fixes")
  routes/          search_musicbrainz, download, monitor_slskd, interface_logs (the event log's
                   stream, and since 2.0.0-player.33 /recent: the last 500 page-bound lines
                   src/logger.py keeps, numbered - see "Server settings and the log in the
                   app"), library,
                   settings (editable since v0.5.1 - see "The settings tab"), navidrome
                   (the player's FIXED list of Subsonic calls - see "The phone player"; and
                   since 2.0.0-player.57 /shuffle and /shuffle/{token}, the Library's Shuffle:
                   every song of your library once, in an order deadwax makes, paged - see
                   "Up Next, shuffle and repeat"; and since 2.0.0-player.58 the six /playlists
                   routes, as the asker, the owner checked before any write, writes as form
                   POSTs - see notes/playlists.md; and since 2.0.0-player.59 /album_index, the
                   Library's whole album list of a scope in one answer with an ETag - see
                   notes/app-library.md),
                   me, auth (sign-in and sign-out, the two routes needing no session),
                   store_album (the app's id bridge - see "Artists, and the two
                   libraries joined"), pins (/deadwax/me/pins - see "Pins, and a finished Home"),
                   my_library (/deadwax/me/library) and held (/deadwax/library/held, Look after
                   the library's) - see "Personal libraries"; people (/deadwax/people, People: a
                   Navidrome admin's, unlocked with their own password - see "Managing accounts");
                   own_password (/deadwax/me/password, You's Change password: yours, changed in
                   Navidrome as you - see "Changing your own password");
                   library's /queue/summary is the app's Needs-a-look count, from the saved
                   scan alone - see "Needs a look"
interface/         the app's pages: player/ (the app, its stylesheets, manifest and icons),
                   player/lab/ (the bench), styles/theme.css and its fonts; `/` (and
                   /index.html) redirects to /player/ (307) - see "The main page retired".
  styles/theme.css THE TOKEN LAYER - every colour, size, space, radius, shadow, duration and
                   easing in the app, linked first by each page; section 10's --dw-* are the
                   app's, sections 1-9 what they alias. Raw values in a stylesheet or a
                   component are a bug; tests/test_app_css.py keeps a token nothing reads out.
  player/          the app's page at /player/, manifest, icons, and its stylesheets: player.css
                   (the player; mechanics its own, look on theme.css section 10) and app.css (the
                   tab bar, Home, Requests, You) - see "The one app" - and signin.css (the sign-in
                   and Sign out, linked only with logins on). player/lab/ is the turntable's
                   test bench's page and its own lab.css.
  dist/            BUILT from ui/, gitignored. Not present in a fresh checkout.
ui/                Preact + Vite + TypeScript: the app (src/player/main.tsx -> src/app/App.tsx)
                   and the bench. ui/src/player/ is the player;
                   player/streamSource.ts is its one-stream gapless engine, with the pure
                   lib/streamPlan.ts and lib/fmp4.ts - see "One stream for FLAC". The level a queued song
                   is played at rides on its entry: the pure lib/loudness.ts (the rule, the address's
                   `&level=`), player/levelling.ts queued() at every play's tap, app/NormalizationChoice.tsx
                   the setting - see "Normalization (2.0.0-player.62)". Since
                   2.0.0-player.9 its main.tsx renders ui/src/app/App.tsx, the ONE app: five tabs
                   with the player inside them - see "The one app". player/deck.ts is the
                   turntable's platter and its own sound (lib/platter.ts, lib/deckVoice.ts, and
                   since 2.0.0-player.24 lib/deckClock.ts, its one time base; the voice ends
                   in a peak limiter since 2.0.0-player.35) - see "The turntable, part two",
                   "The record's sound follows the hand" and "The record's sound never clips".
                   lib/errorWords.ts says every error in a listener's words (the pure classes and
                   sentences), app/ErrorNote.tsx and app/sayError.ts draw them - see "Errors and
                   connections in a listener's words".
                   app/NeedsALook.tsx is the review queue (both frames), its rules the pure
                   lib/needsLook.ts and its count app/useQueueSummary.ts - see "Needs a look".
                   app/ArtistPanel.tsx is the artist page's managing on both frames (Artist
                   images…, Move albums to …, Which artist is this?), its rules and the page's
                   In your library and full facts lib/artistManage.ts - see "The artist page, as
                   the main page had it". components/ holds the editors the Edit panel hosts
                   (MetadataEditor, TrackTagEditor, DeleteAlbumDialog, ArtViewer, LibraryParts'
                   Get buttons) and SettingsView.tsx, the server settings' parts.
                   app/ServerSettings.tsx (drawn from components/SettingsView.tsx's own exported
                   parts) and app/EventLog.tsx (lib/eventLog.ts) are the server's settings and the
                   event log (both frames) - see "Server settings and the log in the app".
                   app/Search.tsx is one list as Apple Music shows it (2.0.0-player.55): Top results,
                   then Artists, Albums, Songs - yours first in each - its rules the pure
                   lib/searchList.ts (the rank, the dedupe, the moments that never move anything),
                   its rows app/SearchRows.tsx (stateless functions, no player action), its kept
                   MusicBrainz answers app/searchAnswers.ts - see "Search like Apple Music". Its
                   Songs section groups a recording search's takes into songs with lib/songs.ts -
                   see "Song search (2.0.0-player.53)".
                   lib/upNext.ts is PURE - Up Next's account of the queue beside the engine's
                   { tracks, index }: Play Next/Last, moves, Shuffle, Repeat unrolled into it;
                   app/UpNext.tsx draws it (both frames), app/QueueMenu.tsx is a song's or an
                   album's Play Next and Play Last, app/ShuffleSongs.tsx the Library's Shuffle and
                   app/useShuffleFeed.ts its pages - see "Up Next, shuffle and repeat".
                   app/LibraryCare.tsx is Rescan and the bulk runs (both frames; its runs
                   app/useLibraryCare.ts; which albums each takes lib/bulkTargets.ts) - see
                   "Looking after the library".
                   app/useMyLibrary.ts is your library as the app keeps it (logins on), drawn by
                   app/YourLibrary.tsx (You), Home's New shelf and the Library's New marks;
                   app/HeldByNobody.tsx is Library care's; the words lib/myLibrary.ts - see
                   "Personal libraries".
                   app/useResume.ts puts the person's play queue back paused as the app opens and
                   saves it as it plays (the engine's restoreQueue its one action), its rules the
                   pure lib/resume.ts - see "Resume what was playing".
                   People and permissions (2.0.0-player.61, notes/logins.md "Managing accounts"):
                   app/People.tsx (with UnlockPeople, AddPerson, ResetPassword, RemovePerson and
                   usePeople), its rules lib/people.ts; what the app shows by permission
                   lib/permissions.ts, read through app/access.ts's useAccess().
                   Playlists (2.0.0-player.58, notes/playlists.md): app/PlaylistsPage.tsx (the
                   list), app/PlaylistPage.tsx (one - plays in the tap, Edit, Delete),
                   app/PlaylistPicker.tsx (Add to a playlist, from the ••• menus and the player
                   bar), app/usePlaylists.ts (the one list, and pages' kept answers), their rules
                   the pure lib/playlists.ts.
                   The Library (2.0.0-player.59, notes/app-library.md): app/LibraryHome.tsx (a
                   phone's root), app/LibrarySection.tsx (a section - a phone's page, a desktop's
                   inline view) on app/Shelf.tsx (blocks, tiles made near the view) and
                   app/ShelfIndex.tsx (the A-Z index), its rules the pure lib/shelves.ts (the
                   sorts, headers, index, Find, blocks); app/albumIndex.ts is the one album list
                   per scope (yours, the store's), app/useYourAlbums.ts its `yours` face.
                   ui/src/lab/ is the turntable's test bench at /player/lab/, a third page built
                   in a pass of its own: the real Turntable and deck over signals it makes, set
                   beside an ideal turntable - see notes/turntable-bench.md.
tests/             3787 tests, all Python, all fixture-driven (+ ui/test/*.sim.cjs scripts)
```

API routes are prefixed **`/deadwax/`** (renamed from `/lidbrainz/`, then from `/jimbrainz/`
in v0.6.21 - see "The name").

### The flow

MusicBrainz search → pick a release → slskd search → rank candidates against that release's
real tracklist → enqueue → poller watches transfers → organizer tags and files the result.

## Where the detail is: `notes/`

This file is loaded into every session and every helper agent, so it stays short: what the project
is, the rules, and the map. Everything else - each decision's full reasoning, each feature's
write-up, the measurements and the reviews - is in `notes/`, one file per area, moved there verbatim
on 2026-10-07 (when this file had grown to 900 KB). **Before changing an area, read its notes file.**
Sections refer to each other by title, and code comments that say "see X in CLAUDE.md" mean the
section of that title in notes/: `grep -rn "### X" notes/` finds it.

| area | notes |
| --- | --- |
| every settled decision, in full | `notes/decisions.md` |
| the main page's look: CSS, panels that move, phones, the design system (the retired main page's - history) | `notes/interface.md` |
| search, the releases grid, discographies, "in your library" marks, newest-answer guards | `notes/search.md` |
| the candidates panel, quality filters, next peer / same peer, peers' speeds, the downloads panel | `notes/downloads.md` |
| the 1.0.1 fixes: the same-origin guard, held releases, a card's Find, the two-step apply | `notes/fixes-1.0.md` |
| the fixes before 2.0.0 (.65): secrets over two saves, symlinks, break-glass, shuffle memory, stop, the start-up scan, proxies, re-starring, warming | `notes/fixes-2.0.md` |
| the library explorer and saved scan, discs and disc titles, the editors, artist pages, CD art, lyrics, folder template | `notes/library.md` |
| artist credits, renamed artists, searching Soulseek under every name | `notes/names.md` |
| the main page's settings tab (the retired main page's - history) | `notes/settings-tab.md` |
| the frontend migration: its plan, the typed API surface, the port's history | `notes/frontend-migration.md` |
| the phone player, the Navidrome relay, the scan wait | `notes/player.md` |
| gapless and seeking | `notes/player-gapless-seeking.md` |
| FLAC in an MP4 for Safari, the muxer, the player cache | `notes/player-flac-mp4.md` |
| one stream for FLAC, hi-res resampled to 48 kHz | `notes/player-stream-hires.md` |
| normalization: the level rule, the measurement, the levelled copy | `notes/player-normalization.md` |
| the store index and the "already have it" checks | `notes/store-index.md` |
| the one app: routes, the gesture rule, the restyle, Now Playing, Info, resume what was playing, errors in a listener's words | `notes/app.md` |
| Requests, Search, the album you don't have, Sources and Get, song search, search like Apple Music | `notes/app-requests-search-get.md` |
| artists, the id bridge, pins, Home | `notes/app-artists-pins.md` |
| the desktop frame, the Edit panel, Needs a look (and Not in Navidrome), server settings and the log, Library care - and all of them on a phone | `notes/app-desktop.md` |
| logins and roles: signing in through Navidrome, sessions, admins, break-glass, the sign-in screen; downloads per person; personal libraries; the player as you (Library and Browse, Add and Remove); People, Navidrome's admins as deadwax's, permissions; changing your own password | `notes/logins.md` |
| playlists: Navidrome's own, as you - whose, the routes and the replace, the picker, a playlist's page and its Edit | `notes/playlists.md` |
| the app's Library: its root, sections, sorts, groups, the index, Find, the album index route, the shelf | `notes/app-library.md` |
| the turntable: its look, momentum, the deck, the first fix (.11, .14, .16) | `notes/turntable.md` |
| the turntable's sound following the hand (.24) | `notes/turntable-sound.md` |
| the turntable's sound since: warble, echo, kernel, first turn, clock, recorder, limiter (.27-.35), less delay (.40) | `notes/turntable-fixes.md` |
| the turntable's test bench at /player/lab/ (.36): signals, motions, A/B/C, Check this device | `notes/turntable-bench.md` |
| the desktop visualizer, the Mandala, the music's feel | `notes/visualizer.md` |
| windows cut straight from the FLAC | `notes/flac-windows.md` |
| backend and data gotchas (slskd, MusicBrainz, compose, scans) | `notes/backend-gotchas.md` |
| tooling and environment gotchas | `notes/tooling.md` |
| performance, profiled | `notes/performance.md` |
| capturing screenshots | `notes/screenshots.md` |
| the sims, one line each | `notes/sims.md` |
| the name, why Lidarr was dropped, the old Next up list | `notes/history.md` |

**A change's write-up goes into its area's notes file** (a new file for a new area, added to the
table above), never here. Add to this file only a rule that holds everywhere.

## Standing rules

- **Audio fidelity first** (James): no processing may cost sound quality; keep the original where
  realistic. Nothing the app plays changes unless a change asks for it.
- **The player** (notes/app.md and the player notes): `usePlayer()` is called once, in
  `app/App.tsx`; playback actions only from the files on `ui/test/app-rules.sim.cjs`'s allowlist, in
  the tap with nothing awaited first (iOS unlocks audio per element, from a gesture); one audio
  element (two with Gapless); **never `createMediaElementSource`** (it breaks locked playback on an
  iPhone). **The engine files have no diff unless a change says so**: `ui/src/player/usePlayer.ts`,
  `ui/src/player/streamSource.ts`, `ui/src/lib/{playQueue,gapless,scrub,streamWrap,streamPlan,fmp4}.ts`,
  `ui/test/player.sim.cjs`.
- **Plain http**: James opens deadwax at a plain `http://` address on his network (WireGuard on the
  phone). Nothing may need a secure context without a fallback (AudioWorklet, crypto.subtle,
  randomUUID, clipboard, service workers). localhost IS a secure context, so test from a non-local
  name too: Chromium with `--host-resolver-rules="MAP deadwax.test 127.0.0.1"`.
- **Only the newest answer draws**: every fetch-then-draw goes through `latestOnly()` (`lib/latest.ts`).
- **Errors in a listener's words**: a page a listener reads (the files `ui/test/errors.sim.cjs` scans) says an
  error through `lib/errorWords.ts` (`errorNote`, `sayError`), never its own text; its own words only for whoever
  runs deadwax (`access.ts seesDetail`). The managing pages (People, Server settings, the log, Needs a look,
  Library care, the editors) still show raw words - UX batch 5's. A server refusal that needs a setting named
  answers `auth.Explained` (`detail` for anyone, `why` for them).
- **Tokens only in CSS** (`interface/styles/theme.css`; section 10's `--dw-*` for the app); a raw value
  in a rule is a bug. `app-desktop.css` rules live only inside its desktop media queries.
- **Links out of the app open beside it** (`target="_blank" rel="noopener"`): following one in the page
  unloads the player.
- **Every route is decided** - public, a user's or one permission's (`tests/test_logins.py` ROUTES): a router
  is included with `current_user` or `require(permission)` (src/users.py), never middleware.
- **The Navidrome routes are a fixed list** (`test_there_is_no_general_proxy`); middleware is plain
  ASGI only, never `@app.middleware("http")` (it hides disconnects).
- **pydantic drops undeclared fields without a word**: a field the browser sends must be declared on
  the request model (it has bitten six times).
- **Every writer to the library is plan/execute**, and every apply route recomputes the plan rather
  than taking one back over the wire.
- Never search the whole disk; never touch James's server (bearded-dragon) or its compose.

## Decisions that should not be re-opened

One line each; the reasoning, and what went wrong before each was made, is in `notes/decisions.md`.

- **Matching is pure** (`matching.py` does no I/O).
- **The organizer is plan/execute**; dry run runs the identical plan and declines to act.
- **The release is stored denormalized** in the job row: filing must not depend on MusicBrainz.
- **Progress is never persisted**: derived from slskd on read, divided by the files wanted.
- **`ORGANIZE_MODE` defaults to `dry_run`.**
- **Edition is a weighted signal, never a filter.**
- **The folder is named after the album's year** (the release group's first release, `original_year`),
  not the pressing's; the `date` tag keeps the pressing's.
- **The search type filter narrows the QUERY, not the results**; the query is bracketed before a
  filter is ANDed on, and the active filter is always shown.
- **The metadata editor searches with a fielded query**, falling back to free text.
- **An album's folder carries its edition; identity lives in the tags**; an untagged folder is never
  treated as a different release.
- **Deleting an album carries every guard** (inside LIBRARY_PATH, never the root, audio directly in
  the folder) and a real dialog: there is no undo.
- **Getting a cover never requires applying a release** and chooses nothing; replacing art lives in
  the editor; bulk runs are driven from the client, one album at a time.
- **Eight writers to the filesystem**, plan/execute, previews and writes sharing one tag computation.
- **MusicBrainz answers are cached, successes only - in memory and on disk since 2.0.0-player.54**; ask
  for the least that answers, with every saving flag defaulting to the expensive-but-correct way (never
  make trackless the default).
- **The metadata queue stores only what you ignored**; what's wrong is derived per request; ignores
  are per issue; rows are keyed on the album's path.
- **The tab badge and the queue never count different things.**
- **Review rows of gone albums are pruned only after a scan that found albums**; deadwax's own delete
  forgets its row at once.
- **The new-import prompt is recorded at import time**, a partly filed download included.
- **A move-organize clears the slskd folder, but never past audio.**
- **An artist folder a re-file empties is removed with `rmdir`** only.
- **Cancelling removes partials only with `SLSKD_INCOMPLETE_PATH` set**, and more strictly than
  `find_local_file` guesses; deadwax also clears slskd's empty incomplete folders (rmdir, older than
  10 minutes), and asks slskd a second time to drop a cancelled job's settled transfers.
- **A job a stop caught mid-filing is settled when the poller starts**, never filed again unattended.
- **The image's HEALTHCHECK judges deadwax alone** (slskd or MusicBrainz down don't count).
- **Errors degrade rather than crash.**

## Gotchas to know before anything

The rest are in `notes/backend-gotchas.md`, `notes/tooling.md` and `notes/interface.md`.

- **The agent's file tools write a `\u`-style escape as the RAW character**;
  `tests/test_source_bytes.py` fails on raw control bytes. Write such escapes with a byte-level replace.
- **The sims need a writable `TMPDIR`** (`TMPDIR=<scratch> node ui/test/<name>.sim.cjs`); pytest must
  NOT get that TMPDIR (`test_a_setgid_bit_is_no_bar` fails under a folder whose group you're not in).
- **`hidden` reading true is not evidence an element is hidden** when CSS sets `display`: measure it.
- `overflow-y: auto` promotes `overflow-x` too; a flex item needs `min-width: 0` for its ellipsis;
  `getBoundingClientRect()` is the transformed box, `offsetWidth` isn't.
- **Bump `SCAN_FORMAT`** whenever `read_album_dir()`'s output changes shape; a retag doesn't move a
  folder's mtime, so writers call `forget_cached_album()`.
- **slskd's 409 means it isn't logged in to Soulseek**; read slskd's error BODIES, not the status line.
- **A hidden browser pane freezes transitions and lazy images**: measure after a paint, never trust a
  screenshot over computed styles.
- **MusicBrainz and the Cover Art Archive go away for minutes at a time**: retry before concluding.

## Frontend: done

**Preact + Vite + TypeScript, in `ui/`.** The vanilla main page retired in 2.0.0-player.66 (`/` answers
a 307 to `/player/`): the app is the only page, beside the turntable's bench. The plan, the typed API
surface and the port's history are in `notes/frontend-migration.md`. The main page's editors live on
in the app's Edit panel, styled by their ids and classes in app-desktop.css and in app.css's "looking
after deadwax from a phone" section, so a change to one is checked on the desktop's panel and the
phone's sheet.

## Conventions

- **Write-ups live in `notes/`** (see "Where the detail is"): a change describes itself in its
  area's notes file, and this file stays short - add here only a rule that holds everywhere.
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
  library, the phone player since 1.0.3, sharing deadwax since 2.0.0-player.60, matching, troubleshooting), written for someone seeing
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
.venv/bin/python -m pytest tests/ -q  # 3787 tests (the audio ones skip without numpy, soxr and soundfile)
```

Frontend, from `ui/`. **Needs Node `^20.19.0 || >=22.12.0`** — see `notes/tooling.md`:

```bash
npm install
npm run build      # tsc --noEmit && vite build && vite build --mode lab (the test bench's pass) -> interface/dist/, required to see the app
npm run typecheck  # tsc alone; runs on older Node when the build won't
```

```bash

The sims are scripts, one per area, each run with Node and a writable `TMPDIR`; CI runs every one on
its own. Run them all with
`for f in ui/test/*.sim.cjs; do TMPDIR=<scratch> node "$f" >/dev/null || echo "FAILED $f"; done`.
What each one holds: `notes/sims.md`.
```

There is no harness: the real page is `/player/`, served by FastAPI on 8080, and it only picks up
frontend changes after `npm run build`.

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

All 3787 tests are fixture-driven, and **nothing in the suite has ever talked to a real
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
  first places to look when the player or the scan wait misbehaves - and what `getUser` and its
  failure limits really do, when a sign-in does (notes/logins.md).

A green suite here means the logic is sound, not that it works against real infrastructure.

## Next up (open)

1. **Real infrastructure**: search, enqueue, completion and filing have run end to end against a real
   slskd; still unwatched live: the derived download speed, queue position, and cancel.
2. **Sources against real Soulseek data** (seen only against fakes).
3. **The phone player on James's iPhone, locked**: the "NOT verified" lists in the player and
   turntable notes are what the phone answers.

**Deliberately not built**: embedding art into the audio; undo, for a retag or a delete (the preview
and the confirmation are the safety nets - keep both honest); bulk apply in the metadata queue (there
is no undo, and a bulk action is where nobody reads the preview). The full lists, with what was built
from them since: `notes/history.md`.
