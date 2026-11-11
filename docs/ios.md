# The iPhone app (early: Phase 1, the player)

deadwax is getting a native iPhone app, built with SwiftUI and its own audio engine, for what a web
page can't do well: seamless joins and normalization done on the phone, downloads to play offline,
and a song's start never lost on AirPods. It's built in phases. Phase 0, "Hello, iPhone", was a
single test screen that proved the tools, the connection and the audio engine. **This is Phase 1,
the player: app 0.2**, the first version meant for playing your music day to day. It has your
library, album pages, Up Next, Now Playing, normalization, the lock screen, plays counted, and
picking up where you left off. Downloads, playlists, Search and the rest come in the next phases
(see [What it can't do yet](#what-it-cant-do-yet)).

**Nothing of Phase 1 has been seen on an iPhone yet.** It's built and tested on a Mac and on Linux,
and what only a phone can tell is what [the checks](#the-checks) are for. Until they're answered,
read everything below as what the app is built to do.

The app talks only to deadwax, never to Navidrome, through deadwax's own routes, so the phone never
needs Navidrome's password.

**Which deadwax it needs.** Everything but normalization works with deadwax 2.0.0 or later.
Normalization needs **deadwax 2.1.1 or later**, which adds the route that tells the app what deadwax
has already measured of an album's loudness: each song's, and the album's as a whole. The app levels
songs on the phone from the same measurements the web app's Normalization uses. The route only reads
what's there and never measures anything itself, and it only answers about an album the signed-in
person can see in Navidrome. With an older deadwax, songs play as they are, and Info says "Not this
time - the album's volume couldn't be checked".

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
  the phone. **You > Debug** says when the install runs out.
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

From then on the app opens straight into your music. If deadwax doesn't answer as it opens, it says
"Can't reach deadwax. Check you're on the right network (or your VPN is on) and try again.", with
**Try again** and **Change address**, and it tries again by itself whenever you come back to the app.

If your sign-in ends while you're using the app (it ran out after 30 days unused, an admin reset
your password, it was ended from another device), the sign-in comes up over the app with deadwax's
reason, Now Playing closes, and the music plays on underneath. Signing in again as the same person
carries on where you were. Signing in as someone else starts afresh: nothing of the first person's
queue stays.

The app has two tabs, **Library** and **You**. Tapping the tab you're on goes back to its first
screen, or to the top of it. Once something is playing, the mini player sits just above the tabs.

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

**The Library needs Navidrome**: it's the albums Navidrome lists, through deadwax. If deadwax can't
reach Navidrome, or hasn't been told where it is, the Library says so instead of showing albums (see
[When something goes wrong](#when-something-goes-wrong)). It checks again each time you come back to
the Library tab or the app, and when you pull down.

## An album's page

- **At the top**: the cover, the title, the artist, and a line like "Electronic · 1998 · FLAC" (the
  genre, the year, and the format when all its songs share one). With logins on, it says whether the
  album is **In your library** or only **In the collection**.
- **Play** plays the album from its first song. **Shuffle** plays it in a random order, with Shuffle
  on.
- **The songs**, under a heading for each disc when there's more than one, or a disc has a title
  ("Disc 2", or "Disc 2 · Live" with its title). The song playing has moving bars instead of its
  number. **Tap a song** to play the album from it. Under the songs: how many and how long ("10
  songs, 42 min").
- **•••** at the end of a song's row has **Play Next** and **Play Last** for that song; the **•••**
  at the top has them for the whole album (see [Up Next](#up-next)).
- **Add to my library** and **Remove from my library**, with logins on. Removing takes the album out
  of your library only: "it's still in the collection, and nothing was deleted."
- The artist's name is plain text for now: artist pages come in a later phase.

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
- **AirPlay**, **Up Next**, and **•••**, whose menu has **Info** and **Go to album**. Go to album
  closes Now Playing and opens the album's page on the tab you're on.
- The chevron at the top, or a swipe down, closes it.

### Up Next

**Play Next** puts a song (or an album) straight after the song playing; **Play Last** puts it after
the songs you've already added, still ahead of the rest of the album. A line above the mini player
says which ("Playing next: Roads", "Added to Up Next: Dummy") for 5 seconds. With nothing playing,
either just plays it.

**Up Next** on Now Playing opens what plays after the song playing:

- **At the top**, the song playing - and with Repeat One on, "Repeat one: this song plays again until
  you skip it." Under it, **Shuffle** and **Repeat**, the same settings as on Now Playing.
- **Playing Next**: the songs you've added, in the order they'll play, with **Clear** to take them all
  out. It's there only when you've added some.
- **The rest of the album or list this time round**, headed "From Mezzanine" for one album's songs or
  "Still to play" for several albums', up to 100 of them, then "And 380 more songs." Under it, what
  comes after: "Then Mezzanine again from the top." with Repeat All ("Then Mezzanine again, in a new
  order." with Shuffle on too), or "Nothing after this song." at the last song with Repeat off.
- **Tap a song** to play it now, even from a pause.
- **Edit** gives each row a handle to drag it by and a button to take it out. A song moves within its
  own group (Playing Next, or the album's), and each change is made as you make it. **Done** ends
  Edit. Outside Edit, a row can't be swiped away, so a song isn't lost by accident.
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
  adjusted", or "Off" when Normalization is off.

An admin also has a **Debug** tab: the file, what was sent to the phone and how it's being played
(**Sent as**, **Normalization** in numbers like "Album, -3.60 dB · the album at -14.4 LUFS",
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
    album was still being measured". One song running into the next never waits. The choice is kept
    on this phone, and takes effect from the next thing you play.
- **Account**, with logins on: **Sign out**. It ends this phone's session and stops what's playing.
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
  **Streamed** or **Downloaded** chooses which copy plays: Downloaded plays the copies on the phone (a
  song with none is streamed). Each song's row has a download button, **Download all 10** downloads
  the lot, and **Remove the downloads** deletes them. These, and the hi-res song below, are the only
  downloads in Phase 1.
- **Hi-res**: **Find a 24/192 FLAC** looks through the library (up to 10,000 songs) for a 24-bit
  192 kHz FLAC, or the highest rate there is, to play. This needs a Navidrome that says each song's
  sample rate (OpenSubsonic's `samplingRate`).
- **Playing**: the song, how far in, previous, play/pause and next, and a line like
  `24-bit 192 kHz FLAC file → 48 kHz output (AirPods Pro)`. The app decodes each file at its own
  rate, with nothing changed. When the output runs at another rate, the app's audio engine converts
  the song to it, as any app must: an iPhone's own outputs and AirPods run at 48 kHz or lower. Under
  it, "An edit held for the next song" when one is (see [the checks](#what-only-a-phone-can-tell)), and
  the last song that failed, in its own words.
- **Library**: how many albums each list had, whether it came new or the kept one still stood, and
  how long it took to come.
- At the bottom, how long this install runs. In its last two days, it also says to run install.sh
  before then.

## The lock screen and interruptions

The lock screen and Control Center show the song, its artist, album, cover and how far in it is.
Play, pause, next and previous work there, as does dragging the position, and the AirPods' presses
work too. A phone call or Siri pauses the music, and it carries on when they're done. Taking an
AirPod out pauses it.

## Plays

A song is counted as played in Navidrome once you've heard half of it, or 4 minutes, whichever comes
first. Songs of 30 seconds or less don't count. That's the rule the web app uses, and Last.fm's.
Navidrome passes plays on to Last.fm or ListenBrainz if it's linked to them, and is told what's
playing now. A play that can't be sent is dropped rather than sent twice.

## Picking up where you left off

The app saves what you're playing in Navidrome, as the web app does: the queue (up to 2,000 songs, 50
of them before the one playing), the song, and how far in. It saves every 30 seconds while playing,
at each pause and change of song, and as the app goes to the background.

When the app opens with nothing playing, it puts back what you were last playing, paused at the
second it stopped, from whichever device saved it last: the web app, or another app on Navidrome. A
notice says where it came from ("Picked up from your Mac", "Picked up from Symfonium"). Nothing is
fetched until you press play. It's put back with this phone's Repeat and Normalization. The web app
picks up the phone's queue the same way ("Picked up from your iPhone").

Coming back to the app while paused, it looks again (at most every 15 seconds). With logins on, it
takes what another device saved since this phone last did. With logins off everyone shares one queue,
and a paused phone never takes somebody else's. The break-glass `deadwax` keeps no queue.

## The songs kept on the phone

Songs come as they are: a FLAC as FLAC, an MP3 as MP3. Only Ogg, Opus and WMA files come as MP3,
because iOS can't play them. The app starts playing as a song arrives, and fetches the next one ahead
of time.

Once a song has all arrived, it's kept on the phone, so playing it again doesn't fetch it again. Up to
2,000,000,000 bytes are kept (2 GB, as iOS's Storage screen counts), and the songs played longest ago
go first. iOS may also empty them when the phone runs short of space, and songs are then fetched
again. A song you skip past before it has arrived is let go, and its part deleted. This isn't a way
to play offline: a song not kept still needs deadwax. Downloads come in a later phase.

## The checks

Phase 1 exists to answer these on the phone. Note what you see for each.

1. **Sign in and count.** Sign in with your Navidrome account. The Library shows your albums: does
   the count above them match the web app's Library? And All albums against the web app's All music?
   You > Debug > Library says how many each list had and how long it took to come: note the times.
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
   they under Playing Next, in that order? Edit: drag one, take one out, Done. Clear. Shuffle on and
   off: the song playing goes on untouched. Repeat One plays the song again; Repeat All starts the album
   again after its last song.
6. **Picking up, both ways.** Play an album on the phone, pause it, and close the app (swipe it away).
   Open the web app on the Mac: the same queue, song and second, paused. Then play something else on
   the Mac, pause it, and open the app on the phone: it has it, paused, and says "Picked up from your
   Mac".
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
- **Repeat One, or a tap in Up Next, in a song's last two or three seconds.** By then the next song
  is lined up for a seamless join, so a change to the queue is held and made after it: Repeat One
  turned on there repeats the next song, not this one (Debug's Playing says "An edit held for the next
  song" meanwhile). A tap on a row still plays that row at once. Does either sound wrong at the join?
- **WireGuard off in the middle of a song**, away from home. What does the mini player say, and does
  the music come back once WireGuard is on again?
- **The Library's grid flung from A to Z**, on a big library. Does it keep up? With the cable in,
  Xcode's Debug navigator shows the app's memory: note it.
- **Sign out, then sign in as someone else.** Their Library, and nothing of the first person's queue.

## What it can't do yet

These are the web app's for now. Most of them come to the phone in the next phases:

- **Downloads** to play offline. Only Debug's test songs and the hi-res one can be downloaded.
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
| Sign in: **"deadwax can't reach the music server, so nobody can sign in just now."** | deadwax signs people in through Navidrome. Check that Navidrome is running and that deadwax's [Navidrome settings](configuration.md#navidrome-settings--connections) are right. |
| The sign-in comes up over the app, with a reason ("Your sign-in ran out after 30 days without use - sign in again.") | Sign in again. The music plays on underneath. |
| Library: **"Your music isn't available right now"** (an admin sees **"Can't reach Navidrome"**) | deadwax can't reach Navidrome. Check Navidrome is running, then **Try again**. |
| Library: **"Your music isn't available yet"** (an admin sees **"Connect Navidrome"**) | deadwax hasn't been told where Navidrome is. An admin's **Set up Navidrome** opens the web app in Safari: set it up in Server settings (Connections), then come back. |
| Library: **"Couldn't update this list - showing it as it was."** | deadwax didn't answer just then. Pull down to try again. |
| An album's page: **"This album isn't here any more - it may have been moved or deleted."** | Go back, and pull down on the Library to bring it up to date. |
| A song's line says **"The connection dropped while this song was loading"**, or the next song's says **"Skipped "..." - it wouldn't play"** | The app asks for a song once more after a moment, then goes on past it. Check the phone's network. |
| **"This device couldn't play this song's audio"**, or **"Skipped "..." - this device couldn't play its audio"** | The file is damaged, or in a form iPhones can't play. Try it on the web app; an admin finds the details in You > Debug > Playing. |
| Info's Normalization: **"Not this time - the album's volume couldn't be checked"** | deadwax is older than 2.1.1, or didn't answer in time. The song plays as it is; with 2.1.1 or later, the album's next play is levelled. |
| The beep album isn't found | Make it with `make-test-album.py` into your music library (see "What you need"), let Navidrome scan it, then Check again in Debug. |
| **"Untrusted Developer"** when opening the app | Settings > General > VPN & Device Management > your Apple ID > Trust. |
| The app won't open at all after a week | The free install ran out. Run `install.sh` again: nothing on the phone is lost. |
| install.sh: **"No paired iPhone the Mac can reach now"** | Connect the cable and unlock the phone (or turn on Connect via network in Xcode, with the Mac and the phone on the same Wi-Fi), then run it again. |
| install.sh: **"Xcode has changed ios/Deadwax.xcodeproj here"** | A team was picked in Xcode's Signing & Capabilities. Run `git checkout ios/Deadwax.xcodeproj`, keep the team in `ios/Config/Local.xcconfig`, and run install.sh again. |
| install.sh: **the build failed** with a signing or profile error | The first install has to come from Xcode with the cable (step 5 of "Once"). After that, the script renews the signing by itself. |
| install.sh: **Xcode knows no Apple ID** | Add it in Xcode > Settings > Accounts, then run the script again. |
| A free account says it can't install more apps | A free account can have only 3 of its own apps on the phone at once. Delete one you don't need. |
