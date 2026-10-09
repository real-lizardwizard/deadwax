# The phone player: the spike, the port to 1.0 and the scan wait

The phone player's design and its port onto 1.0 (1.0.3). The player's speed - 0.25x to 2x, its pitch
moving with it, put on every element the engine plays on - is "The speed fader (2.0.0-player.39)" in
notes/turntable.md, where the fader that sets it lives.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

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
  version check every MP4 answer makes (see "The turntable, part two") - or since 2.0.0-player.23, with no
  MP4 kept of the song as it is, byte ranges of its own `stream` (`format=raw`), still nothing the page
  sent passed on (see "Windows cut straight from the FLAC") - and since 2.0.0-player.17
  artists (getArtists, nothing passed on), one artist (getArtist) and one song (getSong), each by an
  id at most 256 characters passed as Navidrome's `id` parameter (see "Artists, and the two
  libraries joined"). The configured account MAY
  be Navidrome's admin and deadwax has no login, so a catch-all would hand out user management to
  anyone on the network - though the docs and the settings tab now say to use a non-admin account
  of your own: none of the eleven calls
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
