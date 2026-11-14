# The iPhone app (early: app 0.9, downloads, lyrics, the EQ, the turntable, play history and your library)

deadwax is getting a native iPhone app, built with SwiftUI and its own audio engine, for what a web
page can't do well: seamless joins and normalization done on the phone, downloads to play offline,
and a song's start never lost on AirPods. It's built in phases. Phase 0, "Hello, iPhone", was a
single test screen that proved the tools, the connection and the audio engine. Phase 1, the player
(app 0.2), was the first version meant for playing your music day to day: your library, album pages,
Up Next, Now Playing, normalization, the lock screen, plays counted, and picking up where you left
off. Phase 2, downloads (app 0.3), followed: an album, or a song, downloaded to the phone plays from
there, bit for bit as deadwax has it - and goes on playing when deadwax can't be reached (see
[Downloads](#downloads) and [Offline](#offline)). App 0.4 added lyrics on Now Playing, as the web app
shows them (see [Lyrics](#lyrics)). App 0.5 added the EQ: ten sliders and nine presets, kept for each
output on its own - your headphones, the speaker, the car - and switching by itself when the output
changes, a correction for your headphones from AutoEq's measurements, and - under Advanced - filters
and a preamp of your own and Equalizer APO files in and out (see [EQ](#eq)). App 0.6 added the
turntable: Now Playing's second look, as the web app has it - a record you can turn by hand and hear
as you turn it, with the album's CD art on its face (see [The turntable](#the-turntable)). App 0.7
added the turntable's speed fader: the song faster or slower, its pitch moving with it, as a record
deck's does - and at 1x the song exactly as it is (see [The speed](#the-speed)). App 0.8 added play
history: scroll up in Up Next, past the song playing, and it goes on back through every song you've
played - on the phone and in the web app, one list, as the web app's Up Next has it - and the phone's
own plays go into the web app's too (see [Up Next](#up-next) and [What you've
played](#what-youve-played)). **This is app 0.9, which adds your library downloaded by itself**, as
much as fits your storage limit, kept in step with what you star and unstar anywhere - only while the
phone is charging if you choose, and with the app in the background when iOS allows (see [Your library
on this phone](#your-library-on-this-phone)). Phase 4 has begun with **playlists**: yours and those
shared with you, in the Library, played as the web app plays them, and made, added to, edited and
deleted on the phone as in the web app, and downloaded to play with no connection, kept in step as they
change (see [Playlists](#playlists)); with the Library's switch - Albums | Playlists | Artists, swiped
between, in the order you choose - and a pull down that shuffles your whole library (see [The
Library](#the-library)); and with **artists**: your artists, and an artist's page with their albums, Play
and Shuffle (see [Artists](#artists)). Songs, Search and the rest come next (see [What it can't do
yet](#what-it-cant-do-yet)).

**Nothing of Phase 2, the lyrics, the EQ, the turntable, play history, your library downloaded,
playlists or artists has been seen on an iPhone yet.** It's built and tested on a Mac, and what only a
phone can tell is what [the checks](#the-checks) are for. Until they're answered, read everything about
downloads, lyrics, the EQ, the turntable, play history, your library, playlists and artists below as what
the app is built to do.

The app talks only to deadwax, never to Navidrome, through deadwax's own routes, so the phone never
needs the Navidrome account deadwax itself uses. With logins on, you sign in with your own Navidrome
user name and password: the password goes to deadwax, and isn't kept on the phone.

**Which deadwax it needs.** Everything but normalization works with deadwax 2.0.0 or later.
Normalization needs **deadwax 2.1.1 or later**, which adds the route that tells the app what deadwax
has already measured of an album's loudness: each song's, and the album's as a whole. The app levels
songs on the phone from the same measurements the web app's Normalization uses. The route only reads
what's there and never measures anything itself, and it only answers about an album the signed-in
person can see in Navidrome. With an older deadwax, songs play as they are, and Info says "Not this
time - the album's volume couldn't be checked" ("the song's" for a song levelled on its own). 2.1.1
isn't a release yet: until it is, it's in the `:experimental` image, not `:latest` (see "Which image
tag" under [The compose file](getting-started.md#the-compose-file)). You > About shows which deadwax
you have. [Lyrics](#lyrics) need **deadwax 2.1.5 or later** - for now also only in `:experimental` -
and with an older one say "Couldn't load the lyrics." The EQ's
[AutoEq corrections](#autoeq-a-correction-for-your-headphones) need **deadwax 2.1.7 or later**, also only
in `:experimental` for now: with an older one, no suggestion appears and the correction picker's search
says "Something went wrong." - an admin sees why, folded under it: "This deadwax is too old for AutoEq's
corrections: they need deadwax 2.1.7 or later." The rest of the EQ is on the phone and needs nothing of
deadwax.

**Where Phase 1 is.** It's on the `ios` branch while it's being built. `main` has Phase 0, released
with deadwax 2.1.0. install.sh builds whichever branch is checked out, so to try Phase 1, switch to
`ios` once (step 1 of [Once](#once)).

## What you need

- **A Mac with Xcode.** Xcode 16 or later opens the project. An iPhone on iOS 27 needs **Xcode 27**,
  because Xcode only installs on iOS versions it knows. No iOS Simulator is used or needed: when
  Xcode offers to download one, you can say no.
- **About 8 GB free** on the Mac: for the build, and for the copy of the phone's debug symbols Xcode
  makes the first time the iPhone is connected.
- **An iPhone on iOS 17 or later** and its cable, for the first install.
- **A free Apple account.** Its catch: **each install runs for 7 days**, and then the app won't open
  until you install it again. Installing it again is one command, below, and keeps everything on
  the phone. For an admin (with logins off, everyone), **You > Debug** says when the install runs
  out; anyone else just finds the app won't open after the 7 days.
- **The test album.** "Start test (2026)" by "deadwax test" is ten short FLAC songs: eight of three
  beeps each, with the first beep at a known time, and two that are one steady tone cut in two. It's
  still the clearest test of a seamless join, and Debug's Test sounds play it.
  If you made it before it had ten, make it again: the same command adds songs 9 and 10. `ios/scripts/make-test-album.py` makes it, with any
  python3 and nothing to install (the Mac's own is `xcrun python3`):

  ```
  xcrun python3 ~/Developer/deadwax/ios/scripts/make-test-album.py <your music folder>
  ```

  It writes `deadwax test/Start test (2026)/` there (about 6 MB) and touches nothing else. Or make it
  in an empty folder and copy that into your music library. Then let Navidrome scan it. The app finds
  it by name.

## Once

1. **Clone the repo outside iCloud**, to `~/Developer/deadwax`:

   ```
   git clone https://github.com/real-lizardwizard/deadwax.git ~/Developer/deadwax
   ```

   Not Desktop or Documents: when iCloud syncs those, it can evict files from the Mac when space runs
   low, which stalls builds. install.sh pulls whichever branch is checked out: `main` has the app as
   released with deadwax (Phase 0 since 2.1.0), and the `ios` branch has the next phase while it's
   being built, Phase 1 now. To follow it:

   ```
   git -C ~/Developer/deadwax switch ios
   ```
2. **Open Xcode once** and let it finish installing its own components. Or run
   `xcodebuild -runFirstLaunch`. install.sh uses `/Applications/Xcode.app` by itself, so nothing
   system-wide has to change.
3. **Add your Apple ID to Xcode**: Xcode > Settings > Accounts > + > Apple ID. A "Personal Team"
   appears under it.
4. **Your team, in `ios/Config/Local.xcconfig`.** Run `ios/scripts/install.sh` once: it offers to
   write this file for you, from the teams Xcode knows, and then stops, saying the next step is
   step 5 (a build can't work before it). To do it by hand, copy `Local.xcconfig.example` beside it
   and put your team id in it. The file is yours: git ignores it.
   **Set the team only here, never in Xcode's Signing & Capabilities.** Xcode writes a team picked
   there into the project file, which is part of the repo, and the next `git pull` then refuses to
   run. If it has happened, `git checkout ios/Deadwax.xcodeproj` undoes it (install.sh says so too).
5. **The first install, from Xcode with the cable.** Open `ios/Deadwax.xcodeproj`, choose your
   iPhone at the top, and press Run. Signing & Capabilities shows your team, read from
   Local.xcconfig. Xcode registers the phone, makes the free signing profile, and prepares the phone
   for development. Then, on the iPhone:
   - turn on **Settings > Privacy & Security > Developer Mode**, which appears after that first
     connection, and restart when asked;
   - trust yourself as the developer: **Settings > General > VPN & Device Management > your Apple ID
     > Trust**.
6. *(Optional)* In Xcode > Window > Devices and Simulators, select the iPhone and tick **Connect via
   network**. Later installs then need no cable while both are on your home Wi-Fi.

**The app's id is `net.lizardlounge.deadwax`.** Keep it once the app is on the phone. A new
id makes a new, empty app: the sign-in, the songs kept on the phone and the settings stay with the
old one. It also uses up one of the few new app ids a free account may register each week.

## Every week, or when there's a new build

```
~/Developer/deadwax/ios/scripts/install.sh
```

It pulls the latest code, asks GitHub whether the app's checks passed on it (and asks you before
building one that failed or is still running), builds it (Release), and installs it **over** the app
on the phone, so everything on the phone stays. Then it opens the app and says how long the new
install runs: `Installed deadwax 0.9 (9), runs until Wed 18 Nov, 14:02`. It also says how long it
took and the Mac's free space before and after. Xcode doesn't need to be open.

| option | what it does |
| --- | --- |
| `--no-pull` | builds what's checked out, without `git pull` |
| `--yes` | doesn't ask: uses the first team and iPhone it finds, and builds even if the checks failed |
| `--debug` | builds Debug instead of Release |

It remembers which iPhone it installed on, in `ios/Config/device` (also ignored by git). The build
happens in `~/Library/Caches/deadwax-build`, and the last build's whole log is `last-build.log` there.

## The first time you open it

1. **deadwax's address**: the address you open deadwax at, by IP (`192.168.1.20:8090`) or by name.
   `http://` is assumed when you don't type it, and a pasted web-app link (`.../player/`) works too.
   **Check** asks deadwax whether it's there, and the address is kept only once it answers. The first
   time, iOS asks to let deadwax **find devices on your local network**: say yes.
2. **Sign in**, when logins are on: your Navidrome user name and password, as on the web app (a
   password manager can fill them in). The password isn't kept on the phone. Only the session
   deadwax gives back is kept, in the Keychain, for that address. With logins off there's no sign-in,
   and the app opens on the Library.

From then on the app opens straight into your music. It keeps who deadwax last said you are, so it
opens at once and asks deadwax behind it: if your sign-in has ended, the sign-in comes up over the
app, and if deadwax doesn't answer, the app stays open (You says it couldn't check). Only a phone that
has never been let in at that address waits for deadwax; if it doesn't answer, that one says "Can't
reach deadwax. Check you're on the right network (or your VPN is on) and try again.", with **Try
again** and **Change address**, and tries again by itself whenever you come back to the app.

A play made while deadwax can't be reached isn't lost: it's kept on the phone with the time you played
it, and sent - oldest first - as soon as deadwax answers again, so Navidrome (and Last.fm or
ListenBrainz behind it) count it.

If your sign-in ends while you're using the app (it ran out after 30 days unused, an admin reset
your password, or your password was changed from another device), the sign-in comes up over the
app with deadwax's reason, Now Playing closes, and the music plays on underneath. Signing in again as
the same person carries on where you were. Signing in as someone else starts afresh: nothing of the
first person's queue stays.

The app has two tabs, **Library** and **You**. Tapping the tab you're on goes back to its first
screen, or to the top of it. Once something is playing, the mini player sits just above the tabs,
and every screen scrolls far enough for its last row to come up above it.

## The Library

The Library opens on its pages, side by side: **Albums**, **Playlists** and **Artists** (Songs joins them
later in Phase 4). The switch at the top - Albums | Playlists | Artists - picks one, or swipe left and
right between them, the switch moving with you. The Library opens on the first page each time the app
starts, and when someone else signs in; after that it stays on the page you left it on. Tap the Library
tab while you're on it, and the page goes back to its top. Nothing sits above the albums but their count.

With logins on, **Albums** is **Your albums**: the albums in your library, as the web app's Library has them
([sharing deadwax](sharing.md) says how an album gets there), and ••• > **All music** > **All albums** is
the whole collection's. With logins off, and for the break-glass `deadwax` sign-in, Albums is the whole
collection. **Playlists** is your playlists (see [Playlists](#playlists)), and **Artists** the artists of
your albums (see [Artists](#artists)).

**The •••** at the top right (VoiceOver reads it "More for the Library"):

- **Shuffle**: your whole library, shuffled - see [Shuffling your library](#shuffling-your-library). Until
  it's ready it reads "Getting ready…", dimmed.
- **The page's own**: on Albums, **Album order** (showing the one chosen - below) and **Show as list**
  (or **Show as grid**); on Artists, **Artist order**. Playlists has none.
- **Downloaded**: what's on this phone (below).
- **All music**, with a library of your own: **All albums** and **All artists**, the whole collection's.
- **Refresh**: your albums, your playlists and the artists asked for again now.
- **Edit order**: the pages as rows - drag them by their handles into the order you want, and **Done**. The
  Library opens on the first, and this phone remembers the order. A page that's new since you last
  arranged them (Artists, for an order arranged before it came) joins at the end.

Beside the ••• is Playlists' **+**, for [New playlist](#playlists), on that page. The orders and Grid or
list moved into the ••• when Artists joined, so three pages - four, with Songs - fit beside it.

On the Albums page:

- **Grid or list**: ••• > **Show as list** switches to rows, **Show as grid** back to covers. It starts as
  a grid, and this phone remembers your choice.
- **The order** (••• > **Album order**): **Artist** (the first time), **Title**, **Recently added**,
  **Year, newest first** or **Year, oldest first**, under headers: the first letter (names that don't
  start with a letter come last, under #), the month it was added ("Date unknown" when deadwax
  doesn't know), or the year ("No year"). In Your albums, Recently added means when the album came
  into your library; in All albums, when the collection got it. This phone remembers the order.
- **Find**, under the switch, keeps the albums whose title or artist holds every word you type, in any
  order and anywhere in a word ("eat" finds the Beatles). The count above the albums then says "12 of
  3012 albums". Each page keeps its own words in Find.
- **The index** down the right edge, once a list has 50 albums or more: A to Z and # for Artist and
  Title, decades for the two Year orders. There's none for Recently added, or while you're finding.
  Touch or slide along it to jump.
- **New** marks an album that came into your library and that you haven't opened yet, here or on the
  web app. Opening it clears the mark, on both.
- **Tap an album** to open its page. Nothing plays from the Library itself, but the pull.

The list is kept on the phone, so the Library shows at once when the app opens, and is asked for
again when it's more than a minute old, each time the Library comes into view; ••• > Refresh asks now.
If deadwax can't be asked, the list stays as it was, under "Couldn't update this list - showing it as it
was." deadwax lists at most 10,000 albums; past that, the Library says "Showing the first 10000 albums -
deadwax reads at most that many."

An empty Your albums says "Nothing in your library yet.", with **See All music** to add some from
the collection. (Its words mention Search and Get: those are the web app's, for now.)

### Shuffling your library

**Pull down** on any page, a good way past its top: a ring round the shuffle mark fills as
you pull, the mark growing and turning, "Pull to shuffle" under it. At the line the phone ticks, the ring
becomes a purple disc, and it says "Release to shuffle" - let go then, and your library plays shuffled
("Shuffling"). Push back up a little before you let go and it's the ring again (pull down again for
another tick); let go before the line and nothing plays. A pull never refreshes the Library now: it asks
for itself as it comes into view, and ••• > Refresh asks now. The lists opened from the ••• - All albums,
All artists, Downloaded, Downloaded playlists - still refresh when pulled.

It's deadwax's shuffle, the web app's Library > Shuffle: every song of your library (of the collection,
without a library of your own) once, in an order deadwax makes, played from the first. Its first 200
songs are fetched before you ask - as the Library comes into view, and again when that was more than ten
minutes ago - so the music starts the moment you let go. More are added to the end of Up Next as it plays,
whenever fewer than 50 of its songs are left after the one playing, until every song is in. With Repeat
All, once they've all played, a new order begins, never with the song that just ended. If deadwax no
longer has the order (it restarted, or a day went by), a new one carries on and the app says "Your
shuffle started over - deadwax no longer had its order", once. With Normalization on, each song is
levelled on its own, as a playlist's are.

Until its first songs are here, the ring fills but never turns purple, and says "Getting ready…". If
deadwax couldn't get them ready, it says "Couldn't get your songs ready to shuffle" - or, for a library of
more than 200,000 songs, "Your library is too big to shuffle here" - and tries again the next time the
Library comes into view, or with ••• > Refresh. With no songs at all, there's no Shuffle in the ••• and
nothing to pull.

While deadwax can't be reached, it shuffles the songs on this phone instead: ••• > **Shuffle downloads**,
or the pull's "Pull to shuffle your downloads". With nothing downloaded there's no Shuffle in the •••, and
the pull says "Nothing on this phone to shuffle".

With **Reduce Motion** on, the mark doesn't grow, turn or spin; the ring still fills as you pull, and the
states change at once. **VoiceOver** and Switch Control use ••• > Shuffle; the pull's graphic isn't read.
On **iOS 17** there's no pull, only ••• > Shuffle.

**Downloaded** (in the •••) is every album with a song on this phone, whoever's library it's in, drawn as
the other lists are: the same orders, Find, headers and index. An album your library is downloading by
itself shows there once a song of it is here or downloading, never while it only waits its turn.
Its **Recently added** means downloaded to this phone, newest first. Each album there has a third
line: "12 songs", "3 of 12 songs", "Downloading", "Waiting", or, in amber, "Didn't download". With
nothing on the phone it says "Nothing downloaded yet." At its top, **Downloaded playlists** when you've
[downloaded a playlist](#downloading-a-playlist).

**Keep your library on this phone?** The first time you open Downloaded while your library has albums, a
card at its top asks whether to [download your library](#your-library-on-this-phone) by itself ("Keep the
collection on this phone?" with logins off), as much as fits in your storage limit. **Turn On** turns it
on; **Not Now** puts the card away. Either way it doesn't come back, and the setting is in You > Downloads.

**The download marks**, at the end of an album's artist line on every list (and on a song's row on an
album's page): a filled arrow for downloaded (all of it, or some of its songs), a dotted one while it
waits, a ring filling as it downloads, and an amber **!** for didn't download. VoiceOver says them in
words after the artist: "Downloaded", "Partly downloaded", "Downloading", "Waiting to download",
"Didn't download".

**The Library needs Navidrome**: it's the albums Navidrome lists, through deadwax. If deadwax can't
reach Navidrome, or hasn't been told where it is, the Library says so in place of its pages (see
[When something goes wrong](#when-something-goes-wrong)) - with **On this phone > Downloaded** under
it when anything is downloaded, since those play from the phone. It checks again each time you come
back to the Library tab or the app, and when you pull down.

## An album's page

- **At the top**: the cover, the title, the artist, and a line like "Electronic · 1998 · FLAC" (the
  genre, the year, and the format when all its songs share one). It says whether the album is **In
  your library** or only **In the collection**. With logins off, and for the break-glass `deadwax`
  sign-in, every album reads In your library.
- **Play** plays the album from its first song. **Shuffle** plays it in a random order, with Shuffle
  on. Play is the web app's purple button, white on purple; Shuffle beside it the web app's grey one.
- **The songs**, under a heading for each disc when there's more than one, or a disc has a title
  ("Disc 2", or "Disc 2 · Live" with its title). The song playing has moving bars instead of its
  number. **Tap a song** to play the album from it. Under the songs: how many and how long ("10
  songs, 42 min").
- **•••** at the end of a song's row has **Play Next**, **Play Last** and **Add to a playlist…** for
  that song; the **•••** at the top has them for the whole album (see [Up Next](#up-next) and [Add to
  a playlist](#add-to-a-playlist)). Each menu opens from the ••• you tapped, and a tap anywhere else
  closes it.
- **Add to my library** and **Remove from my library**, with logins on. Removing takes the album out
  of your library only: "it's still in the collection, and nothing was deleted."
- **The artist's name**, in purple, opens [their page](#artists). An album that names no artist to go to
  shows the name in grey, and it opens nothing. While the album is still loading, and the list you came
  from didn't say who its artist is, the name is purple but can't be tapped yet, so it never changes
  colour as the album comes in. If the album doesn't come - it couldn't be loaded, it's gone, or deadwax
  can't be reached and it isn't on the phone - the name is grey.

**Downloading it** (see [Downloads](#downloads)):

- **The download button**, at the top right beside the •••: a tap on the arrow downloads every song
  of the album that isn't on the phone yet. Once it's asked for, the button shows how it's going - a
  ring filling while it downloads, a dotted arrow while it waits, a filled arrow once it's all here,
  an amber **!** if a song didn't download - and a tap opens a menu that says so in words ("Waiting
  for Wi-Fi" with "Download over is Wi-Fi only - in You > Downloads." under it, "Downloaded · 412 MB",
  "2 songs didn't download" and why), with **Remove Download** (and **Download Again** when a song
  didn't download). So a tap meant for the ••• beside it never throws a download away.
- **Under the title**, the same in words: "Downloading - 4 of 12", "Waiting for Wi-Fi", "Downloaded",
  "3 of 12 songs downloaded", "2 songs didn't download".
- **Each song** has its mark before its time, and its **•••** has **Download** (or **Remove
  Download**, or **Download Again**); the **•••** at the top has them for the whole album. Removing
  says "Removed from this phone: Dummy".
- **Under the songs**: "412 MB on this phone", or "3 of 12 songs on this phone · 92 MB".
- An album that's gone from the collection, with songs of it still on the phone, says "This album
  isn't in the collection any more - the songs on this phone still play.", and its button has only
  Remove Download.

With [Download your library](#your-library-on-this-phone) on:

- An album it downloaded has the same button, its menu headed "Downloaded with your library". **Remove
  Download** removes it, and your library then leaves it off this phone - the page says "You removed
  this download - your library leaves it off this phone." - until you download it again with the arrow.
- An album of your library that doesn't fit says, under the title, "Your library doesn't all fit in 20
  GB - this one waits for room." The arrow downloads it anyway, as yours: first in line, and never
  removed to make room.
- A song your library downloaded has no Remove Download of its own (it would only come back): remove
  its album instead.
- **Remove from my library**, when your library downloaded the album and you downloaded none of it
  yourself, says "Its download goes from this phone too." - and it does, as soon as deadwax's list
  agrees, usually at once.

With Normalization on, opening an album that has FLAC songs asks deadwax to measure it, if it hasn't
yet, so its first song is less likely to wait when you play it.

## Playlists

**The Library's Playlists page** (the switch's) lists your playlists as Navidrome keeps them - the same ones the web app,
Amperfy and Navidrome show you. With logins on they're read as you, so someone else's private
playlist never shows; with logins off (and for the break-glass `deadwax` sign-in), they're those of
the Navidrome account deadwax uses:

- **Yours**: the playlists you made, each with how many songs and how long ("12 songs · 48 min"), and
  "· Shared" at the end when it's shared with everyone.
- **Shared with you**: other people's playlists they've shared, with whose they are ("Sam · 12 songs ·
  48 min").
- **From files (3)**, folded: playlists Navidrome made from files in the music folders ("From a file ·
  12 songs"). Tap the row to open it out; it stays open until the app is closed, or deadwax goes out of reach and comes back.

Each group is in Navidrome's order, by name, and shows only when it has playlists. The list is asked
for each time the page comes into view, and when you come back to the app on it; ••• > Refresh asks now
(a pull down [shuffles your library](#shuffling-your-library), as on Albums). **Find**, under the switch,
keeps the playlists whose name holds every word you type, in any order, From files opened while it
finds; with none, "No playlists match “…”." If deadwax can't be asked, it says "Couldn't list your
playlists." and why - over the list as it was, or with **Try again** when there's no list to show.
With none at all: "No playlists yet.", how to make one, and **New playlist**. **Tap a playlist** to
open its page. Nothing plays from the list itself.

**New playlist** is the **+** at the top of Playlists: type its name (up to 200 letters) and
**Create**. It's made in Navidrome, as you, empty, and its page opens - add songs to it with **Add to a
playlist…**. If it can't be made, the sheet stays open and says why.

**A playlist's page** is laid out as an album's:

- **At the top**: its cover (Navidrome's four-cover mosaic), its name, whose it is ("Yours", "Yours ·
  Shared with everyone", "Sam's · Shared with you", or "From a file in the music folders"), why it
  can't be changed here when it can't ("Only Sam can change this playlist."), its description, and how
  many songs and how long ("12 songs, 48 min").
- **Play** plays it from its first song. **Shuffle** plays it in a random order, with Shuffle on. **Tap
  a song** to play the playlist from it.
- **The songs**, each with its own album's cover, and its artist and album under its title; the song
  playing has moving bars over its cover. A song that's in the playlist twice is there twice. Under the
  songs: how many and how long.
- **•••** at the end of a song's row has **Play Next**, **Play Last** and **Add to a playlist…** for
  that song, and **Download** (or **Remove Download**, or **Download Again**) for it alone; the **•••**
  at the top has Play Next, Play Last and Add to a playlist… for the whole playlist, and **Download**
  for the playlist as one (see [Downloading a playlist](#downloading-a-playlist)), as the arrow beside
  it does.
- When Navidrome counts songs it isn't listing just now: "2 songs in this playlist aren't in the
  library just now - deleted, or being moved."
- A playlist deleted elsewhere says "This playlist isn't on Navidrome any more - deleted in another
  app, maybe." An empty one says "Nothing in this playlist yet. Add songs from a song's or an album's
  ••• menu - Add to a playlist - or from Now Playing's ••• while a song plays."
- The page shows at once when you go back to it, or open one of the last few again, and is asked for
  again as it shows, and when you come back to the app with it open. If that fails it stays as it was, under "Couldn't update this playlist - showing it
  as it was."; with nothing to show: "Couldn't open this playlist." and why, with **Try again**.

**Playing a playlist**, each song plays as itself, with its own album: the mini player, Now Playing and
the lock screen show its album's cover, **Go to album** opens its own album, and Info > About names its
album and year and gives its number alone - "Track 5", not "Track 5 of 12", since the app has only the
playlist's songs of that album. With Normalization on **Automatic**, each song is levelled on its own,
as the web app levels a playlist (Info says "Song volume matching, ..."): a playlist isn't an album.
**By song**, **By album** and **Off** do what they always do.

### Add to a playlist

**Add to a playlist…** is in every song's and every album's **•••** - an album's page, a playlist's
page, and each of their songs - and in Now Playing's **•••** for the song playing. It opens your
playlists under what you're adding ("Dummy · 11 songs", "Roads · Portishead"), the one changed last
at the top - only the ones you can change: never one shared with you, or one Navidrome made from a
file. **Tap one**: it closes, and the app says what happened ("Added 11 songs to Late night").

When some of them are in it already, nothing is added yet, and it asks:

- "These 11 songs are all in Late night already." - **Add them again**, or **Cancel**.
- "3 of these 11 songs are in Late night already." - **Add them all**, or **Skip those 3** (which adds
  the other 8: "Added 8 songs to Late night - 3 were in it already").
- "Roads is in Late night already." - **Add it again**, or **Cancel**.

**Cancel** goes back to your playlists. **New playlist…** at the top makes one with them: a name, then
**Create** ("Made Late night with Roads"). One tap adds once: the playlists wait ("Adding…") until
Navidrome has answered. Close it while an add is on its way and the add carries on, and the app still
says how it went - open it again meanwhile, from anywhere, and it's still "Adding…", the playlists
waiting. If it couldn't be added, it says why over your playlists.

### Edit and Delete

**Edit**, at the top of a playlist of yours, changes it. It isn't there for one shared with you, or
one from a file, or one of more than 2,000 songs - the page says why instead - and it can be tapped
once the page has been brought up to date. In Edit:

- **Name** (a playlist needs one: "A playlist needs a name.", and Done waits; up to 200 letters),
  **Description** (up to 1,000), and **Shared with everyone**: everyone with an account on this
  Navidrome can find it and play it - in deadwax, Navidrome and their other apps. Only you can change
  it. A name or description made longer in another app is kept as it is: it can be shortened here,
  not lengthened.
- **The songs**: drag one by its handle to move it, and tap its red minus to take it out - one tap,
  as in Up Next. With VoiceOver, each song has Move up, Move down and Remove. Edit only takes songs
  out and reorders them; add them with Add to a playlist.
- **Cancel** leaves it as it was (asking "Discard your changes?" first, if you'd changed anything).
  **Done** saves it ("Saving…"), and the page then shows it as Navidrome has it. Nothing is saved
  until Done.
- If it changed in another app since you tapped Edit - a song added in Amperfy, say - Done saves
  nothing: "This playlist changed in another app while you were editing it - here it is now. Your
  changes weren't saved." Tap Edit and make them again. If Done is refused for any other reason, Edit
  stays open with why, and **Done** tries again.
- Tapping the tab you're on goes back only as far as the playlist while Edit is open: Cancel or Done
  leaves Edit.
- When Navidrome counts songs it isn't listing just now: "2 songs that aren't in the library just now
  will be dropped if you change the songs."

**Delete playlist** is at the bottom of Edit. It asks first: "Delete "Late night"? It goes from
Navidrome for good - from Amperfy and every other app too, and for everyone it's shared with. The
songs stay in the library." - **Delete playlist**, or **Keep it**. There's no undo. Deleted, the page
closes and the app says "Deleted Late night". If it had gone already - deleted in another app - the
page closes all the same, saying so.

### Downloading a playlist

**Download** a playlist with the arrow at the top right of its page, beside its •••, or with
**Download** in that •••. Its songs come as an album's do - each the very file deadwax has - and the
whole playlist is planned at once: it waits for room under the storage limit, or for space on the
phone, as one, never half of it. A song of it already on its way - one you were downloading yourself,
say - carries on, and the rest wait together. The playlist itself is kept on the phone, so it opens
and plays with no connection. While its songs come, the arrow is a ring and the page says how far it
has got ("Downloading - 4 of 12 songs"); once they're all here, "This playlist is downloaded - it plays
with no connection." Tap the mark for what it's doing, with **Remove Download** - and **Download
Again** for songs that didn't come.

- **It keeps in step.** Change it anywhere - add a song in the web app or Amperfy - and the phone
  follows. The app looks when it opens, when you come back to it, when deadwax is back, every 15
  minutes while it runs, and whenever you open the playlist. A song added comes. A song taken out goes
  from the phone only once two looks ten minutes apart agree it has gone, so a moment when Navidrome is
  busy never deletes anything - taken out with **Edit** on this phone, it goes at once (only the songs
  you took out: one Navidrome isn't showing just then, while its file is moved, stays). Deleted here,
  the download goes with it; deleted in another app, it goes once two looks ten minutes apart can't
  find it.
- **What stays.** A song you downloaded yourself, with its album, with your library, or with another
  downloaded playlist stays when the playlist's download goes, or when the song leaves the playlist.
  While a downloaded playlist keeps a song, the song's **•••** has no Remove Download - it says
  "Downloaded with Late night" instead; remove the playlist's download. Your library never removes a
  playlist's songs.
- **Where.** The Library's **Downloaded** (under On this phone) has **Downloaded playlists**, with how
  many - a list of them that opens with no connection too. In You > Downloads, **Downloading** has a
  row for each one with songs to come ("3 of 12 songs to go", or what they wait for), and
  **Downloaded** lists each one first, with its songs here and their size. Tap one to open it; swipe it
  to **Remove** its download. **Remove All Downloads** takes them too, and says so: the playlists
  themselves stay in Navidrome.
- **Its picture.** A playlist's mosaic isn't downloaded with it: with no connection it shows only if
  the phone still has it from before.
- **Smart playlists can't be downloaded.** Navidrome works a smart playlist out again each time, so
  there's no arrow on its page and nothing to download in its •••; the page says "Smart playlists are
  worked out again each time, so this one plays only while deadwax can be reached." Playlists made from
  an .m3u file download as any other. One you downloaded before deadwax could tell it was smart stays
  on the phone as it was - nothing added, nothing taken - and says so; **Remove Download** takes it off
  as any playlist's. (deadwax tells the phone which playlists are smart from its 2.1.x on; before that,
  none is treated as smart.)

### Playlists offline

**Offline**, a downloaded playlist opens and plays the songs of it on the phone. Any other playlist
with a song on the phone opens if its page is one of the last eight you opened since the app started:
the songs not on the phone are dimmed, and Play and Shuffle play the ones that are. The others are
dimmed in the list and open nothing. With no list in hand, Playlists lists your downloaded ones ("Your
downloaded playlists - the rest show once deadwax is back."), or says "Your playlists show here once
deadwax is back." with none. While deadwax can't be reached the Albums page is Downloaded, with
Downloaded playlists at its top.

Nothing is made or changed while deadwax can't be reached: Add to a playlist… isn't in the ••• menus
or Now Playing's, and **+** and **Edit** are dimmed. Nothing is kept to send later - a playlist can be
changed from any app, and a change sent later could land on one that has changed since.

## Artists

**The Artists page** is a page of the Library's switch. With logins on it's **Your artists**: the artists of
the albums in your library, each with how many of your albums are theirs ("2 albums"), as the web app's
Library > Artists has them. ••• > **All music** > **All artists** is every artist in the collection, each
with how many albums the collection has of theirs ("12 albums in the collection"). With logins off, and
for the break-glass `deadwax` sign-in, the page is **Artists**, the whole collection's.

- **A row** is the artist's round picture (Navidrome's, as the web app shows it), their name and their
  count. **Tap it** to open their page. Nothing plays from the list but the pull.
- **The order** (••• > **Artist order**): **Name** (the first time) or **Most albums**. Name sorts by
  deadwax's own spelling of a name - "The" at the start, accents and case set aside - under letter headers,
  with names that don't start with a letter under # at the end. Most albums has no headers. This phone
  remembers the order.
- **Find**, under the switch, keeps the artists whose name holds every word you type, in any order and
  anywhere in a word. The count then says "3 of 120 artists".
- **The index** down the right edge for Name, once a list has 50 artists or more, as the albums' is.

The list is asked for each time the page comes into view, and with ••• > Refresh; until it comes, what was
last listed shows. If deadwax can't be asked, the list stays as it was, under "Couldn't update this list -
showing it as it was." An empty Your artists says "No artists in your library yet.", with **See All
music**. All artists, pushed from the •••, refreshes when pulled; the page in the switch shuffles, as the
others do.

**An artist's page**: their picture and name, **Play** and **Shuffle**, and **Albums** - their albums in
the collection, newest first (undated ones last), each with its cover, its title, and a line like "1994 ·
in your library", a green tick before it for the ones in your library ("in the collection" and no tick for
the rest). With logins off every album is ticked. **Tap an album** to open its page.

- **Play** plays every album of theirs, in the page's order, each as an album - from the first song of the
  newest. **Shuffle** plays every song of them once, in a random order. With Normalization on, Play levels
  each album as a whole and Shuffle each song on its own, as the web app does.
- As the page opens it fetches every album's songs, four albums at a time, so the music starts the moment
  you tap. Until they're in, the line under the buttons says "Getting the songs of the 3 albums you have…"
  ("in the collection" with a library of your own), and Play and Shuffle are dimmed. Then "Plays the 3
  albums you have". An album that wouldn't come is left out - "Plays 2 of the 3 albums you have - the rest
  didn't load" - with **Try again** under it.
- An artist deadwax no longer has says "This artist isn't here any more - their albums may have been moved
  or deleted."
- Not on the phone yet: the web app's discography from MusicBrainz, the description, the facts, pins, and
  the pictures and names managed from the artist's page. Those come with Search and Get.

**Offline**, the Artists page lists what it last listed, an artist with nothing on this phone dimmed (it
opens nothing). With no list in hand it lists the artists of the albums on the phone, under "Only the
artists of downloaded albums show until deadwax is back." - each named as most of their albums here name
them, so an album they made with someone else ("Portishead & Tricky") doesn't rename them. An artist's page that's one of the last 20 you
opened since the app started shows their albums as it last had them - any other, the ones on the phone -
with the albums not on the phone dimmed, and Play and Shuffle playing only the songs here ("Only
downloaded albums play until deadwax is back.").

## Playing

**The mini player**, above the tabs: the cover, the song and its artist, play/pause and next, and a
thin line along it for how far in the song is. Tap it for Now Playing.

**Now Playing**: the cover (a little smaller while paused), the song's title, and "artist — album"
(tap it to go to the album). Under them:

- **The scrubber**, a squared-off bar that thickens under your finger: tap a place to go there, or drag
  and let go. The clocks say how far in the song is
  and how much is left. VoiceOver reads it as "Position in the song", in 5-second steps.
- **Shuffle, previous, play/pause, next, Repeat.** Previous goes back to the song before in a song's
  first 3 seconds; after that, or on the first song, it starts the song again. Repeat goes from off to
  **Repeat all** to **Repeat one** and back to off, and this phone remembers it.
- **Lyrics**, **AirPlay**, **Up Next**, and **•••** along the bottom. **Lyrics** (the speech bubble) shows
  the song's lyrics in the cover's place (see [Lyrics](#lyrics)). The **•••** menu has **Info**, **Add
  to a playlist…** for the song playing (while deadwax can be reached), **Go to album**, **Download** (or
  Remove Download) for the song playing, **Download Up Next** - every song still to play that
  isn't on the phone, when that's two or more - and last **EQ**, with the output's setting under it
  ("Off", "Bass Boost"), which opens the [EQ](#eq) over Now Playing. Go to album closes Now Playing
  and opens the album's page on the tab you're on. What a download item did is said for a moment at
  the top of Now Playing ("Downloading: Roads", "Downloading 23 songs from Up Next").
- **The speed**, when it isn't 1x: a purple `1.25x` between AirPlay and Up Next - tap it to go back to
  1x. At the largest text sizes it isn't drawn; the **•••** menu's first line says it instead ("Speed
  1.25x - back to normal speed"), and does the same. The speed is set on [the turntable](#the-speed).
- **The button at the top right** shows Now Playing as [a turntable](#the-turntable) instead, and back.
- The chevron at the top, or a swipe down, closes it.

### The turntable

Now Playing has a second look, as the web app's does: the song on a record turning on a turntable.
**The button at the top right** - a round record on the cover, a square on the turntable - switches
between the two for as long as Now Playing stays open. Which one it opens as is **Now Playing opens
as** in [You](#you) > Playback: **Cover**, the default, or **Turntable**. The button never changes
that: close Now Playing and open it again, and it's back to what You says. With lyrics showing, the
button turns them off and shows the other look; **Lyrics** shows them in the record's place, and
turning them off brings the record back.

On the turntable, the record takes the cover's place, as big as fits. The title and "artist — album"
move to the middle, and the time line ("2:31 of 7:05") takes the scrubber's place in the same row, so
nothing below it moves: the buttons and the row under them stay as they are. The two looks crossfade
(at once with Reduce Motion on).

- **The record's face is the album's CD art**: the `disc.jpg` (or `.png`) that the web app's **Get CD
  art** saves beside the tracks, or a disc's own (`disc2.jpg` for a song on disc 2). With none, it's a
  black record with the album's cover as its label. The app asks deadwax for it, so an album with no
  MusicBrainz release in its tags gets the plain record, as on the web. A disc with none is asked again
  the next time Now Playing opens; the app keeps the last eight it has shown, so CD art you replace
  shows once that disc has dropped out of those eight, or the app has started again.
- **It turns at 33⅓ rpm** while the song plays: a turn every 1.8 seconds. Press play and it spins up
  over about 0.4 seconds; pause and it slows to a stop. It doesn't turn while Now Playing is closed,
  the phone is locked or the app is in the background, and with **Reduce Motion** on it doesn't turn
  by itself at all.
- **The arm** moves in from the edge towards the middle as the song plays. **Drag it** to go anywhere
  in the song - its middle end is the song's end. While you hold it, the time line says **Needle up**
  and where letting go will go; the song jumps there as you let go.
- **Tap the record** to pause or play. **Play/pause** under it does the same on the turntable, and a
  pause from either winds the record down (see **Pause winds the record down** in [You](#you)). If
  the song changes while your finger is on the record - it reaches its end under a resting finger,
  say - lifting your finger does nothing to the new song: it plays on, or stays paused, just as the
  change left it, and the record follows it.
- **Turn the record** to move through the song, a turn being 1.8 seconds of it, backwards too. Take
  hold of it while it plays and the song pauses under your finger; turn it and you hear it, faster or
  slower as your hand goes, backwards when you turn it back, and nothing while your finger rests. The
  time line says **Scrubbing**. Let go and the record carries on at your hand's speed: if the song was
  playing, the motor brings the record back up to speed and the song carries on from there, taking
  over from the record's sound; if it was paused, the record coasts to a stop and the song stays
  paused where it stopped - play starts from there. Tap play while a paused record coasts and the song
  starts from where the record has got to.
- **The sound is about an eighth of a second behind your hand** (0.12 s, by design: late enough
  that the touches on either side of each moment have arrived, so the pitch stays steady), and then
  whatever the output itself adds - Bluetooth earbuds add a good deal more. Debug's **Delay behind
  the hand** says what iOS reports of it.
- **Where the record's sound comes from**: a stretch of about 40 seconds of the song round where the
  record is, made on the phone from the song's download, or from the copy the app keeps of a song it
  has played - so it costs no data. A song still coming in has its stretches from deadwax instead
  (small FLAC files, cut from the same copy the phone plays), while the turntable shows and the song
  plays, and as you take hold of the record. Offline, a song that isn't all on the phone yet turns
  silently.
- **FLAC songs only**, as on the web: an MP3 or anything else turns silently, and the first time you
  turn one, a line over the foot of the turntable says **The record makes sound for FLAC songs only -
  this one moves silently.** It stays until the song changes. **Over AirPlay** the record is silent
  too (its sound would come about two seconds late), and the line says **The record makes no sound
  over AirPlay - turning it still moves through the song.** Silent or not, turning it still moves
  through the song.
- **A call or Siri** stops the record's sound, and a record you were holding is let go without the
  song starting into the call. Going Home while it coasts stops its sound at once; come back and the
  song is where the record was going.
- **With Reduce Motion on**, a flick lands where its momentum says at once rather than coasting, and
  a pause doesn't wind down. Turning the record still has its sound.
- **VoiceOver**: after the look button, the record is a button that says what a tap does ("The
  record: a tap pauses the song"), and the arm is "Tonearm: position in the song", read as "2:31 of
  7:05": swipe up or down to move 5 seconds.
- **Closing**: on the turntable, only a swipe down from the top row (or the chevron) closes Now
  Playing - a drag on the record or the arm never does. A record coasting back to speed as you close
  it still hands the song back where it was going.

#### The speed

**The fader** stands at the turntable's right, beside the record, as a record deck's pitch fader does:
slide its knob **up to go faster** and down to go slower, from 0.25x at the bottom to 2x at the top,
1x two thirds of the way up (at the mark, which is green while the speed is exactly 1x). Each octave
is the same distance: 0.25x, 0.5x, 1x and 2x are evenly spaced. As on the web, it's a record deck's
speed, not a time-stretch: the pitch moves with it, and the record turns at it - 50 rpm at 1.5x. A turn
of the hand is still 1.8 seconds of the song.

- **Dragging** starts once your finger has moved a little, from the speed it's at, so a touch never
  makes it jump. The speed follows your finger as you go. Coming back near the mark it snaps to exactly
  1x, with **one small tick** under your thumb, and a drag let go there stays at exactly 1x.
- **The readout** at the turntable's bottom right corner says the speed - `1.00x`, `1.25x` - in purple
  while it isn't 1x. **Tap it** to go straight back to 1x. It stays above a line laid over the
  turntable's foot. At the largest text sizes its words stop growing at what its corner can hold; a
  long press shows them large.
- **The cover** says the speed too, between AirPlay and Up Next (see [Playing](#playing)). The mini
  player doesn't show it.
- **At 1x the song is played exactly as it is**, sample for sample, as it was before the fader existed.
  Leaving 1x, and letting go of the fader at 1x (or tapping back to it), each make a very short gap - a
  few milliseconds - as the song moves into and out of the speed's path. Passing through 1x in the middle
  of a drag doesn't.
- **It stays where you left it**, on this phone, for every song, until you change it - opening the app
  again included.
- **The lock screen's clock runs at the speed**, and how far in the song is stays in the song's own
  time. **Plays** count the song heard, whatever the speed: at 2x a song counts in half the time.
- **One finger at a time**: while you hold the record or the arm, the fader takes no touch, and the
  other way round. The fader's touch area stops short of the record, so the record keeps every touch
  on itself.
- **VoiceOver**: after the arm, the fader - "Speed", read as "normal speed" or "1.25 times"; swipe up
  or down to change it by a hundredth (from 1x, up is 1.01x). Then the readout: "Speed 1.25x: back to
  normal speed", a double-tap going back to 1x - at 1x it says "Speed: normal" and is dimmed. The chip
  on the cover reads "1.25x, 1.25 times the song's speed: back to normal speed".

### Up Next

**Play Next** puts a song (or an album) straight after the song playing; **Play Last** puts it after
the songs you've already added, still ahead of the rest of the album. A line above the mini player
says which ("Playing next: Roads", "Added to Up Next: Dummy") for 5 seconds. With nothing playing,
either just plays it.

**Up Next** on Now Playing opens what plays after the song playing - and, above it, what you've
already played:

- **What you've played**, above the song playing (app 0.8, as the web app's Up Next since deadwax
  2.1.15): one list, the newest nearest the song playing, with no headings, dates or times - scroll up
  and it keeps going, back through every song you've started, on the phone and in the web app. Up Next
  opens at the song playing, even with only a song or two left after it; scroll up for the rest.
  Nearest the song playing is what has played since you started the album, list or shuffle - songs a
  tap skipped past included, where they are on the album; above that, everything you played before it,
  in the order you played it. A song Repeat One played again, or that you started again, is one row;
  Repeat All's earlier times round are there as they played. A song you skipped after a second is there
  like any other. As you scroll near the top the next older songs come, a spinner over the top of the
  list while they do (VoiceOver: "Loading earlier songs") - and nothing you're looking at moves when
  they land. If they can't come, the top of the list says "Couldn't load the songs you played before.",
  with **Try again**. **Tap any of them to go back to it** (as the web app does since deadwax 2.1.18):
  it plays now, from its start, and everything played after it moves back down into Up Next, in the
  order you see it - the songs between, the song that was playing (from its start, when it comes round),
  then Playing Next and the rest of the album or list, as they were. The song you tapped is where your
  finger was. Nothing is lost or reshuffled: songs you added with Play Next that were still waiting keep
  their place, after the song that was playing; with Shuffle on, what comes back keeps the order it
  played in (turned on afterwards, Shuffle shuffles it with the rest - a later time round of Repeat
  All's on its own, after this one's - and off, the album or list carries on in its own order); with
  Repeat One each song's repeats come back with it, and otherwise each plays once. Tap a song from
  before this album or list and everything played since it comes back too, skips included, however
  many - shown as songs to come, not above. Each joins what you've played again as it plays (deadwax's
  record of what you played is never changed). Previous from a song you went back to plays the one above
  it (from one from before the album or list, the song again). VoiceOver calls each row "play again",
  says "Playing" and its title once it starts, and moves to the song that plays next. It reads the songs
  as one list with no heading, then the song playing's title as a heading. With a deadwax before 2.1.18,
  which refuses Up Next's account of a queue you went back in, the app saves that queue as just its
  songs, the one playing and the second (it used to try again every 30 seconds and keep nothing):
  [picked up](#picking-up-where-you-left-off) it comes back as that plain list, every song in order,
  without Playing Next or the Shuffle chip.
  What goes in it, and where it's kept: [What you've played](#what-youve-played).
- **The song playing**, where Up Next opens - and with Repeat One on, "Repeat one: this song plays again
  until you skip it." Under it, **Shuffle** and **Repeat**, the same settings as on Now Playing.
- **Playing Next**: the songs you've added, in the order they'll play, with **Clear** to take them all
  out. It's there only when you've added some.
- **The rest of the album or list this time round**, headed "From Mezzanine" for one album's songs or
  "Still to play" for several albums', up to 100 of them, then "And 380 more songs." Under it, what
  comes after: "Then Mezzanine again from the top." with Repeat All ("Then Mezzanine again, in a new
  order." with Shuffle on too), or "Nothing after this song." at the last song with Repeat off.
- **Tap a song** to play it now, even from a pause. Nothing is taken out: tap a song further down the
  album and the songs between stay where they are, behind it - playing song 5, tap song 8, and Previous
  plays 7, then 6, as on the album - and Playing Next stays next, after it. Tap one in Playing Next and
  the songs added above it are behind it the same way. Up Next puts the song playing back at the top
  whenever it changes - a tap, a song ending, Next or Previous - and when Edit starts or ends; Shuffle,
  Repeat, Clear and Edit's changes leave the list where you've scrolled it.
- **After Previous**, a song you'd added that was still waiting stays where it was - after the song you
  went back from - so Up Next lists it there, in the album's group, rather than under Playing Next;
  **Clear** takes only the songs under Playing Next.
- **Edit** gives each row a handle to drag it by and a red minus button that takes it out at once,
  one tap a song. A song moves within its own group (Playing Next, or the album's), and each change is
  made as you make it. What you've played isn't shown while you edit. **Done** ends Edit. Outside Edit, a row can't be swiped away, so a song isn't
  lost by accident. Inside Edit iOS has no swipe-to-delete, so the minus takes a song out with one
  tap - and there's no undo, so a quick double tap takes out the song that moves up under your finger
  too. With VoiceOver, each row's actions have Move up, Move down and Remove; with Voice Control, say
  "Show grid" to reach a minus.
- It closes by itself once nothing is queued.
- **Downloads**: a song asked for shows the same mark as on its album's page, at the end of its line -
  grey filled for on the phone, dotted while waiting, a ring while it downloads, amber when it didn't
  (VoiceOver reads it after the song: "Roads, play now, Downloaded"). Up Next has no download button
  of its own: Now Playing's **•••** > **Download Up Next** is it. While deadwax can't be reached, songs
  not on the phone are dimmed and a tap on one does nothing; in Edit you can still move or take them
  out. The song playing is never dimmed.

**Shuffle**, turned on while a song plays, keeps that song going and shuffles every song of the album
or list you haven't heard this time round. Turned off, the album's own order carries on from the song
playing. Either way the song playing goes on, untouched, and songs you added keep their order, ahead of
the rest.

### Lyrics

**Lyrics**, at the left of Now Playing's bottom row, shows the song's lyrics in the cover's place, as
Apple Music does: the title, the scrubber and the buttons stay where they are. The speech bubble is
filled and purple while lyrics are on. Tap it again for the cover. Lyrics stay on from song to song,
and each time you open Now Playing, until you tap **Lyrics** again or quit the app.

- **Synced lyrics** (most of what deadwax saves): the line being sung is white, the rest dimmer, and
  it's kept about a third of the way down, the lyrics moving up as each line comes. In a long break,
  or an intro of four seconds or more, three dots light one by one until the next line.
- **Scroll** to read ahead or back: the lyrics stay where you put them, the line being sung still
  lighting up. About four seconds after they come to rest they go back to the line being sung, while
  the song plays. Paused, they stay put until you press play. Scrolling them never closes Now
  Playing; a swipe down from the arrow's row does.
- **Tap a line** to play the song from there, from a pause too.
- **Lyrics saved without timings** show whole, under "These lyrics aren't synced to the song.", every
  line white, and don't move by themselves. Their verses run together, as Navidrome reads them.
- **A song with none** (an instrumental, or none found yet): **Lyrics** is dimmed and does nothing.
  With lyrics on, a song with none shows its cover, **Lyrics** still lit, and the next song with
  lyrics shows them again.
- **"Couldn't load the lyrics."**, with **Try again**, when deadwax couldn't get them just then
  ("Can't connect to deadwax." when the phone can't reach it). "This song isn't here any more - it
  may have been moved or deleted." means Navidrome no longer has the song the queue names: play it
  again from its album.
- The background goes darker under lyrics, so the dimmer lines can be read over any cover.

A song's lyrics are asked for as it starts, whether Now Playing is open or not, so **Lyrics** is right
the moment you open it - never while the phone is locked - and, while lyrics show, the next song's a
little before it starts. They're the lyrics deadwax saved beside each song ([the library
guide](library.md#lyrics) has how), read through Navidrome, as the web app shows them.

**Downloaded songs keep their lyrics**, so they show offline too. A song downloaded before app 0.4
gets its lyrics the next time the app opens with deadwax in reach. Lyrics changed on deadwax (**Get
lyrics**, or re-timed) reach a downloaded song the next time it plays with deadwax in reach. Offline,
for a song with none kept, **Lyrics** is dimmed: "Lyrics - not on this phone". Removing a download
removes its lyrics.

**With VoiceOver**, each line says its words, its time ("1:23", and "now" on the line being sung) and
"Plays from here."; a double tap plays from it. The rotor's Actions have "Go to the line being sung".
While VoiceOver is on a line the lyrics don't scroll away from it. **Larger Text** makes the lines
bigger, wrapping. **Increase Contrast** makes the dim lines brighter and the background darker;
**Reduce Motion** makes the lyrics jump to each line rather than scroll; **Reduce Transparency**
takes away their soft top and bottom edges. Nothing about lyrics is on the lock screen.

### Info

**Info** (Now Playing's **•••**) has an **About** tab:

- **The song**: its title and artist, a line like "Track 4 of 10 · 7:05 · played 12 times", its disc,
  and who wrote it, when Navidrome says.
- **The album**: tap it to go to its page. With logins on, it says which pressing it is, and an admin
  also sees its folder on the server.
- **The artist.**
- **Sound**: the file's **Format**, **Gapless** (always On: the app joins every song end to end), and
  **Normalization**: what was done to this song's level, and from what. For example "Album volume
  matching, 3.6 dB quieter", "Song volume matching, 2.1 dB louder - as loud as it can go without
  distorting", "Measuring the album… (3 of 10 songs)", "Off for this song - only FLAC songs are
  adjusted", or "Off" when Normalization is off. **Plays from**: "This phone - checked" (or "checked
  by size", or "not checked yet") for a song downloaded to the phone, "Streamed from deadwax" for one
  that isn't. **EQ**, only while the EQ is on: what it's set to, on which output, and its preamp -
  "Bass Boost on James's AirPods Pro, preamp -6.1 dB".

An admin also has a **Debug** tab: the file, what was sent to the phone and how it's being played
(**Sent as**, **On this phone** - the downloaded copy's check, and for a FLAC its fingerprint, bits,
rate and channels -, **Normalization** in numbers like "Album, -3.60 dB · the album at -14.4 LUFS",
**Gapless**, **Output**, **Conversion**, **Lane**, **Buffered ahead**, **Last start** and **EQ** -
"Filtering: 4 filters at 48 kHz, preamp -6.1 dB", "Off: every sample passed through untouched" or
"Changing: crossfading to the new curve"), and every field Navidrome sent about the song and its
album.

## You

- **At the top**: who you're signed in as, or "No sign-in needed" with logins off.
- **Playback**:
  - **Gapless**: On. "Albums play straight through, with no gap between songs." It isn't a setting:
    the app always plays this way.
  - **Now Playing opens as**: **Cover** (the default) or **Turntable** - what Now Playing shows each
    time it opens. "What you see first when you open Now Playing. The button at its top right switches
    between the two while it's open." See [The turntable](#the-turntable).
  - **Pause winds the record down**: on by default. On the turntable, a pause - a tap on the record,
    or play/pause while it shows - slows the music to a stop over about a second, as a real record deck
    does, and the song stays paused where the sound stopped. Off, the sound stops at once (the record
    still spins down). Pausing from the cover, the lock screen or the mini player always stops at once.
    Both are kept on this phone.
  - **Normalization**: brings songs to an even loudness, the way the web app's does. Four choices:

    | choice | what it does |
    | --- | --- |
    | **Automatic** (the default) | An album you play keeps one level for the whole album, so its quiet songs stay quiet beside its loud ones. Anything else - a song you add with Play Next, say - is levelled song by song. |
    | **By song** | Every song brought to the same loudness, even the quiet and loud songs of one album. |
    | **By album** | Every song at its album's level, even when it plays on its own. |
    | **Off** | No levelling: every song plays exactly as the file is, bit for bit. |

    Only FLAC songs are levelled; other files play as they are. The level is held under each song's
    peak, so nothing is made louder than it can go without distorting. The first time an album is
    levelled, deadwax measures it, so its first song can take a few seconds to start. It waits 20
    seconds at most, then plays the song as it is that time, and Info says "Not this time - the
    album was still being measured" ("the song was" for a song levelled on its own). One song
    running into the next never waits. The choice is kept on this phone, and takes effect from the
    next thing you play.
  - **EQ**: the output playing now under it ("iPhone speaker", "James's AirPods Pro") and its setting
    at the right ("Off", "Bass Boost", "Custom"). It opens the [EQ](#eq) for that output. Each output
    keeps its own EQ, and it's kept on this phone.
- **Downloads**: what's on this phone ("2.1 GB"), opening [You > Downloads](#you--downloads). Under
  it, only while something is happening: "Downloading - 6 songs to go", what it's waiting for, or, in
  amber, "2 songs didn't download".
- **Account**, with logins on: **Sign out**. It ends this phone's session and stops what's playing.
  With anything downloaded, it adds that your downloads stay on this phone for when you sign in again.
  If deadwax can't be reached, it says "Couldn't reach deadwax, so you're still signed in - try
  again." Changing your password is the web app's, for now.
- **About**: deadwax's version, whether logins are on (for an admin), and the app's own version,
  **0.9 (9)**.
- **This phone**: deadwax's address, **Change address**, and **Debug**, for an admin (with logins
  off, everyone is one).

### Debug

Debug is where Phase 0's test screen lives now:

- **deadwax**: **Check** (it runs as Debug opens) says deadwax's version and whether logins are on.
- **Test sounds**, once Check is OK: the test album's songs. Tap one to play the album from it.
  Each song's row has a download button, **Download all 10** downloads the lot, and **Remove the
  downloads** deletes them - through the app's own downloads, so they go on in the background, wait for
  Wi-Fi unless you've said otherwise, and are checked once here. A song on the phone plays from there,
  as every downloaded song does; **Stream even when downloaded** (under Downloads, below) streams it
  instead, to hear the two side by side.
  At the end, **The record's engine beside the song** and its **Start** and **Stop** buttons. It is
  the turntable's own sound engine, the one [the turntable](#the-turntable) plays its record through.
  Here it plays a run of its own over
  whatever is playing: a chord, taken from 1 second, scratched back and forth twice and let go, over
  and over. Under the button:
  - **The record's engine**: its rate, how many blocks it has rendered, and how many times it has started.
  - **Clock**: how far the record's clock runs behind the audio's time stamps, and the largest lead
    over the last 1.5 seconds.
  - **Messages dropped**: shown only if any were.

  It stops when you leave Debug. These rows are for [the checks](#the-turntables-first-checks).
- **Hi-res**: **Find a 24/192 FLAC** looks through the library (up to 10,000 songs) for a 24-bit
  192 kHz FLAC, or the highest rate there is, to play. This needs a Navidrome that says each song's
  sample rate (OpenSubsonic's `samplingRate`).
- **Playing**: the song, how far in, previous, play/pause and next, and a line like
  `24-bit 192 kHz FLAC file → 48 kHz output (AirPods Pro)`. The app decodes each file at its own
  rate, with nothing changed. When the output runs at another rate, the app's audio engine converts
  the song to it, as any app must: an iPhone's own outputs and AirPods run at 48 kHz or lower. Under
  it, "An edit held for the next song" when one is (see [the checks](#what-only-a-phone-can-tell)), and
  the last song that failed, in its own words.
- **Turntable**: what [the turntable](#the-turntable) is doing, mostly in the web app's own rows.
  Until the turntable has shown, and again once you've switched Now Playing back to the cover, one
  row: "Off: the turntable isn't showing". While it shows - and after you close Now Playing on it, so
  you can read them here - what it last did.
  - **Turntable sound**: "Ready: 1:10-1:50, FLAC, decoded at 48 kHz" - the stretch of the song the
    record can play - or "Off:" and why: no stretch yet, one loading, a song that isn't FLAC, AirPlay,
    the record's engine couldn't start.
  - **Window from**: "This phone's download", "The copy kept on this phone", "deadwax - the song is
    still coming in", or that the phone is offline with the song not all on it.
  - **Voice** (on its own audio thread), **Clock step** (the output's block), **Clock** (as in Test
    sounds, above), and **Data used** - what came from deadwax since the turntable showed.
  - **Turntable timing**: how long after the last let-go of a playing record the song was back.
    **Handover**: how early the song was resumed before the record's sound would end, for the start
    the app expected the audio engine to take, and how long it really took. **Position read in**: the longest the app waited on
    the audio engine for the song's place during the last handover. **Window made in**: how long the
    last stretch took to make on the phone.
  - **Limiter** (peaks held under full scale since the turntable showed), **Frames under a hand** (how
    many were drawn while a hand was on the record, and how many late), **Touches under a hand** (how
    many touch samples a second the screen gave), **Delay behind the hand** (the 0.12 s by design,
    then what iOS says the output adds), and, only when there are some, **Messages dropped**, **Not
    restarted**, **Interruptions** and **Slow starts** (presses whose sound began late because the
    record's engine was slow to start).
  - **Recording**: **Record 20 s** records the record's sound for a bug report - what it played, every
    touch and what the record's engine made of it - as the web app's Debug does, in the same kind of
    file. It begins with the record's next sound ("Waiting for the record's next sound"), so tap it,
    go to Now Playing's turntable and turn the record as you would; 20 seconds later the row says
    "20 s recorded: save the file and send it", and **Save the recording (… MB)** opens the share
    sheet (AirDrop it to the Mac, or Save to Files). A file is 15-30 MB: it carries the sound as it
    was made and the part of the song the record played, so the Mac can play it again exactly. The
    20 seconds count from the first sound, rests included: a recording whose 20 seconds end while the
    record is still finishes then. **Record 20 s again**, under the save button, starts another (the
    saved file is deleted; the app keeps only the newest). Until the turntable has shown, the row
    says "Shows the turntable first: the recording is of its sound".
    On the Mac, `swift run --package-path ios/DeadwaxKit replay-deck-recording <file>` plays it again
    through the app's own code and says whether it made the same sound (it should, to the bit). The
    same command takes a recording from the web app's Debug, with `--song <the song's file>`.
  - **Speed**, last, whether or not the turntable has shown: "Normal (1.00x) - the song as it is,
    nothing changed", or "1.25x, the pitch moving with it". After a few seconds of playing, a note
    under it says how fast the song is really moving: "The song moved at 1.25x over the last few
    seconds of playing" (the last 8 seconds, once there are 2). A new speed starts that count again.
- **EQ**: what the [EQ](#eq) is doing. **Output** is the route as iOS gives it - each output's kind,
  name and ID, raw ("Bluetooth (A2DP) · James's AirPods Pro · 60:F8:…"), one line each - and **Key**
  the name the EQ keeps that output's setting under. Then the EQ's audio unit, which sits between the
  app's mixer and the output whether the EQ is on or not. **Unit** says what it is doing: "In the graph: passing every sample through" (off: every
  sample goes out exactly as it came in), "filtering", "crossfading" (a change is fading in, over 20
  ms), "the output is stopped" (paused), "waiting for its first block of sound" (only for a moment as
  the output starts), or "Not made" with the reason, when the phone couldn't make it - or the output
  has more than 8 channels - and the music plays on without it. **Render block** says whether iOS
  asked the unit for the part that does its work: "iOS asked for it 3 times" or so (twice as it's
  made, once each time the output starts); "iOS hasn't asked for it" means no sound can go through
  the EQ, and is worth telling me. **Curve** is what the output's EQ is made of - for Bass Boost "4
  tone bands", the curve's top (+6.0 dB) and where, and "preamp -6.1 dB (automatic)" - or "Off"; **At this rate** is the output's
  rate and how many filter sections each channel runs; **Changes** counts the crossfades, the changes
  that waited for the one before, and any made for another rate; **Started with** is what was put in
  as the output last started ("James's AirPods Pro's curve, put in 0.1 ms before the output
  started"), and **Start took** how long putting it in took - "0.016 ms, its curve made ahead" when
  it was ready, as it should be, or "its curve made then, for 44.1 kHz" at a rate the output hadn't
  started at before; **Over full scale** counts the samples the EQ pushed past the loudest a file can
  hold; **Render** is how long the EQ takes per block of sound, against how long the block lasts;
  **Kept** is what eq.json holds ("eq.json: 3 outputs, 1 preset of yours, 1.2 KB"), or the name an
  unreadable one was set aside under.
  **Muffle what plays** is a test, for the checks below: it puts a steep treble cut (a -24 dB high
  shelf at 2 kHz) through the real unit, so whatever plays sounds muffled at once, and plain again
  when you turn it off, the output's own EQ again. It turns itself off when you leave Debug (locking
  the phone doesn't), and it's off each time the app opens.
- **Engine log**: the app's audio engine says what it does, line by line - each song's lane starting,
  joins, a buffer played, a stream that ran dry, an edit held for the next song, a failure - and Debug
  keeps its last 500 lines, the newest last. While a song plays it writes about two lines a second, so
  that's about four minutes of playing. **Copy** puts the whole log on the clipboard and **Share** sends
  it on (Mail, Messages, Files...). Once it holds 500 lines the oldest go as new ones come, so the lines
  move up while you read; Copy keeps them still. Each line starts with a time in seconds on the phone's
  clock: the gaps between lines are what count. The engine writes nothing that could sign anyone in, and
  before keeping a line the log takes out the usual forms of one anyway: a password, token or session
  given as a value (with = or :), a cookie or sign-in header, and a password in an address. The
  same lines go to the Mac's **Console** app as they happen, for longer than Debug keeps them: with the
  iPhone connected, choose it in Console's sidebar, turn on **Action > Include Info Messages**, press
  Start, and search for `subsystem:net.lizardlounge.deadwax`.
- **Downloads**: **Stream even when downloaded** (off again the next time the app opens); how many
  songs are in each state (wanted, fetching, done, failed) and their bytes; the background downloads
  iOS holds (running, waiting, and how many can carry on from where they stopped); whether deadwax can
  be reached, the phone's network (Wi-Fi, cellular, expensive, constrained) and the last check of
  deadwax; plays waiting to be sent, and songs started that deadwax hasn't taken into your play history
  yet (**Starts waiting to be sent**); how long the sound checks took; and the last 50 download events
  (a backlog of starts sent, or one deadwax refused or couldn't take, is one of them).
- **Your library**: what [Download your library](#your-library-on-this-phone) follows - it's turned
  on and off in You > Downloads (this section had its own switch while that was being built). On, it
  asks deadwax for your library - the albums you've added, or with logins off every album deadwax
  holds - and reads each album's songs, four at a time, in the order they come onto the phone: the
  album you added or played most recently first (a play counts for 30 days).
  - **Following**: your library, or the collection.
  - **Albums**, and **Songs read**: of the albums listed, how many have had their songs read
    ("reading 4" while it reads).
  - **Missing**: albums the last list didn't have. One goes only when a second check, ten minutes or
    more after the first that missed it, agrees - "1 (the first 3 min ago)". An album you remove with
    **Remove from my library** goes at once.
  - **Held back**: "No", or why the last list's missing albums weren't believed: deadwax listed none,
    more than half went at once, or the list stopped at 10,000 albums. Nothing goes then. "believing
    (Remove)" after you answered Remove to You > Downloads' question, "kept them" after Keep Them.
  - **Removed, to let go**: albums a check removed whose downloads haven't gone yet (usually 0).
  - **Leaving their albums**: songs a read found had left their album, waiting for the second read
    ten minutes on ("None", or "3 songs on 2 albums").
  - **Last check**: "200 · 3,010 albums" (a new list), "unchanged (304)" (the same list as last
    time - one small request), or "failed:" and why; how long it took; when.
  - **First read**: how long reading every album's songs took the first time, and the time per album.
  - Then what fits: "412 of 3,010 fit in 20 GB" at your storage limit, after everything you've
    downloaded yourself, and under it what those take and why the rest wait (over the limit, no room
    on the phone, not read yet, removed by you). When the phone is under its 2 GB, in amber, by how much:
    "500 MB under the reserve · confirming" for the first few minutes, then "· giving way".
  - **Check now** checks at once. It also checks by itself: as it's turned on, as the app opens, when
    you come back to the app (if the last check was a minute or more ago), every 15 minutes while the
    app is open or playing, when deadwax answers again after it couldn't be reached, and straight after
    Add to or Remove from my library - and when iOS runs the app in the background for it. Each check
    is a line starting "library" in the Downloads events above.
  - **Power**: the phone's power as Only while charging reads it - "Charging", "Full, on the charger",
    "Not charging" or "Not known" - and "only while charging" when that's on. **Albums out**: how many
    of your library's albums have downloads handed to iOS now (with Only while charging on, never more
    than one).
  - **In the background**: the last five times iOS ran the app in the background for your library,
    newest first - "Refresh · checked, 3 read, 1 album downloading, charging · 4.20 s · 2 h ago" (the
    refresh, or **Charger** for the run iOS starts when the phone is plugged in), or "ended by iOS",
    "couldn't ask deadwax", "nothing to ask: Download your library is off". "No background runs yet"
    until iOS has run one: iOS decides when, and may not at all. A run before the phone's first unlock
    after a restart does nothing and isn't listed (the Downloads events say so).
- **Library**: how many albums each list had, whether it came new or the kept one still stood, and
  how long it took to come.
- At the bottom, how long this install runs. In its last two days, it also says to run install.sh
  before then.

## EQ

The EQ shapes the sound on this phone, **for each output on its own**: your AirPods, wired
headphones, the iPhone's speaker, the car, an AirPlay speaker each keep their own EQ, and the phone
switches to the right one by itself whenever the output changes - AirPods connecting mid-song have
their own EQ from the first sound in them. An output the phone hasn't met before starts **Off**.

Open it from **You > Playback > EQ**, or from Now Playing's **•••** > **EQ**, which opens it over Now
Playing (**Done** closes it). Either way it opens on the output playing now.

**The EQ page**, top to bottom:

- **The output**: its name and "Connected now" (or "Not connected"), and the **EQ** switch. Over
  AirPlay, a note says a change is heard about 2 seconds later.
- **The curve**: what you hear on that output, low notes on the left and high on the right, louder
  above the middle line and quieter below. It goes grey and flat while the EQ is off. The line under
  it says what is happening: "Off: nothing changes the sound.", "Flat: nothing changes the sound
  yet.", the preamp - "Preamp -6.1 dB, so loud songs don't clip." (below) - or, for a curve that
  only cuts (Bass Reduce, Treble Reduce), "Cuts only: nothing gets louder."
- **Correction**: **Correction**, "None" or the correction's name at the right and where it's from
  under it ("AutoEq, measured by crinacle"), which opens the correction picker - and, for Bluetooth
  and USB headphones with no correction yet, AutoEq's suggestion for them (see
  [AutoEq](#autoeq-a-correction-for-your-headphones) below). With both a correction and a tone, the
  curve is the two together, with the correction alone as a thin dashed line.
- **Tone**: **Preset**, which opens the list of presets (below), then **ten sliders**, one for each
  band from 31 Hz to 16 kHz, each from -12 to +12 dB in half-decibel steps. Touch anywhere in a
  slider's column and drag up or down: the knob goes with your finger from wherever it was (it never
  jumps to your finger), and the sound follows as you drag. There's a small tick under your thumb as
  it reaches 0. Double-tap a column to put it back to 0. Moving a slider makes the tone **Custom**,
  and then **Save as Preset…** keeps it under a name of yours.
- **Other outputs**: every other output the phone has met, the most recent first, with the iPhone
  speaker always there, and each one's setting ("Off", "Bass Boost"). Tap one to open its own EQ
  page, which stays on that output. Swipe one for **Rename** and **Forget** (not the speaker).
  Other outputs shows only on the page of the output that's playing.
- On the page of an output that isn't connected: "Not connected: this is what it plays when it is."
  above its curve, and **Forget This Output** at the bottom. Forgetting asks first ("Forget James's
  AirPods Pro? Its EQ is deleted. It starts Off next time it connects."), as Forget does in Other
  outputs.

The **•••** at the top has **Rename…**: give an output a name of your own; leave it empty to go back
to the name iOS gives it.

**While the EQ is off, everything still works, and any change turns it on**: choosing a preset or
moving a slider switches it on (VoiceOver says "EQ on"). Turning the switch off brings back the
sound exactly as it was: off, the EQ passes every sample through untouched.

**The page follows the output.** Opened from You or Now Playing, it changes to the output that's
playing when that changes (VoiceOver says "EQ for James's AirPods Pro") - but not while your finger
is on a slider, and not while something is open over it; it catches up when you let go or come back
to it. The presets page always stays with the output it was opened for: a preset chosen there goes
to that output even if it was disconnected meanwhile, and the top of the page says so ("James's
AirPods Pro isn't connected: changes are kept for when it is.").

**Presets.** Choosing one moves the sliders there and turns the EQ on; the page stays, so you can
listen through several. **Custom** is at the top while your own slider positions are in use, and
stays for as long as the page is open, so you can try a few presets and go back to where you were.

| preset | what it does |
| --- | --- |
| Flat | Nothing changed. |
| Bass Boost | More low end. |
| Bass Reduce | Less low end. |
| Treble Boost | More sparkle and air. |
| Treble Reduce | Softer highs, for bright recordings or headphones. |
| Vocal | Voices brought forward. |
| Loudness | For listening quietly: the lows and highs lifted, as ears hear less of them at low volume. |
| Small Speakers | For small speakers that can't play deep bass: the upper bass lifted instead. |
| Spoken Word | For podcasts and audiobooks: rumble cut, voices clearer. |

Your own presets are listed under **Your presets**: swipe one for **Rename** or **Delete**. A name
can be up to 40 characters, and can't be one already used, a built-in's included, whatever its
capitals or accents ("There's already a preset called "Bass Boost"."). Deleting a preset an output
uses leaves that output's sliders where they were, as Custom. Presets are shared by every output;
each output keeps which one it uses.

**The preamp.** Neighbouring bands overlap, so the curve can go a little past a slider's value:
Bass Boost's +5 dB slider makes about +6 dB of bass. So nothing ever clips, the EQ turns every song
on that output down by the curve's highest boost - "Preamp -6.1 dB" for Bass Boost - and never turns
anything up. That's why everything sounds a little quieter with a boost on: the volume buttons give
it back. A curve that only cuts needs no preamp, and the line under it says so: "Cuts only: nothing
gets louder."

**The sound.** Every change - a slider, a preset, the switch, another output - fades in over 20
milliseconds, so it never clicks. When an output starts, its EQ is in place before its first sound.

**Where it's kept.** On this phone, in the app's own storage (`eq.json`, which the phone's backup
keeps): it belongs to the phone, not to whoever is signed in, so signing out or in as someone else
keeps it, and nothing of it goes to deadwax. If the file ever can't be read, it's set aside (Debug
says under what name) and every output starts Off.

### AutoEq: a correction for your headphones

Every pair of headphones changes the sound on its way to your ears - a bump in the bass, a peak in
the treble. [AutoEq](https://github.com/jaakkopasanen/AutoEq), Jaakko Pasanen's project, works out a
**correction** for each headphone measured by oratory1990, crinacle, Rtings and its other sources: a
set of filters that evens that out, so the headphones sound neutral. The EQ plays one as the
headphones' correction, with your tone on top: Bass Boost on corrected AirPods is Bass Boost on
neutral ones. A correction is a starting point - how in-ears sit in your ears changes what you
hear - so listen, and turn it off and on to compare.

The phone never talks to GitHub: deadwax searches its own copy of AutoEq's list and fetches the
correction you pick (see [AutoEq's corrections](../README.md#autoeqs-corrections-for-the-iphone-apps-eq)
in the README for what the server does). Once you've used one, it's kept on the phone with the
output's EQ, and plays without deadwax.

**The suggestion.** On the EQ page of Bluetooth or USB headphones with no correction, deadwax is asked
once each time the app runs whether AutoEq has the headphones' name - the name iOS gives them, with
an owner's "James's " taken off: "James's AirPods Pro" asks for "AirPods Pro". What it finds shows
under the Correction row:

- **One headphone**: "AutoEq has a correction for Sennheiser HD 650", "Measured by oratory1990".
  Tap it for its page. A headphone AutoEq has measured in more than one condition - "Sennheiser HD 650
  (2020)", "(balanced)" - counts as the one headphone, and the plain one is offered.
- **Several**: "AutoEq has corrections for AirPods Pro", "16 models - pick yours" (as many as AutoEq
  has). Nothing is picked
  for you. Tap it for the picker, with "AirPods Pro" already searched and the models under
  **Suggested for James's AirPods Pro**. A name with another word in it is another model - "Apple
  AirPods Pro 2" isn't the AirPods Pro, "Beats Studio Buds +" aren't the Beats Studio Buds - so it
  is a choice even when it's the only one AutoEq has.
- **Nothing** (a speaker, a car, a name AutoEq doesn't have): no row.

It's only ever a suggestion - nothing changes until you tap **Use**. Swipe it for **Not now** (or
use VoiceOver's action) and it doesn't come back for those headphones. It isn't shown offline, or
once the headphones have a correction.

**Picking AirPods.** iOS calls the first AirPods Pro and the AirPods Pro 2 both "AirPods Pro", so the
name can't tell which you have, and the app always lets you pick. The first generation is **Apple
AirPods Pro**. For the **Pro 2**, crinacle measured them fourteen ways - at eleven listening levels
with noise cancelling on ("Apple AirPods Pro 2 (51dB + ANC)" to "(91dB + ANC)"), and in noise
cancelling, passive and transparency modes; pick the mode you use, and with noise cancelling the
level nearest how loud you listen. "Apple Airpods Pro 2" (HypetheSonics, Harpo, Filk) and
Rtings' "Apple AirPods Pro2" are the same model, measured by others. The same goes for other
headphones that have had a second generation under one name.

**The correction picker** (Correction on the EQ page), for the output it was opened from:

- **None** (ticked when there's no correction) takes the correction away and goes back. The
  correction there is, ticked, goes back keeping it.
- **Suggested for …**, when there's a suggestion.
- **Find your headphones**: type a name or a model - "hd650" and "hd 650" both find the Sennheiser HD
  650. It searches as you stop typing. Each result is one headphone, with who measured it, its form
  ("crinacle · in-ear") and how many more measurements there are ("3 more measurements"). No match
  says "AutoEq has no headphones called "xyz"." - try the model alone.

**A correction's page**: the correction's curve on its own, who measured it and on what ("Measured
by crinacle, on a 711 rig (in-ear)."), its filters and the preamp AutoEq gave it ("10 filters,
preamp -6.0 dB"), then **Use for James's AirPods Pro**. Use makes it that output's correction,
turns the EQ on if it was off, and takes you back to the EQ page. Once used, the button says "Used
for James's AirPods Pro". **Other measurements** are the same headphones measured by other sources,
each with its own page. At the foot, **AutoEq on GitHub** opens AutoEq's page in Safari (the music
keeps playing).

Like the presets, the picker and a correction's page stay with the output they were opened for: take
the AirPods out while reading and **Use for James's AirPods Pro** still puts it on the AirPods - kept
for when they're back - never on the speaker, and the top of the page says they aren't connected.

**When it can't.** Offline: "Can't connect to deadwax." and "Check your connection." with **Try
again**; the correction you have plays on. deadwax unable to reach GitHub: "deadwax can't reach
AutoEq just now." (see [AutoEq can't be reached](troubleshooting.md#autoeq-cant-be-reached)). A
correction AutoEq no longer has: "AutoEq doesn't have that measurement any more." A deadwax older
than 2.1.7, which has no AutoEq: "Something went wrong." (an admin sees why, folded under it). If
AutoEq ever changed its files so the app can't read one: "deadwax couldn't read this correction."

**Thanks.** The corrections are AutoEq's (MIT licence, Copyright (c) 2018-2022 Jaakko Pasanen), made
from measurements by oratory1990, crinacle, Rtings, Super Review, Innerfidelity, HypetheSonics and
AutoEq's other sources - the measurements are theirs.

**VoiceOver and text sizes.** The curve is one item that says its shape ("Up to 6 decibels louder in
the bass. Preamp minus 6.1 decibels.") - and the rotor's **Audio Graphs** has **Play Audio Graph**,
which plays it as a rising and falling tone. Each slider is one adjustable item ("125 hertz, plus 3.5 decibels"): swipe up or down
to move it a decibel, and its actions include **Reset to 0**. At the largest text sizes the ten
sliders become ten rows, each with a - and + button. With Reduce Motion, the curve and the sliders
jump to a new setting rather than gliding.

**Headphone Accommodations.** iOS's own Headphone Accommodations (Settings > Accessibility > Audio &
Visual), on AirPods and some Beats, shapes the sound after deadwax's EQ, on every app. With a
correction on, turn it off - otherwise the two stack, and the headphones no longer sound neutral.
Spatialize Stereo works after the EQ too: whether a correction still sounds right with it on is for
your ears.

### Advanced: your own filters, the preamp, and Equalizer APO files

**Advanced**, a switch at the bottom of the EQ page, opens up what the EQ is made of: a correction's
filters to see and change, filters of your own, the preamp set by hand, and correction files to
import and export in [Equalizer APO](https://sourceforge.net/projects/equalizerapo/)'s format - the
one AutoEq's ParametricEQ.txt files are in. It's one switch for the whole phone, and turning it on or
off changes nothing you hear, only what the EQ page shows.

**The curve** grows taller, with a **handle** - a small circle - for each correction filter that's
on. Touch one (or near it) to select it: it turns white, and its numbers show above the curve
("Peak · 8903 Hz · +6.0 dB · Q 1.66"). Drag it sideways for its frequency (to the hertz under 1 kHz,
ten hertz above), up and down for its gain (a tenth of a decibel), and pinch for how wide it is. The
sound follows as you go. A touch on the curve away from the handles scrolls the page as usual.

**Correction** lists the filters under the Correction row, low notes first, as the handles run left
to right. Each says its type - "Peak", "Low shelf", "High shelf", "Low pass", "High pass", "Band
pass", "Notch", "All pass" - and under it its numbers: "105 Hz · +2.6 dB · Q 0.70" ("BW 1.0 oct" for a
width in octaves, "12 dB/oct" for a shelf's slope, "Left" or "Right" after it for one ear's filter).
Each has its own switch. A filter above the highest note an output plays says "Above what this
output plays, so it's left out." Tap a filter to edit it; swipe it for **Delete**. Under the
filters:

- **Add Filter**: a peak at 1000 Hz, 0 dB, Q 1, opened for you to edit. You can add up to 64 filters
  for each ear; past that it says "64 filters is the most you can add". (A file can bring up to 74 -
  see Exporting, below - and every one of them can be changed, switched, deleted and moved between
  the ears; no change takes an ear past 64, or past as many as it had.) Adding a filter with no
  correction yet starts "Your own filters"; deleting the last of them leaves the output with no
  correction.
- **Import from Files…**, **Paste** and **Export…** (below).

Changing an AutoEq correction makes it yours to change: it reads "AutoEq, measured by crinacle -
changed", and **Back to AutoEq's** - touch and hold the Correction row, or in the **•••** at the top -
puts AutoEq's back as it came. A correction from a file says so the same way once you change it -
"From HD650 ParametricEQ.txt - changed", "From the clipboard - changed" - and an export of it says so
in its comment; to have the file's back, import it again.

**A filter's editor** ("Filter 3", its place in the list): its own curve with its handle, then

- **Type**: changing it keeps the frequency, and the gain and width where the new type has them.
- **Frequency**, in hertz, with a slider from 20 Hz to 20 kHz under it. A shelf filter that a file
  gives by its corner says so: "Its corner frequency, as Equalizer APO reads this shelf - it is
  centred at 131 Hz."
- **Gain** (peaks and shelves), in dB, with - and + of a tenth of a decibel.
- **Q** - or **Width** in octaves, or **Slope** in dB an octave, as the filter was written - with - and +;
  a width or a slope has **Use Q instead**, which turns it into the Q that plays the same. A filter
  with no width shows its type's own ("0.71") greyed in the field. A shelf written `LS` or `HS` with
  no width keeps its place when you give it one, and is exported as `LSC` or `HSC` - by its centre,
  as it plays - since Equalizer APO reads an `LS` with a Q by its corner.
- **Ear** (only when the correction has filters for one ear): Both, Left or Right.
- **On**, and **Delete Filter**.

Type a number and tap Done on the keyboard (or move to another field) to use it; a decimal comma or
point both work. A number out of range stays in the field in red, with what's allowed under it -
"Between 1 and 22000 Hz.", "Between -30 and 30 dB.", "Between 0.01 and 100." (a Q), "Between 0.01
and 10." (a width), "Above 0 dB an octave." (a slope), "Too steep for this gain - at most 19.6 dB
an octave.", or "Too gentle to make a filter." (a slope so near 0 it makes none) - and nothing changes
until it's in range. The editor stays with the output it was
opened for, as the presets page does.

**Preamp**, after Tone: **Automatic**, on by default, is deadwax's own (above) and shows what it is
("-6.4 dB"). Turn it off to set it yourself, in tenths of a decibel from -30 to +12 dB, for every
song on that output; it starts where Automatic was, so turning it off changes nothing you hear. If
yours takes away less than the curve's highest boost, it says "Loud songs may clip: the curve boosts
2.1 dB more than this preamp takes away." - here and under the curve.

**Importing a file.** Three ways in:

- **Import from Files…** on the EQ page, for a `.txt` file in Files or iCloud Drive.
- **Paste**, iOS's own button, for an Equalizer APO setting copied as text - iOS doesn't ask first.
- **From another app**: share a `.txt` file to deadwax - AirDrop it from your Mac, or save it from
  Safari, Mail or Files and choose **deadwax** among the apps. The app opens with the file's preview
  over whatever was showing. deadwax gets a copy, and deletes it once read.

Each shows a **preview** first: where it's from ("From "HD650 ParametricEQ.txt"" or "From the
clipboard"), **For** - which output it goes on, the one playing first (from an output's own page,
that output), and any other the phone has met - the curve of what was read, what it is ("10
filters, preamp -6.4 dB"), the preamp it will play at, what it replaces ("It replaces the correction
for James's AirPods Pro (Apple AirPods Pro, from AutoEq).") and anything **Skipped**. **Import** makes
it that output's correction and turns the EQ on; **Cancel** changes nothing. A pasted correction
reads "Pasted", "From the clipboard" under it.

**What it reads** is what Equalizer APO itself plays, read the way Equalizer APO reads it, so a file
sounds the same here as there:

- `Preamp: -6.4 dB`; `Filter 1: ON PK Fc 105 Hz Gain 2.6 dB Q 0.70` and the other filter types
  (`LSC`, `HSC`, `LS`, `HS`, `LP`, `LPQ`, `HP`, `HPQ`, `BP`, `NO`, `AP`, `PEQ`, `Modal`), with `Q`,
  `BW Oct` or a shelf's slope (`LSC 12 dB`); `OFF` filters, kept switched off; `Channel: L`, `R` or
  `all`, for filters for one ear; one `Device:` line at the top, skipped.
- `GraphicEQ:` (AutoEq's GraphicEQ.txt, Wavelet's): turned into up to 61 filters close to its curve,
  and the preview says how close - "Converted from a GraphicEQ curve: 54 filters, within 0.1 dB of it
  on average and 0.5 dB at most up to 16 kHz; above that, up to 3.8 dB." It's then filters like any
  other, its row "From Wavelet.txt, converted".
- Words and units as Equalizer APO wants them, capitals included: `Preamp`, not `preamp`; `Fc 100 Hz`,
  with the `Hz`; `Gain 6 dB`, with the `dB`. A line Equalizer APO wouldn't play is skipped, as it
  would be there, and the preview says which and why ("Line 9 isn't something Equalizer APO plays
  either (Volume: 5)."). A comma for a decimal point is fine. Lines starting `#` are comments.
- Up to 256 KB, in UTF-8 or Windows' own text; a UTF-16 file (Notepad's "Unicode") is read too, with
  a note that Equalizer APO doesn't read it.

**Refused**, the whole file - "Can't import this file" and why, with only **Done** - when it would
play differently here than in Equalizer APO: another file included (`Include:`); what deadwax can't
play (`Convolution:`, `Delay:`, `Copy:`, `Eval:`, `If:`, `Stage:`, `VSTPlugin:`,
`LoudnessCorrection:`, `IIR` filters); settings for several devices; lines ending the old Mac way;
a number out of range (a frequency over 22000 Hz, a gain or preamp over 30 dB, a number too large to
read at all); a shelf too steep for its gain, or with a slope so near 0 it makes no filter; more than 74 filters for one ear; or nothing in it to play. For whoever runs deadwax,
the line it stopped at shows under the reason.

**Exporting.** **Export…** has **The Whole Curve** - the correction and the tone together, with the
preamp as it plays, so Equalizer APO on a PC (or any app that reads its files) plays what you hear -
and **The Correction Alone**, its filters and its own preamp. Each is a file named after the output
("James's AirPods Pro EQ.txt") for the share sheet: Files, AirDrop, Mail. **Importing a whole curve
back** onto an output with a tone plays the tone twice - the file holds it already - so set that
output's tone to **Flat** first, or export the correction alone. **deadwax reads back what it
exports**: a file can hold up to 74 filters for one ear - the 64 you can add, and the tone's ten
sliders, which The Whole Curve writes as ten more filters - so a whole curve made from your own
filters, AutoEq's or a file within 64 (a converted GraphicEQ is at most 61) reads back whatever the
tone. The one export that doesn't: a whole curve that was itself imported back, exported again with a
tone on top (up to 84 for an ear) - set its tone to Flat first, as above, and it reads back.

## The lock screen and interruptions

The lock screen and Control Center show the song, its artist, album, cover and how far in it is. The
next song's cover is fetched while a song plays, so the lock screen's cover changes with the song.
Play, pause, next and previous work there, as does dragging the position, and the AirPods' presses
work too. At [a speed](#the-speed) other than 1x its clock runs at that speed. A phone call or Siri pauses the music, and it carries on when they're done. Taking an
AirPod out pauses it.

## Plays

A song is counted as played in Navidrome once you've heard half of it, or 4 minutes, whichever comes
first - of the song's own time, at any [speed](#the-speed): at 2x that comes in half the time. Songs of
30 seconds or less don't count. That's the rule the web app uses, and Last.fm's.
Navidrome passes plays on to Last.fm or ListenBrainz if it's linked to them, and is told what's
playing now. A play that can't be sent - deadwax out of reach - is kept on the phone with its time and
sent once deadwax answers again (see [The first time you open it](#the-first-time-you-open-it)).

## What you've played

Every song that starts playing on the phone goes into your play history on deadwax - the one Up Next
scrolls back through, here and in the web app (see [Up Next](#up-next)). It goes in at the song's first
sound, the moment Navidrome is told "now playing", skips included:

- **Not a new song**: pausing and playing again, seeking (the arm or the record on the turntable too),
  a wait for the network, a song tried again from where it stopped, or a change of
  [speed](#the-speed). The next song, Previous, Repeat One playing a song again and a tap in Up Next
  are each a new one - though a song started again straight after itself shows as one row.
- **Picked up where you left off**: a queue put back paused in the middle of a song carries on that
  song's play - it was already in the list when it began, on whichever device began it - so it isn't
  added again. Put back at a song's start, it's a new one.
- **Offline**: a song started with deadwax out of reach shows in Up Next at once, and is kept on the
  phone (in your own downloads' store, so closing the app doesn't lose it) until deadwax answers - then
  sent, oldest first, before the [plays](#plays) waiting with it, up to 500 at a time. A week away is
  sent in one go of several batches. If deadwax answers but can't take them just then, the phone tries
  again 30 seconds on, then a minute, two, and so on up to every 10 minutes, and at the next song.
  Signed out, they wait for you to sign in again as the same person; they're never sent for anyone
  else. If the phone can't read that store ("This phone couldn't read its downloads"), the songs you
  start are held while the app is open and sent from there.
- **The newest 100** are also kept on the phone each time they come, so Up Next shows what you played
  lately with deadwax out of reach. Older ones need deadwax.
- **Kept by deadwax, for ever** - with logins on, each person's own; with logins off, one list for
  everyone who uses this deadwax. There's no Clear, here or in the web app. Removing someone in People,
  or Forget, takes theirs with the rest of what deadwax kept for them.

Up Next asks deadwax for the newest songs each time it opens, again when you come back to the app with
it open, and again when the network comes back with it open, so what you played in the web app meanwhile
shows. Offline it doesn't ask: it shows what the phone kept, with no "couldn't load" line unless you
scroll past that for older songs.

## Picking up where you left off

The app saves what you're playing in Navidrome, as the web app does: the queue (up to 2,000 songs, 50
of them before the one playing), the song, and how far in. It saves every 30 seconds while playing,
at each pause and change of song, and as the app goes to the background.

When the app opens with nothing playing, it puts back what you were last playing, paused at the
second it stopped, from whichever device saved it last: the web app, or another app on Navidrome. A
notice says where it came from ("Picked up from your Mac", "Picked up from Symfonium"; with logins
off, "Picked up from a Mac"). Nothing is fetched until you press play. It's put back with this phone's
Repeat and Normalization. The web app picks up the phone's queue the same way ("Picked up from your
iPhone", or "Picked up from an iPhone" with logins off).

A whole library's shuffle comes back however many songs in it is - its order, and its next songs
coming as before (until this build, one some 750 songs in came back as the songs fetched so far, which
then stopped). A queue you went back in comes back with every song you'd played on to still to come,
going back a second time included (until this build, going back again after changing Up Next while
the furthest song you'd got to played could come back without the songs played since).

Coming back to the app while paused, it looks again (at most every 15 seconds). With logins on, it
takes what another device saved since this phone last did. With logins off everyone shares one queue,
and a paused phone never takes somebody else's. The break-glass `deadwax` keeps no queue.

The phone also keeps the queue it last saved or picked up, in your own downloads' store on the phone:

- **Opened with deadwax out of reach** (Airplane Mode, WireGuard off, deadwax or Navidrome down), it
  puts that queue back, paused where it stopped, with no notice - so a phone opened on a plane still
  has what you were playing. Songs not on the phone are passed over as they come (see
  [Offline](#offline)).
- **A save that couldn't be sent** (no network, or the app closed before deadwax answered) is kept
  too. The next time the app opens, or you come back to it, it first asks deadwax what it has: if
  another device or app saved a queue since this phone last saved or picked one up, that one wins and
  is picked up as usual; otherwise the phone's own goes. While music plays, saves go as they always
  do. A save refused because you were signed out waits for you to sign in again as the same person;
  it's never sent for anyone else.

## The songs kept on the phone

Songs come as they are: a FLAC as FLAC, an MP3 as MP3. Only Ogg, Opus and WMA files come as MP3,
because iOS can't play them. The app starts playing as a song arrives, and fetches the next one ahead
of time.

Once a song has all arrived, it's kept on the phone, so playing it again doesn't fetch it again. Up to
2,000,000,000 bytes are kept (2 GB, as iOS's Storage screen counts), and the songs played longest ago
go first. iOS may also empty them when the phone runs short of space, and songs are then fetched
again. A song you skip past before it has arrived is let go, and its part deleted. This isn't a way
to play offline - iOS may empty it at any time - but a song kept whole when deadwax can't be reached
plays from it. To be sure of a song, download it: downloads are apart from these 2 GB, and are never
removed but by you.

## Downloads

Download an album from its page (the arrow at the top right), a song from its **•••**, or what's
still to play from Now Playing's **•••**. A downloaded song is the very file deadwax has - a FLAC as
FLAC, an MP3 as MP3 (Ogg, Opus and WMA come as MP3, which iOS can play) - and it's what plays from then
on, online or not, bit for bit as deadwax sent it, through the same seamless joins and the same
normalization as a stream.

- **In the background.** Downloads carry on with the app in the background and the phone locked, as
  iOS allows. Closing deadwax from the app switcher stops them until you open it again.
- **Checked once here.** Each song's size is checked against deadwax's file, and a FLAC's sound
  against the fingerprint the file carries, so a copy that arrived damaged is fetched again (three
  tries). A song plays before its check is done.
- **Waiting.** A download waits, and says so, for Wi-Fi (see Download over, below), for a connection,
  for deadwax, for you to sign in, for room under the storage limit, or for space on the phone, and
  starts by itself when it can. Your library's own downloads can also wait for the phone to charge
  (see [Only while charging](#your-library-on-this-phone)).
- **Removing** one album or song needs no confirmation: it can be downloaded again. **Remove All
  Downloads** asks first.
- **Per person.** Each person signed in on the phone has their own downloads. Signing out keeps
  yours, for when you sign in again; another person's are listed as "Other accounts on this phone".

### You > Downloads

- **Storage**: what's downloaded ("2.1 GB of 20 GB"), a bar, and "12 albums · 148 songs · 41.2 GB
  free on this phone". **Storage limit**: 5, 10, **20 GB** (the default), 50, 100 GB, or No limit.
  Lowering it below what's here removes nothing you downloaded yourself: new downloads wait for
  room, and it says so in amber. (Albums [your library](#your-library-on-this-phone) downloaded by
  itself make way, from the bottom.) The 2 GB of songs kept from streaming are apart from it. With other accounts' downloads on
  the phone, **Other accounts on this phone** has their size and **Remove** (it asks first).
- **Your library** ("The collection" with logins off): **Download your library**, what it's doing,
  and **Only while charging** - see [Your library on this phone](#your-library-on-this-phone).
- **Download over**: **Wi-Fi only** (the default) - never mobile data, a phone's hotspot or Low Data
  Mode - or **Wi-Fi and cellular**. Under them, what the phone is on now ("On mobile data now -
  downloads wait for Wi-Fi."), in amber while a download waits for it. Changing it applies at once.
  Both settings are kept on this phone.
- **Downloading**: each album on its way - "4 of 12 songs", or what it waits for, with a bar while it
  downloads. While your library is downloading, one row says so for all of it: "Your library - 38 of
  412 albums to go · 12.4 GB", or what it waits for, with a bar; a tap opens the Library's Downloaded.
  Each [downloaded playlist](#downloading-a-playlist) with songs to come has one row too: "Late night -
  3 of 12 songs to go", or what they wait for; a tap opens it.
  **Didn't download**: each album with songs that didn't, why, and **Try again** (**Try all again** when
  there's more than one); swipe a row to **Remove** them - for an album your library downloaded, that
  leaves the album off the phone, as its Remove Download does, though songs of it you downloaded
  yourself stay. When songs of it are already here, it asks first - "Leave Dummy off this phone?",
  saying those go too - with **Remove Download** and Cancel. A row of songs only a downloaded playlist
  wants has no swipe: remove the playlist's download. **Downloaded**: each downloaded playlist first
  ("12 songs · 412 MB"), then every album on the phone, largest first,
  with its size and its check - **Checked** (for a file that isn't FLAC, its size is all there is
  to check), **Checked by size** (a FLAC that carries no fingerprint), or **Checking…**. A song only a
  downloaded playlist wants is under the playlist's row, not an album's. Tap a row for its album or
  playlist; swipe it to **Remove**.
- **Remove All Downloads**, which asks first. With Download your library on, it's turned off too (the
  question says so), or your library would download it all again. Downloaded playlists go too (it says
  so); they stay in Navidrome.

### Your library on this phone

**Download your library** (You > Downloads, off until you turn it on - or Turn On on the Library's
card) keeps your library on the phone by itself: the albums you've added, newest first, as many as
fit in your storage limit. With logins off, and for the break-glass `deadwax` sign-in, it's **Download
the collection**: every album deadwax holds, newest first. The phone remembers the setting, for
whoever is signed in. This is app 0.9's, on the `ios` branch - not yet in a release.

- **What comes first**: the album you added or played most recently (a play counts for 30 days).
  Whole albums only, and only after everything you downloaded yourself: what you download is never
  removed to make room for your library, and it always has most of the downloads at once (your
  library has at most 20 of the 100). A new album comes onto the phone only with a little to spare
  (50 MB, or 1% of the limit if that's more), so one at the edge isn't downloaded and then removed
  again when its cover arrives; an album already here keeps its place while it fits at all.
- **What it says**: "All 212 albums fit in 20 GB.", or, in amber, "1,240 of 3,010 albums fit in 20 GB.
  Raise the limit or download fewer." With No limit, the phone's own space decides ("1,240 of 3,010
  albums fit on this phone."), always keeping 2 GB free. While it reads each new album's songs from
  deadwax it says "Reading your library - 1,240 of 3,010 albums" with a bar. Under it, "Checked 3
  minutes ago" - or "Couldn't check with deadwax - showing what was there last time."
- **When it checks**: as the app opens, when you come back to it after a minute or more, every 15
  minutes while it's open or playing, when deadwax answers again, straight after Add to or Remove from
  my library - and when you pull down on You > Downloads. A check that fails doesn't put off the
  next one. It downloads ten albums at a time, and the next as those arrive (one at a time with Only
  while charging on, below).
- **Keeping up with deadwax**: each album's songs are read once, then again when its album page is
  opened, and once a week (up to 20 each check), so a song deadwax re-tags under a new id is
  followed. An album that can't be read is skipped, and read after the others at the next check.
- **What it removes, and when**: only what it downloaded itself, never a song you downloaded yourself
  (or, later, one in a downloaded playlist), and never a play waiting to be sent.
  - An album you **remove from your library elsewhere** (the web app, Amperfy) goes when a second
    check, ten minutes or more after the first that missed it, agrees - so a star that flickers while
    deadwax re-tags an album costs nothing. One you remove **in the app** goes as soon as deadwax's list
    agrees.
  - **Lowering the storage limit**: the albums at the bottom make way, whole. Raise the limit and they
    come back.
  - **The phone falling under 2 GB free**, or **downloading something yourself on a full phone**: the
    albums at the bottom make way, whole - only as many as the phone needs, and only once it has been
    short for a few minutes, so one odd reading of the phone's free space never removes anything.
    Meanwhile what you downloaded waits ("the phone is full"), and starts as the room is made. A new
    album never pushes out one already here.
  - **A song that left its album** (deadwax re-tagged it, or it was replaced) goes only when a second
    read of the album, ten minutes or more after the first that missed it, agrees. A read that comes
    back empty, as one can while Navidrome rescans, changes nothing.
  - **Remove Download** on one of its albums: it goes, and stays off until you download it again.
  - **Turning it off**: everything it downloaded goes (what you downloaded yourself stays). With any of
    it on the phone, it asks first - "Remove the 412 albums downloaded with your library?", with what
    they take - with **Turn Off and Remove** and Cancel. It remembers your library, so turning it on
    again says what fits at once.
- **When deadwax's list looks wrong** - empty while the phone has albums of your library, or missing
  more than half of them at once (more than 10) - **nothing goes**. You > Downloads asks instead, in
  amber: "deadwax says your library is empty. Remove the 212 albums downloaded with it from this
  phone?", with **Keep Them** and **Remove**. Keep Them keeps them and puts the question away. Remove
  doesn't remove anything at once either: they go only if deadwax still says the same at a check ten
  minutes or more later. A list that stopped at deadwax's 10,000 albums is never believed. Removing
  the last album of your library in the app removes it, without the question.
- **The ten minutes are by the phone's clock**: moving the clock forward in Settings between two checks
  could make them agree early. The few minutes of "the phone is full" go by the phone's own running
  time, which Settings can't move.
- **Covers, lyrics and normalization** of the albums it downloads are kept as for any download.
- **Only while charging** (under the line of what fits, off until you turn it on, kept on this phone):
  "Your library's albums download only while the phone is charging. Albums you download yourself don't
  wait." On, with the phone unplugged, your library's albums wait, and say "Waiting for the phone to
  charge" - in an album's download menu, with "Only while charging is on - in You > Downloads." under
  it, and in Downloading's row for your library. Unplug it
  while the app is open or playing and what's downloading for your library stops at once, keeping
  what had come, and carries on from there when you plug it in again. With the app in the background,
  iOS downloads what it's been handed and the app can't stop it, so with Only while charging on your
  library hands iOS one album at a time (at most 20 songs at once): unplugged overnight, at most one
  album more comes down. A song that has downloaded nothing for 30 minutes doesn't hold that up: it's
  started again from where it got to, and your library goes on to the next album meanwhile. Albums you
  download yourself never wait for it.
- **In the background**: with the app closed (but not swiped away), iOS may run it now and then -
  about 15 minutes after you leave it, at the soonest - to check your library and hand over what's
  next, reading at most 20 new albums' songs each time, and stopping after 20 seconds whatever it has
  done; and, with Only while charging on and your library still downloading, once the phone is
  plugged in - even if, when you left the app, it was waiting for Wi-Fi or for deadwax rather than
  the charger. Albums below one whose songs it hasn't read yet wait until it has, so nothing is
  downloaded only to make way again. iOS decides when, possibly rarely; Background App Refresh off
  (Settings > General > Background App Refresh), or Low Power Mode, can stop it. It follows the same
  rules as with the app open: nothing goes that wouldn't then - the ten minutes between two checks
  hold, and the phone being short of space is never believed within a run that started the app,
  which iOS gives only seconds. Just after the phone restarts, before you first unlock it, the app
  can't read its own settings: if iOS runs it then, it does nothing. Downloads iOS starts
  while the app is in the background may wait for Wi-Fi and power by themselves. Swiping deadwax away
  in the app switcher stops all of it until you open it again.

## Offline

When the phone has no network, or deadwax doesn't answer (WireGuard off, away from home), the app
says so in an amber strip at the top of each page - "Offline - showing what's on this phone", or
"Can't reach deadwax - showing what's on this phone". Tap it for more, and, when deadwax isn't
answering, **Try again**. It goes by itself once deadwax answers.

- **The Library's Albums page is Downloaded**, under the same switch: headed Downloaded, with
  Downloaded playlists and "Only downloaded albums play until deadwax is back." at its top. It changes
  only when you're not looking at it (another tab, an album open over it, the app in the background), so
  it never moves under your finger; until then the list you were on stays, with every album not on the
  phone dimmed. ••• > **Your albums** (or **Albums**, without a library of your own) takes you to the full
  list, dimmed but for what's here; ••• > Refresh checks whether deadwax is back; ••• > **Shuffle
  downloads**, or a pull, shuffles the songs on the phone (see [Shuffling your
  library](#shuffling-your-library)).
- **Up Next** dims the songs that aren't on the phone; a tap on one does nothing (see [Up Next](#up-next)).
- **An album's page** shows what's on the phone, dims the rest, and Play and Shuffle play only the
  songs here. An album with nothing here says "This album isn't on this phone - it plays once deadwax
  is back."
- **Playlists**: one with a song on the phone, among the last eight you opened since the app started,
  opens with the songs not on the phone dimmed; the others are dimmed and open nothing. None is made or
  changed: Add to a playlist… is left out of the ••• menus, and New playlist and Edit are dimmed (see
  [Playlists offline](#playlists-offline)).
- **Playing**: a song that isn't on the phone is passed over to the next one that is ("Skipped "Roads"
  - it isn't on this phone"). With nothing left that's here, the player stops on it, paused: "Not on
  this phone - it plays once deadwax is back." Play tries it again.
- **Covers**: a downloaded album's is on the phone. Any other album's shows only if it was on screen
  a moment ago; otherwise it's an empty square until deadwax is back.
- **Opening the app** with no network: it opens at once, as last time, onto the strip and Downloaded,
  with the queue you were last playing put back, paused (see
  [Picking up where you left off](#picking-up-where-you-left-off)).
- **Lyrics**: a downloaded song's are on the phone and show as online. For a song with none kept,
  **Lyrics** is dimmed: "Lyrics - not on this phone" (see [Lyrics](#lyrics)).
- **Up Next** still shows what you've played: the newest 100 the phone kept, and every song started
  since, here at once (see [What you've played](#what-youve-played)). Scrolling further up asks deadwax
  for more, and says it couldn't.
- Plays, and the songs you started, are kept and sent later; downloads waiting carry on once the phone,
  or deadwax, is back.

## The checks

Phase 1 exists to answer these on the phone. Note what you see for each.

1. **Sign in and count.** Sign in with your Navidrome account. The Library shows your albums: does
   the count above them match the web app's Library? And All albums against the web app's All music?
   If you're an admin, You > Debug > Library says how many each list had and how long it took to
   come: note the times.
2. **The joins.** Find the test album under All music > All albums ("start test" in Find), tap song 9
   and let it run into song 10: one unbroken tone, with no gap, click or blip. Then a live or
   continuous album you know well: is every join seamless? Then previous: in a song's first 3 seconds
   it goes to the song before, and after that it starts the song again.
3. **Normalization, Automatic.** With Normalization on Automatic (You > Playback), play an album. Info
   > About > Sound > Normalization says "Album volume matching, ..." with the same change for every
   song of it. While it plays, add a song from another album with **•••** > Play Next: when it plays,
   Info says "Song volume matching, ...". (The app has no Search yet, so Play Next stands in for a
   song played on its own.) Then set Normalization to Off and play the album again: Info says "Off".
   Note how long the first song of an album never measured before takes to start.
4. **Quiet and loud.** A quiet old album, then a loud new one (Play Last it): about the same
   loudness, and no distortion on the quiet one brought up. Info says how much each was changed.
5. **Up Next.** While an album plays: Play Next a song and Play Last another, then open Up Next. Are
   they under Playing Next, in that order? Edit: drag one, take one out with its red minus button
   (one tap), Done. Clear. Shuffle on and off: the song playing goes on untouched. Repeat One plays the
   song again; Repeat All starts the album again after its last song. Then **what you've played**: play
   an album from song 5, tap song 8 in Up Next, and press Previous three times - 7, 6, 5. Scroll up: the
   songs played are there. Tap one: it plays again, the row stays under your finger, and Up Next carries on as
   it was.
6. **Picking up, both ways.** Play an album on the phone, pause it, and close the app (swipe it away).
   Open the web app on the Mac: the same queue, song and second, paused. Then play something else on
   the Mac, pause it, and open the app on the phone: it has it, paused, and says "Picked up from your
   Mac" ("Picked up from a Mac" with logins off, where everyone shares one queue).
7. **Plays.** Songs played on the phone turn up in Navidrome's recently played (and on Last.fm or
   ListenBrainz, if Navidrome is linked to them).
8. **AirPlay and AirPods.** AirPlay to a speaker from Now Playing, and back to the phone. AirPods
   connecting in the middle of a song: it carries on from the same place. Take one out: it pauses.
9. **An hour locked.** Play a long album or two, lock the phone and leave it in a pocket for an hour:
   no stop, and no stutter. The lock screen shows each song, and pause and play work there and from
   the AirPods.

### What only a phone can tell

The tests can't reach these either. Note what happens.

- **A phone call in the middle of a song.** It pauses, and after the call it carries on from the
  same place.
- **Repeat One, or a change in Up Next (move or take out a song, Play Next), in a song's last two or
  three seconds.** By then the next song is lined up for a seamless join, so a change to the queue is
  held and made after it: Repeat One turned on there repeats the next song, not this one. A tap on a
  row isn't held: it still plays that row at once. Try a tap there too. Does any of them sound wrong
  at the join?
- **WireGuard off in the middle of a song**, away from home. What does the mini player say, and does
  the music come back once WireGuard is on again?
- **The Library's grid flung from A to Z**, on a big library. Does it keep up? To see its memory,
  run the app from Xcode: open `ios/Deadwax.xcodeproj`, choose the iPhone and press Run, as in step 5
  of [Once](#once). Xcode's Debug navigator then shows the app's memory while you fling: note it.
  Running it this way installs a Debug build over the app (everything on the phone stays), so run
  install.sh afterwards to put the Release build back.
- **Sign out, then sign in as someone else.** Their Library, and nothing of the first person's queue.
- **Download your library on a phone with little space left.** It keeps 2 GB free by the phone's own
  measure of free space, the one iOS uses for what it would make room for. Does Settings > General >
  iPhone Storage agree with what You > Downloads says, and does anything else on the phone complain?
  When the phone dips under 2 GB, Debug says "under the reserve · confirming", then after a few minutes
  "giving way" - does only the bottom album go, and only as much as was needed?

### Phase 2's checks: downloads

1. **An album, on Wi-Fi.** Tap an album's download arrow: the ring fills, the line under the title
   counts the songs, and You > Downloads shows it under Downloading with a bar. Once it's here: the
   filled arrow, "Downloaded · ... MB" in its menu, and You > Downloads lists it with **Checked** (or
   Checking… for a moment). Does a 24-bit 192 kHz album check in reasonable time (Debug > Downloads)?
2. **Locked.** Ask for a big album, lock the phone and leave it for ten minutes: is it all here?
3. **Wi-Fi only.** On mobile data, ask for an album: "Waiting for Wi-Fi", and You > Downloads' line
   in amber. Back on Wi-Fi, does it start by itself? Then Wi-Fi and cellular: does it download on
   mobile data?
4. **Airplane Mode.** Turn it on with an album downloaded: the amber strip, and the Library on
   Downloaded once you come back to it. Play the album: every join seamless, Info says "This phone -
   checked", and Normalization says what it said online. Open an album not on the phone: it says so.
5. **Skipping.** With Airplane Mode on, play a list (or Up Next) mixing downloaded and not: the songs
   not here are passed over, with the notice; at the end, it stops on the first song not here.
6. **Opening offline.** Close the app from the app switcher, turn on Airplane Mode, open it: straight
   onto the strip and Downloaded, with no wait.
7. **Back.** Turn Airplane Mode off: the strip goes ("Back online" with VoiceOver), the plays made
   offline turn up in Navidrome, and the Library is your albums the next time you come to it.
8. **WireGuard off, away from home.** The strip says "Can't reach deadwax"; **Try again** while it's
   off, and the strip goes by itself once it's on.
9. **Force quit mid-download.** Ask for an album, close the app from the app switcher, open it again:
   You > Downloads says downloads stopped, and they carry on.
10. **The storage limit.** Set it to 5 GB with more than that here: the amber line, and nothing
    removed. A new album waits for room.
11. **Sign out and in.** Your downloads stay through a sign-out; signed in as someone else, they're
    "Other accounts on this phone".
12. **Remove All Downloads**: it asks, then the screen is empty and the Library's Downloaded row goes,
    and Settings > General > iPhone Storage > deadwax shows the space back.
13. **A downloaded album opens at once**, online too: no spinner before its songs.
14. **deadwax up, Navidrome down** (Navidrome's container stopped): the Library's "isn't available"
    screen has On this phone > Downloaded under it, and a downloaded album plays.
15. **The strip under every bar**: on the Library (with Find), an album's page and You > Downloads,
    offline, the strip sits under the bar and the list scrolls under it without showing through.
16. **VoiceOver and the largest text size**: the download button ("Download, Downloading, 40
    percent"), a song's actions, the strip as it comes and "Back online" as it goes; at the largest
    text size, You > Downloads and an album's page with nothing cut off.
17. **The queue, kept.** Play a downloaded album, pause halfway through a song, and close the app from
    the app switcher. Turn on Airplane Mode and open it: the mini player shows that song, paused at
    the second you left it, with no notice, and Up Next is as you left it. Press play: it plays.
18. **A queue saved offline, then elsewhere.** (a) Still in Airplane Mode, skip to another song and
    pause; close the app from the app switcher. Turn Airplane Mode off and open the app: the song you
    skipped to is there, paused, with no notice. Open the web app on the Mac with nothing playing
    there: "Picked up from your iPhone", on that song. (b) Again in Airplane Mode, skip to another song,
    pause and close the app; then play something else on the Mac for a minute. Turn Airplane Mode off
    and open the phone: "Picked up from your Mac", on the Mac's song - the phone's offline queue
    didn't overwrite it.
19. **Up Next's marks.** Play a downloaded album, then Play Last one that isn't; open Up Next: the
    first album's songs have the grey filled mark at the end of their line, the second's none. Now
    Playing's **•••** > **Download Up Next**, then Up Next again: the second album's songs go dotted,
    then a ring fills, then the filled mark, and nothing else in a row moves. With VoiceOver, a row
    says "Roads, play now, Downloaded". Do the marks look as they do on the album page, and as Apple
    Music's would?
20. **Up Next offline.** Play a downloaded album with one that isn't queued after it, turn on Airplane
    Mode and open Up Next: the songs not on the phone (History's too) are dimmed, a tap on one does
    nothing, VoiceOver says "Not on this phone, dimmed"; the song playing isn't dimmed. **Edit**: a
    dimmed song's minus and handle still work - take one out, move one. At the largest text size,
    each mark sits after its line, level with the line's first line, clear of the handle.

### Lyrics' checks (app 0.4)

Use a song deadwax filed with synced lyrics (Dummy's "Roads", say), one with lyrics saved without
timings, an instrumental, and Five Finger Death Punch's "American Capitalist". Keep Apple Music to
hand: several of these ask how it compares.

- **P1 The button.** Now Playing's bottom row is Lyrics, AirPlay, Up Next, •••. Lyrics is a speech
  bubble, filled and purple while on.
- **P2 Opening.** Play "Roads", open Now Playing, tap Lyrics: the lyrics take the cover's place, the
  title and the buttons don't move, the line being sung is white and about a third of the way down,
  and the lyrics move up smoothly as each line comes. Tap Lyrics again: the cover. Scroll the lyrics
  hard: Now Playing never starts closing; a swipe down from the arrow's row closes it.
- **P3 Your own scroll, and a tap.** Scroll up to read ahead: it stays where you put it, the lit line
  still changing. Let go; about four seconds after it stops, it goes back to the line being sung -
  sooner, later or the same as Apple Music? Tap a line further on: the song jumps there and plays on.
  Pause, tap a line: it plays from there - does Apple Music start playing too? Pause, scroll down,
  wait ten seconds: it stays. Press Play: back to the line being sung.
- **P4 The lead.** Tap a line and listen: does it light as the words start, a beat after, or before?
  On "American Capitalist", does the lit line ever show the line just sung? (`LYRICS_LEAD_MS` is what
  moves it, for every player at once.)
- **P5 Breaks, and lyrics without timings.** A song with a long intro or a guitar break: three dots,
  lighting one by one, then the next line. The song without timings: "These lyrics aren't synced to
  the song." above them, every line white, nothing moving by itself.
- **P6 None, and on from song to song.** The instrumental: Lyrics is dimmed and does nothing. With
  lyrics on, let a song with lyrics run into it: the cover shows and Lyrics stays lit; the next song
  with lyrics shows them again. Close Now Playing with lyrics on and open it again: still lyrics.
- **P7 Larger Text.** Settings > Accessibility > Display & Text Size > Larger Text at the largest:
  the lines wrap and stay readable, the line being sung clear of the soft edges, and the bottom row's
  four buttons fit.
- **P8 Increase Contrast, Reduce Motion, Bold Text** - and the brightest cover you have (a white
  sleeve): the background goes darker as lyrics open, and the dim lines are still easy to read. With
  Reduce Motion, the lyrics jump from line to line, with no spring.
- **P9 VoiceOver.** Swipe through the lyrics: each line its words and its time, "now" on the line
  being sung, then "Plays from here."; the rotor's Actions has "Go to the line being sung", and it
  goes there. While you're on a line, the lyrics don't scroll away. Double tap a line: it plays from
  there. Does a three-finger scroll hold the lyrics, and do they come back after?
- **P10 Offline.** Download an album, turn on Airplane Mode, play it: its lyrics show and follow. A
  song downloaded with app 0.3 shows lyrics offline once the app has been opened with deadwax in
  reach since the update. A song not kept: Lyrics dimmed, "Lyrics - not on this phone" to VoiceOver.
- **P11 AirPlay.** AirPlay to a speaker: do the lines still land with the words? (AirPlay delays the
  sound by a second or two.)
- **P12 The lock screen**: as before - no change at all - and the music plays on locked as it did.

### The EQ's first checks

These came with the build that put the EQ's audio unit in, before it had anything to set but Debug's
test (You > Debug > EQ); they still hold. Install the usual way, not with `--debug`: a Debug build's
EQ runs far slower than the one that ships. AirPods:

- **E0a Muffle.** Play test sound 1. Debug's EQ says "Unit: In the graph: passing every sample
  through" and "Render block: iOS asked for it" some number of times (tell me the number; if it says
  iOS hasn't, stop there and tell me). Turn on **Muffle what plays**: the beeps sound muffled at once,
  with no click. Turn it off: they sound as before.
- **E0b The join.** Play songs 9 into 10 (one tone cut in two) and turn Muffle on and off ten times as it
  plays: no click, no drop, no break at the join.
- **E0c Nothing changed.** With Muffle off, play an album you know well: it sounds exactly as it did
  before this build.
- **E0d The lock screen.** Stay on Debug and lock the phone. Pause from the lock screen, then press an
  AirPod's stem: the lock screen shows play after the pause, and the press plays. Do it with Muffle
  on, then off. (Leaving Debug turns Muffle off, so start each from Debug.)

### The EQ's checks (app 0.5)

The EQ's own page, with AirPods unless it says. Install the usual way, not with `--debug`.

- **E1 You's row.** You > Playback: after Normalization, **EQ**, with "iPhone speaker" under it and
  "Off" at the right; its note below.
- **E2 The speaker, off.** Open it with the speaker playing: "iPhone speaker", "Connected now", the EQ
  switch off, a flat curve in grey, "Off: nothing changes the sound."
- **E3 It follows the output.** Connect the AirPods and play: the page changes to "James's AirPods
  Pro" by itself (if your finger isn't on a slider). The speaker is now under **Other outputs**, Off.
- **E4 Bass Boost.** Preset > **Bass Boost**: the switch turns on; back on the EQ page the sliders
  show it, the curve shows the bass lifted, and the line says "Preamp -6.1 dB, so loud songs don't
  clip." You hear more bass - and everything a little quieter, which the volume buttons give back.
- **E5 A slider.** Drag the 125 slider up and down while a song plays: the sound follows your finger,
  smoothly, never clicking; a small tick under your thumb at 0. Touch its column away from the knob:
  the knob doesn't jump. Double-tap it: back to 0. "Preset" now says "Custom".
- **E6 Your preset.** **Save as Preset…**, call it "Mine": it's under "Your presets" in Preset. Try to
  save another as "bass boost": "There's already a preset called "Bass Boost"." Rename "Mine", then
  delete it - the sliders stay where they were.
- **E7 On and off.** Flip the EQ switch on and off while a song plays, a dozen times: a clean A/B, no
  click.
- **E8 Out and back in.** Take the AirPods out mid-song: it pauses, as before. Play: the speaker plays
  Off - flat. Put them back in and play: Bass Boost again from the first sound. Then You > Debug > EQ:
  what does **Start took** say?
- **E9 Tune the presets.** Try each of the nine on two albums you know. Tell me any that sound wrong,
  and which way (too much, too little, the wrong place) - the numbers move to what you settle.
- **E10 From Now Playing.** Now Playing > **•••**: **EQ**, with "Bass Boost" under it (or only "EQ" -
  tell me which); it opens the same page over Now Playing, and **Done** closes it.
- **E11 Info.** Info > About > Sound shows **EQ**, "Bass Boost on James's AirPods Pro, preamp -6.1
  dB"; turn the EQ off: the row goes.
- **E12 An hour locked.** With the EQ on, lock the phone and play a whole album: nothing different
  from off but the sound - no drop-outs, no silence; pause and play from the lock screen and the
  AirPods: play and pause right every time. Unlock and open Debug's EQ: the Render row's "refused
  blocks" should be 0.
- **E13 Two rates.** Play a hi-res album and a 44.1 kHz album back to back with the EQ on: no break
  between them; Debug's EQ **At this rate** says 48 kHz.
- **E14 VoiceOver.** The page reads the output, the switch, "The EQ's curve" with what it does (try
  the rotor's Audio Graphs > Play Audio Graph), the line under it, Preset, then "31 hertz, 0 decibels, adjustable" … -
  swipe up: "plus 1 decibel".
- **E15 The outputs' IDs.** Debug's EQ, **Output**: tell me the AirPods' ID; switch the phone off and
  on, and tell me again - and the same for the car, and a USB DAC if you have one.
- **E16 The largest text.** Settings > Accessibility > Display & Text Size > Larger Text at the
  largest: the sliders are ten rows with - and + buttons; everything else wraps.

### AutoEq's checks (app 0.5)

Needs deadwax 2.1.7 or later (`:experimental` for now). AirPods with no correction, unless it says.

- **E17 The suggestion, and Use.** On the AirPods' EQ page, under Correction: "AutoEq has corrections
  for AirPods Pro", "16 models - pick yours" (or however many AutoEq has by then). Tap it: the picker, "AirPods Pro" searched, the first
  generation and the Pro 2's under **Suggested for James's AirPods Pro**. Open the one for your
  generation (for the Pro 2, the listening level and ANC you use): "Measured by …", the curve, Other
  measurements - then take the AirPods out on that page before tapping: the button still says **Use
  for James's AirPods Pro**, the line at the top says they aren't connected, and using it goes back to
  their EQ page, the correction on them - the speaker's EQ unchanged. Put them back in: it plays.
- **E18 What it does.** With the tone Flat, flip the EQ off and on while a song plays: the
  correction's difference (more neutral: often a little less bass bloom and more treble detail on
  AirPods). Then Bass Boost on top: both, one curve, the correction as a thin dashed line under it.
  Tell me how the curve changes when you choose the correction - does it fade across or jump?
- **E19 Searching.** In the picker, search "hd650", "hd 650" and "airpods": each finds what you'd
  expect. Search "zzz": "AutoEq has no headphones called "zzz"." Then None: the correction goes, and
  back on the EQ page the suggestion is back. Swipe it for **Not now**: it goes, and doesn't come back
  after closing the app and opening it again.
- **E20 Offline.** Airplane mode (or WireGuard off away from home), then search: "Can't connect to
  deadwax." with Try again - and the correction still plays. The suggestion isn't shown while
  offline.
- **E21 Headphone Accommodations.** If you use Headphone Accommodations (Settings > Accessibility >
  Audio & Visual), turn it off with a correction on: the two stack otherwise.

### Advanced's checks (app 0.5)

AirPods with an AutoEq correction on (E17), unless it says. Import and export need nothing of
deadwax.

- **E22 Advanced on.** At the bottom of the EQ page, turn **Advanced** on: the curve grows, with a
  handle for each filter; Correction lists the filters, lowest first; **Preamp** after Tone says
  "Automatic". Then You > Debug's EQ section, **Render**: tell me both numbers.
- **E23 The handles.** Drag a handle sideways, then up and down, then pinch it: the sound follows,
  its numbers show above the curve, its row changes too, and the Correction row says "- changed".
  Tell me whether a drag on the curve away from the handles still scrolls the page, and whether the
  pinch takes the filter you meant. Then **Back to AutoEq's** (touch and hold the Correction row):
  the curve and the sound go back.
- **E24 A filter of your own.** **Add Filter**: a peak at 1000 Hz opens. Type +6 for Gain and 4 for
  Q: you hear a peak in the upper mids. Back on the EQ page, switch its row off and on.
- **E25 The preamp by hand.** Turn **Automatic** off: nothing changes in the sound. Set the preamp
  to -2 dB with Bass Boost on: "Loud songs may clip: the curve boosts … dB more than this preamp
  takes away." in amber, under the curve and under Preamp.
- **E26 Export, and back.** Set the tone to **Flat**, then Export… > **The Whole Curve** to Files;
  then **Import from Files…** that file: the preview shows the same curve and numbers; Import -
  nothing changes in the sound.
- **E27 Shared from another app.** AirDrop a ParametricEQ.txt from your Mac (or save one from
  Safari) and share it to deadwax - once with the Library showing, once with Now Playing open, once
  with Up Next open: the preview opens over whatever is showing, For set to the output playing.
  Tell me if any of the three didn't show it.
- **E28 A GraphicEQ.** Import a GraphicEQ.txt from AutoEq: "Converted from a GraphicEQ curve: …
  filters, within … dB"; compare it by ear with the same headphone's ParametricEQ.txt.
- **E29 Refused.** Copy an Equalizer APO setting with `Include: other.txt` in it, and Paste: "Can't
  import this file" and why ("Line … includes another file (other.txt). Import that file itself.").
- **E30 VoiceOver.** On the filter rows: "Filter 3: peak at … hertz …", "On", its switch "Filter 3
  on", and the Delete and Turn Off actions.

### The EQ's follow-ups' checks

- **E31 Cuts only.** Choose **Bass Reduce**: the line under the curve says "Cuts only: nothing gets
  louder." and Preamp (in Advanced) "0.0 dB"; then **Bass Boost**: "Preamp -6.1 dB, so loud songs
  don't clip."
- **E32 A file, changed.** Import a ParametricEQ.txt, then change one of its filters: the Correction
  row's line reads "From … ParametricEQ.txt - changed". Import it again: "- changed" is gone.
- **E33 A big export, read back.** Import a GraphicEQ.txt from AutoEq, move every one of the ten
  sliders off 0 (Custom), Export… > **The Whole Curve** to Files, then **Import from Files…** that
  file: the preview shows the same curve, with no "Can't import this file". Cancel (imported under
  the same tone, it would play twice).

### The turntable's first checks

These come with the build that adds the turntable's sound engine, before it has a screen. They use
You > Debug > Test sounds > **The record's engine beside the song**. Install the usual way, not with
`--debug`.

- **0a Both at once.** Play test sound 1, then tap **Start** on the record's engine. You hear both
  at once: the beeps unchanged, with the record's run over them.
- **0b Nothing in the song.** While the test sound plays, tap **Stop** and **Start** five times.
  Nothing should be heard in the test sound: no click, no drop, no change of level.
- **0c The clock.** Watch the **Clock** row for a minute on the speaker, then on earbuds. Once it
  has settled, the first number moves by no more than a millisecond or two. Tell me both numbers,
  for each.

### The turntable's checks (app 0.6)

These come with the build that puts [the turntable](#the-turntable) on Now Playing. Earbuds or the
speaker unless a check says. The numbers are the turntable plan's, so answers can say "check 8".

- **1 The settings.** You > Playback: Gapless, then **Now Playing opens as** (Cover ticked), then
  **Pause winds the record down** (on), then Normalization - each with its note under it. Choose
  **Turntable**.
- **2 Opens as.** Play an album and open Now Playing: it opens on the turntable. The top-right button
  switches to the cover and back. Close and open it again: it opens on the turntable, whatever you
  switched to.
- **3 Nothing jumps.** Switch between the two: the title and the artist move to the middle and back,
  and nothing moves up or down - the time line sits in the scrubber's row, and the titles and the
  buttons below stay put. The turntable is about as wide as the cover was (a few points narrower, not
  a small record in a tall gap), and nothing overlaps.
- **4 CD art.** An album you've saved CD art for (the web app's **Get CD art**): the record's face is
  the CD art. A two-disc album with a `disc2.jpg`: a disc 2 song shows it. An album with none: a black
  record with the cover as its label.
- **5 It turns.** While playing, a turn every 1.8 seconds, smoothly. Debug > Turntable's **Frames under
  a hand** (after a turn by hand) should show few late.
- **6 Tap and wind down.** Tap the record: the song pauses, its sound slowing to a stop over about a
  second with the platter. Tap again: it plays. Turn **Pause winds the record down** off: the pause is
  instant. Pause from the cover: always instant.
- **7 Hold and turn.** Hold the record while it plays: the song pauses under your finger. Turn it
  slowly, quickly, backwards: you hear it follow, a little more than an eighth of a second behind;
  resting your finger is silence.
- **8 The handover.** Let go mid-turn: the record carries on at your hand's speed, the motor brings it
  back up, and the song carries on. Listen to the moment the song takes over: no jump back, no repeat,
  no gap - and nothing that sounds doubled or briefly louder. Ten times, with a downloaded song and
  with one streaming; tell me Debug's **Handover** row after a few.
- **9 The coast.** Pause, then flick the record: it coasts to a stop with its sound, and the song stays
  paused where it stopped; play starts from there.
- **10 The arm.** Drag the arm: the head lifts, the time line says "Needle up · ..."; let go and the
  song plays from there. The head stays on the end of the arm the whole time: lifted, it grows a touch
  with a soft shadow round it, as if it came toward you. Tap the head quickly a few times: it swells and
  settles back smoothly, never jumping sideways off the arm or flickering. With Reduce Motion on, it
  changes size at once instead.
- **11 An MP3.** Turn the record on one: silent, with "The record makes sound for FLAC songs only -
  this one moves silently." over the foot of the turntable until the next song.
- **12 Still coming in.** A song never played before (not downloaded), turned while it's still coming
  in: it has its sound, and Debug's **Window from** says "deadwax - the song is still coming in".
  Played again later: "The copy kept on this phone".
- **13 Offline.** A downloaded album, in Airplane mode: the record has its sound, and **Window from**
  says "This phone's download".
- **14 Hi-res.** A 96 kHz album: let go at a playing record's own speed - the record's sound and the
  song are the same loudness and tone across the handover. The same with Normalization on.
- **15 Interruptions.** While holding the record, have Siri speak, or take a call: the record's sound
  stops, nothing sticks, and the song doesn't start into the call. Take AirPods out mid-turn - while
  holding the record, and just after letting go of it: no sound from the speaker, the record comes to
  rest and the song stays paused until you play it.
- **16 Going Home.** Flick the record and go Home while it coasts: the sound stops at once. Come back:
  the song is where the record was going.
- **17 AirPlay.** AirPlay to a speaker: turning the record is silent, with the AirPlay line.
- **18 VoiceOver.** The look button, then the record ("The record: a tap pauses the song"), then the
  arm ("Tonearm: position in the song", "2:31 of 7:05"; swiping up and down moves 5 seconds), in that
  order.
- **19 Reduce Motion.** On: the record doesn't turn by itself; a let-go goes straight on - no coast,
  and no gap before the song; a pause is instant. The hand still has its sound.
- **20 The largest text.** The time line stays on one line; a long press on the look button shows its
  large version.
- **21 The lock screen after a wind-down.** With the wind-down on, tap the record to pause and lock the
  phone straight away: within two seconds the lock screen shows the song paused. Press the AirPods'
  stem (or the lock screen's play): it plays. Unlock with the turntable showing and pause with the
  AirPods' stem: the platter runs down silently; lock the phone then, and the lock screen shows the
  song paused. Then the same with the wind-down off.
- **22 Debug.** Debug > Turntable after a few turns: every row has a value, and **Delay behind the
  hand** names more on Bluetooth earbuds than on the speaker.
- **23 Against Safari.** The same song on the turntable in Safari (at deadwax's address) and in the
  app. Someone else hands you the phone with one or the other open, ten times; eyes closed, take the
  record, scratch it, flick it and let it hand back, then say which. Tell me how many you got right,
  and anything that sounded different, and in which. Then record 20 seconds in each (Debug > **Record
  20 s**, the same song and a similar motion) and send both files.
- **24 A whole album.** Leave the turntable showing for a whole album: no warmer than the cover, and
  the battery about the same - a little more, as the record's engine runs beside the song's while it
  plays.

### The speed's checks (app 0.7)

These come with the build that adds [the speed fader](#the-speed). Earbuds or the speaker unless a
check says; the numbers carry on from the turntable's.

- **25 The fader.** On the turntable, drag the knob up: the song speeds up and its pitch rises, the
  readout says `1.25x` in purple, and the record turns faster. Back near the mark it snaps to exactly
  1x with one small tick under your thumb, and the mark goes green. The knob takes a thumb a little to
  either side of it - just past the turntable's right edge too - and at a song's start, the arm's
  handle beside it takes the arm.
- **26 The readout.** Off 1x, tap the readout: straight back to 1x.
- **27 The cover.** Off 1x, switch to the cover: `1.25x` between AirPlay and Up Next, nothing in that
  row moved; tap it - 1x, and it's gone. The mini player shows nothing.
- **28 1x as before.** At 1x everything sounds as it did before the fader existed: Test sounds 9 and
  10 unbroken.
- **29 At 2x and 0.5x.** Test sounds 9 and 10 still unbroken at each; lock the phone - the lock
  screen's clock moves at the speed.
- **30 The record at speed.** At 1.5x, take hold of the record and let go: it comes back to 1.5x
  (50 rpm), and the song carries on at 1.5x.
- **31 Through the mark.** While a song plays, drag the fader slowly up through 1x and back down
  through it, several times: no click or jump at the mark either way. Then let go at the mark: one
  short gap (a few milliseconds), then the song exactly as before the fader existed. The first move
  off 1x has a short gap too.
- **32 No flicker.** Watch play/pause under the record while you move the fader off 1x and let go at
  1x, a few times: it stays a pause button - no spinner, no flash of play. Then lock the phone at
  1.25x: the lock screen shows the song playing, its clock at the speed. Open Control Center while
  it plays at 1.25x: it agrees with Now Playing's clock when you close it.
- **33 Plays at 2x.** At 2x, play a song of four minutes or more to just past its half, then skip:
  it counts as played (its play count in Navidrome, or Last.fm) - about a minute of the clock for a
  four-minute song. At 1x, the same minute doesn't count.
- **34 The tick.** Drag slowly back and forth across the mark: one tick each time you come into it,
  none as you leave it. A tap on the readout, the cover's `1.25x`, and VoiceOver's swipes give none.
- **35 Kept.** Set 1.25x, close the app from the app switcher and open it again: still 1.25x, from the
  first note - the readout and the cover say so. Back at 1x the same way: 1x.
- **36 One finger at a time.** Hold the record and put another finger on the fader: nothing moves.
  Hold the fader's knob and tap the record: no pause. Close Now Playing while holding the fader: the
  speed stays where your finger had it.
- **37 VoiceOver.** After the arm: the fader ("Speed", "normal speed"; a swipe up says "1.01 times"),
  then the readout ("Speed 1.01x: back to normal speed"; a double-tap goes back to 1x, and it then
  says "Speed: normal", dimmed). On the cover off 1x, the chip: "1.25x, 1.25 times the song's speed:
  back to normal speed".
- **38 The largest text.** At an accessibility text size: the readout's words stay inside its corner,
  and a long press on it shows `1.25x` large. On the cover, off 1x, there's no chip: the **•••**
  menu's first line is "Speed 1.25x - back to normal speed", and it goes back to 1x.

### Play history's checks (app 0.8)

These come with the build that adds [what you've played](#what-youve-played). Earbuds or the speaker;
the numbers carry on from the speed's. The web app is deadwax's own page (`/player/`) in Safari or on
the Mac, signed in as you.

- **39 One list.** Play a few songs on the phone, skipping one after a second or two. Open Up Next and
  scroll up past the song playing: every song you started, the skipped one too, newest nearest the
  song playing, with no headings, dates or times - and nothing twice. Open the web app's Up Next: the
  same songs, in the same order.
- **40 Both ways.** Play two songs in the web app, then open Up Next on the phone: they're there,
  above what the phone played before them. With Up Next open on the phone, play a song in the web app,
  go to the Home Screen and back: it comes in.
- **41 Further back.** With more than a hundred songs played, scroll up slowly to the top: a spinner
  over the top of the list, then the older songs above - and the row you were looking at stays where it
  was, with no jump. Keep going: page after page, until the oldest.
- **42 Play one again.** Tap a song far up the list: it plays now, the row stays under your finger,
  and Up Next goes on after it as it was. With VoiceOver: the row says "…, play again", a double tap
  says "Playing …", and the focus stays on the row.
- **43 Not new songs.** Up Next draws a song started again straight after itself as one row, so this
  one is counted in Debug. Turn on Airplane Mode and play a downloaded album, with You > Debug >
  Downloads' **Starts waiting to be sent** a look away: it goes up by one as each song starts. While
  one plays: pause and play, drag the arm on the turntable, take hold of the record and let go, move
  the speed fader off 1x and back, and lock the phone for a minute - the count doesn't move. Next: up
  by one. Airplane Mode off: it goes to 0.
- **44 Picked up.** Play a downloaded album, pause it in the middle of a song, and close the app (swipe
  it away). Turn on Airplane Mode and open it: the song is back, paused. Note **Starts waiting to be
  sent**, press play, look again: the same - the song carries on its play rather than starting a new
  one. Next: up by one. Airplane Mode off afterwards.
- **45 Offline.** Turn on Airplane Mode and play three downloaded songs: each shows in Up Next as it
  starts, and You > Debug > Downloads counts them under **Starts waiting to be sent**. Close the app
  (swipe it away), open it again still offline: Up Next still has them, and what you played before
  (the newest 100). Turn Airplane Mode off: the count goes to 0, and the web app's Up Next has the
  three, in order, before the plays they made counted in Navidrome.
- **46 A long time away.** Days offline with the phone, playing as you do: back in reach, every song
  arrives in the web app's Up Next (Debug's events say "starts sent" with how many).
- **47 Can't load.** Scroll up to the top with WireGuard off on mobile data (and nothing much kept):
  "Couldn't load the songs you played before." at the top, with **Try again**; WireGuard on, Try again:
  the older songs come, and the line goes.
- **48 Someone else.** With logins on, sign out and sign in as someone else: none of the first
  person's songs in Up Next, nor sent as theirs.
- **49 Back in reach.** Turn on Airplane Mode and open Up Next: the songs the phone kept, and no
  "Couldn't load" line at the top. Play a song in the web app on the Mac, then, with Up Next still open
  on the phone, turn Airplane Mode off: the web app's song comes in without closing Up Next. Scrolling
  up then goes on loading older songs as before.

### Your library's first checks (L0a-L0g)

These came with the build that added [Debug's Your library](#debug), the first part of downloading
your library by itself, when nothing downloaded yet. You > Debug > **Your library**, with **Follow
your library** on - in the build after it, that switch is You > Downloads' **Download your library**,
which downloads too (see [the next checks](#your-librarys-checks-50-63)). The web app is
deadwax's own page (`/player/`) in Safari or on the Mac, signed in as you.

- **L0a The first read.** At home on Wi-Fi, turn **Follow your library** on and keep the app in front
  (Auto-Lock off helps): **Albums** says how many your library has - the same as the web app's
  Library - and **Songs read** climbs to all of them. When it's done, **First read** says how long it
  took and the time per album: please send me both. (The time counts from the first list to the last
  album read, so the app going to the background in between makes it longer; if it closes, First read
  never shows - turn the switch off and on to start again.) If you can, once more over WireGuard away
  from home: turn the switch off and on, and send that time too. It decides whether deadwax needs a
  route that reads 50 albums at a time.
- **L0b A star elsewhere.** Add an album in the web app (or star one in Amperfy). Wait a minute after
  Debug's last check, go to the Home Screen and back to the app: within seconds **Albums** is one more,
  and **Songs read** catches up.
- **L0c Removed elsewhere.** Remove an album from your library in the web app. Back in the app a
  minute later, or with **Check now**: **Missing** says 1. Ten minutes or more later, **Check now**:
  Albums is one fewer, Missing is None, and the Downloads events have "library byHand: ... 1 removed".
- **L0d Unchanged.** **Check now** twice, with nothing played in between: the second's **Last check**
  says "unchanged (304)". (A song played in between makes it a 200: the list carries when you last
  played each album.)
- **L0e Removed here.** **Remove from my library** on an album's page in the app, then back to Debug:
  Albums is already one fewer - no ten minutes.
- **L0f Would fit.** Note the "… fit in 20 GB" line; set You > Downloads' **Storage limit** to 5 GB:
  the line says fewer fit in 5 GB. Back to 20 GB: as before.
- **L0g Nothing else moved.** You > Downloads is as it was, nothing is downloading that you didn't ask
  for, and Debug's Downloads counts haven't moved.

### Your library's checks (50-63)

These come with the builds that download your library by itself (54 and 61-63 with app 0.9). Debug's own switch is gone: **You >
Downloads > Download your library** does what it did, and downloads too, so L0a-L0f above now run
with it (L0g no longer holds: things download). Note what you see for each; the Downloads events in
You > Debug have a "library" line for everything it asks for and lets go, and why.

- **50 Overnight.** At home on Wi-Fi, turn on Download your library with the phone on charge, open
  the app, then lock the phone: in the morning your library is downloaded - or as much as fits, said in
  numbers in You > Downloads. Note the time it took, and the size, and what You > Debug > Your library >
  In the background lists. (If little came, try once more with the app open and Auto-Lock off: that
  tells iOS's background apart from the app's.)
- **51 A star elsewhere.** Add an album in the web app (or star one in Amperfy): within 15 minutes of
  the app being open, or straight away when you come back to it, it starts downloading.
- **52 An unstar.** Remove an album from your library in the web app: it stays on the phone at the
  first check that misses it, and goes at the next check ten minutes or more later (pull down on You >
  Downloads to check now). Try it once more with an album you'd also downloaded a song of yourself:
  that song stays.
- **53 Add and Remove here.** **Add to my library** on an album's page: it starts downloading within
  seconds (if it fits). **Remove from my library** on one it downloaded: the line under the button says
  "Its download goes from this phone too.", and it goes within seconds.
- **54 Only while charging.** Turn it on (You > Downloads, under the line of what fits) and unplug the
  phone while your library is downloading: what was downloading stops, and your library's albums say
  "Waiting for the phone to charge" - Downloading's row, and an album's download menu. Download an
  album yourself meanwhile: it doesn't wait. Plug the phone in: your library carries on, from where it
  stopped, one album at a time (Debug's **Albums out** says 1).
- **55 The limit lowered.** With your library filling 20 GB, set Storage limit to 10 GB: the albums at
  the bottom go, whole, and nothing you downloaded yourself; the line says what fits now, in amber.
  Back to 20 GB: they come back.
- **56 A hand download on a full phone.** With your library filling the limit, download another album
  yourself: it downloads, and an album at the bottom of your library makes way.
- **57 Remove Download on a library album.** It goes, and doesn't come back at the next check (pull
  down); its page says "You removed this download - your library leaves it off this phone." Tap its
  arrow: it comes back, as yours.
- **58 The first ask.** On a phone that has never been asked (or after deleting and reinstalling the
  app): the card at the top of the Library. Not Now puts it away for good; next time, try Turn On.
- **59 Remove All** with it on: the question says Download your library is turned off too; afterwards
  nothing downloads again, and You > Downloads shows it off.
- **60 An empty list.** Only if it can be arranged safely - unstar everything on a test account, or
  stop Navidrome's music folder from mounting: nothing goes from the phone, and You > Downloads asks.
  Keep Them keeps them, and the question goes. If you try Remove: still nothing goes at once, and the
  albums go only if a check ten minutes or more later says the same.

- **61 In the background.** Add an album in the web app on the Mac, and leave the phone locked and not
  playing for an hour (the app not swiped away): note whether it came down without opening the app.
  iOS decides when, and may not at all - You > Debug > Your library > In the background says whether
  iOS ran the app, when, and what came of it. Please send me those lines either way.
- **62 Unplugged overnight.** With Only while charging on, start a big library downloading on the
  charger, note how many albums are on the phone (You > Downloads > Downloaded), then unplug the phone
  and lock it. In the morning: at most one album more than when you unplugged, and the rest say
  "Waiting for the phone to charge". Then plug it in overnight with the app closed: note in the morning
  whether it carried on by itself (In the background has a **Charger** line if iOS ran it).
- **63 VoiceOver and the largest text.** With VoiceOver on, and again at the largest text size
  (Settings > Accessibility > Display & Text Size > Larger Text): You > Downloads' Your library section
  - each switch read as one, with its note as the hint, the line of what fits as one - the Library's
  card, and Downloading's row for your library. Nothing cut off or overlapping.

### Playlists' checks (64-69)

These come with the build that adds playlists (still app 0.9). Have a playlist or two in the web app
first - one with songs from several albums - and, if you can, one someone else shares with you.

- **64 Your playlists.** Library > Playlists: the same playlists as the web app's Playlists, under Yours
  and Shared with you, and From files folded (if you have any). Does each row say what the web app's
  row says? Note whether the covers show, at the rows' size and at the top of a playlist's page.
- **65 Playing one.** Open a playlist of songs from several albums: Play plays it in order; Shuffle in a
  random order; a song's tap from that song. Each song shows its own album's cover in the mini player,
  Now Playing and on the lock screen. Info > About on a song names its own album and year, and says
  "Track 5" alone - no "of 12", and no disc line. Then, while it plays, open a dozen album pages or more
  from the Library, and skip to the playlist's last songs: Info still names each one's album and year.
- **66 Normalization.** With Normalization on Automatic, play a playlist: Info > About > Sound >
  Normalization says "Song volume matching, ..." for each song, never "Album volume matching".
- **67 Play Next from a playlist.** A song's •••: Play Next and Play Last queue that song; the •••
  at the top queues the whole playlist. Go to album from Now Playing opens the song's own album, whole.
- **68 Changed elsewhere.** Add a song to a playlist in the web app or Amperfy; back on the phone, go
  back to Playlists and open the playlist again: it has the song. Delete a playlist in the web app with
  its page open on the phone, then pull down on it: it says it isn't on Navidrome any more.
- **69 Offline.** Download a song of a playlist (its •••), then turn on Airplane Mode with the playlist
  open: only that song is bright, and Play plays it. Go back to the Library (it may open on Downloaded):
  Playlists is there, and that playlist opens; one you haven't opened, or with nothing on the phone, is
  dimmed. Also: a playlist of a
  few hundred songs - does it scroll smoothly? And with VoiceOver, is each row read as one?

### Playlists' changes' checks (70-76)

These come with the build that adds Add to a playlist, New, Edit and Delete (still app 0.9). Have the
web app open beside the phone, and Amperfy if you use it. Make a test playlist for these: 75 deletes
one.

- **70 Make one.** Library > Playlists > **+**: a name, **Create** - its page opens, empty, saying how
  to add songs. Then it's in the web app's Playlists, and Amperfy's, under the same name.
- **71 Add to a playlist.** From an album's •••, a song's on an album page, a song's and the top one
  on a playlist's page, and Now Playing's •••: **Add to a playlist…** opens your playlists - does it
  say what you're adding, with the one changed last at the top? Tap one: it closes and says "Added 11
  songs to …". Then **New playlist…** in it: a name, Create - "Made … with …". In the web app, the songs
  are there, in that order. Then, ideally with the server slow: tap a playlist, close the picker while
  it says Adding…, open it again (or Now Playing's) and tap the same one - is it still Adding…, and
  are the songs in the playlist only once?
- **72 Already in it.** Add the same album to the same playlist again: "These 11 songs are all in …
  already." - try Add them again, then remove the copies in Edit. Add an album with one song of it in
  the playlist: "1 of these 11 songs is in … already." - Skip that one adds the other 10. One song
  that's there: "… is in … already." Does each button do what it says?
- **73 Edit.** On a playlist of yours: Edit - rename it, change the description, turn on Shared with
  everyone, drag a song, take one out with its red minus (does one tap do it?), Done. It says Saving…,
  then shows it saved; the web app agrees, and Amperfy after a refresh. Clear the name: "A playlist
  needs a name." and Done dimmed. Change something and Cancel: it asks "Discard your changes?". Do the
  fields take typing, and the switch a tap, while the songs can be dragged? Type past 200 letters in
  the name, and paste a long line into it: it stops at 200. Tap the Library tab while editing: it stays
  on the playlist. Make Done fail (Airplane Mode just after tapping it): does the page go to why?
- **74 Changed elsewhere.** Tap Edit on the phone, add a song to that playlist in the web app, then
  change something on the phone and tap Done: it says the playlist changed in another app and your
  changes weren't saved, and shows it with the web app's song.
- **75 Delete.** Edit > Delete playlist: the question, then Delete playlist. Back on Playlists, "Deleted
  …", and it's gone from the web app and Amperfy. Then New playlist twice quickly: **+**, a name, Create,
  swipe the sheet away at once, **+** again - the second sheet stays, with what you type in it.
- **76 Only yours, and offline.** A playlist shared with you, or one from a file: no Edit, and Add to
  a playlist… never lists it. In Airplane Mode: no Add to a playlist… in the ••• menus or Now
  Playing's, and **+** and Edit dimmed. With VoiceOver in Edit: each song's actions (Move up, Move
  down, Remove), and what's said ("Roads: 3 of 12", "Roads removed").

### Downloaded playlists' checks (77-84)

These come with the build that downloads a playlist (still app 0.9). Use a test playlist of a dozen
songs from a few albums, on Wi-Fi, with the web app open beside the phone.

- **77 Download one and play it offline** (the phase's). On its page, tap the arrow beside the •••: it
  becomes a ring, the page says "Downloading - 4 of 12 songs" as they come, and You > Downloads has its
  row ("3 of 12 songs to go") with a bar. Once all are here: "This playlist is downloaded - it plays with
  no connection." Then Airplane Mode, force-quit the app and open it again: in the Library (it may open
  on Downloaded), Downloaded has **Downloaded playlists** with its count; the playlist opens, every song
  is bright, and Play, Shuffle and a song's tap play it - across albums, each with its own cover. Library
  > Playlists, still in Airplane Mode: it's listed, bright.
- **78 Kept in step.** Add a song to it in the web app, then open it on the phone: the song comes (the
  ring, then here). Take a song out in the web app and open it again at once: the song has left the
  page, but it's still on the phone - the song count under Storage in You > Downloads hasn't dropped;
  ten minutes or more later (open it again, or leave the app open) it's gone from the phone. Take a song
  out with **Edit** on the phone, Done: it's gone from the phone at once.
- **79 What stays.** Download a song of the playlist by hand first (its •••), and an album one of its
  songs is on. Download the playlist; then a song only the playlist brought: its ••• says "Downloaded
  with …" and has no Remove Download. **Remove Download** on the playlist (the mark, or its •••): the song
  you downloaded yourself and the album's songs stay; the rest go. With Download your library on and an
  album of your library in the playlist, turn the switch off: the playlist's songs stay.
- **80 Where it is.** Library > Downloaded > **Downloaded playlists**: the playlist, by name. You >
  Downloads > Downloaded: the playlist first, "12 songs · 412 MB", its songs not under an album row of
  their own; tap it for its page; swipe it to Remove. **Remove All Downloads**: does the question say the
  downloaded playlists go too and stay in your playlists? Afterwards, Downloaded playlists is empty and
  the playlist is still in the web app.
- **81 Deleted.** Delete a downloaded playlist with Edit > Delete playlist: its songs go from the phone
  at once (those you downloaded yourself stay). Delete another in the web app: on the phone it stays,
  playable, for ten minutes or more, then goes with the app's next look.
- **82 Room.** Set the storage limit below what's on the phone plus the playlist, and download it: the
  whole playlist waits ("Waiting for room - the storage limit is reached"), none of it half-fetched;
  raise the limit and it comes. Then, the limit low again: download a big song of another playlist by
  hand, and while it's still coming download that playlist - the song finishes, and the rest of the
  playlist waits for room.
- **83 VoiceOver.** The arrow reads "Download"; while it downloads, its value says how far; downloaded,
  the mark opens its menu with what it is and Remove Download. A Downloading row reads as one ("Late
  night, 3 of 12 songs to go, 75 percent").
- **84 Smart playlists** (deadwax 2.1.21 or later says which playlists are smart). Open a
  smart playlist: no arrow beside the •••, nothing to download in the •••, and under its count "Smart
  playlists are worked out again each time, so this one plays only while deadwax can be reached." An
  .m3u playlist still has its arrow. If you downloaded a smart playlist on an earlier build: it's still
  on the phone, its line says it stays as it was when you made it, and Remove Download takes it off.

### Going back's checks (85-91)

These come with the build that learns going back in Up Next (still app 0.9), and want deadwax 2.1.18 or
later. Use an album of a dozen songs, headphones on, with the web app open beside the phone.

- **85 A song you played, tapped.** Play the album from song 1 to song 5 (Next is fine), then Play Next
  two songs from another album. Open Up Next and tap song 2 above the song playing: it plays at once,
  from its start, with no gap you wouldn't hear at a Previous. Does the row you tapped stay under your
  finger, now as the song playing? Under it: 3, 4, 5, the two songs you added, then 6 on - and nothing
  above it but song 1. Next, Next, Next: 3, 4, then 5 from its start; Next again: the first song you
  added. Previous from song 2 plays song 1.
- **86 Repeat.** Repeat One on song 3 until it has played three times, Repeat off, then Next: tap song 3
  above - it plays once, then 4 (its repeats went: a row plays once), and it starts cleanly. Now Repeat
  All: play past the album's end into the second time round, to its song 3, and tap the first time
  round's song 11 above: Up Next lists 12, then the second time round's 1, 2 and 3 as one list, then the
  rest. Turn Shuffle on: 12 stays first (the first round's), then 1, 2 and 3 of the second round in some
  order, then the rest - does the second round ever start with 12? Shuffle off: 12, 1, 2, 3, 4...
- **87 From before the album.** Play another album first for a song or two, then this one. In Up Next,
  scroll above to the other album's songs and tap the first of them: it plays at once; below it the
  other album's songs after it, then this album's songs as played, then the song that was playing,
  then the rest. Nothing above it (Previous starts it again). Is each tapped song drawn only once - below,
  never above as well? Let them play: each shows above again as it plays, here and in the web app's Up
  Next.
- **88 Locked.** Go back to a song with the phone about to lock, lock it: does it keep playing, and does
  the lock screen show the song you went back to? Do Next and Previous there follow Up Next's new order?
- **89 Picked up.** After going back, force-quit the app and open it again: paused at the song you went
  back to, with the songs moved back down still under it in the same order. Open the web app (reloaded,
  2.1.18 or later): it picks the queue up the same. Go back there, then open the phone: the same again.
- **90 Offline.** In Airplane Mode with the album downloaded, go back to a song: it plays. A song above
  that isn't on the phone is dimmed and a tap does nothing.
- **91 VoiceOver.** Tap a song above the song playing with VoiceOver on: it says "Playing" and the title,
  and VoiceOver is on the song that plays next (Done, at the end of the queue).

### The Library's switch's checks (92-101)

These come with the build that adds the Library's switch, its pull to shuffle and the web app's Play
button (still app 0.9). Earlier checks' "Library > Playlists" is now the switch's Playlists page, and
"Downloaded" is in the Library's •••.

- **92 The switch.** The Library opens on Albums, with nothing above the albums but their count, and
  Albums | Playlists at the top. Swipe left: Playlists - the switch, the buttons and Find follow as the page
  settles; swipe halfway and let go: it springs back, and nothing else changes. Tap Albums: back. Go to
  You and back: the same page. Scroll a long way down and tap the Library tab: the page goes to its top.
  Force-quit and open: Albums. Scrolling up and down never swipes to the other page.
- **93 Edit order.** ••• > Edit order: drag Playlists above Albums, Done. The switch reads Playlists |
  Albums at once; force-quit and open: the Library opens on Playlists. (Put it back as you like it.)
- **94 The •••.** Downloaded opens what's on the phone - with the card asking whether to keep your library
  on this phone at its top, once, if you never answered it. All music opens All albums (with a library
  of your own). Make a playlist in the web app, then ••• > Refresh: it's on Playlists. Shuffle plays your
  library shuffled.
- **95 Pull to shuffle.** On Albums, pull down slowly: the ring fills and the mark grows and turns, "Pull
  to shuffle". At the line: a tick, the purple disc, "Release to shuffle". Push back up a little: the
  ring again, no tick; down again: another tick. Let go armed: "Shuffling", and your library plays - the
  mini player shows a song from anywhere in it. Let go before the line: nothing plays. The same on
  Playlists. A fast fling up to the top shows nothing. Pull to the purple disc, then pull down
  Notification Center (or ask Siri, or take a call) before letting go: nothing plays. Does the graphic sit
  in the gap the pull opens, at your text size? Does the music start the moment you let go?
- **96 Past the first 200** (the phase's). With the shuffle playing, press Next 160 times or so (or let it
  play an evening): Up Next keeps going, never ending at 200. With Repeat off it ends only once every song
  of your library has played; with Repeat All, at the end a new order begins with a different song. Lock
  the phone mid-shuffle for an hour: does it keep going?
- **97 Started over.** Shuffle, then restart the deadwax container (or leave the phone a day) and press Next past
  150: "Your shuffle started over - deadwax no longer had its order", once, and the music carries on.
- **98 Offline.** Airplane Mode: the Library's Albums page is Downloaded, under the same switch; ••• >
  Shuffle downloads, and a pull ("Release to shuffle your downloads"), play only songs on the phone -
  every one of them in time. ••• > Your albums is the way back. With nothing downloaded: no Shuffle in the
  •••, and the pull says "Nothing on this phone to shuffle".
- **99 The Play button.** An album's page and a playlist's: Play is the web app's purple, its white
  triangle and word plainly readable; Shuffle beside it the web app's grey, the same height and corners.
  Pressed, Play darkens, its word staying white, and Shuffle's shading turns over, as the web app's do. The
  other purple buttons - Add to my library, the EQ's Use for, Create in the
  picker, Sign in, Try again - the same purple. Does it look like the web app's Play on your screen?
- **100 Find on Playlists.** On Playlists, type part of a playlist's name: only the playlists that hold
  it; nonsense: "No playlists match “…”." Back on Albums, Find holds the albums' own words.
- **101 VoiceOver and Reduce Motion.** VoiceOver reads the switch as the Library's pages, Albums and
  Playlists; the ••• as "More for the Library", with Shuffle first. With Reduce Motion on (Settings >
  Accessibility > Motion), the pull's mark doesn't grow or turn, the states change at once, and a tap on
  the switch moves the page without sliding.

### Artists' checks (102-111)

**Not done yet.** These come with the build that adds Artists (still app 0.9). Since it, the Albums page's
order and Grid or list are in the Library's •••, and All music is a submenu: ••• > All music > All albums.

- **102 The page.** The switch reads Albums | Playlists | Artists - Artists added at the end of an order
  you'd arranged before. Swipe to Artists: every artist of your albums with "2 albums" under each, in
  letter headers, the index down the edge once there are 50 or more - the web app's Library > Artists, the
  same artists and counts. Does each round picture show the artist? Tap the Library tab: back to the top.
- **103 The •••, three pages.** On Albums: Album order (showing the one chosen) and Show as list; choose
  Title, then Show as list - the albums follow, and back. On Artists: Artist order, Most albums - most first,
  no headers, no index; back to Name. On Playlists: neither, and the + beside the •••. Force-quit and open:
  both orders and the list are as you left them. At the largest text size, does the bar fit the switch, +
  and •••?
- **104 All music.** ••• > All music: All albums and All artists. All artists: every artist of the
  collection, "12 albums in the collection" under each - the collection's count, which can be more than
  your artists' row says. Pull down: it refreshes, no shuffle. With logins off: no All music, and the
  Artists page is every artist, the count alone under each ("12 albums").
- **105 Find.** On Artists, type part of a name ("bj" for Björk, "beat" for The Beatles): only the artists
  whose name holds it, "3 of 120 artists"; nonsense: "No artists match “…”." Back on Albums and
  Playlists, Find holds their own words.
- **106 An artist's page.** Open an artist with several albums: the round picture, the name, Play and
  Shuffle dimmed for a moment under "Getting the songs of the 3 albums you have…" ("in the collection" with
  logins on), then "Plays the 3 albums you have". Their albums are newest first, the undated last, each
  "1994 · in your library" with a green tick - or "in the collection", no tick, for one that isn't in your
  library. Tap one: its page. Back: the page as it was, nothing fetched again. Go back to the list and
  open them again: their albums at once, and "Getting the songs…" or "Plays…" at once under Play - never
  "None of their albums are here to play." while their albums are listed.
- **107 Play and Shuffle.** Play: the newest album from its first song, then the next album, and so on -
  Up Next lists them in the page's order. Shuffle: songs from every album, in no order, with Shuffle on.
  Does the music start the moment you tap, both times? With Normalization on Automatic, Info says Play's
  songs are levelled as an album, Shuffle's as songs.
- **108 The album's artist.** On an album's page the artist is purple: tap it - their page. An album from
  Up Next or Now Playing's Go to the album: the same. Does the name ever flash from grey to purple as the
  page loads? In Airplane Mode, Now Playing's Go to the album for a song that isn't downloaded: the name
  grey, not a purple one that can't be tapped.
- **109 Cut off.** Open an artist with many albums and turn on Airplane Mode before the line says
  "Plays…": "Only downloaded albums play until deadwax is back.", the albums not on the phone dimmed.
  Airplane Mode off: in a moment, "Plays the 5 albums you have" - the albums that didn't come are asked
  for again by themselves. (Should one still not come, the line says "Plays 4 of the 5 albums you have -
  the rest didn't load", with Try again under it.)
- **110 Offline.** Airplane Mode: the Artists page lists as before, an artist with nothing downloaded
  dimmed. Force-quit and open in Airplane Mode: the artists of your downloaded albums, under "Only the
  artists of downloaded albums show until deadwax is back." Open one: their downloaded albums, Play and
  Shuffle playing only those songs, "Only downloaded albums play until deadwax is back." An artist with a
  downloaded album made with someone else ("A & B") and more of their own is listed by their own name.
- **111 VoiceOver.** The switch reads Albums, Playlists and Artists; an artist's row "Portishead, 2
  albums"; an album row on their page "Dummy, 1994 · in your library"; the ••• has Album order and Show as
  list on Albums, Artist order on Artists.

## What it can't do yet

These are the web app's for now. Most of them come to the phone in the next phases:

- **The visualizer**: it stays the web app's, on a desktop.

- A **songs list**, and on an artist's page their **discography** from MusicBrainz, the **description**
  and the artist's managing (pictures, names).
- **Search**, **Get** and **Requests**.
- **Home** and **pins**.
- **Looking after deadwax**: People, Server settings, the event log, Needs a look, Library care, the
  editors, and changing your password. For an admin, **Set up Navidrome** opens the web app in Safari.

## When something goes wrong

| what you see | what to do |
| --- | --- |
| **"Couldn't reach deadwax at ..."** on the address screen | Check the address, and that the phone is on your home Wi-Fi or WireGuard. If you said no to the local network question, turn deadwax on in Settings > Privacy & Security > Local Network. |
| **"Can't reach deadwax. Check you're on the right network (or your VPN is on) and try again."** as the app opens | The same: the phone's network, or deadwax itself. **Try again**, or **Change address** if deadwax has moved. What failed, for whoever runs deadwax, is folded away under it. |
| **"Something went wrong on the server - try again in a moment."** as the app opens | deadwax answered, with an error. **Try again**; if it lasts, deadwax's log says why. |
| Sign in: **"That user name and password didn't work."** | Your Navidrome user name and password, as on the web app. |
| Sign in: **"Too many tries for ... - wait ... seconds and try again."** | deadwax holds off so Navidrome doesn't lock the account. Wait, then try again. |
| Sign in: **"Navidrome isn't answering, so deadwax can't check your password right now - try again in a moment."** | deadwax signs people in through Navidrome, and Navidrome is down, or deadwax can't reach it. Check that Navidrome is running, then sign in again. |
| Sign in: **"deadwax can't reach the music server, so nobody can sign in just now. Tell whoever runs deadwax."** | deadwax hasn't been told where Navidrome is, or the address it has can't be used. Whoever runs deadwax sets it in [Navidrome settings](configuration.md#navidrome-settings--connections); what's wrong is folded under "For whoever runs deadwax". (A deadwax older than 2.0.4 says "Something went wrong on the server - try again in a moment." here instead.) |
| The sign-in comes up over the app, with a reason ("Your sign-in ran out after 30 days without use - sign in again.") | Sign in again. The music plays on underneath. |
| Library: **"Your music isn't available right now"** (an admin sees **"Can't reach Navidrome"**) | deadwax can't reach Navidrome. Check Navidrome is running, then **Try again**. |
| Library: **"Your music isn't available yet"** (an admin sees **"Connect Navidrome"**) | deadwax hasn't been told where Navidrome is. An admin's **Set up Navidrome** opens the web app in Safari: set it up in Server settings (Connections), then come back. |
| Library: **"Couldn't update this list - showing it as it was."** | deadwax didn't answer just then. ••• > Refresh to try again (pull down, on a list opened from the •••). |
| An album's page: **"This album isn't here any more - it may have been moved or deleted."** | Go back, and ••• > Refresh in the Library to bring it up to date. |
| An artist's page: **"This artist isn't here any more - their albums may have been moved or deleted."** | The same: go back, and ••• > Refresh. |
| An artist's page: **"Plays 2 of the 5 albums you have - the rest didn't load"**, or **"Couldn't load their songs."** | deadwax didn't send those albums' songs just then. **Try again** under it; Play and Shuffle meanwhile play the albums that came. |
| A song's line says **"The connection dropped while this song was loading"**, or the next song's says **"Skipped "..." - it wouldn't play"** | The app asks for a song once more after a moment, then goes on past it. Check the phone's network. |
| **"This device couldn't play this song's audio"**, or **"Skipped "..." - this device couldn't play its audio"** | The file is damaged, or in a form iPhones can't play. Try it on the web app; an admin finds the details in You > Debug > Playing. |
| Info's Normalization: **"Not this time - the album's volume couldn't be checked"** ("the song's" for a song levelled on its own) | deadwax is older than 2.1.1, or didn't answer in time. The song plays as it is; with 2.1.1 or later, the album's next play is levelled. |
| Lyrics: **"Couldn't load the lyrics."** | deadwax, or Navidrome behind it, couldn't give them just then: **Try again**. If it's every song, deadwax may be older than 2.1.5, which has no lyrics for the app (an admin sees why, folded under it). |
| Lyrics: **"This song isn't here any more - it may have been moved or deleted."** | Navidrome no longer has the song the queue names (a rescan moved it). Play it again from its album. |
| A playlist has no **Edit**: "Only Sam can change this playlist." | It's Sam's: only they can change it. A playlist from a file, or one of more than 2,000 songs, says why there's no Edit too - change those in Amperfy or Navidrome. |
| Edit: **"This playlist changed in another app while you were editing it - here it is now. Your changes weren't saved."** | It was changed elsewhere after you tapped Edit, so nothing was saved. Tap Edit and make your changes again on the playlist as it is now. |
| Edit: **"The songs were saved, but Navidrome didn't take the name, description or sharing."** | Edit stays open: **Done** again saves the rest. |
| Edit: **"Saved - but Navidrome didn't answer when deadwax asked for the playlist again."** | It's saved. **Done** again, or **Cancel**, and the page asks for it again. |
| The app's notice: **"Couldn't add to Late night."** and why | An add you'd closed Add to a playlist on was refused, or its answer didn't come back. Try again: if the songs did get in, it asks before adding them twice. |
| **Lyrics** is dimmed | The song has none - none on LRCLIB, or none fetched yet (**Get lyrics** in the album's Edit, on the web app). Offline, "Lyrics - not on this phone": none were kept for it, which happens to a song downloaded with app 0.3 until the app has been opened with deadwax in reach. |
| The EQ's correction picker: **"Something went wrong."**, with **Try again** | deadwax answered with an error. If it's every search, deadwax may be older than 2.1.7, which has no AutoEq for the app (an admin sees why, folded under it). |
| An album stays on **"Waiting for Wi-Fi"** | Download over is Wi-Fi only (You > Downloads): join a Wi-Fi network that isn't a phone's hotspot, with Low Data Mode off - or choose Wi-Fi and cellular. |
| **"Waiting for room - the storage limit is reached"** | Raise the Storage limit in You > Downloads, or remove something there (largest first). |
| Your library's albums stay on **"Waiting for the phone to charge"** | Only while charging is on (You > Downloads, under Download your library): plug the phone in, or turn it off. Albums you download yourself don't wait for it. |
| Your library didn't download with the app closed | iOS decides when the app runs in the background, and may not for hours; Background App Refresh off (Settings > General) or Low Power Mode stops it, and so does swiping deadwax away in the app switcher. Opening the app checks and downloads at once. You > Debug > Your library > In the background (an admin's) says whether iOS ran it. |
| **"Waiting for space on this phone"** | The phone itself is full: make room in Settings > General > iPhone Storage. |
| **"2 songs didn't download"**, with why ("The copy kept arriving the wrong size.", "The copy's sound didn't match the original.", "This song isn't on deadwax any more.") | **Try again** in You > Downloads. If it keeps failing, the file on the server may be damaged: play it on the web app. |
| You > Downloads: **"This phone couldn't read its downloads - close deadwax from the app switcher and open it again."** | Downloads are off until the app opens again; nothing is deleted, and downloaded songs stream meanwhile. If it lasts, the phone may be nearly full. |
| **"Not on this phone - it plays once deadwax is back."** | The song isn't downloaded and deadwax can't be reached. Download what you want offline before you go. |
| The beep album isn't found | Make it with `make-test-album.py` into your music library (see "What you need"), let Navidrome scan it, then Check again in You > Debug (an admin's). |
| **"Untrusted Developer"** when opening the app | Settings > General > VPN & Device Management > your Apple ID > Trust. |
| The app won't open at all after a week | The free install ran out. Run `install.sh` again: nothing on the phone is lost. |
| install.sh: **"No paired iPhone the Mac can reach now"** | Connect the cable and unlock the phone (or turn on Connect via network in Xcode, with the Mac and the phone on the same Wi-Fi), then run it again. |
| install.sh: **"Xcode has changed ios/Deadwax.xcodeproj here"** | A team was picked in Xcode's Signing & Capabilities. Run `git checkout ios/Deadwax.xcodeproj`, keep the team in `ios/Config/Local.xcconfig`, and run install.sh again. |
| install.sh: **the build failed** with a signing or profile error | The first install has to come from Xcode with the cable (step 5 of "Once"). After that, the script renews the signing by itself. |
| install.sh: **Xcode knows no Apple ID** | Add it in Xcode > Settings > Accounts, then run the script again. |
| A free account says it can't install more apps | A free account can have only 3 of its own apps on the phone at once. Delete one you don't need. |
