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
album shows as **New** in **Needs a look** like any other filed download. The rest are still in
slskd's folder (a move never clears that folder out while anything failed). The container's own
log names each file and why, most often permissions or a full disk. Fix that, then either copy
the missing tracks across and apply the album's release (**Edit → Release**), or download the
album again: a track the album's folder already has is never filed twice, so only the missing
ones are added.

When it goes on **", no track was filed"**, none of its music reached the library (a cover may
have: that makes a folder, but no album, and nothing is marked **New**), which usually means the
library folder can't be written (see [Downloads finish, but nothing appears in my
library](#downloads-finish-but-nothing-appears-in-my-library)). Requests says **Partly filed** for
the first and **Not filed** for the second.

## A download says "deadwax stopped while filing this"

deadwax was stopped or restarted while it was filing that album, so it can't tell how far it got.
Look at the album in the library (**Library care → Rescan** first) and in slskd's downloads folder:
in move mode, whatever hadn't been filed yet is still in slskd's folder, and in copy mode all of it
is. Anything missing is dealt with as in the section above. In Requests it reads **Interrupted while
filing**, and **Clear done** removes the row.

## Get says "Already downloading", but nothing is

**Get** won't search for a pressing while a download of all of it is queued or arriving, and
names the user it's coming from. Open **Requests**: the download is there, and cancelling it (or
letting it fail) lets **Get** search again. A download of only part of it, such as one disc's
folder, doesn't stop the search: it's a note above the sources.

