# Sharing deadwax

deadwax starts out as one person's app: no sign-in, and whoever can reach it uses it as its one
admin. This page is for when you run it for yourself and now want a partner, family or friends to
use it too - each with their own sign-in, their own requests and their own library, over the one
music folder you already have.

Everything here is about **logins**. They're off until you turn them on, and turning them off
again puts deadwax back the way it was.

**If you ran a 2.0.0 pre-release (`:player`) with logins on**: deadwax's admins are **Navidrome's
admins** - `DEADWAX_ADMINS` is ignored (the log says so once at start-up), so take it out of compose, and
make your own account an admin in Navidrome's **Users** page if it isn't one, or you lose Managing.
Break-glass signs in as **`deadwax`**, not `admin` (the same `DEADWAX_ADMIN_PASSWORD`; what it kept moves
with it), so a Navidrome account called `deadwax` can't sign in to deadwax, while Navidrome's own `admin`
signs in as itself. Close a home-screen app left open from an early pre-release and open it again. Coming
from 1.x, none of this applies: logins are new.

## What sharing gives each person

With logins on, everyone signs in to deadwax with **their own Navidrome account** - the same user
name and password they'd type into Navidrome or Amperfy. deadwax has no accounts of its own: it asks
Navidrome whether the password is right - and whether the account is one of Navidrome's admins, who are
deadwax's admins. Accounts are made, reset and removed in Navidrome; an admin can do all of that from
deadwax too, in **People**. Then, for each person:

