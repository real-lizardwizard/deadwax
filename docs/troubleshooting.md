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

## The app's Get says "refused: already downloading from …" or "already in your library"

A **Get** in the app (or **Download** on the main page) is checked once more as it's queued, and
deadwax refuses a second download of a pressing that is already downloading whole, already being
filed, or already in your library complete - with a `409`. The row in **Requests**, under Needs
attention, reads "refused", with deadwax's words in red under it: "already downloading from bob",
"already downloaded from bob, and being filed now", "already in your library: *folder*". It happens
when the album was
started or filed somewhere else - another tab, the main page, another phone - after the app last
looked: the album page's line under Get, and the sources sheet, said what they knew when
they asked. Nothing is lost: the download that is already on its way is in Requests (cancel it
there to try another user, then Get again), and an album you have is in your library. **Clear done**
removes the refused row. A download of only part of a pressing - one disc's folder - refuses nothing.

## The app's Get shows "slskd isn't logged in…", or nothing to choose from

The sources sheet asks slskd to search Soulseek, as **Find** does, so the same things stop it:

- **slskd's own words, in amber, with Try again** - "slskd isn't logged in to Soulseek, so it can't
  search", "it's waiting for its VPN", or that it can't be reached: see [A search fails with "not
  logged in"](#a-search-fails-with-not-logged-in-or-slskd-refused-it) and [The slskd pill is
  red](#the-slskd-pill-is-red). You's **Connections** says whether deadwax can reach slskd.
- **"Soulseek found nothing for …"**: as [A search finds nothing](#a-search-finds-nothing) - edit the
  query under it (to the album title alone, say) and **Re-search**.
- **"N folders on Soulseek, none pass your filters"**: the chips above the list are hiding them -
  **Lossless** and **24-bit** start pressed when your quality floor (You → Getting albums) says so.
  **Clear filters**, or tap the chip, to see them all.
- **"Didn't pick a source for you: …"** with **Pick the best source for me** on: nothing scored 75 or
  more through the chips, or you already have part of the pressing (or part of it is downloading),
  or it was the album as a whole (below), with no tracklist to judge the folders by. The sources
  are there to choose from yourself.
- **Get's sheet says "… · the album as a whole"**: a row's Get chip couldn't get the album's
  pressings from MusicBrainz, so it searched for the album with no tracklist to match against, as
  the main page's card **Find** does then - so it never picks one for you, whatever your setting.
  Open the album (tap the row) once MusicBrainz is back to choose a pressing and Get that.
- **A row's Get went back to "Get" without opening anything**: it gives up when you move on while it
  asks MusicBrainz for the album's pressings - typing, opening a row, Now Playing or another tab - so
  the sheet never opens over where you went. Tap it again.

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
- **A done download says "Navidrome hasn't found it yet - it may still be scanning"** when tapped:
  deadwax asked Navidrome for the album by the pressing's MusicBrainz id, and by its title, and
  Navidrome has no album carrying that id yet. Navidrome scans a few seconds after a folder changes,
  so tap it again in a moment (the note goes once it opens; with Requests open, the app keeps
  looking by itself). If it never opens: Navidrome may not have rescanned yet (start a scan from
  Navidrome's own pages), or the account deadwax uses can't see that library folder.
- **A done download says "deadwax can't tell which album in your library this is"**: no folder in
  your library is tagged with that pressing's MusicBrainz release id. That happens to **Already in
  your library, nothing filed** when the tracks were already in a folder deadwax didn't file and
  that has no MusicBrainz tags (an old rip): nothing was written into it, so nothing ties it to the
  release, and a rescan won't change that. Apply the release to that album in the main page's
  metadata editor and the row opens it. It can also mean the album's folder has gone since.
- **A done download says "Navidrome isn't set up" or "isn't answering just now"**: the album can't
  be opened in the app until it is - see [below](#the-player-says-connect-navidrome-or-cant-reach-navidrome).
  **"Couldn't look it up just now"** means deadwax itself didn't answer: tap it again.
- **A done download has no ▶**: only a download that filed something has one. "Already in your
  library, nothing filed" opens the album you already had - when its folder is tagged with the
  pressing, as above - with no ▶; an interrupted or unfiled download has neither, as nothing of it
  is known to be in the library.

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

## An artist's page has no albums from MusicBrainz, or the wrong artist's

The app's [artist page](player.md#artist-pages) lists an artist's albums from MusicBrainz, which
needs to know which MusicBrainz artist it is.

- **"MusicBrainz doesn't know who this is from your files, so only the albums you have are
  here."**: neither Navidrome nor your files say. Navidrome reads an artist's MusicBrainz id from
  the album artist's `musicbrainz_albumartistid` tag, which deadwax writes on every album it files
  or you apply a release to (since v0.6.15); albums tagged by something else, or long ago, may lack
  it. Applying the album's release in the main page's metadata editor writes it, and the page
  finds them once Navidrome has rescanned.
- **"MusicBrainz isn't answering just now"**, with **Try again**: MusicBrainz is slow or down (see
  [below](#musicbrainz-is-slow-or-searches-fail)). The albums you have are still listed.
- **An artist opened from an album you don't have shows none of your albums**: deadwax looks for
  them as the Navidrome artist carrying that MusicBrainz id, else the artist your library files
  their albums under, else - only for an artist Navidrome has no id for - one whose name is
  MusicBrainz's, and only when exactly one goes by it. Two artists in your library with the same
  name and no ids can't be told apart, so neither is shown.
- **Play and Shuffle stay grey**: they wait until every album of theirs you have has come from
  Navidrome, and until your library has said which of Navidrome's albums are copies of one album
  (so both of a pressing you hold twice aren't played). If Navidrome didn't send some, the line
  under them says so, with **Try again**; "Navidrome has none of their albums to play" means just
  that - an album only your library has, Navidrome hasn't found yet.
- **An album on an artist's page says neither "in" nor "not in your library", with no Get**: your
  library hasn't answered yet (the first look after deadwax restarts walks the whole library). It
  says once it does.
- **An artist's page says it couldn't ask Navidrome, with Try again**: deadwax couldn't reach
  Navidrome to find the artist; tap Try again.

## The app's Library has no Songs

The **Songs** chip is left out when Navidrome answers an empty search with no songs, which is how
the app lists them; it asks once, as the app starts (once Navidrome answers) - reload the app to
ask again. A Navidrome that answers an empty
search with nothing (an older one, or one set up to) can't list songs this way, and the Library
shows Albums and Artists only. The albums of the songs are all in Albums.

## The app's Home has no "Not played in a while"

It shows only with at least four albums you last played more than 30 days ago, and only when
Navidrome says when each album was last played (OpenSubsonic's `played`, on its "recently played"
list). A library you've been listening through - everything played in the last month - or a fresh
Navidrome has nothing to show yet. A Navidrome that doesn't send `played` never shows it: Info →
Debug's **Navidrome sent** row lists the fields it sends for the album playing. The plays are the
ones Navidrome counts for the account deadwax signs in with, so plays made in another app under
another Navidrome user don't count.

## A pinned album says "Removed from the store", "Not on disk just now" or "Not in Navidrome yet"

- **Removed from the store**: the album was deleted from the main page. Unpin it from Home's **Edit**,
  or get it again - the pin opens the new copy of the same pressing once it's filed.
- **Not on disk just now**: its folder isn't where deadwax last saw it - usually a share or
  disk that isn't mounted. It opens again once the folder is back and deadwax has looked at your
  library again: the main page's library tab scans as it opens, and **Rescan** scans at once. A
  folder moved by hand outside deadwax is matched up by that scan too, and the pin follows it.
- **Not in Navidrome yet**: deadwax has the album, but Navidrome doesn't, or not as that
  release - it may still be scanning after a download or a re-file. Come back to Home in a moment:
  it asks again each time it's shown. If it stays, check that Navidrome can see the folder and that
  the album's files carry its MusicBrainz release id (Navidrome's `musicBrainzId` on the album).

## A pin won't stay, or the app says "Couldn't pin …" or "Not saved"

Pins are kept in deadwax's database. A pin or an unpin deadwax couldn't keep goes back, and a note at
the top of the screen says which album or artist and why ("Couldn't pin Dummy: …"); a change made in
Home's **Edit** says **Not saved: …** under the list instead. The reasons:

- **"Home holds up to 50 pins - unpin one first"**: Home is full. Unpin something in **Edit**.
- **"its database refused the write"** or **"isn't writable"**: check `DB_PATH`, and that the folder
  it's in can be written as `PUID`/`PGID`. When deadwax can't keep pins at all, the pin buttons are
  greyed, and a tap on one says so.
- **"deadwax couldn't read its pins just now"** (or Home's Pinned saying **Couldn't get your pins: …**
  with nothing pinned shown): the database didn't answer in time - usually something else holding it
  a while. Your pins are still there; Home asks again each time it's shown, and keeps what it last had.
- **"deadwax couldn't ask Navidrome about this album just now - try again"**: pinning from the now-
  playing screen's **•••** menu sometimes needs Navidrome to say which release the album is, and it
  didn't answer. Tap again once it's back.
- **"it has no MusicBrainz release id to find it by"**: nothing would find the album again once it
  moved, so it can't be pinned. An album page shows no pin for such an album, and the ••• menu offers
  none when it knows; tag the album with its release (apply a release in the main page's editor).

## The app's Edit panel can't find the album's folder

On a desktop, an album page's **Edit** finds the album's folder by its MusicBrainz release, or - for
an album Navidrome knows by no release - by its name among the library's untagged folders ([how it
finds it](library.md#editing-an-album-in-the-app)). What it says when it can't:

- **"deadwax has no folder of this album: Navidrome knows it by a MusicBrainz release no folder in
  the library is tagged with"**: the files Navidrome scanned carry a release id that no folder in the
  library has - usually an album added by another program since the library was last read, or a
  Navidrome looking at a different folder from `LIBRARY_PATH`. **Look again** reads the library again;
  if that doesn't find it, check the two paths point at the same music.
- **"deadwax can't tell which folder this album is: Navidrome knows it by no MusicBrainz release, and
  no untagged folder in the library has its name"**: the album's name or artist in Navidrome isn't the
  one in its files' tags as deadwax reads them, or its folder does carry a release id. **Open the main
  page** and find it in the Library tab, where its editor works the same.
- **"Which one is it?"**, with a list of folders: more than one untagged folder has the album's name
  and artist (its number of tracks didn't tell them apart). Pick the one this page plays.
- **"The library's scan doesn't list … yet"**: the store knows the folder but the library's last scan
  doesn't. **Look again** scans it.
- **"deadwax couldn't read the library: …"**: reading the library failed - often a reverse proxy
  giving up on a first scan of a large or sleeping library, or a moment without the network. **Look
  again** reads it again.
- **LIBRARY_PATH is not set**: the panel needs the library, as the main page's Library tab does - see
  [the library tab is empty](#the-library-tab-is-empty-or-doesnt-show-a-change).

**Edit** itself is missing on a phone (there's no editor there yet), in a window under 1024 pixels
wide, and for someone deadwax says isn't an admin - with logins off, nobody.

## The app's "Needs a look" count changes when you open it, or has none

The count beside **Needs a look** (the desktop sidebar's **Managing**, and You's **Albums that need a
look**) is worked out from the library's **saved scan**, never by reading the disk, so it costs
nothing to keep asking. While the page is open it shows the page's own count instead, from a fresh
scan - so if the music changed since the library was last read (an album copied in, retagged or
removed by another program), the number moves as the page opens. They count the same albums: every
album with an issue you haven't accepted, and every album deadwax filed that nobody has looked at.

- **No number at all**: nothing needs a look - or deadwax hasn't answered yet. A count is only drawn
  once deadwax has said one, never a 0 standing in for "not known".
- **Only the new albums are counted** until the library at `LIBRARY_PATH` has been read (open **Needs a
  look**, or the main page's Library tab): with no saved scan of that folder there is nothing else to
  count from. That is so on a new database, after `LIBRARY_PATH` is pointed somewhere new, and when the
  last read found no albums there at all (an unmounted share, say).
- **An album filed a moment ago** counts at once, before any scan has seen its folder; it appears on
  the page once the page has read the library.
- **The page is missing on a phone**: it's a short note there, pointing at the main page, which has
  the same queue (**Review N**). There's no editor on a phone yet.

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

## The turntable hangs, or the song is slow to come back after you turn the record

Turning the record pauses the song and plays the record's own sound; letting go brings the record back
to speed (0.4 s from still, up to about 0.8 s after a hard flick) and then starts the song again from
there. How long that really takes, and whether the page kept up while your finger was down, is counted
on your device: turn the record a few times, then open **•••** > **Info** > **Debug** and read
**Turntable timing**.

- **`The song was back N s after the last let-go`**: the whole wait from lifting your finger to the
  song's own playback moving, with how much of it was the record's run back to speed. What is left is
  your browser starting the song again after a seek - on an iPhone that can be several tenths of a
  second, and a web page can't shorten it.
- **`N of M blocks late`** (only where the row above says the sound is "On the main thread", which is
  every page opened over plain `http://`): the record's sound is made by the same thread that draws the
  page there, and each late block is a gap or a click in it. Over `https://` (or `localhost`) the
  browser gives it a thread of its own and this can't happen.
- **`N frames, K late, the longest gap G ms`**: how the picture kept up while your finger held the
  record. Late frames are the page itself stalling.
- **`let-goes after which the song didn't start`**: the browser refused to start the song without a
  tap, or it took more than three seconds to load. Tap play.
- **`The sound interrupted N times`**: something else on the phone took the audio (a call, another
  app).

Since 2.0.0-player.28 the record's sound also stops as soon as the song is back: before, the two
overlapped for up to a few tenths of a second after every let-go, the record's sound a little behind
the song - an echo.

## The turntable's sound warbles or buzzes as you turn the record

Until 2.0.0-player.27 the record's sound had a fast flutter on it whenever your hand's speed was
changing, which is nearly always: "warbly, like there's a dragonfly sound on top of the music". The
pitch followed the jitter in the phone's touch readings. It now works each touch's speed out from the
touches either side of it and plays about an eighth of a second behind your hand (120 ms; about 163
over plain `http://`) instead of a twentieth. If you still hear it:

- **A thin, metallic or fizzy sound on top of the slowed or sped-up song** - "a digital artifact on
  top" - was real until 2.0.0-player.29: slowing or speeding the record's sound means working out the
  sound between the song's own samples, and the short curve it used left a faint mirror copy of the
  song's high notes above the slowed song (a slowed 15 kHz tone came with a second tone at 8 kHz, only
  17 dB quieter), and folded the highs back down over a sped-up one. It is read through a proper filter
  now: those are 60 to 80 dB down.
- **A slow wobble** as you turn is your hand: the pitch follows the record's speed, as on a real deck.
- **Clicks or crackle**, rather than a wobble, on a page opened over plain `http://`: the sound is made
  on the page's main thread there (**Info** > **Debug** > **Turntable sound** says "On the main
  thread"), and a very busy phone can make it late. Say so if you hear it.
- **The record feels late under your finger**: that is the eighth of a second. It can be shortened, at
  the cost of some of the steadiness.

## The turntable makes no sound when you turn the record

Since 2.0.0-player.14 [the turntable](player.md#the-turntable) has its own sound: turning the record
plays the song at the speed of your hand, a flick coasts audibly, and a pause winds down. Since
2.0.0-player.16 a press only takes hold of the record when it can make that sound: whenever it can't,
turning it works as it did before - silently, the song playing on under your finger, and no momentum -
rather than pausing the song over silence. When it's silent, **Info → Debug**'s **Turntable sound**
row (**•••** on the now-playing screen, then **Info**, then **Debug**) says why, in the order to check:

- **`Off: waiting for a tap to start the sound`**: a phone only lets a page start sound from a tap,
  so the record's sound starts at the first tap on the record, the play/pause or skip buttons, the
  button that switches to the turntable, or - since 2.0.0-player.30 - the mini player's tap when Now
  Playing opens as the turntable (until then that tap only brought back a sound that had already
  started, so a turntable opened that way was silent until a first scrub had come and gone) - and a
  turn of the record before any of those is silent, with the song playing on under your finger as
  before. It stops again whenever the screen closes or the phone locks, and the next tap starts it.
- **`Off: its window is loading - …`** or **`Off: no window yet - …`**: the record plays a stretch
  of the song round where it is, and that stretch hasn't arrived. It's fetched as soon as the sound
  has started - a moment after the first tap - for a paused song as much as a playing one (since
  2.0.0-player.30; before, a paused song's was fetched only when you first pressed the record, so its
  first turn was always silent). A press outside the stretch
  shown on a `Ready: …` row works as before too - except on a record still coasting from a flick,
  which you catch as ever, silent until the next stretch arrives.
- **`Off: still starting - …`**: the part that plays the sound hasn't begun yet. If it never gets
  past this, the browser isn't running it: tell us which browser and device.
- **`Off: it isn't a FLAC file (…)`**: only FLAC songs have it. Anything else turns silently, with
  no momentum, as before 2.0.0-player.14.
- **`Off: this browser couldn't decode its window - …`**: the phone refused the stretch of the song
  deadwax sent. The words after the dash are the browser's own: they are what to report.
- **`Off: deadwax didn't send it - …`**: deadwax cuts the stretch from the copy of the song the phone
  plays - the one it keeps in the player's cache, or for a song the phone plays as the FLAC it is, the
  FLAC itself on Navidrome - and couldn't just then: Navidrome not answering, or breaking off, or a
  copy that had to be made and couldn't - the cache unusable or its disk short of space (see
  [A song seeks to the wrong place](#a-song-seeks-to-the-wrong-place), which covers the cache). It
  asks again after ten seconds.
- **`Off: this browser has neither an AudioWorklet nor a ScriptProcessorNode to play it`**, **`no
  Web Audio`**, **`the sound couldn't start - …`** or **`the sound's ScriptProcessorNode couldn't be
  made - …`**: the browser can't play it - the words after the dash are its own.
- **`Ready: …`** and still silent: if the phone's ringer switch is on silent, try it off. Since
  2.0.0-player.16 deadwax asks iOS (16.4 and later) to treat the page as playing music from the first
  tap that starts the record's sound until the turntable goes, which should keep the switch from
  muting it - not yet checked on a phone, so say
  if it does. The song's own playback isn't affected either way.
- **`Off: the turntable isn't showing`**: the now-playing screen is on the cover, or closed.

**Opened at a plain `http://` address?** That's fine since 2.0.0-player.16. A browser gives the
AudioWorklet - the part that plays this sound on an audio thread of its own - only to pages on HTTPS
or `localhost`, and until 2.0.0-player.16 the turntable had nothing else to play it with, so over
plain `http://` the record took the song from you and played nothing (James: "the audio doesn't
follow the turntable when scrubbing"). It now plays it on the page's main thread instead, and the line
under **Turntable sound** says so: `On the main thread - this page isn't on HTTPS, so the browser has
no AudioWorklet`. On HTTPS it says `On its own audio thread (an AudioWorklet)`.

Turning the record never touches the song's own playback: if it's silent, the music still plays
exactly as it did when you let go.

## The turntable's sound doesn't sound like the song

Until 2.0.0-player.24, turning the record at its own speed gave a warble nothing like the song (James:
"it doesn't sound like anything"): the record's sound was timed by the audio's own clock, which on an
iPhone moves in steps of about 21 ms, so its pitch swung many times a second. It now follows each touch
your phone reports at the moment it was made, played back on one smooth clock - so a steady turn plays
the song at your hand's speed. What's left is by design:

- **It's a moment behind your finger**: a twentieth of a second on HTTPS, about 0.09 s over plain
  `http://` - always the same, so the next touch has always arrived before the sound gets there.
  Taking hold of a playing record, or pausing it with the wind-down, repeats the song's last twentieth
  of a second as the record's sound takes over; letting go of a playing record at about its own speed
  skips it (the song plays on straight from where your hand let go, while the record's sound, that much
  behind, stops as you let go) - neither is a fault.
- **Its pitch follows your hand**, and a hand turning by eye is never quite steady - you hear that,
  as you would on a real deck. While you turn steadily deadwax smooths a finger's own jitter out of the
  pitch, measuring how much there is in your touches (so a heavier finger, or a grip near the middle of
  the record, is smoothed as much as it needs); as you speed up, slow down or turn back it follows you
  closely instead. A record turned with a mouse a pixel at a time, slowly, can still waver a little:
  a pixel is a coarse step at that speed.
- **The first turn sounds like every other**: deadwax reads your phone's audio clock all the while the
  turntable shows with its sound on, even with the record standing still, so the first grab of a paused
  record after opening the screen or coming back to the app is timed as smoothly as the rest. If the
  first moments of a turn, and only those, warble, say so.
- **Debug's line under Turntable sound** says how far your phone's audio clock moves at a time (`Its
  clock moves 21.3 ms at a time`) - the steps the record's sound is now timed smoothly across. If the
  sound still warbles, say what that line says, and which browser and device.

## The visualizer doesn't move with the music, or says a song can't be seen

[The visualizer](player.md#the-visualizer) (the five bars at the right of the desktop's player bar)
measures its own silent copy of the stretch of the song playing - never the song you hear - and when
it can't, it runs the effects from a calm, slow idle pattern and says why in a plain note at the
bottom right of the screen (move the pointer, or click or tap, if the controls have faded):

- **"This song can't be seen - it isn't a FLAC file."** Only FLAC songs have that copy, as only they
  have the turntable's sound. An MP3, AAC or any other song always shows the idle pattern.
- **"This song can't be seen just now - deadwax couldn't send its sound."** deadwax cuts the copy
  from the copy of the song the player's cache keeps, or - when the page plays the FLAC as it is -
  straight from the FLAC on Navidrome, and couldn't just then: Navidrome not answering or breaking
  off, or a copy that had to be made and couldn't - the cache unusable or its disk short of space (see
  [A song seeks to the wrong place](#a-song-seeks-to-the-wrong-place), which covers the cache). It
  tries again after ten seconds by itself.
- **"This song can't be seen - …"** with deadwax's own words after the dash (a song deadwax won't cut
  a stretch from - a file cut short, say) or **"this browser couldn't read its sound"**: that song stays
  unseen until you leave the visualizer and open it again; other songs are unaffected.
- **"This browser can't analyse sound, so the song can't be seen."** The browser has no Web Audio, or
  wouldn't make it - every song shows the idle pattern there.

**It moves, but a moment late after a seek, after opening it, or on a song you skipped to**: the
copy is fetched as the song plays - about a second's wait for each new stretch on a home network -
so the first second after opening it, after a seek or after a skip can be still. One song flowing
into the next doesn't wait: the next song's first stretch is fetched in the last few seconds of the
one before. **It stops moving while the music plays on**: the browser may have suspended its sound
with the page in the background; a click anywhere on the visualizer, or any key, starts it again.

**The player's cache fills up after an evening with the visualizer open**: it shouldn't, since
2.0.0-player.23. In a browser that plays the FLAC as it is (Chrome, Firefox or Edge with Gapless off),
deadwax reads each stretch the visualizer shows straight out of the FLAC on Navidrome, a little at a
time, and keeps nothing of it in the player's cache (until then each song shown had a copy made and
kept there, counted against [`PLAYER_CACHE_MB`](configuration.md#paths), pushing an iPhone's songs
out). Where it can't, deadwax's log says so once for each song - `a window of song … can't be cut
straight from its FLAC - …` - and that song's stretches are cut from a copy made in the cache, as
before (when the cache itself can't be used, the line ends `its windows can't be had` instead, and
the visualizer says the song can't be seen just now). The words after the dash say why: a FLAC laid
out unusually (dozens of large pictures in front of its audio, say, or a seek table that points at
the wrong places), or something in front of Navidrome - a proxy - answering a request for part of a
file with another part, or with more than was asked for, or with the whole file once the request is
longer than a few bytes. (Words beginning `reading it went wrong` are a fault in deadwax itself, not
in the file - worth reporting, with the line; the stretches still come from the copy.) A proxy should
pass those requests on to Navidrome as they are. One that ignores every request for part of a file
shows differently, and in more places: every FLAC song's visualizer says **"This song can't be seen -
Navidrome didn't answer a range of the file"**, the phone's turntable is silent, Safari and iPhones
are sent FLAC songs as they are (so their seeks land off again), and the gapless stream plays each
song the ordinary way - nothing is made in the cache at all. The fix is the same.

**The colours aren't the cover's**: until the cover has loaded, and for an album with no cover, **From
the cover** uses the purple. A black-and-white cover gives grey - that is its colour.

**"WebGL isn't available here, so Ambient is showing the simple version."** Your browser has no WebGL,
or has it turned off (some do when the graphics driver is blocked): Ambient shows its plain version;
Bars, Scope and Halo don't need WebGL.

**It didn't take the whole screen**: a browser can refuse to go full screen; the visualizer then fills
the window instead, and works the same.

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
