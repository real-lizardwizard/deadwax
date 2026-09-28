# Troubleshooting

By symptom. Two places answer most questions before anything else: **Settings → Library**,
which checks every path from inside the container and says whether organizing is ready and what's
stopping it, and the **Log**, which has the reasons behind anything that failed, in slskd's or
MusicBrainz's own words where there are any.

## Downloads finish, but nothing appears in my library

In order of likelihood:

1. **Organizing is in dry run.** It's the default. The log says where each file *would* have
   gone. Set `ORGANIZE_MODE` to `copy` or `move` in Settings → Library → Organizing.
2. **`/downloads` isn't slskd's downloads folder.** The host folder mounted at `/downloads` has
   to be the same one slskd writes finished downloads into. If they differ, the files are
   downloaded but deadwax can't find them. Compare the two containers' volume lines. See
   [the three folders](getting-started.md#the-three-folders).
3. **`LIBRARY_PATH` isn't set, or isn't writable.** Settings → Library shows whether it
   exists and can be written, as the container sees it. A path that exists on the host but
   isn't mounted into the container looks perfectly correct from outside.
4. **Permissions.** Files are written as `PUID`/`PGID`. If the library folder belongs to someone
   else, writing fails and the log says so.
5. **The album was already there.** A track the album's folder already has (in any format) is
   never filed again, so a second copy of an album is left in slskd's folder, and the download
   reads *already in the store*. See [organizing](organizing.md).

## The slskd pill is red

- **`CONNECTION_ERROR`**: slskd can't be reached at `SLSKD_URL` from inside the container. Use
  the address the *container* would use (`http://slskd:5030` on a shared Docker network), with
  the `http://`.
- **`NOT_LOGGED_IN` / `NOT_CONNECTED` / `CONNECTING`**: slskd is running but isn't signed in
  to Soulseek. Check slskd's own page. If slskd runs behind a VPN container, it may be waiting
  for the VPN, and the pill says so.
- **`401`**: slskd rejected the API key. Check `SLSKD_APIKEY` against the key in slskd's
  configuration.
- **`UNKNOWN_ERROR`** with **"SLSKD_URL is unusable (…)"** in the **Log**: the address in your
  compose file or `.env` fails the check the settings tab makes on save - a user name or
  password in it, a `?` or `#`, a space, no `http://` - and the brackets say which. deadwax won't
  send slskd anything at such an address, the API key least of all. Fix it in Settings →
  Connections or in compose. A reverse proxy in front of slskd that asks for a login of its own
  can't be reached this way; point deadwax at slskd directly.
- **`UNKNOWN_HTTP_ERROR` / `UNKNOWN_ERROR` / `UNEXPECTED`** otherwise: slskd answered with
  something unexpected. The log has the details.

## The MusicBrainz pill is red

- **`VALUE_ERROR`**: no contact is set. Set `MUSICBRAINZ_EMAIL` (Settings → Connections).
- **`CONNECTION_ERROR` / `MAX_RETRIES_EXCEEDED` / `UNKNOWN_ERROR`**: MusicBrainz couldn't be
  reached, or kept failing. It goes away for minutes at a time now and then (below); if it
  persists, check the container can reach the internet.

## A search fails with "not logged in", or slskd refused it

Searches are refused while slskd isn't signed in to Soulseek; it answers with a `409`, which the
panel explains. It also runs one search at a time, so a search started while another is still
running can be refused with "Only one concurrent operation is permitted": wait and search again.

## A search finds nothing

- Soulseek only returns folders whose paths contain **every word** of the query. Edit the
  **Query** to fewer words (the album title alone, say) and **Re-search**.
- Try a longer `SLSKD_SEARCH_TIMEOUT` (Settings → Downloads): slow and firewalled peers answer
  last.
- The panel says every name it searched under; hover over the query box to see them.

## A download sits at "queued"

It's waiting in the user's upload queue: **queue #N** says how far back you are. A user with a
**free slot** starts straight away. If slskd stops reporting the transfers altogether, the
download fails after about two minutes. Use **↻ next peer** to move it to someone else.

## MusicBrainz is slow, or searches fail

MusicBrainz goes slow or unreachable for minutes at a time, sometimes taking 30-60 seconds a
request. A failed search says it couldn't reach MusicBrainz, which is different from finding
nothing. Try again in a minute. Set `MUSICBRAINZ_EMAIL`: without a contact address, MusicBrainz
may throttle or refuse requests, and the log says so.

A search MusicBrainz rejects as invalid (odd punctuation in a fielded search) says so at once,
rather than retrying.

## The library tab is empty, or doesn't show a change

- **"LIBRARY_PATH is not set"**: set it (Settings → Library → Paths) and mount the folder.
- **An empty library** when you know it isn't empty usually means the volume isn't mounted in
  the container. Settings → Library shows whether the path exists.
- **A change made by another program doesn't show up**: tags edited elsewhere don't change a
  folder's date, which is what the library watches. Press **Rescan**.

## Lots of albums say "Folder off-convention"

Their folder names don't match what the template makes from their tags: albums filed by
another tool, or filed before you changed `ALBUM_FOLDER_TEMPLATE`. Changing the template never
moves anything. Applying the album's release in the metadata editor re-files it.

## No cover, or "No cover on the Archive"

The Cover Art Archive has no front cover for that release. It's a fact about the release, not
a failure. Pick a different release in the metadata editor if a sibling pressing has one. If it
says the request **failed**, the Archive was unreachable; try again later.

## Lyrics are missing, or land late

- LRCLIB doesn't have every song, and instrumentals get no `.lrc` by design. When LRCLIB is under
  load it asks clients to back off, and a track is retried a few times before it's counted as
  failed; **Get lyrics** tries again.
- If lines light up a beat after they're sung, set `LYRICS_LEAD_MS` (try `300`) and press
  **Re-time saved lyrics**.

## A song shows a different picture from its album

Your player is showing a picture embedded in the file, or a disc scan (`cd.jpg`) for songs with a
disc number. The album's **Properties** list which tracks carry their own pictures, and the
track view shows them. **Get CD art** saves a proper `disc.jpg`, which Navidrome prefers over a
`cd.jpg`.

## The artist page can't work out who this is

When the files have no MusicBrainz artist ids and the name is shared by more than one artist,
the page asks you to choose, with each one's description. Choosing one uses its id from then on.

## Settings I changed in compose don't take effect

A value saved in the settings tab **overrides** compose and `.env`, and the row says so. Press
**Revert** on it to go back to the compose value. Also check you didn't write
`SETTING=${SETTING}` in `environment:`, which quietly sets it to empty when compose has no such
variable of its own; the log warns about this at start-up.

## Saving or pressing a button says "Refused: it came from another website"

deadwax only accepts changes from its own page, to stop another website you have open from
deleting albums or starting downloads through your browser. It checks that each request comes
from the address deadwax is being reached at. If you reach it through a reverse proxy that
rewrites the `Host` header (nginx does by default), every change looks as if it came from
somewhere else. Either pass the original `Host` through - in nginx,
`proxy_set_header Host $http_host;`, which keeps the port (`$host` drops it, so a proxy on a port
other than 80 or 443 also needs `proxy_set_header X-Forwarded-Port $server_port;`) - or set
`TRUSTED_ORIGINS` in the container's environment to the address you open deadwax at, such as
`https://music.example.com`. The event log names the address it refused.

## Applying a release pauses before the folder is renamed

That's deliberate. When applying a release changes an album's tags **and** its folder, the
editor writes the tags first and renames the folder afterwards, so Navidrome keeps the album's
plays, ratings and favourites. With Navidrome set up (Settings → Connections), it waits until
Navidrome has scanned the new tags, usually a few seconds, and **Apply** reads *Applying, waiting
for Navidrome*. Without it, or with a `NAVIDROME_URL` the settings tab marks as unusable, it
waits a fixed time, and the button names it (*Applying, renaming in 20s*): `RETAG_RENAME_WAIT`
(Settings → Library → Organizing), 20 seconds by default. Set that to `0` to rename straight
away, which loses those plays and favourites in Navidrome.

## Applying a release left the folder where it was

The editor says the tags were written but the folder was left in place, for one of two reasons:

- *Navidrome hasn't finished a scan since*: for 90 seconds deadwax asked Navidrome, and no scan
  finished.
- *Navidrome couldn't be reached*: nothing answered at Navidrome's address - the connection was
  refused, the name didn't resolve, or no answer came within 5 seconds - either at the start or
  for the rest of the wait. A Navidrome that isn't answering may be restarting, and it scans as
  it starts up, which would see the new tags and the new name together.

Either way, renaming then would have lost the album's plays, ratings and favourites in
Navidrome. The album has its new tags; only the rename is waiting.

**What to do:** once Navidrome is back and has scanned (start a scan from its web page if you
like), open the album in the editor again and apply the same release. The preview says *The tags
were written by an earlier apply*, and Apply writes no tags this time: deadwax asks Navidrome
first, and renames the folder straight away if Navidrome has finished a scan since. If it
hasn't, the apply waits for one as the first did, and leaves the folder in place again if none
comes within 90 seconds.

deadwax only remembers a held-back rename until it restarts. Applying the album after a restart
renames the folder straight away, without asking Navidrome, so let Navidrome scan first. The
same goes once Navidrome has been taken out of the settings, or `RETAG_RENAME_WAIT` set to `0`.

If it happens on every apply, Navidrome isn't noticing changes by itself. Its file watcher is
what scans a changed folder a few seconds later, and it can't when:

- Navidrome's library is on a network share, or another mount that doesn't report changes to
  files, so the watcher never hears about them;
- the watcher or the scanner is switched off in Navidrome's own settings
  (`ND_SCANNER_WATCHERWAIT=0`, or `ND_SCANNER_ENABLED=false`);
- Navidrome isn't reading the folder deadwax files albums into.

Fix whichever it is, and re-apply the albums that were held back once Navidrome has scanned.
Where the scanner is on but the watcher can't see changes (the network share), a scan schedule
(`ND_SCANNER_SCHEDULE`) also works: an apply is held back unless a scheduled scan happens to
finish within its 90 seconds, and re-applying after the next one renames at once. A schedule
doesn't help with `ND_SCANNER_ENABLED=false`, which turns off the watcher and any schedule
alike. A very busy library can hold an apply back now and then too: Navidrome waits for a few
quiet seconds before it scans, and an album being filed, or a bulk cover or lyrics run, keeps
putting that off.

Two related cases don't hold the rename back, and the **Log** says which. If Navidrome keeps
answering but deadwax can't use what it says (a refused login, an error from Navidrome or a
proxy in front of it, a scan status it can't read), there's no telling whether it has scanned.
When that's so from the first question, deadwax waits the fixed `RETAG_RENAME_WAIT` and renames.
When the first questions were answered but not one after them could be used, the folder is
renamed at the end of the 90 seconds, as a fixed wait would have done.

Behind a reverse proxy with a short timeout (60 seconds is common), an apply that waits the full
90 seconds can outlast it, and the page shows an error although the apply finished. Reopen the
album to see where it stands.

## The player says "Connect Navidrome" or "Can't reach Navidrome"

The [phone player](player.md) shows one of these in place of your albums, with the reason under
it.

- **Connect Navidrome**: the three Navidrome settings aren't all set. Fill in `NAVIDROME_URL`,
  `NAVIDROME_USER` and `NAVIDROME_PASSWORD` in Settings → Connections, which marks the one
  that's missing. The container's log also names it at start-up.
- **"NAVIDROME_URL is unusable (…), so deadwax sends nothing to it"**: the address in your
  compose file or `.env` fails the check the settings tab makes on save - a user name or
  password in it, a `?` or `#`, a space, no `http://` - and the brackets say which. deadwax won't
  send Navidrome anything at such an address. Fix it in Settings → Connections or in compose.
  Until then, applying a release waits the fixed `RETAG_RENAME_WAIT` instead of asking Navidrome.
- **"Navidrome couldn't be reached at …"**: deadwax can't connect to that address. It's the
  address as seen from inside the deadwax container, so on a shared Docker network use
  Navidrome's service name and internal port (`http://navidrome:4533`), not `localhost` and not
  the address your phone or browser uses. Check the two containers share a network.
- **"the answer wasn't a Subsonic one"**, **"the answer wasn't JSON"**, **"Navidrome answered
  404"**, or anything ending **"is NAVIDROME_URL the address of Navidrome itself?"**: something
  answered, but not Navidrome's API. Usually it's the path: leave off any `/app` or `/rest`
  (deadwax adds `/rest` itself), and include Navidrome's base path if it has one (`ND_BASEPATH`,
  as in `http://navidrome:4533/music`). A reverse proxy in front of Navidrome that asks for a
  login of its own does it too (it often shows as **"Navidrome answered 401"**); point deadwax at
  Navidrome directly.
