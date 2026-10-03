# Frontend migration: vanilla → Preact + Vite + TypeScript

Everything a fresh session needs to start. The decision is settled (see CLAUDE.md); this is
the how.

## Status

| | |
| --- | --- |
| Toolchain (`ui/`) | **done** — Vite 8, Preact 10, TS strict. `npm run typecheck` is clean. |
| Typed API layer | **done** — every endpoint in the table below, in `ui/src/api/`. |
| localStorage compatibility | **done** for what the ported panels use — `ui/src/state/persisted.ts`. The release-column and log-open keys are still main.js's alone; their Preact readers were written ahead of the ports and removed unused in v0.9.19, so each port writes its own (see the notes below). |
| Downloads panel | **ported**, verified against a running backend with seeded jobs. |
| Tab shell | **done** — `Tabs.tsx`. Search/Library, built to take Settings as a third. |
| Metadata editor | **done** — `MetadataEditor.tsx`, an overlay from the library reusing the candidates-window shape. Pick a release *or* type the fields directly; the release the album is already tagged with sorts first and is badged `current`. |
| Library window | **done** — `LibraryView.tsx` + `src/library.py`. An Explorer-style tree (`LibraryTree.tsx`, `lib/libraryTree.ts`: artist → album → edition → track) beside a details pane (`LibraryDetails.tsx`) with a user-chosen set of track fields - reorderable and resizable by their headers since v0.6.9 (`lib/trackFields.ts`). Replaced the one-row-per-album list in v0.6.5. |
| Candidates panel | **done** (v0.9.10) — `CandidatesPanel.tsx` + `lib/candidates.ts`. Opened by the vanilla Find buttons through the bridge (`openCandidates`); downloads go to the downloads panel through `lib/downloadRequests.ts`. Since 2.0.0-player.15 what those Find buttons send is built by the bundle too: `lib/releasePayload.ts`, the ONE download payload builder, on the bridge as `buildDownloadRelease` - main.js's `buildExpectedFromRelease` and `buildExpectedFromReleaseGroup` are deleted, and `ui/test/payload.sim.cjs` holds the builder to bodies captured from the old Find buttons before the move (`tests/fixtures/payloads/find-buttons.json`). |
| Tag editor | **done** — `TrackTagEditor.tsx` (v0.6.9), born in Preact rather than ported. Edits tags by hand on one track or every ticked one; only the fields you change are sent (`lib/tagEdit.ts`), and the preview comes from the same planner the write recomputes (`src/track_tags.py`). |
| The one app (`/player/`) | **begun** (2.0.0-player.9) — `ui/src/app/`: `App.tsx` (the root, and the one `usePlayer()` call), the tab bar (Home, Library, Search, Requests, You), Home's "Recently added", You (Maximum quality, the connection checks, the version from `/deadwax/me`), per-tab stacks in the hash (`lib/appRoutes.ts`, driven against the real history by `lib/appHistory.ts`), and the player's screens inside them. Since 2.0.0-player.10, Now Playing as its board draws it, with a ••• menu (`ActionMenu.tsx`) and Info over it (`InfoSheet.tsx`: About from `lib/aboutRows.ts`, Debug from `lib/debugRows.ts`), each a sheet by `useSheet.ts`, and Gapless a checkbox in You (`GaplessChoice.tsx`). Since 2.0.0-player.11, Now Playing's second look, the turntable (`player/Turntable.tsx`, its rules in `lib/turntable.ts`), chosen by a button on it and by You's "Now Playing opens as" (`LookChoice.tsx`); since 2.0.0-player.14 its momentum and its own sound (`player/deck.ts` - the platter, the audio context and the window - over the pure `lib/platter.ts` and `lib/deckVoice.ts`, the AudioWorklet made from the latter's own source - or, since 2.0.0-player.16, on a page that isn't HTTPS and so has no AudioWorklet, a ScriptProcessorNode running the same functions on the main thread), with You's "Pause winds the record down" (`WindDownChoice.tsx`). Since 2.0.0-player.12, the Requests tab (`Requests.tsx`, its cards in `JobCard.tsx`, its grouping and words in `lib/requestsView.ts`) and Home's Arriving (`Arriving.tsx`), both on the ONE `useDownloadJobs` App calls - the hook the main page's downloads panel uses, unchanged - with a count on the tab. Since 2.0.0-player.13, the Search tab (`Search.tsx`: Navidrome's search3, then MusicBrainz, the box read by `lib/searchQuery.ts`, the rows by `lib/searchResults.ts`) and the album you don't have (`ReleaseGroupPage.tsx` with `PressingPicker.tsx`, its parts in `lib/pressings.ts`), over TypeScript ports of `tracklistDiff.mjs` and `owned.mjs` (`lib/tracklistDiff.ts`, `lib/owned.ts`) that the sims hold to the `.mjs` answers on shared fixtures (`tests/fixtures/pressings/`). Since 2.0.0-player.15, Get: "Get the album" on that page and a Get chip on Search's rows open the Sources sheet (`Sources.tsx`, its cards `SourceCard.tsx`, what is already here of a pressing `StoreState.tsx`), searching through `hooks/useCandidateSearch.ts` - the candidates panel's orchestration, repeated so the old panel stays untouched - with the payload from `lib/releasePayload.ts`; and You's Getting albums (`GettingChoices.tsx`, kept per user on the server through `useGetSettings.ts`, `lib/getSettings.ts`). Since 2.0.0-player.17, artists and the id bridge: the artist page (`ArtistPage.tsx`, its rows and who-is-who in `lib/artistPage.ts`), the Library's Albums / Artists / Songs (`player/Library.tsx`, `LibraryViews.tsx`, paging in `usePaged.ts`), the album page's artist link and "Also" chips and Info > About filled in (`useInfoDetails.ts`, `lib/idBridge.ts`), and Requests' Done rows opening and playing their album - all joined through `GET /store/album` (`api/store.ts`). It grows in place at `/player/` until it covers the main page; see "The one app" in CLAUDE.md. |
| Multi-stage Dockerfile | **done** — `ui` stage builds into `interface/dist`. |
| Cache-header fix | **done** — hashed chunks immutable, entry bundle revalidates. |
| Everything else | untouched. Vanilla still owns it. |