**"Already downloading for someone else"** (logins on) is a download somebody
else asked for, so it isn't in your Requests and isn't yours to cancel: **Join this download** to
wait for it too (see [downloading](downloading.md#with-logins-on-downloads-per-person)), or ask an
admin, whose cancel is for everyone. If it's below your quality floor, getting a copy of your own
instead isn't offered yet.

"Already downloaded", with "being filed into your library now", means every file has arrived and
it's being filed. That takes seconds. A download that finished while organizing was off is never
filed later, and stops counting two minutes after it finished. One that deadwax was stopped or
restarted part-way through filing stops counting as soon as deadwax starts again, which marks it
"deadwax stopped while filing this" (above).

## Get says you have only some of a pressing you have all of

The note ("You have 9 of 10 tracks of this pressing") counts the release's tracks in the folder,
matching each file by its title, and by its disc and track number when the title isn't the
release's. A file whose title and numbers are both different from MusicBrainz's (a track tagged by
hand, or from another database) isn't counted. Applying the release to the album (**Edit →
Release**) gives every file the release's titles and numbers, and then it counts. The search still
runs, so nothing is lost meanwhile.

## Get says "Already in your library", but I want another copy

deadwax won't fetch a second copy of a pressing you have complete. It names the folder. To
replace it, delete the album first (**Edit → Delete**), then **Get** again. A different pressing
of the same album is searched as usual, with a note that you have the other one.

## Get says "refused: already downloading from …" or "already in your library"

A **Get** on a source is checked once more as it's queued, and
deadwax refuses a second download of a pressing that is already downloading whole, already being
filed, or already in your library complete - with a `409`. The row in **Requests**, under Needs
attention, reads "refused", with deadwax's words in red under it: "already downloading from bob",
"already downloaded from bob, and being filed now", "already in your library: *folder*". It happens
when the album was
started or filed somewhere else - another tab, another phone - after the app last
looked: the album page's line under Get, and the sources sheet, said what they knew when
they asked. Nothing is lost: the download that is already on its way is in Requests (cancel it
there to try another user, then Get again - with logins on, unless somebody else is waiting for it
too: your cancel then only takes it off your list), and an album you have is in your library. **Clear done**
removes the refused row. A download of only part of a pressing - one disc's folder - refuses nothing.

With logins on, a download somebody else started isn't refused: your Get
joins it, and it shows in your Requests. "already downloading from bob" then means you're already
waiting for that download yourself.

## I cancelled a download, and it's still downloading

With logins on, somebody else asked for it too: your ✕ withdrew only your
request - it said "Leave this download?" - and the download carries on for them. It's gone from your
Requests; Get it again while it's still on its way and you're back in. The download itself stops
when the last person waiting for it cancels, or when an admin cancels it - which is also the only
way to send a download you share to another user (another user isn't offered for one yet).

## "Join this download" says the download has finished, failed or been cancelled

Joining asks deadwax again, and the download moved on after the page last looked: "that download
has been filed into the library since", "has finished", "has failed", "has been cancelled", or "has
been cleared from the list since". Get it again: the page then says what's true now - in your
library, or nothing on its way, so the sources are searched. "That download brings only part of this
pressing" is a download of one disc's folder, which can't be joined: Get the pressing as usual.

## Get shows "slskd isn't logged in…", or nothing to choose from

The sources ask slskd to search Soulseek, so these stop it:

- **slskd's own words, in amber, with Try again** - "slskd isn't logged in to Soulseek, so it can't
  search", "it's waiting for its VPN", or that it can't be reached: see [A search fails with "not
  logged in"](#a-search-fails-with-not-logged-in-or-slskd-refused-it) and [You's Connections
  says slskd isn't connected](#yous-connections-says-slskd-isnt-connected).
- **"Soulseek found nothing for …"**: as [A search finds nothing](#a-search-finds-nothing) - edit the
  query under it (to the album title alone, say) and **Re-search**.
- **"Nothing lossless on Soulseek for …"**: your **Format** (You → Getting
  albums) is **Lossless only**, and every folder Soulseek found had no lossless file, so all of them
  were left out - a Re-search is scored the same way and finds the same. Choose **Prefer lossless**
  or **Any** there and **Get** again to see them, or edit the query in case a lossless copy is shared
  under other words. Format can be Lossless only without your choosing it in the app: the first time
  the app asks, it carries over the Format the old page at `/` had left in that browser.
- **"N folders on Soulseek, none pass your filters"**: the chips above the list are hiding them -
  **Lossless** and **24-bit** start pressed when your quality floor (You → Getting albums) says so.
  **Clear filters**, or tap the chip, to see them all. **Complete albums only** leaves out every folder
  missing one of the pressing's tracks. On a computer a **Signals** minimum and the sample-rate floor
  leave folders out too - and no folder passes the floor when its user's client reported no sample
  rate, which many don't.
- **"Didn't pick a source for you: …"** with **Pick the best source for me** on: nothing scored 75 or
  more through the chips, or you already have part of the pressing (or part of it is downloading),
  or it was the album as a whole (below), with no tracklist to judge the folders by. The sources
  are there to choose from yourself.
- **Get's sheet says "… · the album as a whole"**: a row's Get chip couldn't get the album's
  pressings from MusicBrainz, so it searched for the album with no tracklist to match against - so
  it never picks one for you, whatever your setting.
  Open the album (tap the row) once MusicBrainz is back to choose a pressing and Get that.
- **A row's Get went back to "Get" without opening anything**: it gives up when you move on while it
  asks MusicBrainz for the album's pressings - typing, opening a row, Now Playing or another tab - so
  the sheet never opens over where you went. Tap it again.

## You's Connections says slskd isn't connected

**You → Connections** shows each service's word - **Connected**, or the reason as deadwax got it -
with slskd's or deadwax's sentence under it:

- **`CONNECTION_ERROR`**: slskd can't be reached at `SLSKD_URL` from inside the container. Use
  the address the *container* would use (`http://slskd:5030` on a shared Docker network), with
  the `http://`.
- **`NOT_LOGGED_IN` / `NOT_CONNECTED` / `CONNECTING`**: slskd is running but isn't signed in
  to Soulseek. Check slskd's own page. If slskd runs behind a VPN container, it may be waiting
  for the VPN, and the row says so.
- **`401`**: slskd rejected the API key. Check `SLSKD_APIKEY` against the key in slskd's
  configuration.
- **`UNKNOWN_ERROR`** with **"SLSKD_URL is unusable (…)"** in the **Log**: the address in your
  compose file or `.env` fails the check Server settings makes on save - a user name or
  password in it, a `?` or `#`, a space, no `http://` - and the brackets say which. deadwax won't
  send slskd anything at such an address, the API key least of all. Fix it in Settings →
  Connections or in compose. A reverse proxy in front of slskd that asks for a login of its own
  can't be reached this way; point deadwax at slskd directly.
- **`UNKNOWN_HTTP_ERROR` / `UNKNOWN_ERROR` / `UNEXPECTED`** otherwise: slskd answered with
  something unexpected. The log has the details.

## You's Connections says MusicBrainz isn't connected

- **`VALUE_ERROR`**: no contact is set. Set `MUSICBRAINZ_EMAIL` (Settings → Connections).
- **`CONNECTION_ERROR` / `MAX_RETRIES_EXCEEDED` / `UNKNOWN_ERROR`**: MusicBrainz couldn't be
  reached, or kept failing. It goes away for minutes at a time now and then (below); if it
  persists, check the container can reach the internet.

## A search fails with "not logged in", or slskd refused it

Searches are refused while slskd isn't signed in to Soulseek; it answers with a `409`, which the
sources explain. It also starts one search at a time, so a search started while another is still
starting can be refused with "Only one concurrent operation is permitted": wait and search again.
Deadwax's own searches wait their turn to start, across everyone using it, so
two people searching at once don't cause it; something else starting a search at that moment (slskd's
own page, another app) still can.

## A search finds nothing

- Soulseek only returns folders whose paths contain **every word** of the query. Under **Soulseek
  found nothing for …** the query is there to edit: cut it to fewer words (the album title alone, say)
  and press **Re-search**.
- Try a longer `SLSKD_SEARCH_TIMEOUT` (Settings → Downloads): slow and firewalled peers answer
  last.
- An artist with more than one name is searched under each of them (the credit, the name they go by
  now, and names MusicBrainz marks as ended); an edited query searches exactly what you typed.
- **Format** set to **Lossless only** leaves out every folder with no lossless file, and the sources
  say "Nothing lossless on Soulseek for …". Prefer lossless or Any (You → Getting albums) shows them.

## A download sits at "queued"

It's waiting in the user's upload queue: Requests says how far back you are ("#4 in their
queue"). A user with a **free slot** starts straight away. If slskd stops reporting the transfers
altogether, the download fails after about two minutes. Use **Ask again** to ask the same user
again, or **Next peer** to move it to someone else.

## Requests shows nothing moving, or "Can't get your requests from deadwax"

The Requests tab (and Home's Arriving, and the count on the tab) shows what deadwax knows of each
download, and the progress as slskd reports it.

- **slskd can't be reached** (it refuses the connection, or isn't there): every download is still
  listed, but nothing moves - "0 of 10 files", no speed, queued ones "starting". After about two
  minutes of slskd reporting nothing,
  deadwax gives up on them and they move to **Needs attention** as "no transfers reported by
  slskd". **Next peer** and **Ask again** can't get anywhere until slskd is back, and the row says
  why, in red. A download slskd still lists but can't move - slskd signed out of Soulseek, or
  waiting for its VPN - just stops where it is until slskd is back. You's **Connections** says
  whether slskd answers, and [You's Connections says slskd isn't connected](#yous-connections-says-slskd-isnt-connected)
  goes through the reasons. **slskd up but not answering** (it takes the connection and then says nothing) is
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
- **A download started on another device doesn't show**: the app looks again when Home or Requests
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
  release, and a rescan won't change that. Apply the release to that album (**Edit → Release**, from
  its page or **Needs a look**) and the row opens it. It can also mean the album's folder has gone since.
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

## MusicBrainz is down, but searches still answer

That's deadwax's [saved answers](configuration.md#musicbrainzs-saved-answers-settings--connections): anything asked before - a search, an artist, an album's pressings - is
answered from the file deadwax keeps, however old the answer, while MusicBrainz is away. Something
never asked before still needs MusicBrainz, and fails as above. You's **Connections** still says
whether MusicBrainz itself can be reached: it never answers from
the saved answers. Nothing needs doing; when MusicBrainz is back, old answers are refreshed behind
themselves as they're used.

## A MusicBrainz answer looks out of date

A new release missing from a search, or a correction made on MusicBrainz not showing: deadwax shows
its [saved answer](configuration.md#musicbrainzs-saved-answers-settings--connections) for the same
question, and asks MusicBrainz again only once the answer is old - a search after 7 days, an artist, an
album's pressings or a discography after 30. Then the saved answer is still shown once, and the new one
fetched behind it for the next time.

- **Wait for the refresh**: once the answer is old, asking shows the old one and fetches the new one
  behind it; ask once more and the new one is shown. If MusicBrainz didn't answer the refresh, it's
  tried again the next time the answer is read from the file - after the hour it is kept in memory, or
  after deadwax restarts.
- **Or clear them now**: **Clear MusicBrainz's saved answers**, under Settings → Connections (or the
  app's You → Server settings → Connections), empties the file and the memory, and the next answers
  are asked of MusicBrainz again. Only speed is lost.
- To stop saving answers altogether, set `MUSICBRAINZ_CACHE_MB` to `0`.
- If the line beside Clear says **Nothing is being saved**, or the `MUSICBRAINZ_CACHE_PATH` row is
  marked, it names what's wrong: a `musicbrainz-cache.db` in that folder that is some other database
  (it's left alone - point `MUSICBRAINZ_CACHE_PATH` at a folder of its own), deadwax's own database, a
  file where the folder should be (`MUSICBRAINZ_CACHE_PATH` is always a folder), a folder deadwax
  can't write to (check `PUID`/`PGID`), or one that isn't there and can't be made - usually a volume
  that isn't mounted, such as `MUSICBRAINZ_CACHE_PATH=/cache` with the `/cache` line under `volumes:`
  left commented out. The row says so from the start, and for as long as it lasts. A `musicbrainz-cache.db` that can't be read at all is set aside
  as `musicbrainz-cache.db.unreadable-<date>` the next time deadwax uses it, and a new one started;
  the old one can be deleted.

## Search shows an old name, or misses something new

The app's Search shows [what deadwax has saved](finding-music.md#what-deadwax-has-saved)
of MusicBrainz's answers first, marked **saved**, under any words - before MusicBrainz is asked. What's saved
is what MusicBrainz said when it was saved: an artist renamed since (still under the old name), an album
added since (missing), a correction (not shown) - until MusicBrainz's own answer for the words arrives, a
second or so later, and adds what it found below the saved rows. What's saved for these exact words is
refreshed behind itself once it's old (a search after 7 days, the rest after 30).

- **Wait for MusicBrainz's answer**: it lands below the saved rows, never moving them. A row of it that is
  the same artist, album or song as a saved row isn't shown twice - the saved row stands for it, as it was
  saved, until the words are searched again after the saved answers behind it are refreshed (above).
- **Or clear them now**: **Clear MusicBrainz's saved answers** (Server settings → Connections - the desktop
  sidebar's Settings, or You → Server settings) empties what's saved and what Search finds in it; the next searches ask
  MusicBrainz again.
- **Nothing saved ever shows**: saving is off (`MUSICBRAINZ_CACHE_MB` is `0`), nothing has been saved yet,
  or the line beside Clear says why nothing is being saved ([above](#a-musicbrainz-answer-looks-out-of-date)).
  The log says it once if deadwax's SQLite can't search text (it needs FTS5, SQLite 3.43 or newer - the
  image's, 3.46, has it): answers are still saved, only not searched. If the file can't be written (a
  read-only folder), the answers in it are still read, Search finds nothing saved, and the log says *couldn't
  make the saved-search index* once; deadwax tries again a minute later.
- **After going back to an older deadwax and forward again**: an older version (1.x, or an early 2.0.0 pre-release)
  saves and drops answers without telling the index. The next start notices (the log says *changed while the
  saved-search index wasn't kept*) and reads every answer into it again, in the background - until it is
  done, Search finds less of what's saved. Nothing needs doing.

## The app's Search says MusicBrainz isn't answering, or keeps asking

The phone app's [Search tab](finding-music.md) and its album pages
ask MusicBrainz through deadwax, so the same slow minutes reach them.

- **"MusicBrainz isn't answering just now - it often goes away for a few minutes."** at the foot of
  Search's list (every kind it asked failed), **"MusicBrainz isn't answering."** in one section's place
  (that kind alone) - or, on an album you don't have, **"MusicBrainz isn't answering just now, so this
  album's pressings couldn't be loaded - it often goes away for a few minutes."**: deadwax couldn't get an
  answer (a search tries three times - about eight seconds when MusicBrainz is turning searches away, up to
  about a minute and a half when its connection hangs, each try waiting half a minute; an album page for a
  while longer). That's not
  the same as **No albums on MusicBrainz for "…"** or **No results for "…"**, which are answers.
  Tap **Try again** in a minute; the album page never shows part of a pressing list as if it were
  all of it. You's **Connections** says whether deadwax can reach MusicBrainz at all, and [You's
  Connections says MusicBrainz isn't connected](#yous-connections-says-musicbrainz-isnt-connected) goes
  through why it might not.
- **"MusicBrainz isn't answering just now - these are what deadwax has saved from it."** (or **"Saved -
  MusicBrainz is away."** / **"Saved - MusicBrainz is busy."** in a section's place): the same, under rows [deadwax had saved](finding-music.md#what-deadwax-has-saved) -
  those stay, and **Try again** asks MusicBrainz again.
- **"MusicBrainz is busy just now - try again in a moment."**: MusicBrainz answered,
  saying it is turning searches away for a moment - it does, often, for a few minutes at a time, and asking
  for artists, albums and songs at once makes it likelier. **Try again** (or **Search** pressed again) draws the
  list afresh for the same words and asks only what failed. After a search MusicBrainz was too slow for, or away for, the next ones
  draw your library's rows at once and MusicBrainz's arrive in the places kept for them, until it answers in
  time again.
- **"MusicBrainz couldn't read that search - try other words"**: MusicBrainz refused the words as a search
  (unusual punctuation can do it; a slash, as in "AC/DC", is fine). There's no Try again - the same words would
  be refused again; change them.
- **A song I know isn't among MusicBrainz's songs, or only covers of it are**: words with no artist you
  have are matched against song **titles** only, so a famous title alone finds tribute bands and string
  quartets ("hey jude" alone has no Beatles in its first pages). Type the artist with the title - an artist in your
  library is read as the artist ("roads portishead"). Even then a famous song can have hundreds of takes
  in no useful order (Hey Jude by The Beatles is 219): its row gathers them, and **More songs** adds the
  albums of the next 25 to it - the studio album can take a page or two to arrive.
- **An album opened from a song shows a pressing that isn't its usual one**: on purpose - the usual one
  hasn't got the song (a bonus track, say), so it opens on one that has. Choose another in **Pressing**.
- **"Show 3 albums from MusicBrainz"** (or artists, or songs) where a section's rows would be: that answer
  arrived after the list was drawn, with something below it, so it waits in the place kept for it rather than
  pushing what's under your finger down. Tap it. (Song search's "Show songs" became this, for every kind.)
- **Only studio albums under Albums for an artist** - "MusicBrainz's studio albums and EPs - See all for
  everything they made." under them: for an artist's name alone All asks MusicBrainz for their studio albums
  and EPs, since otherwise its first answers are live albums, interviews and compilations. **See all** (the
  Albums chip) asks for everything they made, unfiltered.
- **An artist shows twice, mine and MusicBrainz's**: deadwax matches MusicBrainz's artist to yours by the
  artist's MusicBrainz id in your files - or, when they have none, by name, but only when one MusicBrainz
  artist goes by it. With no id in the files and a name several artists share (there are many Nirvanas), both
  rows stay. The lasting fix: apply the album's release (**Edit → Release**), which writes the artist's id
  into its files, let Navidrome rescan, then reload the app (Search keeps your library's artist list while it's
  open). **Which artist is this?** on the artist's page (an admin's) only changes that page, for that visit -
  Search doesn't read it.
- **An album under a song says "a pressing in your library"**: you have a pressing of that album, and
  nothing deadwax has yet says whether the song is on it. MusicBrainz often keeps one song as several
  recordings across an album's pressings and names only some of them in its answer, so the pressing you
  hold can have the song under one the search didn't bring (Dummy's 1994 CD, for "roads portishead") - or
  not have it at all (The Slow Rush's usual CD, for the Japanese CD's bonus track "Patience"). Tap it:
  deadwax fetches the album's pressings first (the row looks busy) and opens **the album you have** when
  yours has the song, otherwise the album you don't have, on a pressing that has it, where **Get** gets
  it. When your library's own search finds the song by that artist on that album, it
  says **in your library** straight away. If it opened the album you don't have because MusicBrainz
  couldn't list the pressings, the page tries again itself.
- **"Asking MusicBrainz…" for a long time**: on a bad day MusicBrainz takes 30-60 seconds a
  request. An album page fetches every pressing's tracklist, which for an album with hundreds of
  pressings is several requests one after another. Once it has them it keeps them while the app is
  open (the last 20 albums), so going back to the album is instant - and
  deadwax saves them too, so the album opens at once next time, after a reload or a restart as well
  ([saved answers](configuration.md#musicbrainzs-saved-answers-settings--connections)).
- **None of your library in Search, or "Can't reach Navidrome" above the list**: your rows come from
  Navidrome's search, and need Navidrome as Home does ([below](#the-player-says-connect-navidrome-or-cant-reach-navidrome));
  its notice sits once above the list, and MusicBrainz's rows still fill every section under it.
- **An album you have is offered with Get under Albums**: only albums whose files carry MusicBrainz's id for
  the ALBUM (the release group) are recognised as yours there.
  - With no MusicBrainz ids at all: match it to its release (**Edit → Release**), which writes them,
    then search again.
  - **An .m4a album deadwax filed** carries the pressing's id but not the album's - deadwax can't
    write that one into an .m4a yet, when filing or in **Edit → Release** - so it stays listed. Its
    own page (tap it) does say "in your library", since that checks every pressing's id. Tagging it
    with Picard, which writes the album's id into .m4a files, makes the list leave it out too.
  - The first search after deadwax restarts can show one for a moment and then mark it "· in your
    library" in place: deadwax looks through the whole library before it first answers.

## Needs a look or Library care says the library is empty, or doesn't show a change

- **"LIBRARY_PATH is not set"**: set it (Settings → Library → Paths) and mount the folder.
- **An empty library** when you know it isn't empty usually means the volume isn't mounted in
  the container. Settings → Library shows whether the path exists.
- **A change made by another program doesn't show up**: tags edited elsewhere don't change a
  folder's date, which is what the library watches. Press **Rescan** in **Library care** (the
  desktop sidebar's **Managing → Library care**, or **You → Library care**).
- **The Library tab** is Navidrome's: an album shows there once Navidrome has scanned it (see
  [the app's Library looks empty](#the-apps-library-looks-empty)).

## Lots of albums say "Folder off-convention"

Their folder names don't match what the template makes from their tags: albums filed by
another tool, or filed before you changed `ALBUM_FOLDER_TEMPLATE`. Changing the template never
moves anything. Applying the album's release (**Edit → Release**) re-files it.

## A downloaded reissue is filed under its reissue's year

Before 1.0.2, a download was filed under the year of the pressing you picked, and with no
original-year tag: a 2011 remaster of a 1975 album went to `Wish You Were Here (2011) [...]`
instead of `(1975)`. **Needs a look** flags these as **No original year**. Open one and apply its
release: that writes the original year and moves the folder. Downloads
since 1.0.2 are filed under the album's year.

## No cover, or "No cover on the Archive"

The Cover Art Archive has no front cover for that release. It's a fact about the release, not
a failure. Pick a different release in **Edit → Release** if a sibling pressing has one. If it
says the request **failed** (*the Cover Art Archive couldn't be reached - try again*, or *the cover
couldn't be downloaded*), the Archive was unreachable or answered with an error - it goes away for
minutes at a time; try again later.

## Lyrics are missing, or land late

- LRCLIB doesn't have every song, and instrumentals get no `.lrc` by design. When LRCLIB is under
  load it asks clients to back off, and a track is retried a few times before it's counted as
  failed; **Get lyrics** tries again.
- If lines light up a beat after they're sung, set `LYRICS_LEAD_MS` (try `300`), save, and press
  **Re-time saved lyrics** beside it, in **Server settings**, under **Library**. It's refused while the lead has an unsaved change ("Save the new lead
  first."), since it re-times to the saved lead.

## A song shows a different picture from its album

Your player is showing a picture embedded in the file, or a disc scan (`cd.jpg`) for songs with a
disc number. A track's **Pictures in this file** (open it from **Edit → Tags**) shows them. **Get CD art** saves a proper `disc.jpg`, which Navidrome prefers over a
`cd.jpg`.

## The artist page can't work out who this is

When the files have no MusicBrainz artist ids and the name is shared by more than one artist,
the page asks you to choose, with each one's description: **Which artist is this?** (an admin's)
gives the page that artist's albums, facts and pictures for this visit, and **Not them?** in its
**Artist images…** does the same for the pictures. Neither is kept: applying one of the artist's
albums' releases (**Edit → Release**) writes their MusicBrainz id into the files, and the page knows
them from then on.

## Artist images… is greyed out, or Move albums to … isn't there

**Artist images…** needs the one folder the artist's albums share, and says under it why there
isn't one: their albums are filed under two names (move them under the current one first, with
**Move albums to …**), or sit in two places, or one sits at the top of the library - or "deadwax
couldn't read their folder just now", when the library didn't answer for it. When it answered for
none of their names, In your library above says "deadwax couldn't read your library just now" too,
with **Try again** (what it said before stays on screen meanwhile); if it keeps saying so, the library
isn't answering deadwax, or its last scan doesn't list them yet - see
[the library is empty](#needs-a-look-or-library-care-says-the-library-is-empty-or-doesnt-show-a-change). **Move albums to …**
shows only when MusicBrainz's name for them differs from a name your library files their albums
under (the **Now** row), and only once MusicBrainz has answered; both are an admin's. A move that says
an album stays names why - a collaboration, one tagged as another artist, a folder of that name
already there under the new name (or another of their albums moving there), or a track that can't be
read ("'03 Three.flac' can't be read, so its tags can't be written": a file cut short or damaged, or
one the user deadwax runs as can't read - check its permissions, or replace it, and move again).

## Stopping or redeploying deadwax takes a few seconds

With a song playing, or the Log open, a stop waits up to 5 seconds for those to finish, then closes them and
shuts down cleanly (MusicBrainz's saved answers written, every connection closed) - well inside the 10 seconds
Docker gives a container before killing it. The container's log then says "Cancel N running task(s), timeout
graceful shutdown exceeded" and shows an "Exception in ASGI application" traceback for each one it closed: that
is the stop closing them, not a fault.

The one exception is a library scan still reading files - the one deadwax makes by itself on the first start
after an upgrade (a big library takes minutes), or a **Rescan**: a scan can't be stopped part-way, so the stop
waits for it and Docker kills deadwax at 10 seconds. Nothing is lost: what the scan read isn't saved until it
finishes, and the scan at start-up runs again at the next start.

## Settings I changed in compose don't take effect

A value saved in Server settings **overrides** compose and `.env`, and the row says so. Press
**Revert** on it to go back to the compose value. Also check you didn't write
`SETTING=${SETTING}` in `environment:`, which quietly sets it to empty when compose has no such
variable of its own; the log warns about this at start-up.

## Signing in

With logins on ([sharing deadwax](sharing.md)). What each message
on the sign-in screen means, and what to do about it:

### Locked out: nobody can sign in

- **"Navidrome isn't answering, so deadwax can't check your password right now"**: signing in asks
  Navidrome, so with Navidrome down nobody can. That's what the **break-glass** sign-in is for: user
  name `deadwax`, password `DEADWAX_ADMIN_PASSWORD`. It needs neither Navidrome nor deadwax's database,
  and lasts 12 hours. If it isn't set, set it in `.env` (or compose) and recreate the container. Sessions already
  signed in carry on while Navidrome is down - only new sign-ins need it.
- **"Logins are on, but ORGANIZE_MODE is 'dry_run', so nothing downloaded would ever be filed into
  the library"** (or `'off'`, or "LIBRARY_PATH is not set"): with logins on,
  each download is the person's who asked for it once it's filed, so organizing has to be on -
  `ORGANIZE_MODE` `copy` or `move`, with `LIBRARY_PATH` and `SLSKD_DOWNLOAD_PATH` set. Until it is,
  everything but the health check and the pages answers 503 saying so, the break-glass sign-in
  included. Set it in compose and recreate the container. If the message says it's **saved in the
  settings** - a value saved in Server settings beats compose, and Server settings can't be reached
  while this stands - set `AUTH_MODE=off`, recreate, set `ORGANIZE_MODE` to `copy` or `move` in Server
  settings (or revert it to compose's), and switch logins on again. While logins are on, Server settings
  refuses to switch organizing off ("they need organizing to stay on").
- **"Logins are on, but DEADWAX_SECRET_KEY isn't set"** (or "is shorter than 32 characters"): logins
  don't work without the key: the pages load, but everything they ask deadwax for (the health check
  aside) answers 503 until it's set, and the sign-in screen says so. Make one with
  `openssl rand -hex 32`, put it in `.env` as `DEADWAX_SECRET_KEY=<the key>` and recreate the
  container. If it's in `.env` already, look for a `DEADWAX_SECRET_KEY` line under compose's
  `environment:` too - uncommented, even an empty one, it beats `.env` - and delete it.
- **"deadwax can't read its database, so it can't check who you are"**: nothing is let in while the
  database can't be read - check `DB_PATH` is on a volume the container can write. The health check
  stays healthy, since restarting doesn't fix a missing volume. The break-glass sign-in still works.
  A volume that's full or has gone read-only signs nobody out - devices already signed in carry on
  (their 30 days just stop moving on) - but a new sign-in answers this until it's fixed.
- **You've lost the way in altogether**: set `AUTH_MODE=off` in compose and recreate the container -
  deadwax is then exactly as it was before logins. The pins and Getting albums settings the first
  admin took over stay with that admin, for when logins are back on. Or sign in with the break-glass
  `deadwax` - it is an admin whatever Navidrome says. Every download is listed, the
  ones people asked for while logins were on included, and **Clear done** forgets every finished
  one. What you get or pin meanwhile goes to the first admin back - at their next
  sign-in, or their first visit if they're still signed in.

### "Sign in to use deadwax." everywhere, and no sign-in screen

The app was open from before deadwax was upgraded and logins switched on, and the version it is
running doesn't know about logins (a current one reloads itself and shows the sign-in). Close the
home-screen app - swipe it away - and open it again, or reload the tab.

### "The break-glass sign-in has ended"

It lasts 12 hours, and ends at once when `DEADWAX_ADMIN_PASSWORD` changes. Sign in again as
`deadwax`.

### "An admin reset your password - sign in with the new one."

An admin reset your Navidrome password in People, which signs you out of deadwax on every device at once.
Sign in with the new password they give you; Amperfy and any other app you use need it too. Your library,
pins and settings are as they were.

### "Your account was removed."

An admin removed your Navidrome account in People. Nothing of yours is left in deadwax to sign in to;
ask them.

### Signed out after changing your Navidrome password

Every few minutes deadwax asks Navidrome whether the login you signed in with still stands. After you
change your Navidrome password - or your account is deleted - that answer is no, and within about six
minutes deadwax signs you out on every device. The player asks Navidrome as you, so it is often
sooner: the first thing the app asks of Navidrome with the old login - opening Browse or
an album, a cover, the next song - is refused, and that session ends there and then (another device
ends at its own first refusal, or at the six-minute check). Nothing more is asked with the old login,
and until Navidrome has taken a login in the last few seconds the app's requests go to it one at a time,
so a page's burst of covers and pins is one refused login per device, not one each - Navidrome blocks an
account for 20 seconds after five. If the new password is refused anyway right after the change ("That
user name and password didn't work"), wait half a minute and try again. The app's sign-in screen comes back over whatever was
showing, saying "Navidrome no longer accepts the login you signed in with": sign in with the new
password and the app is as it was underneath. **The music doesn't wait**, though: from the moment the
session ends, the player can't fetch any more of it. The song playing goes on only as far as your
device has already fetched it (with Gapless on, a few seconds), and then the player skips through the
rest of the queue as it does with any song that won't play - **Skipped "…" - it wouldn't play**, one
song after another - and stops at the end with a reason that blames the song. Nothing is wrong with the
songs: once you've signed in, play the album again. Changing `DEADWAX_SECRET_KEY` (and restarting
deadwax) signs everyone out too, each session at its next request ("DEADWAX_SECRET_KEY has changed since
you signed in").

### Your library says deadwax can't star albums for you

With logins on, deadwax stars what goes into your library **as you**, with the login you last signed in
with. After you change your Navidrome password that login stops working, and
**You → Your library** says so in red: "deadwax can't star albums for you: Navidrome no longer accepts
the login you signed in with". Nothing is lost - what you get meanwhile is kept, waiting. Sign out
(**You → About → Sign out**) and sign in with your new password: deadwax keeps the new login and stars
everything waiting within a few seconds. Changing `DEADWAX_SECRET_KEY` does the same ("DEADWAX_SECRET_KEY
has changed since you signed in"). Signing out by itself doesn't stop deadwax starring for you.

### "Too many tries for … - wait N seconds and try again"

Three wrong passwords for one user name within a minute, and deadwax stops asking Navidrome about that
name until the minute is up - the message says how long. It's there so a mistyped password, or someone
guessing, never gets the account locked in Navidrome itself (which blocks a user for a while after a run
of failures). Other names aren't affected. The break-glass `deadwax` is held off per address instead: three
wrong passwords from one address and that address waits out the minute, even with the right password, while
other addresses can still sign in. So if someone else's guesses are holding you off, sign in from another
address - behind a reverse proxy every sign-in may come from the proxy's own address, so use deadwax's address
on your network rather than the proxy's.

### "DEADWAX_ADMIN_PASSWORD is shorter than 16 characters"

The log says it once at start-up, with logins on, and the break-glass row in Server settings shows it.
The password still works - it's the way in when Navidrome is down, so deadwax never refuses it - but the
user name `deadwax` is public and wrong guesses are only held off per address, so someone with many
addresses gets many guesses: its length is what keeps strangers out. Make a long random one with `openssl rand -base64 18`,
set it in `.env` (or compose), and recreate the container.

### "That user name and password didn't work"

It's your **Navidrome** user name and password - not anything set in deadwax (except the break-glass
`deadwax`). Case doesn't matter in the name. Two names can't be used: `local` (what deadwax calls its one
user with logins off) and `deadwax` (the break-glass sign-in's). An LDAP account can't sign in at all - Navidrome can't check it with a token, and deadwax says so.

### "Your sign-in ran out after 30 days without use"

A session lasts 30 days from when you last used deadwax on that device; using it moves that on. Sign in
again.

### A button says "That needs Edit albums, which an admin hasn't given you"

(Or Look after the library, Settings and the log, Get albums - or "That's People, which only Navidrome's
admins can use".) You're signed in as someone who isn't a Navidrome admin, and no admin has given you that
permission. deadwax's admins are Navidrome's admins: if you should be one, make
your account an admin in Navidrome's Users page - deadwax notices within about six minutes, or at once if
another admin does it in People. Or ask an admin to tick just that permission for you in People (it's in
force from your next tap). The app doesn't show what you can't use, and deadwax refuses it with these
words. A Managing page reached by its address says "You don't have
permission for this page."

### NAVIDROME_URL, NAVIDROME_USER, NAVIDROME_PASSWORD, SLSKD_URL or SLSKD_APIKEY says "Only an admin can change this"

You were given **Settings and the log**, which lets you change the server settings - all but these five.
Everyone's own Navidrome sign-in is sent to `NAVIDROME_URL`, and its answers say who deadwax's admins are;
`NAVIDROME_USER` and its password are deadwax's own account, which People won't touch, so set to your own it
would put you out of People's reach; and slskd's API key, sent to `SLSKD_URL` with every request, is full
control of slskd. Only an admin (a Navidrome admin, or the break-glass `deadwax`) can
change them. Ask one.

### The event log stops while it's open

An open event log asks again before every line whether you may still read it: if an admin took away
**Settings and the log**, you're no longer a Navidrome admin, or your sign-in ended (a password reset, your
account removed), it closes then rather than at your next tap. The page then says why - the sign-in screen
if you were signed out, or "That needs Settings and the log…" if it was taken away.

### "Getting albums is off for you - ask an admin."

An admin unticked **Get albums** for you in People: you can still play, browse and add what the store has
to your library, but not search Soulseek or download. Only an admin can give it back.

### "...the extra permissions an admin gave you are off until you sign in again"

An admin gave you a permission, and deadwax checks it's still the same Navidrome account it was given to
as you sign in - one Navidrome sign-in as you. That check couldn't be made this time (Navidrome was busy
or not answering, or deadwax had just made several sign-ins), so the extra permissions are off on this
device until you sign in again: **You → About → Sign out**, then sign in. A Get albums taken away still
applies. An admin opening People also puts it right, from your next tap.

### People asks for my password

People changes Navidrome's accounts **as you**, and Navidrome only gives deadwax the key for that in
exchange for your password - which deadwax doesn't keep from your sign-in. So People opens locked: type your
Navidrome password to unlock it, on that device, for 15 minutes since you last use it (**Lock** ends it
sooner). Signing out, a restart of deadwax, or a change to your password ends it too.

### "That isn't the password you signed in to deadwax with"

deadwax checks the password you typed into People against the login you signed in with, before Navidrome is
asked anything. If you've changed your Navidrome password since you signed in, sign out and in again with
the new one. Three wrong ones in a minute and deadwax holds off ("Too many tries"), as it does at the
sign-in.

### "Navidrome only takes a few sign-ins from deadwax every 20 seconds"

Navidrome takes at most five of its own sign-ins per 20 seconds from one address, and every one from deadwax
- every admin unlocking People, and some sign-ins - comes from deadwax's address. deadwax holds itself to
four, and says so rather than have Navidrome refuse; nothing is retried by itself. Wait the seconds it
says and try again.

### "Navidrome says you're not one of its admins"

People only works for a Navidrome admin, and Navidrome has just said your account isn't one (perhaps it was
changed in Navidrome since you signed in): you're an ordinary user in deadwax from then on. An admin can make
you one, in People or Navidrome's Users page.

### People says "Navidrome answered in a way deadwax doesn't know"

People uses the interface Navidrome's own web pages use, which isn't documented and can change between
Navidrome versions - People was made for Navidrome 0.64, and says so when yours is another. Nothing else in
deadwax depends on it. Change accounts in Navidrome's own Users page meanwhile. If it says a password
"didn't take", set that person's password in Navidrome's Users page.

### People says "Navidrome didn't answer in time, so deadwax can't tell whether …"

The change was sent, and then nothing came back - Navidrome took too long, or the connection dropped
partway (Navidrome restarting, a proxy closing it). It may have been made. Open People again and look:
an account made or removed shows there (a removed one deadwax couldn't clear is under **Known only to
deadwax** - Forget it), and for a password, try signing in as them. Nothing in deadwax was changed for it:
after a reset like this they stay signed in until the next check finds the old password gone.

### People made an account but "couldn't read the new account back"

The account was made, and its password checked - only the look at which libraries Navidrome gives it
didn't get an answer. Check in Navidrome's own Users page that they have a library, or they'll see nothing.

### People can't make an account: "deadwax still keeps pins, settings or a library for an earlier …"

deadwax still keeps something under that name - an account removed in Navidrome's own Users page, or a
removal deadwax couldn't finish - and a new person must not inherit someone else's library, pins, play queue or
permissions. Find the name under **Known only to deadwax** at the foot of People and **Forget** it, then
make the account; or choose another name.

### Signed in over HTTPS, and now the http address won't sign in

The sign-in seems to work, then deadwax says "Sign in to use deadwax." again - or the sign-in screen just
comes back. You signed in at the same host name over HTTPS before (through a reverse proxy, say), and
that session's cookie is marked Secure. A browser won't let a plain http page replace a Secure cookie, so
every http sign-in's cookie is thrown away while the old one lasts. Either:

- **Use one address**: keep to the HTTPS one (recommended away from home), or the http one - not both
  for the same host name. Two names work fine (`https://music.example.com` outside, `http://nas.lan:8080`
  at home).
- **Or clear the cookie**: sign out at the HTTPS address (**You → About → Sign out**), or delete the
  site's cookies for that host in the browser's settings (on an iPhone, Settings → Safari → Advanced →
  Website Data). Then sign in over http again.

## deadwax is blank inside a dashboard tile or another page

deadwax refuses to be shown inside another site's page (`X-Frame-Options: DENY` and `frame-ancestors
'none'`), so a page elsewhere can't lay its buttons under deadwax's and trick a click through - and a
dashboard's web tile or `<iframe>` showing deadwax goes blank, even one on the same host. There's no
setting to allow it: make the tile a link that opens deadwax in a tab of its own.

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
for Navidrome*. Without it, or with a `NAVIDROME_URL` Server settings marks as unusable, it
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
  it. Applying the album's release (**Edit → Release**) writes it, and the page finds them once
  Navidrome has rescanned. Meanwhile **Which artist is this?** under the words (an admin's) lets you
  choose who they are for this visit ([Managing an artist](player.md#managing-an-artist)).
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

The **Songs** row (on a desktop, the sidebar's item) is left out when Navidrome answers an empty search with no songs, which is how
the app lists them; it asks once, as the app starts (once Navidrome answers) - reload the app to
ask again. A Navidrome that answers an empty
search with nothing (an older one, or one set up to) can't list songs this way, and the Library
shows Albums and Artists only. The albums of the songs are all in Albums.

## The app's Shuffle says "Getting ready…" for a long time

The Library's **Shuffle** ([shuffling the whole library](player.md#shuffling-the-whole-library)) waits for deadwax to read every song of your library from Navidrome before it can make an
order - 15 calls of 2,000 songs for a library of 30,000, which should take several seconds on a NAS the
first time (an estimate: it hasn't been timed on one yet); within ten minutes of that a new order is instant. Leave it a little: it turns into
**Shuffle** once the list is in (above your albums, with how many songs under it).

- **It never gets ready**, and its title (or VoiceOver) says "Couldn't get your songs ready to shuffle":
  deadwax couldn't ask Navidrome - see [the player says "Can't reach Navidrome"](#the-player-says-connect-navidrome-or-cant-reach-navidrome).
  It asks again the next time the list shows: go to another view and back.
- **"Your library is too big to shuffle here"** in deadwax's answer: the shuffle reads at most 200,000
  songs, far beyond a home server's library.
- **A song you added a moment ago isn't in the shuffle**: the order is made from the list as it was read,
  kept ten minutes; the next shuffle after that has it.
- **"Your shuffle started over - deadwax no longer had its order"**: deadwax keeps a shuffle's order in memory, so after a restart (or a day without it being played -
  a shuffle [picked up](player.md#picking-up-where-you-left-off) the next day, say) a fresh order takes over, and
  songs already heard in the old one can come round again. It keeps the last four orders each Shuffle button asked for ahead,
  across all your devices, so it can also happen if the list sat open on one device while that same
  Shuffle got ready (or was tapped) more than four times elsewhere before you tapped it.

## The app's Library looks empty

With logins on the **Library** tab is **your** library - your starred albums
in Navidrome - not the whole store. An account that hasn't starred anything yet, and hasn't had
anything filed for it, sees **Nothing in your library yet** - in any order, Recently played too - and
the same under Artists: tap **Browse the store** (or a row of the Library's **Browse** group - on a desktop,
the sidebar's **Browse** group) for every album deadwax holds, and open one to **Add to my library**. A few
more things that make your library look short:

- **An album waiting to be starred** isn't there yet: your Library lists what Navidrome has starred for
  you, and a download is starred once Navidrome has scanned it. **You → Your library** says what's
  waiting, and why.
- **An album with no MusicBrainz release id** can't be added from its page (deadwax keeps your library
  by release, and the page says so). Star it in Amperfy - your Library is your Navidrome favourites, so
  it shows there - or have an admin match its release.
- **The break-glass `deadwax`** has no library of its own: its Library is the whole store.

## The Library shows the first 10000 albums

The app's Library has each list - your albums, or the store's - from deadwax in one
answer, which reads Navidrome's albums 500 at a time and stops at 10,000 (twenty pages), so a page of it
says **Showing the first 10000 albums - deadwax reads at most that many.** and counts 10000. The rest are
still in Navidrome and in deadwax: **Search** finds them, and an artist's page lists all of theirs. For your
albums it's the 10,000 you starred most recently; for the store's, the 10,000 Navidrome had most recently.

## The Library's albums are in a different order

The app's Library opens **Albums** by **Artist** (each artist's albums oldest first) on a device that never
chose an order - **Recently added** has its own place, as the Library list's grid and its **See all**. Choose
another from the sort at the top of the page: it's remembered on that device, and so is the artists' order. Names are sorted the way
deadwax compares them - "The" at the front set aside, accents and case aside, digits and symbols under **#**
after Z - in the store's lists too, so an album or two can sit where Navidrome's own web page wouldn't put it
(Navidrome also sets aside "La", "El" and others, and puts compilations last).

## The app's Home has no "Not played in a while"

It shows only with at least four albums you last played more than 30 days ago, and only when
Navidrome says when each album was last played (OpenSubsonic's `played`, on its "recently played"
list). A library you've been listening through - everything played in the last month - or a fresh
Navidrome has nothing to show yet. A Navidrome that doesn't send `played` never shows it: Info →
Debug's **Navidrome sent** row (an admin's - with logins on, ask one to look, playing the same album) lists the fields it sends for the album playing. The plays are the
ones Navidrome counts for the account the player asks as - `NAVIDROME_USER` with logins off, your own
with them on - so plays made in another app under another Navidrome user don't
count.

## A pinned album says "Removed from the store", "Not on disk just now" or "Not in Navidrome yet"

- **Removed from the store**: the album was deleted (**Edit → Delete**). Unpin it from Home's **Edit**,
  or get it again - the pin opens the new copy of the same pressing once it's filed.
- **Not on disk just now**: its folder isn't where deadwax last saw it - usually a share or
  disk that isn't mounted. It opens again once the folder is back and deadwax has looked at your
  library again: **Library care → Rescan** scans at once. A
  folder moved by hand outside deadwax is matched up by that scan too, and the pin follows it.
- **Not in Navidrome yet**: deadwax has the album, but Navidrome doesn't, or not as that
  release - it may still be scanning after a download or a re-file. Come back to Home in a moment:
  it asks again each time it's shown. If it stays, check that Navidrome can see the folder and that
  the album's files carry its MusicBrainz release id (Navidrome's `musicBrainzId` on the album).

## An album in my library isn't starred in Amperfy, or "waiting to be starred"

With logins on your library is your starred albums in Navidrome, and **You →
Your library** says how many are still waiting to be starred, and why:

- **"Navidrome hasn't got it yet"** - it was filed, and Navidrome hasn't scanned it. Navidrome's watcher
  usually picks a new folder up within a minute; deadwax asks again after 30 seconds, a minute, two, and
  so on up to every half hour, until the star holds. If it never comes: Navidrome isn't reading the
  folder deadwax files into (`LIBRARY_PATH` and Navidrome's music folder must be the same folder), or
  the folder's files don't carry the release id Navidrome is asked for. **Needs a look** raises a folder
  Navidrome doesn't list as **Not in Navidrome**.
- **"It has no MusicBrainz release id"** - deadwax finds an album in Navidrome by its release id, so an
  untagged album can't be starred by deadwax. An admin can apply a release to it (its Edit panel's
  **Release**); it is starred once it has one. Or star it yourself in Amperfy: deadwax then matches it
  by its album artist and name (when exactly one starred album without a release id has them, and only
  one of your waiting albums without one does - two pressings of one album by the same name both stay
  waiting, since which you starred can't be told) and counts it as starred within five minutes.
- **"Its folder isn't there just now"** - the album's folder is missing (an unmounted share, say).
  deadwax asks again once it's back.
- **"Navidrome isn't answering"** - deadwax asks again by itself.
- **"Navidrome took the star but didn't keep it"** - Navidrome said yes, and the album didn't come back
  starred. deadwax tries again; if it keeps happening, look in Navidrome's log.
- **In red, "deadwax can't star albums for you"** - see [Signing in](#your-library-says-deadwax-cant-star-albums-for-you).

**The first admin's library is empty after signing in** (a new install, or an upgrade from a version
whose saved scan deadwax can't read): the albums already in the store go into it after deadwax's first
scan of the library, which the event log says ("deadwax hasn't scanned the library yet…"). deadwax starts
that scan by itself, in the background, as it starts ("reading every album's tags once now"); on a big
library it takes a few minutes. Once it's done, the event log says how many albums went into the library,
and deadwax stars them. If the log says the scan at start-up failed, search for something or press
**Library care → Rescan** to scan again.

**An album page says "deadwax hasn't found this album's folder in the store"** just after the upgrade:
the same first scan hasn't finished yet - album pages can offer **Add** once it has. Give it a few
minutes (the event log says when it's done), or press **Library care → Rescan**.

An album you **unstar** in Amperfy is taken out of your library at deadwax's next look (every five
minutes) - deadwax never stars it back. An album you star there is added the same way, if the store
holds it: deadwax finds it by its release id, so a starred album Navidrome reads no release id from
isn't added. After an admin applies a release to an album, Navidrome may show it unstarred for a moment:
deadwax notices it is the same album under a new id, or missing mid-scan, and stars it again rather
than taking it out of your library.

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
  none when it knows; tag the album with its release (**Edit → Release**).

## A playlist says songs aren't in the library

"2 songs in this playlist aren't in the library just now - deleted, or being moved": Navidrome still has
those songs in the playlist, but no file for them - an album deleted, a folder moved and not yet scanned,
an unmounted share. Navidrome doesn't list them, so deadwax can't name them. They come back by themselves
once Navidrome finds the files again. In **Edit**, saving a change to the playlist's songs drops them for
good (the page says so before **Done**); changing only its name, description or sharing keeps them. Only
your own playlists say this - somebody else's shared one, or one Navidrome made from a file, plays without
the line.

## Done says the songs were saved, but…

"The songs were saved, but Navidrome didn't take the name, description or sharing: …", or "Saved - but
Navidrome didn't answer when deadwax asked for the playlist again: …": part of the save, or all of it,
went through before Navidrome refused or stopped answering - a busy database ("database is locked"), a
restart. **Edit** stays open with your changes: press **Done** again once Navidrome is answering and it
finishes the rest (it knows the songs it sent may be there already, so it doesn't take them for a change
made in another app). Or press **Cancel** and **Discard**: the playlist is asked for again and shows what
was saved.

## "deadwax adds up to 2,000 songs at a time"

Adding a whole playlist (its **•••**) of more than 2,000 songs to another, or making a new one from it, is
more than deadwax sends in one go - add an album or a few songs at a time, or use Amperfy or Navidrome. A
name over 200 characters and a description over 1,000 are refused the same way, saying so.

## Couldn't save: the playlist changed in another app

"This playlist changed in another app while you were editing it - here it is now. Your changes weren't
saved." While you were in **Edit**, the playlist's songs changed somewhere else - Amperfy, Navidrome's own
page, or deadwax on another device. deadwax saves nothing then (it can't tell which order you meant), and
shows the playlist as it is now: press **Edit** and make the change again.

## No Edit on a playlist

A playlist's page says why in Edit's place:

- **"Only ethan can change this playlist."** It's somebody else's, shared with everyone. Play it, or add
  its songs to one of yours.
- **"Navidrome made this playlist from a file in the music folders…"** A smart playlist (`.nsp`) or one
  imported from an `.m3u` - Navidrome keeps it in step with the file, so it can't be changed or deleted
  here. These are under **From files**; the `.m3u` ones are often the sidecars that came with a Soulseek
  download, which deadwax files beside the songs.
- **"deadwax edits playlists of up to 2,000 songs…"** It plays here; change it in Amperfy or Navidrome.

## The playlists I made in deadwax aren't in Amperfy

With logins off, deadwax makes every playlist as `NAVIDROME_USER` - the one account it uses. Amperfy signed
in as a different Navidrome account sees them only once they're shared (**Edit** → **Shared with
everyone**). Turn [logins](configuration.md#logins-environment-only) on and each person's playlists are made as them, the
same ones Amperfy shows. With logins on, Amperfy shows a new playlist after its next sync.

## Amperfy can't save my change to Ethan's playlist

It's Ethan's: a shared playlist can be played by everyone but changed only by its owner, and Navidrome
refuses the change. Amperfy lets you try and doesn't say it was refused - its copy goes back to Navidrome's
at its next sync. deadwax shows somebody else's playlist with no **Edit**.

## The Edit panel can't find the album's folder

An album page's **Edit** (on a phone as on a desktop) finds the album's folder by its MusicBrainz release, or - for
an album Navidrome knows by no release - by its name among the library's untagged folders ([how it
finds it](library.md#which-folder-and-after-an-edit)). What it says when it can't:

- **"deadwax has no folder of this album: Navidrome knows it by a MusicBrainz release no folder in
  the library is tagged with"**: the files Navidrome scanned carry a release id that no folder in the
  library has - usually an album added by another program since the library was last read, or a
  Navidrome looking at a different folder from `LIBRARY_PATH`. **Look again** reads the library again.
  If its tags were changed by another program, **Rescan** (**Managing → Library care**) first - a
  retag in place isn't noticed otherwise. Or **Choose the folder** and pick it from the list. If it
  isn't there at all, check the two paths point at the same music.
- **"deadwax can't tell which folder this album is: Navidrome knows it by no MusicBrainz release, and
  no untagged folder in the library has its name"**: the album's name or artist in Navidrome isn't the
  one in its files' tags as deadwax reads them, or its folder does carry a release id. **Choose the
  folder** lists every folder in the library's scan; type part of its name, artist or folder to narrow
  the list, and click the one this album is - the panel edits that folder from then on (until the next
  **Edit**). A folder Navidrome doesn't list at all is opened from **Needs a look** instead (**Not in
  Navidrome**, or **Ignored** once accepted).
- **"Which one is it?"**, with a list of folders: more than one untagged folder has the album's name
  and artist (its number of tracks didn't tell them apart). Pick the one this page plays.
- **"The library's scan doesn't list … yet"**: the store knows the folder but the library's last scan
  doesn't. **Look again** scans it.
- **"deadwax couldn't read the library: …"**: reading the library failed - often a reverse proxy
  giving up on a first scan of a large or sleeping library, or a moment without the network. **Look
  again** reads it again.
- **LIBRARY_PATH is not set**: the panel needs the library - see
  [the library is empty](#needs-a-look-or-library-care-says-the-library-is-empty-or-doesnt-show-a-change).

**Edit** itself is missing only for someone deadwax says isn't an admin - with logins off, nobody. On a
phone (a window under 1024 pixels wide) it's at the top of the album's page, beside the pin, rather than
after **Play** and **Shuffle**.

## The "Needs a look" count changes when you open it, or has none

The count beside **Needs a look** (the desktop sidebar's **Managing**, and You's **Albums that need a
look**) is worked out from the library's **saved scan**, never by reading the disk, so it costs
nothing to keep asking. While the page is open it shows the page's own count instead, from a fresh
scan - so if the music changed since the library was last read (an album copied in, retagged or
removed by another program), the number moves as the page opens. They count the same albums: every
album with an issue you haven't accepted, and every album deadwax filed that nobody has looked at.

- **No number at all**: nothing needs a look - or deadwax hasn't answered yet. A count is only drawn
  once deadwax has said one, never a 0 standing in for "not known".
- **Only the new albums are counted** until the library at `LIBRARY_PATH` has been read (deadwax reads
  it as it starts, the first time, and **Needs a look** as it opens): with no saved scan of that folder there is nothing else to
  count from. That is so on a new database, after `LIBRARY_PATH` is pointed somewhere new, and when the
  last read found no albums there at all (an unmounted share, say).
- **An album filed a moment ago** counts at once, before any scan has seen its folder; it appears on
  the page once the page has read the library.
- **Not in Navidrome** is counted from Navidrome's last answer, the one the page's list was checked
  by. The count asks Navidrome only when it hasn't been asked yet (as the app starts) or its answer is
  more than five minutes old, so after Navidrome scans the number can lag until the page has read the
  library again - a read asks Navidrome behind itself, so it's the read after it, or a **Rescan**
  (which waits for Navidrome's answer), that brings the new answer in.

## An album says "Not in Navidrome"

The app's library is Navidrome's, so deadwax checks each album folder against
the albums Navidrome lists and raises one it doesn't, in **Needs a look**
([how it's checked](library.md#not-in-navidrome)). The app can't show or play such an
album until Navidrome lists it. In turn:

- **Navidrome hasn't scanned it yet.** deadwax waits for Navidrome's next scan before flagging a
  folder that changed since its last one began - a folder filed, moved in, retagged or given a cover -
  but for 15 minutes at most, since a folder Navidrome can't see never brings a scan. So a folder
  marked within 15 minutes of a change is one Navidrome has scanned since; one marked later may just
  not have been scanned, if Navidrome's file watcher is off or it only scans on a schedule - a release
  applied in place is marked then too, as Navidrome still has the album as it was. Start a scan in
  Navidrome, then press **Rescan** (in the app, **Library care**) once it has finished: a Rescan asks
  Navidrome and waits for its answer, where an ordinary read asks behind itself and shows the new
  answer only on the read after.
- **Navidrome can't read its files.** Navidrome skips what the user it runs as can't read. Make the
  folder and its files readable by that user - the same `PUID`/`PGID` as deadwax and slskd is
  simplest - and scan again.
- **The folder is outside Navidrome's music folder.** Navidrome has to read the same music deadwax
  files into: point its music folder at what you mount at `LIBRARY_PATH`. A second library in
  Navidrome that the account deadwax uses (`NAVIDROME_USER`) can't see counts as not listed too.
- **deadwax's scan is behind the files.** A folder is matched to Navidrome's albums by its release
  id, or - with none - by its album title and artist, as deadwax last read them. A tag edited by
  another program isn't noticed until **Rescan** (it doesn't change the folder's date), so when
  Navidrome has read the new tags and deadwax still has the old ones, press **Rescan** (in the app,
  **Library care**).

A folder whose files carry no album tag at all is never checked (Navidrome files those under "[Unknown
Album]"). If an album really is fine as it is, **It's fine as it is** accepts it like any issue -
and it leaves the queue. Accepted it, and want it back? **Needs a look → Ignored** lists every album
whose issues you accepted: open it, and **un-ignore** brings it back to **All**.

**No album is marked even though some should be**: the app's **Needs a look** says why in the line
above its list - Navidrome isn't set up, couldn't be asked (with the reason; the
[Navidrome messages below](#the-player-says-connect-navidrome-or-cant-reach-navidrome) are the same), was
scanning when last asked (only the albums already found missing are marked until a read after it), or
hadn't answered when the library was read (it's asked again the next time). A read is checked against
Navidrome's last answer and asks again behind it, so after Navidrome changes it takes one more read -
or a **Rescan**, which waits for Navidrome's answer - for the marks to follow. And a folder that
changed in the last 15 minutes is marked only once Navidrome has scanned since, or the 15 minutes are
up ([above](#an-album-says-not-in-navidrome)) - that one the line doesn't say.

## Ignored albums come back to the review queue

**It's fine as it is** saves which issues you accepted in deadwax's database. When deadwax couldn't
open it (`DB_PATH` - the log says "could not open the job store" as deadwax starts), nothing can be
kept: the album comes back on the next read. **Needs a look** says so above its list ("Ignores can't be
saved: deadwax couldn't open its job store (DB_PATH)…"). Check `DB_PATH` and that the folder it's in
can be written as `PUID`/`PGID`, then restart deadwax.

## Library care's runs don't do what I expect

- **No Get covers · N, Get CD art · N or Get lyrics · N**: nothing in the library (or among the folders
  **Narrow to** matches) needs one - each run says so - or the page is still on the saved scan
  (*Checking the library…*): the runs are offered once the disk has been read. A run that has just
  saved something says *Checking the library…* too, for the moment it takes to read the library again.
- **"had none on the Archive"** / **"had none to find"**: the Cover Art Archive (and, for CD art,
  fanart.tv) answered that it has no picture for that release - a fact about the release.
  **"failed - try those again"**: the request didn't get an answer - the Archive couldn't be reached
  or answered with an error, as it does for minutes at a time - so run it again later. Both stay in
  the next run's count, since neither album has its picture yet.
- **Lyrics counted in tracks**: "not on LRCLIB or instrumental" is final; "failed" is worth another
  go. An album that already has some lyrics isn't offered - finish it from its own **Get lyrics**, in
  its Edit panel.
- **A run's words went**: they're kept while the app stays open, also on another page; a reload
  forgets them.

## The app's Log is missing lines, says "The stream was lost", or starts empty

The **Log** (the desktop sidebar's **Managing → Log**, or **You → Log** on a phone or a desktop) shows
deadwax's event log, newest first. As it opens it reads what deadwax kept: **the last 500
lines since deadwax started** - nothing from before a restart (a Komodo redeploy starts it empty), and
nothing older than those 500. Then it follows deadwax live, joining the two so no line is missing or
shown twice.

- **"The stream was lost - trying again"**: deadwax stopped answering (restarting, or the network
  dropped). The page keeps trying by itself - also behind a reverse proxy that answers with an error
  page while deadwax is down, which makes the browser give up: the page then asks again itself every
  few seconds. When deadwax answers again the lines logged meanwhile are filled in, as long as they are
  among the last 500. If deadwax restarted, its earlier lines are gone from what it kept, but the ones
  already on screen stay.
- **It stays on "Connecting…" behind nginx**: nginx holds a proxied answer in its buffers until they
  fill, and a live log is a trickle. deadwax asks nginx not to buffer the Log (`X-Accel-Buffering: no`),
  which nginx honours unless told to ignore it; a proxy that doesn't know the header needs buffering
  turned off for deadwax - in nginx, `proxy_buffering off;`, as in [Sharing deadwax's sample
  block](sharing.md#turning-logins-on).
- **"deadwax couldn't send the lines it kept"**: the page couldn't read the history as it opened, so it
  shows only what deadwax logs from then on. The next time it opens (leave the page and come back) it
  reads the history again and fills in the earlier lines it missed.
- **It only follows while it is showing.** Leave the page, put the app in the background or open the
  visualizer (or, on a phone, the now-playing screen) over it and it stops listening; it catches up as it shows again. That is on purpose: a
  connection held open is one of the few a browser allows to deadwax, and the player's music uses
  them too. So there is no count of unread lines anywhere.
- **Clear** empties the page only, which then says **Cleared**. Nothing on the server is cleared, and
  the lines cleared don't come back when you return; deadwax's own container log is untouched either
  way.

## The player says "Connect Navidrome" or "Can't reach Navidrome"

[The app](player.md) shows one of these on Home and in the Library tab, in place of your
albums, and in Search in place of what's in your library, with the reason under it - and, since
deadwax needs Navidrome for the app's library, that it does: **Connect Navidrome**
says "deadwax needs Navidrome for your library" and to set it up in deadwax's settings
(Connections), and **Can't reach Navidrome** that your library shows once deadwax can reach it. The other tabs
(and Search's MusicBrainz rows, and an album you don't have) work without Navidrome, and You's
**Connections** shows Navidrome as **Not set up** or **Can't reach it**, with the same reason under it.

- **Connect Navidrome**: the three Navidrome settings aren't all set. Fill in `NAVIDROME_URL`,
  `NAVIDROME_USER` and `NAVIDROME_PASSWORD` in Settings → Connections, which marks the one
  that's missing. The container's log also names it at start-up. In the app, **Set up Navidrome**
  under the reason opens the app's own **Server settings** at **Connections** (on a phone too); once the three are saved there the app asks Navidrome again by itself.
- **"NAVIDROME_URL is unusable (…), so deadwax sends nothing to it"**: the address in your
  compose file or `.env` fails the check Server settings makes on save - a user name or
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

## Saving settings says "type the Navidrome password again - the environment's password was given for the environment's address"

You reverted `NAVIDROME_PASSWORD` to the one in compose or `.env` while `NAVIDROME_URL` is an address
saved in Server settings. That password was given for the address in compose or `.env`, so deadwax won't
put it back to be sent to another one. Type the password for the address you saved, or revert `NAVIDROME_URL` in the same
save to go back to both of compose's or `.env`'s. The same goes for `SLSKD_APIKEY` and `SLSKD_URL` ("type
the slskd API key again - the environment's key was given for the environment's address").

## Saving settings says "type the slskd API key again with the new address"

Every request deadwax sends slskd carries the API key, and the key gives full control of slskd,
so deadwax won't send the saved key to a new address until it has been typed for it. Change
`SLSKD_URL` and type `SLSKD_APIKEY` too, then save both at once; the key's row says so in red
before you save. Saving the address it already is, or reverting it, doesn't need the key.

## The player doesn't pick up where I left off

The app puts back what was playing as it opens, paused
([picking up where you left off](player.md#picking-up-where-you-left-off)). When it doesn't:

- **You're signed in as the break-glass admin** (`deadwax`): it keeps no queue - it has no Navidrome account of
  its own.
- **Navidrome (or deadwax) didn't answer as the app opened**: nothing is put back then. It asks again when you
  come back to the app - switch away and back - at most every 15 seconds.
- **The song that was playing was deleted**: Navidrome keeps a deleted file's song as a *missing file* until it is
  purged (its **Missing Files** page, or `ND_SCANNER_PURGEMISSING`, which is `never` unless set), and until then it
  comes back with the queue - press play and it's skipped like any song that won't play, **Skipped "…" - it
  wouldn't play**, and the next one plays. Once purged, the next one is put back, at 0:00; one further along just
  isn't there.
- **Another app saved an empty queue** since - cleared it: Navidrome's queue is the one believed, so there's
  nothing to put back.
- **It came back a little before where it stopped**: an app iOS closed in a pocket comes back from its last
  save, which is up to 30 seconds old.
- **A browser that won't keep anything for the page** (its storage blocked, or cleared every time): it still picks
  up, but can't remember which device it is, so its own queue comes back with "Picked up from your …" each time.
- **A Navidrome too old for it**: deadwax saves and reads the queue by its position in the list (OpenSubsonic's
  `indexBasedQueue`, which Navidrome 0.64.2 has), so a song in it twice is never confused. A Navidrome without it
  refuses those calls: nothing is put back or saved, and the container's log (not the event log) says now and
  then (at most every ten minutes) that Navidrome didn't keep the play queue.

## It picked up a queue I didn't play

The line at the top said where it came from:

- **"Picked up from a …"** - logins are off, and everyone shares one queue (the `NAVIDROME_USER` account's), so a
  device opening with nothing queued picks up whatever anyone played last. A paused player never takes someone
  else's. With logins on everyone has their own ([Sharing deadwax](sharing.md)).
- **"Picked up from your …"** - another of your devices played since. A paused player brought back to the front
  takes it too, with logins on - play something and the queue is yours again.
- **"Picked up from …" an app's name** - another Subsonic app saved your play queue in Navidrome since. Navidrome
  keeps one queue for each person, and the newest wins.

## Amperfy doesn't show what I was playing in deadwax

Amperfy doesn't use Navidrome's play queue: it keeps its own, on the phone. So it neither shows deadwax's nor
replaces it, and deadwax won't pick up what Amperfy was playing.

## Up Next lost Playing Next or Shuffle after picking up

The queue came back as a plain list - its songs in order from the song playing, which are right - without Up
Next's groups or the Shuffle chip, which only deadwax's own account of the queue keeps. That happens when:

- **another app saved the queue last** - it keeps only the songs;
- **songs were removed from the library** since - deleted and purged from Navidrome's missing files - so the
  account no longer matches the songs;
- **the account was very long** - over 262,144 characters, about 256 KB: a playlist of thousands of different
  songs - and was left out (the 2,000 songs kept are all there);
- **another deadwax on the same Navidrome account** saved it.

## Plays don't show up in Navidrome

- **A song counts once you've heard half of it or four minutes**, whichever comes first, and only
  songs longer than 30 seconds count. Skipping ahead adds nothing, so a song you skipped through
  isn't a play.
- **Plays go to the `NAVIDROME_USER` account with logins off**, and to your own - the account you
  signed in with - with logins on (the break-glass `deadwax`'s go to `NAVIDROME_USER`). Look at that account's play counts.
- **Behind a reverse proxy that rewrites the `Host` header**, deadwax takes the player's play
  reports for requests from another website and refuses them, and the phone doesn't say so. The
  **Log** names each refusal. Pass the original `Host` through, or set
  `TRUSTED_ORIGINS`, as [below](#saving-or-pressing-a-button-says-refused-it-came-from-another-website).
- **Counted in Navidrome, but not on Last.fm or ListenBrainz**: that part is Navidrome's. Check
  the account has them linked there, and that scrobbling is switched on for the `deadwax` player
  on Navidrome's **Players** page.

## The app's page is blank

This only happens running deadwax from source. `/player/` loads a script built from `ui/`, which
isn't in a fresh checkout: run `npm run build` in `ui/`, which builds the app (and the turntable's
test bench). The Docker image builds it for you.

## An old bookmark or home-screen icon opens the app

**An old bookmark or home-screen icon** for `http://<server>:8080/` opens `/`, which sends you to
`/player/` - the app - with a redirect (a 307, so it's never kept for good). That's expected: the old
page at `/` retired in 2.0.0, and with Navidrome set up everything it did is in the app. Re-add the icon from `/player/` if
you'd like it to open there directly. If `/` still shows the old page, the container is still
running a 1.x image: pull the new one. If it lands on a blank page, see
[above](#the-apps-page-is-blank).

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
  Transcoding and Max Bit Rate unset; [the app's guide](player.md#formats-and-navidromes-players-page)
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
  whose album had another release applied to it while it sat in the queue, which Navidrome
  may now know by another id. For that one, open the album again from the grid.
- **"The connection dropped while this song was loading"**: the phone lost deadwax (a VPN
  dropping, say), or deadwax lost Navidrome. The player asks again by itself; if it has stopped,
  tap play.
- **With logins on and libraries of their own in Navidrome** (its multi-library setting), a song that
  plays on a computer but is skipped on an iPhone or iPad, is silent on the turntable, or plays with a
  gap under Gapless: deadwax fetches those songs into its own cache as `NAVIDROME_USER`, and Navidrome
  tells that account it has nothing by that id when it can't see the song's library. Give
  `NAVIDROME_USER` access to every library in Navidrome ([the player as you](player.md#the-player-as-you-with-logins-on)).

## Info has no Debug tab, or it went

**Debug is an admin's**: a Navidrome admin's, the break-glass `deadwax`'s, and with
logins off everyone's. Anyone else's **Info** is **About** alone, with no tabs above it, and About's
**Playing** group says what a listener can use of it: the file's **Format**, **Gapless** and
**Normalization**, in Debug's own words. Where this guide asks for another of Debug's rows, an admin
reads it - and where they read it matters:

- **Rows about the song** - **Navidrome sent**'s **Song**, **On other songs** and **Album** - say the same
  on any device: ask an admin to look on theirs, playing the same song.
- **Rows about the device** - the rest: **Sent as**, **Resampled**, **Why**, **Speed**, **Gap**,
  **Last seek**, **Turntable sound**, **Turntable timing** and **Recording** - describe the device and browser Info is open on. On an admin's own phone they're that
  phone's, not yours. For these, an admin reads Debug on your device: **You → About → Sign out**, let them
  sign in there and do what went wrong again (the same song, the same turn of the record), read the row,
  then sign out and sign back in as you.

Made an admin and still no Debug? It shows as Info opens, once it has asked deadwax who you are - a
moment after it opens, so for that moment Info can still look as it did. **Make admin** in People is in force at once; a role changed in Navidrome's own Users page,
deadwax follows within about six minutes ([Sharing deadwax](sharing.md#when-something-changes)). The other
way round, a Debug that was showing turns into About once deadwax says the role has gone.

## A song sounds too fast, too slow, too high or too low

That's [the speed](player.md#the-speed-fader): set on the turntable's speed
fader, it holds for every song after and is kept on the device, and its pitch moves with it - faster
is higher, slower lower, as a record played at the wrong speed. Off 1x the now-playing screen says so:
a chip (`1.25x`) at the left end of the row of buttons under the cover's transport, and the
turntable's own readout, under its fader; on a desktop, a chip in the player bar. The mini player
above the tabs doesn't show it, so open the now-playing screen. **Tap the chip, or the readout, and
it's back to exactly 1x.** Only a song that sounds wrong at 1x is something else - Info → Debug's **Speed** row
(an admin's, and read on the device it's about - see [Info has no Debug tab](#info-has-no-debug-tab-or-it-went))
says `Normal (1.00x)` then.

A song at another speed that should be higher or lower and **keeps its own pitch** instead (sounds
stretched, the way a podcast at 2x does) means the browser is holding the pitch: Debug's **Speed** row
(an admin's, and read on the device it's about - see [Info has no Debug tab](#info-has-no-debug-tab-or-it-went)) says `but the browser is holding the pitch`, or `this browser has no pitch switch`. Say which browser
it is.

### A browser won't play a speed

Every speed from 0.25x to 2x is in the range Chrome, Edge and Firefox play (Firefox mutes outside
1/8x to 8x; Chrome refuses a speed outside 0.0625x to 16x). On an iPhone and in Safari, Apple's player
promises any song from 1x to 2x, and below 1x only a song it says it can play slowly - not yet seen on
an iPhone either way. Info → Debug's **Speed** row (an admin's, and read on the device it's about - see [Info has no Debug tab](#info-has-no-debug-tab-or-it-went)) says what happened:

- **`Asked for 0.25x; the browser refused it - …`**: the browser threw the speed back, in its own words.
  The song plays on at the speed it had; choose another.
- **`Asked for 0.25x; the browser plays it at 1.00x`**: the browser took another speed instead of it.
- **`The song moved at 1.00x over the last few seconds of playing`** under a speed that isn't 1x: the
  browser said yes but plays the song at its own speed - what a song Apple won't play slowly would do.
  (It reads a little under the speed across a moment the song waited for the network, and comes back
  in a few seconds of playing; after a change of speed it starts again, and shows after a couple of
  seconds of playing at the new one. The row keeps up while Debug stays open.)

Tell us what it says, with the browser, and the song's format from the **Format** row.

## The turntable shows a plain black record, not the album's CD art

The record's face is the CD art deadwax holds for the album - a `disc.jpg` (or `disc2.jpg` for a
song on disc 2) beside its tracks - and the plain record, with the cover as its label, is what it
shows when it can't find one. In the order to check:

- **The album has no CD art yet.** In the album's **Edit → Artwork**, press **Get CD art** (it's
  only there while the album has none), or run **Library care → Get CD art · N**. When the Cover Art Archive and fanart.tv have
  no picture of the disc either, there's none to be had. A `cd.jpg` that came with a download
  doesn't count: it's whatever its sharer scanned.
- **The album isn't tagged with a release.** deadwax finds the album's folder by the MusicBrainz
  release id in its files, which Navidrome reads. An untagged rip has none: match a release in
  **Edit → Release**, then Get CD art.
- **Navidrome hasn't read the new tags yet, or can't be reached.** You's **Connections** says
  whether Navidrome answers. After a retag, Navidrome notices the files by itself a few seconds
  later.
- **deadwax hasn't seen the folder.** It knows the library's folders from its scans and from what
  it files; one copied in by another program is unknown until a scan has seen it (**Library care →
  Rescan**).
- **It was saved while the turntable was showing.** The turntable looks again each time the
  now-playing screen opens: close it and open it again, or switch to the cover and back with the
  button at the top right. (A picture replaced by hand can take up to five minutes to change: the
  phone keeps one that long.)

## The turntable hangs, or the song is slow to come back after you turn the record

Turning the record pauses the song and plays the record's own sound; letting go brings the record back
to speed (0.4 s from still, up to about 0.8 s after a hard flick) and then starts the song again from
there. How long that really takes, and whether the page kept up while your finger was down, is counted
on your device: turn the record a few times, then open **•••** > **Info** > **Debug** and read
**Turntable timing** (an admin's, and read on the device it's about - see [Info has no Debug tab](#info-has-no-debug-tab-or-it-went)).

- **`The song was back N s after the last let-go`**: the whole wait from lifting your finger to the
  song's own playback moving, with how much of it was the record's run back to speed. What is left is
  your browser starting the song again after a seek - on an iPhone that can be several tenths of a
  second, and a web page can't shorten it.
- **`N of M blocks late`** (only where the row above says the sound is "On the main thread", which is
  every page opened over plain `http://`): the record's sound is made by the same thread that draws the
  page there, and each late block is a gap or a click in it. Over `https://` (or `localhost`) the
  browser gives it a thread of its own and this can't happen. A block counts as late when it was still being written once the browser had begun to
  play it. In blocks of 512 (the next line says which) a late block where the record's sound is heard
  moves the page to blocks of 1024 for the rest of the visit, a little later behind your hand and with
  twice the room.
- **`The record's sound: N ms behind the hand by design`**: 121.5 ms on its
  own thread, 142.8 in blocks of 512 and 164.2 in blocks of 1024 on the main thread - then what this
  device's own audio says it adds after that: `base` (in Chrome its hardware's own render; Safari always
  says 2.7 ms, its own 128-frame step, whatever the hardware does), `output` (from there to the speaker -
  a Bluetooth headset's delay included, where the browser knows it) and `from render to speaker` (`base`
  and `output` together, read another way - not a third figure to add), each only where the browser
  gives it - an older Safari may give only `base`. If the turntable feels slow under your finger, what
  you hear is the design figure plus `from render to speaker` (or, where that isn't given, plus `base`
  and `output`); a
  Bluetooth headset is usually the biggest part of it, and no page can shorten that - wired headphones or
  the speaker can.
- **`N frames, K late, the longest gap G ms`**: how the picture kept up while your finger held the
  record. Late frames are the page itself stalling.
- **`let-goes after which the song didn't start`**: the browser refused to start the song without a
  tap, or it took more than three seconds to load. Tap play.
- **`The sound interrupted N times`**: something else on the phone took the audio (a call, another
  app).

The record's sound also stops as soon as the song is back: before, the two
overlapped for up to a few tenths of a second after every let-go, the record's sound a little behind
the song - an echo.

## The turntable's sound warbles or buzzes as you turn the record

The record's sound works each touch's speed out from the touches either side of it, so the jitter in
the phone's touch readings doesn't reach the pitch, and plays about an eighth of a second behind your
hand (121.5 ms - 120 for that, and 1.5 more for the limiter below; over plain `http://` about 143 where
the computer's audio works in 512 frames or fewer at a time, 164 elsewhere). If you hear a warble or a
buzz:

- **A crackle or tick on the loudest drum hits, at any speed, its own included**: on a loud song the
  record's sound would go over full scale (working out the sound between the song's own samples brings
  back the peaks the song has between them, and the sound's filter for the deepest bass adds to them -
  about 2 to 3 dB on a loud, hard-clipped master), and the browser cuts off whatever is over. So the
  sound ends in a limiter that turns it down smoothly, 1.5 ms ahead of a peak, just enough to keep every
  sample half a decibel under full scale, and changes nothing at all where nothing comes near it. **Info** > **Debug** > **Turntable timing** (an admin's, and read on the device it's about - see [Info has no Debug tab](#info-has-no-debug-tab-or-it-went)) says how many peaks it has held
  since the turntable showed and the deepest it turned the sound down (`Peaks held under full scale:
  36 since it showed (65 samples), the deepest 1.4 dB`), brought up to date a moment after you let go
  (the sound runs an eighth of a second behind your hand, and a coast after it is counted too). A loud
  song turned down by a decibel or so on its loudest moments is the limiter doing its job; a crackle
  with that count still at none isn't it.
- **A thin, metallic or fizzy sound on top of the slowed or sped-up song**: slowing or speeding the
  record's sound means working out the sound between the song's own samples, which can leave a faint
  mirror copy of the song's high notes; deadwax reads it through a filter that keeps those 60 to 80 dB
  down. If you hear one, the test bench below tells whether it's deadwax.
- **A slow wobble** as you turn is your hand: the pitch follows the record's speed, as on a real deck.
- **Clicks or crackle**, rather than a wobble, on a page opened over plain `http://`: the sound is made
  on the page's main thread there (**Info** > **Debug** > **Turntable sound** says "On the main
  thread"), and a very busy phone can make it late. Say so if you hear it.
- **The record feels late under your finger**: that is the eighth of a second. It can be shortened, at
  the cost of some of the steadiness.

**To tell whether it is deadwax at all**, use [the turntable's test bench](player.md#testing-the-turntable)
(**Info** > **Debug** > **Open the test bench** for an admin, or `/player/lab/` typed after deadwax's address for anyone): turn the real turntable over test
tones - or over a song from your library, turned exactly as the app turns it -
or have it turned for you at perfect speeds, and hear what it played (A) beside a perfect turntable
turned the same way (B along deadwax's own path, C along a smooth one) - blind if you like. On a song you
know, A against C answers the question directly: if they sound alike, the digital sound is what
scrubbing that song at those speeds sounds like.
If A and C sound alike, what you hear is what turning a record sounds like; if C is clean and A isn't,
deadwax adds it, and the numbers under them say which part. Its **Check this device** gives a file of
numbers and recordings to send - keep the page in view and the screen awake while it runs.

**If you still hear a digital sound after all of that, record it** - three fixes in
a row were each real and each not the one being heard, and a recording from your own device is the
way to find what is (the clipping above was found in one; a recording also holds
each moment's loudest sample before the file's 16 bits cut it off, so it shows how far over anything
went): an admin opens **•••** > **Info** > **Debug** with the turntable showing and its sound started (turn
the record once first), press **Record 20 s** on the **Recording** row, press **Done**, and turn the
record as you normally would for the next 20 seconds. Open Info > Debug again: the row says
`20 s recorded`, and **Save the recording** downloads one JSON file of about 5 MB - what the record's
sound actually played, with every touch as it came and what the sound made of it. Nothing is sent
anywhere by itself; send the file with your report. On a Mac, Chromium with the window narrowed below
1024 px gets the phone layout, and over plain `http://` the same main-thread sound path as the phone.

## The turntable makes no sound when you turn the record

[The turntable](player.md#the-turntable) has its own sound: turning the record
plays the song at the speed of your hand, a flick coasts audibly, and a pause winds down. A press only takes hold of the record when it can make that sound: whenever it can't,
turning it works as it did before - silently, the song playing on under your finger, and no momentum -
rather than pausing the song over silence. When it's silent, **Info → Debug**'s **Turntable sound**
row (**•••** on the now-playing screen, then **Info**, then **Debug** - an admin's, and read on the device it's about: see
[Info has no Debug tab](#info-has-no-debug-tab-or-it-went)) says why, in the order to check:

- **`Off: waiting for a tap to start the sound`**: a phone only lets a page start sound from a tap,
  so the record's sound starts at the first tap on the record, the play/pause or skip buttons, the
  button that switches to the turntable, or the mini player's tap when Now Playing opens as the
  turntable - and a turn of the record before any of those is silent, with the song playing on under your finger as
  before. It stops again whenever the screen closes or the phone locks, and the next tap starts it.
- **`Off: its window is loading - …`** or **`Off: no window yet - …`**: the record plays a stretch
  of the song round where it is, and that stretch hasn't arrived. It's fetched as soon as the sound
  has started - a moment after the first tap - for a paused song as much as a playing one. A press
  outside the stretch
  shown on a `Ready: …` row works as before too - except on a record still coasting from a flick,
  which you catch as ever, silent until the next stretch arrives.
- **`Off: still starting - …`**: the part that plays the sound hasn't begun yet. If it never gets
  past this, the browser isn't running it: tell us which browser and device.
- **`Off: it isn't a FLAC file (…)`**: only FLAC songs have it. Anything else turns silently, with
  no momentum.
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
- **`Ready: …`** and still silent: if the phone's ringer switch is on silent, try it off. Deadwax asks iOS (16.4 and later) to treat the page as playing music from the first
  tap that starts the record's sound until the turntable goes, which should keep the switch from
  muting it - not yet checked on a phone, so say
  if it does. The song's own playback isn't affected either way.
- **`Off: the turntable isn't showing`**: the now-playing screen is on the cover, or closed.

**Opened at a plain `http://` address?** That's fine. A browser gives the
AudioWorklet - the part that plays this sound on an audio thread of its own - only to pages on HTTPS
or `localhost`, so over plain `http://` deadwax plays it on the page's main thread instead, and the line
under **Turntable sound** says so: `On the main thread - this page isn't on HTTPS, so the browser has
no AudioWorklet`. On HTTPS it says `On its own audio thread (an AudioWorklet)`.

Turning the record never touches the song's own playback: if it's silent, the music still plays
exactly as it did when you let go.

## The turntable's sound doesn't sound like the song

The record's sound follows each touch your phone reports at the moment it was made, played back on one
smooth clock (not the audio's own clock, which on an iPhone moves in steps of about 21 ms) - so a steady
turn plays the song at your hand's speed. What's left is by design:

- **It's a moment behind your finger**: about an eighth of a second on HTTPS (121.5 ms), over plain
  `http://` about 0.143 s where the computer's audio works in 512 frames or fewer at a time (Chrome on a
  Mac) and about 0.164 s elsewhere (Safari and every iPhone browser, which can't say) - always the same, so the touches around each moment
  have always arrived before the sound gets there - and a turn that starts as your
  finger lands is timed from that moment, not from when it had gone the few pixels that tell a turn from
  a tap - as far back as about a tenth of a
  second before the record is taken, so a start slower than that keeps the rest. Info > Debug > **Turntable timing** (an admin's, and read on the device it's about - see [Info has no Debug tab](#info-has-no-debug-tab-or-it-went))
  says what your device's audio adds on top - a Bluetooth headset's 150-250 ms most of all. Taking hold of a playing record, or pausing it with the wind-down, repeats the
  song's last eighth of a second as the record's sound takes over; letting go of a playing record at
  about its own speed skips it (the song plays on straight from where your hand let go, while the
  record's sound, that much behind, stops as you let go) - neither is a fault.
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

**The player's cache fills up after an evening with the visualizer open**: with
[Normalization](player.md#normalization) on (the default) every FLAC song you play is kept there as its
levelled copy anyway, and the visualizer's stretches are cut from that copy, adding nothing more; the
cache fills with the songs played, as for an iPhone - raise [`PLAYER_CACHE_MB`](configuration.md#paths)
if that's too few. With Normalization off it shouldn't: in a browser that plays the
FLAC as it is (Chrome, Firefox or Edge with Gapless off),
deadwax reads each stretch the visualizer shows straight out of the FLAC on Navidrome, a little at a
time, and keeps nothing of it in the player's cache. Where it can't, deadwax's log says so once for each song - `a window of song … can't be cut
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

**The feel doesn't seem to match the music**: it is read from the copy over the last few seconds, so
it settles a few seconds into a song and drifts as the song changes (it starts at "in between"). It is tuned on real music: calm music reads **smooth**, metal and other music with
distorted guitars and cymbals filling its top end **aggressive**, and funk and other grooving music
mostly **in between**. A sparse, clean guitar piece can read smooth, and a heavy track **in between**
when it has little top end (few cymbals, little distortion above about 2 kHz) or few, sparse beats.
How loud the record was mastered hardly matters, and neither does a 120 Hz screen; a very quiet record
can read a little smoother and a very loud one a little more aggressive. A screen drawing fewer than 60
frames a second does matter: the feel reads the music less often and misses some of its onsets, and at
30 - which a battery saver can bring (Chrome's Energy Saver halves a page's frame rate) - about a third
of them, so heavy music can read **in between** and grooving music **smooth**. On a laptop on battery,
turning the battery saver off (or plugging in) brings it back. Only the Mandala's shapes follow the
feel; every style follows the tempo.

**The colours aren't the cover's**: until the cover has loaded, and for an album with no cover, **From
the cover** uses the purple. A black-and-white cover gives grey - that is its colour.

**"WebGL isn't available here, so Ambient is showing the simple version."** Your browser has no WebGL,
or has it turned off (some do when the graphics driver is blocked): Ambient shows its plain version;
Bars, Scope and Halo don't need WebGL.

**It didn't take the whole screen**: a browser can refuse to go full screen; the visualizer then fills
the window instead, and works the same.

## With Gapless on, there's still a pause between songs, or the player reloads by itself

[Gapless](player.md#gapless-playback) (in **You**, under **Playback**) depends on the
device and the connection, and **Info → Debug** (**•••** on the now-playing screen, then **Info**, then **Debug** - an
admin's, and read on the device it's about: see [Info has no Debug tab](#info-has-no-debug-tab-or-it-went)) says how each song change went, in its **Gap** row. Compare it with Gapless off on the same phone
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
- **A shuffled album, or one with songs added from Up Next**: the stream follows Up
  Next's order, so the same rules hold - every FLAC song of one format joins in one stream, in whatever
  order; an MP3 or a song of another sample rate added in the middle ends the stream before it, and the
  next tap starts one again. A Play Next in a song's last minute takes the next song back out of the
  stream and fetches the song now next: a `0 ms` reading after it is a join that played straight through.

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
- **Quieter than "Original"**: every resampled song is lowered by 3 dB, the same for
  all of them, so that nothing clips and the joins stay exact. Turn the volume up a notch. Nothing
  else about the sound changes. (With [Normalization](player.md#normalization) on, a resampled song is
  levelled instead, and the 3 dB is part of its level - see
  [Everything is quieter than in other players](#everything-is-quieter-than-in-other-players).)
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

## Everything is quieter than in other players

That's [Normalization](player.md#normalization), on **Automatic** by default: deadwax
brings every FLAC song to one loudness (-18 LUFS, as ReplayGain 2.0 does), and most music is mastered
louder than that, so it comes out 6 to 12 dB quieter. Turn the volume up - nothing else about the sound
changes, and nothing clips. To hear every song exactly as it is, choose **Off** in You → Playback (it takes effect
from the next thing you play): every song is then sent bit for bit as it was.

## The first song of an album takes a while to start

With [Normalization](player.md#normalization) on, the first time deadwax levels an album it downloads and
measures every FLAC song of it before the first one plays - a few seconds for a CD album, longer on a NAS
or for hi-res. Info's **Normalization** row (in About's **Playing**, and in Debug) says `Measuring its album… (7 of 12 songs)` meanwhile.
It happens once an album: the measurements are kept in deadwax's database, and a download deadwax files
is measured as it's filed. Opening the album's page before you tap Play starts the measuring early; a play
from Search, Requests or an artist's **Play** starts it as you tap, so the first play of an album from there
is the one most likely to wait. If the
waits are for songs you've played before, the player's cache is too small to keep their levelled copies
(each about 1.5 times a CD song's file): raise [`PLAYER_CACHE_MB`](configuration.md#paths).

## An MP3 is louder (or quieter) than the songs around it

Only FLAC songs are levelled by [Normalization](player.md#normalization) - and not every FLAC: a 20- or
32-bit one, one with more than two channels, and every song while the player's cache can't be used play as
they are too (Info's **Normalization** row says which). Re-encoding an MP3, AAC or Opus
file to level it would cost quality, so they play as they are. Info's **Normalization** row (in About's **Playing**, and in Debug) says
`Not levelled - MP3 songs play as they are`.

## A box set's first song was louder or quieter than the rest

The first time deadwax levels a big album, measuring all of it can take longer than the 50 seconds a song
is held for (20 for a hi-res song): that first song then plays as it is, that once - and any other song of
the album that comes up while it's still being measured plays as it is too, straight away rather than after
a wait of its own. The rest play at the album's level once the measuring is done (it carries on regardless).
Info's **Normalization** row (in About's **Playing**, and in Debug) says `Played as it is this time - its album was still being measured`
for such a song, and deadwax's log says `plays as it is this time - its album is still being measured`. Play
the album again and every song is at the album's level.

## With Normalization on, songs are skipped one after another

If the browser can't play deadwax's levelled copy of a song - a 24-bit FLAC in an MP4, which is how every FLAC
song comes with [Normalization](player.md#normalization) on (the default) - the player passes it over for the
next song, as it does any song that won't play, when Gapless is off. (In the gapless stream it plays the song as
the file is instead.) It shows as every FLAC song of an album being skipped while MP3s play. Choose **Off** in You
→ Playback, then reload the page: every song is then sent as it always was. And please report it, with the
phone's model and iOS version - it's the one thing about Normalization that couldn't be checked before it
shipped.

## A song still won't stream, or seeks land off in Safari, after switching Normalization off

A song whose levelled copy was refused once - deadwax wouldn't make it (a damaged file, say), or the
browser couldn't decode it - is played as the file itself, without its level, for the rest of the
page's life: with Normalization **Off** too, it's then sent as the bare FLAC (no MP4, so Safari's seeks in it can
land seconds off) and kept out of the gapless stream. Reload the page and it's asked for as before.

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
you let go. If a tap or a drag doesn't move the bar at all, that's a bug worth reporting.

**Where the music lands in a FLAC is Safari's doing**, on an iPhone and on a Mac. To seek, a player
has to work out where in the file a moment is. In a FLAC, where a second of quiet takes far fewer
bytes than a second of loud, Safari estimates it from the bytes it has already read, and in a song
whose loudness changes, that estimate is off: 3 and 8 seconds out on an iPhone, up to 14 in a
song-like test file on a Mac, and up to 50 in one with a quiet first minute. Safari's clock then
says the time you asked for, not the time you hear. Chrome, Arc, Edge and other Chromium browsers
land exactly where asked every time.

**deadwax sends Safari FLAC inside an MP4**, the same audio bit for bit in a container
that carries a table of where everything is, and its seeks land there exactly
([the app's guide](player.md#seeking-and-where-safari-lands) says more). So a song that still
seeks to the wrong place in Safari, or on the iPhone, but not in Chrome, is one that didn't come
that way. **Info → Debug says which** (**•••** on the now-playing screen, then **Info**, then
**Debug** - an admin's, and read on the device it's about: see
[Info has no Debug tab](#info-has-no-debug-tab-or-it-went)): its **Sent as** row says how the song playing was sent.

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
