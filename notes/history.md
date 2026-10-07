# History: the name, and why Lidarr was dropped

Moved verbatim from CLAUDE.md (2026-10-07); CLAUDE.md keeps the rules in short.

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

### Next up (as it stood on 2026-10-07)

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