**Two panes, one attribute.** `Tabs` is presentational; `renderShell()` in `main.tsx` writes
`data-tab` on `#main-container` and CSS decides which pane shows. Doing that write from a
`useEffect` inside `Tabs` looked cleaner and was *wrong* — it didn't fire when the tab changed
from a click originating in the library tree, so the button highlighted and the panes didn't
move. Cross-tree DOM writes go in the shell, synchronously.

**The bridge has three entries now**, the new one being `runSearch` — the library's clickable
artist/album names hand off to the vanilla search rather than reimplementing it. It retires
when the search view is ported.

**Needs Node `^20.19.0 || >=22.12.0`.** On older Node, `npm install` warns but silently drops
rolldown's native binary and the build dies with "Cannot find module
'./rolldown-binding.*.node'". `npm run typecheck` still works there.

## Ground rules

1. **Incremental, not big-bang.** There are zero frontend tests. A full rewrite has no safety
   net, so port panel by panel and keep the app working at every commit.
2. ~~**The library window is the first workload.**~~ **Superseded.** The Downloads panel went
   first instead: the library window needs a backend endpoint that doesn't exist yet, so it
   would have proved the setup against invented data, while Downloads exercises polling, live
   updates, keyed lists and mutations against a backend that already works. The reasoning
   still holds for anything genuinely new — build it in Preact rather than extending vanilla.
3. **Do not carry the two performance bugs across** (details below). They're the actual cause
   of the "lag" complaint, and they're just as reproducible in Preact.
4. **The CSS stays where it is.** `interface/styles/main.css` (now ~3,500 lines) owns the CRT
   look for BOTH halves — no component imports CSS, and ported markup reuses the existing
   class names verbatim. Port markup first, restyle later as a separate deliberate pass;
   changing both at once means you can't tell which broke it.

## Toolchain setup — as built

```
ui/
  index.html             # DEV HARNESS ONLY - not built, not served. See below.
  src/
    main.tsx             # mount table: element id -> component
    player/              # the phone player at /player/ - its own entry, main.tsx (1.0.3); the engine and its screens
    app/                 # the one app it grows into (2.0.0-player.9): App, the tabs, Home, Requests, You, the sheets over Now Playing - main.tsx renders App
    bridge.ts            # window.deadwax - the seam with the vanilla app
    api/                 # types.ts + one wrapper module per backend module
    components/
    hooks/               # useDownloadJobs - polling, cadence, mutations
    lib/                 # format, jobs vocabulary, speed sampling
    state/               # persisted.ts - the three localStorage keys
  tsconfig.json          # strict + noUncheckedIndexedAccess + exactOptionalPropertyTypes
  vite.config.ts
  package.json
interface/               # existing vanilla app — stays until fully replaced
  player/                # the player's hand-written page, manifest, icons and stylesheet
  dist/                  # build output, gitignored
```