- **"Navidrome refused the login"**: the account name or password is wrong. Type the password
  again in Settings → Connections: the tab never shows the saved one, so a typo is easy to miss.
  After several failed logins in a row Navidrome may refuse even the right password for a short
  while, so give it a minute before **Try again**.
- **"Navidrome can't use token logins for this user"**: Subsonic apps sign in with a token made
  from the password, and this account can't. Give the player an ordinary account made in
  Navidrome itself.
- **"Navidrome answered 500"**, or another number of 500 or more: Navidrome itself is failing.
  Check its own log.

## Saving settings says "type the Navidrome password again with the new address"

Every request deadwax sends Navidrome carries a login made from the password, so it won't send
the saved password to a new address until the password has been typed for it. Change
`NAVIDROME_URL` and type `NAVIDROME_PASSWORD` too, then save both at once. Saving the address it
already is, clearing it, or reverting it doesn't need the password.

## Saving settings says "type the slskd API key again with the new address"

Every request deadwax sends slskd carries the API key, and the key gives full control of slskd,
so deadwax won't send the saved key to a new address until it has been typed for it. Change
`SLSKD_URL` and type `SLSKD_APIKEY` too, then save both at once; the key's row says so in red
before you save. Saving the address it already is, or reverting it, doesn't need the key.

