# Tooling and environment: gotchas

Each of these cost real time. Don't rediscover them.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

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
  - a single `output.file` cannot hold two entries and a shared chunk (since 2.0.0-player.36 the test
  bench's `deadwax-lab` is a third, in a config of its own, as vite builds it in a pass of its own - see
  notes/turntable-bench.md). Rolldown doesn't empty
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
