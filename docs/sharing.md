# Sharing deadwax

deadwax starts out as one person's app: no sign-in, and whoever can reach it uses it as its one
admin. This page is for when you run it for yourself and now want a partner, family or friends to
use it too - each with their own sign-in, their own requests and their own library, over the one
music folder you already have.

Everything here is about **logins**. They're off until you turn them on, and turning them off
again puts deadwax back the way it was.

## What sharing gives each person

With logins on, everyone signs in to deadwax with **their own Navidrome account** - the same user
name and password they'd type into Navidrome or Amperfy. deadwax has no accounts of its own: it asks
Navidrome whether the password is right. Then, for each person:

- **Their own requests and downloads.** Requests, Home's **Arriving** and the count on the Requests
  tab show the downloads *they* asked for. If somebody else is already downloading the same pressing,
  they aren't sent off to fetch it twice: they **join** that download instead, and it arrives for both
  of them. Their ✕ on a shared download only takes it off their own list; it carries on for the
  others. (An admin's ✕ is the exception: it cancels the download for everyone, and asks first.)
  ([Downloading → downloads per person](downloading.md#with-logins-on-downloads-per-person).)
- **Their own library.** Each person's library is **their favourites in Navidrome** - their starred
  albums - so Amperfy, or any other Subsonic app signed in as them, shows the same albums. What they
  get is starred for them once it's filed; an album the store already has is a tap away
  (**Add to my library**, nothing downloaded); starring or unstarring an album in Amperfy is read
  back within five minutes. **Remove from my library** only unstars it - nothing is deleted.
  ([Your library](player.md#your-library-with-logins-on).)
- **Their own player.** The app plays as them, so their plays, play counts, **Recently played** and
  **Not played in a while** are theirs, and plays go on to their own Last.fm or ListenBrainz if they
  linked one in Navidrome. ([The player as you](player.md#the-player-as-you-with-logins-on).)
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

- **One store.** Everything anyone gets is filed into the same music folder, once. Everyone can look
  through all of it (**Browse** in the Library) and add any of it to their own library. There is no
  per-person storage or quota.
- **One slskd.** Every download comes through your slskd and your Soulseek account. Searches start
  one at a time across everyone (each waits a moment for its turn), so two people searching at once
  don't trip slskd up.
- **Looking after the library is an admin's.** Editing an album, deleting one, the albums that need
  a look, Library care, the server settings and the log belong to the people you name as admins -
  see [Admins and everyone else](#admins-and-everyone-else).

## Before you start

- **A Navidrome account for each person.** Make them in Navidrome (its own user settings - an admin
  of Navidrome does this), not in deadwax: deadwax never creates or changes a Navidrome account.
  An ordinary account is enough; nobody needs to be a Navidrome admin. Two names can't be used,
  because deadwax keeps them for itself: `local` and `admin`. An account Navidrome can't check with a
  token (an LDAP one) can't sign in.
- **Navidrome set up in deadwax**: `NAVIDROME_URL`, `NAVIDROME_USER` and `NAVIDROME_PASSWORD`
  ([the phone player's setup](player.md#setting-it-up)). Signing in asks Navidrome at `NAVIDROME_URL`.
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
  its port 8080; step 3 of [turning logins on](#turning-logins-on) has the one setting it may need. A
  VPN on each person's phone avoids needing HTTPS at all.

## Turning logins on

The four login settings are read from the container's environment - compose's `environment:`
block, or `.env` - and nowhere else. The settings tab shows them, locked: a value saved there would
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
   compose does). Put the key in one place only: a `DEADWAX_SECRET_KEY` line in `environment:` beats
   `.env`, even an empty one or a `...` copied as written, and then nobody can sign in.
2. **Add the other settings** to deadwax's compose:

   ```yaml
       environment:
         - AUTH_MODE=on
         - DEADWAX_ADMINS=james              # your Navidrome user name; comma-separate several
         # DEADWAX_SECRET_KEY is in .env (step 1) - not here as well
         # optional - signs in `admin` with no Navidrome, for when Navidrome is down:
         #- DEADWAX_ADMIN_PASSWORD=...
   ```

   - `AUTH_MODE` - `off` (the default) or `on`. Anything else is read as **on**, so a typo never leaves
     deadwax open; the log says so.
   - `DEADWAX_ADMINS` - who is deadwax's admin, by Navidrome user name (case doesn't matter). Put
     yourself here. Navidrome's own admin setting isn't used: an admin here needn't be one there.
     Left empty, nobody who signs in through Navidrome is an admin, and the log says so.
   - `DEADWAX_SECRET_KEY` - the key. **Losing it costs nothing but sign-ins**: make a new one, and
     everyone is signed out at their next request after the restart and signs in again. Until each
     person does, deadwax can't star new albums for them - those wait, and are starred once they've
     signed in again.
   - `DEADWAX_ADMIN_PASSWORD` - optional, the **break-glass** sign-in: user name `admin` and this
     password sign in an admin without asking Navidrome or reading deadwax's database - for when
     Navidrome is down, or nobody else can get in. It lasts 12 hours, and ends at once if the
     password changes. It has no Navidrome account behind it, so no library of its own, and its
     player plays as `NAVIDROME_USER`.
3. **Behind a reverse proxy**, if it rewrites the `Host` header (nginx does, unless told
   `proxy_set_header Host $http_host`), also set `TRUSTED_ORIGINS` to the address you open deadwax
   at, such as `https://music.example.com` - otherwise every change, plays included, looks like it
   came from another website and is refused. The session cookie is marked Secure when deadwax is
   reached over HTTPS, directly or through a proxy that sends `X-Forwarded-Proto`.
4. **Recreate the container** and open deadwax. The app shows a sign-in screen; sign in with your
   Navidrome user name and password. An app already open on a phone, or in a tab, reloads itself into
   the sign-in screen the next time it asks deadwax for something. The main page has no sign-in of its
   own: it says you're signed out, and its **Sign in** goes to the app's and back.

Each setting's full row is in [Configuration → Logins](configuration.md#logins-environment-only).
**If you're upgrading** at the same time and had the home-screen app open from a version before
2.0.0-player.48, close it (swipe it away) and open it again, and reload any tab left open - an older app can't tell that logins
came on, and everything in it fails with "Sign in to use deadwax." until you do.

## What happens to what you had

You were deadwax's one user until now (deadwax calls that user `local`). When logins come on:

- **The first admin to sign in takes it over**, in one step: the pins on Home, the Getting albums
  settings, and every download made before (they show in that admin's Requests). What that admin had
  already set wins over the old. If an admin is still signed in from earlier - a session lasts 30
  days and outlives a restart - it's taken over on their first visit instead.
- **The store goes into the first admin's library**, once ever: every album already in it is put in
  that admin's library and starred for them in Navidrome. That's yours - it was all yours before
  anyone else had a library. The one exception is an album somebody else's download brought in,
  which is theirs. If deadwax hasn't scanned the library yet (a new install), this waits for its first
  scan - searching, opening an album's page, or **Library care → Rescan** starts one.
- **Everyone else starts with an empty library**, apart from albums they had already starred in
  Navidrome that the store holds: those are read back and added (without a **New** mark - they were
  theirs already).
- **Plays, playlists and favourites** are Navidrome's, and stay where they are. With logins off, the
  player played as `NAVIDROME_USER`; with logins on, it plays as whoever is signed in. So if
  `NAVIDROME_USER` is your own account, your play counts and playlists carry on as yours; if it was a
  separate account, what it played and made stays that account's.

## Adding a person

1. Make them a Navidrome account.
2. Give them deadwax's address - the same one you use, `/player/` for the app (they can add it to an
   iPhone's home screen, as you did). Nothing changes in deadwax: no restart, no setting.
3. They sign in with that Navidrome user name and password.

**The first time**, they see the app without any managing: no **Managing deadwax** in You, no
**Edit** on an album. Their Library says **Nothing in your library yet.**, with **Browse the store**,
where the whole store is. Home has no pins yet; their Getting albums settings are the defaults, or what that browser's
main-page **Settings → Downloads** already says, carried over once. From
there they search, **Get** what they want, or add what the store already has. They stay signed in on
that device for 30 days from the last time they used it; **You → About → Sign out** signs them out.

To make someone an admin, add their Navidrome user name to `DEADWAX_ADMINS` and recreate the
container.

## When something changes

- **Removing a person.** There's no user list in deadwax to remove them from: delete their account
  in Navidrome, or change its password. Within about six minutes deadwax notices Navidrome no longer
  takes that login and signs them out on every device - sooner if they're using the player, whose next
  request is refused. Take their name out of `DEADWAX_ADMINS` if it's there. Nothing they got is
  deleted: it stays in the store for everyone. Their library still counts as somebody's, so their
  albums don't appear under **Held by nobody**. deadwax knows people by their Navidrome user name, so
  an account made again under the same name finds that person's pins and Getting albums settings
  waiting - but not their library: a new Navidrome account has no favourites, so within about five
  minutes deadwax reads each album as unstarred and takes it out of their library (the albums stay in
  the store, and **Browse** adds them back). If they may come back, change the password rather than
  deleting the account.
- **A forgotten password** is Navidrome's to reset: reset it there, and they sign in with the new
  one. A changed password signs them out the same way, and **You → Your library** says in red that
  deadwax can't star albums for them until they sign in again; nothing waiting is lost.
- **Wrong passwords**: after three wrong passwords for one user name within a minute, deadwax stops
  asking Navidrome about that name for the rest of the minute - "Too many tries for … - wait N seconds
  and try again" - so a mistyped password, or someone guessing, never gets the account locked in
  Navidrome itself. Other names aren't held up.
- **Navidrome down**: nobody new can sign in, since signing in asks Navidrome - except with the
  break-glass `admin`. Everyone already signed in stays signed in, but the player plays from
  Navidrome, so Home and the Library say they can't reach it; searching, **Get** and Requests still
  work, and starring waits until Navidrome is back.

What each message on the sign-in screen means: [Troubleshooting → Signing in](troubleshooting.md#signing-in).

## Admins and everyone else

| | everyone signed in | admins |
| --- | --- | --- |
| search, find on Soulseek, **Get**, join a download | yes | yes |
| play, playlists, their own library (Add, Remove), pins, Getting albums settings | yes | yes |
| their own downloads: see, cancel, retry (**Next peer**, **Ask again**), **Clear done** | yes | yes |
| leave a download somebody else is waiting for too (their ✕ on it), so it carries on for them | yes | no - an admin's ✕ cancels it for everyone |
| everyone's downloads: see who asked ("Asked by ethan"), cancel for everyone | no | yes |
| edit an album: apply a release, tags, cover, CD art, lyrics, delete it | no | yes |
| an artist's pictures, moving their albums under their current name, **Which artist is this?** | no | yes |
| **Needs a look**, **Library care** (Rescan, the bulk runs, **Held by nobody**) | no | yes |
| the server settings and the event log | no | yes |

The app doesn't show anyone else what's an admin's - **Managing deadwax** in You, the sidebar's
Managing group, **Edit** on an album, the managing on an artist's page - and deadwax refuses it if
asked anyway ("That's for deadwax's admin…"). Everyone can still look at everything in the store:
albums, their tracks, covers, lyrics and artists. Until the main page retires it still shows its
editing buttons to everyone, and refuses them the same way. A download that fails says why on the
asker's own row in Requests; the event log, which also records who signed in, is an admin's.

## Turning logins off again

Set `AUTH_MODE=off` and recreate the container. deadwax is then as it was before logins: no sign-in,
and anyone who can reach it uses it as its one admin. So keep it on your own network, or behind
something else that asks for a password.

- **Kept**: everything in deadwax's database. The pins and Getting albums settings the first admin
  took over stay with that admin, for when logins are back - so with logins off, Home starts with no
  pins, and Getting albums starts again from its defaults (or what the browser's main-page
  **Settings → Downloads** says, carried over once, as on a first visit). Each person's library, pins and kept login stay too,
  untouched, and the stars in Navidrome stay as they are (deadwax unstars nothing).
- **Back to one**: there's one library again - the whole store - and "in your library" means the
  store. Every download is listed, and **Clear done** in Requests (the main page's **Clear finished**)
  forgets every finished one. The player
  plays as `NAVIDROME_USER` again, so plays and playlists are that account's, shared by everyone.
  Nothing is starred while logins are off.
- **Switched on again later**, what was got and pinned meanwhile goes to the first admin back, as it
  did the first time, and a session used within the last 30 days is still signed in.

## What it doesn't do

- **No sign-up page**, and no way to make or change an account from deadwax: accounts are
  Navidrome's.
- **No per-person storage or quotas**: there's one store, and one copy of each album in it.
- **No private albums**: anyone signed in can browse the whole store. Your library is which albums
  are yours, not who may see them - unless Navidrome itself gives users separate libraries, in which
  case deadwax only ever plays someone a song Navidrome would give them.
- **No roles beyond admin**: someone is an admin or they aren't.
