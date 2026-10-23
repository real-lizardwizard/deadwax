# The fixes before 2.0.0 (2.0.0-player.65)

The release review's list, done before 2.0.0 is tagged: secrets over two saves, the example files, symlinks out of an
album, break-glass, the Library's Shuffle's memory, stopping the container, the store index after the upgrade, the
event log behind nginx, the slash redirect behind TLS, the Secure cookie, re-starring, the Normalization docs, warming
a first play, and the small ones. Read it when your work touches any of those areas. Sections refer to each other by
title: `grep -rn "### <title>" notes/` finds one.

### Fixes before 2.0.0 (2.0.0-player.65)

James (2026-10-23): "review 2.0.0 and let me know if it's ready for release". The release review (eight lenses, every
finding checked by skeptics, then a completeness round - `deadwax-scratch/work/rel200/verdict.md`) said **ready after
the listed fixes**, no blockers. Its sections 3 and 4, in its order. The main page's retirement, the prerelease
history in the user docs and the version bump to 2.0.0 are the next steps', not this one's.

- **The environment's secret over two saves** (MAJOR, `src/routes/settings.py` `_moved_without_secret`). A new
  address saved with ANY secret (`[{SLSKD_URL: collector}, {SLSKD_APIKEY: junk}]` - accepted, a secret was typed),
  then the secret alone reverted (`[{SLSKD_APIKEY: null}]` - never checked, no address in the batch) put compose's key
  back at the collector's address; the next ping carried it there. Navidrome's pair the same. Now the second half:
  a batch that REVERTS a secret (value `null`) while the address in force after the batch - saved before, or in it,
  a revert of it reading as the environment's - is non-empty and not the environment's address is refused, on the
  secret's row, in `ENVIRONMENTS_SECRET_ELSEWHERE`'s words ("type the slskd API key again - the environment's key
  was given for the environment's address, and SLSKD_URL would be another one (or revert SLSKD_URL in the same
  save)"). Reverting both together is allowed (the environment's pair), as is a revert while the address is the
  environment's, or cleared (nothing is sent). **Blanking** (`""`) stays allowed: it leaves no secret, so nothing of
  the environment's goes anywhere - pinned by its own test (the spec said "reverts or blanks"; a blank refused would
  be a refusal with nothing to protect). The environment's value is `Config.ENV_VALUES` once the overrides were
  applied, else what Config holds (`_environments`), as `_stops_organizing` reads it. And `SLSKD_URL` and
  `SLSKD_APIKEY` joined `ADMINS_ONLY` (the key is full control of slskd), so "Settings and the log" no longer hands
  it out; with logins on an admin's own saves are held to the two-save rule too. Tests: both orders for both pairs,
  logins off (test_slskd_settings.py, test_navidrome_settings.py) and on (test_logins.py, as an admin; the
  ordinary-with-Settings test now asserts the slskd rows locked in their words).
