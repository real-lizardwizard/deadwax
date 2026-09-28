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
  the library tab reads whatever is there.
- **Optionally, [Navidrome](https://www.navidrome.org)** and an account on it of your own (not
  an admin one), for [the phone player](player.md). Nothing else needs it.

## The three folders

This is the part worth getting right the first time. The container needs three folders
mounted into it:

| inside the container | what it is | on your host |
| --- | --- | --- |
| `/downloads` | **slskd's finished-downloads folder** | the *same* folder slskd writes finished downloads into |
| `/music` | your library, where organized albums are filed | wherever your music lives |
| `/config` | deadwax's database: which download is which release, your settings, the saved library scan | any folder of its own |

The first one is where almost every first-run problem comes from. A finished download is
written into slskd's own downloads folder, and deadwax has to find those files to file them. So the
host folder you mount at `/downloads` must be **the same host folder** slskd's container has
mounted as its downloads directory. If the two disagree, downloads still work but organizing
quietly finds nothing.

```
host: /srv/media/slskd/downloads ──┬── mounted into slskd  as its downloads folder
                                   └── mounted into deadwax as /downloads
```

A fourth folder is optional: slskd's **incomplete** folder, mounted at `/incomplete` with
`SLSKD_INCOMPLETE_PATH=/incomplete` set. With it, cancelling a download also deletes the
half-finished file slskd kept, and the empty folders slskd leaves behind in there are cleared
every ten minutes. Without it, slskd's own behaviour stands: it keeps partial files so a retried
download can resume.

## The compose file

Start from [`docker-compose.example.yml`](../docker-compose.example.yml) in the repository.
The essentials look like this:

```yaml
services:
  deadwax:
    image: ghcr.io/real-lizardwizard/deadwax:latest
    container_name: deadwax
    restart: unless-stopped
    environment:
      - SLSKD_DOWNLOAD_PATH=/downloads
      - LIBRARY_PATH=/music
      - DB_PATH=/config/deadwax.db
      - SLSKD_URL=http://slskd:5030
      - SLSKD_APIKEY=your-slskd-api-key
      - MUSICBRAINZ_EMAIL=you@example.com
      - PUID=1000
      - PGID=1000
    volumes:
      - /srv/media/slskd/downloads:/downloads
      - /srv/media/music:/music
      - /srv/appdata/deadwax:/config
    ports:
      - "8080:8080"
```

A few things to know:

- **`SLSKD_URL` is the address of slskd as seen from inside this container**, which is often not
  the one you type into a browser. If slskd is another container on the same Docker network, use
  its service name and internal port: `http://slskd:5030`. Include the `http://`; deadwax says
  exactly what's wrong with a URL it can't use.
- **`PUID` and `PGID`** are the user and group the app runs as, and so who owns every file it
  writes into your library. Set them to the same values as slskd and your other media
  containers. `id yourname` on the host prints them.
- **Settings can go in `environment:` or in a `.env` file** beside the compose file (start from
  [`.env.example`](../.env.example)), or both. If a setting is in both, `environment:` wins.
  A `.env` keeps your API key out of a file you might paste somewhere.
- **Write literal values in `environment:`.** `SLSKD_URL=${SLSKD_URL}` reads compose's *own*
  environment, and when that's empty it still counts as set, so it quietly overrides your
  `.env`. The log warns about this at start-up if it happens.
- **Which image tag.** `:latest` is the current release. `:experimental` is rebuilt on every push
  to the development branch and moves under you. `:0.2.1` and older are the original
  Lidarr-based app, which doesn't understand any of these settings.

Every setting is described in [Configuration](configuration.md).

## The first run

1. **Start it** and open `http://your-server:8080`.
2. **Check the two connection pills** at the top: MusicBrainz and slskd. Green means connected.
   A red one names the problem, such as `NOT_LOGGED_IN` when slskd is running but not signed in
   to Soulseek, or `CONNECTION_ERROR` when it can't be reached at all. On a phone the pills
   only appear when something is wrong.
3. **Open Settings → Library.** Every configured path is shown as the container sees it,
   checked for whether it exists and can be read and written. There's also a plain statement
   of whether organizing is ready, listing everything that's stopping it. If a path is wrong,
   this is where it shows.
4. **Download something small.** Search for an album, pick a pressing, press **Find**, then
   **Download** on a good candidate. [Finding music](finding-music.md) and
   [Downloading](downloading.md) walk through it.
5. **Watch the log** (the **Log** button, top right). Organizing starts in **dry run**, so when
   the download finishes the log says where each file *would* have been filed, and nothing is
   written. Check the paths look right.
6. **Switch organizing on.** In Settings → Library → Organizing, set `ORGANIZE_MODE` to `copy`
   (files are copied into the library and slskd's copies stay) or `move` (they're moved, and
   slskd's emptied folder is cleaned up). A setting saved in the settings tab takes effect
   straight away, with no restart.

## Running it day to day

- **The settings tab overrides compose.** A value saved there is stored in deadwax's database
  and wins over your compose file and `.env`, and the row says it's overriding. **Revert**
  deletes the override, so the compose value applies again.
- **Updating** is pulling the new image and recreating the container. The database in `/config`
  carries everything over.
- **The image has a health check.** `/deadwax/health` answers 200 while the background download
  poller is running and 503 if it has stopped. Neither slskd nor MusicBrainz being down makes
  deadwax unhealthy, because restarting deadwax wouldn't fix them.
- **There is no login.** Anyone who can reach the port can use it, so keep it on your own
  network or put it behind something that asks for a password.
- **On your phone**, the main page works as it is, and `/player/` is a separate player for
  your library, played from Navidrome, that you can add to an iPhone's home screen. To use either
  away from home, reach deadwax over a VPN such as WireGuard or Tailscale rather than an open
  port. See [the phone player](player.md).

## Coming from jimbrainz

It's the same app under its old name. Point your stack at
`ghcr.io/real-lizardwizard/deadwax` instead of `…/jimbrainz`. Nothing else needs changing: an
existing `/config/jimbrainz.db` keeps being used where it is. Don't rename the file by hand.
