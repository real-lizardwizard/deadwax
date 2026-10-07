# Capturing screenshots

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

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