- **The example files' logins block.** The compose example offered `#- DEADWAX_SECRET_KEY=` (and the admin password)
  to uncomment: an empty line under `environment:` beats `.env`, and nobody can sign in. Both lines are gone; the
  block says logins need `ORGANIZE_MODE` copy or move (or every route is a 503) and to keep the key in `.env`;
  `.env.example` gained the three login lines, commented out, with the same words. "since .45" became .46 (when
  Navidrome became required) and the MusicBrainz sizing "about 4,000 artists" became "about 1,100 artists explored",
  as measured in .56 (about 160 KB an artist with Search's index) - in both files and `src/config.py`'s comment.
  troubleshooting.md's "put it in compose" now says `.env`, and to look for a stray line under `environment:`.
  Pinned by test_logins.py's example-files test.
- **Symlinks out of an album.** Covers and artist pictures were READ through a symlink (`library.py`
  `load_album_art`, `load_artist_art`) and WRITTEN through one. Reads now check what `/disc_art` checks - the file
  itself resolves inside its folder (`is_within(entry, directory)`) - a cover refused is passed over for the
  embedded art, logged. Every picture writer refuses a target name that IS a symlink, dangling or not
  (`organizer.LINK_REFUSED`: "is a link to somewhere else, which deadwax won't write through"): `retag.save_cover_art`
  and `execute_retag`'s cover (the tags still written, the problem said), `artist_art.execute_artist_art`,
  `disc_art.save_disc_art` - and, the same hole, `lyrics.execute_lyrics`. A link already there and not being replaced
  is still skipped silently, as an existing file is. tests/test_symlinks_out_of_the_album.py, and test_retag.py's.
- **Break-glass.** The name `deadwax` is public and the throttle counted every guess for it, so three wrong guesses a
  minute from anyone kept the way in shut. **The first version of this fix made an oracle**: `auth.sign_in` checked
  the break-glass password BEFORE the throttle's wait, so the right one answered 200 while every wrong one answered
  429 - a 429 said "wrong" as surely as a 401, and the throttle no longer slowed a guesser at all. Changed before
  the slice was committed: the wait comes first again, as for every name, and the break-glass name's tries are
  counted per name AND client address (`auth.break_glass_key(address)`, the sign-in route passing
  `request.client.host`) - a tuple, so no typed name (a string, `deadwax@1.2.3.4` included) ever shares its count;
  an IPv6 address counts as its /64, an IPv4-mapped one as its IPv4. A held-off address gets 429 for the right
  password too, word for word the wrong one's, and learns nothing; the owner from another address signs in. Behind
  a reverse proxy every sign-in may share the proxy's address (uvicorn trusts X-Forwarded-For only from 127.0.0.1,
  its default), and then it is the per-name throttle of before - accepted, and the docs say to sign in at deadwax's
  own address then. Ordinary (Navidrome) names are unchanged: per name, the wait first, Navidrome not asked while
  held. A guesser with many addresses still gets three a minute from each, so the password's length is what
  protects it.
  `config.describe_admin_password` (16 characters, `ADMIN_PASSWORD_ADVISED`) warns once at start-up with logins on
  and marks the row in the settings tab (status error, the detail in words) - never refused: it is the way in during
  an emergency. Neither ever quotes it. Docs: configuration, sharing, troubleshooting (a new entry for the warning).
  Tests (test_logins.py): a held-off address's right password is a 429 like a wrong one's; another address signs in
  meanwhile; ordinary names still per name from any address, and `deadwax@<address>` typed is an ordinary name; an
  IPv6 /64 counted as one. Each mutation-checked: the password before the wait, break-glass per name alone, every
  name per address, a string key, no /64, and the route passing no address each fail them.
- **The Library's Shuffle's memory** (`src/routes/navidrome.py`). Each order held the list it was made from, and the
  list is built again every ten minutes: measured at 20,000 songs (`work/builder65/measure_shuffle.py`, ten orders -
  four unclaimed a scope over both scopes and two claimed - each made over a rebuilt list, tracemalloc): **196.3 MB
  before, 21.6 MB after**. Orders and lists now hold the songs' ids (tuples of the very strings the one table keys
  them under, 160 KB an order), the songs themselves kept once in `_shuffle_songs_by_id` - one table whoever's lists,
  since SHUFFLE_FIELDS are the song's own and each order names only ids its own user's build read; a rebuilt list
  reuses the dict of an unchanged song (`_kept_song`), so the ids are shared too. A changed song is paged as Navidrome
  now has it. `_sweep_shuffles` forgets orders a day untouched, lists past their ten minutes and every song nothing
  names; `run_shuffle_sweeps`, a lifespan task, runs it every SHUFFLE_SWEEP_S (600 s), so an idle deadwax lets them
  go (after the sweep: 0 orders, 0 songs). Pages answer the same; nothing the app sees changed.
- **Stopping the container.** `src/main.py` passes `timeout_graceful_shutdown=5` (GRACEFUL_SHUTDOWN_S). uvicorn
  0.40.0's `Server.shutdown` waits that long for open requests, cancels what is still open, then sends the lifespan's
  shutdown - so the teardown runs (before, a playing song or an open Log made uvicorn wait for ever and docker
  SIGKILLed it at 10 s). The teardown's own order is unchanged (the tasks cancelled - now with the start-up scan and
  the sweep among them - MusicBrainz's refreshes stopped, its connections closed, the saved answers written and
  closed, every client closed); uvicorn doesn't wait for a cancelled stream to unwind before the teardown starts, so a
  stream's last lines may race the clients' close - harmless, it is ending anyway. Seen on a real uvicorn (port 8110,
an open Log stream, SIGTERM): exited after 5.2 s, "Application shutdown complete"; uvicorn logs "Cancel 2 running
task(s)" and an "Exception in ASGI application" traceback per cancelled request - its own words for the stop, said
in troubleshooting.md so nobody reads them as a fault. tests/test_main.py: the setting, the
  order read off uvicorn's own source, and a real Server shutting down over a request task that never ends.
  **Not bounded: a scan's walk.** `scan_library` runs in a worker thread (`asyncio.to_thread`), which cancelling
  its task can't stop, and `asyncio.run` waits for the default executor's threads at exit - so a stop during the
  start-up scan of a big library, or a Rescan, still outlives Docker's 10 s and is killed. Harmless (the scan's
  results are saved only at its end; the start-up scan runs again next start), and said in troubleshooting.md.
  Not seen on a real stop - read from the code (the review).