## Plays don't show up in Navidrome

- **A song counts once you've heard half of it or four minutes**, whichever comes first, and only
  songs longer than 30 seconds count. Skipping ahead adds nothing, so a song you skipped through
  isn't a play.
- **Plays go to the `NAVIDROME_USER` account.** Look at that account's play counts.
- **Behind a reverse proxy that rewrites the `Host` header**, deadwax takes the player's play
  reports for requests from another website and refuses them, and the phone doesn't say so. The
  main page's **Log** names each refusal. Pass the original `Host` through, or set
  `TRUSTED_ORIGINS`, as [below](#saving-or-pressing-a-button-says-refused-it-came-from-another-website).
- **Counted in Navidrome, but not on Last.fm or ListenBrainz**: that part is Navidrome's. Check
  the account has them linked there, and that scrobbling is switched on for the `deadwax` player
  on Navidrome's **Players** page.

## The player page is blank

This only happens running deadwax from source. `/player/` loads a script built from `ui/`, which
isn't in a fresh checkout: run `npm run build` in `ui/`, which builds the main page's panels at
the same time. The Docker image builds it for you.

## A song in the player won't start, or can't be skipped through

A song that won't play while the music is meant to be playing doesn't stop the queue. The player
asks for it once more a moment later, picking up where it stopped if it got part-way, and if it
fails again it moves on to the next song and says so under that song's title for a few seconds:
**Skipped "…" - it wouldn't play**. A file that arrived but can't be decoded isn't asked for
twice: **Skipped "…" - its file couldn't be decoded**. At the end of the queue there's nothing to
move on to, so playing stops there with the reason on screen, and if nothing was playing (you
pressed next while paused, say) the reason is only shown. Tap play on a song that failed to ask
for it again.

- **Some files are transcoded.** The player sends a file as it is when the phone says it can play
  it, and asks Navidrome for an MP3 of anything else: on an iPhone, mostly Ogg (Vorbis or Opus)
  and WMA. A transcode is made as it plays, so the first time you play one you can't skip through
  it, and its length is only an estimate. Let it play; once Navidrome has cached it, it behaves
  like any other file.
- **A transcoding is set for `deadwax` on Navidrome's Players page.** It replaces the MP3 the
  player asked for, and can hand the phone a format it can't play. Leave that player's
  Transcoding and Max Bit Rate unset; [the phone player](player.md#formats-and-navidromes-players-page)
  explains why.
- **A limit on transcodes in Navidrome.** There's none unless you set one
  (`ND_TRANSCODING_MAXCONCURRENT`, or `ND_TRANSCODING_MAXCONCURRENTPERUSER`). With one set, a
  transcode over it is refused, and the phone can't tell that apart from audio it can't play: it
  shows as *Couldn't play this song - Navidrome didn't send audio this device can play*, or as
  the song being skipped. Tap it again after a few seconds, or raise the limit.
- **"Couldn't play this song - Navidrome didn't send audio this device can play"** or **"This
  song's file couldn't be decoded"**: the file may be damaged, or in a format neither the phone
  nor the transcode could manage. Try it in Navidrome's own web player. The first message is
  also how any refused request looks from inside the page: a transcode limit (above), or a song
  whose album was re-applied in the metadata editor while it sat in the queue, which Navidrome
  may now know by another id. For that one, open the album again from the grid.
- **"The connection dropped while this song was loading"**: the phone lost deadwax (a VPN
  dropping, say), or deadwax lost Navidrome. The player asks again by itself; if it has stopped,
  tap play.

## The log says a transcode "ended at … of the … bytes Navidrome estimated"

That line, followed by `ASGI callable returned without completing response` from the web
server, is expected after every transcoded song, and isn't an error. Navidrome can only estimate
a transcode's length, and closes the connection where the transcode really ends, which is close
to the estimate; deadwax passes that on to the phone the same way.

**"Navidrome stopped sending song … after N of M bytes"**, a warning followed by the same
web-server line, is different: the connection to Navidrome broke part-way through a file, from
Navidrome restarting or the network between the two. Worded **"after N of the M bytes Navidrome
estimated"**, it's a transcode that stopped well short of its estimate (under 90% of it, often
nothing at all): the transcode failed, and Navidrome's own log usually says why. Either way the
song stops where it broke, and the player may ask for it again by itself; if it doesn't carry
on, play it again.

## The page looks wrong after an update

Reload it. The page is never cached without checking, but a tab left open across an upgrade
keeps the old page until it's reloaded.
