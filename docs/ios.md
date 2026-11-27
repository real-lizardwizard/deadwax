# The iPhone app (early: Phase 0)

deadwax is getting a native iPhone app, built with SwiftUI and its own audio engine, for what a web
page can't do well: seamless joins and normalization done on the phone, downloads to play offline,
and a song's start never lost on AirPods. It's built in phases. **This is Phase 0, "Hello, iPhone"**:
a single test screen that proves the tools, the connection and the audio engine on a real iPhone.
It isn't yet a player to use day to day. That's Phase 1.

The app talks only to deadwax, never to Navidrome, through deadwax's own routes. Nothing changes on
the server for Phase 0: it works with deadwax 2.0.0 as it is.

deadwax 2.1.1 adds the one route the next phase needs for normalization. It tells the app what
deadwax has already measured of an album's loudness: each song's, and the album's as a whole. The app
can then level songs on the phone from the same measurements the web app's Normalization uses. The
route only reads what's there and never measures anything itself. It only answers about an album
the signed-in person can see in Navidrome. Nothing changes for the web app.

deadwax 2.1.24 adds the route the app's Search will draw covers from for the albums you don't have
yet, the ones it finds on MusicBrainz. deadwax fetches the album's front cover from the Cover Art
Archive the first time it's asked for and passes it on, so the app still talks only to deadwax. It
keeps each cover it fetched, up to 128 MB, in a folder of its own beside the player's cache
(`deadwax-covers`, in [`PLAYER_CACHE_PATH`](configuration.md#paths) or the container's temporary
space), so a cover it has kept is answered without asking the Archive (and fetched again behind it
once it's a month old). When the Archive has no cover, or can't be reached, deadwax says so within
seconds rather than keeping the app waiting, and the app can draw the empty cover. Like **Get
cover**, it needs deadwax's container to reach `coverartarchive.org` and `archive.org`. Nothing
changes for the web app, which loads those covers from the Archive itself.

deadwax 2.1.32 adds the route the app's **Artist images…** will draw its pictures from. The pictures
it offers are on other sites (Wikimedia Commons, TheAudioDB and fanart.tv), so deadwax fetches each
one when the app asks for it and passes it on, keeping nothing. It fetches only from those sites'
picture addresses, over HTTPS: `commons.wikimedia.org`, plus `thumb.wikimedia.org` and
`upload.wikimedia.org`, where Commons sends it; `r2.theaudiodb.com`; and `assets.fanart.tv`. It
never fetches from anywhere else, and only for someone who can **Edit albums**. When a picture can't
be had, deadwax says so within seven seconds rather than keeping the app waiting. Like **Artist
images…** in the web app, it needs deadwax's container to reach those sites. Nothing changes for the
web app, which loads those pictures from the sites itself.

deadwax also adds the route the app's **Info** will draw a song's **credits** from: who played what on it
(lead vocals first, then other vocals, then each instrument, then an orchestra or conductor), who wrote it, and who
produced, engineered, mixed and mastered it. An instrument is named as the album credits it where MusicBrainz says
("lead guitar" and "rhythm guitar" on Back in Black, not "guitar" twice). They come from
[MusicBrainz](https://musicbrainz.org), and how much MusicBrainz knows differs from album to album, so the app
always says which of these it is showing:

- **On this song**: MusicBrainz credits this recording itself.
- **On the album**: MusicBrainz credits the album as a whole, not song by song.
- **The band in 1980** (the album's year: when it first came out, not the pressing's or a single's date):
  MusicBrainz has no credits for the album, but its artist is a band, so it shows the members on the album's date,
  with what each played. Everyone is shown whom MusicBrainz's dates don't rule out, so others may be there who
  didn't play: where a member joined or left during the album's year and MusicBrainz can't say whether before or
  after it came out, they're shown with "joined 1980" or "left 1980". When MusicBrainz has no dates for any member,
  it's **The band's members**: everyone who was ever in the band. A compilation never shows the band, since its songs
  come from other years.
- **No credits yet**: MusicBrainz has none for the album, with a link to add them there. When other songs on the
  album do have credits, the answer says so too. Or the album isn't matched to a MusicBrainz release, so there's
  nothing to look up (**Edit → Release** matches it).

deadwax finds the song on its release by the recording id in its file, when the file has one (Picard writes it;
deadwax doesn't). Otherwise it uses the disc and track number, but only when that disc's track numbers in Navidrome
are exactly the release's. If it can't be sure which track it is, it shows the album's credits rather than another
song's. It asks MusicBrainz as it asks for everything else, and keeps each album's credits for a month, so
they're there even while MusicBrainz is down. When MusicBrainz can't be asked and nothing is kept yet, the app says
the credits can't be asked for just now
([troubleshooting](troubleshooting.md#a-songs-credits-say-they-cant-be-asked-for-just-now)). Anyone signed in can
see them, and no setting is needed. The web app doesn't show them yet.

## What you need

- **A Mac with Xcode.** Xcode 16 or later opens the project. An iPhone on iOS 27 needs **Xcode 27**,
  because Xcode only installs on iOS versions it knows. No iOS Simulator is used or needed: when
  Xcode offers to download one, you can say no.
- **About 8 GB free** on the Mac: for the build, and for the copy of the phone's debug symbols Xcode
  makes the first time the iPhone is connected.
- **An iPhone on iOS 17 or later** and its cable, for the first install.
- **A free Apple account.** Its catch: **each install runs for 7 days**, and then the app won't open
  until you install it again. Installing it again is one command, below, and keeps everything on
  the phone. The app shows when its install runs out.
- **The test album.** "Start test (2026)" by "deadwax test" is ten short FLAC songs: eight of three
  beeps each, with the first beep at a known time, and two that are one steady tone cut in two.
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
   being built (`git switch ios` to follow it).
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
id makes a new, empty app: the downloads and the sign-in stay with the old one. It also uses up one
of the few new app ids a free account may register each week.

## Every week, or when there's a new build

```
~/Developer/deadwax/ios/scripts/install.sh
```

It pulls the latest code, asks GitHub whether the app's checks passed on it (and asks you before
building one that failed or is still running), builds it (Release), and installs it **over** the app
on the phone, so everything on the phone stays. Then it opens the app and says how long the new
install runs: `Installed deadwax 0.1 (1), runs until Fri 30 Oct, 14:02`. It also says how long it
took and the Mac's free space before and after. Xcode doesn't need to be open.

| option | what it does |
| --- | --- |
| `--no-pull` | builds what's checked out, without `git pull` |
| `--yes` | doesn't ask: uses the first team and iPhone it finds, and builds even if the checks failed |
| `--debug` | builds Debug instead of Release |

It remembers which iPhone it installed on, in `ios/Config/device` (also ignored by git). The build
happens in `~/Library/Caches/deadwax-build`, and the last build's whole log is `last-build.log` there.

## The test screen

- **deadwax's address**: the address you open deadwax at, by IP (`192.168.1.20:8090`) or by name.
  `http://` is assumed when you don't type it. A pasted web-app link (`.../player/`) works too.
  **Check** asks deadwax whether it's running and who you are to it, and says whether logins are on
  or off. The first time, iOS asks to let deadwax **find devices on your local network**: say yes.
- **Sign in** appears when logins are on. Use your Navidrome name and password, as on the web app.
  The password isn't kept on the phone. Only the session deadwax gives back is kept, in the
  Keychain. **Sign out** ends that session.
- **Test sounds**: the test album's songs. Tap one to play the album from it. Each song's row has a
  download button, and **Download all 10** downloads the lot. **Streamed / Downloaded** chooses which
  copy plays: Streamed fetches each song as it plays, and Downloaded plays the copies on the phone (a
  song with no copy is streamed). **Remove the downloads** deletes the copies.
- **Hi-res**: **Find a 24/192 FLAC** looks through the library (up to 10,000 songs) for a 24-bit
  192 kHz FLAC, or the highest rate there is, and shows it to play. This needs a Navidrome that says
  each song's sample rate (OpenSubsonic's `samplingRate`).
- **Playing**: the song, how far in, previous, play/pause and next. Under them is a line like
  `24-bit 192 kHz FLAC file → 48 kHz output (AirPods Pro)`. The app decodes each file at its own
  rate, with nothing changed. When the output runs at another rate, the app's audio engine converts
  the song to it, as any app must: an iPhone's own outputs and AirPods run at 48 kHz or lower. That
  conversion is the one step that changes the samples, so its quality is measured by the app's
  checks.
- The line at the bottom says how long this install runs. In its last two days, it also says to
  install again.

The lock screen and Control Center show what's playing, and their controls work, as do the AirPods'.
A phone call or Siri pauses the music, and it carries on when they're done. Taking an AirPod out
pauses it. A pause stops the app's audio output at once: that is how iOS knows it has paused, so
the lock screen shows play and the AirPods' next press plays. The next play starts the output
again, a moment later.

## The checks

Phase 0 exists to answer these on the phone. Note what you see for each.

1. **Install without a Simulator.** `install.sh` builds and installs. Note how long it took, and the
   free space before and after (it prints both).
2. **The icon.** The app's icon (a record) shows on the home screen. If it's blank, say so: the
   icon is plain image files, with no asset catalog, and that's what this checks.
3. **The connection.** Check says OK, by IP and by name, on home Wi-Fi. The Local Network question
   appears once (say yes). Then away from home over WireGuard: does Check still say OK?
4. **AirPods, from silence.** With AirPods in, tap test song 1 and count the beeps: all three? While
   it plays, tap song 3: all three? Pause for 2 minutes, then tap song 2: all three? Then the same on
   the phone's speaker. Try it Streamed, and again Downloaded.
5. **The join.** Tap song 9 and let it run into song 10, about 5 seconds in. They're one steady
   tone cut in two, so you should hear one unbroken tone: no gap, click or blip where they meet.
   (The beep songs can't show this: they meet in silence.)
6. **Locked.** Tap song 7 and lock the phone straight away. Songs 8, 9 and 10 should start one after
   another while it's locked (about a minute in all: the beeps at 21 seconds in 7 and 8, then the
   tone). Then play the hi-res song, lock the phone, and let it play to its end. While it plays, pause
   from the lock screen, wait 2 minutes, and play from the lock screen again: it should carry on from
   where it was. The lock screen shows each song, and pause and play work there and from the
   AirPods.
7. **Interruptions.** A phone call or Siri during play pauses it, and it comes back afterwards.
   Taking an AirPod out pauses it.
8. **Hi-res.** The 24/192 song plays, and the line under Playing says its rate and the output's
   (192 kHz file → 48 kHz output, or whatever it is).

## What it can't do yet

Everything a player needs beyond these tests: your library, album pages, a queue, normalization,
plays counted, resuming where you left off, playlists, Search, Get and Requests. Those come in the
next phases. Phase 0's streamed songs are kept only until the app next starts, and its downloads
are only for the test songs and the hi-res one.

## When something goes wrong

| what you see | what to do |
| --- | --- |
| **"Couldn't reach deadwax at ..."** | Check the address, and that the phone is on your home Wi-Fi or WireGuard. If you said no to the local network question, turn deadwax on in Settings > Privacy & Security > Local Network. |
| The beep album isn't found | Make it with `make-test-album.py` into your music library (see "What you need"), let Navidrome scan it, then Check again. |
| **"Untrusted Developer"** when opening the app | Settings > General > VPN & Device Management > your Apple ID > Trust. |
| The app won't open at all after a week | The free install ran out. Run `install.sh` again: nothing on the phone is lost. |
| install.sh: **"No paired iPhone the Mac can reach now"** | Connect the cable and unlock the phone (or turn on Connect via network in Xcode, with the Mac and the phone on the same Wi-Fi), then run it again. |
| install.sh: **"Xcode has changed ios/Deadwax.xcodeproj here"** | A team was picked in Xcode's Signing & Capabilities. Run `git checkout ios/Deadwax.xcodeproj`, keep the team in `ios/Config/Local.xcconfig`, and run install.sh again. |
| install.sh: **the build failed** with a signing or profile error | The first install has to come from Xcode with the cable (step 5 of "Once"). After that, the script renews the signing by itself. |
| install.sh: **Xcode knows no Apple ID** | Add it in Xcode > Settings > Accounts, then run the script again. |
| A free account says it can't install more apps | A free account can have only 3 of its own apps on the phone at once. Delete one you don't need. |