- **The store index after the upgrade.** SCAN_FORMAT 8 -> 9, so `seed_from_saved_scan` finds nothing in an older
  saved scan and the index stays empty until something scans: album pages couldn't offer Add, Find couldn't see the
  library, the first admin's seed waited. `routes/library.scan_at_start` (from the lifespan, as a background task -
  never awaited before the app serves) walks the library once when `store_index_scanned` lacks LIBRARY_PATH, through
  the scan machinery every request uses: `scan_library` (its lock - never two walks at once; a request's scan meanwhile
  waits and reads the cache) and `_save_scan` (the saved scan, the index, `store_index_scanned`) - the request-free
  halves of `_ensure_cache_loaded` / `_persist_cache`, which now call them. Logged as it starts and ends; a failure is
  said and left to the next scan. An empty library records nothing, so the next start walks it again (cheap). The seed
  log line and the docs (sharing, player, troubleshooting) no longer claim an album page starts a scan.
- **The event log behind nginx.** The stream answers `X-Accel-Buffering: no` (nginx's own header for "don't buffer
  me"); sharing.md's step 3 has a sample nginx block (`Host $http_host`, `X-Forwarded-Proto`, `proxy_buffering off`
  for the Log and the audio, `proxy_read_timeout 1h`), linked from configuration's TRUSTED_ORIGINS row and the Log's
  troubleshooting.
- **`/player` behind a TLS proxy.** Starlette wrote its slash redirect's Location (the static mount's and the
  router's alike) from the request as deadwax received it, plain http. `RelativeRedirects`, plain ASGI like the
  layers beside it, rewrites any 3xx Location naming deadwax's own Host to a relative reference (path, query,
  fragment); one naming another host is left alone (`relative_location`). Not FORWARDED_ALLOW_IPS=*. Its path
  never starts with two slashes - see "After the second review" below.
- **The Secure cookie.** A troubleshooting entry ("Signed in over HTTPS, and now the http address won't sign in"):
  the cause (a browser won't let an http page replace a Secure cookie) and the fixes (one address per host name, or
  sign out over https / clear the site's cookies). The cookie keeps its name (renaming it would sign everyone out).
- **Re-starring** (`src/stars.py` `star_entry`). `getAlbum` is asked before `star`: an album already starred is only
  confirmed, so Navidrome's starred date isn't reset (it was, when a grant came between two read-backs - a first scan
  just after a sign-in). One more call per album starred. **The nit**: an untagged album (no release id) can't be
  found in Navidrome to star, so the seed's untagged albums waited for ever - even ones starred in Amperfy. The
  read-back (`sync_user`, `_untagged`) now matches a waiting untagged entry to the ONE starred album Navidrome reads
  no release id from with its album artist and name (case and spacing folded; two such albums match neither) and
  confirms it; once starred it is kept while its Navidrome id stays among the stars (asking nothing), removed when
  `getAlbum` says unstarred, and left as it is when Navidrome doesn't have it (error 70) or it is being applied to - a
  star lost isn't one taken away. Untagged and unstarred: still waiting, saying why (an admin can apply a release).
- **The Normalization docs** say which FLACs aren't levelled (20- or 32-bit, more than two channels, every song while
  the player's cache can't be used, and the over-long CD song); the log line of a levelled copy says it was put in
  "an MP4 for Normalization" (or "a fragmented MP4 for Normalization"), not `wrap.made`'s "for Safari".
