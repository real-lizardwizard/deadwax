# Getting started

From nothing to a first album filed in your library. It takes about ten minutes, most of it
spent getting three folder paths to agree.

## What you need

- **Docker**, with compose. Anything that runs a compose stack works: plain `docker compose`,
  Komodo, Portainer, Dockge.
- **A running slskd** ([slskd.org](https://slskd.org)), logged in to Soulseek, with an **API key**
  set in its configuration (under `web` → `authentication` → `api_keys`). Every search and
  download goes through slskd; deadwax never talks to Soulseek directly.
- **An email address** to give MusicBrainz as a contact. They ask every app for one, and rate
  limit the ones that don't send it.
- **A folder for your music library.** An empty one is fine, and so is an existing library:
  deadwax reads whatever is there.
- **[Navidrome](https://www.navidrome.org)**, reading the same music folder, and an account on it
  of your own (not an admin one). [The app](player.md) - on a phone, and on a computer laid out for a
  desktop - shows and plays your library from Navidrome, so it needs one for the library. Searching, getting albums and following downloads work without it.

## The three folders

This is the part worth getting right the first time. The container needs three folders
mounted into it:

| inside the container | what it is | on your host |
| --- | --- | --- |
| `/downloads` | **slskd's finished-downloads folder** | the *same* folder slskd writes finished downloads into |
| `/music` | your library, where organized albums are filed | wherever your music lives |
| `/config` | deadwax's database: which download is which release, your settings, the saved library scan - and, beside it, MusicBrainz's [saved answers](configuration.md#musicbrainzs-saved-answers-settings--connections) (`musicbrainz-cache.db`, only a cache, unless `MUSICBRAINZ_CACHE_PATH` names another folder) | any folder of its own |

The first one is where almost every first-run problem comes from. A finished download is
written into slskd's own downloads folder, and deadwax has to find those files to file them. So the
host folder you mount at `/downloads` must be **the same host folder** slskd's container has
mounted as its downloads directory. If the two disagree, downloads still work but organizing
quietly finds nothing.

```
host: /srv/media/slskd/downloads ──┬── mounted into slskd  as its downloads folder
                                   └── mounted into deadwax as /downloads
```

A fourth folder is optional: slskd's **incomplete** folder, mounted at `/incomplete`, with
`SLSKD_INCOMPLETE_PATH` set to `/incomplete` in Settings → Library. With it, cancelling a download also deletes the
half-finished file slskd kept, and the empty folders slskd leaves behind in there are cleared
every ten minutes. Without it, slskd's own behaviour stands: it keeps partial files so a retried
download can resume.

## The compose file

Start from [`docker-compose.example.yml`](../docker-compose.example.yml) in the repository. It holds
only what Docker needs - everything else is set in the app once it's running:

```yaml
services:
  deadwax:
    image: ghcr.io/real-lizardwizard/deadwax:latest
    container_name: deadwax
    restart: unless-stopped
    env_file:
      - path: .env
        required: false
    volumes:
      - /srv/media/slskd/downloads:/downloads
      - /srv/media/music:/music
      - /srv/appdata/deadwax:/config
    ports:
      - "8080:8080"
```

A few things to know:

- **Change only the left side of each volume** - your host's folders. The right side is where the image
  looks: it sets `SLSKD_DOWNLOAD_PATH=/downloads` and `LIBRARY_PATH=/music` itself, and keeps its
  database in `/config`.
- **`.env` sits beside the compose file**, and is optional: with `required: false` compose starts
  deadwax without one (that form of `env_file` needs Docker Compose 2.24 or newer - `docker compose
  version` says which you have). Start from [`.env.example`](../.env.example). It's the place for
  what you'd rather not keep in deadwax's database or can't set in the app: slskd's API key and
  Navidrome's password if you like, **`PUID` and `PGID`**, and the logins.
- **`PUID` and `PGID`** are the user and group the app runs as, and so who owns every file it
  writes into your library. Set them to the same values as slskd and your other media
  containers. `id yourname` on the host prints them. Both are 1000 unless `.env` says otherwise.
- **Everything else** - slskd's address and key, MusicBrainz's email, Navidrome, organizing, cover art,
  lyrics, the caches - starts at a default and is set in **Server settings** after the first start
  ([below](#the-first-run)). Any of it can be an environment variable instead:
  [every variable deadwax reads](configuration.md#environment-variables), with its default, where it's
  set in the app, and how to give one (literal values, and why a line under `environment:` beats `.env`
  even when it's empty).
- **Which image tag.** `:latest` is the current release. `:experimental` is rebuilt on every push
  to `main`, so it runs ahead of `:latest` and moves under you. `:0.2.1` and older are the original
  Lidarr-based app, which doesn't understand any of these settings.

**Already have a longer compose file?** It goes on working exactly as it is - a setting it gives still
applies, and one saved in Server settings still beats it. To trim it, take a setting's line out,
recreate the container, and set the setting again in Server settings. It can't be saved there first:
Server settings saves only a value that differs from the one it shows, so typing in the one compose
already gives saves nothing, and taking the line out would then lose it. An address goes with its key
or password - take both out, and type both in the same save. Leave `DB_PATH` and any path you mounted
somewhere other than `/downloads` and `/music` where they are. **With logins on, leave `ORGANIZE_MODE`
and the three `NAVIDROME_` lines too** (or switch logins off while you trim): with organizing back at
dry run nobody can reach Server settings to set it again, and without Navidrome only the break-glass
`deadwax` can sign in.

## The first run

1. **Start it** and open `http://your-server:8080` - that opens the app, at `/player/`.
2. **Fill in Server settings → Connections** - the desktop sidebar's **Server settings**, or **You → Manage →
   Server settings** on a phone - and **Save changes**; it applies at once:
   - **`SLSKD_URL`**, slskd's address **as seen from inside this container**, which is often not the
     one you type into a browser: for another container on the same Docker network, its service name
     and internal port, `http://slskd:5030`. Include the `http://`; deadwax says exactly what's wrong
     with an address it can't use.
   - **`SLSKD_APIKEY`**, an API key from slskd's configuration, in the same save. If you'd rather keep
     the key in `.env`, put `SLSKD_URL` there with it and leave both out of the app: a key from `.env`
     is only ever sent to the address from `.env`, so a new address saved in the app takes the key again.
   - **`MUSICBRAINZ_EMAIL`**, your contact address for MusicBrainz.

   Then **check You → Connections**: MusicBrainz, slskd and Navidrome. **Connected** means connected;
   otherwise it says what's wrong in a word, with a sentence under it saying where to put it right -
   **Not on Soulseek** when slskd is running but not signed in to Soulseek, **Can't reach it** when it
   can't be reached at all ([troubleshooting](troubleshooting.md#yous-connections-says-slskd-isnt-connected)).
   Connections is for whoever runs deadwax: with logins on, only admins and anyone given **Settings and
   the log** see it.
3. **Open Settings → Library**. Every configured path is shown as the container sees it,
   checked for whether it exists and can be read and written. There's also a plain statement
   of whether organizing is ready, listing everything that's stopping it. If a path is wrong,
   this is where it shows.
4. **Download something small.** Search for an album, open it, pick a pressing, press **Get the
   album**, then **Get** on a good source. [Finding music](finding-music.md) and
   [Downloading](downloading.md) walk through it.
5. **Watch the log** (the sidebar's **Event log**, or **You → Manage → Event log**). Organizing starts in **dry run**, so when
   the download finishes the log says where each file *would* have been filed, and nothing is
   written. Check the paths look right.
6. **Switch organizing on.** In Settings → Library → Organizing, set `ORGANIZE_MODE` to `copy`
   (files are copied into the library and slskd's copies stay) or `move` (they're moved, and
   slskd's emptied folder is cleaned up). A setting saved in Server settings takes effect
   straight away, with no restart.
7. **Set up Navidrome.** Point Navidrome at the same music folder you mounted at `/music`, then fill
   in `NAVIDROME_URL` (Navidrome's address as this container sees it, such as
   `http://navidrome:4533`), `NAVIDROME_USER` and `NAVIDROME_PASSWORD` in Settings → Connections (or uncomment the three
   `NAVIDROME_` lines in your `.env`, copied from `.env.example`, and recreate the container) -
   [the app's setup](player.md#setting-it-up) has the details. Then Home and the Library show your
   albums from Navidrome (with
   logins on, the Library is each person's own and **All music** is the collection - [sharing
   deadwax](sharing.md)).

**What the app shows without Navidrome.** Home's shelves, the Library tab, the albums and artists
you have and Search's look in your library each say **Connect Navidrome** (or **Can't reach
Navidrome**, with the reason and **Try again**) and how to set it up, in place of your albums -
and, to anyone who doesn't run deadwax, **Your music isn't available yet** (or **right now**) and to
tell whoever does, never Navidrome's address or a setting. The
rest works without it: Search's MusicBrainz rows, an album you don't have and its **Get**,
**Requests**, Home's arriving downloads and **You**. An album folder Navidrome doesn't list - not
scanned yet, unreadable, or outside Navidrome's music folder - is never out of reach: **Needs a
look** raises it as **Not in Navidrome** (see [the library](library.md#not-in-navidrome)).

## Running it day to day

- **Server settings overrides compose.** A value saved there is stored in deadwax's database
  and wins over your compose file and `.env`, and the row says it's overriding. **Revert to the
  environment** deletes the override, so the compose value applies again.
- **Updating** is pulling the new image and recreating the container. The database in `/config`
  carries everything over.
- **The image has a health check.** `/deadwax/health` answers 200 while the background download
  poller is running and 503 if it has stopped. Neither slskd nor MusicBrainz being down makes
  deadwax unhealthy, because restarting deadwax wouldn't fix them.
- **There is no login unless you turn logins on** ([below](#turning-logins-on)). With logins off - the
  default - anyone who can reach the port can use it, so keep it on your own network or put it
  behind something that asks for a password.
- **On your phone**, the app is the same app, laid out for it, and you can add it to an iPhone's
  home screen. To use it away from home, reach deadwax over a VPN such as WireGuard or Tailscale
  rather than an open port. See [the app](player.md).

## Turning logins on

To share deadwax with other people, turn logins on: everyone then signs in with their own
**Navidrome** account and has their own requests, library, plays and playlists, over the one collection,
and Navidrome's admins are deadwax's admins (an admin can give anyone else a part of that, in People). Up to
three settings, in the container's environment - `.env`, where `.env.example` has them waiting, not
Server settings, which only shows them. The secret key is a key made with `openssl rand -hex 32`, and
goes in `.env` only - a line for it under compose's `environment:` as well, even an empty one, beats
`.env` ([Sharing deadwax, step 1](sharing.md#turning-logins-on)):

```bash
AUTH_MODE=on
DEADWAX_SECRET_KEY=<the key>
# optional - signs in `deadwax` with no Navidrome, for when Navidrome is down:
#DEADWAX_ADMIN_PASSWORD=
```

To manage deadwax you sign in as a **Navidrome admin** account - make yours one in Navidrome's own Users
page if it isn't, or keep a separate admin account for managing. Navidrome has to be set up (step 7),
since signing in asks it, and organizing has to be on -
`ORGANIZE_MODE` `copy` or `move` (step 6) - or deadwax refuses everything, saying why. Recreate the
container, open deadwax, and sign in. Put HTTPS in front of it before reaching it from outside your
own network; plain http is fine there and over WireGuard.

**[Sharing deadwax](sharing.md) is the full story**: what each person gets and what stays shared,
each setting, what happens to what you had (the first Navidrome admin to sign in takes it over), adding
and removing people (People, in You), what admins can do that others can't and the permissions they can
give, and turning logins off again. Every setting's
row: [Configuration → Logins](configuration.md#logins-environment-only). If you're locked out, see
[Troubleshooting](troubleshooting.md#signing-in).

## Coming from 1.x

**Your library now comes from Navidrome.** 1.x browsed `LIBRARY_PATH` itself; the app's Library
tab, album and artist pages, Home's shelves and the player show what Navidrome lists, and say
**Connect Navidrome** until it's set up ([setting it up](player.md#setting-it-up)) - with logins on,
**Your music isn't available yet** to anyone who doesn't run deadwax. Search's
MusicBrainz results, Get, Requests, Needs a look and Library care work without it.

The old page at `/` retired in 2.0.0: `/` opens the app. With Navidrome set up, everything it did is
in the app - a bookmark or a home-screen icon for `/` lands there - and a browser that used the old page has its
Format, quality floor and Confirm before cancelling carried over the first time it opens the app
([configuration](configuration.md#your-settings-in-the-app-per-user-on-deadwax)). The last version
with that page is the git tag `last-main-page`.

## Coming from jimbrainz

It's the same app under its old name. Point your stack at
`ghcr.io/real-lizardwizard/deadwax` instead of `…/jimbrainz`. Nothing else needs changing: an
existing `/config/jimbrainz.db` keeps being used where it is. Don't rename the file by hand.
