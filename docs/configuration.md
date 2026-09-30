# Configuration

There are two kinds of setting. **Server settings** belong to the container: where slskd is,
where your library is, how albums are filed. **Preferences** belong to your browser: how many
search results to ask for, which candidate filters start switched on. Both are edited in the
**Settings** tab, which has five pages: Search, Downloads, Library, Connections and Interface.

![The Connections page of the settings tab, saying where each setting came from](../assets/images/settings.png)

## Where a server setting comes from

A server setting can be given in three places. The first one found wins:

1. **The settings tab.** A value saved there is stored in deadwax's database and applies
   immediately, with no restart. The row says it's overriding your compose file, and
   **Revert** removes the override so the compose value applies again.
2. **The `environment:` block** of your compose file.
3. **A `.env` file** next to the compose file.

If none of them sets it, the default below applies. On start-up, the log names the source of
each setting it read, which helps when a value isn't the one you expected. Settings → Library
also shows every path as the container sees it, and whether it exists and can be read and
written.

Two settings can't be changed from the settings tab, and the tab says why: `DB_PATH` is where
the tab's own overrides are stored, and `PUID`/`PGID` are used before the app starts.

## Server settings

### Connections

| setting | default | what it does |
| --- | --- | --- |
| `SLSKD_URL` | *(required)* | slskd's address **as seen from inside this container**, with the scheme: `http://slskd:5030` for a container on the same Docker network. If slskd has a URL base, include it, as in `http://slskd:5030/slskd`. It can't hold a user name or password, a `?` or `#`, or a space, and the settings tab explains exactly what's wrong with an address it can't use. One set in compose or `.env` that fails the same check is refused as well: deadwax sends slskd nothing at it, and the **Log** and the container's log say why. **Changing it takes the API key again**, typed in the same save, so the saved key is never sent to an address it wasn't entered for. Reverting it doesn't. |
| `SLSKD_APIKEY` | *(required)* | an API key from slskd's configuration. Never shown in the page, only whether it's set. Every request to `SLSKD_URL` carries it, and it gives full control of slskd. |
| `MUSICBRAINZ_EMAIL` | *(recommended)* | your contact address for MusicBrainz. The app builds its identifying user agent around it, as `deadwax/<version> ( you@example.com )`, so the version it sends is always the one running. Without a contact, MusicBrainz may refuse or throttle requests. |
| `MUSICBRAINZ_USERAGENT` | | the old way: a whole user agent written by hand. Still read, and its contact is used if `MUSICBRAINZ_EMAIL` isn't set. |
| `THEAUDIODB_KEY` | | optional. [TheAudioDB](https://www.theaudiodb.com) is a source of artist banners, logos and backgrounds for artist pages. Without it (or a fanart.tv key), an artist page shows a photograph where Wikimedia Commons has one. |
| `FANARTTV_KEY` | | optional. A [fanart.tv](https://fanart.tv) **project** key: artist thumbnails, banners, backgrounds, logos, and CD art, voted on by the people who use them. It has to be your own, because fanart.tv issues keys per application. |
| `FANARTTV_PERSONAL_KEY` | | optional, with the project key: shows you images added in the last week, which the project key alone doesn't. |

### The phone player (Settings → Connections)

Optional, and all three or none: [the phone player](player.md) at `/player/` is off until every
one is set, and the settings tab marks whichever is missing. With them set, and an address that
passes the check below, applying a release also asks Navidrome when it has scanned before
renaming a folder (see `RETAG_RENAME_WAIT` below).

| setting | default | what it does |
| --- | --- | --- |
| `NAVIDROME_URL` | | Navidrome's address **as seen from inside this container**, with the scheme: `http://navidrome:4533` for a container on the same Docker network. If Navidrome runs under a base path (`ND_BASEPATH`), include it, as in `http://navidrome:4533/music`; deadwax adds `/rest` itself. It can't hold a user name or password, a `?` or `#`, or a space, and the settings tab says which. One set in compose or `.env` that fails the same check is refused as well: deadwax sends Navidrome nothing at it (the player, the settings tab and the container's log all say why), and applying a release falls back on the fixed `RETAG_RENAME_WAIT`. **Changing it takes the password again**, typed in the same save, so the saved password is never sent to an address it wasn't entered for. Clearing or reverting it doesn't. |
| `NAVIDROME_USER` | | the Navidrome account the player plays as. Its play counts are recorded there, and passed on to Last.fm or ListenBrainz if that account has them. It doesn't need to be an admin, and a non-admin account of your own is the one to use. |
| `NAVIDROME_PASSWORD` | | that account's password. It stays in deadwax: the page only shows whether it's set, and the phone is never sent it or anything made from it. |

### Paths

| setting | default | what it does |
| --- | --- | --- |
| `SLSKD_DOWNLOAD_PATH` | | where slskd's **finished** downloads appear inside this container, usually `/downloads`. It must be the same files slskd writes; see [the three folders](getting-started.md#the-three-folders). |
| `SLSKD_INCOMPLETE_PATH` | | optional: slskd's **incomplete** folder inside this container. Setting it turns on two clean-ups: a cancelled download's half-finished file is deleted, and the empty folders slskd leaves in there are cleared every ten minutes. Leave it unset to keep slskd's own behaviour, which keeps partial files so a retry can resume. |
| `LIBRARY_PATH` | | your music library inside this container, usually `/music`. Organized albums are filed here, and the library tab reads it. Everything else works without it. |
| `DB_PATH` | `/config/deadwax.db` | deadwax's database. An install from before the rename keeps using `/config/jimbrainz.db` if that's where its data is. |
| `PLAYER_CACHE_PATH` | *(the container's temporary space)* | where [the phone player](player.md#seeking-and-where-safari-lands) keeps the FLAC songs it repackages: as MP4s for Safari and iPhones, whose seeks only land where you asked in an MP4, and as the fragmented MP4s [Gapless](player.md#one-stream-for-flac) joins into one stream, in any browser, including hi-res songs resampled to 48 kHz for [Maximum quality](player.md#maximum-quality-hi-res-at-48-khz) (a resampled copy is kept apart from the song's original, and is about a quarter of its size). deadwax makes a folder of its own inside it, `deadwax-player`, private to the user it runs as, and touches nothing else there, so it can be a folder other things use too. **It's only a cache**: nothing in it needs backing up, deleting it is always safe, and a song that isn't in it is made again from Navidrome the next time it's played, which only makes that first play start a moment later. Left empty, it's the container's temporary space, which starts empty whenever the container is recreated. Best on a fast disk (an SSD); see below. A change applies to the next song, with no restart. |
| `PLAYER_CACHE_MB` | `1024` | the most that cache holds, in MB, from 64 to 1048576. A CD-quality song is 20 to 60 MB, so the default is a few albums. The songs played longest ago are cleared first. While a song is being made its download sits beside it until it's done, so the folder can briefly hold one song more than this. A song another song is waiting behind is never cleared while it's being played (it was served in the last two minutes), so a song that doesn't fit beside the ones playing waits: Safari is sent it as FLAC, and the gapless stream plays it the ordinary way. A single song bigger than the whole setting is made only while nothing else in the cache is being played, and is then kept on its own. The MP4 and the fragmented MP4 of one song are two files, and both count. deadwax also leaves the disk 128 MB spare and needs room for two copies of the song being made: when there isn't, older songs are cleared to make room, and if there still isn't enough, Safari is sent the FLAC and the gapless stream plays that song the ordinary way. Nothing is cleared for a song clearing couldn't make room for. |

**Putting the player's cache on a fast disk.** Mount a folder into the container and point
`PLAYER_CACHE_PATH` at it, as `docker-compose.example.yml` shows:

```yaml
    environment:
      - PLAYER_CACHE_PATH=/cache
    volumes:
      - /path/to/fast/disk/deadwax-cache:/cache
```

The folder has to be writable by `PUID`/`PGID`: unlike `/config`, deadwax doesn't change its
owner. Leave it out of your backups. Settings → Library shows whether deadwax can write there,
and what's wrong with its own `deadwax-player` folder inside it, if anything. It uses that folder
only while it's a real folder (not a link), owned by the user deadwax runs as, and open to nobody
else (mode 700), which is how deadwax makes it. The setgid bit an OpenMediaVault shared folder
passes on to folders made inside it doesn't matter. One that isn't, say after `PUID` changed or
when something else made it first, is left alone: delete it, and deadwax makes a new one. A disk
that doesn't keep file permissions (CIFS, NTFS or exFAT) can't hold the cache; use a
Linux-formatted one. Until then,
and whenever the cache can't be used at all, Safari is sent the FLAC, which plays but whose seeks
can land seconds off.

### Organizing

| setting | default | what it does |
| --- | --- | --- |
| `ORGANIZE_MODE` | `dry_run` | what happens when a download finishes. `off`: nothing. `dry_run`: the log says where each file would go, and nothing is written. `copy`: files are tagged and copied into the library, and slskd's copies stay. `move`: files are tagged and moved, and slskd's emptied folder is removed. See [Organizing](organizing.md). |
| `ALBUM_FOLDER_TEMPLATE` | `{album} ({year}) [{edition}]` | how an album's folder is named. The artist folder above it is always the artist. See [folder names](organizing.md#folder-names). |
| `COUNTRY_IN_FOLDER` | `off` | `on` lets a release's country name its folder when nothing else tells the pressing apart, as in `Dummy (1994) [GB]`. Two different releases never share a folder either way. |
| `RETAG_RENAME_WAIT` | `20` | when applying a release changes an album's tags **and** its folder, the metadata editor writes the tags first and renames the folder afterwards, because Navidrome keeps plays, ratings and favourites across either change, but not both at once. Without Navidrome set up, this is the seconds it waits between the two. **With Navidrome set up** (the phone player's three settings), it asks Navidrome instead, and renames as soon as Navidrome has finished a scan that began after the tags were written, usually a few seconds later; the number then only has to be more than 0, and is the fixed wait used if Navidrome answers from the start in a way deadwax can't use (a refused login, say). If Navidrome finishes no scan within 90 seconds, or can't be reached at all, the folder is left where it is and the editor says so; applying the album again checks with Navidrome first, and renames once it has scanned (see [troubleshooting](troubleshooting.md#applying-a-release-left-the-folder-where-it-was)). `0` renames straight away, either way. From 0 to 300. |

### Soulseek searches (Settings → Downloads)

| setting | default | what it does |
| --- | --- | --- |
| `SLSKD_SEARCH_TIMEOUT` | `8` | seconds each Soulseek search listens for answers, from 3 to 60. Peers answer over several seconds, slow and firewalled ones last, so a longer search hears from more of them and a shorter one gets you a list sooner. |

### When a download fails (Settings → Downloads)

| setting | default | what it does |
| --- | --- | --- |
| `AUTO_RETRY_PEER` | `off` | `on` moves a failed download to the next peer from the list you picked it from, by itself. It's off by default because the next peer down may be a different pressing or a worse rip. **Try next peer** on a failed download works either way. |

### Cover art

| setting | default | what it does |
| --- | --- | --- |
| `COVER_ART_SIZE` | `500` | how big a cover to save from the Cover Art Archive: `250`, `500`, `1200` or `full`. `full` is the original upload, often several megabytes. |

### Lyrics

| setting | default | what it does |
| --- | --- | --- |
| `FETCH_LYRICS` | `on` | look up lyrics on [LRCLIB](https://lrclib.net) for each album as it's filed, and save them as a `.lrc` file beside each track. It only ever adds files, and nothing is fetched in dry run. |
| `LYRICS_LEAD_MS` | `0` | milliseconds to move synced lyrics *earlier* as they're written (negative moves them later), from −5000 to 5000. LRCLIB's timings are tapped along by people and tend to trail the singing a little, so if lines light up a beat late in your player, try `300`. **Re-time saved lyrics**, beside it, applies a new value to lyrics already saved. |

### The container

| setting | default | what it does |
| --- | --- | --- |
| `PUID` / `PGID` | `1000` / `1000` | the user and group the app runs as, and so the owner of every file it writes. Match them to slskd and your other media containers. |
| `TRUSTED_ORIGINS` | | environment only. Changes that another website sends are refused, by checking each request's `Origin` against the address it's being reached at. Behind a reverse proxy that rewrites the `Host` header (nginx does unless told `proxy_set_header Host $http_host`), every change looks foreign, the phone player's plays included. List the address you open deadwax at here, comma-separated with the scheme, e.g. `https://music.example.com`. It can't be set in the settings tab, because it guards that tab's own save. |

## Preferences (per browser)

These are stored in your browser, so each browser and device has its own. They're the
*starting* state for each search; you can still change anything on the spot.

**Search**

| preference | default | what it does |
| --- | --- | --- |
| Results to ask for | 50 | how many release groups a search asks MusicBrainz for (1-100) |
| Studio albums only | off | start every search with the type filter set to studio albums, leaving out live albums, compilations, interviews, demos, remixes and DJ mixes. The filter button says when it's on. |
| Sort | Year (oldest first) | how search results are ordered |

**Downloads**

| preference | default | what it does |
| --- | --- | --- |
| Format | Prefer lossless | **Any format**: format doesn't count. **Prefer lossless**: FLAC and other lossless formats score higher, MP3 still eligible. **Lossless only**: lossy candidates are left out. |
| Auto-grab best match | off | on a new **Find**, download the top candidate straight away if it scores 75 or more. The panel says it did. It never happens on a re-search. |
| Ask before cancelling | on | a confirmation before a download is cancelled. Cancelling loses your place in the peer's queue. |
| Candidate filters | all off | what the candidates panel starts with: a minimum score, free slot only, complete albums only, a minimum bitrate and bit depth, and the sort. |

**Interface**

| preference | default | what it does |
| --- | --- | --- |
| Open the log on start | off | show the event log when the page loads |

## The phone player's settings (per device)

[The phone player](player.md) at `/player/` keeps four settings of its own, on the device, in the
app's own storage: a home-screen app keeps its storage apart from Safari's, so set them in the app
itself. None of them is on the main page's Settings tab.

| setting | default | where it is | what it does |
| --- | --- | --- | --- |
| Maximum quality | Up to 48 kHz | **You** → Playback | whether hi-res FLAC songs are resampled to 48 kHz (or 44.1 kHz) or sent as they are - see [Maximum quality](player.md#maximum-quality-hi-res-at-48-khz). Before 2.0.0-player.9 it was behind a gear beside the Library title; it keeps the setting it had there. |
| Gapless | off | **You** → Playback | joins songs into one stream, or gets the next song ready on a second player - see [Gapless playback](player.md#gapless-playback-experimental). A checkbox; until 2.0.0-player.10 it was a switch on the now-playing screen, and it keeps the setting it had there. |
| Now Playing opens as | Cover | **You** → Playback | whether the now-playing screen opens as the cover or as [the turntable](player.md#the-turntable). The button at the screen's top right switches between them for as long as it's open, without changing this. |
| Library order | Recently added | **Library**, above the grid | Recently added, Recently played, Artist or Title |