- **Warming a first play.** `warmAlbum()` (player/levelling.ts - beside queued(), whose storage read it shares; not
  player/api.ts, whose sims can't take preact) warms an album with a FLAC song unless Normalization is Off; the album
  page's effect calls it, and so now do Search's song tap, Requests' Done ▶ and an artist's Play (its first album;
  Shuffle levels by song and warms nothing) - each right AFTER its tap's playTracks, nothing awaited, so the tap is
  untouched. `warmLevels()` keeps an in-flight set, so one album is never asked twice at once (the server's gate
  already drops a second album as "busy"). **Honestly**: a play's own levelled request starts the same album task
  (`_album_task`), so warming at the tap gains only the moments before that request reaches deadwax; warming those
  albums before the tap (as their songs are prefetched) was left out on purpose - deadwax measures one album at a
  time, so a warm of a row's album would make a tap on another one wait behind it. app-rules.sim (the order and the
  count, per site) and requests.sim (behaviour: warmed once, after the play; nothing for an album with no FLAC song,
  nothing under Off).
- **Small ones.** A sign-in deadwax can't read (an over-long password) answers 422 with `SIGN_IN_FORM`'s words, never
  FastAPI's list echoing the input - `refused_body`'s People handling, for `/deadwax/auth`. "Join it" is no longer
  drawn without its button (StoreState, for someone without Get albums: `perPerson.withoutJoin`). Library care's line
  names only the parts drawn (`libraryCare.careLine`). configuration.md: three login settings, three Get settings.
  The iframe refusal and the first admin's starring of the store are said plainly in sharing.md (Before you start,
  What happens to what you had), with a troubleshooting entry for a blank dashboard tile; a stop's 5 seconds there too.
- **Verified**: Python 3602 collected (3600 passed, 2 skipped; 66 more than .64's 3536, thirteen of them the two reviews' below); pyflakes clean; tsc clean;
  every sim; the build; the engine files without a diff. Each rule above mutation-checked (broken, its test failing,
  restored byte for byte): see the slice's report. **NOT verified** against real infrastructure: a real nginx in front
  of the Log; Navidrome 0.64.2's `getAlbum` `starred` before a `star`, and an untagged album's starred2 entry with an
  empty `musicBrainzId` (the fake is shaped from its source); a real `docker stop` timed with a song playing.

### After review (fixes before 2.0.0)

The slice's review found these, each confirmed by a skeptic; all fixed in the same change.

- **A sweep in the middle of a Shuffle build** (major). `_shuffle_songs` put each song in `_shuffle_songs_by_id` page
  by page, awaiting search3 between pages, and stored its list only at the end; `run_shuffle_sweeps` is its own task,
  and `_sweep_shuffles` keeps only songs a list or order names - so a sweep landing between two pages dropped every
  song the build had read so far (nothing named them yet: a first shuffle, or after a day idle). The order said the
  full total and `_shuffle_page` skipped the missing ids, so pages came back short or empty; the app's feed advances
  by the songs a page brought (lib/upNext.ts), so it repeated songs and never reached the total (the reviewer's repro:
  4,500 queued, 2,500 distinct). Now a build keeps its songs (trimmed to SHUFFLE_FIELDS) in a local list, and the
  table takes them - through `_kept_song`, sharing an unchanged song's dict as before - in the same synchronous step
  that stores `_shuffle_lists[key]`, nothing awaited between: no sweep can land between the two. A build's songs are
  held twice only while it runs (its own list, then the table). A failed build (413, Navidrome gone) leaves nothing in
  the table now. test_navidrome_shuffle.py runs a sweep from inside the third search3 page.
- **A dry-run retag and a cover that is a symlink** (`execute_retag`). The symlink check came after the dry-run branch,
  so a dry run said it would write `cover.png` where the apply refuses it; a dry run runs the identical plan. The check
  is first now, and a dry run says "tags would be written but the cover art wouldn't be saved: cover.png is a link…".
- **Two untagged pressings of one name, one star** (`stars.sync_user`). The match was unique on the starred side only:
  two waiting untagged entries with the same album artist and name (Dummy (1994), Dummy (1994) [Deluxe] - store_album
  keeps the edition apart) were both confirmed from one star, with one Navidrome id, and unstarring removed both. A
  name two of the user's untagged entries (waiting or starred) share now matches neither; both wait. troubleshooting.md
  says so.
