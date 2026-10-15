# Logins and roles

Step 3 of the multi-user plan (the plan is a Claude Doc, "deadwax multi-user plan", section "Accounts,
logging in, roles"). Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Logins and roles (2.0.0-player.48)

James (2026-10-14): "I'd like to make sure the logins get built as well". Every design choice below was
decided with him when the plan was made (2026-09-27) - don't re-open them. The users: James (the only
admin; his Navidrome account `james` is NOT a Navidrome admin) and his roommate Ethan (a user), over
plain http on the LAN and WireGuard.

**Off is today.** `AUTH_MODE` (`off` default | `on`) is ENVIRONMENT ONLY, like the other three
(`DEADWAX_ADMINS`, `DEADWAX_SECRET_KEY`, `DEADWAX_ADMIN_PASSWORD`): a stored override beats compose, so
a bad value saved in the settings tab could never be undone from it. All four are in
`Config.NOT_EDITABLE` (`LOGIN_SETTINGS`, `LOGINS_LOCKED`), so `apply_overrides` ignores a stored row and
the PUT refuses one; the settings payload has a read-only **Logins** group (`_logins_rows`, secrets as
set or not), which the tab puts under Connections (`tabForGroup`). Off, `current_user` answers `local`
without looking at the request and nothing is read or written; every test and sim that existed passed
unchanged. Anything but `off`/`on` reads as ON (`describe_auth_mode`) and is said at start-up: a typo
fails closed.

**The pieces.** `src/auth.py` is the mechanics; `src/users.py` the two dependencies (`current_user`,
`require_admin`), `is_admin` and `auth_mode`; `src/routes/auth.py` the HTTP (`POST /deadwax/auth/login`
{username, password}, `POST /deadwax/auth/logout`); `store.py`'s `sessions` table and its SYNC methods.

- **Every router is checked by a dependency** (`app.py`: `dependencies=[Depends(current_user)]`, or
  `require_admin` for the log and the server settings whole; the library's writers and the review queue
  per route, `ADMIN` in routes/library.py) - never `@app.middleware("http")`. `current_user` is
  SYNCHRONOUS, so FastAPI runs it in its thread pool and a SQLite read there blocks nothing; FastAPI
  caches it per request, so a route's own `Depends(current_user)` is the same call. Public: the health
  check, the pages (`/`, `/player/`, the lab), the static files and the two auth routes.
  **`tests/test_logins.py`'s `ROUTES` decides every route** (public, user, admin): the app's routes must
  be exactly its keys, every non-public route answers 401 without a session, every admin route 403 to a
  user (with `ADMIN_ONLY`'s words), and no user route depends on `require_admin` - a route added
  without deciding fails.
- **Signing in is Navidrome's Subsonic `getUser`**, for the account's own name, signed as that account
  with a token deadwax makes (md5 of password + a fresh 16-byte-hex salt) - never the web login
  (`/auth/login`: undocumented, and 5 logins per 20 s per IP, all of deadwax's from one IP).
  `auth.LoginClient` is its own httpx client beside the player's (whose `_params` lay NAVIDROME_USER's
  login on last), needing only `NAVIDROME_URL`, held to `describe_navidrome_url` - the only thing that
  holds a compose-set address to it (the settings tab checks what is saved there), so an address with a
  login in it, or no scheme, gets no sign-in's or re-check's token and is told as the address problem. The name is sent as
  typed; the identity is the Navidrome user name LOWERCASED. Error 40 is a wrong login (401
  `WRONG_LOGIN`), 41 an LDAP account (502, said), unreachable a 503 ("Navidrome isn't answering") that
  isn't counted against the name. `NavidromeError` gained `code` (Subsonic's) for this.
- **The throttle** (`auth.Throttle`): 3 wrong passwords per lowercased name in any 60 s, then 429 with
  Retry-After and Navidrome not asked; each name's tries in turn (an `asyncio.Lock` per name), so ten at
  once are ten counted; a success clears it; the break-glass name too. Navidrome blocks a user for 20 s
  after 5 failures; 3 a minute plus the re-check's one a pass never reach it. Nothing ever retries.
  The record is bounded (`cap`, 10000 names) but a name HELD OFF is never what makes room
  (`_make_room`): first what has left the window, then names under the limit, oldest first, never the
  failure just counted - so failing 10000 other names can't flush `james` (it could, until review).
  With every name held the record goes past the cap; each of those cost Navidrome 3 refusals and leaves
  within the minute. (Refusing new names when full was rejected: filling the table would then have
  locked everyone out, right passwords included.)