**The build inputs are two TypeScript entries, not `index.html`.** While the port is
incremental the page users get is still the hand-written `interface/index.html`, which loads the
bundle as one extra module script. So the build emits JS, not a page. Since 1.0.3 there are two
entries, one per hand-written page:

| entry | source | loaded by |
| --- | --- | --- |
| `deadwax-ui` | `src/main.tsx` | `interface/index.html`, the main page (as `/dist/deadwax-ui.js`) |
| `deadwax-player` | `src/player/main.tsx`, which renders `src/app/App.tsx` | `interface/player/index.html`, the app at `/player/` (as `/dist/deadwax-player.js`) |

Both entry filenames are pinned unhashed (`entryFileNames: '[name].js'`) because a static HTML
file has to name them. Code they share (Preact, the HTTP helpers) goes into a hashed chunk under
`dist/assets/` that both import, and split chunks keep their hashes.

When the migration finishes and Vite owns the main page, let it build `index.html` normally, but
**keep the player's entry** (or give the player its own HTML input): deleting
`rollupOptions.input` outright would drop the player, and `/player/` would load a script that
isn't there - a blank page with nothing on screen to say why.

Two consequences worth knowing:

- **An unhashed entry is a mutable URL**, so `src/api/app.py` must send `no-cache` for it.
  That's already wired; don't undo it.
