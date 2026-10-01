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

## A download says "N file(s) failed to organize"

Some of its files couldn't be written into the library. The ones that could are there, and the
album shows as **New** in the library like any other filed download. The rest are still in
slskd's folder (a move never clears that folder out while anything failed). The container's own
log names each file and why, most often permissions or a full disk. Fix that, then either copy
the missing tracks across and apply the album's release in the metadata editor, or download the
album again: a track the album's folder already has is never filed twice, so only the missing
ones are added.

When it goes on **", no track was filed"**, none of its music reached the library (a cover may
have: that makes a folder, but no album, and nothing is marked **New**), which usually means the
library folder can't be written (see [Downloads finish, but nothing appears in my
library](#downloads-finish-but-nothing-appears-in-my-library)). The app's Requests tab says
**Partly filed** for the first and **Not filed** for the second. A row from before deadwax
2.0.0-player.12, where nothing landed, has no such ending and reads **Partly filed**; **Clear
done** removes it.

## A download says "deadwax stopped while filing this"

deadwax was stopped or restarted while it was filing that album, so it can't tell how far it got.
Look at the album in the library (**Rescan** first) and in slskd's downloads folder: in move mode,
whatever hadn't been filed yet is still in slskd's folder, and in copy mode all of it is. Anything
missing is dealt with as in the section above. **Clear finished** removes the row (**Clear done**
in the app's Requests tab, where it reads **Interrupted while filing**).

## Find says "Already downloading", but nothing is

**Find** won't search for a pressing while a download of all of it is queued or arriving, and
names the user it's coming from. Open **Downloads** (or the app's **Requests** tab): the download
is there, and cancelling it (or letting it fail) lets **Find** search again. A download of only
part of it, such as one disc's folder, doesn't stop the search: it's a note above the results.

"Already downloaded", with "being filed into your library now", means every file has arrived and
it's being filed. That takes seconds. A download that finished while organizing was off is never
filed later, and stops counting two minutes after it finished. One that deadwax was stopped or
restarted part-way through filing stops counting as soon as deadwax starts again, which marks it
"deadwax stopped while filing this" (above).

## Find says you have only some of a pressing you have all of

The note ("You have 9 of 10 tracks of this pressing") counts the release's tracks in the folder,
matching each file by its title, and by its disc and track number when the title isn't the
release's. A file whose title and numbers are both different from MusicBrainz's (a track tagged by
hand, or from another database) isn't counted. Applying the release to the album in the library
tab's metadata editor gives every file the release's titles and numbers, and then it counts. The
search still runs, so nothing is lost meanwhile.

## Find says "Already in your library", but I want another copy

deadwax won't fetch a second copy of a pressing you have complete. The panel names the folder. To
replace it, delete the album in the library tab first, then **Find** again. A different pressing
of the same album is searched as usual, with a note that you have the other one.

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
download fails after about two minutes. Use **↻ retry** to ask the same user again, or **↻ next
peer** to move it to someone else.

## The app's Requests tab shows nothing moving, or "Can't get your requests from deadwax"

The Requests tab (and Home's Arriving, and the count on the tab) shows what deadwax knows of each
download, and the progress as slskd reports it.

- **slskd can't be reached** (it refuses the connection, or isn't there): every download is still
  listed, but nothing moves - "0 of 10 files", no speed, queued ones "starting". After about two
  minutes of slskd reporting nothing,
  deadwax gives up on them and they move to **Needs attention** as "no transfers reported by
  slskd". **Next peer** and **Ask again** can't get anywhere until slskd is back, and the row says
  why, in red. A download slskd still lists but can't move - slskd signed out of Soulseek, or
  waiting for its VPN - just stops where it is until slskd is back. You's **Connections** says
  whether slskd answers, and [The slskd pill is red](#the-slskd-pill-is-red) goes through the
  reasons. **slskd up but not answering** (it takes the connection and then says nothing) is
  slower to show: deadwax waits on it, so the tab keeps its spinner, or the last answer, until the
  phone gives up on the request, and then says it can't get your requests.
- **"Can't get your requests from deadwax"**, with the reason under it: deadwax itself didn't
  answer (restarting under Komodo, say, or the phone off your network or VPN). What's below is
  from the last answer, and it keeps asking while the tab is open. Home's Arriving says the same
  ("Can't reach deadwax just now") and keeps asking while something is on its way.
- **A spinner, and nothing else**: the app hasn't had deadwax's first answer yet. It never says
  "Nothing requested yet" before it knows.
- **"Downloads aren't being kept track of"**: deadwax can't write its database, so it can't list
  or file downloads. They still arrive in slskd's folder. Check `DB_PATH` and that the folder it's
  in can be written as `PUID`/`PGID`.
- **A download started on the main page doesn't show**: the app looks again when Home or Requests
  comes into view and when you come back to it. Switch to Requests, or pull it back up from the
  background.

## MusicBrainz is slow, or searches fail

MusicBrainz goes slow or unreachable for minutes at a time, sometimes taking 30-60 seconds a
request. A failed search says it couldn't reach MusicBrainz, which is different from finding
nothing. Try again in a minute. Set `MUSICBRAINZ_EMAIL`: without a contact address, MusicBrainz
may throttle or refuse requests, and the log says so.

A search MusicBrainz rejects as invalid (odd punctuation in a fielded search) says so at once,
rather than retrying.

## The app's Search says MusicBrainz isn't answering, or keeps asking

The phone app's [Search tab](finding-music.md#on-the-phone-the-apps-search-tab) and its album pages
ask MusicBrainz through deadwax, so the same slow minutes reach them.

- **"MusicBrainz isn't answering just now - it often goes away for a few minutes."** under **Not in
  your library yet** - or, on an album you don't have, **"MusicBrainz isn't answering just now, so
  this album's pressings couldn't be loaded - it often goes away for a few minutes."**: deadwax
  couldn't get an answer (it retries for a while first). That's not the same as **Nothing on
  MusicBrainz for "…"**, which is an answer.
  Tap **Try again** in a minute; the album page never shows part of a pressing list as if it were
  all of it. You's **Connections** says whether deadwax can reach MusicBrainz at all, and [The
  MusicBrainz pill is red](#the-musicbrainz-pill-is-red) goes through why it might not.
- **"Asking MusicBrainz…" for a long time**: on a bad day MusicBrainz takes 30-60 seconds a
  request. An album page fetches every pressing's tracklist, which for an album with hundreds of
  pressings is several requests one after another. Once it has them it keeps them while the app is
  open (the last 20 albums), so going back to the album is instant.
- **The library half shows nothing, or "Can't reach Navidrome"**: that half is Navidrome's search,
  and needs Navidrome as Home does ([below](#the-player-says-connect-navidrome-or-cant-reach-navidrome));
  MusicBrainz is still searched under it.
- **An album you have is listed under Not in your library yet**: only albums whose files carry
  MusicBrainz's id for the ALBUM (the release group) are recognised there.
  - With no MusicBrainz ids at all: match it to its release in the main page's metadata editor,
    which writes them, then search again.
  - **An .m4a album deadwax filed** carries the pressing's id but not the album's - deadwax can't
    write that one into an .m4a yet, and the metadata editor can't either - so it stays listed. Its
    own page (tap it) does say "in your library", since that checks every pressing's id. Tagging it
    with Picard, which writes the album's id into .m4a files, makes the list leave it out too.
  - The first search after deadwax restarts can show one for a moment and then mark it "· in your
    library" in place: deadwax looks through the whole library before it first answers.

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

## A downloaded reissue is filed under its reissue's year

Before 1.0.2, a download was filed under the year of the pressing you picked, and with no
original-year tag: a 2011 remaster of a 1975 album went to `Wish You Were Here (2011) [...]`
instead of `(1975)`. The library flags these as **No original year**. Open one in the metadata
editor and apply its release: that writes the original year and moves the folder. Downloads
since 1.0.2 are filed under the album's year.

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

The [phone player](player.md) shows one of these on Home and in the Library tab, in place of your
albums, and in Search in place of what's in your library, with the reason under it. The other tabs
(and Search's MusicBrainz half, and an album you don't have) work without Navidrome, and You's
**Connections** shows Navidrome as **Not set up** or **Can't reach it**, with the same reason under it.

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
fails again it moves on to the next song and says so for a few seconds, in the mini player where
the artist goes and above the song's title on the now-playing screen:
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

## The now-playing screen no longer shows how the song was sent, or the last gap and seek

They moved in 2.0.0-player.10, and nothing was taken away. The two lines that sat between the cover
and the song's title (the last song changes, and *Last seek* ending with how the song came) are
now in **Info → Debug**: tap **•••** on the now-playing screen, then **Info**, then **Debug**. They
are labelled rows now rather than lines, so some of the wording moved. The last song change is the
**Gap** row, in the old words less "Last song change" (up to four before it on an *Earlier* line,
where the old line said "before:"), and the last seek the **Last seek** row, less "Last seek:". How
the song came, which ended the old seek line (`· FLAC in MP4, 192 kHz resampled to 48 kHz`), is the
**Sent as** row (`FLAC in MP4, 24-bit, 48 kHz`), with the resampling on a **Resampled** row of its
own (`192 kHz to 48 kHz, 3 dB quieter`), and two rows that are new, **Why** and **Gapless**
([the phone player](player.md#info--debug) lists them all). The **Gapless** switch that sat beside
the album's name is a checkbox in **You**, under **Playback**, and keeps the setting it had.

## The turntable shows a plain black record, not the album's CD art

The record's face is the CD art deadwax holds for the album - a `disc.jpg` (or `disc2.jpg` for a
song on disc 2) beside its tracks - and the plain record, with the cover as its label, is what it
shows when it can't find one. In the order to check:

- **The album has no CD art yet.** On the main page's Library tab, press **Get CD art** on the
  album (it's only there while the album has none). When the Cover Art Archive and fanart.tv have
  no picture of the disc either, there's none to be had. A `cd.jpg` that came with a download
  doesn't count: it's whatever its sharer scanned.
- **The album isn't tagged with a release.** deadwax finds the album's folder by the MusicBrainz
  release id in its files, which Navidrome reads. An untagged rip has none: match a release in the
  metadata editor, then Get CD art.
- **Navidrome hasn't read the new tags yet, or can't be reached.** You's **Connections** says
  whether Navidrome answers. After a retag, Navidrome notices the files by itself a few seconds
  later.
- **deadwax hasn't seen the folder.** It knows the library's folders from its scans and from what
  it files; one copied in by another program is unknown until the main page's Library tab has
  been opened (or **Rescan**).
- **It was saved while the turntable was showing.** The turntable looks again each time the
  now-playing screen opens: close it and open it again, or switch to the cover and back with the
  button at the top right. (A picture replaced by hand can take up to five minutes to change: the
  phone keeps one that long.)

## With Gapless on, there's still a pause between songs, or the player reloads by itself

[Gapless](player.md#gapless-playback-experimental) (in **You**, under **Playback**) is an
experiment, and **Info → Debug** (**•••** on the now-playing screen, then **Info**, then **Debug**)
says how each song change went, in its **Gap** row. Compare it with Gapless off on the same phone
and connection: the difference is what Gapless saves.

FLAC songs are meant to play [in one stream](player.md#one-stream-for-flac), the Gap row reading
`0 ms, in one stream`:

- **`in one stream` with a number above 0**: the stream had to wait for the next song's audio. The
  connection couldn't keep 30 seconds ahead, or deadwax was still making the next song (its first
  play: deadwax downloads it from Navidrome whole first). Once the song is in the player's cache,
  it shouldn't happen again for that song.
- **FLAC songs reading `handed over` or `one element` instead**: they didn't go into a stream. A
  stream only starts from a tap (Play, a song, Next, Previous), so after a song that played the
  other way the next ones do too until you tap. It also ends before a song that isn't FLAC, has
  more than two channels, or comes from a file of another sample rate than the songs before it
  (hi-res songs join under both Maximum quality choices). It doesn't start while the
  sound is on AirPlay, and after three failures in a row, or a cache deadwax can't use, it's off for
  10 minutes. A song deadwax won't repackage says why in deadwax's log, in a line starting
  `player: song`.
- **The song carried on, but Sent as went from `In one stream` to something else mid-song** (and
  Gapless from `On, in one stream` to `On`):
  the stream couldn't go on (the connection dropped for too long, deadwax couldn't send a song,
  or the browser couldn't play what it was sent), and the song carried on from where it had got
  to. In Safari a seek in that one song can land a little off. The next tap starts a stream again.

For the second player, which gets everything else ready:

- **`download unfinished`**: the next song hadn't finished downloading when this one ended, so it
  was streamed, taking as long as with Gapless off. On a connection that can't download a
  whole song while the one before plays, this happens every time, and Gapless only uses more
  data: turn it off.
- **`one element (airplay)`**: nothing is got ready while playing to an AirPlay speaker, on
  purpose. Song changes there go the ordinary way.
- **`had to load`, or numbers as big as with Gapless off**: the phone threw away what the
  second player had buffered, most likely with the screen locked. It still plays; it just
  isn't gapless there.
- **`failed before playing`**: the next song wouldn't play from what had been got ready, and was
  asked for again; the time includes that.
- **`one element (refused)`**: iOS wouldn't start the second player, and the song went on the one
  that was playing.
- **The AirPlay button disappears, or stays when the speaker has gone, with Gapless on**:
  Safari tells each of the two players separately whether a speaker is there, and a player it
  hasn't told yet says "none". So the button shows while either says there is one. If it still
  misbehaves, lock and unlock the phone, which (going by Safari's source) makes both ask again;
  AirPlay in Control Center works whatever the button does. Say so if it happens.
- **The app reloads by itself**, and the music stops: iOS taking memory back. Songs up to 64 MB are
  held in memory ahead of time, and hi-res albums come close to that. Turn Gapless off.

## A hi-res song takes a while to start, or sounds quieter

Both come from [Maximum quality](player.md#maximum-quality-hi-res-at-48-khz)'s default, **Up to
48 kHz**, which has deadwax resample FLAC songs above 48 kHz to 48 kHz (or 44.1 kHz).

- **A wait before the first play of a song**: deadwax downloads it from Navidrome and resamples it
  before sending anything, about 2.5 seconds for a 7-minute 24/192 song on an M2 Mac and several
  times that on a NAS. It's kept in the player's cache afterwards and starts at once. In the gapless
  stream only the first song you tap waits: the rest are got ready a minute ahead. With Gapless
  off, or while AirPlaying, the next song is asked for a few seconds into each song. If
  waits come back for songs you've played before, the cache is too small to keep them: raise
  [`PLAYER_CACHE_MB`](configuration.md#paths).
- **Quieter than before, or than "Original"**: every resampled song is lowered by 3 dB, the same for
  all of them, so that nothing clips and the joins stay exact. Turn the volume up a notch. Nothing
  else about the sound changes.
- **deadwax's log says** `was lowered a further 0.40 dB so nothing clips`: that song was mastered so
  loud that even 3 dB wasn't room enough (rare: measured only on masters clipped very hard). It's
  lowered by exactly enough, and its joins with the songs beside it step in level by that much.
- **deadwax's log says** `is resampled without the song before it (...) - the join with the song
  before may not be exact` (or `after`): deadwax couldn't read the neighbouring song's edge from
  Navidrome just then, so that join may click. A play of the song more than ten minutes later tries
  again; until then every play is that same copy.
- **deadwax's log says** `songs above 48 kHz can't be resampled on this server`: the audio libraries
  it needs didn't load, which happens when running from source without installing
  `requirements.txt`. Hi-res songs are then sent as they are.
- **Hi-res songs stall under "Original"**: an iPhone holds only a few seconds of 24/192 at a time,
  so a weak connection can run it dry. Go back to **Up to 48 kHz**.

## After a long pause, play on the lock screen does nothing until the app is opened

A while after the music stops, iOS puts the player's page to sleep: once nothing is playing, Safari
gives up the page's permission to run in the background, and the lock screen's buttons wait until
the page wakes, which is when you open it. So play on the lock screen seems to do nothing, and when
you open the app it starts at once. It happens with Gapless on or off, and to any web
page that plays music, and a short pause usually isn't long enough for it.

There's no clean way round it from a web page. The only one would be never to stop, playing
silence while paused, which keeps the phone awake, uses battery, and leaves the lock screen saying
something is playing, so deadwax doesn't. Open the app and press play; the song carries on from
where it was.

## A song seeks to the wrong place

You move the player's bar to 2:10 and the music comes in somewhere else: a few seconds out, or a
lot further in a song that goes from quiet to loud. The bar and the clock say 2:10 all the same.

**The bar itself** takes a tap anywhere along it, or a drag from anywhere on it, and seeks where
you let go. (Before 1.1.0-player.2 it was the browser's own slider, which on an iPhone moves only
when you drag its small round thumb: a tap on the bar, or a drag started beside the thumb, did
nothing.) If a tap or a drag still doesn't move the bar at all, that's a bug worth reporting.

**Where the music lands in a FLAC is Safari's doing**, on an iPhone and on a Mac. To seek, a player
has to work out where in the file a moment is. In a FLAC, where a second of quiet takes far fewer
bytes than a second of loud, Safari estimates it from the bytes it has already read, and in a song
whose loudness changes, that estimate is off: 3 and 8 seconds out on an iPhone, up to 14 in a
song-like test file on a Mac, and up to 50 in one with a quiet first minute. Safari's clock then
says the time you asked for, not the time you hear. Chrome, Arc, Edge and other Chromium browsers
land exactly where asked every time.

**Since 1.1.0-player.3 Safari gets FLAC inside an MP4**, the same audio bit for bit in a container
that carries a table of where everything is, and its seeks land there exactly
([the phone player](player.md#seeking-and-where-safari-lands) says more). So a song that still
seeks to the wrong place in Safari, or on the iPhone, but not in Chrome, is one that didn't come
that way. **Info → Debug says which** (**•••** on the now-playing screen, then **Info**, then
**Debug**): its **Sent as** row says how the song playing was sent. (Until 2.0.0-player.10 this was
the end of the *Last seek* line between the cover and the song's title.)

- **`FLAC in MP4, …`**: it came inside an MP4. A seek that still lands off is worth reporting,
  with the song.
- **`FLAC, not in an MP4, …`**: deadwax sent the FLAC as it is. It does that for a file
  over 512 MB, and for one it can't repackage with certainty (a file cut short, say, or with
  something after the audio it doesn't recognise); the song plays as before, and seeks may land
  off. deadwax's log names the song and the reason, in a line starting `player: song … is sent to
  Safari as FLAC, not in an MP4`. If the log says instead that Navidrome stopped sending the song,
  or that the song couldn't be put in an MP4 because of the disk (full, or not writable), that
  was one play: the next one tries again.
- **`Asked for FLAC in MP4`** that never changes: the player couldn't find out what came. The
  song itself may still have come as an MP4.
- **`…, as the file is`** (`FLAC, as the file is`, `MP3, as the file is`): the song isn't a FLAC,
  or the browser isn't Safari, or it's a Safari too old to play FLAC in an MP4. Anything but a FLAC
  is sent as it is. AAC and ALAC (`.m4a`) already
  come in an MP4 and seek exactly, and so does an MP3 at a **constant** bit rate, but a
  **variable-bit-rate MP3** (LAME's V0 or V2, the most common kind) can land seconds off in Safari
  just as a FLAC did, and deadwax doesn't repackage it: on a test song, a V2 MP3 landed up to 41
  seconds out where a constant 320 kbps copy landed exactly.

**The first play of a song waits a moment** in Safari while deadwax repackages it (under a quarter
of a second for a CD-quality song where it was measured). Then it's kept, up to
[`PLAYER_CACHE_MB`](configuration.md#paths) of songs (1 GB unless you set it), in the container's
temporary space or in [`PLAYER_CACHE_PATH`](configuration.md#paths) if you've set one. Skipping
past songs before they start doesn't make the next one wait: deadwax stops making the ones you
skipped.

**When the cache can't be used, Safari gets the FLAC.** It never stops a song playing, but its
seeks can land off again, and deadwax's log says why:

- **`… the disk holding the cache (…) is short of space even with older songs cleared out of it`**:
  a song needs room for two copies of itself while it's made, and deadwax leaves 128 MB free for
  everything else on that disk, clearing the songs played longest ago to find it. If the log says
  this, that disk is nearly full with other things. Free some space, or point `PLAYER_CACHE_PATH`
  at a folder on a disk with room. In a container, the temporary space is usually on the same
  disk as Docker itself, which on a NAS is often a small system drive.
- **`Safari is sent FLAC, not MP4s, because the player's cache can't be kept - …`**, said once
  until the problem changes. The rest of the line names it:
  - *this container has no writable temporary space (a read-only root filesystem?), and
    PLAYER_CACHE_PATH isn't set*: a container run with a read-only root filesystem, and no
    `tmpfs` on `/tmp`. Set `PLAYER_CACHE_PATH` to a folder you've mounted that deadwax can write.
  - *… isn't a folder this container can see*, *… couldn't be made* or *… can't be written to*:
    the folder `PLAYER_CACHE_PATH` names isn't mounted, or isn't writable by `PUID`/`PGID`.
    Settings → Library says the same on that row.
  - *… is a link, not a folder deadwax made*, *… belongs to another user*, or *… is open to other
    users*: deadwax only keeps its songs in a `deadwax-player` folder that it made itself and
    nobody else can use. Delete the folder the line names, and deadwax makes a new one on the
    next song.
  - *… can't be made private: the disk it is on doesn't keep file permissions*: the disk
    `PLAYER_CACHE_PATH` is on is CIFS, NTFS or exFAT, which make every folder open to everyone.
    Point it at a Linux-formatted disk.

A song whose MP4 was cleared out mid-song and can't be made again at once doesn't switch to the
FLAC halfway through, since the two files' bytes differ: deadwax asks Safari to try again, and the
player's own retry asks for the song afresh, from where it stopped.

**Info → Debug's Last seek row tells you when a seek landed off**, whichever way the song came. It
shows *Asked 2:10, the player said 2:10* (*interrupted* instead, if Previous, Next or a
failure came before the seek got there). Safari says the time asked for either way, so that can't
show it, but the end of the song can: if the seek landed off, the song runs out before its clock
reaches the end, or plays on after the clock has stopped at the end, by the same amount. When the
song gets to its end with no other seek or pause in between, the row adds how far off it was, for
example *the song played on 7 s after its clock ended, so it really landed at about 2:03*. *The
song ended on time* means that seek landed where you put it.

**Seek tables don't help.** A FLAC can carry a table of where each moment is in the file, so that a
player doesn't have to estimate, and plenty of files have none (ffmpeg, for one, doesn't write
one). But in the measurements above a seek table made no difference to where Safari landed: the
same song landed in the same wrong places with and without one. Chromium lands exactly either way,
and Safari now gets the MP4, so there's no need to add tables to your library for this. If you
want to look anyway, with the `flac` tools:

```sh
metaflac --list --block-type=SEEKTABLE "01 - Song.flac"   # nothing listed: no table
metaflac --add-seekpoint=10s "01 - Song.flac"            # a point every 10 seconds (writes the file: back it up)
```

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