- **Reserved names** (`RESERVED_NAMES`): `local` (logins-off's user, whose rows the first admin takes)
  and `admin` (break-glass) - never put to Navidrome, so a Navidrome account named `admin` can't be
  deadwax's admin by its name.
- **The session**: `"s." + secrets.token_urlsafe(32)` in the `deadwax_session` cookie (Navidrome's is
  `jwt`, and cookies aren't kept apart by port) - HttpOnly, SameSite=Strict, Path=/, Max-Age 400 days
  (Chrome's cap; the server's own expiry is what counts), Secure when the request came over HTTPS or
  `X-Forwarded-Proto: https`. The `sessions` table keys on the id's SHA-256 (`id_hash`) - a copy of the
  file is no live cookie - and keeps the typed name, token and salt Fernet-ENCRYPTED (`seal_credential`)
  with a key HKDF-SHA256-derived from `DEADWAX_SECRET_KEY` (one derived key per purpose; any string of
  32+ characters will do; the `cryptography` package, pinned in requirements.txt - CI installs that
  file). Expiry slides: 30 days from the last use (`SESSION_IDLE_SECONDS`), written at most every 10
  minutes (`TOUCH_SECONDS`) - BEST EFFORT (`_touch`): the session was read and stands, so a write that
  fails (a full /config, a volume gone read-only, a lock past SQLite's 10 s) is a warning in the log and
  the request goes on; `touched` moves on first, so it isn't tried on every byte range, and the expiry
  in memory moves only once the database has it, so a missed write can only end a session sooner. (Until
  the second review it was a 503 saying the database couldn't be READ - playback stopped within ten
  minutes of the disk filling.) Held in memory (`_held`) and read from the database again after 60 s
  (`CACHE_SECONDS`), so a stream's byte ranges don't each read SQLite and a database gone away is found
  within a minute.
- **The re-check** (`check_sessions`, run every 60 s by `run_session_checks`, a lifespan task only with
  logins on and a database): every live session Navidrome hasn't vouched for in 5 minutes
  (`RECHECK_SECONDS`) is put to getUser again with its own token, ONE per person a pass (so it never
  makes a run of failures for one account - a person with three stale devices is signed out of them a
  minute apart). Error 40 ends the session (`end_session`: row deleted, `_ended[id_hash] = LOGIN_GONE`,
  so the next request's 401 says why); a credential that won't decrypt (another key) ends it with
  `KEY_CHANGED`; Navidrome down ends NOTHING - it is proof of nothing.
- **Admins** are `DEADWAX_ADMINS` (comma-separated, lowercased) plus the break-glass admin
  (`is_admin`). Navidrome's adminRole is never read (the tests' fake sets it for ethan to prove it).
- **Break-glass**: `DEADWAX_ADMIN_PASSWORD` compared in constant time (SHA-256 digests through
  `hmac.compare_digest`, so neither length nor prefix shows), then a cookie `"b." + Fernet token`
  (padding stripped, so the cookie isn't quoted) holding the fixed user, a nonce and an HMAC of the
  password - needing neither Navidrome nor the database. Fernet's own timestamp bounds it to 12 hours
  (`decrypt_at_time`); a new password ends every one; sign-out remembers its nonce in memory (a restart
  forgets, the 12 hours bound that). It takes over nothing (`adopt_local` is for a Navidrome admin).
- **Fail closed**: no usable key (`auth.unusable()`) is a 503 on every protected route and the sign-in,
  saying what to set; the store unavailable, or a read raising, is a 503 (`NO_DATABASE`; a failed expiry
  WRITE isn't one, above, though a new sign-in's write is) - never "signed in", and never "signed out" (which would only send everyone to a sign-in that can't work). A
  break-glass cookie is checked before the database. The health check stays 200 (it judges deadwax
  alone, as it always did).
- **`adopt_local(user)`** (written in 2.0.0-player.18) is called on every Navidrome sign-in of an
  admin: the first takes what `local` saved, theirs winning; after that `local` is empty and it takes
  nothing. Switching logins off again leaves those rows with the admin. Since 2.0.0-player.49 the
  first admin seen with a session after a start takes over what `local` still holds too (see
  "Downloads per person" - a session outlives the restart that switches logins on).
- **The pages** carry `<meta name="deadwax-auth" content="on">` (`LOGINS_MARK`) when logins are on -
  the app's page also the sign-in's own stylesheet (`SIGNIN_SHEET`, `interface/player/signin.css`) -
  injected by `with_logins_mark`; off, every page is byte for byte what it was (no extra stylesheet, no
  round trip before the app draws). `/` and `/index.html` get routes of their own before the static
  mount only with logins on. `/docs`, `/redoc` and `/openapi.json` are off with logins on.
- **Never sent to the page or logged**: the password, the token and salt (httpx stays quiet at
  WARNING, src/logger.py), the secret key, the break-glass password, the cookie's id (only its hash is
  stored). The sign-in answers what `/deadwax/me` answers. Logged: who signed in, a refused name
  (truncated to 60 characters), who the re-check signed out - to the event log, an admin's.
- **What a session's end cuts, and what it doesn't**: a response already streaming when its session
  ends - the log's event stream, a song's one response - runs on; every request after is refused,
  the player's included. So the music does NOT wait under the sign-in screen: the song playing goes on
  only as far as the device has it (the audio element asks for more by range; the gapless stream
  fetches pieces of a few seconds, and its next piece's 401 is `classifyAnswer`'s "fatal", leaving the
  stream for the plain URL, which 401s too). Then the ENGINE's failure path - untouched - asks for each
  song once more and skips it (`afterFailure`: retry, then skip, to the end of the queue), so by the
  time someone has signed in the queue has usually run out, its last reason blaming the song
  (`describeMediaError`). Found in review (headless Chromium, a session ended under a playing album:
  the queue went by in about 14 s, and with Gapless on the playing song stopped at the next piece).
  **For James**: stopping the skip-through on a 401 (holding the queue where it is) is an engine
  change, in `playQueue.ts`/`streamPlan.ts`, and so his call; nothing here does it. The docs say what
  happens.
- **Cookies aren't kept apart by port**: every service on deadwax's host name (Navidrome, slskd, the
  NAS's page) is sent `deadwax_session` with its own requests. HttpOnly keeps their pages' scripts from
  reading it, but the services themselves receive it - trust what shares the host name, or give deadwax
  a name of its own. (`__Host-` would help only with Secure, which plain http rules out.)
- **SameSite=Strict never locks the app out**: the pages are public, and every request they make is
  same-origin, so even a launch Strict withholds the cookie from (a link followed from another site)
  draws the page and then sends the cookie with its first ask.
- **The same-origin guard** still stands outermost, in front of the sign-in too (a page elsewhere can't
  sign the browser into an account of its choosing). Logins close the DNS-rebinding gap it had (see "The
  1.0.1 fixes"): a rebound page is on the attacker's host name, which deadwax's cookie isn't for.

**Who can do what** (the plan's table; Ethan is a user):

| action | user | admin |
| --- | --- | --- |
| search, find on Soulseek, request (Get) | yes | yes |
| their own Getting albums preferences, pins | yes | yes |
| leave or retry their own requests, hide finished ones | yes (since step 4, 2.0.0-player.49 - "Downloads per person") | yes |
| see and cancel everyone's downloads | no - their own and joined ones only (the gap step 3 left, closed by step 4) | yes |
| edit the shared library: apply a release, edit tags, delete, covers, lyrics, CD art, re-file an artist, artist images (and their artist search), bulk runs, rescan | no | yes |
| the review queue (Needs a look, `/queue/*`) and the new-imports badge | no | yes |
| the event log (`/interface_logs/*`) | no | yes |
| server settings (`/settings`) | no | yes |

Reading stays everyone's: `/library/albums`, `/tracks`, `/lyrics`, the pictures, an artist, owned.

**The app** (`ui/src/app/signInGate.tsx`, `SignIn.tsx`, `SignOutRow.tsx`, `session.ts`;
`lib/signIn.ts`; `api/auth.ts`). `player/main.tsx` draws the app at once when the page has no mark (off:
today) - and RELOADS it at its first 401 (`reloadWhenLoginsComeOn`): with logins off nothing answers
401, so a 401 there means they were switched on under a page kept open (the home-screen app iOS held in
memory, a tab), which has no gate - until the second review everything in it failed "Sign in to use
deadwax." and no sign-in came until the app was killed. The page that comes back carries the mark. Once a
page, and not again within a minute (`RELOAD_AGAIN_MS`, noted in sessionStorage for the tab; reloading
regardless where the browser keeps nothing), so a proxy answering 401 to requests but not to the page
can't set it reloading over and over. It needs the page to be running .48 already: upgrading and
switching logins on together leaves a page of older code that can't tell (getting-started.md says to
reopen the app). With the mark, `startWithLogins` asks `/deadwax/me` FIRST. Signed in, the app is drawn knowing whether
this is an admin (`session.ts` `adminUntilAsked`, which App's `admin` and You's start from - a user never
sees an admin's rows for a moment); signed out, the sign-in screen is drawn ALONE in a layer of its own
(`#signin-root`) and the app only once someone signs in. `api/http.ts` turns any 401 (but the sign-in's
own) into a `deadwax:signed-out` event with the server's words; the gate brings the sign-in screen back
OVER the app - the app left mounted, `#player-root` inert and aria-hidden, `html.has-signin` holding
the page still - so nothing it holds is lost (what the player does meanwhile: "What a session's end
cuts" above; no engine file changed). The same person signing in carries on, focus given back to what
had it (`focusBefore`, `preventScroll`); someone else starts the app again (`location.reload`: the
pins, Getting albums and the queue in hand were the other's). **A 401 for a request sent before the
latest sign-in is ignored**: `api/http.ts` stamps each request with the session it went out under, and
the gate calls `newSession()` as the sign-in screen goes - else a poll that left with the old cookie
just before the sign-in answered, and was answered just after, brought the screen straight back
(saying the old reason) over someone who had just signed in - a few re-sign-ins in a hundred over
WireGuard. **The player's own requests don't go through http.ts** (the element's `src`, the gapless
stream's fetch), so the gate also listens for media elements' `error` in the CAPTURE phase on the
document (it doesn't bubble; the player's elements are in the page) and asks `/me` - the sign-in comes
up as the first song fails, not at the next tap. A `/me` that fails WITHOUT a 401 over the running app
(WireGuard still reconnecting as the phone is unlocked, deadwax down as a song fails) leaves the app
alone: nobody was signed out. Who is asked again as the page comes back to the front
(visibilitychange) and as the browser shows it again from its back-forward cache (`pageshow`
persisted), never on a timer - WHILE THE SIGN-IN SHOWS TOO: a 200 then takes it away as a sign-in would
(signed in in another tab, or Back to a sign-in already done). `?return=/` (the main page's link) goes
back to `/` once signed in - by `location.replace`, so Back from `/` doesn't land on a done sign-in -
and nowhere else (`returnTarget`). The screen: deadwax's name, a
user name and a password (autocomplete `username`/`current-password`, no capitals or corrections on the
name), read from the fields at submit (a password manager's fill needn't fire input), deadwax's own
words for a failure in an assertive live region always in the page, the password dropped once its
sign-in answered, why it is showing (the 401's words) in amber above the form and as the dialog's
`aria-describedby` (focus goes straight to the name field, so VoiceOver would never read it out) - but
not the plain "Sign in to use deadwax.". 17px fields, a card centred by its margins (so a short screen scrolls to its top),
clear of the notch and home bar, over everything (z 60) - but a FULL-SCREEN element is in the browser's
top layer, over any z-index, with everything outside it inert: the desktop visualizer's full screen hid
the sign-in (and its focus didn't take) until the visualizer was left (second review). So the gate leaves
full screen as the sign-in comes up (`leaveFullScreen`, with the webkit form) - the visualizer closes
itself on fullscreenchange - and focuses the name field once the browser has left. (Chromium does NOT
make the full-screen element inert under the inert host - the visualizer's own controls kept working -
so it was hidden, not stuck.) Nothing in it plays: it is on no allowlist and
reaches no action. **Sign out** (You > About, logins on only) signs out and reloads - leaving stops the
music, unlike a session that ends. Its footnote names the Navidrome account - or, for the break-glass
`admin`, the break-glass password and its 12 hours (no Navidrome account is behind that one).

**The main page** (`components/SignedOutNotice.tsx`, from `ui/src/main.tsx`): any 401 - and, with the
mark, `/deadwax/me` asked once as it loads, since main.js's own fetches don't go through http.ts - draws
a plain notice over the page (`#main-container` inert) with **Sign in** to `/player/?return=/`. No login
of its own: it retires. The downloads panel's failing poll isn't logged as an error once the notice is up.
While the notice shows, `/me` is asked again as the page comes back to the front or out of the
back-forward cache; a 200 reloads the page (its panels gave up while signed out) - so Back after the
round trip, or a sign-in in another tab, doesn't leave "You're signed out" over someone who isn't.

**Verified**: 2540 Python tests (2538 passed, 2 skipped; 76 new - tests/test_logins.py and
tests/test_logins_css.py), pyflakes, tsc, every sim (ui/test/signin.sim.cjs new), the build; the engine
files have no diff. Mutation-checked: the walk (a router included without its dependency; an admin
route's guard removed), the throttle's count, the constant-time compare's digest, the re-check's error
40 (and Navidrome down ending nothing), the cookie's HttpOnly and SameSite, the encrypted credential,
the reserved names, the gate's overlay over the app (not in place of it) and its same-person carry-on.

**After review** (each a test that failed without its fix, then 31 mutations each caught): the late 401
(above); media errors asking `/me`; Back after the main page's round trip (`location.replace`, the
re-ask on `pageshow` and while the sign-in shows, the main page's reload); focus given back and the
reason as the dialog's description; the break-glass footnote; the throttle that could be flushed. Tests
that pinned too little, now pinned: sign-out ending a session HELD in memory (used before signing out)
and clearing the cookie at `Path=/`; error 40 ending the session in the database too (replayed after
`forget_sessions`, a restart); the lifespan starting the re-check only with logins on (the suite's
first test to enter the lifespan, everything it touches stubbed) and `run_session_checks` pausing
`CHECK_EVERY_SECONDS` and outliving a failed pass; `Config.logins_on` - not only `describe_auth_mode` -
on for a typo; the start-up error for a missing or short key (which said "every page" answers 503; the
pages answer 200 - now "every request but the health check and the pages"); the identity lowercased
when Navidrome answers with the stored case (the fake now can: `stored`); the sweep of expired sessions;
a check moving `checked_at` on; a held session re-read after `CACHE_SECONDS`; the sim's password field
actually typed into before "the password gone".
**After the second review** (each a test that failed without its fix, then 17 mutations each caught):
the app page opened with logins off reloading at its first 401 (`reloadWhenLoginsComeOn`, once, the
minute's guard, regardless where storage is refused); full screen left as the sign-in comes up, the name
field focused once it has; a failed expiry write letting the request through (`_touch` best effort -
tried once, not lengthening the expiry, a later read still ending it). Tests that pinned too little, now
pinned: the sim's fake page records each listener's options and sends an element's error to CAPTURE
listeners only, as the browser does (losing `true` passed every sim until then); the late 401 through
`fetchOk` as well as `get`; a `/me` failing without a 401 over the running app (a TypeError, a 503)
leaving it alone (dropping `|| appShown` passed until then); the lifespan logging the missing key (it
only called the words' test directly - the call could be deleted); the sign-in client's
`describe_navidrome_url` refusal (never reached: the fixture built the client with a good address).
**Real page** (an instance with logins on over a stand-in Navidrome checking token auth for james and
ethan, headless Chromium as deadwax.test over plain http, 390x844, 320x568 and 1440x900): the sign-in
alone, focus in the name field, fields 16px+, nothing past the edge at 320; a wrong password said;
james with Managing in You and the sidebar; Sign out back to the sign-in; ethan with neither, and an
admin route answering him 403 in words; with Navidrome stopped, ethan told it isn't answering and the
break-glass admin signed in; logins off on another instance: today's app, no mark, no stylesheet, "Logins
are off", no Sign out; the main page's notice, its link to the app's sign-in and back to `/`; ethan's
password changed in the stand-in while a song played: the re-check signed the session out, the sign-in
screen came back over the app (still mounted, inert) saying why, the music carried on (for the
seconds watched - what follows is in "What a session's end cuts"), and signing in
with the new password carried on with no reload. No console errors (the main page's signed-out downloads
poll quieted). After the first review, the same way (logins on, 390x844 and 1440x900): a session ended
on the server under a playing album, nothing tapped - the next song's stream answered 401, the media
error asked `/me` (401, no scrobble in between, in the server's log) and the sign-in came up over the
app saying why, focus in the name field; signing in again carried on; focus given back to You's Sign out
after signing in again; the break-glass footnote; the main page's round trip leaving no
`/player/?return=/` in the history, and Back then the main page signed in with no notice. After the
second review: an app page opened with logins OFF (390x844), deadwax recreated with them on under it,
the page hidden and shown (its visibilityState stood in for - headless never hides a page): its asks
(`/me/pins`, `/download/jobs`) answered 401, the page reloaded itself with the mark and opened at the
sign-in, focus in the name field, and ethan signed in; the visualizer in full screen at 1440x900 under
james, the session ended on the server, the next ask's 401: full screen left, the visualizer closed, the
sign-in what shows in the middle of the screen with focus in its name field, signing in again carrying
on with no reload - and with `leaveFullScreen` disabled in a control build, the sign-in stayed hidden
behind the visualizer. No console errors. **NOT verified**: on James's iPhone (the home-screen app's cookie across launches, Safari's
handling of a SameSite=Strict cookie on the app's launch, the keyboard over the sign-in card); against a
real Navidrome 0.64 (its getUser and its own failure limits are read from its source, not watched); a
proxy terminating TLS (Secure by `X-Forwarded-Proto` is tested, not seen); how far Safari plays the song
it has when its session ends (it fetches by range - likely seconds); the back-forward cache and
`pageshow` on iOS; the media-error ask in Safari on the iPhone and in the home-screen app, locked and
unlocked (seen only in desktop Chromium); whether iOS keeps the home-screen app in memory across a
container recreated with logins on, and its reload into the sign-in there; leaving full screen in Safari
and Firefox (the webkit form is in, unwatched).

### Downloads per person (2.0.0-player.49)

Step 4 of the multi-user plan (the Claude Doc's "Requests and downloads"), closing the one gap
"Logins and roles (2.0.0-player.48)" left: every signed-in user saw, and acted on, the whole queue.
Every rule was decided with James on 2026-09-27 - don't re-open them. The spec is
`deadwax-scratch/uplan/slice-downloads-per-person.md`. **With logins off nothing changes**: one user,
`local`, the admin - every existing test passed unchanged, but for the changes on purpose listed at
the end - downloads somebody asked for while logins were on included (review): `/jobs` lists every
download (`list_jobs()` with no user, as before), Clear finished deletes every finished one
(`delete_jobs`, tidying every cancelled one first) and `/enqueue` refuses one already on its way
(its join runs only with logins on). The one change logins-off sees, by the rule itself: a download
failed and moving to its next peer by itself counts as in flight (below), so a Find in those seconds
stops at it - worded "failed - moving to the next peer", nothing said about cancelling it for one.

- **Requesters are their own table**, `job_requests` (job_id, user, requested_at, left_at, hidden_at;
  store.py's schema says what each means): `jobs.username` is the Soulseek PEER, and several people
  can want one download. `create_job(..., user=)` writes the job and its asker's row in one
  transaction. A database from before the table gets it once (`JobStore.init`, only when the table
  didn't exist): every job `local`'s, asked when it was made - so a later start never hands back to
  `local` what an admin took. `adopt_local` moves local's requests with its pins and preferences (it
  answers `(pins, preferences, requests)` now - test_pins.py's three tuples changed with it), and -
  review - not only at a sign-in: `auth._take_over_leftovers` hands what `local` still holds to the
  FIRST ADMIN SEEN with a session after a start (`store.local_has_anything`, then `adopt_local_now`,
  its synchronous write, in FastAPI's thread pool; once a process, best effort, a failure logged and
  left to the next sign-in). A session lasts 30 days from its last use and outlives a restart, so an
  admin may never sign in again: an upgrade from .48 with logins on (every download became local's as
  the table was made) or logins switched off and on again left their rows "Asked by local" and the
  finished ones undeletable (`local`'s request kept them). Logins only change at a restart, and
  `local` gains nothing while they're on, so once is enough. One
  definition of a request still waiting, `ACTIVE_REQUEST` (asked, not left, not hidden), read by the
  list, a cancel and a clear alike. No foreign keys (the connection doesn't enforce them): rows are
  deleted with their job, by hand (`delete_jobs`, `hide_finished`).
- **Who sees what** (`list_jobs(user=, everyone=)`, `routes/download._per_person`): a user their
  active requests (joined ones too); an admin everyone's but what they hid. With logins on each row
  carries `mine` and `shared` (somebody else is waiting on it), and for an admin `requested_by` - the
  OTHER requesters, in the order they asked (`ORDER BY requested_at, rowid`). Off, none of the three
  (the payload as it was). The app draws an admin's row "Asked by ethan" / "Asked by you and ethan" /
  "Asked by you, ethan and sam" (`lib/perPerson.ts askedByText`) - and, review, a user's row of a
  download somebody else waits for too "Someone else asked for it too" (`SHARED_TEXT`, nobody named),
  so a Get that joined somebody's download and a ✕ that will only leave aren't a surprise - under the
  line of every card - Downloading, Waiting, Needs attention, Done - and the main page's Downloads
  panel beside the user. Requests, Home's Arriving and
  the badge draw whatever `/jobs` gives, so they follow by themselves; the event log stays the
  admin's, and a user's failures show on their own rows.
- **Acting on somebody else's**: `_job_for` answers 404 - as for no job - to a user who isn't an
  active requester of it, for cancel, retry and retry_same (a user can't even learn the id is real);
  an admin may act on any.
- **Joining**: `/enqueue`, under the release's lock, finds the whole pressing already coming
  (`store_index.in_flight`) for somebody ELSE and adds a request instead of refusing -
  `{"queued": 0, "job_id", "joined": true}`, nothing asked of slskd - with logins on only (review: with
  them off `local` is missing from every download asked for while they were on, and joined one of those
  instead of the 409). The same person asking twice is
  still the 409 ("already downloading from bob") - guarded twice, by the route's requester check and
  by `request_job` answering `'waiting'` for someone already waiting (each alone passes the test; both
  removed fail it). `request_job` answers `'joined'`, `'waiting'`, `'gone'` or None, and writes only
  while the job's row is there, in its IMMEDIATE transaction (review: a Clear - which takes no release
  lock - deleting a complete-while-filing or retry-pending job between a join's look and its write left
  a request pointing at nothing, and answered `joined`): the join route then answers its "cleared from
  the list since" 409, and `/enqueue` falls through to `already_have` - nothing on its way now, so the
  Get fetches it. `POST /download/jobs/{job_id}/join` is the explicit join the store line's button
  makes: under the job's lock, only a download `still_coming` and whole (`store_index.is_whole`),
  else a 409 in words ("that download has been filed into the library since - get it again to see
  where it stands", "brings only part of this pressing"); `joined` false when already waiting. A
  download not there at all - the usual way: the last who asked cleared it after the page drew its
  line - is the same "cleared from the list since" 409 (second review: the first look answered 404
  "No such download job", so the words the docs promise came only in the race; a join has no id to
  hide, unlike cancel and retry).
  `store_state`/`find_candidates` describe a download in flight with logins on as `yours`, `shared`
  (somebody else waits for it - review) and, for an admin, `requested_by`, plus what
  its copy is (`describe_job`: `formats` - the candidate's, else read off the files' names - and the
  `bitrates`, `bit_depths`, `sample_rates`, `variable_bitrate` it was picked with). For that a Get
  now sends the picked folder's `quality` (and each runner-up's), kept as `jobs.quality_json`
  (JOB_COLUMNS; `job_quality` keeps only those keys) and taken on by a retry to the next peer (the
  same peer asked again keeps it). Find still doesn't search for a pressing downloading whole: the
  box stands where the sources would (`lib/perPerson.ts storeStatusFor`): "Already downloading for
  someone else", "From glassbeads · FLAC 16/44.1 · 3 of 11 files" (`copyText`: the copy as a source
  card's Quality says it, `qualityText` - review: it was "FLAC 902kbps 16-bit 44.1kHz", a bitrate the
  cards never show for lossless, in an order neither page uses), the quality
  floor's word when the copy falls short of You's floor ("It's below your quality floor (24-bit), and
  getting a copy of your own isn't offered yet." - or "Its folder doesn't say whether it meets…"
  when the folder didn't report what the floor asks about; judged by the floor's own rules through
  `passesFilters`; the app's only - the main page has no per-user floor), then what Join does
  (`joinNote(place)`: "Join it to have it in your Requests too - one download, everyone who asked
  waiting for it.", Downloads on the main page - review: it named Requests there, and "both of you"
  however many waited), and `JoinDownload` (StoreState.tsx - its own component, keyed on the job, so
  StoreState stays a leaf): the tap asks at once, waits aria-disabled, says a refusal in an alert, and
  gives way to "Joined - it's in your Requests." - handing the focus it had to the store box
  (`keepJoinFocus`; the box is `tabIndex={-1}` and stays drawn through the album page's next look, so
  focus is never dropped to the page - review), and on a desktop at the frame's control size, as Get
  is (`.app-desk .app-store-join` - review). In the Sources sheet a join
  hands over to Requests as a Get does - only while the sheet still shows the Get that joined; on the
  album page the line asks the store again and becomes yours; the main page's candidates panel has
  its own Join ("Joined - it's in Downloads."), in `components/StoreStatusBox.tsx` since the review
  (out of CandidatesPanel, so sources.sim draws it; aria-disabled while it waits, never `disabled`,
  which dropped the focus, and its focus handed to `.candidates-store`). The album page asks You's
  settings each time it shows (`useGetSettings(shown)`), beside the store, so the floor's word is in
  hand as the line draws - added to useGetSettings' and app-requests-search-get.md's lists of when
  they're asked (review: a gate on `yours === false` was weighed and left - the floor line would then
  land after the line had drawn, in the polite live region). Every downloads list in the page asks again after a
  join (`lib/downloadRequests.ts` `joinDownload`/`onDownloadsChanged`, which `useDownloadJobs`
  listens to). The box's Join never picks for you - "Pick the best source for me" doesn't join from
  it - but a Get, a pick for you included, that reaches `/enqueue` just as somebody else's download of
  the pressing has started joins it (the race the spec makes a join): the app says so afterwards -
  the row in Requests is that download, from its peer, "Someone else asked for it too" - and the main
  page's card says **Joined ✓** with why, not "Queued ✓" (review: the answer's `joined` was read
  nowhere).
  **Not in this step, on purpose**: "start your own" when the copy is worse than your filters, and
  "when it lands it replaces the worse copy for everyone" - that is deadwax deleting audio by itself,
  refused at three layers today (notes/store-index.md "Not built, on purpose"); James's to design.
  The box says a copy of your own isn't offered yet.
- **"Downloading now" counts every state in between** (`store.still_coming`, the one predicate
  `in_flight_job` and the join route read): queued, downloading, `complete` in the seconds before
  filing (organizing on), `organizing`, and - new - `failed` with a retry pending: the poller's
  `_fail` marks the job in `store_index._RETRY_PENDING` (memory: one process runs one poller) from
  just before it writes `failed` until `_auto_retry` has had its turn (AUTO_RETRY_PEER on, a
  runner-up left), so a second person's Get in that moment joins it instead of starting a download the
  retry would then refuse. Find's answer for one says `status: 'failed'` and claims no files in
  (`_describe_in_flight` sets `done_files = files` for the filing statuses only), and the store line
  says "failed - moving to the next peer" (`downloadProgressText`'s one new case) with nothing about
  cancelling it for another peer (`storeStatusFor`) - review: it read "From bob · failed" under
  "Already downloading", and told you to cancel it for a peer it was already moving to. Logins on or
  off: the rule counts it either way. The poll loop's two failures (refused, never reported) go
  through `_fail`, and `_fail`'s `finally` clears the mark when the retry raises - both pinned since
  the review.
- **The per-release lock** (`store_index.release_lock`, since step 2) covers the check, the join,
  slskd's enqueue and the job insert for everyone: two people's Gets of one release at once make one
  download and one join (tested through two concurrent signed-in clients). Cancel and join take the
  same lock (`poller.job_lock_key`, formerly `_retry_lock`), so a join never lands between a last
  request leaving and the download being cancelled.
- **Cancel means leave** (`store.leave_job`, one IMMEDIATE transaction): a user's cancel withdraws
  their request (`left_at`) while somebody else's is active - `{"left": true}`, slskd untouched, the
  download carrying on; the LAST active request's cancel leaves the row as it is and cancels the
  download itself (`_cancel_download`, today's body: slskd's transfers, the status, the tidy, the
  partials under SLSKD_INCOMPLETE_PATH), so the last one sees it cancelled and can retry it. An
  admin's cancel is always the download's - for everyone, theirs shared included. The app's ✕ asks
  what it will do (`cancelWords`): a user's on a shared download "Leave this download? Someone else
  asked for it too, so it carries on for them." / **Leave it**; an admin's on one somebody else waits
  for "Cancel this download for everyone? ethan asked for it (too)." / **Cancel for everyone**;
  anything else the words it always had. The main page's confirm() says the same for a shared one.
  Review: a leave is a leave everywhere - the ✕ and its question are named "Leave …" (`cancelWords`'s
  `leaves`), the card reads "leaving…" while it is asked and is heard so, and once the row has gone
  from your list (the one way a tap takes a card away) the page says "<album>: left - it carries on
  for whoever else asked" and puts the focus on the card beside it, else the page's heading
  (`requestsView.changes`' `gone`, `focusAfterGone`, Requests.tsx's layout effect) - it fell to the
  page. And the store line of a download of yours somebody else waits for too, as a user, says
  "Someone else asked for it too, so cancelling it in Requests only takes it off your list - another
  peer isn't offered for a download you share." instead of "Open Requests to cancel it if you want
  another peer" (`sharedNote`, `leavesOnCancel`: `shared` and no `requested_by`) - a cancel that only
  leaves gives no other peer, and the next Get would join it again. An admin's line is as it was: their
  cancel is for everyone. A double-tapped ✕ (two cancels from one person at once) leaves once and
  cancels nothing - `leave_job`'s `'none'` is the 404 - and a join can't land between the last leave
  and the cancel (the job's lock): both pinned with requests really at once since the review.
- **Retry is open to any requester**, and an admin: the one job moves (`move_to_peer`), its
  requests the job's, so everyone waiting moves with it. A requester who had cleared a failed job
  from their list isn't waiting for it and stays cleared: `move_to_peer` turns their hidden request
  into a withdrawn one (`left_at`, `hidden_at` cleared) - review: an admin who had asked too and
  cleared it kept `hidden_at`, so the download running again was in nobody's view of theirs, with no
  ✕ to cancel it; now an admin sees it again, as one who never asked does. Asking again (a Get, a
  Join) brings either back.
- **Clear finished hides it for you** (`store.hide_finished`, one transaction): every finished
  download in the asker's list gets their `hidden_at`, and a job is deleted once no request on it is
  active (`_nobody_else`). An admin hiding somebody else's gets a row that is NO request
  (`requested_at` NULL), which never keeps a job - and `move_to_peer` deletes such rows, so a download
  an admin cleared shows again once it's retried. Before deleting, only the cancelled jobs this clear
  will really delete have their transfers tidied out of slskd's list (`jobs_to_forget`). `removed` is
  how many left the asker's list. With logins off the route keeps its old body - every finished job
  deleted (`delete_jobs`), every cancelled one tidied first (`jobs_with_status`) - whoever asked for it
  (review: `hide_finished('local', everyone=True)` only hid a job somebody had asked for while logins
  were on, so it came back to their Done list once logins did). Not changed: Clear still deletes a
  `complete` job in the seconds before filing, and a failed one whose retry is pending, though both
  count as coming (Clear's statuses are older than this step; a join racing it is answered above).
- **One Soulseek search starts at a time, across all users** (`slskd_endpoint.SearchGate`,
  `SEARCH_GATE`): slskd's limiter (SemaphoreSlim(1,1), Wait(0)) covers STARTING a search, and one
  person's Find always started its searches in turn - two people's at once could collide, and one
  Find failed "slskd is already running a search". Each start now takes the process-wide gate,
  held until slskd has answered that start (the cancel-mid-start path included), waiting in line
  `SEARCH_TURN_SECONDS` (30) at most and then starting anyway - never refusing. A turn is bounded
  too (review): one still in its start after the bound gives its place up itself (a `call_later`
  timer, cancelled when the turn ends in time; the turn then never releases the lock again, so a
  stuck start that does end leaves the next holder holding it). slskd_api sends with no timeout and
  the start's thread can't be cancelled, so a POST never answered (a connection dropped without a
  reset) held the gate for the life of the process, and every later start - anyone's, each name's
  query - waited the whole 30s behind it; now it holds up the line once. The listening for
  answers is shared as before. The lock is made per event loop (the tests run a loop each). Two tabs
  or two people inside deadwax no longer meet slskd's 429; another client starting a search at that
  moment, or a start the gate lets through after its bound, still can - slskd_endpoint.py's comment
  and notes/backend-gotchas.md say so since the review (they still blamed "two tabs").
- **Organizing must be on** (`Config.describe_logins_organizing`): with logins on, `ORGANIZE_MODE`
  `copy` or `move` and both of organizing's folders set - under dry_run nothing is filed, so nothing
  could be granted or deduplicated. Otherwise `auth.unusable()` says why, exactly as for a missing
  secret key: every protected route and the sign-in answer 503 with it (the app's sign-in screen
  shows it; the break-glass admin is refused too), the health check and pages stay 200, and
  `report_logins` logs it at start-up - saying where the value comes from: a mode saved in the
  settings tab (OVERRIDDEN) beats compose, and with logins refused the tab can't be reached, so the
  way back is logins off. To keep an admin from locking everyone out from inside, the settings PUT
  refuses, with logins on, a batch that would leave organizing off (a value, or a revert to an
  environment that says dry_run - `_stops_organizing`). test_logins.py's `on` fixture sets copy and
  both folders for this (changed on purpose).
- **Changed on purpose** in existing tests: test_logins.py's ROUTES (the join route; the comment on
  the gap) and its `on` fixture (organizing on); test_pins.py's three adopt_local tuples. In the sims
  (review): requests.sim's `changes` checks read `said` and `moved` (it answers `gone` too), and a
  user's shared row now says "Someone else asked for it too" where it said nothing.

**Verified**: 2698 Python tests (2696 passed, 2 skipped; 61 new - tests/test_downloads_per_person.py,
35 at first, 20 from the review and 6 from the second), pyflakes, tsc, every sim (requests.sim.cjs,
sources.sim.cjs and, since the review, group.sim.cjs - the album page's Join asking the store again -
extended), the build; the engine files have no diff. Mutation-checked, 49 rules, each test failing with its rule broken and the file restored
byte for byte (PYTHONDONTWRITEBYTECODE - a stale .pyc of the same size and second hid two at first):
the migration's once, the asker's row, a user's own list, requested_by the admin's, the 404, joining
on Get, the same person refused (both guards together), the join under the lock (moved outside, the
concurrent test failed), `yours`, join only what's coming and whole, retry pending in flight and the
poller marking it, the last leave and a leave, an admin's cancel for everyone, retry by either, hide
for you and delete once everyone has, an admin's hide being no request, a retried download showing
again for the admin, clearing tidying only what it deletes, adopt_local's move and copy, the search
gate and its bound, organizing on and its folders, start-up saying so, the settings refusal and a
revert counting, the quality kept and taken on by a retry, logins off sending no new fields, the route
walk; and in the UI the joinable box, the floor's word, unknown not below, who asked, a user's leave,
the card's line and the question's words, Join offered, waiting, its refusal, Sources handing over -
only while it shows - and judging by your floor. **Not mutation-checkable**: `leave_job`'s IMMEDIATE
transaction (two last requesters leaving at once - the test passes without it too; the race is
microseconds wide). **The review's fixes**, mutation-checked the same way (each test failing with its
fix undone): logins off refusing rather than joining, and its Clear deleting and tidying as before;
the first admin seen taking local's over (an upgrade's and an off-and-on's, an admin's never a
user's, looked for once a process and again after a restart); a retried download's hidden requester withdrawn (an admin seeing it, a user
staying cleared); a join for a job gone writing nothing, the route's 409, Get falling through; Find's
`shared` and an admin's `requested_by`; a download moving on claiming no files; the poll's two
failures through `_fail`, and its `finally`; re-joining after a leave, and after clearing one still
coming; blanking
SLSKD_DOWNLOAD_PATH refused, and logins-off saves allowed; a second cancel's 404, the cancel's and
the join's locks; the order they asked (three wrong orders); the same peer keeping the quality,
adopt_local keeping the admin's own row, job_quality's keys; the join's 503; and in the UI the copy's
words, Join's note (its place, no count), "moving to the next peer" and no cancel line for it, your
shared one's line (and not an admin's), a user's shared row, "leaving…" and its announcement, a left
card heard and its focus to the next card or the first, the ✕ and its question named Leave, Join's
focus to the box (only when the button had it; the box a target), the main page's box waiting
aria-disabled, joined, refused and its focus, a join telling every list, the album page asking the
store again. Not covered by a sim: the main page's "Joined ✓" card (CandidatesPanel isn't drawn by
any) - tsc and the real page only. **The second review's**, the same way: a turn still starting
after the bound giving up its place (and only it - a turn ended in time leaves no timer, a stuck one
that ends leaves the next holder holding); a join of a download cleared before the tap, and of no
such id, the "cleared since" 409; SLSKD_DOWNLOAD_PATH's half of organizing's folders (only
LIBRARY_PATH's was pinned, so "organizing on and its folders" above was half true); the cancel's
re-read under the job's lock, with a retry holding it (an admin's cancel and the last requester's);
and in the sims, three that were pinned only through pure helpers: a Get's body carrying its
folder's quality and each runner-up's (sources.sim read only the usernames), useDownloadJobs asking
again after a join (requests.sim had only its own stand-in listeners), and Requests putting the
focus where a left card's went (requests.sim stubbed every layout effect away: it runs Requests'
now, against a stand-in document whose cards are found by `data-row`).
**Real page** (dl49's own instance, logins on, a scratch database, a hard-linked library copy, a
stand-in Navidrome checking token auth for james and ethan, its own fake slskd; two headless
Chromiums as deadwax.test over plain http, 390x844 and 1440x900; 48 checks in two drivers, and one
more on a third instance): james Got Dummy from the
sources; ethan's album page said "Already downloading for someone else · From glassbeads · FLAC
902kbps 16-bit 44.1kHz · queued" with Join, which joined (the line then said it's his, Requests had
it, no names); james's row said "Asked by you and ethan"; ethan's ✕ asked "Leave this download?…" and
Leave it took it from his list while it went on for james (his row naming nobody); ethan's own
download asked the plain question and his cancel - the last - cancelled it, still listed for him;
james saw it under Needs attention "Asked by ethan" and his Next peer moved it for both ("try 2");
ethan joined Dummy again and james's ✕ asked "Cancel this download for everyone? ethan asked for it
too.", cancelling it for ethan; ethan's Clear done hid it from him alone, james's then deleted it
(no job row, no request rows); the main page's Downloads panel showed ethan only his, and james "Asked
by you and ethan"; the Sources sheet (phone and the desktop panel) stood the box with Join where the
cards would be and handed over to Requests; logins off (another instance): no new fields, the old
question, cancel and Clear done as before; logins on with dry_run (a third): 503 with the reason on
every route and the sign-in screen saying it, health 200. No console errors, nothing past the edge at
390. **The review's fixes on the real page** (the fixer's own instance, logins on, a fresh database, its
own stand-in Navidrome and fake slskd; two headless Chromiums as deadwax.test over plain http, james
at 390 and ethan at 1440x900; 15 checks): james Got Dummy from the sources; ethan's album page said
"From glassbeads · FLAC 16/44.1 · 0 of 11 files" and "...one download, everyone who asked waiting for
it.", its Join 14px and 34px tall as Get; Join from the keyboard (Enter) left the focus on the store
box - as "Joined" showed, and after the line became his ("Someone else asked for it too, so
cancelling it in Requests only takes it off your list..."); in Requests his Dummy row said "Someone
else asked for it too" (no names), its ✕ "Leave Dummy" and the question "Leave Dummy?", and Leave it
from the keyboard took the row away with the focus on his other card and the live region saying
"Dummy: left - it carries on for whoever else asked", the download still going for james; no console
errors. Not looked at there: the main page's store box and its "Joined ✓" card, and the Sources
panel's Join (sim-checked).
**NOT verified**: on James's iPhone (Join and Leave it under a finger); against a real slskd with
two people searching at once (the 429 is read from slskd's source and rehearsed with a fake that
refuses an overlapping start); the copy's quality for a download started on the main page before this
version (none kept: the format alone, from its files' names).

### Personal libraries (2.0.0-player.51)

Step 5 of the multi-user plan (the Claude Doc's "Personal libraries as Navidrome favourites"). Every rule
was decided with James on 2026-09-27 (option B: one Navidrome library; "your library" is that user's
Navidrome FAVOURITES - starred albums - two-way with Amperfy) - don't re-open them. The spec is
`deadwax-scratch/uplan/slice-personal-libraries.md`. The pieces: `src/library_ledger.py` (the rules, pure but
for the worker's wake-up and the retag marks, and `grant_job`, which writes what `grant_for` decides),
`src/stars.py` (starring as each user and reading their stars back - a lifespan worker), store.py's five
tables (library_membership, user_credentials, library_flags, library_seed, store_index_scanned) and their
methods, `src/routes/my_library.py` (`/deadwax/me/library`, a user's) and
`src/routes/held.py` (`/deadwax/library/held`, an admin's) - all seven routes in test_logins' ROUTES.

- **The ledger** is `library_membership` (user, album_id, added_at, how, state, incomplete, navidrome_id,
  starred_at, removed_at, removed_why, seen_at, attempts, next_try, problem; store.py's schema says what
  each means), keyed on `store_album.id` - never a path or a release id, both of which an apply or a
  re-file changes. `how`: grabbed | added | seeded | starred (elsewhere). `state`: waiting | starred |
  removed (`removed_why` unstarred | deleted | dismissed). `seen_at` NULL is the new marker.
- **Grants on every way a download ends** (`grant_for`, from organize_job's results and the plan's new
  `same_release` - whether the folder already held this release BEFORE anything was written; reading it
  files nothing differently): filed - ADDED; every file already there - ADDED in the same release's
  folder (a second copy of a release held is never filed beside the first: organizer's duplicate rule,
  v1.0.1), FLAGGED in an untagged or other folder (`library_flags`, a row of its own so the requesters
  clearing the job can't lose it before an admin looks; the event log says so too); some files failed -
  INCOMPLETE when a track landed (entries `incomplete`), nothing when none did; a dry run, nothing that
  could be filed, filing that raised - nothing. Each ACTIVE requester (`store.requesters`: asked, not
  left, not hidden) gets it - who left gets nothing - and only one who can have a library
  (`library_ledger.has_library`: never the break-glass admin, whose entry would never be starred or
  shown yet would count as held; with none left nothing is recorded). With logins off a FLAGGED filing is
  neither flagged nor said nor recorded on the job (Held by nobody isn't drawn then, and the flag would
  outlive logins-off naming `local`). Written before the status moves on, so a row never
  reads "filed" a poll before it says what it gave, and kept on the job (`jobs.album_id`,
  `jobs.library_grant`, JOB_COLUMNS) for the row's words: `/jobs`' `library`, with logins on only.
- **"Nothing could be filed" offers the next peer** (the plan's table), with logins on: `job_outcome(...,
  not_filed=True)` answers `not_filed` for NOTHING_ORGANIZED, ORGANIZE_FAILED (both now named in
  poller.py, the words unchanged) and "…, no track was filed"; `poller.retryable` takes it, so the retry
  route, `_fresh_job` (the next peer's only - Ask again stays failed/cancelled) and `/jobs`'
  `alternatives_left` do too, and list_jobs - passed `poller.NOT_FILED_PATTERNS` (LIKE patterns of those
  three messages) by the jobs route with logins on only - reads the runners-up of those rows and no other
  finished one (review: every `complete` row with an error, dry runs above all, doubled the poll). The
  app puts the row under Needs attention with Next peer and no Ask again (the same files would fail the
  same way); the main page's row shows ↻ next peer alone. With logins off: as it was (None, Done, a 409) -
  the spec's "nothing visible changes".
- **Starred as the user** (`stars.star_entry`): the album found with search3 by its release id, then its
  title, believed only on its own musicBrainzId (`find_album` - the bridge's rule, but RAISING, so a
  refused login never reads as "not found"; the bridge's id cache shared, imported lazily: the bridge's
  module reaches the poller, which reaches library_ledger); `star`; then getAlbum's `starred` as the
  user - `star` answers OK for any id. Not found (`not_in_navidrome`), not confirmed (`not_confirmed`),
  folder gone (`missing`), no release id (`no_release`): the entry waits, `next_try` 30 s doubling to
  1800 s (`retry_after`), for ever. Navidrome unreachable: said on the entry and on everything the user
  has waiting (`ledger_note_waiting`), NOT counted, and the pass stops. Every call through `AsUser` - the
  login laid on last - and `star_client`, a LoginClient of its own held to describe_navidrome_url. Never
  NAVIDROME_USER's login, never Navidrome's admin.
- **The credential per user** (`user_credentials`): the sign-in seals the token and salt ONCE and keeps
  the same string in the session and here (`_keep_for_library`, in the thread pool as every write of the
  sign-in is - review: on the loop, a writer holding the lock stalled every request and stream; best
  effort; it also asks about everything of theirs waiting at once). Sign-out leaves it (the point: starring while nobody is signed in). It dies
  - `dead_at` - when the worker's call is refused (error 40) or it won't open (another key), and when the
  re-check ends a session with LOGIN_GONE or KEY_CHANGED - only if it is still THAT login
  (`credential_dead` compares the sealed string; a newer sign-in's stands). A user signed in before this
  table existed gets their newest session's credential copied in (`live_credentials`), so an upgrade from
  .50 with sessions kept stars without anyone signing in again.
- **Read back** (`sync_user`, every SYNC_SECONDS = 300 per user, and at the worker's first pass after a
  start): getStarred2's ALBUMS only (songs and artists stay ordinary favourites), by musicBrainzId. Held
  and starred there: confirmed (a waiting one becomes starred; a new Navidrome id taken). Starred there
  and in the store (`index_present`) but not held: added (`ledger_sync_add` - how starred, new; an
  unstarred one held again). Held as STARRED by deadwax and not starred there: looked up again - not in
  Navidrome, or back under another id than the one starred: the star was LOST (mid-retag, between
  scans), so it waits as `star_lost` and is starred again at once; the same id and getAlbum not starred:
  unstarred - removed, conditionally on the entry still being that star (`ledger_remove ... AND
  navidrome_id IS ?`). Never for an album not present or being applied to right now
  (`library_ledger.retagging`, set by `retag_apply` around the whole apply, released in a `finally`).
  Pins stay deadwax's own. **The first read-back** of a user (`user_credentials.synced_at` NULL) adds what
  it finds SEEN: favourites from before deadwax kept a ledger are theirs, not news (review: three hundred
  favourites were three hundred New marks); every read after it marks an add new. It counts as done -
  `synced_at` written - only when the index knew the store as it began (`index_scanned`: the root in
  `store_index_scanned`, asked before getStarred2, so a first scan finishing mid-read doesn't count it):
  before the library's first scan `index_present` finds none of the favourites, and the next read, no
  longer the first, added every one New (second review - a fresh install, or an upgrade from main whose
  saved scan is in an older SCAN_FORMAT; a sign-in kicks the worker, so the read-back won that race every
  time). Until then each read is the first, so a star made before the first scan isn't new either.
  **A getStarred2 answered with an error** - a Subsonic failure other than 40, an HTTP status, a body
  that isn't JSON - is that user's alone (`SyncRefused`): logged, their sync backed off to SYNC_SECONDS,
  their starring still run, nobody else's pass stopped (review: it stopped every pass at that user, so
  nobody after them in name order was starred, and called it "Navidrome isn't answering"). Unreachable
  still stops the pass; error 40 still kills the credential.
- **The worker** (`run_library_worker`): a lifespan task with logins on and a database (beside the
  re-check), a pass every WORK_SECONDS = 15 s or at a `kick()` (a grant, a sign-in, Add, a flag added, an
  apply's re-star - call_soon_threadsafe on the worker's own loop; nothing with no worker), STAR_BATCH =
  25 a user a pass, another pass at once after a full batch. One task, so its Navidrome calls are one at
  a time. With logins off `work_once` does nothing even if credentials are kept. "A full batch" counts
  only outcomes the ledger took (`star_due`'s `written`; `star_entry` answers None for a write that
  didn't land): a full disk, or /config refusing writes while reads work, left the same 25 due and asked
  for another pass at once, for ever - thousands of Navidrome calls a second (review). Now it waits for
  the next pass.
- **Seeding** (`seed_library_now`, once ever): every present album into the first admin's library,
  waiting, SEEN (no news), except one a download of somebody else's (not theirs, not `local`'s) brought -
  an entry `grabbed`, still held - at their sign-in after adopt_local, or at the first-admin take-over (`_take_over_leftovers`, after its adopt, in
  its own try: a session outliving the upgrade). Ethan's starts empty. **Held over until the store index
  knows the store** (review): a sign-in before the index has been filled from a scan of the root
  (`store_index_scanned`, written by `index_reconcile` when its scan found albums - a real scan, or the
  saved scan at start-up; at init, every root a pre-.51 index already holds is counted, so an upgrade
  from .50 seeds at the sign-in) records the seed as `library_seed` with `seeded_at` and `albums` NULL
  and the admin's name, says so in the event log, and the first scan that finds albums does it, in its
  own transaction (`_seed_rows`, shared). Without this, a fresh install with logins on - or an upgrade
  from main, whose saved scan is in an older SCAN_FORMAT - seeded what little the index held and was done
  for good, every album the first scan then found belonging to nobody. A scan that found nothing finishes
  nothing (an unmounted share looks like that); an index that knows the store but holds only others'
  downloads seeds nothing and is done: an album arriving afterwards without a request belongs to nobody.
  **Once because of the look before** - `library_seed.seeded_at` set, read under BEGIN IMMEDIATE (and
  `index_reconcile`'s own `seeded_at IS NULL`): the one row (`id = 1` CHECKed) only records whose seed it
  is, when it was done and how many it held, or that it is held over, and its write is an upsert since
  the hold-over, so it would take a second seed without a word (second review: the notes called the two
  "guards, each alone enough"; breaking the look alone fails four tests). **Only a grant leaves an album
  out** (second review): an album somebody else holds because they starred it in Amperfy - their first
  read-back, which a worker pass 15 s after an upgrade's restart can run before the admin's first
  request, adds their favourites from before - or added it from the store was in the store already, and
  libraries aren't exclusive, so both hold it; leaving those out made the seed's outcome hang on whether
  that pass had run first, for good. A grant, `grabbed`, is an album their download brought (or one
  their download found already there - an edge left as it is: it came with their request).
- **Logins off**: `local` is given what it files - silently kept, never starred, never shown (`/me/library`
  answers `{"on": false}`, `yours` and `library` aren't sent, `holders` isn't either, a flagged filing is
  neither flagged nor said) - and adopt_local
  moves local's entries to the first admin (`local_has_anything` counts them; moved seen, so nothing of it
  is "new"; not in the three counts said). Why kept rather than not at all: logins-off is how James runs
  today, and what he gets with logins off is his - as pins, preferences and requests already follow.
- **Writers keep it true**: an apply re-stars every holder (`ledger_restar` on the row the reindex
  answers - starred and waiting both asked now; the two-step apply is what lets a star follow at all);
  `index_merge` and `index_move`'s newcomer union their holders in their own transactions
  (`_ledger_union`: an entry only on the source moves; with both, the one held wins - starred over
  waiting over removed - the new marker kept if either was new); a re-file keeps the id; `index_gone(...,
  'deleted', by=)` tombstones every live entry in the same transaction ("removed by the admin") - but the
  deleting admin's own (`by`, the delete route's user, `local` with logins off), which is removed and put
  away at once (`dismissed`): nobody is told to request again what they chose to delete (review);
  `missing` touches nothing. A tombstone of the same release is put away (`dismissed`) when it is granted
  again, added, or starred again in Amperfy. The delete dialog's summary (logins on) carries `holders` -
  everyone ELSE who holds it, in the order they got it, `local` and the break-glass admin left out - and
  `yours`, whether the admin asking does; when the ledger can't be read, neither, but `holders_unknown`
  (review: an unread ledger read "Nobody has it in their library" in the one dialog with no undo).
- **Add to my library** (`POST /deadwax/me/library/add`, a Find's body): held_copy's verified folders
  (`album_ids`, which `_store_state` POPS before answering - the page never sees row ids) into the user's
  library, `added`, seen, incomplete when the store holds part (the route's - the app offers Add only for
  a pressing held whole). 409s in words: logins off, the break-glass admin (no Navidrome account, no
  library - the app never offers it Add), no release id, not in the store. `_store_state`'s `held.yours`
  (logins on, not break-glass) says whether they hold any of those folders - left out when the ledger
  can't be read, so the line reads as it always did rather than "not yours" on a guess.
- **The admin's**: `GET /deadwax/library/held` - present albums nobody holds (waiting or starred - local
  counts) and the open flags; a flag's `add` gives the album (followed through merges, refused when not
  present) to who asked and turns the job's `library_grant` to `added`; `dismiss` puts it away and turns
  it to `looked` (`library_ledger.LOOKED`) - each only while the job still says `flagged`
  (`set_job_grant(..., was=)`), so the requesters' row says what the admin did (second review: it kept
  saying "so not added - an admin has been asked to look" with the album in their library).
  `grantWords`: `looked` - "Already in the store as another copy, so not added - an admin has looked at
  it", amber. `/deadwax/me/library` - count, starred, waiting, the
  login's state (`ok` | `dead` with LOGIN_GONE/KEY_CHANGED's words | `none`), the waiting albums with
  `problem_text`, `new` (seen_at NULL), the tombstones; `seen` (by release or ids) and `dismiss`.
- **The app**: the store line (lib/perPerson.ts storeStatusFor's new case, lib/myLibrary.ts) - held
  whole, `yours` false: "In the store, not in your library", the folders and what's held, "Add it to your
  library to have it starred for you in Navidrome - nothing is downloaded.", and Add to my library
  (StoreState's `AddToLibrary`, the album page and the Sources sheet; StoreStatusBox's own on the main
  page) - Join's behaviour: asked at once, aria-disabled while out, the refusal in an alert, added words
  with the focus handed to the box; an add says so (`announceAddedToLibrary`, lib/libraryEvents.ts) and
  the album page hears it and asks the store again, so its line becomes "Already in your library" -
  whether the add was its own or the Sources panel's beside it (review: a desktop's panel left the page
  saying "not in your library"), and the panel, which doesn't ask again, draws `addedStatus` (perPerson:
  "Already in your library", the add note gone, Add kept so its "Added" words stay) - and so does the main
  page's StoreStatusBox once its add is in (second review: it said "In the store, not in your library"
  and the add note above "Added"). A part not yours: "The store has …" (candidates.storeNotes). Requests' Done words
  (`grantWords`); You > Your library (YourLibrary.tsx, at the top, logins on and a library only); Home's
  "New in your library" (Home's `newAlbums`, under Pinned, waited for as the pins are) and the Library's
  New mark over the cover's corner (player/Library.tsx reads the store), both from app/useMyLibrary.ts
  (latestOnly; asked as Home, the Library tab or You shows, when an album is filed and when a store line
  adds one; `seenAlbum` from App's openAlbum, by the album's musicBrainzId, AND for the album page on top
  of the tab showing - reached by its address too - again as each answer lands; an album opened before
  the first answer is kept and looked at as it lands - review: the Library's marks waited for Home to
  ask, and an album opened by its address, or before deadwax first said, kept its mark); the delete
  dialog's holders line ("In your library and ethan's…" for the admin who holds it; deadwax unable to
  read it said so); You's waiting lines three albums a reason, then "and N more" (`waitingText`), and
  they and the removed rows' names break anywhere (`.app-mylib-waiting`, review); Library care's Held by
  nobody (HeldByNobody.tsx, latestOnly, a ref guard against a second tap; "Show all"/"Show fewer" one
  button). A row that leaves - Put away in You, Add for them or Put away in Held by nobody - hands its
  focus to the row now in its place, else the one before, else the section's heading (`nextFocus`,
  applied once the answer without it has drawn and only if focus fell to the page), and what happened
  is said in the polite region (review: focus fell to the page, nothing said).
- **What step 6 changes** (left on purpose): the Library tab still lists every album Navidrome has - it
  becomes the user's starred albums (getAlbumList2 `starred`, as them), Browse the store; and "in your
  library" elsewhere in the app (an album page's meta line, Search's rows, the artist page's In your
  library, "You also have another pressing") still means the STORE - so an album page can say "in your
  library" in its meta line above a store line saying "In the store, not in your library" (seen on the
  real page). The player's calls are still NAVIDROME_USER's (client_for), so Home's Recently added and
  Not played are the shared account's.
- **Changed on purpose** in existing tests: test_store_index's `test_held_complete` (held_copy's
  `album_ids`); test_logins' ROUTES (seven routes) and `concrete` (`{flag_id}`); app-rules.sim's two Home
  source checks (the memo's deps and `ready`). After review: test_personal_libraries' `on` fixture counts
  its library as scanned (seeding's wait has tests of its own), `test_starring_an_album_in_amperfy_adds_it`
  reads the stars back once before the star (a first read-back's finds are seen), the delete test's
  holders (`["ethan"]` and `yours`, james's own entry `dismissed`); mylibrary.sim's holders words (the
  summary is passed); app-rules.sim's ask check (Home or the Library tab).

**Verified** (as built, before review): 2780 Python tests (2778 passed, 2 skipped; 62 new - tests/test_personal_libraries.py), pyflakes,
tsc, every sim (ui/test/mylibrary.sim.cjs new; sources, requests, home and app-rules extended), the build;
the engine files have no diff. Mutation-checked, 77 rules (review found that claim partly overstated - see After review), each test failing with its rule broken and the file
restored byte for byte (PYTHONDONTWRITEBYTECODE): grant_for's flagged/added and incomplete, the backoff,
the poller's grant and the all-there folder indexed for it, the plan's same_release, a flag giving nobody,
only active requesters; the star confirmed by getAlbum, every call as the user, the release id first, a
refused login dying, only that login, the re-check killing it, the sign-in keeping it and asking again at
once, a session standing in; Navidrome down said and not counted; Amperfy's star added and unstar removed,
a star lost to a missing album or a new id put back, mid-retag skipped, albums only; seeding once (both
guards broken together - each alone passed then; since the hold-over fix the row's write is an upsert and
the look is the one guard - see Seeding), leaving out others' holdings, at an admin's sign-in only and
at the take-over; the merge union and its ranking, a move's newcomer; delete tombstones and the holders
without local; a re-grant and an Amperfy re-star putting tombstones away; the apply's re-star and its
retag mark; `yours`, no row ids sent; Add's seen and incomplete, break-glass refused; the new list; held by
nobody's query, a flag for an album gone; `library` and not_filed with logins on only, no track filed;
local's library taken over (counted by local_has_anything, none of it new); the worker idle with logins
off, `/me/library` with logins off, a kick waking it, the lifespan starting it with logins on only; the
route walk and held's admin dependency. In the sims: the store line's Add case, "The store has", Add's
focus handoff, the main page's Add only with a release, the flagged row's amber, not_filed under Needs
attention without Ask again, Home waiting for what's new and its order, App's seenAlbum, nothing asked for
break-glass, only a new album telling deadwax, only the newest answer, Put away asking again, one flag at a
time, a refusal kept, the holders' words, Home's shelf only what Navidrome has, the dialog's line, the
Library's mark. Not covered by a sim: the main page's ↻ next peer on a not-filed row (DownloadJobRow) -
tsc only. A guard found redundant by a mutation (grantWords' `library === undefined`) was taken out.
**Real page** (libs51's own instances: logins on at 8110 and off at 8111, scratch databases, a copied
library, a stand-in Navidrome on 4541 keeping each user's stars apart (star/unstar/getStarred2, getAlbum's
`starred` for the asker, search3 by release id) over it, a fake slskd on 5041 writing the files a download
brings and holding a `hold-*` peer's until released; two headless Chromiums as deadwax.test over plain
http, ethan at 390x844, james at 1440x900; 69 checks in four drivers, all passing on a clean run, and 4 more
at 320x568): ethan's library read filled the index, his sign-in seeded nothing; james's first sign-in seeded all
six, seen, once, and the worker starred the five with release ids AS james (the stand-in's stars: none for
ethan or the shared login), Windows waiting "no release id" - said in his You; ethan's Get of Third filed,
in his library alone, starred as him once the stand-in scanned it, confirmed on its id; his Home's New in
your library under Pinned with Third, the Library's tile marked New ("New in your library" to a screen
reader), opening it unmarked it in the ledger and took the shelf away; his row "In your library"; BULLY
asked by ethan from a held peer, joined by james, released, filed, in both libraries, starred as each;
james's row `added`, asked by both. "Amperfy" (the stand-in, as ethan): Dummy starred - read back after a
restart, ethan's (how starred, new) and on his Home; Third unstarred - read back, removed (unstarred), not
starred back. The album page of The Slow Rush for ethan: "In the store, not in your library", the no-download
line, Add - added, the line asked again saying "Already in your library", starred for him; james's delete
dialog for Dummy "In james and ethan's libraries: deleting it takes it out, and they'll see it was removed
by the admin.", deleted, both tombstones; ethan's You "Dummy by Portishead - Removed by the admin - request
it again to have it back." with Request it again (Dummy's group page) and Put away (gone, dismissed);
Library care's Held by nobody listing Third (ethan unstarred it); BULLY's folder stripped of its release id
and got again: flagged, nobody given it, ethan's row in amber, the flag in james's Library care with Add
for them (closed, nothing doubled); logins off: `{"on": false}`, no Your library, no New shelf or marks, the
store line with no `yours` or row ids. Nothing past the edge at 390 or 320; no console errors. **NOT
verified**: against a real Navidrome 0.64 (its search3 by release id, `star` for an unknown id, getAlbum's
`starred` as the asking user and getStarred2 are read from its source and the plan, and faked); Amperfy
itself (the stand-in stars as Amperfy would); how Navidrome's album ids behave through a real two-step
apply (the sync's "another id: lost" rule is what covers it, tested against a fake); on James's iPhone;
the five-minute sync's timing (driven by restarts on the real page, by `forget_syncs` in the tests).

**After review** (24 findings, majority-confirmed, all fixed; the decisions are in the bullets above):
logins off writing a flag and an event-log line pointing at a section it doesn't draw; the downloads poll
reading every finished row's runners-up; an unread ledger read as "nobody" (the delete dialog) and "not
yours" (the store line); the worker re-passing at once, for ever, when the ledger's writes fail; one
user's getStarred2 error stopping everyone's pass; a first read-back's favourites all New; a break-glass
download giving the album to a holder that doesn't exist; seeding done for good on an index that didn't
know the store yet; the kept login written on the event loop; long names pushing You sideways or cut off;
the desktop Sources panel's Add leaving it and the page saying "not in your library"; the deleting admin
told to request again what they deleted, and named in the third person; the Library's New marks waiting
for Home, and an album opened by its address keeping its mark; Put away / Add for them / Show all
dropping focus to the page; every waiting album named in one paragraph; and the docs promising an Add for
a part and words for break-glass the app never offered. The reviewers' mutation runs also showed rules
the 77-rule claim named only in part - held by nobody's query (starred holders), delete tombstones (only
live entries), the merge union (the new marker), seeding once (an empty seed) - and a dozen it didn't
(a grant or Add over an unstarred entry, incomplete cleared, the unstar's navidrome_id guard, an apply
re-asking waiting entries, a flag followed through a merge, `new` from held entries only, break-glass's
`yours`, a refused apply's retag mark, a missing album's wait and read-back, the batch's size and
`more`, `incomplete` counted, find_album's title fallback and its known id, the key-changed credential in
the worker and the re-check, and three logins-off guards); each has its own test now. **Verified**: 2819
Python tests (2817 passed, 2 skipped; test_personal_libraries.py 101, 39 more), pyflakes, tsc, all 51 sims
(mylibrary, sources and app-rules extended), the build; the engine files have no diff. **Mutation-checked,
65 rules** (`deadwax-scratch/work/libs51-fixer/mutate.py`, each file restored byte for byte by hash,
PYTHONDONTWRITEBYTECODE): every fix above and every rule in the list just given, each caught by the test
or sim meant for it. **Real page** (libs51-fixer's own instances: logins on at 8112 and off at 8113,
scratch databases, a hard-linked copy of libs51-builder's library plus tiny albums - two one-word titles,
six untagged, 22 copied in by hand - and a copy of its stand-in Navidrome on 4542; 45 checks in four
drivers, all passing - the first in two goes, its screenshot folder missing the first time): james's sign-in to an unscanned library held the seed over and said so; a search's
first scan seeded all 15, seen, and the worker starred them as james; his You at 375 named three untagged
albums "and 5 more", the one-word title broken, nothing past the edge; ethan's two favourites from before
were added starred and seen, no New shelf; two stars after it were new, and a page opened straight onto
`#/library` marked both New without Home; one opened by its address was unmarked in the ledger; james's
delete dialog said "In your library and ethan's: deleting it takes it out, and ethan will see it was
removed by the admin.", his own entry put away, ethan's tombstoned; ethan's removed cards at 320 wrapped
inside the card, Put away handed focus to the next row, then the heading, and said so; a desktop's Sources
panel Add left the panel "Already in your library" with its Added words and the page beside it saying the
same; Held by nobody's Show all/Show fewer kept its focus, Add for them handed it to the next flag and Put
away to the heading, "given to ethan" said; logins off: Home's shelves drawn 165 ms in, no New, no Your
library, no Held by nobody, `/me/library` `{"on": false}`, the delete summary naming nobody. No console
errors. **NOT verified**: what the list above says is not - all of it against a real Navidrome 0.64.

**After the second review** (12 findings, majority-confirmed; the decisions are in the bullets above):
the seed leaving out every album another user's first read-back had put in their library (an Amperfy
favourite from before, read back by a worker pass that can beat the admin's first request) - only a
grant leaves one out now; a first read-back before the library's first scan counted as the first, so the
read after it marked every old favourite New - it counts only on an index that knew the store as it
began; Add for them and Put away leaving the requesters' row saying "an admin has been asked to look" -
`added` and `looked` now; the main page's store box saying "In the store, not in your library" and the
add note above "Added" - `addedStatus` there too; docs/player.md and Home.tsx counting Add to my library
as New (it never is); the Seeding bullet's "two guards, each alone enough" (the look is the one guard);
"four tables" (five); and three rules with no test - an apply never re-starring a removed entry
(ledger_restar's state guard), the read-back taking a new Navidrome id for a starred entry, and seenAlbum
telling deadwax by the store's ids. **Verified**: 2824 Python tests (2822 passed, 2 skipped; test_personal_libraries.py 106, 5 more),
pyflakes, tsc, all 51 sims (sources, mylibrary and requests extended), the build; the engine files have no
diff. **Mutation-checked, 13 rules** (`deadwax-scratch/work/libs51-fixer2/mutate.py`, each file restored
byte for byte by hash, PYTHONDONTWRITEBYTECODE), each failing the test or sim meant for it on an
assertion: the seed's `how = grabbed` (gone, and excluding nothing), the read-back's index check (gone,
`index_scanned` always true, `synced_at` never written), Add for them's and Put away's row writes,
`set_job_grant`'s `was`, the `looked` words, the main page's box after Add, ledger_restar's state guard,
the read-back's new-id branch, seenAlbum's ids. **Real page** (libs51-fixer2's own instances: logins on at
8114 and off at 8115, scratch databases, a four-album library made for it - one an untagged rip - and a
copy of the stand-in Navidrome on 4543; the two flagged downloads filed through the real poller and
organizer by a script against the stopped server's database, no slskd; 29 checks in four drivers, all
passing - two driver mistakes, a selector and an unscanned logins-off library, fixed and run again):
ethan's Mezzanine starred in the stand-in before deadwax; his sign-in's read-back found nothing in an
unscanned index and wasn't counted; after the first scan and a restart, the worker's read-back added it
starred and SEEN, no New shelf on his Home; james's first sign-in seeded all four, Mezzanine included, and
the worker starred the three with release ids AS james, ethan's star his own; ethan's two flagged rows
amber "an admin has been asked to look"; james's Add for them on one and Put away on the other (Library
care) turned them into "Already in the store, added to your library" (plain) and "...so not added - an
admin has looked at it" (amber); nothing past the edge at 390 or 320; the main page's box for Third (ethan's
Find) "In the store, not in your library" with the add note and Add, then after Add "Already in your
library", no add note, the Added words - Third his, `added`; logins off: `/me/library` `{"on": false}`,
the main page's box "Already in your library" with no Add. No console errors. **NOT verified**: as above -
all of it against a real Navidrome 0.64.
