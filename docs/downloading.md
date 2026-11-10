# Downloading

**Get** searches Soulseek through slskd for the pressing you chose, ranks every folder that comes
back against that pressing's real tracklist, and lets you pick the one to download. **Choose a
source** opens as a sheet over the page on a phone, and as the **Sources** panel beside the album on
a desktop. The **Requests** tab then follows the download until it's filed.

## Where Get is

- **Get the album**, the purple button on [the album you don't have](finding-music.md#the-album-you-dont-have),
  under the **Pressing** button. It gets **the pressing chosen there** - the usual one unless you
  picked another - and the sources are matched against that pressing's tracks. That page is
  reached from Search, from an artist's page, and - for **another pressing of an album you have**,
  the deluxe beside the standard, say - from **Pressings** on the album's own page (see
  [finding music](finding-music.md#another-pressing-of-an-album-you-have)). Its **Pressing** list
  marks every pressing you already have **In your library**.
- **Get**, the small button at the end of an album MusicBrainz offers in the **Search** tab - in Top
  results, under **Albums**, or in the Albums view. It gets the album's usual pressing (the one its page
  opens on), without opening the page. At the end of a song MusicBrainz offers ("Get The Slow Rush, with
  Patience") it gets **the album that song row names, on a pressing that has the song** - its Japanese
  CD, for Patience - and if MusicBrainz can't list that album's pressings just then, the album's page
  opens instead, the song marked, and its **Get the album** takes over: a download is never filed
  without the album's year. It reads **Getting…** while it asks MusicBrainz for the album's pressings,
  which can take a few seconds; if you move on meanwhile - type in the box, open a row, Now Playing
  or another tab - it gives up and reads **Get** again, so the sheet never opens over where you went.
  If MusicBrainz can't list an album's pressings just then, it gets the album as a whole, and the
  sheet says so ("… · the album as a whole").
- **Get**, the same small button on each album row of [an artist's page](player.md#artist-pages)
  that isn't in your library. It works as Search's does - the usual pressing, **Getting…** while it asks
  MusicBrainz, the album as a whole when MusicBrainz can't list the pressings - and gives up if you
  leave the page before MusicBrainz answers.

**Get the album** gets one exact pressing, and the download is matched against **its real
tracklist**: track names, track count and track lengths. When it's filed, each track gets that release's title,
number, disc and ids. **The album as a whole** has no tracklist to match against, so a folder is
scored on its edition, format and availability alone - pick a pressing when you can.

## When you already have it

Before it searches, **Get** looks for the pressing you chose in your library and in your
downloads, by its MusicBrainz release id - and the album's page says the same under **Get the
album**, without searching Soulseek, as you choose a pressing:

- **Already in your library**: every track of that pressing is there. Soulseek isn't searched.
  It shows the folder, how many of its tracks it holds ("11 of 11 tracks") and in what format, and
  there's nothing to download.
- **Already downloading**: a download of that whole pressing is queued or arriving. Soulseek
  isn't searched for this either. It names the user it's coming from and how far it has got
  ("queued", "4 of 10 files"). To try another user, cancel it in Requests and **Get** again. A
  download that has just failed and is being moved to the next user by itself (`AUTO_RETRY_PEER`
  on) counts too, for the few seconds that takes: it says "didn't work - trying another source", and
  nothing about cancelling it for another user, since it's already going to one. With logins on,
  one somebody else asked for says **Already downloading for someone else**, and you can join it;
  and one of yours that somebody else is waiting for too says that cancelling it only takes it off
  your list - another user isn't offered for a download you share
  ([below](#with-logins-on-downloads-per-person)).
- **Part of it downloading**: a download of only some of its tracks is under way, such as one
  disc's folder on its own (fewer files than the pressing has tracks). It will never bring the
  rest, so the search runs as usual, with a note above the sources naming the user and how far it
  has got.
- **Already downloaded**: every file of a download of it has arrived and it's "being added to
  your library now". There's nothing to cancel; once it's filed, **Get** says what your
  library holds of it.
- **Part of it held**: the library has some of its tracks but not all. The search runs as usual,
  with a note above the sources: "You have 9 of 10 tracks of this pressing, in *folder*." - with
  logins on, "The collection has 9 of 10 tracks…" when that folder isn't in your library. The note then
  says what a download would do, because that depends on where it would be filed:
  - "Getting it adds only the tracks that folder doesn't have yet": the part you have is
    in the folder a download of it is filed into, so the tracks already there aren't filed a
    second time.
  - "Getting it would add a separate copy, in *folder*, rather than fill in that folder": the
    part you have is in a folder named some other way (by Picard, or by an older folder naming
    template), so a download is filed as a separate folder, tracks you have included.
- **Another pressing of the same album held**: the search runs, with a note for each pressing
  you have, "You also have another pressing:" and its edition (or year), format and folder. With
  logins on, one the collection holds that isn't in your library says "The collection also has another
  pressing:" instead, and a pressing the collection holds whole that isn't yours says **In the collection,
  not in your library**, with **Add to my library** ([the player as you](player.md#the-player-as-you-with-logins-on)).

The album's page asks again when you choose another pressing, when an album is filed, and when you
come back to it - so after a Get it says **Already downloading**, and a download cancelled in
Requests stops being said. While it's asked again, what it said last stays.

What counts as held is checked on disk every time: the folder has to still be there, with its
files tagged as that release (deadwax reads the first one), and what's counted is the release's
tracks it holds. Each file is matched to a track by its title first, so a set numbered across
its discs, or a stray disc number, still counts; a file whose title isn't the release's (or
that has none) is matched by its disc and track number instead. A track you have twice, as FLAC
and MP3 say, counts once, and audio that isn't one of its tracks doesn't count. A folder whose first file
isn't tagged as that release, such as one shared with untagged files from before deadwax,
doesn't count, so the download goes ahead and filing skips whatever tracks the folder already
has (see [organizing](organizing.md)). An album copied in by another program counts once a scan
has seen it: **Library care → Rescan** ([the library](library.md#library-care)). A Get of the
album as a whole has no release id and isn't checked.

The tracks of a DVD-Video or Blu-ray in a pressing (a deluxe edition's concert film, say), and
any track MusicBrainz lists as a video, aren't counted: they never arrive as audio, so a pressing
is complete once you have all of its audio. A plain "DVD" is counted as audio unless MusicBrainz
marks its tracks as video, since it may be a DVD-Audio disc.

The same check stops a second copy getting through another way:

- **Get** on a source is refused, and the row in Requests says why ("It's already in your
  library." - "in the collection" with logins on - or "It's already downloading."), when the album was filed or started somewhere
  else (on another device, say) after the sources opened. Two taps at once only ever queue one
  download. A download of only part of the pressing refuses nothing.
- **Same source again** and **Another source** don't start a download again once that pressing has been filed
  complete, while another download of all of it is under way, or when the download has already
  been retried meanwhile (from another device, or by `AUTO_RETRY_PEER`) or cleared from the list.
  The row says why while it is still stopped ("It's already downloading.", "It's already been tried
  again meanwhile.", "It's been cleared from the list - Get it again to download it."; whoever runs deadwax
  also sees deadwax's own words, with the source's name or the folder). `AUTO_RETRY_PEER` makes the same check, and says why
  it didn't retry in the event log (except when a tap on the row got there first, which isn't a
  failure).

## The search it runs

The query is the artist and the album title. It's searched under **every name the artist goes
by**, because a sharer's folder is named however the album was credited when they got it:

- the name on the release (the credit, as in "Kanye West" on *Donda*);
- the artist's current name ("Ye"), which is what deadwax files under;
- former names MusicBrainz marks as ended.

The searches run side by side, so an artist with two names costs barely more than one. While it
searches the sheet says **Looking for "Third" by Portishead…** ("This takes a few seconds."), and
under the sources it says what was searched: "Searched for "Portishead Third" · 41 sources, 4 match
your filters". **Search again**, under that line, opens the query (**Search for**) to edit: press
**Search** (or Enter) and an unedited query searches every name again, while an edited one searches exactly what
you typed. How long each search waits for answers is `SLSKD_SEARCH_TIMEOUT`, 8 seconds by default.

**Cancel**, Escape or a tap above the sheet closes it (on a desktop, the panel's close button, or
Escape while you're in it), and stops the search in slskd - at once, so an answer arriving as you
close it picks nothing. Only the newest search's answer is ever shown.

## Choosing a source

Each source found is a card - one folder on one user's share, or one set of folders: an album
shared one folder per disc (`CD 1`, `CD 2`) is one card, marked **in 2 parts, one per disc**, and downloads
as one album. It stays split only when the pressing you chose is a single disc, since one disc of
a bigger set can be exactly that album.

- **The score**, a percentage - **70%** is a 70% match - is how well the folder matches the pressing you chose: green from 75%
  up, amber below. The best match - the highest score that passes the chips, first in **Best
  match** order - has a purple edge and the one solid purple **Get**, and keeps them when you sort
  another way; the rest are tinted. How the score is worked out is in
  [How matching works](matching.md).
- **The folder**, and **from** the user.
- **Speed**, large, with a bar (full at 3 MB/s). It says where its number comes from: **what you got
  from them**, in green, when deadwax has downloaded from that user before (with a `~` when it's an
  average of several downloads); **their usual speed** - the user's own upload rate over their whole
  history, shared between everyone they serve, never a promise of yours - otherwise; and **Unknown**,
  **no speed reported yet**, when there's neither. Nothing in the Soulseek protocol says a transfer's
  speed before it starts, so the speed you got before is the closest thing to an answer there is.
- **Tracks** ("11 of 11", amber when tracks are missing), **Quality** ("FLAC 16/44.1", "FLAC 24/96",
  "MP3 320k", only what the user's client reported), **Size**, and **Starts**: **now** with a free
  slot, **after 3 others** waiting in the user's queue ahead of you, or **soon** with no free slot and nobody ahead.
- **Missing "Threads"**, in amber, when the folder hasn't some of the pressing's tracks - up to three
  named, then how many more. A DVD's tracks are never counted, in Tracks or as missing: a CD+DVD
  shared whole is "14 of 14", its 20 film tracks left out. (The score still counts them, so such a
  folder scores lower than its tracks deserve.)
- **Why it's a 70% match**, last on the card: the **edition words** found in the folder's name
  (REMASTER, DELUXE, …, coloured by what they say), and the score broken down as **chips** -
  **Track names**, **Track count**, **Track lengths**, **Edition**, **Format** and **Availability**,
  each with its own percentage (green from 75%, amber from 40%, red below) and what it measures
  written beside it ("the tracks found whose length is right, to within 8 seconds", say - see
  [How matching works](matching.md)). A part that couldn't be judged (no track lengths reported, say)
  is left out. On a phone they're behind a tap on the **score** (a small arrow beside
  it turns as they open, and the card grows downward, so nothing above them moves); on a desktop
  they're always shown.

![The Sources panel beside Dummy on a desktop: each folder's score and the signals behind it, its speed, tracks, quality, size and when it starts](../assets/images/candidates.png)

**Get** on a card queues that folder's audio files with slskd - the release the search was for,
with the rest of the list as shown kept for **Another source** - and the app switches to **Requests**,
where the download is already showing ("starting…") from the tap, while slskd looks the user up
and connects. That can take several seconds for a firewalled user. If slskd or deadwax refuses it -
the user is offline, or deadwax answers that the pressing is **already downloading** or **already in
your library** - the row there says **didn't start**, with why, under Needs
attention. Only the audio is downloaded.

### Narrowing the list

Above the cards are **Lossless** (every file lossless; a folder whose format couldn't be told never
passes), **24-bit**, **Starts now** (a free upload slot, so it starts at once), **Complete albums only** (every track of the pressing there, as
a card's **Tracks** counts them - so a CD+DVD's whole CD, "14 of 14", passes, and a folder with no
tracklist to count against, the album as a whole, isn't left out) and the sort (**Best match**,
**Highest quality**, **Largest first**, **Smallest first**). They start as your **quality floor**
(You → Getting albums, below): Lossless or 24-bit pressed, or a **320 kbps** chip, which shows only
while that's your floor; Complete albums only always starts off. A floor is judged by the folder's
*worst* file, and a folder whose files don't report a value doesn't pass a floor for it, with one
exception: a lossless folder passes 320 kbps, because lossless beats any lossy bitrate.

The search is scored by your **Format** (You → Getting albums; Prefer lossless unless you choose
otherwise): **Any** - format doesn't count; **Prefer lossless** - a folder with no lossless file
scores lower on Format; **Lossless only** - such folders are left out of the answer altogether. It's
separate from the quality floor, which only filters what was found and never changes a score.

**On a desktop** the panel has two more filters, its own:

- **Match details**: the least each part of the match score may be - **Track names**, **Track count**,
  **Track lengths**, **Edition**, **Format** and **Availability**, a slider each - with a count on the chip of how many are
  set. An unjudged part never satisfies a minimum. Narrow the window to a phone's with the panel open
  and its minimums stop filtering until it's wide again.
- **A sample-rate floor**: **Sample rate** (any), **44.1 kHz+**, **48 kHz+**, **88.2 kHz+** or
  **96 kHz+**, judged by the folder's *worst* file; a folder whose user's client reported no sample
  rate never passes one. It starts at any on each Get, stays as you set it when the panel follows the
  page to another pressing, and **Clear filters** clears it with the rest.

### What else the sources can say

- **Already in your library** or **Already downloading**, in a box where the cards would be: Soulseek
  wasn't searched. A download in flight is cancelled in Requests, if you want another user (with
  logins on, not one somebody else is waiting for too: the box says so).
- Notes above the cards for a part held, a part downloading, and another pressing held.
- **"41 sources found - none match your filters."**, with **Clear filters** and **Search again**.
- **"Nothing found for "Portishead Third"."**, with the query to edit and **Search**. An
  unedited search searches every name again; an edited one searches exactly what you typed.
- **"Nothing lossless found for "Portishead Third"."**, when your **Format** is **Lossless
  only** and Soulseek did answer: every folder it found had no lossless file, so all of them were
  left out. It says so ("Some were found, but none with lossless files - your Format is Lossless
  only, which leaves the rest out."), and that the setting is in You → Getting albums; choose **Prefer lossless**
  or **Any** there and **Get** again to see them. The query to edit is still under it - a lossless
  copy may be shared under other words.
- **slskd unable to search** - not logged in to Soulseek, waiting for its VPN, unreachable - in
  slskd's own words, in amber, with **Try again**.

With VoiceOver, each outcome is read out as it comes - "4 sources.", "Nothing found for …",
"Nothing lossless found for …", why it couldn't search, "Already in your library" - and **Try again**,
**Search** and **Clear filters** leave the focus in the sheet.

### When I tap Get

**When I tap Get** (You → Getting albums) can be **Pick the best source for me** instead of the
default, **Show me the sources**. Then a Get takes the top card itself - in best-match order,
through the chips (your quality floor, unless you change them while it searches), and only when it
scores 75 or more - queues it, and switches to Requests. When nothing qualifies it shows the cards,
with a line saying why: "No close match that passes your filters - choose a source yourself." (none
scores 75% or more and passes the chips) - or, when no source was found at all, only the empty list's own line. It never picks for a pressing you already have, whole or in part, or that is already
downloading, whole or in part: held or downloading whole shows its box, as above, and a part held or
downloading shows the cards with the reason ("You already have part of it - choose a source
yourself."). It never picks for **the album as a whole** either - a row's Get when MusicBrainz couldn't
list the pressings - since with no tracklist a folder is scored on its edition, format and availability alone,
and nearly any lossless folder reaches 75 however few of the tracks it holds ("This pressing has no
tracklist to check the sources against - choose a source yourself."). And it never
picks on a search you edit and run from **Search again**, which you're steering by hand - only on Get itself (and on **Try again**
after slskd couldn't search, which is that Get again). These settings, and Format, are kept for you
on deadwax - see [configuration](configuration.md#your-settings-in-the-app-per-user-on-deadwax).

### On a desktop: the Sources panel

On a desktop (a window 1024 pixels wide or more - see [the app on a desktop](player.md#on-a-desktop))
the sources open in a **Sources** panel beside the album rather than a sheet over it: a third column
from 1280 pixels wide, over the right of the page below that. They're the same cards - each with its
chips and what they measure always showing - with **Match details** and the sample-rate floor added (above). **Get the
album** sits beside the **Pressing** button and shows pressed while the panel shows that pressing's
sources (click it again to close them), and the page stays usable: **choose another pressing and the
sources are searched again for it**, keeping your filters - and never picking a source for you, even
with **Pick the best source for me**, since you're choosing. The panel's close button, or Escape while
you're in it, closes it.

## Requests

The **Requests** tab follows every download, with a count on the tab of the ones on their way, on a
phone and a desktop alike (on a desktop it's the sidebar's **Requests**):

- **Downloading**: the album, who it's coming from, a progress bar and files done out of files
  wanted with the live speed ("6 of 10 files · 1.8 MB/s") - worked out from the bytes arriving, not
  slskd's average since the transfer began. **✕** cancels it ([below](#cancelling)). A download
  being filed into your library reads "adding to your library…" ("adding…" on Home), with nothing
  left to cancel.
- **Waiting**: queued in the user's queue, with its place there when slskd says ("4th in their
  queue"; "4th in line" on Home), or "starting" before it does, with a **✕** too. A download asked for
  with **Get** shows here from the tap, as "starting…" until slskd answers. If the user has already
  refused some of its files while the rest wait, it says so in amber ("4th in their queue · 3 failed"): those files
  won't come, and the download will end as failed unless you move it to another user.
- **Needs attention**: a failed or cancelled download, with why in red - or a Get that slskd or
  deadwax refused, as **didn't start** - with **Another source** and **Same source again**
  ([below](#when-a-download-fails)). Why is said in plain words; deadwax's own refusals ("already in
  your library") as they are, and slskd's under them only for an admin or someone with **Settings and
  the log** - anyone else reads "The download couldn't be started."
- **Done**: how it ended, and how long ago ("In your library · 12 minutes ago"). The other endings:
  **You already had it** (every track was already in the album's folder; the
  download itself is still in slskd's folder), **In your library - 2 files couldn't be added** (some
  files couldn't be written into the library and some tracks were; see
  [troubleshooting](troubleshooting.md#a-download-says-n-files-couldnt-be-added)), **Stopped while
  being added to your library** (deadwax stopped part-way; see
  [troubleshooting](troubleshooting.md#a-download-says-it-stopped-while-being-added-to-your-library)), the
  reason it wasn't added, in plain words ("Downloaded, but not added to your library: deadwax is set to
  rehearse adding albums, without moving any files." for a dry run, say, or "It downloaded, but none of its songs
  could be added to your library."; [every one](troubleshooting.md#requests-says-why-a-download-stopped-or-wasnt-added)),
  and **Downloaded, but not added to your library** when organizing is off - `ORGANIZE_MODE` set to `off`, or `LIBRARY_PATH` or
  `SLSKD_DOWNLOAD_PATH` not set (Settings → Library names which; see
  [troubleshooting](troubleshooting.md#downloads-finish-but-nothing-appears-in-my-library)).
  A done download whose album is in your library - filed, partly filed, or already there - **opens
  that album** when you tap it, and one it filed has a round **▶** that plays it. The five newest of
  those have their songs fetched while Requests shows, so their ▶ plays at once: an album filed while
  you watch is looked for once Navidrome has had a few seconds to scan it, and again, less and less
  often, until it has; one a later download of the same pressing added to is fetched again. Any other
  ▶ opens the album, where Play is one tap away. Which album Navidrome holds for a download is looked
  up by deadwax (by the pressing's MusicBrainz id, which is on the download). A row that can't be
  opened says why, and a later tap tries again: **Not ready to play yet - it may still be scanning.**
  (Navidrome hasn't found it yet - it scans a moment after a filing); **Can't find this album to open
  it - it may have moved, or isn't matched to a pressing.** (an "already there" download whose tracks were in a folder
  deadwax didn't file, with no MusicBrainz tags - no scan changes that - or its folder moved or
  deleted since); the music server **isn't set
  up** or **can't be reached**; or **Couldn't open it - tap to try again.** when deadwax itself didn't
  answer. Those with only whoever runs deadwax to put right (stopped while being added, or organizing
  off) say "Tell whoever runs deadwax." to anyone else, and deadwax's own words under the line to them.
- **Clear done**, at the top, removes every finished, failed and cancelled download, the ones under
  Needs attention included (with logins on, from your list - [below](#with-logins-on-downloads-per-person)).

Each album shows its cover from the Cover Art Archive (the pressing's front cover), or a plain
square when there's none, or no internet to fetch it from. When a download is filed, the Library
picks the new album up by itself once Navidrome has scanned it.

![Requests: one album downloading, one waiting in a user's queue, one refused with another source a tap away, and one filed](../assets/images/downloads.png)

**Home** shows up to three of the downloads on their way under **Arriving**, above Recently added,
with **See all** (or a tap on one) going to the list on Requests - even if you'd left an album open
on that tab. When nothing is on its way, Home has no Arriving section at all. The app looks at the
downloads every half second while Requests is open, keeps looking every few seconds while anything is
on its way, and otherwise stops; it looks again whenever Home comes into view and whenever you come
back to the app, so a download started on another device shows up without anything left running. If
deadwax stops answering while something is on its way (restarting, or the phone off your network for
a moment), the app keeps asking every half second until it answers, and Arriving says "Can't update
downloads right now - showing the last progress. Trying again…"

### When a download fails

The reason is shown on the row, in plain words: the user refused the transfer ("The person sharing it
refused to send it."), stopped responding, the transfer broke off, or slskd reported none of its transfers
for about two minutes ("deadwax lost track of this download - the person sharing it may have gone offline,
or downloads stopped working for a while." - the user gone, usually, or slskd down or restarted). An admin, or someone with **Settings and the log**, also sees slskd's or deadwax's own words
under it; [troubleshooting](troubleshooting.md#requests-says-why-a-download-stopped-or-wasnt-added) has
every reason and what to do about it.

**Same source again** asks the same user again. Only the files that didn't arrive are asked for, and
slskd can pick a partly downloaded file up where it stopped (unless a cancel deleted it; see
below). It's the one to try when a user was briefly offline or a transfer timed out. If slskd
is still stopping the last attempt, the row says to try again in a moment, and a refusal shows
the reason, as with any download.

**Another source · 2 left** moves the download to the next user from the list it was picked from,
skipping any user already tried. It asks up to three in turn until one accepts, and the row then
says **2nd try**, **3rd try** and so on. With none left to try, the row says "No other source to try -
Get it again to search for more." The old attempt's transfers are cleared out of slskd. With
`AUTO_RETRY_PEER` on, this happens by itself when a download fails.

While either runs the button says so ("Trying another source…", "Trying again…") and both wait, and if
nobody would take it, why is shown under the reason ("No other source would send it.", say). On a narrow phone the two buttons stack, so
neither loses its words.

### Cancelling

**✕** on a downloading or waiting download cancels it. It asks first, in the card itself - "Cancel
this download? You'll lose your place in their queue.", with **Keep it** and **Cancel
download** (tap the ✕ again to close the question) - unless **Confirm before cancelling** is off on
that device (You → Getting albums; see
[configuration](configuration.md#the-phone-players-settings-per-device)). It never puts up a pop-up dialog,
which would hold up the music playing in the same app. Once you cancel, the row reads "cancelling…"
at once, its cover and title faded, and the transfers are removed from slskd's own list too. If
`SLSKD_INCOMPLETE_PATH` is set, the half-finished file slskd was writing is deleted as well;
otherwise slskd keeps it, which is its normal behaviour.

## With logins on: downloads per person

With logins on ([sharing deadwax](sharing.md)), a download is the person's who asked for it. With
logins off everyone shares one list, and everything above holds as written (but for a download
moving to its next user by itself counting as **Already downloading**, above) - downloads somebody
asked for while logins were on included: every one is listed, **Clear done** forgets every finished
one, and a Get of a pressing one of them is bringing in is refused ("It's already downloading.")
rather than joined.

- **Who sees what.** Requests, Home's **Arriving** and the count on the Requests tab hold the
  downloads *you* asked for, and the ones you joined. An admin sees everyone's, each row saying who
  asked: **Asked by ethan**, or **Asked by you and ethan** for one you share (a row only you asked
  for says nothing more; one nobody is waiting for any more - its asker removed in People - says **Nobody
  is waiting for this any more**, and carries on, filed for nobody). A user's row of a download somebody
  else is waiting for too says **Someone else asked for it too** - never who. Nobody but an admin (or
  someone an admin gave **Everyone's downloads**) sees somebody else's download. The event log stays
  an admin's; a download that fails says why on its own row, as it always has.
- **Joining.** A pressing somebody else is already downloading whole isn't fetched a second time.
  The sources and the line under **Get the album** say **Already downloading for someone else** (or
  **Already downloaded for someone else** while it's being filed), with what you'd get: the user it's
  coming from, its format and quality as their folder showed it when it was picked, as a source
  card's Quality says it ("FLAC 24/96", "MP3 320k"; just the format, read off its files' names, when
  deadwax wasn't told more) and how far it has got - and **Join this download**. Joining puts it in
  your Requests too: one download, everyone who asked waiting for it. In the sheet it then switches
  to Requests, as a Get does; on the album's page the line says it's yours. If the copy is below your
  quality floor (You → Getting albums), or its folder doesn't say whether it meets it, the box says
  so ("Its quality isn't known, so it may be below your quality floor …") - getting a copy of your
  own instead isn't offered yet. A Get that reaches deadwax just as
  somebody else's download of the same pressing has started joins it too, rather than being
  refused - "Pick the best source for me" included: its row in Requests is then that download, from
  their user, saying **Someone else asked for it too**. Asking for one you're already waiting for is
  still refused ("It's already downloading."). Only a download still on its way can be joined -
  queued, downloading, being filed, or failed and being moved to the next user by itself
  (`AUTO_RETRY_PEER`); one that has finished, stopped or been cleared since the page asked is
  refused, saying which.
- **Cancel means leave.** **✕** on a download somebody else is waiting for too takes away only your
  request: it leaves your Requests and carries on for them. Its question says so - "Leave this
  download? Someone else asked for it too, so it carries on for them.", with **Leave it** - and so
  does the ✕ itself to a screen reader ("Leave …"), the card while it's asked ("leaving…") and,
  once it's gone, the page ("left - it carries on for whoever else asked"). So a download you
  share is no cancel away from another user: Get it again and you'd join it again. The
  download itself is cancelled - slskd told, and the half-finished files removed when
  `SLSKD_INCOMPLETE_PATH` is set - only when the last person waiting for it cancels (they then see it
  cancelled, and can retry it), or when an admin (or someone given Everyone's downloads) cancels: their ✕ is for everyone, and asks
  "Cancel this download for everyone? ethan asked for it." with **Cancel for everyone**.
- **Retrying.** **Another source** and **Same source again** are anyone's who is waiting for the download, and an
  admin's: the one download moves, and everyone waiting moves with it. Anyone else's cancel or retry
  of it is answered as if it weren't there.
- **Clear done** clears finished, failed and cancelled downloads from *your* list; a download is
  forgotten for good once everyone who asked has cleared it, or left it. An admin's clears everyone's
  finished downloads from the admin's own list - the people who asked still see theirs - and one
  cleared that way shows again if it's retried, whether the admin asked for it too or not. A user who
  cleared a failed download somebody else then retries isn't waiting for it any more, and it stays
  out of their list - until they Get it again.
- **One Soulseek search starts at a time.** slskd refuses a search started while another is starting,
  so two people's Gets at the same moment could fail one of them. Each search waits its turn to
  start - a moment, since only the start is held, not the listening for answers - and never
  refuses; after 30 seconds' wait (slskd stuck on one) it starts anyway, and a start slskd still
  hasn't answered after 30 seconds gives up its turn, so one stuck search holds the others up once,
  not until deadwax restarts.
- **Organizing has to be on.** With logins on, `ORGANIZE_MODE` must be `copy` or `move`, with
  `LIBRARY_PATH` and `SLSKD_DOWNLOAD_PATH` set: in dry run nothing is ever filed, so nothing could
  become the people's who asked for it. Until it is, deadwax refuses everything but the health check
  and the pages, saying why (see [troubleshooting](troubleshooting.md#locked-out-nobody-can-sign-in)),
  and Server settings won't switch organizing off while logins are on.
- Downloads made while logins were off are taken over by the first admin to sign in, with the pins
  and Getting albums settings - or, when an admin's session outlived the restart that switched logins
  on (logins switched off and on again, say), by the first admin to use deadwax after it starts
  ([what happens to what you had](sharing.md#what-happens-to-what-you-had)).
- **What a download gives you**: it goes into [your library](player.md#your-library-with-logins-on) -
  your starred albums in Navidrome - when it ends, for everyone still waiting for it (not anyone who
  left it, nor the break-glass `deadwax`, which has no library), and its row in Requests says so:
  - **filed** - added: **In your library** (an admin's row of somebody else's: **In their library**);
  - **every file was already there**, in the folder of that same release - a second copy isn't filed
    beside the first, and it's added: **Already in the collection, added to your library**;
  - **every file was already there** in a folder of **another pressing or an untagged rip** - given to
    nobody on a guess, and an admin is asked to look (**Library care → In nobody's library**):
    **Not added - the collection's copy may be another pressing, so an admin has been asked to check it**.
    Once the admin has looked, the row says so: **Already in the collection, added to your library** after
    their **Add for them**, **Not added - the collection's copy may be another pressing; an admin has
    checked it** after their **Dismiss**;
  - **some files failed to file** - added, marked incomplete: **In your library - 2 files couldn't be
    added**;
  - **a dry run**, or organizing off (with logins off only - on, organizing must be on), **failed**, or
    **nothing could be filed** - nothing; the row says why, as it always has. A download that arrived but
    of which nothing could be filed (nothing found where `SLSKD_DOWNLOAD_PATH` says, filing that failed,
    no track filed) is under **Needs attention** with **Another source** - not **Same source again**, since the same
    files would fail the same way. With logins off it stays under Done.
- **A pressing the collection already holds** that isn't in your library says **In the collection, not in your
  library** with **Add to my library** instead of **Already in your library** - see
  [the app's guide](player.md#your-library-with-logins-on).

## The event log

**Event log** - the desktop sidebar's, under **Manage**, or **You → Manage → Event log** on a phone - shows what's
happening behind the scenes: searches, how many answers came back, queueing, filing, and anything that
went wrong, with slskd's or MusicBrainz's own words where there are any. It shows the last 500 lines
since deadwax started, newest first, then follows new ones live while the page shows: each with its
time, its level - errors in red, warnings in amber - and its words, as text. **Clear** empties the
view; nothing on the server changes. It's an admin's, or the log's for anyone an admin gave
**Settings and the log** ([Sharing deadwax](sharing.md#admins-permissions-and-everyone-else)). See
[troubleshooting](troubleshooting.md#the-event-log-is-missing-lines-says-lost-the-live-feed-or-starts-empty)
when it isn't showing what it should.