- **LIBRARY_PATH saved while the start-up scan walks** (`routes/library._save_scan`). The walk began with the old root
  and `_save_scan` read Config again: the old library's paths were saved, reconciled and marked scanned under the new
  root (whose start-up scan then never ran). `_save_scan` takes the root walked (`walked`; the start-up scan and both
  request scans pass it) and, when LIBRARY_PATH has changed since, saves nothing and says so in the log ("that scan is
  set aside"); the start-up scan then logs no "scanned" line. test_scan_at_start.py moves the root mid-walk.
- **A locked row's Revert** (`SettingsView.tsx`). The revert button drew on `overridden` alone, so a person given
  Settings and the log saw "Revert to the environment" on the locked slskd and Navidrome rows, and its save was
  refused with the batch. It draws only when the row is editable.
- **The two-save rule's other half beside the field.** `retypeSecretNote` said only "type it again" for a new address
  without its secret. A secret reverted while the address in force after the save - saved before, or typed now - isn't
  the environment's now says, on the secret's row, "Reverting brings back the environment's API key (password), which
  was given for the environment's address - type the key again, or revert SLSKD_URL in the same save" - before Save
  refuses it. It needs to know whether the environment holds a secret at all (with none, the revert just unsets it and
  is allowed), so a secret's row now carries `env_set` (a yes or no, never the value; null on other rows) - the server
  rule's own `_environments(secret)`. settingslog.sim: the drawn rows and the rule's cases.
- **Words.** People's warning for Settings and the log (`WARN_SERVER`) and sharing.md no longer say it can point
  deadwax at slskd or Navidrome (their rows stay an admin's): "other folders and change how it downloads and files".
  configuration.md's SLSKD_URL and NAVIDROME_URL rows say the revert is refused while the address is a different one
  from compose's or `.env`'s (a saved address equal to the environment's is allowed, and tested). `.env.example`'s
  DEADWAX_SECRET_KEY sentence reads straight. troubleshooting.md's stop entry and "Stopping the container" above say a
  scan's walk can't be stopped and outlives Docker's 10 s.
- **Tests**: the reverse two-save order as an admin with logins on (test_logins.py, both pairs), so "both orders, on
  and off" above holds.
- **Verified after review**: Python 3596 collected (3594 passed, 2 skipped); pyflakes, tsc, all 63 sims and the build
  clean; the engine files without a diff. Each fix mutation-checked (the fix undone, its test or sim failing, the file
  restored byte for byte). NOT verified on a real page: the locked rows and the revert note as drawn in a browser.

### After the second review (fixes before 2.0.0)

- **An open redirect from the relative Location** (major, a regression of the fix above). The static mount at `/`
  writes its slash redirect from the request's DECODED path, and uvicorn decodes `%2F`: `/%2Fevil.example%2F..%2Fplayer`
  is the path `//evil.example/../player`, which StaticFiles resolves to the player's folder and redirects to
  `http://host//evil.example/../player/`. Absolute, that stayed on deadwax's host; made relative it was
  `//evil.example/../player/`, which a browser reads as protocol-relative - another host. Pages are public with logins
  on, so a link to deadwax could send anyone to a look-alike sign-in. `relative_location` now collapses every leading
  slash (and backslash) of the path to one: `/evil.example/../player/`, which the browser resolves on deadwax's own
  host (to `/player/`). test_pages.py asks the real app for the `%2F`, `%2F%2F` and `%2F%5C` forms and checks each
  Location resolves on deadwax's host; and the pure function's cases.
- **The environment-holds-no-secret exemption, tested.** `_moved_without_secret` allows a secret's revert at a new
  address when compose and `.env` hold no secret (the revert only unsets the typed one; nothing is sent) - the rule the
  tab's `env_set` note mirrors. Nothing pinned it on the server; test_slskd_settings.py and test_navidrome_settings.py
  now save a new address with a typed secret, revert the secret alone with none in the environment, and expect 200.
- **Verified after the second review**: Python 3602 collected (3600 passed, 2 skipped); pyflakes, tsc, all 63 sims and
  the build clean; the engine files without a diff. Both mutation-checked: `relative_location` back to the path as it
  came (all four new redirect tests fail) and without the backslash (the pure case fails); the `_environments(secret)`
  condition dropped (both new settings tests fail); each file restored and compared with `cmp`. NOT verified: the
  `%2F` form through James's real proxy (nginx's `proxy_pass` with no URI passes it through, per the reviewer).
