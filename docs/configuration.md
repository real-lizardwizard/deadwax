# Configuration

There are two kinds of setting. **Server settings** belong to the container: where slskd is,
where your library is, how albums are filed. **Preferences** belong to your browser: how many
search results to ask for, which candidate filters start switched on. Both are edited in the
**Settings** tab, which has five pages: Search, Downloads, Library, Connections and Interface.
[The phone app](player.md) has a few of its own: some kept on the device, and three - how **Get**
works - [kept for you on deadwax](#your-settings-in-the-app-per-user-on-deadwax).

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
the tab's own overrides are stored, and `PUID`/`PGID` are used before the app starts. Nor can the
three [logins](#logins-environment-only) settings: the tab shows them, locked, under Connections.

### In the app

The server settings can also be changed in [the app](player.md) at `/player/`: on a desktop (a
window at least 1024 pixels wide) **Managing → Settings** in the sidebar, or **You → Server
settings** - which a phone has too since 2.0.0-player.47, laid out for it (the tabs a finger tall,
each setting's name over its field, **Save changes** in a bar along the bottom above the tab bar and
the player). It is the same server half of the settings tab - the same rows, the same three pages
(Library, Downloads, Connections), the same rules - and what is saved there is the same override,
in the same database. Changes stay drafts until **Save changes**, which saves every page's changes
at once or, if deadwax refuses one, none of them, saying why. A change made while a save is still
on its way stays a draft for the next save, and drafts are kept if you go to another page - the Log,
say - and come back, until the app is reloaded. **Re-time saved lyrics** is there too (since
2.0.0-player.42), under **Library**'s Lyrics group beside `LYRICS_LEAD_MS`, as on the settings tab: it
is refused while the lead has an unsaved change ("Save the new lead first." - it re-times to the
saved lead), reads the library from the disk, re-times one album at a time with a **stop** on its
button, and says what it did; a run keeps going, and can still be stopped, if you go to another page
and come back. What it did is said once - where it ended, or when you come back to a run that ended
while you were away - and on your next visit the line is back to its prompt. Typing a new lead lets
it go too: what it said was at the old lead, so once the new one is saved the line says its prompt,
not the old run's words. The same goes for a lead typed while a run is still going, even if you save
it before the run ends: deadwax reads the lead as it does each album, so the albums done before the
save moved to the old lead and the rest to the new one, and the line goes back to its prompt as the
run ends. Pressing it again is safe - it moves what is still at the old lead and leaves the rest.
**Clear MusicBrainz's saved answers** is there too (since 2.0.0-player.54), under **Connections**
beside its two settings, as on the settings tab ([below](#musicbrainzs-saved-answers-settings--connections)). The browser preferences (search, candidates, auto-grab, the interface) are
still the main page's settings tab's; the page says so and links to it. On a first run with Navidrome
not set up, the app's **Set up Navidrome** (on Home, the Library and Search) opens this page at
**Connections**; once the three Navidrome settings are saved, the app asks Navidrome again by itself.

## Server settings

### Connections

| setting | default | what it does |
| --- | --- | --- |
| `SLSKD_URL` | *(required)* | slskd's address **as seen from inside this container**, with the scheme: `http://slskd:5030` for a container on the same Docker network. If slskd has a URL base, include it, as in `http://slskd:5030/slskd`. It can't hold a user name or password, a `?` or `#`, or a space, and the settings tab explains exactly what's wrong with an address it can't use. One set in compose or `.env` that fails the same check is refused as well: deadwax sends slskd nothing at it, and the **Log** and the container's log say why. **Changing it takes the API key again**, typed in the same save, so the saved key is never sent to an address it wasn't entered for. Reverting it doesn't. Nor can the key from compose or `.env` be put back while the address is a new one: reverting `SLSKD_APIKEY` alone while the address in force is a different one from compose's or `.env`'s is refused, and the key's row says so before you save: type the key, or revert the address with it. With logins on, **only an admin can change it** (or the key) in the settings tab, even someone given Settings and the log: the key is full control of slskd. |
| `SLSKD_APIKEY` | *(required)* | an API key from slskd's configuration. Never shown in the page, only whether it's set. Every request to `SLSKD_URL` carries it, and it gives full control of slskd. With logins on, only an admin can change it in the settings tab. |
| `MUSICBRAINZ_EMAIL` | *(recommended)* | your contact address for MusicBrainz. The app builds its identifying user agent around it, as `deadwax/<version> ( you@example.com )`, so the version it sends is always the one running. Without a contact, MusicBrainz may refuse or throttle requests. |
| `MUSICBRAINZ_USERAGENT` | | the old way: a whole user agent written by hand. Still read, and its contact is used if `MUSICBRAINZ_EMAIL` isn't set. |
| `THEAUDIODB_KEY` | | optional. [TheAudioDB](https://www.theaudiodb.com) is a source of artist banners, logos and backgrounds for artist pages. Without it (or a fanart.tv key), an artist page shows a photograph where Wikimedia Commons has one. |
| `FANARTTV_KEY` | | optional. A [fanart.tv](https://fanart.tv) **project** key: artist thumbnails, banners, backgrounds, logos, and CD art, voted on by the people who use them. It has to be your own, because fanart.tv issues keys per application. |
| `FANARTTV_PERSONAL_KEY` | | optional, with the project key: shows you images added in the last week, which the project key alone doesn't. |

### Navidrome (Settings → Connections)

All three, for the library (since 2.0.0-player.46 deadwax needs Navidrome for it, no longer an
option): the app at `/player/` - [the phone player](player.md), and on a computer the same app laid
out for a desktop - shows and plays your library from Navidrome, so its Home shelves, Library,
albums and artists you have, and Search's look in your library say **Connect Navidrome** until every
one is set; the settings tab marks whichever is missing. Searching MusicBrainz, getting albums,
**Requests** and **You** work without them. With them set, and an address that passes the check
below, deadwax also checks every album folder against the albums Navidrome lists, raising one it
doesn't as [Not in Navidrome](library.md#not-in-navidrome), and applying a release asks Navidrome
when it has scanned before renaming a folder (see `RETAG_RENAME_WAIT` below). Point Navidrome at the
same music `LIBRARY_PATH` reads.

| setting | default | what it does |
| --- | --- | --- |
| `NAVIDROME_URL` | | Navidrome's address **as seen from inside this container**, with the scheme: `http://navidrome:4533` for a container on the same Docker network. If Navidrome runs under a base path (`ND_BASEPATH`), include it, as in `http://navidrome:4533/music`; deadwax adds `/rest` itself. It can't hold a user name or password, a `?` or `#`, or a space, and the settings tab says which. One set in compose or `.env` that fails the same check is refused as well: deadwax sends Navidrome nothing at it (the player, the settings tab and the container's log all say why), and applying a release falls back on the fixed `RETAG_RENAME_WAIT`. **Changing it takes the password again**, typed in the same save, so the saved password is never sent to an address it wasn't entered for. Clearing or reverting it doesn't. Nor can the password from compose or `.env` be put back while the address is a new one: reverting `NAVIDROME_PASSWORD` alone while the address in force is a different one from compose's or `.env`'s is refused, and the password's row says so before you save: type the password, or revert the address with it. With logins on, **only an admin can change it** in the settings tab, even someone given Settings and the log: everyone's own sign-in goes to it, and its answers say who deadwax's admins are. |
| `NAVIDROME_USER` | | the Navidrome account the player plays as. Its play counts are recorded there, and passed on to Last.fm or ListenBrainz if that account has them. It doesn't need to be an admin, and a non-admin account of your own is the one to use. With logins on, **only an admin can change it** (or its password) in the settings tab, even someone given Settings and the log: People won't touch deadwax's own account, so pointed at someone's own it would put them out of People's reach. With logins on each person's player plays as their own account instead, and this one is still needed: deadwax asks as it for what answers for nobody in particular (fetching a song once into the player's cache, whether Navidrome has finished a scan, which albums it lists), and the break-glass `deadwax` plays as it - [the player as you](player.md#the-player-as-you-with-logins-on). With Navidrome's per-user libraries, give it **every** library: a song in one it can't see won't play on an iPhone, through Gapless or on the turntable, and its folder counts as not in Navidrome. With logins off (and for the break-glass `deadwax`) the [playlists](player.md#playlists) made in deadwax are this account's - Amperfy signed in as anyone else sees them only once shared - which is one more reason it shouldn't be a Navidrome admin: deadwax shows nobody another user's private playlists either way, but an admin account in Amperfy would. (Playlists add no setting.) |
| `NAVIDROME_PASSWORD` | | that account's password. It stays in deadwax: the page only shows whether it's set, and the phone is never sent it or anything made from it. |

### MusicBrainz's saved answers (Settings → Connections)

Since 2.0.0-player.54 every answer MusicBrainz gives deadwax is saved on disk, so asking the same thing
again - a search, an artist, an album's pressings, the metadata editor's lookups, a download's
tracklist - is answered at once instead of waiting on MusicBrainz, even after deadwax restarts and even
while MusicBrainz is away. The answers are shared by everyone using deadwax. Only answers are saved,
never a failure: a minute when MusicBrainz is down is never remembered as an answer. (Before, they were
kept in memory for an hour; that hour is still there, in front of the file.)

Since 2.0.0-player.56 the app's Search also looks through everything the answers hold - every artist,
album and song in them, the songs of every album page opened included - **under any words**, and shows
what it finds first ([what deadwax has saved](finding-music.md#what-deadwax-has-saved)). For that the file
keeps an index of them beside the answers, made as each answer is saved and dropped with the last answer
that mentions a thing; its room counts toward `MUSICBRAINZ_CACHE_MB` below. A file saved by an earlier
version is read into it once, in the background, on the first start (the log says when it's done).

| setting | default | what it does |
| --- | --- | --- |
| `MUSICBRAINZ_CACHE_PATH` | *(the database's folder)* | the **folder** MusicBrainz's answers are saved in, as `musicbrainz-cache.db`, **as seen from inside this container**. Always a folder, never the file itself: deadwax makes it when it isn't there yet, and touches nothing else in it. Left empty, it is the folder `DB_PATH` is in - `/config/musicbrainz-cache.db` for most - so it is on the volume you already have. It can be the same folder as `PLAYER_CACHE_PATH`, on a fast disk ([below](#paths)). The folder has to be writable by `PUID`/`PGID`; a file of that name, or a folder holding deadwax's own database as `musicbrainz-cache.db`, is refused. **It's only a cache**: nothing in it needs backing up, deleting it is always safe (stop deadwax first, or use **Clear** below), and all it costs is speed - the next answers are asked of MusicBrainz again. The file is made when the first answer is saved. A change applies from the next answer, with no restart (the old file is left where it is). |
| `MUSICBRAINZ_CACHE_MB` | `200` | the most the saved answers take, in MB, from 0 to 1048576 - the index Search looks through included (since 2.0.0-player.56). An artist explored the app's way - searched, their page with all of their albums, one album opened and one of its songs searched - is 6 to 10 answers: 44 to 108 KB of answers, and 68 to 248 KB with the index (about 160 KB on average, measured on five artists; the more albums in their discography the more - Metallica's 539 took the most), so 200 MB holds about 1,100 of those (about 2,700 before the index). Past it, the answers used longest ago are dropped first, until the file is back under 90% of this. **`0` turns saving off**: answers are kept in memory only, for an hour, as before 2.0.0-player.54 - and Search finds nothing saved; a file already there is left as it is, and **Clear** still empties it. |

**How old an answer can be.** MusicBrainz changes - new releases, corrections - so a saved answer has
an age: a **search** is refreshed after **7 days**, and everything else - an artist, a release, an
album's pressings, an artist's discography - after **30 days**. An older answer is still shown straight
away; deadwax then asks MusicBrainz for a new one quietly behind it, for next time. That refresh waits
until nobody is waiting on MusicBrainz and nothing has been asked of it for five seconds, and goes one
at a time - so a refresh hardly ever holds up anything you ask: up to three requests asked together
still go straight away, and only a fourth asked within five seconds of a refresh waits for its turn
under MusicBrainz's rate limit, at most five seconds. If MusicBrainz doesn't answer, the saved answer
is kept and the refresh tried again the next time the answer is read from the file; if it says the
thing asked for is gone (or can't be asked that way), that answer is kept as it is and the other
refreshes go on. The screen you're looking at isn't redrawn by it. An artist's discography and an
album's pressings come from MusicBrainz a hundred at a time, and those pages are saved and refreshed
**together**: a refresh asks for every page, one turn each, and replaces the saved ones only when all
of them have come, so a long list is never put together from pages of different ages (an album shown
twice, or one missing). When one page of such a list has gone from the file, the whole list is asked
of MusicBrainz again.

**Clear MusicBrainz's saved answers**, under the two settings (on the settings tab and in the app's
Server settings, both under **Connections**), shows how many answers the file holds and how big it
is, and empties it - on disk and in memory, and what Search finds in it. Only speed is lost. It's refused while
`MUSICBRAINZ_CACHE_PATH` has an unsaved change (it clears the file that is saved) and when nothing is
saved.

The connection check (the MusicBrainz pill, and You's **Connections** in the app) never answers from
the saved answers: one saved last week can't say whether MusicBrainz can be reached now. (It keeps its
answer in memory for an hour, as it always did.)

### Paths

| setting | default | what it does |
| --- | --- | --- |
| `SLSKD_DOWNLOAD_PATH` | | where slskd's **finished** downloads appear inside this container, usually `/downloads`. It must be the same files slskd writes; see [the three folders](getting-started.md#the-three-folders). |
| `SLSKD_INCOMPLETE_PATH` | | optional: slskd's **incomplete** folder inside this container. Setting it turns on two clean-ups: a cancelled download's half-finished file is deleted, and the empty folders slskd leaves in there are cleared every ten minutes. Leave it unset to keep slskd's own behaviour, which keeps partial files so a retry can resume. |
| `LIBRARY_PATH` | | your music library inside this container, usually `/music`. Organized albums are filed here, and the library tab reads it. Everything else works without it. |
| `DB_PATH` | `/config/deadwax.db` | deadwax's database. An install from before the rename keeps using `/config/jimbrainz.db` if that's where its data is. |
| `PLAYER_CACHE_PATH` | *(the container's temporary space)* | where [the phone player](player.md#seeking-and-where-safari-lands) keeps the FLAC songs it repackages: as MP4s for Safari and iPhones, whose seeks only land where you asked in an MP4, and as the fragmented MP4s [Gapless](player.md#one-stream-for-flac) joins into one stream, in any browser, including hi-res songs resampled to 48 kHz for [Maximum quality](player.md#maximum-quality-hi-res-at-48-khz) (a resampled copy is kept apart from the song's original, and is about a quarter of its size). deadwax makes a folder of its own inside it, `deadwax-player`, private to the user it runs as, and touches nothing else there, so it can be a folder other things use too. **It's only a cache**: nothing in it needs backing up, deleting it is always safe, and a song that isn't in it is made again from Navidrome the next time it's played, which only makes that first play start a moment later. Left empty, it's the container's temporary space, which starts empty whenever the container is recreated. Best on a fast disk (an SSD); see below. A change applies to the next song, with no restart. |
| `PLAYER_CACHE_MB` | `1024` | the most that cache holds, in MB, from 64 to 1048576. A CD-quality song is 20 to 60 MB, so the default is a few albums. The songs played longest ago are cleared first. While a song is being made its download sits beside it until it's done, so the folder can briefly hold one song more than this. A song another song is waiting behind is never cleared while it's being played (it was served in the last two minutes), so a song that doesn't fit beside the ones playing waits: Safari is sent it as FLAC, and the gapless stream plays it the ordinary way. A single song bigger than the whole setting is made only while nothing else in the cache is being played, and is then kept on its own. The MP4 and the fragmented MP4 of one song are two files, and both count. With the player's [Normalization](player.md#normalization) on (the default, since 2.0.0-player.62) most FLAC songs are kept as levelled 24-bit copies, about 1.5 times a CD song's file, so the default holds fewer albums: a few GB on an SSD suits it better. Songs being measured for it are downloaded into this folder too, a few at a time, and deleted once measured. deadwax also leaves the disk 128 MB spare and needs room for two copies of the song being made: when there isn't, older songs are cleared to make room, and if there still isn't enough, Safari is sent the FLAC and the gapless stream plays that song the ordinary way. Nothing is cleared for a song clearing couldn't make room for. The desktop's [visualizer](player.md#the-visualizer) (and the phone's turntable) cut their stretches from a song's MP4 here when there is one - with Normalization on, a levelled song's own levelled copy - and otherwise - in a browser that plays the FLAC as it is, Chrome, Firefox or Edge with Gapless off and Normalization off - straight from the FLAC on Navidrome (since 2.0.0-player.23), adding nothing to the cache; only where that can't be done (the log says so once a song) is an MP4 made and kept for them, as Safari's would be. |

**Putting the caches on a fast disk.** deadwax keeps two caches: the player's songs
(`PLAYER_CACHE_PATH`) and [MusicBrainz's saved answers](#musicbrainzs-saved-answers-settings--connections)
(`MUSICBRAINZ_CACHE_PATH`). One folder on a fast disk (an SSD) can hold both: mount it into the
container and point both settings at it, as `docker-compose.example.yml` shows:

```yaml
    environment:
      - PLAYER_CACHE_PATH=/cache
      - MUSICBRAINZ_CACHE_PATH=/cache
    volumes:
      - /path/to/fast/disk/deadwax-cache:/cache
```

Inside it the player keeps its songs in a folder of its own, `deadwax-player`, and the saved answers
are one file beside it, `musicbrainz-cache.db`; neither touches anything else there. Either setting
can be left out: the player's songs then go in the container's temporary space, and the saved answers
beside the database in `/config`. The folder has to be writable by `PUID`/`PGID`: unlike `/config`,
deadwax doesn't change its owner. Leave it out of your backups. Settings → Connections shows whether
deadwax can write there for the saved answers, and Settings → Library whether it can for the player,
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
| `ORGANIZE_MODE` | `dry_run` | what happens when a download finishes. `off`: nothing. `dry_run`: the log says where each file would go, and nothing is written. `copy`: files are tagged and copied into the library, and slskd's copies stay. `move`: files are tagged and moved, and slskd's emptied folder is removed. See [Organizing](organizing.md). With [logins](#logins-environment-only) on it has to be `copy` or `move`. |
| `ALBUM_FOLDER_TEMPLATE` | `{album} ({year}) [{edition}]` | how an album's folder is named. The artist folder above it is always the artist. See [folder names](organizing.md#folder-names). |
| `COUNTRY_IN_FOLDER` | `off` | `on` lets a release's country name its folder when nothing else tells the pressing apart, as in `Dummy (1994) [GB]`. Two different releases never share a folder either way. |
| `RETAG_RENAME_WAIT` | `20` | when applying a release changes an album's tags **and** its folder, the metadata editor writes the tags first and renames the folder afterwards, because Navidrome keeps plays, ratings and favourites across either change, but not both at once. Without Navidrome set up, this is the seconds it waits between the two. **With Navidrome set up** (its three settings, [above](#navidrome-settings--connections)), it asks Navidrome instead, and renames as soon as Navidrome has finished a scan that began after the tags were written, usually a few seconds later; the number then only has to be more than 0, and is the fixed wait used if Navidrome answers from the start in a way deadwax can't use (a refused login, say). If Navidrome finishes no scan within 90 seconds, or can't be reached at all, the folder is left where it is and the editor says so; applying the album again checks with Navidrome first, and renames once it has scanned (see [troubleshooting](troubleshooting.md#applying-a-release-left-the-folder-where-it-was)). `0` renames straight away, either way. From 0 to 300. |

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
| `LYRICS_LEAD_MS` | `0` | milliseconds to move synced lyrics *earlier* as they're written (negative moves them later), from −5000 to 5000. LRCLIB's timings are tapped along by people and tend to trail the singing a little, so if lines light up a beat late in your player, try `300`. **Re-time saved lyrics**, beside it (on the settings tab, and in the app's **Managing → Settings**), applies the saved value to lyrics already saved - refused while the lead has an unsaved change. |

### The container

| setting | default | what it does |
| --- | --- | --- |
| `PUID` / `PGID` | `1000` / `1000` | the user and group the app runs as, and so the owner of every file it writes. Match them to slskd and your other media containers. |
| `TRUSTED_ORIGINS` | | environment only. Changes that another website sends are refused, by checking each request's `Origin` against the address it's being reached at. Behind a reverse proxy that rewrites the `Host` header (nginx does unless told `proxy_set_header Host $http_host`), every change looks foreign, the phone player's plays included. List the address you open deadwax at here, comma-separated with the scheme, e.g. `https://music.example.com`. It can't be set in the settings tab, because it guards that tab's own save. [Sharing deadwax](sharing.md#turning-logins-on) has a sample nginx block that passes the `Host` through instead. |

### Logins (environment only)

Off by default. With `AUTH_MODE=on`, everyone signs in with their **Navidrome** user name and
password, and only deadwax's admins - **Navidrome's admins** - and anyone an admin gives a permission to
can change the library - [Sharing deadwax](sharing.md) walks
through turning them on, what each person gets, and turning them off again. All three are read from the container's
environment (compose's `environment:` block or `.env`) and nowhere else: the settings tab, and the
app's **Managing → Settings**, show them under **Connections**, locked, saying so - a value saved
there would beat your compose file, so a wrong one could lock everyone out with no way back from the
page that saved it. Change one in compose and restart deadwax.

| setting | default | what it does |
| --- | --- | --- |
| `AUTH_MODE` | `off` | `off`: deadwax as it always was - no sign-in, and anyone who can reach the port can use it, as its one admin. `on`: everyone signs in. Anything else is read as `on`, so a typo never leaves deadwax open, and the log says so. With logins on, `/docs` and `/openapi.json` (the API's own pages) are switched off. |
| `DEADWAX_ADMINS` | | **removed in 2.0.0-player.61** - ignored now, with a line in the log at start-up saying so. deadwax's admins are Navidrome's: an account that is a Navidrome admin is deadwax's admin, read as it signs in and every few minutes after. Take it out of compose. |
| `DEADWAX_SECRET_KEY` | | **required with logins on**: at least 32 characters - make one with `openssl rand -hex 32`. Signing in keeps a token made from your Navidrome password in deadwax's database, `DB_PATH` (on Navidrome's API it is as good as the password, for as long as the password stands), encrypted with this key. Without it nobody can sign in: everything but the health check and the pages themselves answers 503, saying why, and the sign-in screen shows it. Changing it (deadwax reads it at a restart) signs everyone out, each at their next request, and deadwax can't star albums for anyone until they've signed in again. |
| `DEADWAX_ADMIN_PASSWORD` | | optional: the **break-glass** sign-in. User name `deadwax` (it was `admin` until 2.0.0-player.61), this password - an admin who needs neither Navidrome nor the database, for when Navidrome is down or nobody else can sign in (nobody being a Navidrome admin, say). It lasts 12 hours, and ends at once if this password changes. Unset, there is no such sign-in. **Make it long and random** - `openssl rand -base64 18`: the name is public, and wrong guesses are held off per address - three a minute from each, after which even the right password waits out the minute there - so a stranger's guesses hold off only the stranger, and you still get in from another address. Someone with many addresses still gets many guesses, which leaves its length as what keeps strangers out. Behind a reverse proxy every sign-in may come from the proxy's address, and then guesses through the proxy hold off yours through it too: sign in at deadwax's own address on your network instead. One shorter than 16 characters still works, but with logins on the log says so at start-up and its row in the settings tab is marked. Since `deadwax` is this sign-in's name, a Navidrome account called `deadwax` can't sign in to deadwax; Navidrome's own `admin` account signs in as itself, like anyone. |

**Who can do what.** An admin - a Navidrome admin - can do everything. Anyone else signed in can
search, find and get albums, play, pin to Home and choose their own Getting albums settings; editing
the library (applying a release, tags, covers, lyrics, CD art, an artist's pictures), deleting and
re-filing, rescans, the albums that need a look, the log and the server settings are an admin's - unless
an admin gives that person the permission for them, by category, in **You → Managing deadwax →
People** - and Get albums can be taken away. **Permissions are kept in deadwax's database, per person,
and set in People** - no setting of their own. The app doesn't show anyone what they can't use, and
deadwax refuses it (a 403 that says what it needs) - [the full table](sharing.md#admins-permissions-and-everyone-else). **Downloads are each person's own**: you see the downloads you asked for, and join one somebody else already has
on its way rather than fetching it twice; your cancel leaves a download others still want, and your
Clear done clears it from your list - an admin, or someone given Everyone's downloads, sees and
cancels everyone's. See [Downloading](downloading.md#with-logins-on-downloads-per-person).

**Organizing has to be on**: with logins on, `ORGANIZE_MODE` must be `copy` or
`move`, with `LIBRARY_PATH` and `SLSKD_DOWNLOAD_PATH` set - a download is the person's who asked for it
once it's filed, and in dry run nothing ever is. Until it is, everything but the health check and the
pages answers 503 saying why, and start-up logs it; while logins are on, the settings tab refuses a
save that would switch organizing off.

**Staying signed in.** Signing in keeps you signed in on that device for 30 days from when you last
used deadwax there, through restarts. Every few minutes deadwax asks Navidrome whether the login you
signed in with still stands, so changing your Navidrome password, or your account being deleted, signs
you out within about six minutes; Navidrome merely being down signs nobody out. Your deadwax user is
your Navidrome user name, lowercased: renamed in Navidrome, you sign in again under the new name.
Three wrong passwords for one name within a minute and deadwax stops asking Navidrome about that name
for the rest of the minute ("Too many tries"), so a mistyped password - or someone guessing - never
gets the account locked in Navidrome (the break-glass `deadwax` is counted per address instead, so
someone else's guesses hold off only their address - see `DEADWAX_ADMIN_PASSWORD` above). The session is a cookie, `deadwax_session`: HttpOnly, SameSite
Strict, and Secure when deadwax is reached over HTTPS (directly, or through a proxy that sends
`X-Forwarded-Proto`). Plain http is fine on your own network and over WireGuard; **put HTTPS in front
of deadwax before reaching it from anywhere else**, since over plain http a password and a session can
be read on the way.

**The database holds the tokens.** `DB_PATH` (`/config/deadwax.db`) keeps each signed-in session's
Navidrome token, encrypted with `DEADWAX_SECRET_KEY`, and only a hash of each session's cookie. It
also keeps each user's latest sign-in token the same way, beside the sessions - not
removed by signing out - so the albums that go into their library are starred in Navidrome as them while
they aren't signed in (see [your library](player.md#your-library-with-logins-on)); a new sign-in
replaces it, and a changed Navidrome password makes it stop working. Keep the file as private as the
key: a copy of both is as good as the passwords on Navidrome's API until they change.

**Your library**: with logins on, each person's library is their starred albums
in Navidrome - every download they asked for is added and starred as them, an album the store holds can
be added without a download, and starring or unstarring in Amperfy is read back every five minutes. No
setting: it follows `AUTH_MODE`. See [the phone player](player.md#your-library-with-logins-on).

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
| Format | Prefer lossless | **Any format**: format doesn't count. **Prefer lossless**: FLAC and other lossless formats score higher, MP3 still eligible. **Lossless only**: lossy candidates are left out. The app's **Get** has its own, kept for you on deadwax: **Format** (below), which starts from this one. |
| Auto-grab best match | off | on a new **Find**, download the top candidate straight away if it scores 75 or more. The panel says it did. It never happens on a re-search. The app's **Get** has its own, kept for you on deadwax: **When I tap Get** (below). |
| Confirm before cancelling | on | a confirmation before a download is cancelled by the Downloads panel's ✕. Cancelling loses your place in the peer's queue. The app's Requests tab has its own, in You (below), which starts from this one. |
| Candidate filters | all off | what the candidates panel starts with: a minimum score, free slot only, complete albums only, a minimum bitrate and bit depth, and the sort. |

**Interface**

| preference | default | what it does |
| --- | --- | --- |
| Open the log on start | off | show the event log when the page loads |

## The phone player's settings (per device)

[The phone player](player.md) at `/player/` keeps fourteen settings of its own, on the device, in the
app's own storage: a home-screen app keeps its storage apart from Safari's, so set them in the app
itself. None of them is on the main page's Settings tab.

| setting | default | where it is | what it does |
| --- | --- | --- | --- |
| Maximum quality | Up to 48 kHz | **You** → Playback | whether hi-res FLAC songs are resampled to 48 kHz (or 44.1 kHz) or sent as they are - see [Maximum quality](player.md#maximum-quality-hi-res-at-48-khz). Before 2.0.0-player.9 it was behind a gear beside the Library title; it keeps the setting it had there. |
| Normalization | Automatic | **You** → Playback | since 2.0.0-player.62: whether deadwax levels FLAC songs to one loudness - **Automatic** (an album you play at one level for the whole album, anything else song by song), **By song**, **By album**, or **Off** (every song sent bit for bit as before) - see [Normalization](player.md#normalization). Kept as `deadwax-player-normalization`, `song`, `album` or `off`: anything else stored there - nothing, a mistyped value, storage that can't be read - is Automatic. Used from the next thing you play. |
| Gapless | off | **You** → Playback | joins songs into one stream, or gets the next song ready on a second player - see [Gapless playback](player.md#gapless-playback-experimental). A checkbox; until 2.0.0-player.10 it was a switch on the now-playing screen, and it keeps the setting it had there. |
| Now Playing opens as | Cover | **You** → Playback | whether the now-playing screen opens as the cover or as [the turntable](player.md#the-turntable). The button at the screen's top right switches between them for as long as it's open, without changing this. The phone layout's only: [on a desktop](player.md#on-a-desktop) there's no now-playing screen, so it changes nothing there. |
| Pause winds the record down | on | **You** → Playback | whether pausing from [the turntable](player.md#the-turntable) slows the song's sound to a stop with the record over about a second (on), or stops it at once. The turntable's only: the cover's pause, the lock screen's and a song ending are always instant - and on a desktop, which has no turntable, it changes nothing. A checkbox. |
| Speed | 1x | the turntable's **speed fader**, beside the platter (and the chip that shows a speed that isn't 1x, on the cover and the desktop's player bar, which puts it back to 1x) | how fast the song plays, from 0.25x to 2x, its pitch moving with it - a record deck's speed, not a time-stretch - since 2.0.0-player.39; see [the speed fader](player.md#the-speed-fader). Kept as `deadwax-player-speed`, a number from 0.25 to 2 in hundredths: anything else stored there - nothing, a word, a number out of range - plays at 1x. It holds for every song after, until you change it. |
| Repeat | off | **Up Next**'s Repeat chip (on a desktop, the player bar's Repeat too) | off, **Repeat all** (the album or list again from the top, a new order with Shuffle on) or **Repeat one** (the song again until you skip it) - since 2.0.0-player.57; see [Up Next, shuffle and repeat](player.md#up-next-shuffle-and-repeat). Kept as `deadwax-player-repeat`, `all` or `one`: anything else stored there - nothing, a mistyped value, storage that can't be read - is off. Shuffle isn't kept: it belongs to what's playing. |
| Library view | Albums | [on a desktop](player.md#on-a-desktop), the sidebar's Library and Browse views | which view a desktop's Library opens on: Albums, Artists or Songs (since 2.0.0-player.17), or with logins on Browse's Albums, Artists or Songs. Songs is left out where Navidrome won't list songs, and the albums show instead. A desktop's **Recently added** (since 2.0.0-player.19) isn't kept: the view kept is the last of the others. Kept as `deadwax-player-library-view`. A phone doesn't use it: since 2.0.0-player.59 its Library opens on [the list](player.md#the-library), each row a page of its own. |
| Library order | Artist | a Library page's sort, on its title's row (Albums, Browse's Albums) | **Artist**, **Title**, **Recently added**, **Year, newest first**, **Year, oldest first**, **Recently played** or **Most played** - see [the Library](player.md#the-library) - since 2.0.0-player.59, one order for your albums and the store's. Kept as `deadwax-player-order`: the four that came before (Recently added, Recently played, Artist and Title) keep the values they were saved as, so a device that chose one keeps it; anything else stored there - nothing, a mistyped value - is Artist. Until 2.0.0-player.59 the default was Recently added, which now has its own place: the Library list's grid and its **See all**. |
| Artists order | Name | a Library page's sort, on Artists (and Browse's Artists) | **Name** (under letters, with the index) or **Most albums**. Kept since 2.0.0-player.59 as `deadwax-player-artist-order`: `albums` is Most albums, and anything else stored there is Name. Until then it went back to Name each time. |
| Visualizer effect | Ambient | the [visualizer](player.md#the-visualizer)'s effects, at its top right | Bars, Scope, Halo or Ambient (since 2.0.0-player.20) - what it opens on next time; **V** steps through them too. The visualizer is a desktop's, so on a phone this changes nothing. |
| Visualizer colour | From the cover | the visualizer's **Colour** | From the cover (the playing album's) or Purple (deadwax's own). |
| Ambient style | Mandala | the visualizer's **Style** list, shown with Ambient | Mandala, Waves, Liquid, Burst, Ribbons, Smoke, Rings or Embers - or **Rotate all**, through all eight in that order. |
| Confirm before cancelling | on | **You** → Getting albums, under the three kept on deadwax | whether the Requests tab's **✕** asks first (since 2.0.0-player.41; until then the app read the main page's setting of that name in the same browser - which a home-screen app never had - and always asked there). Kept as `deadwax-player-confirm-cancel`. The first time a device reads it, it starts from the main page's **Confirm before cancelling** in that browser (above), once: off if that's off, and otherwise on - from then on the two are separate. A checkbox. |

The Requests tab's **✕** asks before cancelling, by **Confirm before cancelling** - in the card
itself (**Keep it** or **Cancel download**), never as a pop-up, which would hold up the music.

## Your settings in the app (per user, on deadwax)

Three settings in the app's **You → Getting albums** (since 2.0.0-player.15; Format since
2.0.0-player.41) decide what **Get** does
([Get, and choosing a source](downloading.md#on-the-phone-get-and-choosing-a-source)). They are kept
**on deadwax, per user** - not on the device - so they follow you from the phone to a browser and
back. With logins off (the default) everyone using deadwax shares one set, on every device; with
logins on each person has their own, and the first Navidrome admin to sign in takes over the ones chosen before
([sharing deadwax](sharing.md#what-happens-to-what-you-had)). Each is a list to tap in You: the choice shows at once and
is saved behind it, and if deadwax can't keep it (its database isn't writable) it goes back to what
deadwax has and You says so. Choices made quickly are saved one after another, in the order you made
them, so the last one is what stays. The app asks deadwax for them each time You is opened, on
**Check again** under Connections, and before every search the sources start - a Get, another Get or
pressing while a desktop's Sources panel stays open, **Try again**, **Re-search** - so a change made
on another device shows without closing the app. Until deadwax has first answered, nothing shows as
chosen and nothing can be, and a Get shows the sources.

| setting | default | what it does |
| --- | --- | --- |
| When I tap Get | Show me the sources | **Show me the sources**: Get opens the list of folders found on Soulseek, and you choose. **Pick the best source for me**: Get takes the best match itself when it scores 75 or more and passes your quality floor, queues it and shows Requests - and shows you the sources, saying why, when nothing does, when you already have the pressing (whole or in part) or it is already downloading, or when it is the album as a whole (a row's Get when MusicBrainz couldn't list the pressings: with no tracklist, no score can be trusted). Never on a Re-search. |
| Quality floor | Any | what a source must at least be: **Any**, **320 kbps** (lossless passes too), **Lossless** (every file lossless; a folder whose format couldn't be told doesn't pass) or **24-bit**. It's what a pick must pass, and what the sources start filtered by - as a chip pressed above them (Lossless, 24-bit, or a 320 kbps chip, shown only while that's your floor), so it's never a filter on out of sight: tap the chip to see everything. |
| Format | Prefer lossless | what every Get's search is scored by, as the main page's **Format** (above) is for its Find: **Any** - format doesn't count; **Prefer lossless** - a folder with no lossless file scores lower on the score's Format part (0.45 of it, where a folder with one scores all of it), still offered; **Lossless only** - such folders are left out of the sources altogether. It changes the score; the quality floor doesn't - it only filters what was found. Every search waits for deadwax's answer to the ask it starts with (above), so a Format changed on another device is the one the search is scored by. With Lossless only, an album Soulseek has only in lossy formats says "Nothing lossless on Soulseek for …", naming this setting, rather than that nothing was found. |

The first time the app asks for them, with nothing saved yet, the quality floor starts from what the
main page's **Candidate filters** (above) say in that browser: a minimum bit depth of 24 is
**24-bit**, of 16 is **Lossless** (only lossless files report a bit depth), and a minimum bitrate
of 320 is **320 kbps**; anything else is Any. **Format** starts from the main page's **Format**
(above). **When I tap Get** always starts at Show me the sources - the main page's Auto-grab is not
carried over. That happens once: from then on the app and the main page keep their own copies, and
changing one doesn't change the other. A setting added in a later version is carried over once in
the same way, on its own: if the app had already carried yours over before Format existed
(2.0.0-player.15 to .40), it carries over Format alone the next time it asks - never the floor
again, over what you've chosen since. (A home-screen app keeps its own storage, apart from Safari's,
so on a phone the main page's preferences usually aren't there to start from, and the defaults
stand.) Only what differs from the defaults is saved, so a default changed in a later version still
reaches you if you never chose otherwise.

They're stored in deadwax's database (`DB_PATH`), in its `user_prefs` table - a row for each one
you chose, and one more that lists which settings have been carried over for you, which is how
that carrying over happens only once for each - through `GET` and `PUT /deadwax/me/preferences`.

**What you pin to Home** (since 2.0.0-player.18) is kept the same way: on deadwax, per user, in its
`pins` table - never as a star in Navidrome. It isn't a setting: the album, artist and now-playing
screens pin and unpin, and Home's Edit reorders ([Home and pins](player.md#home-and-pins)).
