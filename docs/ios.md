# The iPhone app (early: Phase 2, downloads)

deadwax is getting a native iPhone app, built with SwiftUI and its own audio engine, for what a web
page can't do well: seamless joins and normalization done on the phone, downloads to play offline,
and a song's start never lost on AirPods. It's built in phases. Phase 0, "Hello, iPhone", was a
single test screen that proved the tools, the connection and the audio engine. **This is Phase 1,
the player: app 0.2**, the first version meant for playing your music day to day. It has your
library, album pages, Up Next, Now Playing, normalization, the lock screen, plays counted, and
picking up where you left off. **Phase 2 adds downloads**: an album, or a song, downloaded to the
phone plays from there, bit for bit as deadwax has it - and goes on playing when deadwax can't be
reached (see [Downloads](#downloads) and [Offline](#offline)). Playlists, Search and the rest come in
the next phases (see [What it can't do yet](#what-it-cant-do-yet)).

**Nothing of Phase 2 has been seen on an iPhone yet.** It's built and tested on a Mac, and what only
a phone can tell is what [the checks](#the-checks) are for. Until they're answered, read everything
about downloads below as what the app is built to do.

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
you have.

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
install runs: `Installed deadwax 0.2 (2), runs until Wed 18 Nov, 14:02`. It also says how long it
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

With logins on, the Library is **Your albums**: the albums in your library, as the web app's Library
has them ([sharing deadwax](sharing.md) says how an album gets there). Above them, **All music >
All albums** is the whole collection. With logins off, and for the break-glass `deadwax` sign-in,
the Library is **Albums**: the whole collection.

- **Grid or list**: the button at the top right switches between covers and rows. It starts as a
  grid, and this phone remembers your choice.
- **The order** (the button beside it): **Artist** (the first time), **Title**, **Recently added**,
  **Year, newest first** or **Year, oldest first**, under headers: the first letter (names that don't
  start with a letter come last, under #), the month it was added ("Date unknown" when deadwax
  doesn't know), or the year ("No year"). In Your albums, Recently added means when the album came
  into your library; in All albums, when the collection got it. This phone remembers the order.
- **Find** at the top keeps the albums whose title or artist holds every word you type, in any order
  and anywhere in a word ("eat" finds the Beatles). The count above the albums then says "12 of
  3012 albums".
- **The index** down the right edge, once a list has 50 albums or more: A to Z and # for Artist and
  Title, decades for the two Year orders. There's none for Recently added, or while you're finding.
  Touch or slide along it to jump.
- **New** marks an album that came into your library and that you haven't opened yet, here or on the
  web app. Opening it clears the mark, on both.
- **Tap an album** to open its page. Nothing plays from the Library itself.

The list is kept on the phone, so the Library shows at once when the app opens, and is asked for
again when it's more than a minute old. Pull down to ask now. If deadwax can't be asked, the list
stays as it was, under "Couldn't update this list - showing it as it was." deadwax lists at most
10,000 albums; past that, the Library says "Showing the first 10000 albums - deadwax reads at most
that many."

An empty Your albums says "Nothing in your library yet.", with **See All music** to add some from
the collection. (Its words mention Search and Get: those are the web app's, for now.)

**Downloaded.** Once anything is downloaded, on its way or didn't download, the top of the Library has
**On this phone > Downloaded**, with how many albums. It's every album with a song on this phone,
whoever's library it's in, drawn as the other lists are: the same orders, Find, headers and index.
Its **Recently added** means downloaded to this phone, newest first. Each album there has a third
line: "12 songs", "3 of 12 songs", "Downloading", "Waiting", or, in amber, "Didn't download". With
nothing on the phone it says "Nothing downloaded yet."

**The download marks**, at the end of an album's artist line on every list (and on a song's row on an
album's page): a filled arrow for downloaded (all of it, or some of its songs), a dotted one while it
waits, a ring filling as it downloads, and an amber **!** for didn't download. VoiceOver says them in
words after the artist: "Downloaded", "Partly downloaded", "Downloading", "Waiting to download",
"Didn't download".

**The Library needs Navidrome**: it's the albums Navidrome lists, through deadwax. If deadwax can't
reach Navidrome, or hasn't been told where it is, the Library says so instead of showing albums (see
[When something goes wrong](#when-something-goes-wrong)) - with **On this phone > Downloaded** under
it when anything is downloaded, since those play from the phone. It checks again each time you come
back to the Library tab or the app, and when you pull down.

## An album's page

- **At the top**: the cover, the title, the artist, and a line like "Electronic · 1998 · FLAC" (the
  genre, the year, and the format when all its songs share one). It says whether the album is **In
  your library** or only **In the collection**. With logins off, and for the break-glass `deadwax`
  sign-in, every album reads In your library.
- **Play** plays the album from its first song. **Shuffle** plays it in a random order, with Shuffle
  on.
- **The songs**, under a heading for each disc when there's more than one, or a disc has a title
  ("Disc 2", or "Disc 2 · Live" with its title). The song playing has moving bars instead of its
  number. **Tap a song** to play the album from it. Under the songs: how many and how long ("10
  songs, 42 min").
- **•••** at the end of a song's row has **Play Next** and **Play Last** for that song; the **•••**
  at the top has them for the whole album (see [Up Next](#up-next)). Each menu opens from the •••
  you tapped, and a tap anywhere else closes it.
- **Add to my library** and **Remove from my library**, with logins on. Removing takes the album out
  of your library only: "it's still in the collection, and nothing was deleted."
- The artist's name is plain text for now: artist pages come in a later phase.

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

With Normalization on, opening an album that has FLAC songs asks deadwax to measure it, if it hasn't
yet, so its first song is less likely to wait when you play it.

## Playing

**The mini player**, above the tabs: the cover, the song and its artist, play/pause and next, and a
thin line along it for how far in the song is. Tap it for Now Playing.

**Now Playing**: the cover (a little smaller while paused), the song's title, and "artist — album"
(tap it to go to the album). Under them:

- **The scrubber**: tap a place to go there, or drag and let go. The clocks say how far in the song is
  and how much is left. VoiceOver reads it as "Position in the song", in 5-second steps.
- **Shuffle, previous, play/pause, next, Repeat.** Previous goes back to the song before in a song's
  first 3 seconds; after that, or on the first song, it starts the song again. Repeat goes from off to
  **Repeat all** to **Repeat one** and back to off, and this phone remembers it.
- **AirPlay**, **Up Next**, and **•••**, whose menu has **Info**, **Go to album**, **Download** (or
  Remove Download) for the song playing, and **Download Up Next** - every song still to play that
  isn't on the phone, when that's two or more. Go to album closes Now Playing and opens the album's
  page on the tab you're on. What a download item did is said for a moment at the top of Now Playing
  ("Downloading: Roads", "Downloading 23 songs from Up Next").
- The chevron at the top, or a swipe down, closes it.

### Up Next

**Play Next** puts a song (or an album) straight after the song playing; **Play Last** puts it after
the songs you've already added, still ahead of the rest of the album. A line above the mini player
says which ("Playing next: Roads", "Added to Up Next: Dummy") for 5 seconds. With nothing playing,
either just plays it.

**Up Next** on Now Playing opens what plays after the song playing - and, above it, what has already
played:

- **History**, above the song playing: what has played since you started the album, list or shuffle -
  songs a tap skipped past included, where they are on the album - oldest at the top. Up Next opens at
  the song playing, even with only a song or two left after it; scroll up for History. A song Repeat One
  played again is one row; Repeat All's earlier times round are there as they played. It goes back 50
  plays (as many as come back when you pick the queue up on another device) - each time Repeat One
  played a song counts as one - and starts again when you play something new. **Tap one** to hear it
  again now ("play again", VoiceOver calls it, and says "Playing" and its title once it starts): Playing
  Next and the album carry on after it as they were, the song that was playing joins History, and the
  list stays where it is under your finger. VoiceOver reads History under its own heading, then the song
  playing's title as one.
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
  made as you make it. History isn't shown while you edit. **Done** ends Edit. Outside Edit, a row can't be swiped away, so a song isn't
  lost by accident. Inside Edit iOS has no swipe-to-delete, so the minus takes a song out with one
  tap - and there's no undo, so a quick double tap takes out the song that moves up under your finger
  too. With VoiceOver, each row's actions have Move up, Move down and Remove; with Voice Control, say
  "Show grid" to reach a minus.
- It closes by itself once nothing is queued.

**Shuffle**, turned on while a song plays, keeps that song going and shuffles every song of the album
or list you haven't heard this time round. Turned off, the album's own order carries on from the song
playing. Either way the song playing goes on, untouched, and songs you added keep their order, ahead of
the rest.

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
  that isn't.

An admin also has a **Debug** tab: the file, what was sent to the phone and how it's being played
(**Sent as**, **On this phone** - the downloaded copy's check, and for a FLAC its fingerprint, bits,
rate and channels -, **Normalization** in numbers like "Album, -3.60 dB · the album at -14.4 LUFS",
**Gapless**, **Output**, **Conversion**, **Lane**, **Buffered ahead** and **Last start**), and every
field Navidrome sent about the song and its album.

## You

- **At the top**: who you're signed in as, or "No sign-in needed" with logins off.
- **Playback**:
  - **Gapless**: On. "Albums play straight through, with no gap between songs." It isn't a setting:
    the app always plays this way.
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
- **Downloads**: what's on this phone ("2.1 GB"), opening [You > Downloads](#you--downloads). Under
  it, only while something is happening: "Downloading - 6 songs to go", what it's waiting for, or, in
  amber, "2 songs didn't download".
- **Account**, with logins on: **Sign out**. It ends this phone's session and stops what's playing.
  With anything downloaded, it adds that your downloads stay on this phone for when you sign in again.
  If deadwax can't be reached, it says "Couldn't reach deadwax, so you're still signed in - try
  again." Changing your password is the web app's, for now.
- **About**: deadwax's version, whether logins are on (for an admin), and the app's own version,
  **0.2 (2)**.
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
- **Hi-res**: **Find a 24/192 FLAC** looks through the library (up to 10,000 songs) for a 24-bit
  192 kHz FLAC, or the highest rate there is, to play. This needs a Navidrome that says each song's
  sample rate (OpenSubsonic's `samplingRate`).
- **Playing**: the song, how far in, previous, play/pause and next, and a line like
  `24-bit 192 kHz FLAC file → 48 kHz output (AirPods Pro)`. The app decodes each file at its own
  rate, with nothing changed. When the output runs at another rate, the app's audio engine converts
  the song to it, as any app must: an iPhone's own outputs and AirPods run at 48 kHz or lower. Under
  it, "An edit held for the next song" when one is (see [the checks](#what-only-a-phone-can-tell)), and
  the last song that failed, in its own words.
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
  deadwax; plays waiting to be sent; how long the sound checks took; and the last 50 download events.
- **Library**: how many albums each list had, whether it came new or the kept one still stood, and
  how long it took to come.
- At the bottom, how long this install runs. In its last two days, it also says to run install.sh
  before then.

## The lock screen and interruptions

The lock screen and Control Center show the song, its artist, album, cover and how far in it is. The
next song's cover is fetched while a song plays, so the lock screen's cover changes with the song.
Play, pause, next and previous work there, as does dragging the position, and the AirPods' presses
work too. A phone call or Siri pauses the music, and it carries on when they're done. Taking an
AirPod out pauses it.

## Plays

A song is counted as played in Navidrome once you've heard half of it, or 4 minutes, whichever comes
first. Songs of 30 seconds or less don't count. That's the rule the web app uses, and Last.fm's.
Navidrome passes plays on to Last.fm or ListenBrainz if it's linked to them, and is told what's
playing now. A play that can't be sent - deadwax out of reach - is kept on the phone with its time and
sent once deadwax answers again (see [The first time you open it](#the-first-time-you-open-it)).

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
  starts by itself when it can.
- **Removing** one album or song needs no confirmation: it can be downloaded again. **Remove All
  Downloads** asks first.
- **Per person.** Each person signed in on the phone has their own downloads. Signing out keeps
  yours, for when you sign in again; another person's are listed as "Other accounts on this phone".

### You > Downloads

- **Storage**: what's downloaded ("2.1 GB of 20 GB"), a bar, and "12 albums · 148 songs · 41.2 GB
  free on this phone". **Storage limit**: 5, 10, **20 GB** (the default), 50, 100 GB, or No limit.
  Lowering it below what's here removes nothing: new downloads wait for room, and it says so in
  amber. The 2 GB of songs kept from streaming are apart from it. With other accounts' downloads on
  the phone, **Other accounts on this phone** has their size and **Remove** (it asks first).
- **Download over**: **Wi-Fi only** (the default) - never mobile data, a phone's hotspot or Low Data
  Mode - or **Wi-Fi and cellular**. Under them, what the phone is on now ("On mobile data now -
  downloads wait for Wi-Fi."), in amber while a download waits for it. Changing it applies at once.
  Both settings are kept on this phone.
- **Downloading**: each album on its way - "4 of 12 songs", or what it waits for, with a bar while it
  downloads. **Didn't download**: each album with songs that didn't, why, and **Try again** (**Try
  all again** when there's more than one). **Downloaded**: every album on the phone, largest first,
  with its size and its check - **Checked** (for a file that isn't FLAC, its size is all there is
  to check), **Checked by size** (a FLAC that carries no fingerprint), or **Checking…**. Tap a row for its album; swipe it to **Remove**.
- **Remove All Downloads**, which asks first.

## Offline

When the phone has no network, or deadwax doesn't answer (WireGuard off, away from home), the app
says so in an amber strip at the top of each page - "Offline - showing what's on this phone", or
"Can't reach deadwax - showing what's on this phone". Tap it for more, and, when deadwax isn't
answering, **Try again**. It goes by itself once deadwax answers.

- **The Library opens on Downloaded.** It changes only when you're not looking at it (another tab, an
  album open over it, the app in the background), so it never moves under your finger; until then the
  list you were on stays, with every album not on the phone dimmed. At the top, **Your albums** (or
  **Albums**, without a library of your own) takes you to the full list, dimmed but for what's here. A pull down checks whether
  deadwax is back.
- **An album's page** shows what's on the phone, dims the rest, and Play and Shuffle play only the
  songs here. An album with nothing here says "This album isn't on this phone - it plays once deadwax
  is back."
- **Playing**: a song that isn't on the phone is passed over to the next one that is ("Skipped "Roads"
  - it isn't on this phone"). With nothing left that's here, the player stops on it, paused: "Not on
  this phone - it plays once deadwax is back." Play tries it again.
- **Covers**: a downloaded album's is on the phone. Any other album's shows only if it was on screen
  a moment ago; otherwise it's an empty square until deadwax is back.
- **Opening the app** with no network: it opens at once, as last time, onto the strip and Downloaded,
  with the queue you were last playing put back, paused (see
  [Picking up where you left off](#picking-up-where-you-left-off)).
- Plays are kept and sent later; downloads waiting carry on once the phone, or deadwax, is back.

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
   song again; Repeat All starts the album again after its last song. Then **History**: play an album
   from song 5, tap song 8 in Up Next, and press Previous three times - 7, 6, 5. Scroll up: History has
   the songs played. Tap one: it plays again, the row stays under your finger, and Up Next carries on as
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

## What it can't do yet

These are the web app's for now. Most of them come to the phone in the next phases:

- **Up Next's marks**: Up Next doesn't show which songs are downloaded yet.
- **Playlists**, **artist pages** and a **songs list**, and the Library's **Shuffle** of your whole
  library.
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
| Library: **"Couldn't update this list - showing it as it was."** | deadwax didn't answer just then. Pull down to try again. |
| An album's page: **"This album isn't here any more - it may have been moved or deleted."** | Go back, and pull down on the Library to bring it up to date. |
| A song's line says **"The connection dropped while this song was loading"**, or the next song's says **"Skipped "..." - it wouldn't play"** | The app asks for a song once more after a moment, then goes on past it. Check the phone's network. |
| **"This device couldn't play this song's audio"**, or **"Skipped "..." - this device couldn't play its audio"** | The file is damaged, or in a form iPhones can't play. Try it on the web app; an admin finds the details in You > Debug > Playing. |
| Info's Normalization: **"Not this time - the album's volume couldn't be checked"** ("the song's" for a song levelled on its own) | deadwax is older than 2.1.1, or didn't answer in time. The song plays as it is; with 2.1.1 or later, the album's next play is levelled. |
| An album stays on **"Waiting for Wi-Fi"** | Download over is Wi-Fi only (You > Downloads): join a Wi-Fi network that isn't a phone's hotspot, with Low Data Mode off - or choose Wi-Fi and cellular. |
| **"Waiting for room - the storage limit is reached"** | Raise the Storage limit in You > Downloads, or remove something there (largest first). |
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