- **Their own requests and downloads.** Requests, Home's **Arriving** and the count on the Requests
  tab show the downloads *they* asked for. If somebody else is already downloading the same pressing,
  they aren't sent off to fetch it twice: they **join** that download instead, and it arrives for both
  of them. Their ✕ on a shared download only takes it off their own list; it carries on for the
  others. (An admin's ✕ is the exception: it cancels the download for everyone, and asks first.)
  ([Downloading → downloads per person](downloading.md#with-logins-on-downloads-per-person).)
- **Their own library.** Each person's library is **their favourites in Navidrome** - their starred
  albums - so Amperfy, or any other Subsonic app signed in as them, shows the same albums. What they
  get is starred for them once it's filed; an album the collection already has is a tap away
  (**Add to my library**, nothing downloaded); starring or unstarring an album in Amperfy is read
  back within five minutes. **Remove from my library** only unstars it - nothing is deleted. The app says
  all this in their words, not Navidrome's: **Added to your library.**, "waiting to be added", "Your library is
  also in your other music apps, such as Amperfy, as your favourite albums." - and the music everyone shares
  is **All music** in the Library, "the collection" in a sentence. Home's **Recently added** is their own
  albums the collection got most recently (since 2.0.5), as the Library's is.
  ([Your library](player.md#your-library-with-logins-on).)
- **Their own player.** The app plays as them, so their plays, play counts, **Recently played** and
  **Not played in a while** are theirs, and plays go on to their own Last.fm or ListenBrainz if they
  linked one in Navidrome. ([The player as you](player.md#the-player-as-you-with-logins-on).)
- **Their own queue.** What they were playing is kept as their own play queue in Navidrome, with deadwax's
  account of Up Next beside it, so it follows them between devices: they stop on the phone, open deadwax on the
  computer, and it's there, paused where they stopped. Nobody else's queue is ever put back for them.
  ([Picking up where you left off](player.md#picking-up-where-you-left-off).)
- **Their own playlists.** Playlists are Navidrome's, made as them, so they're theirs in Amperfy too.
  One they share (**Shared with everyone**) shows to the others under **Shared with you** - playable,
  but only its owner can change it. A private one is never shown to anyone else in deadwax - though
  Navidrome's own admins can still see it in Amperfy, which is Navidrome's doing.
  ([Playlists](player.md#playlists).)
- **Their own pins and Getting albums settings.** What's pinned to Home, and You → Getting albums
  (what Get does, the quality floor, the format), are kept on deadwax for each person, so they follow
  them from the phone to a computer. The player's other settings - Gapless, Maximum quality, the
  turntable's - are kept on each device, as they always were, whoever signs in there.

**What stays shared:**

- **One collection.** Everything anyone gets is filed into the same music folder, once. Everyone can look
  through all of it (**All music** in the Library: All albums, All artists, All songs) and add any of it to
  their own library. There is no
  per-person storage or quota.
- **One slskd.** Every download comes through your slskd and your Soulseek account. Searches start
  one at a time across everyone (each waits a moment for its turn), so two people searching at once
  don't trip slskd up.
- **Looking after the library is an admin's.** Editing an album, deleting one, the albums that need
  a look, Library care, the server settings, the log and People belong to Navidrome's admins - and an
  admin can hand some of it to anyone else, by category - see
  [Admins, permissions and everyone else](#admins-permissions-and-everyone-else).

## Before you start

- **A Navidrome account for each person.** Make them in Navidrome's own **Users** page, or - once you
  are signed in to deadwax as a Navidrome admin - in deadwax's **People** ([Adding a person](#adding-a-person)).
  An ordinary account is enough for everyone else. **You need one Navidrome admin account to manage
  deadwax**: deadwax's admins are exactly Navidrome's admins. That can be your everyday account, or a
  separate one you sign in as only to manage (Navidrome's own `admin`, say) - see the upgrade note above
  for what making an account a Navidrome admin gives it. Two names can't sign in to deadwax, because
  deadwax keeps them for itself: `local` and `deadwax`. An account Navidrome can't check with a token
  (an LDAP one) can't sign in.
- **Navidrome set up in deadwax**: `NAVIDROME_URL`, `NAVIDROME_USER` and `NAVIDROME_PASSWORD`
  ([the app's setup](player.md#setting-it-up)). Signing in asks Navidrome at `NAVIDROME_URL`.
  Keep `NAVIDROME_USER` set once logins are on: deadwax still uses that account for what belongs to
  nobody in particular, such as fetching a song once into the player's cache for every phone. If your
  Navidrome gives users libraries of their own, give that account every one.
- **Organizing on**: `ORGANIZE_MODE` set to `copy` or `move`, with `LIBRARY_PATH` and
  `SLSKD_DOWNLOAD_PATH` set. A download becomes the asker's when it's filed, and in dry run nothing
  ever is - so with logins on and organizing off, deadwax refuses everything (but its health check
  and the pages themselves) until it's fixed, saying why.
- **HTTPS before anything leaves your network.** Plain `http://` is fine on your own network and over
  a VPN such as WireGuard or Tailscale. Anywhere else, put HTTPS in front of deadwax first: over plain
  http a password and a session can be read on the way. deadwax doesn't serve HTTPS itself - that
  means a reverse proxy with a certificate (Caddy, nginx, Traefik, Nginx Proxy Manager…) in front of
  its port 8080; step 3 of [turning logins on](#turning-logins-on) has the one setting it may need, and
  a sample nginx block. A VPN on each person's phone avoids needing HTTPS at all.
- **No frames.** deadwax refuses to be shown inside another site's page - an `<iframe>`, a dashboard's
  web tile (Homarr, Heimdall, Home Assistant's webpage card…), even one on the same host - so a page
  elsewhere can't lay deadwax's buttons under its own and trick a click through. Such a tile goes
  blank; make it a link that opens deadwax in its own tab instead. There's no setting to allow it.

## Turning logins on

The three login settings are read from the container's environment - compose's `environment:`
block, or `.env` - and nowhere else. Server settings shows them, locked: a value saved there would
beat compose, so a wrong one could lock everyone out with no way back from the page that saved it.

1. **Make a secret key.** On any machine with OpenSSL:

   ```bash
   openssl rand -hex 32
   ```

   It must be at least 32 characters. It encrypts the Navidrome logins deadwax keeps (so it can
   star albums for people while they're signed out) and seals the break-glass sign-in. Keep it with
   your other secrets, in `.env` rather than a compose file you might paste somewhere:

   ```bash
   DEADWAX_SECRET_KEY=<the key>
   ```

   That's `.env` beside the compose file, which compose passes in through `env_file:` (the example
   compose does, and [`.env.example`](../.env.example) has all three login lines waiting). Put the key
   in one place only: a `DEADWAX_SECRET_KEY` line under compose's `environment:` beats `.env`, even an
   empty one or a `...` copied as written, and then nobody can sign in.
2. **Add the other settings** beside it, in `.env` (or, for these two, compose's `environment:`):

   ```bash
   AUTH_MODE=on
   # optional - signs in `deadwax` with no Navidrome, for when Navidrome is down:
   #DEADWAX_ADMIN_PASSWORD=
   ```

   - `AUTH_MODE` - `off` (the default) or `on`. Anything else is read as **on**, so a typo never leaves
     deadwax open; the log says so.
   - There is no setting for who the admins are: **Navidrome's admins are deadwax's admins**, read as
     each person signs in and every few minutes after. Making an account a Navidrome admin gives it more
     than deadwax's Managing: in Navidrome its **Users**, **libraries** and settings pages, **every
     library**, and in Amperfy (or any Subsonic app signed in as it) **everyone's playlists, private ones
     included**.
   - `DEADWAX_SECRET_KEY` - the key. **Losing it costs nothing but sign-ins**: make a new one, and
     everyone is signed out at their next request once the container is recreated with it, and signs in
     again. Until each
     person does, deadwax can't star new albums for them - those wait, and are starred once they've
     signed in again.
   - `DEADWAX_ADMIN_PASSWORD` - optional, the **break-glass** sign-in: user name `deadwax` and this
     password sign in an admin without asking Navidrome or reading deadwax's database - for when
     Navidrome is down, or nobody who can sign in is a Navidrome admin. It lasts 12 hours, and ends at
     once if the password changes. Make it long and random (`openssl rand -base64 18`): the name is public,
     and wrong guesses are held off per address (three a minute from each, the right password included once
     an address is held off) - so a stranger's guesses keep only the stranger out, and you still get in from
     another address. Behind a reverse proxy every sign-in may come from the proxy's own address, and then
     a stranger's guesses through the proxy hold you off through it too: sign in at deadwax's address on
     your network instead. Someone with many addresses still gets many guesses, so its length is what keeps
     them out. Shorter than 16 characters, the log at start-up and its
     row in Server settings say so (it still works). It has no Navidrome account behind it, so no library of its own,
     its player plays as `NAVIDROME_USER`, it keeps no play queue (nothing is put back or saved for it), and it
     can't use **People** (which asks Navidrome as you).
3. **Behind a reverse proxy**, if it rewrites the `Host` header (nginx does, unless told
   `proxy_set_header Host $http_host`), also set `TRUSTED_ORIGINS` to the address you open deadwax
   at, such as `https://music.example.com` - otherwise every change, plays included, looks like it
   came from another website and is refused. The session cookie is marked Secure when deadwax is
   reached over HTTPS, directly or through a proxy that sends `X-Forwarded-Proto`. Reach one host name
   over HTTPS or over plain http, not both: a browser that signed in over HTTPS won't let the http
   address sign in until that cookie is gone ([troubleshooting](troubleshooting.md#signed-in-over-https-and-now-the-http-address-wont-sign-in)).
   A sample nginx block that does all of this - and keeps the Log's live lines and the player's audio
   flowing, which nginx otherwise holds back in its buffers:

   ```nginx
   server {
       listen 443 ssl;
       server_name music.example.com;
       # ssl_certificate and ssl_certificate_key: your certificate

       location / {
           proxy_pass http://192.168.1.20:8080;     # deadwax's port on your server
           proxy_http_version 1.1;
           proxy_set_header Host $http_host;        # the address you opened, port and all - no TRUSTED_ORIGINS needed
           proxy_set_header X-Forwarded-Proto $scheme;   # so the session cookie is marked Secure
           proxy_buffering off;                     # the Log's live lines and the audio arrive as they're sent
           proxy_read_timeout 1h;                   # an open Log, a long apply, a paused song
       }
   }
   ```
4. **Recreate the container** and open deadwax. The app shows a sign-in screen; sign in with your
   Navidrome user name and password. An app already open on a phone, or in a tab, reloads itself into
   the sign-in screen the next time it asks deadwax for something.

Each setting's full row is in [Configuration → Logins](configuration.md#logins-environment-only).
**If you're upgrading** at the same time and had the home-screen app open from before the upgrade,
close it (swipe it away) and open it again, and reload any tab left open - an older app can't tell that
logins came on, and everything in it fails with "Sign in to use deadwax." until you do.

## What happens to what you had

You were deadwax's one user until now (deadwax calls that user `local`). When logins come on:

- **The first Navidrome admin to sign in takes it over**, in one step: the pins on Home, the Getting
  albums settings, and every download made before (they show in that admin's Requests). What that admin
  had already set wins over the old. If an admin is still signed in from earlier - a session lasts 30
  days and outlives a restart - it's taken over on their first visit instead.
- **The collection goes into the first Navidrome admin's library**, once ever: every album already in it is
  put in that admin's library and **starred for them in Navidrome** - so their Navidrome favourites, and
  Amperfy's, fill with the whole collection. There's no undo for all of them at once: unstar them in Amperfy,
  or **Remove from my library** in deadwax, one album at a time. So sign in first with the account you
  listen on (made a Navidrome admin), not a separate managing account. An album already starred is only
  checked, never starred again, so the date Navidrome shows for it stays. That's yours - it was all yours
  before anyone else had a library. The one exception is an album somebody else's download brought in,
  which is theirs. If deadwax hasn't scanned the library yet (a new install, or an upgrade from a
  version whose saved scan it can't read), this waits for its first scan - which deadwax starts by
  itself, in the background, as it starts (a search or **Library care → Rescan** starts one too). Both wait for a
  **Navidrome admin's** sign-in: on an install where nobody signing in is one, the collection goes into
  nobody's library until someone is made one. Once done, neither happens again for a second admin - an
  admin who signs in later starts as anyone new does.
- **Everyone else starts with an empty library**, apart from albums they had already starred in
  Navidrome that the collection holds: those are read back and added (without a **New** mark - they were
  theirs already).
- **Plays, playlists and favourites** are Navidrome's, and stay where they are - the first admin's
  favourites gaining the collection's albums, above, is the one thing added to them. With logins off, the
  player played as `NAVIDROME_USER`; with logins on, it plays as whoever is signed in. So if
  `NAVIDROME_USER` is your own account, your play counts and playlists carry on as yours; if it was a
  separate account, what it played and made stays that account's.

## Adding a person

From deadwax, as a Navidrome admin:

1. **You → Managing deadwax → People** (on a desktop, **People** in the sidebar's Managing group).
2. **Unlock People** with your own Navidrome password. People changes Navidrome's accounts *as you*,
   and Navidrome needs your password for that; deadwax checks it against the login you signed in with
   first (so a typo never reaches Navidrome), uses it once and doesn't keep it. It stays unlocked on
   that device for 15 minutes since you last use it; **Lock** ends it at once.
3. **Add a person**: a **User name** (lowercase letters, digits, dots, underscores and hyphens, up to
   32, starting with a letter or a digit), an optional **Display name**, and a **Password** typed twice
   (8 to 128 characters, not the user name). **Make account**. The account is always made ordinary:
   making someone an admin is its own step. deadwax then signs in once as the new account to check the
   password took, and says if Navidrome gave them no library to see.
4. Tell them their user name, the password you chose and deadwax's address - the same one you use,
   `/player/` for the app (they can add it to an iPhone's home screen, as you did). Amperfy signs in
   with the same. Nothing else changes in deadwax: no restart, no setting.

Or make the account in Navidrome's own **Users** page and skip to step 4.

Over plain `http://` a password typed in People crosses your network readable, as everyone's sign-in
does - fine on your own network or over a VPN; anywhere else, put HTTPS in front of deadwax first. People
says so under each password field.

**The first time**, they see the app without any managing: no **Managing deadwax** or **Connections**
in You, no **Edit** on an album; when something fails they're told what happened and what to do -
try again, or tell whoever runs deadwax - never an error's own words. Their Library - and Home's Recently added - says **Nothing in your library yet.**, with **See All music** in
the Library, where the whole collection is. Home has no pins yet; their Getting albums settings are the defaults, or what the old page at `/` had
left in that browser, carried over once ([configuration](configuration.md#your-settings-in-the-app-per-user-on-deadwax)). From
there they search, **Get** what they want, or add what the collection already has. They stay signed in on
that device for 30 days from the last time they used it; **You → About → Sign out** signs them out.

To make someone an admin, use **Make admin** on their row in People, or tick **Admin** for them in
Navidrome's own Users page - deadwax notices within about six minutes. To give them only part of an
admin's job, tick it under their **Permissions** instead ([below](#admins-permissions-and-everyone-else)).

## When something changes

- **Removing a person.** In People, **Remove…** on their row opens a dialog saying exactly what goes:
  in Navidrome, for good, their account, play counts and history, favourites, every playlist they own
  (shared ones too) and their Last.fm or ListenBrainz link; in deadwax, their sign-ins, library list,
  pins, play queue, Getting albums settings and permissions. Every album stays in the collection, and a download only
  they were waiting for carries on, filed for nobody (cancel it in Requests first if nobody wants it).
  There's no undo: type their user name to remove them. They're signed out on every device at once.
  If they may come back, reset their password instead.
  An account deleted in Navidrome's own Users page instead signs them out within about six minutes,
  and what deadwax kept for them shows in People under **Known only to deadwax**, with **Forget** -
  until it's forgotten, deadwax won't make a new account of that name in People, so a new person never
  inherits someone else's library, pins, play queue or permissions.
- **Changing your own password**: **You → About → Change password**, for anyone signed in with their own
  Navidrome account - your current password, then the new one twice (8 to 128 characters, not your user
  name, not the one you have), **Show** to see what you typed. deadwax checks the current one against the
  login you signed in with before it asks Navidrome anything, so a typo costs nothing; then it changes the
  password in Navidrome *as you*, and checks the new one works. The device you changed it on stays signed
  in - what's playing carries on - under a new sign-in of its own, so a copy of its old one (if someone
  had taken this browser's sign-in, the reason to change a password) is signed out too; every other device
  of yours is signed out and signs in again with the new password, and it says how many ("Signed out of
  your other 2 devices"). Amperfy and any other app you
  use with Navidrome need the new password too. It's your Navidrome password, so it's changed for
  Navidrome itself as well. Not for the break-glass `deadwax` (its password is `DEADWAX_ADMIN_PASSWORD`), nor
  for `NAVIDROME_USER`'s account - change that one in Navidrome, then in **Server settings → Connections**.
  A few tries a minute at most; three wrong current passwords hold the name off for the rest of the minute,
  as at the sign-in. If Navidrome is set not to let people change their own details (`EnableUserEditing`
  off - it's on unless someone turned it off), it says so, and an admin can reset it for you in People.
- **A forgotten password**: in People, **Reset password…** on their row - the new one typed twice. They
  are signed out of deadwax on every device at once, and sign in with the new password; Amperfy and any
  other app they use need it too. Their library stays. (You can't reset your own there - change it in
  **You → Change password**, which needs the one you have; a forgotten admin password needs another admin's
  People, or Navidrome itself.) A password changed in Navidrome itself signs them out within about six
  minutes, and **You → Your library** says in red that new albums can't be added to their library until they
  sign in again; nothing waiting is lost.
- **Making someone an admin, or no longer one**: **Make admin** / **No longer admin** in People, which
  says first what it gives (or that they keep every library Navidrome gave them as an admin), and is in
  force at their next request. Changed in Navidrome's own Users page, deadwax follows within about six
  minutes. People won't change your own role, `NAVIDROME_USER`'s account, or leave Navidrome without an
  admin.
- **Wrong passwords**: after three wrong passwords for one user name within a minute, deadwax stops
  asking Navidrome about that name for the rest of the minute - "Too many tries for … - wait N seconds
  and try again" - so a mistyped password, or someone guessing, never gets the account locked in
  Navidrome itself. Other names aren't held up. The break-glass `deadwax` is counted per address instead:
  an address held off waits out the minute even with the right password, and other addresses can still
  sign in with it.
- **Navidrome down**: nobody new can sign in, since signing in asks Navidrome - except with the
  break-glass `deadwax`. Everyone already signed in stays signed in, but the player plays from
  Navidrome, so Home and the Library say they can't reach it; searching, **Get** and Requests still
  work, and starring waits until Navidrome is back.

What each message on the sign-in screen means: [Troubleshooting → Signing in](troubleshooting.md#signing-in).

## Admins, permissions and everyone else

**Admins are Navidrome's admins** - plus the break-glass `deadwax` - and can do everything. Everyone
else can do what the left column says, and an admin can give any of them more, by category, under
**Permissions** on their row in People.

| | everyone signed in | given in People | admins |
| --- | --- | --- | --- |
| play, playlists, their own library (Add, Remove), pins, Getting albums settings | yes | - | yes |
| their own downloads: see, cancel, **Clear done** | yes | - | yes |
| **Get albums**: search Soulseek, **Get**, the sources, join a download, **Another source**, **Same source again** | yes - an admin can take it away | - | yes |
| **Edit albums**: apply a release, tags, cover, CD art, lyrics (one album, or Library care's runs), an artist's pictures, **Which artist is this?** | no | **Edit albums** | yes |
| **Look after the library**: delete an album, move an artist's albums under their current name, **Needs a look**, **Rescan**, **Held by nobody** | no | **Look after the library** | yes |
| **Everyone's downloads**: see who asked ("Asked by ethan"), cancel or retry anyone's, clear everyone's finished | no | **Everyone's downloads** | yes |
| **Settings and the log**: the server settings and the event log - and You's **Connections**, and the words behind what went wrong (Navidrome's or slskd's own, a setting's name) under each error | no | **Settings and the log** | yes |
| **People**: make, reset and remove Navidrome accounts, make admins, give permissions | no | never - it comes with being a Navidrome admin | yes |
| **Info → Debug** on the now-playing screen: how each song is sent, the last song changes and seek, the turntable's readouts and recording, the test bench link, the fields Navidrome sent | no - **Info** is **About** alone, with a **Sound** group (the file's format, Gapless, Normalization, in a listener's words) - and never the album's folder, which is an admin's | never - it comes with being an admin | yes |

- **Giving permissions**: People → their row → **Permissions** → tick what to give → **Save
  permissions**. It's in force from their next tap - no sign-in. An admin's row is all ticked and
  can't be changed ("Admins can do everything."); so is your own, `NAVIDROME_USER`'s and a reserved
  name's. Settings and the log can point deadwax at other folders and change how it downloads and files,
  and Look after the library deletes albums for good - give those only to someone you'd trust as an admin. **`NAVIDROME_URL`,
  `NAVIDROME_USER`, `NAVIDROME_PASSWORD`, `SLSKD_URL` and `SLSKD_APIKEY` stay an admin's** even then:
  everyone's own Navidrome sign-in goes to the address, and it says who the admins are; the account is
  deadwax's own, which People won't touch - set to someone's own account, it would put them out of People's
  reach; and slskd's API key, which goes to slskd's address, is full control of slskd. For anyone else they
  show locked ("Only an admin can change this").
- **A listen-only account**: untick **Get albums** for them. They can still play, look through and add what
  the collection has; Get becomes "Getting albums is off for you - ask an admin."
- **Bound to the account**: a permission is given to that Navidrome account, not just the name - an
  account removed and made again under the same name doesn't inherit it. deadwax checks the account
  as they sign in (one Navidrome sign-in as them, only for someone given something); if it can't, what
  was given is off until their next sign-in (a Get albums taken away still applies), and You says so.
- Making someone an admin keeps what was ticked for them, for if they're ever made ordinary again.
- **Debug is an admin's**: it was built for testing deadwax on a phone, and everyone
  else's Info has no tabs - About alone, with a short **Sound** group of the three things a listener can
  use, in a listener's words (Debug has the numbers). The album's folder on the server, at About's foot, is an admin's
  only, like Debug. Made an admin, or made ordinary, it shows as Info next opens, once it has asked who they are (a
  moment after it opens). The turntable's test bench
  at `/player/lab/` still opens by its address, as before - Debug was only its link.

Retrying someone else's download needs both Everyone's downloads (to reach it) and Get albums (it
starts a download). Library care shows with Edit albums or Look after the library - each part by its own.

The app doesn't show anyone what they can't use - Managing in You and the sidebar shows a row per
permission, an album's **Edit** its editors or its Delete, an artist's page its managing - and deadwax
refuses it if asked anyway ("That needs Edit albums, which an admin hasn't given you."). Everyone can
still look at everything in the collection: albums, their tracks, covers, lyrics and artists. A download
that fails says why on the asker's own row in Requests; the event log, which also records who signed
in and every change made in People, is Settings and the log's.

## Turning logins off again

Set `AUTH_MODE=off` and recreate the container. deadwax is then as it was before logins: no sign-in,
and anyone who can reach it uses it as its one admin. So keep it on your own network, or behind
something else that asks for a password.

- **Kept**: everything in deadwax's database - permissions too. The pins and Getting albums settings
  the first admin took over stay with that admin, for when logins are back - so with logins off, Home starts with no
  pins, and Getting albums starts again from its defaults (or what the old page at `/` had left in
  that browser, carried over once, as on a first visit). Each person's library, pins and kept login stay too,
  untouched, and the stars in Navidrome stay as they are (deadwax unstars nothing).
- **Back to one**: there's one library again - the whole collection - and "in your library" means the
  collection. Every download is listed, and **Clear done** in Requests
  forgets every finished one. The player
  plays as `NAVIDROME_USER` again, so plays, playlists and the play queue are that account's, shared by
  everyone.
  Nothing is starred while logins are off.
- **Switched on again later**, what was got and pinned meanwhile goes to the first Navidrome admin back,
  as it did the first time, and a session used within the last 30 days is still signed in.

## What it doesn't do

- **No sign-up page**: accounts are made by an admin, in People or in Navidrome.
- **No resetting a password you've forgotten** yourself: changing your own needs the one you have
  (**You → Change password**); forgotten, an admin resets it in People.
- **No choosing a person's Navidrome libraries**: People warns when a new account got none - tick them
  in Navidrome's own Users page.
- **No per-person storage or quotas**: there's one collection, and one copy of each album in it.
- **No private albums**: anyone signed in can look through the whole collection. Your library is which albums
  are yours, not who may see them - unless Navidrome itself gives users separate libraries, in which
  case deadwax only ever plays someone a song Navidrome would give them.
- **No roles beyond admin**: someone is a Navidrome admin or they aren't - what an ordinary person may
  do beyond the defaults is the five permissions above, ticked per person.