- **No CSS is imported by any component**, deliberately — the existing `main.css` still owns
  everything on the main page, and the app at `/player/` has hand-written stylesheets of its own
  (`interface/player/player.css` and `app.css`, on `theme.css` section 10's `--dw-*` tokens).
  `tests/test_pages.py` holds each page's bundle to a vite entry and its stylesheets to files that
  are served. A JS-entry build does not auto-inject an emitted stylesheet, so the first
  component that imports CSS has to solve that. Don't discover it by accident.

`ui/index.html` is a harness for building one component in isolation with HMR. It proxies
`/deadwax`, `/styles` and `/assets` to `127.0.0.1:8080`, so start the backend first, and
remember it is *not* the real page — only `npm run build` updates that.

### Dockerfile

Becomes multi-stage. Current build is `pip install` only, so this is the real cost of the
decision:

```dockerfile
FROM node:22-alpine AS ui
WORKDIR /ui
COPY ui/package*.json ./
RUN npm ci
COPY ui/ ./
RUN npm run build          # emits into interface/dist

FROM python:3.14-slim
# ... existing gosu + pip layers unchanged ...
COPY --from=ui /interface/dist ./interface/dist
```

**Done, with one deviation:** the second stage copies `--from=ui` *after* `COPY interface/`,
so a stale `interface/dist` left by a local build is overwritten rather than shipped.

`src/api/app.py` was updated at the same time, as this section warned it must be:
`/dist/assets/` (hashed, content-addressed) is served `immutable, max-age=31536000`, while
`/dist/` (the unhashed entry bundles) joins `/scripts/`, `/styles/`, `/assets/` on `no-cache`.
Leaving the middleware alone would have reintroduced "I upgraded and nothing changed" for
precisely the ported half of the interface. Since 1.0.3 `/player/` is on `no-cache` too - the
player's page, manifest and icons - since an app on a phone's home screen is exactly the tab
that never gets reloaded.

## API surface to type — done

All of this is typed in `ui/src/api/types.ts` with per-module wrappers beside it. Kept here as
the reference. All prefixed `/deadwax/`.

| endpoint | method | notes |
| --- | --- | --- |
| `search_musicbrainz/fully_search?query=&limit=` | GET | returns `{release-groups, best-match-releases}`. **503 = MusicBrainz unreachable**, distinct from empty results — surface it as such. |
| `search_musicbrainz/releases?release_group_mbid=` | GET | `{id, releases, problem}`. `problem` (since 2.0.0-player.13) says MusicBrainz failed part way: the list is short, not the album's pressings. |
| `search_musicbrainz/release_group?release_group_mbid=` | GET | `{id, releases, problem}`, every pressing WITH its tracklist and its `release-group` (2.0.0-player.13, the app's album-you-don't-have page). A malformed id is a 422 - the page checks the id first (`groupMbid`). |
| `library/owned` | GET | `{albums[], problem}`, each album reduced to which album and edition it is - and, since 2.0.0-player.17, who it is by (`albumartist_mbids`: one id, a collaboration's several, or none). ETag'd; the app reads it through `owned()` in `ui/src/api/library.ts` and `lib/owned.ts` (the port of `owned.mjs`). |
| `navidrome/search?q=&artistCount=&albumCount=&songCount=&…Offset=` | GET | the app's Search, library half (2.0.0-player.13): Navidrome's search3 as `{artists, albums, songs}`; counts capped at 50/50/500. An empty `q` lists everything, a page at a time - the app's Library > Songs (2.0.0-player.17). |
| `navidrome/artists`, `navidrome/artists/{id}`, `navidrome/songs/{id}` | GET | the app's Library > Artists, its artist page, and Info's play count and writers (2.0.0-player.17): getArtists flattened to `{artists}`, getArtist and getSong as Navidrome sent them. An id past 256 characters is a 422. |
| `store/album?release_mbid=` or `?navidrome_id=` | GET | the id bridge (2.0.0-player.17): `{release_mbid, release_group_mbid, navidrome_id, present[], other_pressings[]}` - the store's live folders of the release, the album's other pressings, and Navidrome's album id for each (looked up by deadwax itself; null when Navidrome hasn't got it). Exactly one of the two, or a 422. Read through `ui/src/api/store.ts`. |
| `search_musicbrainz/artist?mbid=` | GET | an artist's light facts (2.0.0-player.17): `artist_facts` less its links and members. 503 when MusicBrainz can't be reached; a malformed id is a 422. |
| `search_musicbrainz/discography?artist_mbid=&types=album&studio_only=` | GET | every release group credited to the artist - a browse, complete unless `truncated`; `problem` when it broke off. The app's artist page reads its albums (`getDiscography`). |
| `search_musicbrainz/ping` | GET | `{status, code}` |
| `monitor_slskd/ping` | GET | `{status, code}` |
| `download/find_candidates` | POST | body: `{artist, album, year, release_mbid, edition_tags, tracks[], format_preference, query_override}` → `{query, response_count, candidates[]}` |
| `download/enqueue` | POST | body: `{username, files[], directory, release}` → `{status, queued, job_id}` |
| `download/jobs` | GET | `{jobs[], tracking_enabled}`. `files_failed` is only present when slskd matched transfers — optional, not always-zero. |
| `download/jobs/{id}/cancel` | POST | |
| `download/jobs/clear` | POST | |
| `library/albums` | GET | `{albums[], artists[], library_path, problem, ...}`. `problem` is a setup message (unset/missing LIBRARY_PATH), NOT an error — render it, don't throw. Since v0.9.20 tracks arrive compact (`track_defaults`) and the per-scan fields as `X-Scan-*` headers, with an ETag — read it through `loadScan()` or `listAlbums()` in `ui/src/api/library.ts`, which undo both. |
| `library/rescan` | POST | same shape; drops the server's per-folder mtime cache |
| `library/retag/preview` | POST | `{album_path, release, fetch_art}` → a plan. Writes nothing and fetches nothing, deliberately a separate endpoint from apply rather than a flag. |
| `library/retag/apply` | POST | same body; recomputes the plan server-side and executes it. Returns `{plan, results}`. |
| `library/deletion_summary?album=` | GET | what deleting would remove, read live. Touches nothing. |
| `library/delete` | POST | `{album_path}`. Permanent, no undo — guards in `library.py::delete_album`. |
| `library/art?album=<relative path>` | GET | image bytes or 404. `album` is the path the scan reports. Only endpoint that reads the filesystem from user input — see the containment check. |
| `interface_logs/interface_logs` | GET | **SSE stream**, not fetch. **Correction:** the frame is `{event_time, event_type, event_content, src?}` — this table was written from the endpoint, but `SSEHandler.emit()` in `src/logger.py` also sends a pre-formatted `event_time` and only attaches `src` when the record carried one. Frames without a `src` are real and must render. |

Canonical shapes are in `src/routes/download.py` (pydantic models) and
`src/matching.py::score_candidate` (candidate shape). Derive the TS types from those rather
than from the current JS.

### localStorage keys to preserve

Users have these set; don't orphan them.

- `deadwax-download-defaults` — `{formatPreference, autoGrab}`, JSON, possibly partial
- `deadwax-release-columns` — `{orderVersion, order, visible, widths}`, JSON. Read and written
  by main.js only; the releases-grid port (#5) writes the Preact reader, and must keep the
  vanilla loader's reconciliation - it checks the saved order against the current column set
  and backfills anything new, which stops a version that adds a column from hiding it forever -
  and `orderVersion` (see COLUMN_ORDER_VERSION in main.js).
- `deadwax-log-open` — the literal string `'1'`/`'0'`, **not** JSON. Writing `true` here
  reads back as closed on any un-ported page. main.js's alone until the log is ported.

`deadwax-download-defaults` is handled in `ui/src/state/persisted.ts`. Readers for the other
two were written there ahead of their ports and removed, unused, in v0.9.19.

## What to port, in order

| # | component | source | notes |
| --- | --- | --- | --- |
| 1 | ~~**Library window**~~ | *new* | **done.** `LibraryView.tsx` + `src/library.py`. Edition-aware; artist/album names hand off to a search through the bridge. Rebuilt as a tree + details pane in v0.6.5. |
| 2 | ~~Downloads panel~~ | ~~`renderDownloads` + 81 lines of manual reconciliation~~ | **done.** `key={job.id}` deleted all of it. Went first; see ground rule 2. |
| 3 | ~~Candidates panel~~ | ~~`renderCandidates`, filters, signal sliders~~ | **done** (v0.9.10). The Find buttons that open it are the releases grid's; since 2.0.0-player.15 the payload they send is the bundle's (`buildDownloadRelease` on the bridge, `lib/releasePayload.ts`). |
| 4 | Filter column | `renderFacets`, tri-state facets | |
| 5 | Releases grid | `buildReleasesGrid` (312 lines) | hardest. Consider TanStack Table via `preact/compat` — it replaces the column resize/reorder/visibility code wholesale, and TanStack Virtual fixes the DOM-size problem structurally |
| 6 | Top bar, log, profile | `init.js` + dropdowns | |

## State model

Seven module-level mutable objects become explicit state. They're small enough that Preact
signals or a couple of contexts will do — no Redux.

| current | becomes |
| --- | --- |
| `columnState` (persisted) | table config state + localStorage effect |
| `globalFilterState` (text + tri-state facets) | filter state |
| `candidateFilterState` (incl. `minSignals`) | candidates-panel local state |
| `downloadDefaults` (persisted) | settings state |
| `lastCandidateResult` | query result |
| `jobSpeedSamples` | **done** — a plain `Map` in a ref (`ui/src/lib/speed.ts`), folded in the poll callback rather than during render, so rendering stays pure |
| `mountedReleaseGrids` | **delete entirely** — a hand-rolled subscription system that props replace |

## Two bugs that must not survive the port

Profiled, with numbers, in CLAUDE.md. Both are trivially reintroducible in Preact.

1. **Eager hidden DOM.** `renderBody` builds every release's full track list up front even
   though it's hidden until clicked — ~half the entire DOM. In Preact write
   `{expanded && <Tracks/>}`. Do not render collapsed content.
2. **Forced synchronous layout.** `checkScrollability()` reads `scrollHeight`/`clientHeight`,
   forcing a full-document re-layout — measured up to **962 ms**. Called from 6 places
   including every expand toggle. Replace with CSS (`overflow: auto` handles scrollbars
   without measuring) or `ResizeObserver`. **Never read layout properties in a render path.**

## Verification while working

- `npm run typecheck` from `ui/` — cheap, and works on Node versions the build won't.
- `.venv/bin/python -m pytest tests/ -q` — 126 tests, all backend. Unaffected by this work;
  if they break, something is wrong beyond the frontend.
- **There are still no frontend tests, and a clean typecheck proves very little about a
  ported panel.** Downloads typechecks and matches the old markup class-for-class, but has
  never rendered a real job. Anything involving live data — polling cadence, derived speed,
  queue position, cancel — has to be watched against a running backend before it's believed.
- **Verify UI against computed styles and DOM state, not screenshots.** The preview pane has
  repeatedly served stale composites — it once showed a panel as transparent when computed
  styles proved it opaque.
- When checking colours, remember `theme.css` is `@import`ed and caches independently of
  `main.css`. Bust it explicitly.

## Definition of done for the migration

`interface/scripts/` and `interface/index.html` are gone, `interface/dist/` is the only
served frontend, and the Dockerfile's `ui` stage builds it. Until then both coexist — that's
expected, not a mess to clean up prematurely.

**The practical progress meter is `ui/src/bridge.ts`.** Every entry on `window.deadwax` is a
call the ported code still has to make into the old app, or vice versa. It holds two today
(`refreshDownloads`, `closeOtherDropdowns`). Adding one is sometimes the right call for a
panel in flight; leaving one is not. When the bridge is empty and `main.js` has nothing left
to run, delete both and switch Vite to building `index.html`.
