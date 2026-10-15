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
  nothing. Switching logins off again leaves those rows with the admin.
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
| leave or retry their own requests, hide finished ones | yes (step 4 makes requests per person) | yes |
| see and cancel everyone's downloads | **the one known gap**: until step 4, a user sees and acts on the whole queue, as everyone did | yes |
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
