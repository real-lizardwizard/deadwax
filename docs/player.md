# The phone player

There's a second page in deadwax, at **`/player/`**: a music player for your library, made to be
added to an iPhone's home screen and opened like an app. It plays from
**[Navidrome](https://www.navidrome.org)**, through deadwax, which keeps Navidrome's login and
passes on the player's requests, so the phone never holds Navidrome's password and only ever
needs to reach deadwax.

It's growing into one app for everything deadwax does: five tabs along the bottom (**Home**,
**Library**, **Search**, **Requests** and **You**), with the player inside them. **Requests** shows
your downloads as they arrive (since 2.0.0-player.12), and **Search** finds artists, albums and songs -
yours first in each, then MusicBrainz's, in one list as Apple Music shows it (since 2.0.0-player.55) - and
shows an album you don't have with each of its pressings' tracklists (since 2.0.0-player.13) - and **Get** fetches it: the sources found on Soulseek, to choose from
(since 2.0.0-player.15). **Home** has the albums and artists you [pin](#home-and-pins) to it, and
what you haven't played in a while (since 2.0.0-player.18). On a computer's screen - a window 1024
pixels wide or more - the same app has [a desktop's layout](#on-a-desktop) (since 2.0.0-player.19): a
sidebar instead of the tabs, a player bar along the bottom, and the sources beside an album rather
than over it - and, from the player bar, [a full-screen visualizer](#the-visualizer) (since
2.0.0-player.20).

It's early. Playing on a locked iPhone, and moving to the next song by itself there, have been
seen working on a real iPhone; other things haven't been confirmed yet.
[The list is below](#not-yet-verified-on-a-real-iphone).

## What you need

- **Navidrome**, reading your music library. The player plays whatever Navidrome has, so point
  Navidrome at the same folder deadwax files albums into. deadwax needs it for the app's library
  (since 2.0.0-player.46): an album folder Navidrome doesn't list is raised on a desktop's **Needs a
  look** as [Not in Navidrome](library.md#not-in-navidrome), so nothing on disk is out of reach.
- **An account on Navidrome for the player to use.** Use one of your own, and not an admin
  account: nothing the player asks Navidrome for needs one. With logins off, plays are counted on
  this account; with logins on, each person plays as their own account and this one fetches songs
  into deadwax's cache ([the player as you](#the-player-as-you-with-logins-on)).

## Setting it up

Three settings, all blank by default, in **Settings → Connections** (or in your compose file or
`.env`, like any other setting; see [Configuration](configuration.md#navidrome-settings--connections)):

| setting | what to put there |
| --- | --- |
| `NAVIDROME_URL` | Navidrome's address **as seen from inside the deadwax container**, with the `http://` |
| `NAVIDROME_USER` | the Navidrome account the player plays as (with logins on, each person plays as their own, and this one is still needed - [the player as you](#the-player-as-you-with-logins-on)) |
| `NAVIDROME_PASSWORD` | that account's password |

The player stays off until all three are set, and the settings tab marks whichever is missing.

**The address is the one deadwax uses, not the one your phone uses.** It's deadwax that asks
Navidrome for everything, so the phone never needs to reach Navidrome at all. If Navidrome is another
container on the same Docker network, use its service name and internal port:
`http://navidrome:4533`. Don't use `localhost`: inside the deadwax container, that's deadwax
itself.

- **If Navidrome runs under a base path** (its `ND_BASEPATH` setting, such as `/music`), include
  it: `http://navidrome:4533/music`. Leave off the `/rest` that Navidrome's API lives under, which
  deadwax adds by itself, and the `/app` you may see in your browser's address bar.
- **The address can't carry anything else**: no user name or password in it (those have their
  own settings), no `?` or `#`, and no spaces. The settings tab refuses one that does, and says
  why. One set in your compose file or `.env` never goes through the tab, so deadwax checks it
  before sending anything: if it fails, nothing is sent to it, and the player shows **Can't reach
  Navidrome** with what's wrong with the address.
- **Changing the address needs the password again, typed in the same save.** Every request
  deadwax sends Navidrome carries a login made from the password, so deadwax won't send the
  saved one to an address it wasn't typed for. In the settings tab, fill in both, then save.
  Clearing the address, or reverting it to your compose file's, doesn't need the password.
- **The password stays in deadwax.** The settings tab only shows that it's set, and the phone is
  never sent it, or anything made from it.

Then open `http://your-server:8080/player/`. If something's wrong, Home and the Library tab say
what, in place of the albums: **Connect Navidrome** when the settings aren't all there - deadwax
needs Navidrome for your library, set up in deadwax's settings (Connections) - or **Can't reach
Navidrome** with the reason and a **Try again** button. The tab bar and You work without
Navidrome, so You's **Connections** can say what deadwax can and can't reach. [Troubleshooting](troubleshooting.md#the-player-says-connect-navidrome-or-cant-reach-navidrome)
goes through each one.

Setting Navidrome up also changes one thing on the main page: applying a release in the
metadata editor asks Navidrome when it has scanned the new tags before renaming the folder,
instead of waiting a fixed time, and leaves the folder where it is if no scan comes or Navidrome
can't be reached. See [`RETAG_RENAME_WAIT`](configuration.md#organizing).

## Adding it to an iPhone's home screen

1. Open `/player/` in **Safari**.
2. Tap **Share**, then **Add to Home Screen**.
3. It gets its own icon (a record, with the dead wax ring picked out in purple) and opens full
   screen, without Safari's toolbars.

An icon added before the tabs came (2.0.0-player.9) should keep working: the app grew in place at
`/player/`, so there's nothing to add again, and its settings stay under the same names. That
hasn't been checked on a phone yet ([below](#not-yet-verified-on-a-real-iphone)).

## What it does

- **Five tabs** along the bottom: **Home**, **Library**, **Search**, **Requests** and **You**.
  Each keeps its own pages, as an iPhone app's tabs do: an album opened from Home stays under
  Home while you look at the Library, and is there when you come back - the browser's back
  button, or a swipe back, onto another tab brings that tab back as you left it too. Tapping the
  tab you're on goes back to its first screen; tapping it again there scrolls to the top. With the
  phone on its side the tab bar is shorter, each tab's icon beside its name (and Requests' count
  beside its icon, before the name).
- **Home**: **Arriving**, up to three downloads on their way, with **See all** going to the list
  on Requests - only while something is on its way: otherwise Home has no Arriving at all. If
  deadwax stops answering meanwhile, Arriving says what it shows is deadwax's last answer, and the
  app keeps asking until it answers. Then **Pinned**, the albums and artists you pinned, two to a
  row, with **Edit** to reorder and unpin them; **Recently added**, Navidrome's 20 newest albums in
  a row you swipe along; and **Not played in a while**, the albums you last played longest ago (more
  than 30 days), when there are at least four. Tap an album to open it, an artist for their page.
  [Home and pins](#home-and-pins) has the details.
- **Library**: **Albums**, **Artists** or **Songs**, chosen by the chips under the title, with a
  sort under them (tap it for the phone's own picker) and how many there are beside it once the
  whole list is in. **Albums** is a grid in one of four orders - **Recently added**, **Recently
  played**, **Artist** or **Title** - more loading as you scroll. **Artists** is every artist
  Navidrome has, by **Name** or **Most albums**, each opening [their page](#artist-pages); an
  artist who renamed is one row, under the name deadwax files them under (Ye, not Kanye West).
  **Songs** is every song, a page at a time; a song opens its album, where you play it. The Songs
  chip isn't there at all when Navidrome won't list songs that way (it is asked once, for a single
  song). What you're looking at and the albums' order are remembered on that device, and each view
  keeps its place when you switch between them. With logins on, the Library is **yours** and
  **Browse** is the whole store - [the player as you](#the-player-as-you-with-logins-on).
- **An album**: its cover, **Play** and **Shuffle**, and its songs, under "Disc 1", "Disc 2"
  headings for a set. A disc with a title of its own shows it beside its number: "Disc 4 · Live at
  Wembley". The titles are the ones deadwax writes into your files from MusicBrainz (or you set by
  hand in the main page's tag editor), as Navidrome reads them. A one-disc album shows its title
  only when its files carry a disc number: Navidrome keeps a disc's title only for a numbered
  disc, and deadwax writes no disc number for a one-disc release. Files tagged by Picard ("1/1")
  have one; for others, set **Disc** to 1 along with **Disc title** in the tag editor. Tap a song
  to play the album from there. Shuffle plays the album's songs in a random order. The back button
  names the tab it goes back to. The artist's name under the title opens [their page](#artist-pages).
  Under it, **In your library** (with logins on, **In the store** for an album that isn't yours, and
  **Add to my library** under Play - [the player as you](#the-player-as-you-with-logins-on)), and an **Also: …** chip for each other pressing of the album you
  have that Navidrome has found ("Also: 20th Anniversary Reissue 180gram", or the year when a
  pressing has no edition of its own) - tap it for that pressing's page - and, since
  2.0.0-player.41, **Other pressings ›**: every pressing of the album as MusicBrainz lists them, the
  ones you have marked **In your library**, with **Get the album** for another - the deluxe beside the
  standard ([finding music](finding-music.md#another-pressing-of-an-album-you-have)). The row shows
  once deadwax has said what you hold, in a place kept for it, so nothing in it moves as it fills.
  Beside an Also chip, in a row too narrow for all three whole (a phone held upright), it reads
  **Pressings**, and In your library keeps only its tick, to leave the Also chip room - with logins on,
  **In the store**, which has no tick to keep, gives way whole there (a screen reader still hears it). The pin at the top right pins the album to Home ([Home and pins](#home-and-pins)).
  Beside it, for an admin (everyone, with logins off), **Edit** opens the album's editors in a sheet over
  the whole screen (since 2.0.0-player.47 - [below](#looking-after-deadwax-from-a-phone)).
  Since 2.0.0-player.44, tap the **cover** to see it full size - Navidrome's own picture, unresized - in
  [the cover viewer](library.md#the-cover-viewer): tap to zoom in where you touch, pinch, drag to move,
  ✕ or **Close** to put it away (going back puts it away too, as it goes back). And at the foot of the page, under the songs, **Properties**: the
  album's **Year** - "1994 (this pressing 2014)" when this pressing's year isn't the album's own -
  its **Size**, its **Release** on musicbrainz.org (a link that opens beside the app, so the music
  keeps playing; "Not tagged with a MusicBrainz release" when Navidrome says its files carry none) and **First seen**, when
  deadwax first found it, "filed by deadwax" when it was a download. They're what deadwax's own scan
  of the folder says, so they show once deadwax has answered, and a line deadwax can't say is left
  out.
- **A mini player** along the bottom, just above the tabs, while something is playing, with
  play/pause and next. Tap it to open the now-playing screen, from any tab.
- **You**: **Getting albums** - **When I tap Get** (**Show me the sources**, or **Pick the best
  source for me**), the **Quality floor** (Any, 320 kbps, Lossless, 24-bit) and, since
  2.0.0-player.41, **Format** (Any, Prefer lossless, Lossless only - what a Get's sources are scored
  by), kept for you on deadwax rather than on the device (see [configuration](configuration.md#your-settings-in-the-app-per-user-on-deadwax)),
  then **Confirm before cancelling**, which is this device's;
  **Gapless** ([below](#gapless-playback-experimental)), **Now Playing opens as** and
  **Pause winds the record down** ([the turntable](#the-turntable)) and **Maximum quality**
  ([below](#maximum-quality-hi-res-at-48-khz)) under **Playback**;
  **Connections**, whether deadwax can reach MusicBrainz, slskd and Navidrome, checked the first
  time you open You and again with **Check again** (which asks for the version again too); the
  version, and whether logins are on - with them on, who you're signed in as and **Sign out**, which
  ends this device's session (and stops what's playing) and goes back to the sign-in screen
  ([Signing in](#signing-in)). For an admin, **Managing deadwax**: **Albums that need a look**,
  with how many, which opens **Needs a look**, then **Library care**, **Server settings** and **Log** -
  on a phone as on a desktop since 2.0.0-player.47 ([below](#looking-after-deadwax-from-a-phone)) - and
  **Open the main page**, which opens it beside the app.
- **Requests**: your downloads, under **Downloading** (a bar, "6 of 10 files · 1.8 MB/s", who it's
  from, and **✕** to cancel, which asks in the card first - **Keep it** or **Cancel download** -
  unless You's **Confirm before cancelling** is off),
  **Waiting** (its place in the user's queue, or "starting"), **Needs attention** (why it stopped,
  in red, with **Next peer · N left** and **Ask again**) and **Done** (how it ended and how long
  ago: "In your library · 12 minutes ago"), each heading only when it has something under it, and
  **Clear done** at the top. Until deadwax first answers it shows a spinner, never "Nothing
  requested yet". With VoiceOver, what changes is read out: a retry starting or refused, a
  download moving to another heading. The tab carries a count of what's on its way. Covers come
  from the Cover Art Archive, so a phone with no internet shows plain squares. A **Get** lands here,
  showing from the tap. [Downloading](downloading.md#on-the-phone-the-requests-tab) has every state
  and what each button does. A **Done** download whose album is in your library opens it with a
  tap, and one it filed has a round **▶** that plays it - at once for the five newest, whose songs
  are fetched while Requests shows (an album filed while you watch once Navidrome has had a few
  seconds to scan it, looked for again until it has), and otherwise by opening the album, where you
  play it. A row that can't be opened says why: Navidrome hasn't found the album yet, no folder in
  your library is tagged with its release, or Navidrome isn't set up or answering. With
  [logins](#signing-in) on (since 2.0.0-player.49) they're **your** downloads - the ones you asked for
  or joined - and an admin's are everyone's, each saying who asked ("Asked by you and ethan"); a ✕ on
  one somebody else is waiting for too leaves it to them ("Leave it"), and an admin's cancels it for
  everyone. A pressing somebody else is already downloading offers **Join this download** where its
  sources would be, and under **Get the album**. [Downloading](downloading.md#with-logins-on-downloads-per-person)
  has the rules.
- **Search**: one box, then one list as Apple Music shows it (since 2.0.0-player.55): **Top results** - the
  best artist, album or song, yours or not, each saying what it is ("Song · Portishead · Dummy"), three on a
  phone and six tiles on a desktop - then **Artists**, **Albums** and **Songs**, each with yours first, then
  MusicBrainz's, a few of each with **See all** in its heading. The chips **All**, **Artists**, **Albums**
  and **Songs** over the list narrow it to one kind, in full, with **More from your library** and **More from
  MusicBrainz** (**More songs**) for the next pages. Your rows say "in your library" (with logins on, "in
  your library" or "in the store"). An artist opens [their page](#artist-pages) - one only MusicBrainz knows
  by its MusicBrainz id, even with Navidrome down - an album opens it, and a song of yours plays from there
  through its album once that album has been fetched (a ▶ at its right says so - the albums of the songs in
  Top results and then of the first songs are fetched as the answer arrives), and otherwise opens its album.
  MusicBrainz's songs (since 2.0.0-player.53) are every take of one song one row ("Portishead · 4:56 ·
  Dummy · in your library"); in Songs a tap opens the albums it's on - albums and EPs, then singles, then the
  compilations, live albums, soundtracks and broadcasts behind one line that opens - and an album to open it
  on a pressing that has the song, the song marked and scrolled to (one you have the song on opens the album
  you have; one you have a pressing of that nothing yet says has the song says "a pressing in your library",
  and a tap looks through the album's pressings first); in Top results a tap goes straight to the album it
  names. An artist's name alone asks MusicBrainz for their studio albums and EPs (said in a line under them;
  the Albums chip asks for everything) and for no songs - type a title with the artist ("roads portishead").
  MusicBrainz is asked when you press Search on the keyboard or a moment after you stop typing; its albums
  leave out the ones you have (one your library turns out to hold after the list is drawn says "in your
  library", and opens the album you have), and one you have that your library's own search didn't list is
  shown among yours. **Nothing drawn moves under your finger**: what your library can already tell is drawn
  at once, the sections when MusicBrainz has answered (a second and a half at most), and a kind still out
  lands in a place kept for it - drawn straight in when nothing is below it, else behind **Show 3 albums
  from MusicBrainz**. Tap an album MusicBrainz offers for **the album you don't have**: laid out like an
  album you have - its artist a link to their page when it's credited to one artist - with a **Pressing**
  button where Play would be, starting on the usual pressing - its status, date, labels, catalogue number
  and barcode under it, every pressing's in the list, and a filter there for an album of more than 30 - and
  that pressing's tracklist, with its bonus tracks, other versions and renamed or missing tracks marked;
  "maybe in your library", dashed, when only a folder with no MusicBrainz ids has its name ("maybe in the
  store" with logins on, when that folder isn't in your library); and the album and the pressing on
  musicbrainz.org at its foot. MusicBrainz isn't asked for anything until you search, and the album page
  works with Navidrome down. **What deadwax has saved** of MusicBrainz's answers (since 2.0.0-player.56) is
  searched too, under any words, the moment your library is: its rows lead each kind's MusicBrainz rows,
  marked **saved** - search "portishead", open Dummy, and "glory box" later finds Glory Box at once, after a
  restart, with MusicBrainz away - and MusicBrainz's own answer adds what isn't there yet below them. When
  MusicBrainz is away the saved rows stay, with a line saying these are what deadwax has saved.
  [Finding music](finding-music.md#on-the-phone-the-apps-search-tab) has how the box is read, how Top
  results are chosen, [what's saved](finding-music.md#what-deadwax-has-saved) and what every note means.
- **Get**: **Get the album** on the album you don't have - under the Pressing button, with a line
  under it saying what you already have of that pressing, if anything - gets the pressing chosen;
  **Get** at the end of an album MusicBrainz offers in Search gets its usual pressing, and at the end of a
  MusicBrainz song (since 2.0.0-player.55) the album it names, on a pressing that has the song. Each opens
  **Choose a source**, a sheet of the folders found on Soulseek, one card each: the score, the
  folder and who it's from, then **Speed** first and large (what you got from that user before, in
  green, or their own average, or none reported), Tracks, Quality, Size and when it **Starts**, and
  what it's missing in amber - and, behind a tap on the score (since 2.0.0-player.41), why it scored
  what it did: the score's six parts as chips and the edition words in the folder's name.
  **Lossless**, **24-bit**, **Free slot**, **Complete albums only** and the sort narrow the list,
  and **Search again** under it opens the query to edit. The search is scored by You's **Format**.
  A card's **Get** queues it and switches to Requests, where it already shows. With **Pick the best
  source for me** in You, Get queues the best match itself when one scores 75 or more under your
  quality floor (never for the album as a whole, with no tracklist to judge by).
  [Downloading](downloading.md#on-the-phone-get-and-choosing-a-source) has every state of the sheet.
- **Links to the main page** (You's, and the Navidrome message's) open it beside the player, in a
  new tab, so the music keeps playing. From the home-screen app it opens outside the app, in Safari
  or a browser view over it.
- **Now playing**: a large cover (a grey square for an album without one), the song's title, and
  under it the artist and the album on one line ("Pink Floyd — Wish You Were Here"): tap that line
  to go to the album. Then the scrubber; previous, play/pause and next; and a row of buttons: at its
  left end, wherever the speed isn't 1x, [the speed's chip](#the-speed-fader) (`1.25x`; tap it for
  1x), then an **AirPlay** button when there's a speaker on the network to send to, and **•••**.
  The button at its top right, a round record, shows it as [a turntable](#the-turntable) instead.
  Drag it down by its top half, or tap the arrow at its top, to close it (Escape closes it too). While
  it's open nothing behind it can be reached by the keyboard or VoiceOver; opening it moves to its
  close arrow, and closing it goes back to where you were. Until 2.0.0-player.10 it also showed two
  lines about how the song was sent and how the last song changes and seek went, and the Gapless
  switch: those are in [Info → Debug](#info--debug) and in **You** now.
- **•••** on the now-playing screen opens a short menu: **Info**; **Go to album**, which closes
  the now-playing screen and opens the song's album in the tab you're on, as if you'd tapped it
  there; and **Pin album to Home** (**Unpin album from Home** once it is), which pins the song's
  album, closes the menu and says at the top of the screen that it did (or why it couldn't). The
  menu shows what it showed as it opened: a song changing while it's up doesn't change the pin's
  album under your finger.
- **Info** is a sheet over the now-playing screen, with two tabs. **About** is the song, the album
  and the artist: the song's title and artist, "Track 3 of 6 · 5:08 · played 12 times" (counted on
  its own disc; the plays as Navidrome counts them now), its disc's title when the album has disc
  titles ("Disc 2 · Unreleased Tracks", as the album page heads it), and **Written by** whoever
  Navidrome says wrote it; the album's cover, title, year, label, format and number of songs, then
  **This pressing:** its edition, year and format as deadwax holds it (tap the card to go to the
  album); the artist - who they are, from MusicBrainz ("Group · London · 1965 to 2014"), and how
  many of their albums you have (with logins on and a library of your own, how many the store has:
  "3 albums in the store") - with the album's own artist beside it when that's someone else,
  as on a compilation; tap it for their page. It's the song's own artist: a Portishead track on a
  compilation goes to Portishead, not Various Artists, and only an old credit of a renamed artist
  (Kanye West on a Ye album, one MusicBrainz artist under two names) goes to the page the album is
  filed under. Last, **In your library → Folder** (headed **In the store** with logins on and a
  library of your own - the folder is the store's, whoever it's in the library of): where the album is on disk, a folder a line for
  a set kept one folder per disc - text you can select and copy. Info asks Navidrome, deadwax and
  MusicBrainz for these as it opens, so they appear a moment after it does (the song's and the
  pressing's together, so a card doesn't grow under your finger). Anything not sent is left out,
  never guessed. **Debug** is how the song is
  being played, in labelled rows: see [Info → Debug](#info--debug). **Done**, Escape or a tap above
  the sheet closes it.
- **The scrubber** is the whole bar: tap anywhere along it to jump there, or drag from anywhere on
  it and it follows your finger, seeking when you let go. It works from the keyboard too (arrows
  move 5 seconds, Page Up and Page Down 30, Home and End to the ends), and VoiceOver's swipe up
  and down move it. [Seeking](#seeking-and-where-safari-lands) says why a seek in Safari can land
  somewhere other than where you put it.
- **Previous** restarts the song if you're more than three seconds in, and goes back a song if
  you're not, as Apple Music does.
- **A song that won't play doesn't stop the album.** The player asks for it once more a moment
  later, and if that fails too, moves on to the next song, saying **Skipped "…"** and why for a
  few seconds: in the mini player where the artist goes, and above the song's title on the
  now-playing screen. At the end of the queue it stops, with the reason on screen.
  [Troubleshooting](troubleshooting.md#a-song-in-the-player-wont-start-or-cant-be-skipped-through)
  goes through the reasons.
- **The lock screen and Control Center** show the song, its artist, album and cover, with
  previous, next and a scrubber. There are no 10-second skip buttons: iOS shows either those or
  previous and next, never both.
- **Back** works: an open album is in the page's address, so the browser's back goes back to
  where you opened it from, scrolled where you left it. A saved link to an album from before the
  tabs (`#/album/…`) still opens it, in the Library.
- **The look** is deadwax's own, the same "touch of Windows 7" as its other screens: Noto Sans,
  with monospace for track numbers and times, square-ish corners, no blur. It's drawn from the
  same fonts deadwax serves itself, so it needs no internet.

## Artist pages

An artist's page (since 2.0.0-player.17) opens from Search (Top results and the Artists section - an artist
only MusicBrainz knows by its MusicBrainz id, since 2.0.0-player.55), **Library → Artists**, the artist's name on an album you have and on the album you don't
have, and Info's artist card.

- **At the top**, their picture - their background (`fanart.*`) where it's in their folder, else the
  one Navidrome has for them, which is the `artist.jpg` **Artist images…** saves into their folder
  ([below](#managing-an-artist)) - or a plain coloured band, with their name at its foot (their logo
  in its place where `logo.*` is in their folder) and who they are under it ("Group · Bristol · since
  1991", from MusicBrainz). **Pin** at its top right pins them to Home (it reads **Pinned** once they
  are); it waits, greyed, until the page knows who they are on MusicBrainz, or that nobody can say -
  [Home and pins](#home-and-pins).
- **Play** and **Shuffle** play every album of theirs you have, one copy of each (the plain edition
  when you have several), in the order the page lists them - with logins on, every album of theirs in
  the store, yours or not ("Plays the 2 albums in the store" -
  [the player as you](#the-player-as-you-with-logins-on)). They wait - greyed - until every
  album's songs have come from Navidrome - fetched a few at a time as soon as the page knows them -
  so a tap plays at once; the line under them says what they'll play, that Navidrome is still being asked or has
  none of theirs, or that it didn't send some (with **Try again**). They're there from the moment
  the page opens, whenever Navidrome could have albums of theirs, so nothing moves when it answers.
- **Albums** is their albums as MusicBrainz lists them - every one, not a search's best matches -
  oldest first, those with no date last: the ones you have marked **✓ in your library** (and "2
  editions" when you have more than one pressing - with logins on the ✓ is for yours alone, and one the
  store holds that isn't yours reads "2008 · in the store", with no ✓ and no Get: it opens its page,
  which has **Add to my library**), the others **not in your library** with a
  **Get** chip that opens the sources for the album's usual pressing, as Search's does. Every album
  of theirs you have that MusicBrainz's list doesn't match (an untagged rip, an EP, a live album) is
  listed too, one row per album, so nothing you have is left off. The list waits a moment for
  Navidrome, MusicBrainz and your library to answer and is then drawn once - "Looking in your
  library…" ("Looking in the store…" with logins on) or "Asking MusicBrainz…" meanwhile - and what isn't
  in your library is only said once
  your library has answered. **Studio only** (on to begin with) leaves out MusicBrainz's live
  albums, compilations and the like - never one you have; toggling it keeps the list on screen
  until the new one comes. An album you have opens; one you don't opens the album you don't have.
  Back to the page from an album draws it at once, where you left it.
- **A renamed artist** is one page: Ye's has Donda (credited to Kanye West) and BULLY (credited to
  Ye) side by side, since MusicBrainz lists an artist's albums under every name they've used.
- **Which artist** it is on MusicBrainz comes from Navidrome (the album artist's MusicBrainz id it
  reads from your files), else from the MusicBrainz ids deadwax wrote into the albums of theirs you
  have. With neither - files tagged by something else, or not at all - the page says MusicBrainz
  doesn't know who this is and lists only what you have, with **Which artist is this?** to choose
  ([below](#managing-an-artist)). An artist opened from MusicBrainz is
  matched to Navidrome's the same way, and by name only when exactly one artist in your library
  goes by it.
- The page works with Navidrome down for an artist opened from MusicBrainz (their albums, without
  what you have); one opened from your library needs Navidrome, like an album you have. If deadwax
  couldn't ask Navidrome for them, the page says why, with **Try again**.

Under the albums (since 2.0.0-player.45, as the main page's artist page has them), once the albums are
drawn and MusicBrainz and your library have answered - or after three seconds - and all at once, so
nothing above them moves as they come. If your library still hasn't answered by then (its first look
after deadwax restarts can take a while), **In your library** comes last instead of first, saying it's
looking, and fills in where it is:

- **In your library**: how many albums and tracks you have under their names, their size, the years,
  and the folder they share - or the folders, and why there isn't one (their albums filed under two
  names, say, or in two places). It's every name your library files their albums under: Ye's page
  counts Donda, filed as "Kanye West", and BULLY, filed as "Ye". It goes by the album artist your
  files carry, as the main page does, so two artists your files give the same name (two bands called
  Nirvana) are counted together. If deadwax couldn't read your library for them just then, it says so,
  with **Try again** - over what it said before, when it had said anything - rather than claiming
  there's nothing of theirs. With logins on it's headed **In the store** and counts what the store holds
  of theirs, whoever's library it's in ("Nothing of theirs in the store.", "Looking in the store…").
- **About**, from MusicBrainz: what tells them apart from others of the name ("formerly Kanye West"),
  **Now: …** when your library files their albums under a name that isn't theirs now (on their page by
  the name they have now, **Also filed as: …** names the others instead), then **Type**,
  **From**, when they began and ended in words - **Born** and **Died** for a person, **Founded** and
  **Dissolved** for a group, **Began** and **Ended** otherwise ("8 June 1977") - and **Other names**;
  their genres; and their links, the first eight with the rest behind "N more links", each opening
  beside the app, two of a kind told apart (**Official site · portishead.co.uk**). If MusicBrainz
  doesn't answer, About says so, with **Try again**.
- **Line-up**, for a group: its members, the current ones first, with their roles and years, past
  members stepped back, the first ten with the rest behind "N earlier members".

### Managing an artist

For an admin (everyone, while logins are off; with them on, the names in `DEADWAX_ADMINS`), on a phone
and on a desktop:

- **Artist images…** (under In your library) shows every picture of them found - Wikimedia Commons
  always, TheAudioDB and fanart.tv when deadwax's settings have their keys (under **Connections**;
  the picker says which is missing) - slot by slot: square image, banner, background, logo, wide
  image and clear art, each with where it's from, and the file already in their folder or "none
  found for this". The best of each is chosen to start with; tap a picture to choose it, tap it again
  to leave that slot alone; **Use another picture** puts any picture found in any slot. **Save**
  writes them into their folder (`artist.*`, `banner.*`, `fanart.*`, `logo.*`, `landscape.*`,
  `clearart.*` - [the library guide](library.md#artist-pages) has which app reads which); **Replace
  pictures that are already there** says whether a file already in a slot is replaced. **Not them?**
  searches MusicBrainz for another artist, for the pictures alone; while that artist's pictures are
  being looked for, or if that look fails, **Save** waits (and **Try again** looks for that artist
  again). It needs one folder: greyed, it says why - their albums filed under two names (move them
  first, below), or in two places, or that deadwax couldn't read their folder just then.
- **Move albums to …** (in About's **Now** row, when your library files their albums under a name
  that isn't theirs now) previews every album that would move - where it is, where it goes, how many
  tracks and how many are retagged - every album that stays and why (a collaboration, one tagged as
  another artist, a folder of that name already there or another album moving there, a track deadwax
  can't read), then **Move N albums** moves them: each album's folder goes under the current name
  keeping its own name, its album artist tag becomes the current name, and each track's own artist
  (what the sleeve credited) stays. The old folder goes once it's empty, and their pictures come with
  it. What happened is said, with **Done** - every album that didn't move, and why. On the page of an
  old name every album of which moved, the page follows them: it becomes their page by their
  MusicBrainz id, where you were on it. Any other page - theirs by the name they have now, or a name
  an album stayed under - stays as it is. Ten seconds after the move the page asks Navidrome again, by
  when it has usually scanned the move. A Mac's hidden `._` twin of a track (its resource fork) is
  never retagged; it moves with its folder. A track deadwax can't read - cut short, damaged, or not
  readable by the user deadwax runs as - keeps its album where it is: its tags can't be rewritten, and
  moved it would still name the old artist.
- **Which artist is this?** - where the page says MusicBrainz doesn't know who this is (the files
  don't say, or several artists share the name: there are eight called Nirvana) - searches MusicBrainz
  for the name and lists every artist going by it, with what tells them apart ("as Kanye West" when an
  old name of theirs matched). Choosing one gives the page their albums, About and pictures for this
  visit (the page says so, with **Change**); applying an album's release in the metadata editor writes
  who it's by into its files, for good.

These open as a sheet over the whole screen on a phone (on its side, the sheet scrolls as one), and
on a desktop as a panel beside the page (by the same rule as Sources and the Edit panel: one panel at
a time, a third column from 1280 pixels, over the page's right edge below that). **Escape** closes it -
on a desktop, from inside it.

## Home and pins

**Home** is the player's: what's on its way, what you keep coming back to, what's new, and what you
haven't heard for a while. In order:

- **Arriving**, only while a download is on its way ([above](#what-it-does)).
- **Pinned** - the albums and artists you pinned, two to a row (one to a row on a phone narrower
  than 374 points, so each card has room to say what it needs): an artist's picture round, an
  album's cover square, its name over "Artist" or the album's artist. Tap a card to open the album or
  the artist's page. With nothing pinned yet it says how to pin something.
- **New in your library** - with logins on (since 2.0.0-player.51): the albums added to [your
  library](#your-library-with-logins-on) since you last opened them - filed for you (or added for you
  by an admin after a look), or starred in Amperfy - once Navidrome has them. An album you add yourself
  with **Add to my library** isn't marked new: you were looking at it. Opening one, from here or
  anywhere in the app, takes it off. With nothing new, or logins off, there's no such section.
- **Recently added**, Navidrome's 20 newest albums.
- **Not played in a while**: the albums you last played more than 30 days ago, the longest ago
  first, up to 20 - made from Navidrome's list of the albums played most recently (its first 500),
  by when each was last played. With fewer than four, or a Navidrome that doesn't say when an album
  was played, there's no such section at all. The plays are the ones Navidrome counts for the
  account the player asks as - `NAVIDROME_USER` with logins off, your own with them on (since
  2.0.0-player.52; [the player as you](#the-player-as-you-with-logins-on)).

Home waits a moment for your pins before it draws the shelves under them (a second and a half at
most while Home is on screen - counted again if you leave it before then and come back, until your
pins have once arrived or the wait has once run out), so Pinned arriving never pushes them down under
your finger.

**Pinning.** Three places pin something to Home: the pin at the top right of **an album** you have,
**Pin** at the top right of **an artist's page** (it says **Pinned** once they are), and **Pin album to
Home** in the now-playing screen's **•••** menu, for the song's album. Tap again to unpin. A new pin
goes first. The pin shows straight away and is saved behind it; if deadwax can't keep it, it goes
back, and a note at the top of the screen says which album or artist and why ("Couldn't pin Dummy:
Home holds up to 50 pins - unpin one first"). The ••• menu closes as you tap it, so the note says
what happened either way ("Pinned Dummy to Home"). A page's pin waits, greyed, until deadwax has said
what is pinned, so it never shows an album as unpinned that is pinned; when deadwax can't keep pins
at all, it stays greyed and a tap says why. The ••• menu leaves the pin out for an album Navidrome
says has no MusicBrainz release id, or while deadwax can't keep pins, and the ••• button says "pin"
in its name only when the menu has it.

**Edit**, at the right of the Pinned heading, turns the cards into a list. Each row has **up** and
**down** buttons, an **✕** to unpin it, and a grip at its right end to drag it by (only the grip
drags, so the page still scrolls under your finger anywhere else). Each change is saved as you make
it. Edit sends deadwax the list as you saw it along with the change, so something pinned on another
device since your Home last asked keeps its place rather than being unpinned unseen. If deadwax
can't keep a change, the list goes back and **Not saved** and why is said under the list (never
above it, so no row moves under your finger) until your next change, or until Home asks deadwax
again. After a move, the keyboard (or VoiceOver) stays on the button you used, in the row's new
place; after an unpin, on the next row's **✕**. **Done** goes back to the cards.

**What a pin follows.** An album is pinned by deadwax's own record of it in your library - the same
one that knows you already have an album when you Get it - so it keeps opening the album after you
re-file it, apply another release to it, or merge a disc folder into it in the main page's editor.
An album pinned before deadwax has looked at your library is pinned by its MusicBrainz release, and
moves onto that record as soon as deadwax has one. An artist is pinned by their MusicBrainz id, and
their card opens their page by it (so it still opens after their albums are re-filed under a new
name), or - when nobody can say one - by their name and Navidrome's id for them. Names pinned that
way that differ only in how they were typed (accents, case, which dash) are one pin: "Björk" and
"Bjork" show as pinned on both pages. A card can say why it won't open, in two lines under its title:

- **Removed from the store** - the album was deleted in deadwax (from the main page). If you get it
  again, the pin opens the new copy.
- **Not on disk just now** - its folder isn't where deadwax last saw it: usually a share that isn't
  mounted. It comes back once the folder is back and deadwax has looked at your library again (the
  main page's library tab scans as it opens; **Rescan** scans at once).
- **Not in Navidrome yet** - deadwax has it, but Navidrome doesn't (yet): it may still be scanning.

**Where they're kept.** On deadwax, for you - not on the phone, and **never as stars in Navidrome**
(stars belong to each Navidrome user and mean something else there). With logins off (the default)
there is one user, so every device sees the same pins; with [logins](#signing-in) on, each person has
their own, and the first admin to sign in takes over the ones pinned before. They're in deadwax's
database (`DB_PATH`), in its `pins` table, through `GET` and `PUT /deadwax/me/pins` and
`POST /deadwax/me/pins/toggle`. Home holds up to 50.
## Looking after deadwax from a phone

Since 2.0.0-player.47 a phone has every page a desktop has for looking after deadwax - in any window
narrower than 1024 pixels, so an iPad held upright too. They're for an admin, which with logins off is
everyone:

- **Editing an album**: an album's page has **Edit** at the top, beside the pin. It opens **Edit album**
  as a sheet over the whole screen - the same five tabs as a desktop's panel, **Release**, **Tags**,
  **Artwork**, **Lyrics** and **Delete**, the main page's own editors laid out for a phone (fields big
  enough that iOS doesn't zoom into them, **Apply** kept at the foot of the sheet, in reach above the
  home indicator, as you scroll the preview). It finds the album's folder, follows the album to its new
  id after you apply another release and goes back from a deleted album exactly as on a desktop -
  [the library guide](library.md#editing-an-album-in-the-app) has all of it. Ticking a run of tracks
  with Shift is a keyboard's; tick each one. The page behind waits while the sheet is open. The close
  button closes it - a tap on the dimmed page beside it doesn't (it shows there on a phone on its side
  or an iPad), so a stray one can't throw away an edit you've half made; inside the tag editor, a track or the delete confirmation, their own **Cancel**,
  **Tracks** or **Close** goes back one step. Turn an iPad (or widen the window) past 1024 pixels with
  the sheet open and it becomes the desktop's panel beside the page - and a sheet again the other way.
- **You → Managing deadwax**: **Albums that need a look** (with how many) opens **Needs a look** - the
  albums whose tags, folder or cover want attention and the ones deadwax filed that you haven't looked
  at, with a chip per kind of issue. Tap one and the Edit sheet opens on it, saying where it is in the
  list (*1 of 17*), with **◁**, **skip ▷** and, after **Apply**, **Next album ▷** to work through them
  ([the library guide](library.md#needs-a-look-in-the-app)). **Library care** has **Rescan** and the runs
  that fetch covers, CD art and lyrics, each with its **Stop** ([the library guide](library.md#library-care-in-the-app)).
  **Server settings** is the server half of the main page's settings tab - three tabs, every change a
  draft until **Save changes** in the bar along the bottom, above the tab bar and the player
  ([configuration](configuration.md#in-the-app)). **Log** is deadwax's event log, newest first, each line's
  time, level and where it came from over its words; it follows deadwax live while the page shows, and
  lets go while the now-playing screen is over it or you're elsewhere
  ([troubleshooting](troubleshooting.md#the-apps-log-is-missing-lines-says-the-stream-was-lost-or-starts-empty)).
- **Setting Navidrome up from a phone**: on a first run, Home, the Library and Search say **Connect
  Navidrome**, with **Set up Navidrome**: it opens **Server settings** at **Connections**. Fill in
  `NAVIDROME_URL`, `NAVIDROME_USER` and `NAVIDROME_PASSWORD`, **Save changes**, and the app asks
  Navidrome again by itself - your library shows without a reload. Changing them later, on a setup that
  works, asks again too, leaving the pages you have open as they are while it does; if the new settings
  don't reach Navidrome, those pages say so.

## On a desktop

Open `/player/` in a window **1024 pixels wide or more** - a computer's browser, or an iPad on its
side - and the same app is laid out for a desktop (since 2.0.0-player.19). It's the same app, not
a second one: the same pages, the same addresses (a link or a bookmark opens the same thing at
either size), the same settings. Make the window narrower than 1024 and it's the phone's layout
again - and the other way round - without the music stopping: only what's around the pages
changes. (You's **Now Playing opens as** and **Pause winds the record down** are the phone layout's
own: there's no now-playing screen on a desktop, so they change nothing there.)

- **A sidebar** down the left instead of the tab bar: **deadwax**, the **search field**, **Home**
  and **Requests** (with the count of what's arriving, as the tab has), the Library's views -
  **Recently added**, **Albums**, **Artists** and **Songs** (Songs left out when Navidrome won't list
  songs, as on a phone; with logins on, the Library's three are yours and a **Browse** group under
  them has the store's Albums, Artists and Songs - [the player as you](#the-player-as-you-with-logins-on))
  - then **Managing**: **Needs a look**, with how many albums need one, the
  library's review queue in the app, an album folder Navidrome doesn't list among them (**Not in
  Navidrome**; [the library guide](library.md#needs-a-look-in-the-app) has it),
  **Library care** - **Rescan** and the runs that fetch covers, CD art and lyrics for the albums
  missing them ([the library guide](library.md#library-care-in-the-app)) - **Settings**, the server's settings - the main page's settings tab's server half, its three pages
  and its one save ([Configuration](configuration.md#in-the-app) has it) - and **Log**,
  deadwax's event log: the last 500 lines since it started, then new ones as they come, while the page
  shows ([troubleshooting](troubleshooting.md#the-apps-log-is-missing-lines-says-the-stream-was-lost-or-starts-empty)),
  and **Open the main page**, which opens the main page in a new tab (a desktop needs nothing that is
  only there now: an album is edited from its own page, below, the bulk runs are **Library care**'s, and
  an artist's pictures and **Move albums to …** are on the artist's page, [above](#managing-an-artist)), and
  **You** at the foot. Where you are is highlighted. Home, Requests and You work as the phone's tabs
  do: a click shows it as you left it, and a click on the one showing goes back to its first page
  (and, there, to the top). So does the Library view showing. Another Library view shows that view -
  where you left it when you were already on the Library's first page, and at its top from anywhere
  else.
- **The search field** is Search's box: type in it and Search's results show in the main area - one list,
  Top results as tiles three across (two across beside a side panel), then Artists, Albums and Songs, yours first in each, with the chips under
  the large title (since 2.0.0-player.55) - and Enter asks at once. It keeps saying what you searched
  for while an album you found is open. (Search's own box isn't drawn on a desktop.)
- **Recently added** in the sidebar is Navidrome's albums newest first, a view of its own beside
  **Albums**, so Albums keeps the order you chose for it (Recently added, Recently played, Artist or
  Title, from the button at the title's right). It's the desktop's alone: a phone shows the albums
  there, and doesn't remember it.
- **The Library's albums and Home's Recently added** are a grid, six covers across - fewer while a
  panel is a column beside them (from 1280 pixels wide), so a cover stays a cover's size. Home's
  **Arriving** cards sit side by side.
- **A player bar** along the bottom instead of the mini player: the song's cover, title and "Artist
  — Album" (click that to go to the album), previous, a round play/pause and next, the scrubber with
  the time gone and the time left at its ends (click or drag along it; its dot shows when you point
  at it), and at the right **AirPlay** when there's a speaker to send to, **Info**, and the
  [visualizer](#the-visualizer)'s button (five bars) - and before them, wherever the speed isn't 1x,
  [the speed's chip](#the-speed-fader) (`1.25x`; click it for 1x). With nothing playing it stays,
  saying so.
  There's no now-playing screen and no [turntable](#the-turntable) on a desktop - the bar is the
  player, and the visualizer is the desktop's full-screen view of it.
- **Info** opens beside the page as a panel, with the same About and Debug as on a phone. **Done**,
  the Info button again, or Escape while you're in the panel closes it. Going to an album or an
  artist from the player - the bar's "Artist — Album", or Info's own cards - closes it too when it
  lies over the page (between 1024 and 1279 pixels wide); as a column beside the page it stays.
- **An album** has its cover beside its title, **Play**, **Shuffle** and **Edit** in a row, and its
  songs in a list as on a phone. Between 1024 and 1279 pixels wide, while a panel lies over the page,
  the row moves under the cover, so the panel - the Edit panel included - leaves it in view.
- **Edit** (since 2.0.0-player.21, for an admin - everyone, with logins off) opens the **Edit album**
  panel beside the page, and shows pressed while it's open: underline tabs for **Release** (the main
  page's metadata editor: pick the pressing, read the preview, **Apply**), **Tags** (the album's
  tracks with tick boxes, and the tag editor for the ticked ones - a track's name opens what's inside
  it: every field, the pictures in the file, its lyrics and all its tags, with **Previous**, **Next**
  and **Edit this track…**, since 2.0.0-player.44), **Artwork** (**Get cover**, **Get CD art**, the
  cover and CD art opening full size), **Lyrics** (**Get lyrics**) and **Delete**. They're the main page's own editors, so they
  work as [the library guide](library.md#editing-an-album-in-the-app) says - which also says how the
  panel finds the album's folder, and what happens after an edit: the page asks Navidrome again,
  and after you apply a different release it follows the album to the new id Navidrome gives it.
  The panel closes when you go to another page; the close button, Edit again, or Escape while
  you're in the panel closes it too (in the tag editor, inside a track or the delete confirmation,
  Escape closes that first, back to the track or to its tab).
- **The album you don't have** has its cover beside its title, then **Get the album** with the
  **Pressing** button beside it, what you already have of that pressing under them, and the
  tracklist as a table - #, Title, Length - with an **Against the usual tracklist** column whenever
  any pressing of the album differs (the bonus track, the other version, the renamed one, each
  marked there with a short note: "only on this pressing", "usually 3:58"). A title or note too long
  for its column ends in "…" - point at it to read it whole. From 1280 pixels wide **Get the album**
  and **Pressing** sit beside the cover, under the title; narrower, they sit under the cover, so the
  Sources panel (which lies over the page there) leaves them in view - with it open they keep to the
  part of the page it doesn't cover, **Pressing** dropping under **Get the album** with its label
  shortened where there isn't room beside it. **Get the album** opens the **Sources**
  panel beside the page, and shows pressed while the panel shows that pressing's sources: click it
  again to close them.
- **The Sources panel** is the same cards as on a phone - the score, the folder and who it's from,
  then Speed first, Tracks, Quality, Size and Starts in a row, and the score's parts as chips, always
  showing - with **Search again** under them, and **Lossless**, **24-bit**,
  **Free slot**, **Signals**, **Complete albums only**, a sample-rate floor (any, 44.1, 48, 88.2 or
  96 kHz and up, by the folder's worst file - since 2.0.0-player.50) and the sort. **Signals** sets
  the least each part of the match score
  may be - **Titles**, **Count**, **Lengths**, **Edition**, **Format** and **Peer**, a slider each -
  as the main page's candidates panel does, and its chip counts how many are set. Signals and the
  sample-rate floor are the panel's alone: narrow the window to a phone's with the panel open and
  they stop filtering (neither
  chip is drawn on a phone), until it's wide again. The page stays usable beside the panel:
  **choose another pressing and the sources are searched again for it**, keeping the filters you set
  and never picking one for you (even with **Pick the best source for me**) - and go back and open
  the same album again with the panel still open, and they're searched for the pressing it shows. A
  card's **Get** queues it and shows Requests, as on a phone. The close button, or Escape while
  you're in the panel, closes it.
- **Where the panel goes**: from 1280 pixels wide it's a third column and the page makes room for
  it; between 1024 and 1279 it lies over the right of the page, which there isn't room to share. One
  panel shows at a time: opening Info puts the sources away, and Get puts Info away - and an album's
  **Edit** puts either away, as they put the Edit panel away.
- **The look** is the desktop's version of the same style: smaller labels and headings, a darker
  page and cards, and Explorer-style highlights in the sidebar and the pressing list.
- **On a touch screen** in this layout - an iPad on its side - every control is a finger's size
  (44 points): the player bar is a little taller, with its buttons above the scrubber, and the
  sidebar's items, the tracklist's rows, the chips and the buttons grow to match.

### The visualizer

Since 2.0.0-player.20 the desktop layout has a full-screen visualizer: the music drawn as it plays,
in place of the phone's turntable. Click the **five bars** at the right end of the player bar. It
takes the whole screen (or, where the browser won't allow that, the whole window), and **Leave full
screen**, **Escape**, or leaving full screen any other way closes it, back to where you were. The
music carries on throughout - the visualizer only watches it.

- **Effects**: **Bars** (the spectrum as bars, the lows in the middle, with falling peaks and a
  reflection), **Scope** (the waveform as a glowing line, its last half-second hanging behind it),
  **Halo** (a ring of spectrum spokes round the album's record - its CD art turning, when deadwax has
  some, or a black record with the cover as its label) and **Ambient**.
- **Ambient** is a family of styles, chosen from the **Style** list beside the effects: **Mandala** (a
  kaleidoscope whose mirrors swing and whose shapes morph through polygons, lattices, flowers and
  circles - one figure in the middle of the screen with dark room round it, in the cover's colours;
  when its number of mirrors changes - doubling, tripling, halving or going to a third - a new mirror
  swings shut inside every wedge at once, or swings open, so every wedge stays like every other and
  no single line is left for shapes to appear out of; its tiles carry on from one cell into the next
  rather than being cut off along a straight edge), **Waves** (ridges of the spectrum flying towards
  you, the heading drifting as if you were flying over them), **Liquid** (ink curling in water), and
  the **Media Player style** five, after Windows Media Player's: **Burst**, **Ribbons**, **Smoke**,
  **Rings** and **Embers**. **Rotate all** goes through all eight in that order - each for 30 seconds
  of playing (a pause doesn't count), fading from one into the next, starting on the Mandala when the
  visualizer opens on it, or, chosen while another style shows, carrying on from that one - and
  nothing about it is random.
  The Mandala, Waves and Liquid shift and flow with the music rather than flashing on the beat; the
  Media Player five answer it as Media Player's did (Rings strikes a ring on each kick). Under the
  **Style** button it says how it hears the music - **feel: smooth**, **in between** or
  **aggressive**, and the tempo it has found - and, with Rotate all, which style is showing (on a
  window 1280 pixels wide or more). The feel comes from how busy the music is (its onsets, counted 60
  times a second on a screen drawing 60 frames a second or more), how much of it is above about 2 kHz, and how
  noisy it is (distorted guitars and cymbals are noisy, pianos and pads are tonal), each followed over
  a few seconds; the last two are measured against the loudest part of the sound, so how loud a record
  was mastered hardly matters (a very quiet one can read a little smoother, a very loud one a little
  more aggressive). Calm music reads smooth, music with distorted guitars and cymbals aggressive, and
  funk and other grooving music mostly in between; a sparse, clean guitar piece can read smooth, and a
  heavy track with little top end, or with few, sparse beats, in between - and a song that builds
  moves across as it builds. Below 60 frames a second it reads the music less often and misses some of
  its onsets: at 30, which a battery saver can bring (Chrome's Energy Saver halves a page's frame rate),
  about a third of them, and heavy music can then read in between and grooving music smooth.
- **The music shapes it**: the Mandala follows the feel - aggressive music (metal, say) brings sharp,
  spiky, fast-twisting figures held tighter in the middle; smooth music rounder, slower, wider,
  flowing ones, changing as a song changes - and the tempo sets how fast every style moves.
- **Colour**: **From the cover** takes its colours from the playing album's cover (a black-and-white
  cover gives grey); **Purple** is deadwax's own.
- **The controls** - the song at the top left, the effect, style, colour and Leave full screen at the
  top right, and play/pause at the foot - fade out after a few seconds while the music plays and you
  don't move the pointer, and come back when you move it, click or tap anywhere, or press a key (a
  click or tap that brings them back does only that - it never presses a control that was hidden
  under it). They stay while it's paused. **Space** plays and pauses (holding it down doesn't keep
  toggling), **V** goes to the next effect (**Shift+V** the one before), and **Escape** leaves. The
  **Style** list opens on the style chosen; the arrow keys, Home and End move through it, Enter picks
  one, and Escape closes it. On a touch screen - an iPad on its side - every control is a finger's
  size.
- **Kept on this computer**: the effect, the colour and the Ambient style you chose, as the player's
  other settings are (Ambient, From the cover and the Mandala until you choose).

**What it listens to.** The visualizer never touches the song you hear. It fetches its own copy of
the stretch that's playing - the same FLAC stretch deadwax cuts for the turntable's sound - decodes
it, and plays it silently, at volume zero, in time with the song, to measure it. So the song plays
exactly as it always does, and nothing of the copy is ever heard. The next song's first stretch is
fetched in the last few seconds of the one before, so one song flows into the next without the
visualizer standing still (one you skip to, or jump to, can be still for a moment). It all works
over a plain `http://` address. At [another speed](#the-speed-fader) the copy plays at that speed too
(since 2.0.0-player.39), so it stays in time with the song, and a song at 2x reads twice the tempo.

What that copy costs while the visualizer shows: 40 seconds of the song fetched for every 32 played,
and one stretch of each next song. deadwax cuts each stretch from the copy of the song that
[the player's cache](configuration.md#paths) keeps where there is one (the MP4 Safari plays, or the
gapless stream's - a Mac's Safari, the gapless stream and a resampled hi-res song have it made
already), which costs Navidrome nothing but a quick check of which file it has. A browser that plays
the FLAC as it is - Chrome, Firefox or Edge with Gapless off, the default - has no such copy, and
since 2.0.0-player.23 deadwax reads each stretch straight out of the FLAC on Navidrome instead: the
start and the last few hundred bytes of the file once a song, then about the stretch's own size (a
little more while it finds its place in a long song with no seek table) - never the whole song, and
nothing made or kept in the cache, so the visualizer doesn't push anyone's songs out of it. (Until then the
first stretch of each song had deadwax fetch the whole song again and keep a copy of it in the cache.)
The stretch is the same, byte for byte, either way - the song's own audio, untouched.

**"This song can't be seen".** Only FLAC songs have that copy, and a song the visualizer can't hear
runs the effects from a calm, slow idle pattern instead, with a plain note at the bottom right
saying why (a long one wraps in its corner): the song isn't a FLAC file; deadwax couldn't send its
sound just now (it tries again after ten seconds); this browser couldn't read its sound; or this
browser can't analyse sound at all.
[Troubleshooting](troubleshooting.md#the-visualizer-doesnt-move-with-the-music-or-says-a-song-cant-be-seen)
has what to do.

**Without WebGL** - a browser that doesn't have it, or has it turned off - Ambient shows a simpler
version (soft drifting colours), and a line at the bottom right says so; the other three effects
don't need it. **With Reduce Motion on** (your system's accessibility setting), everything moves slowly and
calmly, and nothing jumps with the beat.

## The turntable

The now-playing screen has a second look, made for the phone: the song on a record turning on a
turntable. **The button at its top right** switches between the two, for as long as the screen
stays open - a round record on the cover, a square (the cover) on the turntable. Which one it
opens as is **Now Playing opens as**, in **You** under **Playback**: **Cover**, the default, or
**Turntable**. Like the others there, it's kept on that device. The button never changes the
setting: close the screen and open it again, and it's back to what You says.

Since 2.0.0-player.14 the record has **momentum** and **its own sound**: flick it and it keeps
turning; the sound follows your hand, faster and slower and backwards; and pausing from the turntable
winds the sound down with the record. The two come together: where the record can't make its sound
(below), turning it works as it did before, silently and with no momentum. All of it is described
below.

- **The record's face is the album's CD art**: the `disc.jpg` (or `.png`) that the main page's
  **Get CD art** saves beside the tracks - see [the library](library.md#covers-cd-art-and-lyrics).
  For a set, it's the playing song's disc's own (`disc2.jpg` for a song on disc 2), or, where the
  disc has none of its own, a `disc.jpg` that stands for every disc. With no CD art, it's a plain
  black record with the album's cover as its label. A `cd.jpg` that came with a download isn't
  used: it's whatever its sharer scanned, and Get CD art is still offered beside it.
- **Finding it**: the phone only knows Navidrome's name for the album, so deadwax asks Navidrome
  which MusicBrainz release the album is (Navidrome reads that from the files), and finds the
  folder filed as that release. So an album with no release id in its tags - an untagged rip -
  always gets the plain record; match a release in the metadata editor first, as Get CD art needs
  anyway. CD art saved while the turntable is showing appears the next time the now-playing screen
  opens (or when you switch to the cover and back); a picture replaced by hand can take up to five
  minutes to change, as the phone keeps one that long. [Troubleshooting](troubleshooting.md#the-turntable-shows-a-plain-black-record-not-the-albums-cd-art)
  goes through why it might show the plain record.
- **The record turns at 33⅓ rpm** while the song plays. Press play and the platter spins up over
  about 0.4 seconds; pause and it slows to a stop over about a second, as a real deck's does (the
  song itself starts and stops as it always has). Those are the figures at 1x: with [the speed
  fader](#the-speed-fader) set elsewhere the record turns at that speed instead - 50 rpm at 1.5x - and
  takes longer or shorter to get there and to stop. It doesn't turn while the now-playing screen is
  closed, the phone is locked or the app is in the background, so nothing is drawn for nobody.
  With **Reduce Motion** on (the iPhone's Settings → Accessibility → Motion), it doesn't turn at
  all.
- **The arm moves in from the edge of the record towards the middle** as the song plays, so where
  it is says how far through the song you are. The line under the song's name says the time:
  "2:31 of 7:05".
- **Tap the record** to pause, or to play. A pause from the record winds its sound down with it
  (see **Pause winds the record down** below).
- **Turn the record** to move through the song: a whole turn is 1.8 seconds, as a real record at
  33⅓ turns, and turning it back goes back. While you turn, the time line says **Scrubbing** and
  where the record is.
  - **With its sound**: take hold of the record and the song pauses under your finger; turn it and
    you hear it, faster or slower as your hand goes, backwards when you turn it back, and nothing
    while your finger rests. Turn it at the record's own speed at 1x - a turn every 1.8 seconds - and you
    hear the song as it plays (a turn of your hand is always 1.8 seconds of the song, so with the speed
    fader at 2x, where the record turns every 0.9 seconds, a turn every 1.8 seconds plays it at half
    the speed it was playing) (since 2.0.0-player.24; before, it warbled out of all recognition - see
    below). A press that stays put for a moment takes hold too, and a quick tap is
    still a tap. A turn that starts the moment your finger lands is heard from that moment (since
    2.0.0-player.40): the record isn't taken until your finger has gone a few pixels - it might yet be
    a tap - but once it has, it is taken from where it was as your finger went down, and its sound
    follows every touch since, so those few pixels no longer add to the delay (before, they added about
    35 ms with your hand at the record's own speed, 70 at half of it and 95 at a quarter). It can reach
    back only about a tenth of a second, though, counted from when the page hears your finger move: a
    start slow enough to still be inside those pixels by then is heard from a tenth of a second before
    the record is taken, not from the press - the slower your hand, the more of the old delay it keeps,
    and a browser that passes touches on late leaves less room (measured in headless Chrome over HTTPS,
    which passed them on about 30 ms late, a start at a quarter of the record's speed was heard about
    60 ms sooner than before, not 95). A playing song still plays on under those few pixels, and pauses
    as the record is taken. Let go and the record carries on at the speed your hand gave it - the speed it had as
    your finger last moved, not slowed by the moment between that and lifting it, and from where it
    was then, so its sound carries straight on without a stall. If the song was
    playing, the motor brings the platter back to its own speed - a backwards flick is stopped
    about as quickly as a forward one is slowed (under a second for a hard one), then the platter
    spins back up - and the song carries on from there, the record's own sound handing over to it.
    If the song was paused, the record coasts to a stop under its own weight (a hard flick coasts
    for a second or two) and the song stays paused where it stopped. Either way the song is moved as
    you let go, to where the record will end up, so it's ready when the record gets there. A coast
    back past the start stops at the start; one past the end stops just short of it, and the song
    ends from there.
  - **While it coasts back to speed**, the song is still meant to be playing: tap **Next** or
    **Previous** and the next song plays; switch to the cover and the song plays on from where the
    record was going. Drag the arm, or tap Previous to start the song again, and the record goes
    quiet - the song plays from wherever that put it once the platter is back at speed. Tap play
    while a paused record coasts, or while a pause winds down, and the song starts from where the
    record had got to - what you heard - not from where it was going to stop.
  - **Before its sound has started**: the record's sound can only start from a tap - a tap on the
    record, the play/pause or skip buttons, or the button that switches to the turntable (and, once
    it has started before, tapping the mini player to open the screen). It stops whenever the screen
    closes or the phone locks. And it needs the stretch of the song where the record is (below) to
    have arrived - a moment after that first tap while the song plays; for a paused song, the first
    press asks for it. Until then (since 2.0.0-player.16 - before, a turn could pause the song and
    play nothing), turning the record works as it did before 2.0.0-player.14: silently, the song
    playing on while you hold it (the record itself stops turning under your finger), moved on or
    back by as much as you turned it when you let go, and no momentum. Letting go of the record
    counts as a tap, so the next turn has its sound once its stretch is in. A record still coasting
    from a flick is the exception: the flick paused the song already, so you catch it as ever, even
    where its next stretch hasn't arrived yet - silent until it does.
  - **The sound** comes from FLAC songs only - a stretch of about 40 seconds of the song round
    where it's playing (less for a hi-res song played as it is), which deadwax cuts from the very copy
    of the song the phone plays - for a hi-res song under **Maximum quality**'s **Up to 48 kHz**, the
    48 kHz copy, so the record sounds just as loud as the song - and sends as a small FLAC file of its
    own while the turntable shows and the song plays, once a tap has started the sound. An iPhone has
    asked for that copy already, to play the song; a phone that plays the FLAC as it is gets its
    stretches read straight out of the FLAC (since 2.0.0-player.23 - nothing made or kept), and a
    resampled song has its copy made the first time. That
    costs about a third more data than the song itself while the turntable shows and the song plays
    (about half as much again for a hi-res song played as it is, whose stretches are shorter), and
    nothing at all on the cover, or before the first tap. An MP3 or any other kind of file turns as
    before 2.0.0-player.14: silently, and with no momentum.
  - **It's about an eighth of a second behind your hand**, always the same: the record's sound
    follows every touch your phone reports, each at the moment it was made, and plays the path they
    trace 120 ms later - and 1.5 ms more since 2.0.0-player.35, for the limiter below. Over plain
    `http://`, where the sound is made on the page's main thread, it is later by two of the blocks it is
    made in: about 143 ms in all where the computer's audio says it works 512 frames or fewer at a time
    (Chrome on a Mac), and about 164 ms where it works more at a time, or can't say - Safari, on a Mac
    and on every iPhone, whose browsers all report the same 128 frames whatever the hardware does
    - since 2.0.0-player.40, which made the blocks half as long where the audio allows it; it was about
    165 everywhere before. That is late enough that the touches either side of each moment have
    arrived, so it never has to guess where your hand is going. What your device's own audio adds after
    that - a Bluetooth headset's 150-250 ms included, which no page can shorten - is on top, and Info >
    Debug's **Turntable timing** says what the browser knows of it. Each touch's place and speed are worked out from the touches
    around it, before and after, and the speed is smoothed, so a finger's own jitter stays out of the
    pitch whether your hand is steady or speeding up, slowing down or turning back. The coasts, the
    motor's run back to speed and the wind-down are timed the same smooth way, and are as far behind
    too; the song itself, and where it's moved to when you let go, are just as before. A busy moment
    that loses a few of your touches doesn't stop the sound.
    Since 2.0.0-player.29 a slowed or sped-up record is the song and nothing else: the sound between
    the song's own samples is worked out through a proper filter, where the short curve used before
    left a thin, fizzy copy of the high notes on top of a slowed song and folded them back over a
    sped-up one.
    Since 2.0.0-player.35 it **never clips**. On a loud song the record's sound went over full scale
    on the drum hits - working out the sound between the song's own samples brings back the peaks the
    song has between them, and the sound's filter for the deepest bass adds to them - and the browser
    cut off whatever was over. A recording from James's own Mac (Info > Debug > **Record 20 s**,
    below) showed it on his song: 144 samples at full scale, in 15 short bursts - about one a second,
    on the loudest drum hits - at every speed, 1x included. In the recording's slowed stretches, the
    only ones where a sound the song can't make can be told from the song, it was the only such sound;
    whether it is the "digital sound" he hears is for his ears to say. The sound now ends in a
    limiter: it looks 1.5 ms ahead, turns the sound down smoothly - never a step, and both channels
    alike - just enough to keep every sample half a decibel under full scale, holds that for 20 ms and comes back up over a few tenths of a second. Where
    nothing comes near full scale it changes nothing at all, not one bit; on a loud song it turns the
    loudest moments down by a decibel or so - **Turntable timing** in Info > Debug says how many peaks
    it has held and the deepest it went.
    (2.0.0-player.24 played 50 ms behind and read each touch's speed from the newest edge of a short
    curve whenever your hand's speed was changing - which carried the jitter straight into the pitch:
    a fast flutter, "like a dragonfly sound on top of the music". 2.0.0-player.27 traded 70 ms more
    delay for a steady pitch; if the record now feels late under your finger, say so - the two pull
    against each other.)
    Taking hold of a playing record, or pausing it with a
    wind-down, plays the song's last eighth of a second again as the record's sound starts; and
    letting go of a playing record at about its own speed - when the song plays on straight from your
    hand - skips that eighth: the record's sound stops as you let go, that much behind, and the song
    starts from where your hand let go. All of that holds from the very first turn: while the turntable
    shows with its sound on, deadwax keeps reading the phone's audio clock - ten times a second, even
    with the record standing still - so the first grab of a paused record after you open the screen, or
    come back to the app, is timed as smoothly as any other, and nothing it learns mid-turn moves the
    timing until you let go.
  - **Over plain `http://` too** (since 2.0.0-player.16): a browser gives the part that best plays
    this sound - an AudioWorklet, on an audio thread of its own - only to a page on HTTPS (or on the
    computer itself, `localhost`). Opened at a plain `http://` address on your network, deadwax plays
    the record's sound on the page's main thread instead, with the very same code, so it sounds the
    same - only a few hundredths of a second later (about 0.143 s behind your hand in all where the
    computer's audio works in 512 frames or fewer at a time, about 0.164 s elsewhere, where it's about
    0.12 s - 121.5 ms - on HTTPS); on HTTPS it gets its own thread, which is steadier if the page is
    busy. Its blocks are 512 frames long only where the browser says its audio renders that few at a
    time (since 2.0.0-player.40 - Chrome and other browsers built on it say it truly; Safari, and every
    browser on an iPhone, always says 128, so there they stay 1024), and deadwax goes back to 1024 - at the record's next silent moment,
    for the rest of the visit - if they then come two at a time all the same, or if the page once
    doesn't finish one in time while the record's sound is heard: a block of 512 has half the time a
    block of 1024 has, and a late one plays a moment of the sound twice. From the first tap
    that starts the sound until the turntable goes (switched back to the cover), deadwax also tells an
    iPhone that the page plays music, so the ringer switch on silent doesn't mute the record's sound (while you turn it the song itself is paused, and iOS would
    otherwise treat the record's sound as the kind the switch silences - not yet checked on a phone).
    [Info → Debug](#info--debug)'s **Turntable sound** row says whether it's ready, and if not, why,
    and which of the two plays it.
    It never touches the song's own playback: what you hear when the record is at its own speed is
    the song, exactly as it always was.
- **Pause winds the record down**, a checkbox in **You** under **Playback**, beside **Now Playing
  opens as**: on (the default), pausing from the turntable - a tap on the record, or the pause button
  while the turntable shows - slows the song's sound to a stop with the record over about a second
  at 1x (from 2x about 1.25 s, from 0.25x about 0.55 s - it winds down from the song's own speed),
  and the song stays paused where the sound stopped (tap play before it has, and the song starts
  from where the sound had got to). Off, the sound stops at once (the record
  still spins down). It's only ever the turntable's: the cover's pause, the lock screen's and a song
  ending are always instant. Kept on the device, like the others.
- **Drag the arm** to jump anywhere in the song: to the middle of the record is the end, to its
  edge the start. It starts to move once your finger has gone a few pixels, from where the song
  is, so a small wobble moves nothing. The song jumps when you let go; while you hold the arm, the
  time line says **Needle up** and the time letting go will go to - even while the record is still
  coasting from a flick, which goes quiet as you take the arm (the arm then moves on from where the
  record was going to land).
- **From the keyboard, and with VoiceOver**, the arm is a slider like the scrubber (arrows move 5
  seconds, Page Up and Page Down 30, Home and End to the ends), and the record is a button that
  says whether a tap pauses or plays.
- **Everything else is the same as on the cover**: previous, play/pause and next - except that on
  the turntable they also start the record's sound, its pause winds the record down as a tap on the
  record does, and its play starts from where a coasting record has got to - and the row of buttons
  under them, but for the speed's chip: [the speed fader](#the-speed-fader)'s readout, at the
  plinth's corner, says the speed here (on a phone on its side, where the readout is too small to
  read, the chip shows too). The screen still closes only by a drag down from its top row, the
  arrow, or Escape: a drag on the record or the arm never closes it. A note that a song was skipped or
  couldn't be played sits over the foot of the turntable, so the record and the arm never move or
  change size when it comes and goes; the speed fader's readout, in that corner, stays drawn on top
  of it.
- **On a phone on its side** the turntable is small (there's no landscape layout yet); the arm's
  handle shrinks with it rather than covering the record.
- **With Reduce Motion on**, a flick still lands where its momentum says - the record jumps there
  rather than coasting, and a playing song plays on from there at once - and pausing doesn't wind
  down. Turning the record still has its sound.

There's no hint on how to use it: the record and the arm are the instructions.

## The speed fader

Since 2.0.0-player.39 the song can play from **a quarter of its speed to twice it**, and **its pitch
moves with it** - a record deck's pitch control, not a time-stretch: faster is higher, slower is lower;
2x is an octave up, 0.5x an octave down. It's the player's speed, not the turntable's, but it's set on
the turntable.

- **The fader** stands at the right of the platter, as on a deck: **up is faster**, 0.25x at the
  bottom, 2x at the top. It goes by octaves - 0.25x, 0.5x, 1x and 2x evenly spaced - so 1x is two
  thirds of the way up, where a line is drawn across the slot; the line lights green while the speed
  is exactly 1x. Under it, at the plinth's corner, **the readout** says the speed - `1.00x`, `1.25x` -
  in purple whenever it isn't 1x. The fader's touch area stops short of the record, so a touch on the
  record's edge beside it is still the record's.
- **Drag the knob** and the speed changes as your finger moves, as a pitch fader's does. Nothing
  happens until your finger has gone a few pixels, and it then moves on from where the speed was, so a
  touch never jumps it. A drag that ends within 2% of 1x lands on exactly 1x. **Tap the readout** to
  go straight back to exactly 1x.
- **From the keyboard, and with VoiceOver**, it's a vertical slider called Speed: the arrows move it by
  0.01, Page Up and Page Down by 0.1, **Home** to 0.25x and **End** to 2x; VoiceOver reads it as
  "1.25 times", or "normal speed". The arrows step past the 1x snap, so 1.01x is one press from 1x.
- **It stays where you left it**, as a deck's pitch fader does: for every song after, kept on the device
  like the settings in You, through Gapless's stream and its second player, a song asked for again
  after it dropped, AirPlay, and a reload of the app. The lock screen's scrubber moves at the speed.
- **Off 1x, a chip says so on the now-playing screen's cover and on a desktop** - `1.25x` - at the
  left end of the row of buttons under the cover's transport, and in the [desktop's player
  bar](#on-a-desktop), before AirPlay, Info and the visualizer. **Tap it** and the speed is back to
  1x. So a speed set on a phone is never left playing unseen on a desktop, or an iPad turned on its
  side. Nothing moves when it comes and goes. On a phone on its side, where the turntable is too small
  to read its readout, the chip shows on the turntable too. **The mini player above the tabs doesn't
  show the speed**: open the now-playing screen to see it.
- **The turntable follows the speed.** The platter turns at it (50 rpm at 1.5x); taking hold of a
  playing record starts its sound at it; let go, and the motor brings the record back to it - the
  same motor, so from still it takes 0.4 seconds to reach 1x and 0.8 to reach 2x; and a pause from the
  turntable winds down from it, a little longer from 2x (about 1.25 s) and shorter from 0.25x (about
  0.55 s). Turning the record by hand is the same as ever: 1.8 seconds of the song a turn.
- **At 1x nothing about playback changes.** deadwax touches none of the browser's playback settings
  there: the setting that keeps the pitch the same at another speed is switched off only while the
  speed isn't 1x, because Chrome resamples the song whenever it's off, even at 1x, where with it on 1x
  is a straight copy. (Safari plays 1x the same way either way.)
- **What browsers do with it.** Chrome and Edge play every speed from 0.0625x to 16x, so all of this.
  Firefox mutes the sound outside 1/8x to 8x, so none of this. On an iPhone and in Safari, Apple's
  player plays any song from 1x to 2x, and below 1x a song it says it can play slowly - which hasn't
  been tried on an iPhone yet. [Info → Debug](#info--debug)'s **Speed** row says what the browser
  does: the speed, whether the pitch moves with it, anything it refused, and how fast the song really
  moved over the last few seconds of playing - so a browser that isn't playing the speed it was given
  shows there.
- **Plays are still counted by what you hear of the song**: a song counts once you've heard half of it
  (or four minutes), whatever the speed - at 2x that comes in half the time.
- **The [visualizer](#the-visualizer)** watches its silent copy at the same speed, so a song at 2x shows
  twice the tempo.

## Testing the turntable

The turntable has a **test bench** (2.0.0-player.36): a page of its own where you turn the real
turntable - the same record, the same momentum and the same sound your phone runs, nothing re-made for
the page - over simple signals the page makes itself, and hear what it played beside an ideal
turntable turned exactly the same way. It is there for the question "is that digital sound deadwax's,
or is it what turning a record at those speeds sounds like?".

**Getting there**: on the now-playing screen, **•••** > **Info** > **Debug**, and **Open the test
bench** on the **Test bench** row, under **The turntable** - it opens in a tab of its own beside the
app, so the song playing carries on. Or type the address: `/player/lab/` after deadwax's own (for
example `http://192.168.1.10:8080/player/lab/`). It works on a phone and on a desktop, over plain
`http://` as well as `https://`. Nothing it does is saved on the server or touches the library.

**The turntable**, at the top: turn it with a finger or the mouse as in the app, tap it to play or
pause, and use the arm. Its label carries a mark, so you can see it turn. **Play** plays the test song (and **Pause** winds the record down when **Pause
winds the record down** is ticked, as in the app); **Start the sound** starts the record's sound
without playing anything. Under them it says where the record's sound runs: **on its own audio
thread** over `https://` or on `localhost`, **on the main thread** over plain `http://` (a phone or a
browser only gives a page the audio thread when it is secure) - the same as the app does.

**The song** is one of these, made at 44.1 kHz (a CD rip), 48 kHz or 96 kHz (a hi-res song), two
minutes long, 12 dB under full scale unless it says otherwise:

- **Sine 440 Hz** - the reference: turned at any steady speed it must sound like one pure tone.
- **Sine 1 kHz** - where a wobble in the speed is easiest to hear. **Sine 100 Hz** (low) and **Sine 5
  kHz** (high).
- **Two sines, 440 + 660 Hz** - a fifth: two lines that must stay two lines.
- **Square**, **Sawtooth** and **Triangle 220 Hz** - each with nothing above the song's own top.
- **Chord** (A major) - something like an organ.
- **Tone bursts** (1 kHz, 50 ms on, 450 off) - starts and stops, and silence between.
- **Clicks**, one every half second - a slowed record makes thumps, a sped-up one ticks.
- **Sweep 50 Hz to 10 kHz** over the two minutes - where you are is the pitch you hear.
- **Pink noise**, 20 dB under full scale RMS - broadband. **Silence** - anything you hear while
  turning it is the bench's or deadwax's own.
- **Sine 440 Hz at full scale** - so the record's limiter has something to do.
- **Square 220 Hz, aliased on purpose** - a reference only, never deadwax's: a square made the cheap
  way, its aliases in the song itself - so it sounds harsh and out of tune with itself, and turned
  faster or slower they move with the speed, like everything else in it.
- **Your own file** - any file the browser can play, its first two minutes.
- **A song from your library** - a song from Navidrome, the whole of it, played exactly as the app
  plays it: see below.

**A song from your library** (2.0.0-player.37) puts music you know on the bench. Choose it, and a
search box appears: type a song, an artist or an album - `eye in the sky`, say, for The Alan Parsons
Project's "Eye in the Sky" - and tap the song among what Navidrome finds. Each shows its artist and
album, its length and its format as Info shows it ("FLAC, 16-bit, 44.1 kHz, stereo"). That song is
then the bench's song, the whole of it, its length as Navidrome has it, and the record's label is its
album's cover where Navidrome has one. It plays exactly as the app plays it - its own stream, asked for as the app asks for it
(inside an MP4 in Safari and on an iPhone, resampled under **Up to 48 kHz** for a hi-res song, as
Navidrome's MP3 for a file the browser can't play), and the record's sound comes from deadwax's own
windows of it - the same path the app's turntable takes, so what you hear on the bench is what you
hear in the app. Changing between a song from your library and the bench's own signals starts the
record's sound afresh, so press **Play** or **Start the sound** after it (the bench says so). The last
song you picked is offered again the next time the page opens on this device - **Use it again** - as
long as Navidrome still has it; one it no longer has is forgotten. A song that isn't a FLAC plays, and
its record is silent, as in the app, and the bench says why ("it isn't a FLAC file"); a song that
won't load says so. If Navidrome isn't set up or isn't answering, the bench says so in one line, and
its own signals still work. The song can't be changed while anything records, a motion runs or the
check runs - the search is faded then.

**Turn it for me** turns the record for you, through the very steps a finger's turn goes through, 60
times a second, with none of a hand's unevenness: **Steady 1x**, **0.5x**, **0.25x**, **2x**,
**Backwards 1x**, **1x with a slow wobble** (10% either way, 1.3 times a second, like a hand
drifting), **A slow ramp** (0.25x up to 2x and back over 8 s) and **A scratch** (back and forth,
twice a second). They work on a song from your library too. Tick **With a finger's jitter** to add a real finger's unevenness. While one runs -
from the tap, while it gets the record ready too - the record can't be grabbed and **Play** is faded
and does nothing (the song and the record's sound would play together); **Stop the motion** stops it once it
turns. A motion starts where the record is, if it
fits there, or 20 seconds in; a file too short for one says how long it needs.

**Record, and compare**: **Record 10 s** records what the record's sound plays while you turn it -
starting the sound first, if it hasn't started; **Record the next motion** records the next of **Turn
it for me**. The song can't be changed while it records, and a recording the page was hidden through
(the screen locked, another app or tab) is thrown away - the record's sound stops with the page. A
moment later you get three versions of the same movement, level-matched on what you can hear (above
20 Hz: B and C keep the rumble below that which deadwax's own sound filters out, and counting it would
play them quieter than A):

- **A - deadwax**: what the record's sound played.
- **B - ideal, deadwax's path**: the song read perfectly from its definition along exactly the path
  deadwax's own sound followed, keeping only what a perfect turntable could send out at that speed:
  nothing at or past half the sound's sample rate - a perfect cut-off, which a sped-up record reaches
  sooner, so a square wave played fast loses its top harmonics in B, as it has to in A. Pink noise, the aliased
  square, your own file and a song from your library, which are samples rather than a formula, are
  read between their samples by a long, near-perfect interpolator - far cleaner than deadwax's, but a
  filter all the same. B also has neither of the two things deadwax's sound does after reading the song:
  the filter that takes out everything under 10 Hz or so (so B keeps a slowed record's deepest rumble, and
  the offset of a record held still - nothing you can hear) and the limiter that keeps the loudest peaks
  under full scale. What is in A and not in B is how deadwax reads the song, and those two.
- **C - ideal, smooth path**: the song read the same perfect way along a smooth path through your
  movement (for a motion, the motion's own exact path), with no limits a live sound has. It never jumps: where your
  hand lets go, rests or sets off again, or misses a few samples, the path carries straight on, its
  speed eased from one to the next. What is in A and not in C is everything deadwax adds while it
  follows your hand live.

Press **Play the comparison** and switch with the buttons (or the arrow keys among them) or the keys
**1**, **2** and **3** - the switch goes to the same moment of the recording, through a moment's
silence that is the same whichever you switch to, so the switch itself tells you nothing - and
**Space** plays or pauses. The keys work anywhere on the page once there is a comparison, except
while you type in a field, or with another button focused (Space presses that button). Under them, a spectrogram of each (time across, pitch up; a stray line shows as a
line that shouldn't be there) and the numbers:

- **Read head off the smooth path**: how far deadwax's sound strayed from the smooth path, in
  milliseconds of the song - the most, and typically.
- **Speed wobble above 20 Hz**: how much the speed flutters, as a share of the speed - for deadwax's
  path and for the smooth one. A flutter like that is heard as a warble or a buzz on a tone.
- **What isn't the signal (A against B)**: for a tone, how loud the sound in A is that the perfect
  reading hasn't got, against the tone, and the loudest single such sound and its pitch. Lower is
  cleaner; 60 dB or more down is hard to hear on a tone.
- **The replay**: how closely playing the recording back through deadwax's sound here reproduces it -
  what B and C are built on - and how far its read head was from where the sound said it was. Often
  it is the recording to the bit. But it can't know exactly when each step of a movement reached the
  sound - least of all on the main thread - so where the speed changes it may be up to a tenth of a
  millisecond of the song off (the replay then reads -18 to -90 dB rather than far below): far too
  little to hear, or to move the numbers above.

If it says **Record it again**, none of the numbers above is shown, only the replay's, and the line
under it says why:

- **The replay didn't follow this recording**: something held the page up while it played (on the
  main thread the record's sound is played between everything else the page does), the sound slowed
  where the movement didn't, and B isn't deadwax's path. That is a stall of the page, not of the way
  deadwax reads the song: record it again.
- **Nothing took the record while it recorded**: you pressed **Record 10 s** and didn't turn the
  record, or a turn was already under way when you pressed it (only a turn that starts after it
  counts: let go, and take it again). Nothing is compared then - it says so under the Record
  buttons.
- **The record's sound said nothing of where it was after the record was taken**: the recording ended
  just after you took it. Record again, and keep turning while it records.

**What it means**: if A and C sound alike to you, what you hear is what turning a record at those
speeds sounds like - nothing to fix. If C is clean and A isn't, deadwax adds it, and the numbers say
which part: A against B is how the sound reads the song, B against C the path it follows.

**On a song from your library**, B and C read the song itself: once the recording is done, the bench
asks deadwax again for the windows of the song that cover where the record went - cut from the same
copy the record's sound plays from - and reads them the near-perfect way (the record's own windows,
which the replay needs, usually come straight from the browser's cache). Never the whole song: only
those windows, at most four of them (about 160 seconds of a CD-quality song, 52 of a hi-res one played
as it is - more than ten seconds of ordinary turning goes over). Past that, or if deadwax doesn't send a
window, there is no B or C that time - A plays alone, with no blind test - and the comparison says
why; the numbers that need only the paths - how far the read head strayed, the speed's wobble, the
replay - are still there. **What isn't the signal** isn't measured on music: music
has something at nearly every pitch, so there is nowhere for it to show. Listen instead: if A and C
sound alike, the "digital" sound you hear when scrubbing that song is what scrubbing it at those speeds
sounds like; if C is clean and A isn't, deadwax adds it - and since the record's sound on the bench is
the app's own path, the same is true in the app.

**Blind**: to check your ears without knowing which is which, choose two of A, B and C and **Start the
blind test**: each trial plays the two and an X that is one of them at random, and you say which. At
the end it says how many you got and how likely that score is by guessing - under 5% means you can
hear the difference.

**Check this device** runs, on the 1 kHz and 440 Hz sines, Steady 1x, 0.5x, 2x, Backwards 1x and the
slow wobble, recording each (about a minute and a half), and lists for each which sound path ran, how
far its clock moves at a time, how many of its blocks were late (on the main thread - on its own audio
thread it says **None (an AudioWorklet)**, which counts none), how many of the page's frames came late
while it turned (the page held up), the speed's wobble and the sound that isn't the signal - or
**Record it again** in their place, with why, on a run whose replay didn't hold - it needs a tone, so
it always runs on the bench's own sines: with a song from your library chosen, it changes the song to
them and asks you to tap **Carry on** to start the record's sound. **Play** is faded
and does nothing while it runs. **Keep
the page in view and the screen awake while it runs** (on an iPhone, Auto-Lock locks it after 30
seconds or a minute untouched): a hidden page stops the record's sound, so a run the page was hidden
through is thrown away, and the check waits for you to tap **Carry on** to run it again. **Save
results** gives you one file of all of it - the browser, whether the page was secure, every number and
every recording - to send with a report; a check that stopped part way (**Stop the check**, or a run
that failed) gives one too, of the runs it finished, marked incomplete with why. It is the way to get
numbers off an iPhone over plain `http://`.

**The record's sound, live** draws the record's sound as it plays, so a stray line can be seen as
well as heard; it moves only while the record sounds. And **How the sound is running** at the foot
of the page shows Info > Debug's two turntable rows.

## Gapless playback (experimental)

Between two songs there's normally a short pause, about a second on an iPhone over a VPN: when
one song ends, the phone has to ask deadwax for the next one and start it from nothing. **Gapless**, a checkbox in **You** under **Playback**, closes that gap. It's **off** by default.
It's kept on the device, and a home-screen app keeps its settings apart from Safari's, so turn it
on in the app itself. (Until 2.0.0-player.10 it was a switch on the now-playing screen, beside the
album's name; it keeps the setting it had there.)

With it on, the player works one of two ways, song by song: FLAC songs played one after another
go into **one stream**, and everything else is got ready on a **second player**.

### One stream, for FLAC

FLAC songs played one after another are joined end to end into one continuous stream on a single
audio player, the way a CD plays: there's nothing to start between two songs, so there's nothing
to hear. Each song is joined on the exact sample where the one before it ends, which is what an
album mixed straight through (a live album, a DJ mix) needs.

deadwax repackages each song for this, as the same FLAC audio in a fragmented MP4, with no
re-encoding, and keeps it in the player's cache beside Safari's MP4s. The player fetches it in
pieces of a few seconds, keeping about 30 seconds ahead of what you're hearing.

- **Where it works**: Safari on an iPhone, an iPad or a Mac, and Chromium browsers (Chrome, Arc,
  Edge). A browser that can't do it uses the second player for every song.
- **A stream starts from a tap**: **Play** or **Shuffle** on an album, tapping a song, or **Next**
  and **Previous**, in the app or on the lock screen. A song that starts by itself after one
  played the other way goes the other way too, and the next tap starts a stream again. A new
  stream has to open and fetch before iOS lets a page that isn't playing go to sleep, so it waits
  for you.
- **The songs have to match**: FLAC, one or two channels, 16 or 24 bits, and all of one format, from
  files of one sample rate. Hi-res songs join too: resampled to 48 kHz under
  [Maximum quality](#maximum-quality-hi-res-at-48-khz)'s default, or as they are under "Original".
  The stream ends before a song that isn't FLAC (an MP3, an Opus file), a song with more than two
  channels, or a song from a file of another sample rate than the ones before it (a 96 kHz song
  after 192 kHz ones, even though both come out at 48 kHz). That song plays from the second player,
  with the usual short change, and the stream picks up again at your next tap.
- **Next, Previous and the scrubber** move inside the stream when the song is in it. As the stream
  crosses into a song, the lock screen shows that song's title, cover and its own position, and
  plays are counted song by song as usual.
- **AirPlay**: a stream can't go to an AirPlay speaker, because Safari only allows one with AirPlay
  turned off. The AirPlay button still works: tapping it takes the song you're hearing out of the
  stream, carrying on from where it was, and opens the list of speakers. On a Mac, tap it a second
  time for the list. While the sound is on an AirPlay speaker, no stream starts.
- **When something goes wrong, the music carries on.** If the stream can't go on (deadwax won't
  repackage a song, the connection drops for longer than the stream holds, the browser can't play
  what it was sent), the song you're hearing carries on the other way from where it had got to. It
  comes as the FLAC file as it is, so in Safari a seek in that one song can land a little off (see
  [Seeking](#seeking-and-where-safari-lands)). A resampled song carries on resampled instead, at the
  same level, in an MP4 deadwax makes at once from the stream's copy. A later song that can't be had just ends the stream
  before it, and plays from the second player at its turn: the song you're hearing isn't cut
  short. Three failures in a row with no stream getting as far as playing in between, or
  deadwax's cache being unusable, turn streaming off for 10 minutes; the second player is used
  meanwhile.
- **The first time a song is played** deadwax downloads it from Navidrome whole and repackages it
  before sending anything, which is quick on the same machine. If nothing has come after about 25
  seconds, the song plays the other way.
- **It needs room in the player's cache**, as Safari's MP4s do: see
  [`PLAYER_CACHE_MB`](configuration.md#paths). A song too big for what the cache's disk has free
  plays the other way, and the songs around it still stream.

### The second player, for everything else

For songs the stream doesn't take, and in browsers without it, the next song is got ready on a
second audio player while this one plays. This was the only way before 1.1.0-player.5. It still
leaves a short gap (the second player has to start), just a shorter one.

- **The next song is got ready while this one plays.** A few seconds into each song, the player
  downloads the whole of the next one into the phone's memory and loads it into the second player,
  which is kept silent. When the song ends, the second player starts straight away and the two
  swap places, so the next song is ready in turn. **Next** uses the ready song too.
- **Memory is capped.** Files up to 64 MB are downloaded ahead, which covers about ten minutes of
  CD-quality FLAC. Bigger files (most hi-res FLAC) and transcoded songs aren't downloaded ahead:
  the second player is given the song's address and buffers what Safari lets it.
- **Not on AirPlay.** While the sound is going to an AirPlay speaker nothing is got ready, and
  every song change goes the ordinary way. Once AirPlay stops, the next song is got ready again.
- **The music doesn't stop because of it.** If the next song can't be handed over when this one
  ends (nothing got ready, a song that wouldn't load, AirPlay in use, or iOS refusing to start the
  second player), that change goes the ordinary way, exactly as with Gapless off. A song that
  won't play from memory is asked for from Navidrome straight away. The usual rules for songs
  that won't play still apply after that: one more try, then skip.
- **A download that hasn't finished is streamed instead.** If this song ends before the next one
  has finished downloading (a short song, a slow connection), the download is dropped and the
  second player streams the song from its address, which takes as long as the ordinary way.
- **It uses more data.** Each next song is downloaded in full, even if you skip it. **On a slow
  connection** it can use more still and not help at all: when a whole song can't download while
  the one before plays, every download is dropped part-way and the song streamed afresh, so part
  of every song is sent twice, for a change no quicker than with Gapless off. If
  [Info → Debug](#info--debug)'s **Gap** row keeps saying `download unfinished`, turn Gapless off.

**Turning Gapless off** takes effect at once: the song you're hearing carries on alone, from
where it was, and anything got ready is let go of.

### Info → Debug

How the song you're hearing was sent, and how the last song changes and your last seek went, are
in **Info**: tap **•••** on the now-playing screen, then **Info**, then **Debug**. (Info opens on
the tab you last left it on, scrolled to the top.) Until 2.0.0-player.10 the gap and seek parts
were two lines on the now-playing screen, between the cover and the song's title; they moved here
so that screen shows the song, and they say the same things as labelled rows. The **Gap** and
**Last seek** rows keep the old lines' words, less their openings (`Last song change`,
`Last seek:`), and the older changes are on an *Earlier* line. The end of the old seek line, how
the song was sent (`· FLAC in MP4, 192 kHz resampled to 48 kHz`), is now the **Sent as** row, with
the resampling on a **Resampled** row of its own. Debug has five parts:

| part | row | what it says |
| --- | --- | --- |
| The file | **Format** | the file as Navidrome read it: `FLAC, 24-bit, 192 kHz, stereo`. A part Navidrome didn't give is left out |
| What this device is sent | **Sent as** | how the song comes: `FLAC in MP4, 16-bit, 44.1 kHz`, `In one stream, 24-bit, 48 kHz`, `FLAC, as the file is`, `MP3, transcoded by Navidrome`. [Seeking](#seeking-and-where-safari-lands) says what the MP4s are for |
| | **Resampled** | `192 kHz to 48 kHz, 3 dB quieter` when deadwax resampled the song for [Maximum quality](#maximum-quality-hi-res-at-48-khz), `Not known yet` while it hasn't said, otherwise `No` |
| | **Why** | why it came that way: `Maximum quality: Up to 48 kHz`, `48 kHz and below is never resampled`, `Only FLAC is resampled`, `Maximum quality: Original`, and so on |
| | **Gapless** | `Off`, `On`, or `On, in one stream` while this song is playing in [the stream](#one-stream-for-flac) |
| | **Speed** | [the speed](#the-speed-fader) (since 2.0.0-player.39): `Normal (1.00x) - the song as it is, nothing changed`, `1.25x, the pitch moving with it`, or what the browser did instead - `but the browser is holding the pitch`, `the browser refused it - …` in its own words, `the browser plays it at 1.00x`. Under it, once the song has played a few seconds, how fast it really moved: `The song moved at 1.24x over the last few seconds of playing` (lower than the speed across a moment it waited for the network; begun again from a change of speed). The row keeps up while Debug is open - a change of speed, from the desktop's player bar beside it, shows at once, and the measure as it comes and moves |
| Last song change and seek | **Gap** | the last song change: how long it took and how it was made (below), with up to four before it on an *Earlier* line |
| | **Last seek** | where your last seek went: see [Seeking](#seeking-and-where-safari-lands) |
| The turntable | **Turntable sound** | whether [the turntable](#the-turntable)'s own sound is ready: `Ready: 0:42-1:22, FLAC, decoded at 48 kHz` (the stretch of the song it holds), or off and why (below), with which part plays it (its own audio thread, or the page's main thread and why), how far the phone's audio clock moves at a time, and what its stretches have cost since the turntable showed and when the last of them came (`6.8 MB fetched since the turntable showed, the last window 1:01 in` - divide one by the other for a rate) |
| The turntable | **Turntable timing** | how the turntable is keeping up on this phone, counted since it last showed (2.0.0-player.28): `The song was back 1.24 s after the last let-go - 0.40 s of it the record's run back to speed`, and under it whether the sound - when it is made on the page's main thread - had gaps (`12 of 3400 blocks late, the worst by 38 ms`), how the picture kept up under your finger (`310 frames, 4 late, the longest gap 118 ms`), any let-go after which the song didn't start, and any time the browser interrupted the sound - and, since 2.0.0-player.35, how many peaks the record's sound held under full scale and the deepest it turned the sound down to do it (`Peaks held under full scale: 36 since it showed (65 samples), the deepest 1.4 dB`: each of those went past half a decibel under full scale and was turned down; on a loud song about a third of them went over full scale too, where the browser would have cut them off - counted up to a quarter of a second or so after you let go, once the sound, an eighth of a second behind your hand, has caught up, coasts included) - and, since 2.0.0-player.40, how far behind your hand the record's sound is by design and what this device's own audio says it adds after that (`The record's sound: 142.8 ms behind the hand by design (blocks of 512 on the main thread), then what this device's audio adds - it says base 2.7 ms, output 8.0 ms, 12.3 ms from render to speaker`: the browser's own figures, each only where it gives them - the output figures include a Bluetooth headset's delay where the browser knows it, and an older Safari may give only the first). The blocks-late count works in Chrome since 2.0.0-player.40 too: until then it compared the audio clock with a time Chrome makes from that same clock, and could never count one. If the turntable feels like it hangs, these numbers say where |
| The turntable | **Recording** | a 20-second recording of the record's own sound, as a file to send with a bug report (2.0.0-player.32). **Record 20 s** starts it (the turntable showing, and its sound started - turn the record once first); close Info and turn the record as you would; when the row says `20 s recorded`, **Save the recording** downloads one JSON file (about 5 MB for 20 s) holding what the record's sound actually played on your device, every touch as it came, and what the sound made of it - exactly what's needed to hear and replay a sound no lab has reproduced; since 2.0.0-player.35 it also holds each moment's loudest sample as it was before the file's 16 bits cut it off, so it shows how far over anything went. Nothing is sent anywhere by itself |
| The turntable | **Test bench** | a link, **Open the test bench**, that opens the turntable's test bench at `/player/lab/` in a tab of its own beside the app, so the song playing carries on (2.0.0-player.36) - see [Testing the turntable](#testing-the-turntable) |
| Navidrome sent | **Song**, **On other songs**, **Album** | the names of the fields Navidrome sent for the song and for its album, without their values; those it sent empty on an *Empty* line; and the fields other songs of the album carry that this one doesn't |

The **Gap** row is timed with Gapless off as well, the same way, so you can compare the two.

A change is timed from the moment one song ended to the moment the next one's **sound started**:
when the player's clock for the new song is first seen moving. It isn't timed to the moment the
browser says the song is playing, because Safari says that as soon as it's asked to play a song
it has data for, before any sound comes out. A second player that claims to be ready but has lost
what it buffered would read as a few milliseconds that way; timed on the clock, it reads as the
silence it really is.

| it says | meaning |
| --- | --- |
| `in one stream` | the stream crossed from one song into the next. 0 ms when the next song's audio was already there; otherwise how long the stream waited for it |
| `one element` | Gapless is off: the ordinary way |
| `handed over, from memory` | the second player started a song held in memory |
| `handed over, streamed` | the second player started a song it had buffered from its address |
| `handed over, streamed (download unfinished)` | the next song hadn't finished downloading, so the second player streamed it instead |
| `…, had to load` | the second player didn't have enough of the song to start at once, so it loaded first: iOS may have thrown away what it had buffered |
| `…, failed before playing` | the new song failed before it made a sound, and the time includes asking for it again (or skipping it) |
| `one element (airplay)` | Gapless is on but the change went the ordinary way; also `nothing ready`, `failed to get ready`, `another song ready`, `refused` |

While the song is playing in a stream, **Sent as** starts `In one stream` and **Gapless** says `On,
in one stream`. A hi-res song resampled for Maximum quality reads `In one stream, 24-bit, 48 kHz`
(or `FLAC in MP4, 24-bit, 48 kHz` when it played the other way), with **Resampled** saying `192 kHz
to 48 kHz, 3 dB quieter`; one streamed as it is under "Original" reads `In one stream, 24-bit,
192 kHz`. deadwax resamples the whole song before it sends any of it, which takes a few seconds on a
NAS, and until the start of the song has arrived nothing on the phone can say what deadwax did: then
**Sent as** reads just `In one stream` (or `Asked for FLAC in MP4`), **Resampled** `Not known yet`
and **Why** `Asked for resampled; deadwax hasn't answered yet`. They fill in by themselves while
Info is open.

Only songs ending by themselves are timed, and only when the next one went straight to sound.
Changes you make yourself (**Next**, **Previous**, a new song, moving the scrubber, pressing play)
aren't timed, and neither is a change where the music stopped: a pause, iOS stopping for a call or
Siri, iOS refusing to start the next song, or a song that wouldn't play at the end of the queue.
Anything longer than 30 seconds isn't counted either. If it says Gapless isn't helping,
[troubleshooting](troubleshooting.md#with-gapless-on-theres-still-a-pause-between-songs-or-the-player-reloads-by-itself)
says what each answer means.

**Turntable sound** says what your phone made of the record's own sound - which only your phone can
say, since an iPhone decodes it its own way. Whenever it says **Off**, a press on the record works as
it did before 2.0.0-player.14: silently, the song playing on under your finger.

| it says | meaning |
| --- | --- |
| `Ready: 0:42-1:22, FLAC, decoded at 48 kHz` | the stretch of the song the record can play, and the rate your phone decoded it at. A press there has the record's sound |
| `Off: the turntable isn't showing` | the now-playing screen is on the cover, or closed |
| `Off: waiting for a tap to start the sound` | the sound can only start from a tap: tap the record, a transport button or the look button. Nothing is fetched for it before the first one |
| `Off: still starting - …` | the part that plays it hasn't begun yet |
| `Off: it isn't a FLAC file (it is MP3)` | only FLAC songs have the record's sound |
| `Off: this browser couldn't decode its window - …` | your phone refused the stretch deadwax sent, in its own words: tell us what it says |
| `Off: this browser has neither an AudioWorklet nor a ScriptProcessorNode to play it` (or `no Web Audio`) | the browser can't play it at all |
| `Off: the sound couldn't start - …` (or `the sound's ScriptProcessorNode couldn't be made - …`) | the browser's own reason |
| `Off: deadwax didn't send it - …` | deadwax couldn't make the stretch just then; it asks again after ten seconds |
| `Off: deadwax said that is past the end of the song` | the phone asked for a stretch beyond the file's end (the song's length as Navidrome gave it is longer than the file); it asks again after ten seconds |
| `Off: its window is loading - …` | the stretch is on its way |
| `Off: no window yet - …` | the song is paused and the record hasn't been pressed: nothing is fetched until it plays, or until the record is pressed |

The line under it says which part plays the sound (since 2.0.0-player.16): `On its own audio thread
(an AudioWorklet)`, or `On the main thread - this page isn't on HTTPS, so the browser has no
AudioWorklet` when deadwax is opened at a plain `http://` address (or `… the AudioWorklet wouldn't
load (…)`, in the browser's words, when it refused it) - then, once it has seen it move (since
2.0.0-player.24), how far the phone's audio clock moves at a time, `Its clock moves 21.3 ms at a time`
(the audio's own render: about 21 ms on an iPhone, 6 on a desktop browser; deadwax times the record's
sound smoothly across those steps) - then what its stretches have cost.

**Navidrome sent** is there to check what your Navidrome really sends before later parts of the app
rely on it: the field names only, such as `discTitles` on an album or `musicBrainzId`, `playCount`
and `played` on a song, as Navidrome's answer had them. A name alone can mislead both ways, so two
things more are said:

- **Some fields Navidrome always sends, empty when the files have nothing for them**:
  `musicBrainzId` as `""` on a song or an album with no MusicBrainz id tag (deadwax writes the
  album's, not each recording's), `discTitles` as `[]`, `bpm` as `0`, and `bitDepth` as `0` for a
  lossy file. Those are on the row's *Empty* line, not listed as if they held something. A name on
  the main line has a value.
- **Other fields Navidrome leaves out whenever they are zero or never set**: `playCount` and
  `played` on a song nobody has played, and on a song `starred`, `userRating`, `year`, `track` and
  `discNumber`. So a missing name doesn't mean Navidrome can't send it. **On other songs** lists
  the fields other songs of the same album carry and this one doesn't, which is where `playCount`
  shows up for a song never played when one beside it has been.

What it shows is the album's answer as it was when you opened the album's page and played from it,
so a song you've played since still has no `playCount` there: go back, open the album again, play
from it, and look again. It says *Not known* when the player doesn't have the album the song was played from.

### What still needs trying on a real iPhone

The stream is built on the recipe a test page proved on an iPhone first: seamless in Safari and in
Arc, with the screen locked, fetching over the network while locked. deadwax's own player has been
checked in a desktop browser (Chromium): recorded as it played, the joins came out to the sample,
the lock screen followed each song, and seeks, Next and Previous landed where they should. The
second player's song changes took about 98 ms there against about 145 ms with Gapless off, and
94 and 96 ms on an iPhone. To try the stream on the phone:

1. Tick **Gapless** in You and play an album of CD-quality FLAC from a tap, with the screen on.
   Info → Debug's Gap row should say `0 ms, in one stream`, and you shouldn't hear the joins.
2. **Lock the phone** and let at least ten songs change by themselves. The lock screen should show
   each song's title and its own position as it comes. Unlock and open Info → Debug: the Gap row
   shows the last change, and up to four before it on its *Earlier* line.
3. From the app and from the lock screen, try **Next**, **Previous** and the scrubber, and seek
   back to near the start of a song that played a few minutes ago.
4. Try **AirPlay** while a stream plays: the song should carry on and the list of speakers open.
5. Play an album with an MP3, or a song of another sample rate, in the middle. The stream should
   end before it, that song play from the second player, and a tap start a stream again after it.
6. Pause for a minute or two and carry on, from the app and from the lock screen. After a long
   pause on the lock screen, iOS may not let play work until you open the app; that isn't the
   stream (see [troubleshooting](troubleshooting.md#after-a-long-pause-play-on-the-lock-screen-does-nothing-until-the-app-is-opened)).
7. Play a 24/192 album whose tracks run into each other, from a tap, with
   [Maximum quality](#maximum-quality-hi-res-at-48-khz) at **Up to 48 kHz**. The first song may
   take a few seconds to start (that's deadwax resampling it). After that Info → Debug should read
   `In one stream, 24-bit, 48 kHz` for Sent as and `192 kHz to 48 kHz, 3 dB quieter` for
   Resampled, the song changes `in one stream`, and you shouldn't hear the joins, locked or not.
   Then switch to **Original** and start the album again from a tap (a stream that is playing
   carries on with the setting it began with): Sent as reads `In one stream, 24-bit, 192 kHz`.
   Listen for the music stalling on a weaker connection, and match the volume before comparing,
   since resampled songs are 3 dB quieter.

## Maximum quality: hi-res at 48 kHz

**Maximum quality** is in **You**, under **Playback**, with two choices. (Before 2.0.0-player.9 it
was behind a gear beside the Library title.) Like Gapless above it, it's kept on the device.

- **Up to 48 kHz** (the default): FLAC songs at 88.2, 96, 176.4, 192, 352.8 or 384 kHz, 16 or 24
  bits, are resampled by deadwax to 48 kHz (44.1 kHz for the 88.2 kHz family) and sent as lossless
  24-bit FLAC. They then join the gapless stream like any CD-quality album, which a 24/192 album
  couldn't before. Every other song is sent exactly as before, bit for bit.
- **Original**: songs above 48 kHz are sent as they are. With Gapless on, FLAC ones join
  the stream too, as they are. An iPhone can only hold about 5 MB of a stream at a time, which is
  8 seconds or so of 24/192, so the stream runs only 4 or 5 seconds ahead of you: a weak connection
  can make these songs stall where 48 kHz ones wouldn't.

**Why 48 kHz loses nothing you can hear on an iPhone.** Apple says an iPhone plays at most 24-bit/48
kHz, and that anything higher needs an external DAC. Its speaker, AirPods (which get lossy AAC over
Bluetooth anyway), Apple's Lightning and USB-C headphone adapters, and AirPlay all run at 44.1 or 48
kHz, so the phone converts a 192 kHz song down itself before you hear it, whatever deadwax sends.
The only question is which conversion you get:

- deadwax's uses libsoxr's highest-quality setting. It is flat to within 0.01 dB up to 22.2 kHz
  (20.4 kHz for 44.1 kHz), changes 20 kHz by less than 0.0000001 dB, adds no delay and keeps the
  phase. It keeps 24 bits (the rounding is 144 dB below full scale) and aliasing at least 184 dB
  down. Measured against two independent references, it matches to the last bit.
- iOS's own conversion of a 96 kHz file was measured rolling off 3.5 to 4.5 dB near 20 kHz (on
  older iOS versions; nothing newer has been measured).

What 48 kHz does remove is everything above about 22 kHz, where human hearing stops (in the
best-known study, a 24 kHz tone was heard only at 88 dB or louder, and nothing above 26 kHz at all).
The one place 192 kHz might reach your ears is a USB DAC running at the song's own rate. Whether
Safari on an iPhone ever asks for that isn't known (WebKit never asks the phone for a sample rate),
so "Original" stays, if you have one to try it with.

**Resampled songs are 3 dB quieter.** Taking out the ultrasonics can push a loud master's peaks
past full scale. Measured on masters clipped hard when they were made, it was up to 2.9 dB over.
So every resampled song is lowered by the same 3 dB. That leaves room so nothing clips, and because
every song of an album gets the same gain, the joins stay exact. It's a change of level only, the
same as a notch down on the volume. Turn it up, and when you compare "Up to 48 kHz" with "Original",
match their levels first, or the louder one will sound better. A master that still goes over is
lowered further, by exactly enough, and deadwax's log says so. Its joins with the songs beside it
then step in level by that much.

**The joins stay exact.** Resampling a song on its own treats the silence either side of it as part
of the music, which puts a click at every join of an album whose tracks run into each other. So
deadwax resamples each song with the edges of its neighbours on the album, on one sample grid for
the whole album. The songs then fit together exactly as if the whole album had been resampled at
once. It finds the album and its order from Navidrome. If a neighbour can't be read just then, that
join may not be exact and deadwax's log says so. For the next ten minutes every play of that song
is that same copy (so a song already playing never changes under you, and a neighbour that keeps
failing costs one wait, not one at every song change); a play after that tries again.

**The first play of a hi-res song takes longer.** deadwax downloads the song from Navidrome and
resamples it before sending anything. A 7-minute 24/192 song takes about 2.5 seconds on an M2 Mac,
and a NAS will be several times slower. In a stream, the next song is got ready about a minute
ahead, so only the first song you tap waits, and the stream gives it up to a minute before playing
it the other way. With Gapless off, or while AirPlaying, the player asks deadwax for the
next song's copy a few seconds into each song. Once made, a song is kept in the player's cache (see
[`PLAYER_CACHE_MB`](configuration.md#paths)), and plays at once from then on.

**Changing the setting** takes effect from the next song started or got ready. A stream that is
playing carries on as it began.

## Seeking, and where Safari lands

The scrubber seeks where you let go, and shows that time until the player has got there, however
long that takes over a slow connection. Where the music then comes in is up to the browser.

**In a FLAC file, Safari doesn't land where it was asked to.** To seek in a FLAC a player has to
find the moment in the file, and a second of a quiet passage takes far fewer bytes than a second
of a loud one. Safari's engine (on a Mac, and every browser on an iPhone or iPad, which all use it)
estimates from the part of the file it has already read, and in a song whose loudness changes it
lands off, while its clock says the time you asked for. Measured on a Mac with that engine:

| test song | where seeks landed |
| --- | --- |
| steady loudness | within a third of a second |
| loudness moving like a song's (quiet intro, verses and choruses) | 1 to 14 seconds out |
| a quiet first minute, then loud | up to 50 seconds out, and up to 159 over a slow connection |

On an iPhone it landed 3 and 8 seconds out. A **seek table** in the file made no difference. Chrome
and other Chromium browsers (Arc and Edge included) land exactly where asked every time.

**So Safari gets FLAC songs inside an MP4.** An MP4 file carries a table of where every piece of
the audio is, and Safari's engine seeks by that table exactly. When the player is running in
Safari, it asks deadwax for each FLAC song inside an MP4, and deadwax repackages it: **the very same
FLAC audio, bit for bit, in a different container**. Nothing is transcoded and nothing is lost, and
the files in your library aren't touched. Measured the same way, through deadwax: every seek into
the MP4 landed within a hundredth of a second, where the same song as FLAC landed up to 40 seconds
out. Other browsers get the FLAC as it is, as before.

- **The first time a song plays, it starts a moment later.** deadwax has to fetch the whole file
  from Navidrome and repackage it before it can send the first byte: under a quarter of a second
  for a four-minute CD-quality song where it was measured, and probably a little longer on a NAS.
  After that the song is kept, so playing it again and seeking in it don't wait.
- **Skipping doesn't wait.** Skip past songs before they start and deadwax stops making the ones
  you skipped, and stops fetching them from Navidrome, so the song you land on starts as soon as it
  would have on its own.
- **Where it's kept**: in a folder of deadwax's own, `deadwax-player`. Nothing needs setting up:
  by default it's in the container's temporary space, which is emptied when the container is
  recreated, and that only means the next first play of each song waits that moment again. To keep
  it, or to put it on a fast disk (an SSD), set
  [`PLAYER_CACHE_PATH`](configuration.md#paths) to a folder you've mounted. Nothing goes in your
  config folder. It holds up to [`PLAYER_CACHE_MB`](configuration.md#paths) of songs, 1 GB unless
  you set it, the songs played longest ago making room for new ones; while a song is being made,
  its download sits beside it, so the folder briefly holds one song more than that. It's only a
  cache, and deleting it is always safe.
- **When the disk runs short**, older songs are cleared to make room, and deadwax leaves some space
  free for everything else on that disk. If there still isn't room, or the folder can't be used at
  all (say the container can't write anywhere), the song is sent as FLAC. It plays exactly as
  before; only its seeks can land off. deadwax's log says why.
- **Some FLACs are sent as they are**: a file over 512 MB (an hour-long album ripped as one file,
  or long hi-res), or one deadwax can't repackage with certainty (cut short, say, or with something
  after the audio it can't account for). It plays exactly as before, and seeks in Safari can land
  off. deadwax's log says which song and why.
- **Only FLAC.** Anything else is sent as it is. AAC and ALAC, in an `.m4a` file, already come in an
  MP4 with its table, so Safari seeks them exactly. **An MP3 lands exactly only if it's constant
  bit rate.** A variable-bit-rate MP3 (LAME's V0 or V2, which is most MP3s in most libraries) can
  land seconds off in Safari, just as a FLAC did, and deadwax doesn't repackage it. Measured on a
  Mac with Safari's engine, on a test song whose loudness swings far more than most music's: a
  constant 320 kbps MP3 landed within a hundredth of a second on every seek, and a V2 copy of the
  same song from a fraction of a second to 41 seconds out.

**Info → Debug shows it on your phone** (tap **•••** on the now-playing screen, then **Info**, then
**Debug**; until 2.0.0-player.10 it was a line between the cover and the song's title). Its **Last
seek** row is the last seek you made, with the bar or from the lock screen: *Asked 2:10, seeking…*
while it's on its way, then *Asked 2:10, the player said 2:10*. If it never got there, because you
pressed Previous or Next first or the song failed under it, it says *Asked 2:10, interrupted*, and
before your first seek, *No seek yet*. Its **Sent as** row says how the song playing was sent, in
Safari:

| Sent as | meaning |
| --- | --- |
| `FLAC in MP4, …` | the song came inside an MP4: seeks should land where you put them |
| `FLAC, not in an MP4, …` | deadwax sent the FLAC as it is (see above); seeks may land off |
| `Asked for FLAC in MP4` | for a moment, while the player checks what came |

In other browsers a FLAC reads `FLAC, as the file is`, since they get every file as it is (a hi-res
song resampled for Maximum quality comes in an MP4 in any browser). So does a FLAC in a Safari too
old to play one in an MP4, and a song that isn't a FLAC reads the same way, `MP3, as the file is`
(an MP3's seeks can still land off; see above).

Safari says the time asked for wherever it lands, so "the player said" can't tell you where a seek
really went, but the end of the song can: if the seek landed off, the song runs out before its
clock reaches the end, or plays on after its clock has stopped at the end, by the same amount. If
the song plays to its end with no other seek or pause, the Last seek row adds what that showed:

| it adds | meaning |
| --- | --- |
| `the song ended on time, so it landed there` | the seek landed where you put it (to within about a second and a half) |
| `the song ran out 7 s before its clock did, so it really landed at about 2:17` | it landed 7 seconds later in the song than asked |
| `the song played on 7 s after its clock ended, so it really landed at about 2:03` | it landed 7 seconds earlier |

To try it on the iPhone, play a FLAC and check Sent as reads `FLAC in MP4`; then pick a song with a
quiet opening and a loud middle, seek well into the loud part near the end, and let it finish.
Last seek should say `the song ended on time`. [Troubleshooting](troubleshooting.md#a-song-seeks-to-the-wrong-place) says more.

## How plays are counted

The player reports plays to Navidrome the way any Subsonic app does, so play counts, "Recently
played" and Navidrome's own Last.fm or ListenBrainz scrobbling carry on working.

- **"Now playing"** is sent when a song actually starts playing.
- **A play** is sent once you've **heard** half the song or four minutes of it, whichever comes
  first, for songs longer than 30 seconds (Last.fm's rule). It counts listening, not position:
  skipping ahead adds nothing, so jumping to the last few seconds of a song isn't a play.
  Listening with the phone locked counts.
- **A play is dated from when the song started playing**, not from when it was put on: a song
  you skipped to while paused and started an hour later is a play from an hour later.
- **Hearing a song again counts again.** **Previous** more than three seconds in, or play on a
  song that has ended, starts a new listen: "now playing" is sent again, and it can count as
  another play. Pausing and carrying on is the same listen.
- Plays go to the `NAVIDROME_USER` account with logins off, and on to Last.fm or ListenBrainz if that
  account has them linked in Navidrome. With logins on (since 2.0.0-player.52) they go to **your own**
  Navidrome account - the one you signed in with - and to your Last.fm or ListenBrainz
  ([the player as you](#the-player-as-you-with-logins-on)).
- A play that can't be reported doesn't interrupt the music, and nothing on the phone says so.
  If plays aren't turning up, see [troubleshooting](troubleshooting.md#plays-dont-show-up-in-navidrome).

## Formats, and Navidrome's Players page

**Files are sent as they are** whenever the phone says it can play them, which on an iPhone
should cover FLAC, MP3, AAC and ALAC. That's the only kind of file Navidrome can send in pieces (byte ranges), which is
what Safari needs to start a song quickly and to skip around in it. The one change is that Safari
gets a FLAC inside an MP4 of the same audio, so that its seeks land
([Seeking](#seeking-and-where-safari-lands)); that's sent in pieces too. With Gapless
on, FLAC songs [in a stream](#one-stream-for-flac) come as a fragmented MP4 of the same audio, in
any browser.

**A file the phone can't play is transcoded to MP3** by Navidrome as it plays. On an iPhone
that's mostly Ogg (Vorbis or Opus) and WMA. A transcode is made as it goes, so the first time
you play one it **can't be skipped through**, and its length is Navidrome's estimate. Once
Navidrome has cached that transcode, it can be skipped through like any other file.

There's no setting yet for a lower bit rate over mobile data.

**Leave Navidrome's Players page alone for deadwax.** Navidrome lists the player there as
`deadwax`, and its **Transcoding** and **Max Bit Rate** look like the place to save mobile data.
They aren't:

- It's **one entry for every browser** using the player, on every network. Every request reaches
  Navidrome from the deadwax container, so Navidrome can't tell your phone on mobile data from a
  laptop at home.
- The player asks for files **as they are, by name**, and Navidrome answers that before it looks
  at the Players page, so a setting there never reaches them anyway.
- For the files it does reach, the ones the phone can't play, a transcoding set there **replaces
  the MP3 the player asked for**, and can hand the phone a format it can't play either.

So leave that player's Transcoding and Max Bit Rate unset.

## Signing in

With logins on ([turning them on](getting-started.md#turning-logins-on)), the app opens on a sign-in
screen: your **Navidrome** user name and password. Nothing else of the app is drawn until you've signed
in, and then you stay signed in on that device - the home-screen app included - for 30 days from when
you last used it. Admins (deadwax's `DEADWAX_ADMINS`) see everything described here; anyone else sees no
**Managing deadwax** in You or the sidebar, no **Edit** on an album and no managing on an artist's page,
and can do everything else - search, **Get**, play, pin.

If your session ends while you're using the app - you changed your Navidrome password, say, or your
account was removed, which deadwax notices within about six minutes - the sign-in screen comes back
**over** whatever was showing, saying why: as soon as the app next asks deadwax for something, as it
comes back to the front, or as a song fails to load. Sign in again as the same person and it goes, leaving the app as it
was underneath. **The music doesn't wait for you, though**: until you've signed in again the player
can't fetch any more of it. The song playing goes on only as far as your device has already fetched
it - with **Gapless** on that's a few seconds, since its stream is fetched a few seconds at a time - and
after that the player does what it does with any song that won't play: it asks for each song left in
the queue once more and skips it (**Skipped "…" - it wouldn't play**), so by the time you've signed in
it has usually reached the end of the queue and stopped, with a reason that blames the song (it was the
sign-in). Play the album, or the song, again once you're back. Signing in as someone else there starts
the app again, since the queue, the pins and the settings in it were the other person's. The app also
asks who is signed in each time it comes back to the front, so a session that ended while the phone was
in your pocket shows the sign-in as you pick it up - and a sign-in screen left showing after you signed
in somewhere else (another tab, say) goes. On a desktop with the visualizer in full screen, the sign-in
takes the screen back first (the visualizer closes), since nothing else can show over full screen. An
app left open while logins are switched on reloads itself into the sign-in screen
([Turning logins on](getting-started.md#turning-logins-on)). What each message means:
[Troubleshooting → Signing in](troubleshooting.md#signing-in).

## Your library, with logins on

Since 2.0.0-player.51. With logins on, **your library is your starred albums in Navidrome** - your
favourites, the same ones Amperfy (or any Subsonic app) shows as starred - and deadwax keeps it for you:

- **What you get is starred for you.** A download you asked for (or joined) is added to your library
  once it's filed, and deadwax stars it **as you** in Navidrome as soon as Navidrome has scanned it -
  found by its MusicBrainz release id, starred, and then checked, since Navidrome answers "OK" to a
  star even for an album it doesn't know. Not there yet, or the star didn't hold, and deadwax asks again
  by itself: after 30 seconds, then a minute, two, and so on up to every half hour, for as long as it
  takes. You needn't be signed in: deadwax keeps the login you last signed in with (encrypted, as your
  session's is) so an album filed at 3am is starred all the same. Signing out leaves it; signing in
  again replaces it.
- **Add to my library.** An album the store already holds that isn't in your library says **In the
  store, not in your library** under **Get the album** (and in the Sources sheet, and the main page's
  candidates panel) with **Add to my library**: it goes into your library and is starred for you, and
  nothing is downloaded. It's offered for a pressing the store holds whole; of a part the store holds
  the line says **The store has 9 of 11 tracks of this pressing**, and a download fills it in, as before.
  **Already in your library** now means yours.
- **Two-way with Amperfy.** Every five minutes deadwax reads your starred albums back: an album you
  star in Amperfy (and the store holds) is added to your library, one you unstar is taken out. A star
  Navidrome loses rather than you taking it away - the album missing from Navidrome for a moment while
  an admin applies a release to it, or coming back under a new Navidrome id after its tags changed - is
  put back instead. Only albums count: starring a song or an artist stays an ordinary favourite. Pins on
  Home stay deadwax's own. A star and an unstar made in two places within a few minutes end up as
  whichever deadwax reads last. The albums you'd already starred before deadwax first read your stars
  back are added to your library too, but not marked new - they were yours already. That first read
  waits for deadwax to have scanned the library once (a new install hasn't until someone searches,
  opens an album's page or runs **Library care → Rescan**): until then every read counts as the first,
  so a star you make before that isn't marked new either.
- **You → Your library** says how many albums your library holds and how many are still waiting to be
  starred, and why - a few albums named for each reason, then how many more: "Navidrome hasn't got it
  yet", "It has no MusicBrainz release id" (an admin can apply a release to it), "Its folder isn't there
  just now", "Navidrome isn't answering". **If you
  change your Navidrome password**, the login deadwax kept for you stops working: it says so in red -
  deadwax can't star albums for you until you sign in again - and what you get meanwhile waits, then is
  starred once you've signed in with the new password. An album an admin deleted is listed there as
  **Removed by the admin - request it again to have it back**, with **Request it again** (its album
  page, where **Get** is) and **Put away**; getting it again puts it away by itself.
- **New** marks: Home's **New in your library**, and a **New** badge on an album's tile in the Library,
  until you open it - from a tile, a link, or its address.
- **The Library tab** is your starred albums since 2.0.0-player.52, with the whole store under
  **Browse**, and "in your library" everywhere in the app means yours - [the player as
  you](#the-player-as-you-with-logins-on).
- **The first admin** to sign in after this version (or to come back to deadwax with a session from
  before it) has every album already in the store put into their library and starred for them, once:
  it was all theirs before anyone else had a library. If deadwax hasn't scanned the library yet at that
  moment - a new install, or one upgraded from a version whose saved scan it can't read - that waits for
  its first scan (searching, opening an album's page or **Library care → Rescan** starts one), so the
  albums it finds then are theirs too. The one exception is an album somebody else's download brought
  in: that is theirs. An album somebody else had starred in Amperfy, or added, goes into both libraries.
  Anyone else's library starts with only the albums they'd already starred. An album that arrives
  without anyone asking for it - copied in by hand, or by another program - is nobody's: it stays in the
  store for anyone to add, and an admin sees it under **Library care → Held by nobody**.
- **The break-glass `admin`** has no Navidrome account, so no library: nothing it downloads goes into
  one, its store line reads as it always did, and **Add to my library** isn't offered to it. Its player
  plays as the shared `NAVIDROME_USER` account ([below](#the-player-as-you-with-logins-on)).
- **With logins off** nothing of this shows: there is one library, and everything in the store is in
  it.

## The player as you, with logins on

Since 2.0.0-player.52. With logins on, the player is **yours**: everything it asks Navidrome - your
albums, a search, a song, a cover, the audio itself, "now playing" and a play - is asked **as you**, with
the login you signed in with. So your plays, play counts, **Recently played**, **Not played in a while**
and your favourites are your own, as they are in Amperfy, and a play goes on to your Last.fm or
ListenBrainz if you linked them in Navidrome. `NAVIDROME_USER` and `NAVIDROME_PASSWORD` are still needed:
deadwax asks as that account for what answers for nobody in particular - fetching a song once into its
own cache for every phone that plays it (FLAC in an MP4 for Safari, the gapless stream, the turntable's
sound), which songs sit beside a hi-res one, whether Navidrome has finished a scan, and which albums it
lists at all (**Not in Navidrome**). With logins off nothing here changes: one account, everybody's.

- **Library is your albums** - your starred albums in Navidrome, the same ones Amperfy shows as
  starred - in the same four orders as ever (**Recently added**, **Recently played** - the ones you've
  played - **Artist** and **Title**). **Artists** is the artists of your albums, counting your albums of
  theirs. **Browse** is the whole store: every album, every artist (counting the store's albums of
  theirs: "2 albums in the store") and every song, as the Library always listed them. On a phone two
  chips over the views choose **Your library** or **Browse**; on a desktop the sidebar lists both,
  **Library** (Recently added, Albums, Artists - yours) and **Browse** (Albums, Artists, Songs). Songs is
  Browse's: Navidrome lists songs from the whole store.
- **An empty library says so** - Ethan's, at first: "Nothing in your library yet", with **Browse the
  store** - in whichever order the albums are in (**Recently played** too: it says "Nothing in your
  library played yet" only over a library that has albums, none played), and under **Artists** as well;
  search, or open an album in Browse, and add it from its page - or **Get** one deadwax doesn't have.
- **In your library means yours**: an album page says **In your library** for an album you starred (in
  deadwax or in Amperfy) or that your library holds, and **In the store** - in grey, with no box - for
  one the store has that isn't yours; it waits for the album's own answer and deadwax's before it says
  either. So does the album you don't have's line and its **Pressing** list, Search's rows, the artist
  page's rows ("2008 · in the store", the ✓ for yours alone) and "The store also has another pressing";
  the artist page's facts are headed **In the store**, and its Play plays their albums in the store
  ("Plays the 2 albums in the store"), yours or not. Info's folder heading
  and its artist count describe the store - **In the store**, "3 albums in the store" - whichever
  library the album is in. The album you don't have's line speaks of the album, and the line under
  **Get** of the pressing chosen: when a pressing of it is yours but the one chosen is the store's, the
  line says **another pressing in your library**, so a page never says "in your library" over **In the
  store, not in your library** - nor the other way round: the album you don't have asks deadwax again
  each time it shows, and takes the line under Get's word for the pressing it's about, so once deadwax
  has read back an album you unstarred in Amperfy (or removed on another device), both lines say so.
- **Add to my library**, on an album page under **Play** for an album in the store that isn't yours
  (Browse, Search or an artist's page take you there): it goes into your library and is starred for you
  in Navidrome at once, nothing downloaded, and it's in your Library when you go back. An album with no
  MusicBrainz release id can't be added - deadwax keeps your library by release - and its page says so:
  star it in Amperfy to have it there. So does one whose folder deadwax hasn't found in the store (not
  scanned yet, or outside the folder it looks after). When deadwax couldn't be asked, the page offers
  neither, rather than guess.
- **Remove from my library**, on the album page of one of yours: it's unstarred for you and taken out of
  your library. **Nothing is deleted** - the store keeps the album and its files, and anyone else who
  has it keeps it - and the page says so: "Removed from your library - it's still in the store, and
  nothing was deleted." It asks no "are you sure?": nothing is lost, and **Add to my library** puts it
  straight back - or, for an album Add can't put back (no release id, or a folder deadwax hasn't found),
  the line after it says how: star it in Amperfy. It isn't listed as "removed by the admin" in You
  either - you removed it. If deadwax can't write the Remove down (its database refusing a write), it
  says so - Navidrome has unstarred it, and Remove again finishes it.
- **Search** (one list since 2.0.0-player.55): in each section yours first, then the store's, then
  MusicBrainz's - each row of the store's saying **in your library** or **in the store** (nothing while
  that isn't known yet: such a row sits among yours and may say "in the store" there once known, rather
  than move), an artist's count your own when you have albums of theirs ("1 album in your library"), else
  the store's; an album you add on its page says **in your library** in its row when you come back. With
  logins off every row of yours says **in your library** now too, since the half titles that said it went.
  MusicBrainz's songs (since 2.0.0-player.53) say **in your library** or **in the store** of a song, and of
  each album it's on, the same way - and **a pressing in your library** (or **a pressing in the store**) of
  an album held as a pressing nothing yet says has the song or hasn't.
- **Home**: Recently added and Not played in a while are asked as you (so "not played" is what *you*
  haven't played); **New in your library** is as before.
- **A Navidrome that gives users libraries of their own** (its multi-library setting): deadwax only ever
  hands you a song Navidrome would give you. Its cache holds one copy of a song for every phone, so
  before answering from it deadwax asks Navidrome, as you, whether you may have that song - once every
  five minutes per song, so seeking and the gapless stream don't wait on it - and a song you may not
  have is "not found", whoever else has played it. **Give `NAVIDROME_USER` every library**: the cache
  fetches each song as that account, so a song in a library it can't see is "not found" there too - it
  won't play on an iPhone or iPad, the turntable is silent for it, and Gapless plays it with a gap
  ([troubleshooting](troubleshooting.md#a-song-in-the-player-wont-start-or-cant-be-skipped-through)).
- **The break-glass `admin`** has no Navidrome account, so its player plays as the shared
  `NAVIDROME_USER` account (its plays are that account's) and sees deadwax as it is with logins off:
  the Library is the store, "in your library" means the store, and Add and Remove aren't offered. It is
  there to get you in when your own login won't, and the shared account is the one deadwax was set up
  with.
- **If your Navidrome password changes** while you're signed in, the player's next request is refused:
  your session ends there and then (as the six-minute check would end it), the sign-in screen comes up
  saying **Navidrome no longer accepts the login you signed in with - if you changed your Navidrome
  password, sign in with the new one**, and nothing more is asked of Navidrome with the old one. Navidrome
  (0.64.1 and later, by default) blocks an account for 20 seconds after five failed logins from one
  address, the right password included, so deadwax keeps its own failures to one: until Navidrome has taken your login in the last
  few seconds, the app's requests go to it one at a time - the first asks, and the rest wait for its
  answer - so a page's burst of covers and pins after the change is one refused login, not one each.
  Each device you're signed in on costs one. Sign in with the new password and carry on.
- **If `DEADWAX_SECRET_KEY` changes** (and deadwax restarts), each session ends at its next request,
  the sign-in screen saying **deadwax's DEADWAX_SECRET_KEY has changed since you signed in**.

## Using it away from home

Unless you've turned logins on there's no login in deadwax, so don't open a port to the internet for
it - and with them on, don't do it without HTTPS in front of deadwax. Reach it over a VPN
instead, such as **WireGuard** or **Tailscale**, and open `/player/` at deadwax's address on that
network. Only deadwax needs to be reachable: the phone never talks to Navidrome.

Behind a reverse proxy that rewrites the `Host` header, the player's plays look to deadwax like
requests from another website, and are refused. [`TRUSTED_ORIGINS`](configuration.md#the-container)
fixes that.

## Known gaps

- **Gapless playback**: there's a short gap between songs, unless you tick the
  [experimental Gapless setting](#gapless-playback-experimental) in You.
- **Hi-res through a USB DAC**: whether Safari ever runs a DAC at a song's own rate is unknown.
- **Play from the lock screen after a long pause** may do nothing until the app is opened: iOS
  puts a web page that isn't playing to sleep. See
  [troubleshooting](troubleshooting.md#after-a-long-pause-play-on-the-lock-screen-does-nothing-until-the-app-is-opened).
- **CarPlay**: not something a web page can offer.
- **Offline**: nothing is kept on the phone for listening without a connection.
- **Not played in a while** looks only at the 500 albums you played most recently, so in a
  library with more played albums than that, the very oldest plays aren't considered. It needs
  Navidrome to send when each album was last played (OpenSubsonic's `played`); without it, the
  section isn't shown.
- **An album with no MusicBrainz release id can't be pinned** (its pin isn't shown): nothing would
  find it again once it moved.
- **On a desktop**, the sidebar's **Managing** has **Needs a look**, **Library care**, **Settings** and **Log**, and otherwise opens the main page;
  between 1024 and 1279 pixels wide a panel lies over the right of the page, the end of a long
  tracklist under it. The Edit panel edits one album, from its page or from **Needs a look**; the bulk
  runs are **Library care**'s; an artist's pictures and **Move albums to …** are on the artist's page, on
  a phone too; the browser preferences of its settings tab stay the main page's. The [visualizer](#the-visualizer)
  sees FLAC songs only; its play/pause is its one control of the music (skip and seek from the player
  bar, after leaving it).
- **The queue doesn't survive iOS closing the app.** Reopen it after iOS has cleared it from
  memory and nothing is queued.
- **Siri**, and a lower bit rate for mobile data.
- **The rest of deadwax**: the main page's browser preferences (search, candidates, auto-grab, the
  interface) and its track table's columns stay there (it works on a phone too); editing an album, the
  albums that need a look, Library care, the server settings and the log are the app's, on a phone as
  on a desktop, since 2.0.0-player.47.
- **On its side**, the now-playing screen shrinks the cover to fit above the controls, which
  leaves it small. There's no landscape layout with the cover beside the controls yet.
- **A saved link to an album can stop working** after you re-apply its release in the metadata
  editor, since Navidrome may give it a new id. The page says Navidrome has nothing by that id;
  go back to the Library and open it again. (Applied from the app's own **Edit** panel, the page
  follows the album to its new id; a link saved before still names the old one.)

## Not yet verified on a real iPhone

The player was built and tested in a desktop browser against a stand-in Navidrome that answers
the way Navidrome's own code does. Since then it has been used on a real iPhone, against a real
Navidrome, and it **keeps playing with the screen locked** and **moves to the next song by
itself while locked**, which is what iOS has historically been fussy about for web apps and the
question the whole player existed to answer. Still to find out:

- whether the **lock-screen and Control Center controls** work;
- whether **AirPlay** works;
- whether **the home-screen app works over plain `http`**, as it will over a VPN;
- whether it keeps clear of the notch and the rounded corners **on its side**;
- **the tab bar and the mini player above it** under a real finger, and whether they keep clear of
  the home bar, upright and on its side (where the tab bar turns compact, the icon beside the
  label);
- whether **an icon added before the tabs** opens the new app with its settings (Maximum quality,
  Gapless, the Library's order) as they were;
- how the home-screen app opens **a link to the main page** - in Safari, or a browser view over
  the app - and whether the music carries on underneath;
- whether **Navidrome sends each disc's title** for your albums (the album page's "Disc 4 · ..."
  headings, and Info → About's disc line);
- **what Navidrome sends** for a song and an album: [Info → Debug](#info--debug)'s **Navidrome
  sent** lists the field names, and later parts of the app want `musicBrainzId`, `played` and
  `playCount` from it;
- **the turntable** under a real finger: turning the record and dragging the arm without the
  screen moving or closing, a tap on the record pausing, and whether it turns smoothly and stops
  while the phone is locked;
- **the turntable's own sound** (2.0.0-player.14): turning the record and hearing it, forwards and
  backwards; holding it still (silent); flicking it while the song plays (it whirs, comes back to
  speed, and the song carries on from there - the song is started again after your tap, which iOS is
  expected to allow; if it says "Tap play to start" instead, it didn't, and the record should then
  slow to a stop rather than keep turning); flicking it back hard (it should be back at speed within a
  second or so); flicking it while paused (it coasts and lands); tapping Next while a flicked record
  comes back to speed (the next song should play); pausing from the record (it winds down) and with
  **Pause winds the record down** off (instant); a hi-res song (its sound as loud as the song); with
  the ringer switch on silent as well as off (iOS has silenced this kind of sound
  on silent before); then locking the phone mid-song after turning the record - the music should keep
  playing and the lock screen's next should work - and all of it on AirPods. If anything is silent,
  [Info → Debug](#info--debug)'s **Turntable sound** row says why;
- **the turntable's sound over plain `http://`** (2.0.0-player.16 - the fix for "the audio doesn't
  follow the turntable when scrubbing"): opened at your usual `http://` address, Debug's **Turntable
  sound** should say `Ready: …` with `On the main thread - this page isn't on HTTPS …` under it,
  and turning the record should be heard forwards and backwards, silent held still, with no quick
  rise in pitch as you grab a playing record or pause from it; a press in the
  moment before it's ready should leave the song playing under your finger; the ringer switch on
  silent shouldn't mute it (deadwax now asks iOS to treat the page as playing music from the first
  tap on the turntable until it goes); and, after turning the record, locking the phone mid-song should still leave the
  music playing, with the lock screen's controls and AirPods working;
- **the turntable's sound following your hand** (2.0.0-player.24 - the fix for "it doesn't sound
  like anything"): turning the record steadily at about its own speed should sound like the song,
  at about half speed like the song an octave down, backwards like it backwards, on HTTPS and over
  plain `http://` alike; the sound should feel a hair behind your finger (an eighth of a second since 2.0.0-player.27, a
  little more over `http://`) and never lurch - the very first turn of a paused record after opening
  the screen included; stopping your finger should stop it within a moment, and starting again should
  carry on from there. Debug's **Turntable sound** line says how far your phone's audio clock moves at
  a time (`Its clock moves … ms at a time`) - tell us what it says;
- **the turntable's sound never clipping** (2.0.0-player.35): scrubbing a loud song should have no
  crackle on its drum hits, slowed, sped up or at its own speed; Debug's **Turntable timing** should
  count the peaks it held (`Peaks held under full scale: …`), and a recording made then should have no
  moment over half a decibel under full scale;
- **Requests** on the phone: the ✕ asking in the card (unless You's **Confirm before cancelling** is
  off on the phone - it's kept per device, so a home-screen app has its own), the count on the tab, Home's Arriving coming
  and going, a download started on the main page showing up when you come back to the app, what
  VoiceOver reads out as downloads change, and the covers fetched from the Cover Art Archive over
  your VPN; with logins on (2.0.0-player.49), **Join this download** and the ✕'s "Leave it" under a
  real finger, and Requests on two phones signed in as two people showing each their own;
- **Search** against your Navidrome: what its search finds for an artist, an album and a song
  (it hasn't been tried against a real Navidrome yet) - and so (2.0.0-player.55) the order it finds them in,
  which decides which of yours lead Top results and the sections (the test stand-in sorts by name, a real
  Navidrome by relevance), whether it sends each artist's MusicBrainz id (MusicBrainz's artists are matched
  to yours by it), and how long its whole list of artists takes on a big library; a song's tap starting its
  album, the pressing list scrolling under a finger without the page moving, the Cover Art Archive's covers
  over your VPN, and MusicBrainz's artist search with accents ("bjork" for Björk - every try of it was
  turned away as MusicBrainz shedding searches); the list's places filling under a thumb, and what
  VoiceOver reads of its one live region, its section headings and its chips;
- **Artists and the id bridge** (2.0.0-player.17) against your Navidrome: whether it sends each
  artist's MusicBrainz id (the artist page's albums from MusicBrainz depend on it, or on the ids
  deadwax wrote into your files), whether its search finds an album by its MusicBrainz release id
  (deadwax asks that first, then by the album's title), what its empty search lists for **Songs**,
  whether it sends a song's play count and writers and an album's label (Info → About), and an
  artist's picture as the page's hero;
- **Pins and Home** (2.0.0-player.18): whether your Navidrome sends `played` on its "recently
  played" list (Home's **Not played in a while** shows only if it does), dragging a row in **Edit**
  by its grip under a real finger without the page scrolling, the pin on an album page, an artist
  page and in the ••• menu, and a pinned album still opening after you re-file it in the main page's
  editor;
- **Get** (2.0.0-player.15) against your slskd and real Soulseek folders: the sources sheet
  scrolling under a finger without the page behind it moving, a tap above it closing it, the sort's
  picker (iOS's own wheel), the cards' words for real folders and users, a download showing in
  Requests from the tap, and **Pick the best source for me**;
- **Info and the ••• menu** under a real finger: that Info's list scrolls and nothing behind it
  does, that a tap above it closes it, and that the Gapless checkbox in You turns gapless on from
  its tap as the switch did;
- how Safari handles a **transcoded** song, and which Ogg files it says it can play;
- whether a song that won't load is **asked for again with the phone locked**: the second try
  comes a moment later, with nothing playing meanwhile, which is exactly when iOS may be holding
  the page back;
- **whether seeks land in the MP4s on the phone**: FLAC was seen landing 3 and 8 seconds out on an
  iPhone, and the MP4s landing exactly was measured on a Mac's Safari engine only (see
  [Seeking](#seeking-and-where-safari-lands)); and how long a song's first play waits there;
- whether the scrubber takes a tap and a drag under a real finger, which a desktop browser can only
  stand in for;
- everything about [the one stream](#what-still-needs-trying-on-a-real-iphone) as deadwax builds
  it, though the way it's built was proved on an iPhone first;
- hi-res songs resampled to 48 kHz, and above all a 24/192 album's joins, and how long the first
  song waits on your NAS; and 24/192 streamed as it is under "Original" (whether an iPhone keeps up
  with it, and plays FLAC at that rate in a stream at all);
- **[the speed fader](#the-speed-fader)** (2.0.0-player.39): whether the pitch really moves with the
  speed on the phone (it should sound like a record played fast or slow, never the same pitch
  stretched), whether 0.25x and 0.5x play at all (Apple promises 1x to 2x for any song, and below 1x
  only for a song it says can play slowly - Debug's **Speed** row says how fast the song really moved),
  whether a change of speed while the [one stream](#one-stream-for-flac) plays stutters (Apple's player
  may throw away the sound it has queued when the speed changes), the lock screen's scrubber at the
  speed, and AirPlay - WebKit hands an AirPlay speaker the same speed as the phone, but whether a
  speaker plays it, and its pitch, is the speaker's business. And the fader under a real finger,
  beside the record and the arm.
