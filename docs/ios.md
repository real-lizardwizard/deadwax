# The iPhone app (early: app 0.13, downloads, lyrics, the EQ, the turntable, play history, your library, the Library, Search, Requests, getting albums, Manage, Edit album and the artist tools)

deadwax is getting a native iPhone app, built with SwiftUI and its own audio engine, for what a web page can't do
well: seamless joins and normalization done on the phone, downloads to play offline, and a song's start never lost on
AirPods. It's built in phases. Phase 0, "Hello, iPhone", was a single test screen that proved the tools, the
connection and the audio engine. Phase 1, the player (app 0.2), was the first version meant for playing your music day
to day: your library, album pages, the Queue, Now Playing, normalization, the lock screen, plays counted, and picking up
where you left off. Phase 2, downloads (app 0.3), followed: an album, or a song, downloaded to the phone plays from
there, bit for bit as deadwax has it - and goes on playing when deadwax can't be reached (see [Downloads](#downloads)
and [Offline](#offline)). App 0.4 added lyrics on Now Playing, as the web app shows them (see [Lyrics](#lyrics)). App
0.5 added the EQ: ten sliders and nine presets, kept for each output on its own - your headphones, the speaker, the
car - and switching by itself when the output changes, a correction for your headphones from AutoEq's measurements,
and - under Advanced - filters and a preamp of your own and Equalizer APO files in and out (see [EQ](#eq)). App 0.6
added the turntable: Now Playing's second look, as the web app has it - a record you can turn by hand and hear as you
turn it, with the album's CD art on its face (see [The turntable](#the-turntable)). App 0.7 added the turntable's
speed fader: the song faster or slower, its pitch moving with it, as a record deck's does - and at 1x the song exactly
as it is (see [The speed](#the-speed)). App 0.8 added play history: scroll up in the Queue, past the song playing, and
it goes on back through every song you've played - on the phone and in the web app, one list, as the web app's Up Next
has it - and the phone's own plays go into the web app's too (see [the Queue](#queue) and [What you've
played](#what-youve-played)). App 0.9 added your library downloaded by itself, as much as fits your storage limit,
kept in step with what you star and unstar anywhere - only while the phone is charging if you choose, and with the app
in the background when iOS allows (see [Your library on this phone](#your-library-on-this-phone)). App 0.10 added
Phase 4's Library: **playlists** - yours and those shared with you, played as the web app plays them, and made, added
to, edited and deleted on the phone as in the web app, and downloaded to play with no connection, kept in step as they
change (see [Playlists](#playlists)); the Library's switch - Albums | Playlists | Artists, and Songs with logins off
(with them on, every song is under All music > All songs), swiped between, in the order you choose - and a pull down
that shuffles your whole library (see [The Library](#the-library)); **artists** - your artists, and an artist's page
with their albums, Play and Shuffle, and (with a Last.fm key on deadwax) their listeners and Top Songs (see
[Artists](#artists)); and **songs** - every song, a page at a time, each
opening its album (see [Songs](#songs)). **This is app 0.11, Phase 5's Search**: your library and MusicBrainz searched
as the web app's Search searches them, in one list - Top results, then artists, albums and songs, yours first - a song
playing from its tap; the albums, artists and songs you don't have yet, each opening its page (an album's pressings
and tracklists, an artist's albums); what deadwax has saved of MusicBrainz's answers, drawn with your library at once;
and **More** from MusicBrainz, a page at a time (see [Search](#search)). Phase 6 begins with **Requests**, still app
0.11: every download you asked for - in the web app, or on another phone - under the web app's four headings, with its
progress, cancelled, tried again from another source and cleared on the phone, and a finished album opened or played
from its row (see [Requests](#requests)). Then **Get**, still app 0.11: an album you don't have got from the phone -
what deadwax already has of the pressing said under Get the album, the sources Soulseek has for it in a sheet, each
with why it scored what it did, and the one you pick on its way in Requests from your tap (see [Getting an
album](#getting-an-album)). **App 0.12** finishes getting albums on the phone: a download somebody else asked for
**joined**, a pressing in the collection **added to your library**, **Pick the best source for me**, and **When I tap
Get**, **Quality floor** and **Format** chosen on the phone (see [Settings](#settings)). **App 0.13** is Phase 7, the
last of the plan: **Manage** lists the tools for looking after deadwax that you may use - editing an album, Needs a
look, Library care, People, Server settings and the event log - each of which at first opened in the web app, in
Safari, as **Change password** did (see [Manage](#manage)). Still 0.13, the tab that was called You is **Settings**
now: a short list of groups, each opening a page of its own, and every choice on them one row with a menu rather than
a list of ticks (see [Settings](#settings)). The web app's tab is called Settings too, since deadwax 2.1.35. Still
0.13, **Phase 8** begins bringing those tools into the app itself, one build at a time: first **Edit album** - an
album's folder, what's wrong with it, and the release it's matched to, chosen and applied on the phone, from the
album's ••• or Settings > Manage > Edit an album (see [Edit album](#edit-album)). Then its **Tags**: each track's
file, everything in it, and its tags edited on one track or many at once. Then its **Artwork** and **Lyrics**: the
cover and CD art, each full screen, and Get cover, Get CD art and Get lyrics on the phone. Then its **Delete**: what
deleting the folder takes, read as it is now, and whose libraries it's in, asked once more before it goes - and with
it nothing in Edit album opens the web app any more. Then **the artist tools**, from an artist's page: **Artist
images…**, every picture of them found, chosen and saved into their folder; **Which artist is this?**; and **Move
albums to …**, their albums filed under an old name moved under the one they have now (see [Managing an
artist](#managing-an-artist)). Then **Needs a look**: the albums that need fixing and the new downloads nobody has
looked at, how many beside it in Settings > Manage, each worked through in Edit album with **Skip** and **Next album**
(see [Needs a look](#needs-a-look)). Then **Library care**: Rescan, and covers, CD art and lyrics fetched for every
album without, one album at a time - with In nobody's library for an admin (see [Library care](#library-care)). Then
**Server settings**: whether deadwax reaches MusicBrainz, slskd and Navidrome, and every setting of the server's, each
group a page of its own, saved together - with Re-time saved lyrics and MusicBrainz's saved answers - and the
Library's **Set up Navidrome** opening it over the Library (see [Server settings](#server-settings)). Then the **Event
log**: what deadwax has said since it started, newest first, each new line as it's logged, with Copy on a long press
and Clear for the phone's view (see [Event log](#event-log)). Then **Change password**: your Navidrome password
changed on the phone, which stays signed in while every other sign-in of yours is signed out (see [Change
password](#change-password)). Then **People**, for an admin: unlocked with your own Navidrome password, every
Navidrome account with its permissions, a password reset, the admin role and Remove, Add a person, and the names
deadwax keeps things for with no account (see [People](#people)). And last, nothing in the app takes you to the web
app any more: what was left of the way out to it is gone, and the app's only links out are to MusicBrainz, AutoEq on
GitHub and the Sharing deadwax guide (see [Manage](#manage)).

**Nothing of Phase 2, the lyrics, the EQ, the turntable, play history, your library downloaded,
playlists, artists, songs, Search, Requests, Get or Manage has been seen on an iPhone yet.** It's built and tested on a Mac,
and what only a phone can tell is what [the checks](#the-checks) are for. Until they're answered, read
everything about downloads, lyrics, the EQ, the turntable, play history, your library, playlists, artists,
songs, Search, Requests, Get and Manage below as what the app is built to do.

**On a Mac too.** Still app 0.13, the same app runs on a Mac with Apple silicon - a sidebar, a player bar and side
panels in a window that resizes freely, with the Mac's menus and keys - installed with `ios/scripts/install-mac.sh`
and never running out. It has run on a Mac since 17 Nov; what is still to check there is in [The Mac
app](#the-mac-app).

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
tag" under [The compose file](getting-started.md#the-compose-file)). Settings > About shows which deadwax
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

deadwax 2.1.24 adds the route the app's Search draws covers from for the albums you don't have
yet, the ones it finds on MusicBrainz (with an older deadwax they're drawn as an empty square). deadwax fetches the album's front cover from the Cover Art
Archive the first time it's asked for and passes it on, so the app still talks only to deadwax. It
keeps each cover it fetched, up to 128 MB, in a folder of its own beside the player's cache
(`deadwax-covers`, in [`PLAYER_CACHE_PATH`](configuration.md#paths) or the container's temporary
space), so a cover it has kept is answered without asking the Archive (and fetched again behind it
once it's a month old). When the Archive has no cover, or can't be reached, deadwax says so within
seconds rather than keeping the app waiting, and the app can draw the empty cover. Like **Get
cover**, it needs deadwax's container to reach `coverartarchive.org` and `archive.org`. Nothing
changes for the web app, which loads those covers from the Archive itself.

deadwax 2.1.32 adds the route the app's [**Artist images…**](#managing-an-artist) draws its pictures from. The pictures
it offers are on other sites (Wikimedia Commons, TheAudioDB and fanart.tv), so deadwax fetches each
one when the app asks for it and passes it on, keeping nothing. It fetches only from those sites'
picture addresses, over HTTPS: `commons.wikimedia.org`, plus `thumb.wikimedia.org` and
`upload.wikimedia.org`, where Commons sends it; `r2.theaudiodb.com`; and `assets.fanart.tv`. It
never fetches from anywhere else, and only for someone who can **Edit albums**. When a picture can't
be had, deadwax says so within seven seconds rather than keeping the app waiting. Like **Artist
images…** in the web app, it needs deadwax's container to reach those sites. Nothing changes for the
web app, which loads those pictures from the sites itself.

## What you need

- **A Mac with Xcode.** Xcode 16 or later opens the project. An iPhone on iOS 27 needs **Xcode 27**,
  because Xcode only installs on iOS versions it knows. No iOS Simulator is used or needed: when
  Xcode offers to download one, you can say no.
- **About 8 GB free** on the Mac: for the build, and for the copy of the phone's debug symbols Xcode
  makes the first time the iPhone is connected.
- **An iPhone on iOS 17 or later** and its cable, for the first install.
- **A free Apple account.** Its catch: **each install runs for 7 days**, and then the app won't open
  until you install it again. Installing it again is one command, below, and keeps everything on
  the phone. For an admin (with logins off, everyone), **Settings > This phone > Debug** says when the install runs
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
   - turn on the iPhone's **Settings > Privacy & Security > Developer Mode**, which appears after that first
     connection, and restart when asked;
   - trust yourself as the developer: the iPhone's **Settings > General > VPN & Device Management > your Apple ID
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
install runs: `Installed deadwax 0.13 (13), runs until Wed 18 Nov, 14:02`. It also says how long it
took and the Mac's free space before and after. Xcode doesn't need to be open.

| option | what it does |
| --- | --- |
| `--no-pull` | builds what's checked out, without `git pull` |
| `--yes` | doesn't ask: uses the first team it finds and the iPhone it installed on last (the first it finds the first time), and builds even if the checks failed |
| `--debug` | builds Debug instead of Release |

It remembers which iPhone it installed on, in `ios/Config/device` (also ignored by git). If that
iPhone isn't in reach - not unlocked, or not on the same Wi-Fi as the Mac or on its cable - it asks
before installing on another one, and with `--yes` it stops instead: "… isn't in reach now, so nothing
was installed", with the iPhones that are. To install on another iPhone, write its name in
`ios/Config/device`, or run it without `--yes` and say yes. The build
happens in `~/Library/Caches/deadwax-build`, and the last build's whole log is `last-build.log` there.

## The Mac app

The same app runs on a Mac too, built from the same code through Apple's Mac Catalyst - not the web app in a window,
and not a second app. It's the same version as the phone's (app 0.13 (13) now), it talks only to deadwax as the phone
does, and it plays through the same audio engine: seamless joins, normalization, the EQ, downloads. **This is its
eighth build** - the first ran and played (the Mac app's slice 1), the second added the Mac's menus, keyboard shortcuts
and right-click menus, and a window you can close while the music plays (slice 2), the third laid the window out as the
web app's desktop is laid out - a sidebar, the page, side panels and a player bar (slice 3), the fourth gave it the
Mac's own words - **This Mac** where the phone says This phone (slice 4), the fifth pauses for sleep and for headphones
taken out, reads a Mac's power for Only while charging, keeps a long run's display on, keeps work going with the
window hidden, and says the Mac's words for Download over (slice 5), the sixth brings EQ files in and out the Mac's way -
**File > Import EQ File…** ⌘O, Export…'s Save panel, Finder's Open With and a file dropped on the window or the Dock
(slice 6); this one is looking after deadwax on a big screen - Edit album sized by the window, Manage's pages at a
readable width, **File > Save changes** ⌘S for Server settings, Tab between the editor's fields, and the event log's
lines selected and copied with ⌘C (slice 7); this one begins the Mac's own look, the redesign drawn for it - a title
strip along the top naming the page, and the sidebar as drawn: words without glyphs, in the Mac's colours, corners
and type (the redesign's first slice; the pages themselves are still the phone's, and follow in the slices after).
**Most of it is still unchecked on a Mac** - it
has been opened and used on one since the first build (17 Nov), but what only a Mac can tell is what its checks are
for ([404-415](#the-mac-apps-checks-404-415),
[416-423](#the-mac-apps-menus-keys-and-window-checks-416-423), [424-433](#the-mac-apps-desktop-frame-checks-424-433),
[434-438](#the-mac-apps-words-checks-434-438), [439-446](#the-mac-apps-sleep-power-and-downloads-checks-439-446),
[447-451](#the-mac-apps-eq-files-checks-447-451), [452-458](#the-mac-apps-managing-checks-452-458) and
[518-525, 532-540 and 608-609](#the-mac-redesigns-checks-518-614)).

**What it is today.** The window is laid out as the web app's desktop is, whatever its size: the **sidebar** at the
left, the **page** you're on beside it, the **side panel** at the right when you open it - Queue, Lyrics, Info or EQ - and the
**player bar** along the foot, under a **title strip** along the top - the window's traffic lights at its left and
the page you're on named in its middle, as the **Window** menu names the window. Every page is the phone's own page,
in macOS's sizes and controls (the Mac idiom), until the redesign's later slices draw each one the Mac's way. The
window is at least 880 x 600 points - room for the sidebar, a page and the bar - as large as you like above that, and
opens at 1280 x 820; macOS remembers its size and place after that. What the phone does, the Mac does, with the Mac's
menus and keys, and these differences.

- **The sidebar** (220 points wide; **View > Hide Sidebar** ⌃⌘S puts it away and brings it back), from the top:
  - **deadwax**, the app's name.
  - **The search field.** Type in it and Search's results fill the page - the same results as the phone's Search,
    which has no field of its own on the Mac. Return searches at once (MusicBrainz too), as the phone keyboard's
    Search does. Escape empties it while the cursor's in it. **Edit > Find** ⌘F shows the sidebar and puts the cursor
    here, leaving the page as it is.
  - **Requests**, with the count of downloads on their way, as the phone's tab has it.
  - **Library.** With a library of your own, a switch beside the heading - **Yours** and **All**: Yours lists the
    Library's pages in the order you keep for its switch (Albums, Artists, ... - Playlists is its own group below),
    All lists all of deadwax's Albums, Artists and Songs. **Downloaded** follows on either. The switch follows where you
    are, and stays as you left it otherwise (kept on this Mac); turned with a page of the other side showing, it opens
    the same kind of page on this side - your Albums for All's Albums, All's Artists for your Artists. With logins off,
    the Library's pages and Downloaded, no switch. With the switch picked out by Tab, ← and → turn it.
  - **Playlists**: All playlists, then yours and those shared with you, by name - twenty at most.
  - **Manage** (only what you're allowed): Edit an album, Needs a look with its count, Library care, Server settings,
    Event log, People - the rows of Settings > Manage.
  - **Settings**, at the foot, in view however far the rest scrolls.

  Playlists' and Manage's headings fold their groups away; what's folded is kept on this Mac, and folded Manage shows
  Needs a look's count on its heading. The row for where you are is lit - a folded heading too, when the page showing
  is one of its rows. Clicking the row you're on goes back to its own page from whatever you opened over it - and
  on Requests, Settings or a Library page of Yours, clicking it there goes to the top of its list, as tapping the tab
  you're on does on the phone. A playlist's row or a Manage row opens its page over what's there, in place of another
  playlist's or Manage page rather than piling them up - except a playlist you're editing, or a Change password or
  People change still under way: the new page opens over that one, which waits under it (Back) as you left it. The
  rows are words alone, with no glyphs, and the lit one is drawn in the selection's purple with its edge.
- **The page.** The Library's **Albums** and **Artists** - yours and All's - are the Mac's own: a toolbar along the
  top - **Play**, **Shuffle**, **Sort** and its pop-up (the phone's orders), **Grid | List** and a **Find** field -
  over the albums or artists as covers, as many in a row as fit and none under 150 points across, or as a list in
  columns: Albums' **Album** (a small cover and its title, then **New** for an album new in your library and a purple
  **▶** for the one playing), **Artist** (with the album's download mark at its end), **Year** and **Songs**; Artists'
  **Artist**, **Albums** (Navidrome's count), **Songs**, **Plays** and **Last played** ("today", "yesterday", "3 days
  ago", "last week", then the day - moving on at midnight with the list left open) added up from that artist's albums
  there. A split album or a compilation counts in the Albums of each artist on it, but its songs and plays only under
  the album's own artist. Every other row is faintly striped; click a row to light it, ↑ and ↓ move it, ⌘↑ and ⌘↓ go to
  the first and the last, Return or a double-click opens it, and right-clicking an album's row gives the album's menu,
  as a cover's does. **Play** plays the lit album, or the lit artist's songs, once they've come - dimmed until then;
  in Grid nothing is lit (choosing Grid lets the lit row go), so Play is dimmed there, and holding the pointer over it
  says to select one in List. **Shuffle** shuffles your library (All's, the collection), in Grid as in List. Grid or
  List is kept on this Mac, apart from the phone's. How many albums (or artists) and songs (or albums - each counted
  once) are listed, and "1 selected", are in the status bar along the foot. **Playlists** is a list in columns too:
  **Playlist**, **Songs**, **Length**, **Whose** ("Yours", the owner's name, or "From a file"), **Changed** (Last
  played's words) and **On this Mac** (a chip once it's downloaded, else how far its download has got) - yours first,
  then those shared with you, then those from files. On a page too narrow for them all, Whose and Changed are left
  out, so the name always has room. Its toolbar has **New playlist…**, **Play** and **Shuffle** for the lit playlist
  (dimmed until its songs have come - offline, only its songs on this Mac - and only while it's listed: a playlist
  **Find** hides is let go) and **Find in playlists**; right-click a row for its menu; the status bar counts those
  listed ("9 playlists · 7 yours · 2 shared with you" - only what Find finds while you type, nothing while there are
  none). Songs is still the phone's page, under the phone's top: the magnifying glass, the switch of the pages and
  the •••.
  **An album's page** is the Mac's own since the new look, across the window: a toolbar of **Play**, **Shuffle**, **Add
  to Queue**, **Add to a playlist…**, **Download** (once asked for, a menu headed with how far it has got) and **Edit**
  (for someone who may edit albums). It fits the page at every window size, the side panel open or not; should it
  ever not fit (a download's long words), all but Play and Shuffle fold into a **•••** (the right-click's items, Edit
  album among them). Under it the cover, the title, the artist in purple, the meta line and "Played yesterday · 12
  times" (Last played's words, moving on at midnight - Album info's **Played** says the same), the badge and the
  download line; then the songs in columns - **#** (the song's own number, a ▶ for the one playing), **Title**,
  **Plays** (blank for a song never played, never 0), **Length** and a **•••** - with a heading row above each disc's
  first song where the phone has one ("Disc 2", or "Disc 2 · Live" for a disc with a title); double-click or Return
  plays from the lit song; then **Properties**: Released, Added, Format, Size (only when every song says its own) and,
  for an admin, **Folder** (or **Folders**, for an album in more than one), as Album info shows it. The status bar
  has the songs, their length and the size.
  **A playlist's page** is drawn the same way: the toolbar (Play, Shuffle, Add to Queue, Add to a playlist…, Download,
  Edit - dimmed for one you can't change), the mosaic, the name, whose it is and when it changed, its songs and length,
  then the songs in columns - **#**, **Title**, **Album** and **Length**. Its **Edit** is the phone's form, as before.
  There's no Play Next or Play Last (the queue's one item is Add to Queue, as on the phone and in the right-click), and
  no list of the album's other pressings.
  **An artist's page** is the Mac's own too: a toolbar of **Play**, **Shuffle** and - once their albums on MusicBrainz
  are asked - **Studio only | Everything**, with **Artist images…**, **Move albums…** and **Which artist is this?** at
  its end for someone who may ([Managing an artist](#managing-an-artist)), folded into a **•••** in a narrow window.
  Under it a band: their round picture, their name, who they are on MusicBrainz ("Group · Sydney · since 1973"), their
  Last.fm listeners, and chips at its right - "6 in your library", "2 in the collection", "10 more to get" (that one
  only for someone who can get albums). Then **Top Songs** (all ten, with **From Last.fm** under them - after the albums
  when Last.fm answered late), **Albums**: the discography in columns - **Album**, **Year**, **Songs**, **In your
  library** (a chip, then the album's format once its songs have come, "2 pressings", or "not in your library") and the
  buttons: **Play** and **Open** for an album of yours, **Get** for one nobody has (it opens the album you don't have;
  for someone who can't get albums - with logins on, an admin gives **Get albums** - it's **Open**), **Open** for one of
  theirs the library holds - and **Most played**: the songs of theirs you've played most, each once however many
  pressings it's on, with its plays (no section at all until you've played one of them). Double-click or Return plays
  from a song or opens an album - a double-click on a row's buttons is the buttons', not the row's; right-click one of
  yours for its menu. The tables are part of the page, which scrolls as one; ↑ and ↓ move through the table you last
  clicked, bringing its row into view. VoiceOver reads an album's row as one - "Low, 1977, in your library, FLAC" - its
  Play, Open and Get as its actions. The status bar: "16 albums", "6 in your library", "59 songs".
  The album you don't have sits in the middle of the page at a readable width (760 points); it scrolls with the pointer
  anywhere across the page, their scroll bar at its right edge. Pages you've opened stay as you left them as you move
  between the sidebar's rows - Library, Search, Requests and Settings each keep their pages, where you'd scrolled to and
  what you'd typed or begun, a playlist's Edit included, as the phone's tabs keep them. One thing starts again: All's
  Albums, Artists, Songs and Downloaded each open in place of the last one, so going back to one after another starts
  it at its top.
- **The player bar**, always there along the foot, 66 points tall. At its left the keys in one row: **Shuffle**,
  **Previous**, **Play/Pause** (the big purple one, with a spinner while a song loads), **Next** and **Repeat** - Shuffle
  and Repeat light while on. Then the display, the bar's whole height: the song's cover flush at its left - click it for
  the cover full size - and three lines beside it. The first is the song's title, with **Next** and the song that then
  plays at its right; the second **Artist — Album**, which goes to the album's page, with a readout like "3 of 11 · FLAC
  16/44.1" at its right - the song's place in what you queued and its format; the third the time played, the scrubber
  and the time left (click or drag on it to move in the song). In a narrow window the first line leaves out Next when
  it has no room for it and the second its readout, each on its own; hold the pointer over a cut-short title or name
  and it shows whole. Then the tools: **Queue**, **Lyrics** and **Info** as one joined strip, the **EQ**, where the
  music plays - AirPlay's button and the output's name, the name left out in a window under 1000 points wide (hold the
  pointer over the button for it) - and **•••**, Now Playing's: Info, Add to a playlist…, Go to album, the song's
  download items, the EQ. With nothing queued the keys are dimmed and the display says **Nothing playing**.
- **The side panel**: a strip of tabs along its top - **Queue**, **Lyrics**, **Info** and **EQ** - and the tab's page
  under them, one at a time, 400 points wide. Open it from the bar's Queue, Lyrics, Info and EQ buttons (each lit
  while its tab shows), the •••'s Info and EQ, or **View > Queue** ⌥⌘U, **Lyrics** ⌥⌘L, **Info** ⌘I and **EQ** ⌥⌘E, each ticked while its tab shows; or click a
  tab to move to it. A tab's key (or menu item) shows its tab - opening the panel if it's shut, switching to it if
  another tab shows - and closes the panel when its tab is the one showing; a tab's **Done** or Escape closes it too.
  With the window 1280 points wide or more the panel is a column of its own and the page narrows beside it; narrower,
  it lies over the page's right edge. Either way the page, the sidebar and the bar still answer. The Queue is the
  phone's, Lyrics the lines Now Playing shows on the phone, lit as they're sung, and the EQ the phone's EQ page for
  the output playing now, every control working there; its Import… opens its preview over the window, and a shared
  or opened EQ file (File > Import EQ File…, Open With, a file dropped on the window) shows the EQ tab with its preview
  over it - the Mac has one EQ. **Info** is about what you've selected - an album's row selected in a list shows its
  Album info, an artist's their name and Go to artist, headed **Selected album** or **Selected artist** - and with
  nothing selected about the song playing, headed **Playing**. When the queue ends the Queue closes, and Info unless
  something is selected; Lyrics stays, saying Nothing playing. With nothing playing, the Queue tab - and Info, with
  nothing selected either - says **Nothing playing** too. Settings > Playback's **EQ** row opens the EQ tab. Going to an album from
  the bar, Info or ⌘L closes a panel lying over the page, so it doesn't cover the album.
- **No Now Playing.** The Mac has no Now Playing screen, and so no turntable: everything Now Playing has is in the bar
  and the side panel.

**The menu bar** keeps the Mac's own menus - Undo to Select All, Close Window ⌘W, Enter Full Screen, the Window menu -
and adds deadwax's:

| menu | what deadwax adds |
| --- | --- |
| **deadwax** | About deadwax, **Settings…** ⌘, (the Settings tab), Hide deadwax ⌘H, Quit deadwax ⌘Q |
| **File** | **Import EQ File…** ⌘O: the Mac's Open panel, for an EQ setting's `.txt` (see EQ files below); **Save changes** ⌘S: Server settings' Save changes, while one of its pages is in front (see Managing below); Close Window ⌘W - and no New Window: there is only ever one window |
| **Edit** | **Find** ⌘F: the cursor in the sidebar's search field, the sidebar shown if it was hidden. The Mac's own **Copy** ⌘C and **Select All** ⌘A also copy and select the event log's lines (see Managing below) |
| **View** | **Show Sidebar** or **Hide Sidebar** ⌃⌘S; **Queue** ⌥⌘U, **Lyrics** ⌥⌘L, **Info** ⌘I, **EQ** ⌥⌘E - each shows its tab of the side panel, or closes the panel when its tab is showing, ticked while it shows; **Refresh** ⌘R: the page you're on, asked again (see below); **Row Size** - **Small**, **Medium** or **Large**, the one in use ticked, then **Make Bigger** ⌘+ and **Make Smaller** ⌘−: how tall every list's rows are (see below) |
| **Controls** | **Play** or **Pause** (Space), **Next** ⌘→, **Previous** ⌘←, **Forward 10 Seconds** ⌥⌘→, **Back 10 Seconds** ⌥⌘←, **Shuffle**, **Repeat** (Repeat off, Repeat all, Repeat one - the one that's on is ticked), **Go to Current Song** ⌘L (the album of the song playing) |

Format has nothing of deadwax's in it (there's nothing to format), and there's no deadwax Help (no Mac help book:
this guide is the help). Every Controls item is dimmed while nothing is queued. Shuffle is named as Now Playing's
Shuffle button is: during the Library's Shuffle it reads **Shuffle - shuffling your whole library** (**Shuffle -
shuffling all music** for all of deadwax's), ticked and dimmed, as Now Playing's is - that order is the shuffle. The
Repeat submenu's three items are the words the Queue says to VoiceOver as Repeat changes: Repeat off, Repeat all, Repeat
one. Queue is dimmed with nothing queued (unless its tab is showing: then it closes the panel), and Info too unless a
row is selected, and Lyrics with nothing queued or for a song known to have none. **While a sheet is up** (Edit album, Add to a playlist, the EQ, a cover full size - any of them)
Settings…, Import EQ File…, Find, Refresh, Go to Current Song, the sidebar and the side panel's tabs are dimmed: they'd act on the
window under the sheet - and Save changes is, unless the sheet is Server settings' own page (the Library's Set up
Navidrome) - and all of them until you're signed in. **While a text field has the
cursor** - Search, Find in the Library, a name - Space types a space and ⌘→ and ⌘← move along the line: they don't
play, pause or skip then (their menu items still do). Forward and Back stay within the song. There's no volume of deadwax's own: the Mac's
volume keys and menu bar volume work, as for any app.

The rest of the differences:

- **Pull to refresh** isn't on the Mac: macOS refuses it in the Mac's layout. **View > Refresh** (⌘R) does what the
  page's pull does on the phone, on every page that has one - and on the Library, an album and a playlist, whose pull
  shuffles on the phone, what their **•••** > **Refresh** does. Refresh is dimmed on a page that has none, while one is
  on its way, and while a sheet is up - unless the page in front inside the sheet has a refresh of its own (Edit
  album's release page).
- **Right-click** a song, an album or a playlist for the menu its **•••** has: a song's row (on an album, a playlist,
  All songs or Search) its own •••'s; an album's tile or row (the Library's albums, Search's, an artist's) the album
  page's •••; a playlist's row its page's •••. Only the page's own Refresh is left out - that's ⌘R on the page.
  An album's or a playlist's menu needs its songs, which deadwax is asked for each time the pointer rests on it: until
  the first answer the menu says Loading - right-click again - unless the album or playlist is downloaded, when the
  downloaded one's menu shows at once. After Edit album writes to an album, or a change you make to a playlist, the
  menu waits for deadwax's new answer, so it never queues songs that have gone. An album deadwax no longer has but
  that's downloaded on this Mac has its page's menu - Add to Queue and Album info, no Add to a playlist, Edit album or
  download items. Artists have no right-click menu, as their rows have no •••. The EQ's correction and the event log's
  lines keep their long-press menus, as a right-click.
- **Row Size.** **View > Row Size** sets how tall the rows are in every list the Mac draws as its own: **Small** - as
  they've always been, rows 30 points tall with a cover 20 across - **Medium** (40, with a cover of 28) or **Large**
  (52, with a cover of 40). The one in use is ticked. **Make Bigger** ⌘+ and **Make Smaller** ⌘− go one size at a time
  and stop at the ends: Make Bigger is dimmed at Large, Make Smaller at Small. ⌘+ (typed ⌘⇧= on a US keyboard) and ⌘−
  are the menu's keys, so they work wherever the menu does. ⌘= - the same key without Shift, as Finder takes it - works
  too while deadwax's main window is the one in front. All of them change together: Albums and Artists as a list, an
  album's songs, Playlists, a playlist's songs and Requests (whose rows are 34 at Small, with room for a meter). Only
  the rows and their covers grow: the words stay their size, in the middle of the row, and the column headings and a
  disc's heading row keep theirs. The row you've selected stays in view as the rows grow or shrink. A bigger cover
  leaves a playlist's or a request's name the room it had, so at Large Playlists still shows every column in the
  smallest window and beside the side panel, and Requests still fits a window as it first opens. In a short window an
  album's songs box gives way first, scrolling inside, so Properties stays on the page at Large too. Row Size is kept
  on this Mac, as Grid or List is, and is as you left it after you quit; the phone has no Row Size, and its rows don't
  change. All songs and Search are still the phone's pages, so they don't follow it yet.
- **Escape** closes the sheet in front - its Close, Cancel or Done, so where Close asks before throwing away what you
  typed (Edit album, Artist images, a playlist's Edit), Escape asks too. Where Close doesn't ask, Escape does nothing
  while you've typed something Close would throw away - Add a person's passwords, Reset password's, Which artist is
  this?'s and Artist images' searches, Choose a source's search words, a new playlist's name: click Close or Cancel
  then. It closes a cover shown full size. In the window itself Escape goes to one thing at a time, in this order: a
  text field with the cursor (the sidebar's search field's Escape empties it), then the side panel, whichever tab
  shows - then a playlist's Edit, as its Cancel. **Return never confirms a delete or a write** in a question
  deadwax asks: Return is the question's Cancel (Keep editing, Keep it, Keep as it is, Cancel). A text field's own
  Return is as on the phone - New playlist's name field creates the playlist.
- **Closing the window** (⌘W, or its red button) leaves the music playing, as Music's does. Click deadwax in the Dock
  and the window comes back on the tab and page you left, the Library on the page it showed. **⌘Q** quits deadwax,
  and the music stops. While Edit album has changes, or a playlist's Edit has, the window can't be closed - Close
  Window is dimmed and the red button off - until you've finished or thrown them away.
- **No turntable**: there's no Now Playing on the Mac to show it, and Settings > Playback hasn't Now Playing opens as
  or Pause winds the record down. The turntable stays the phone's.
- **Your sign-in** is kept in a file rather than the Keychain - see [Where the Mac keeps your sign-in](#where-the-mac-keeps-your-sign-in).
- **EQ files.** An Equalizer APO setting - a `.txt` from AutoEq, say - comes in five
  ways, each to the preview the phone's Import from Files… shows, For the output playing now (from an EQ page's
  Import… or Paste, that page's output, as on the phone), over whatever page or sheet is up:
  - **File > Import EQ File…** ⌘O, from any page: the Mac's Open panel, for one plain-text file.
  - The EQ page's **Import…** (the phone's Import from Files…): the same Open panel.
  - **Finder's Open With**: right-click a `.txt` > Open With > deadwax. deadwax is offered for a text file but never
    made the Mac's default for one - a double-click still opens TextEdit. It comes to deadwax's one window, never a
    second, and with the window closed, that window comes back for it.
  - **Dropped**: drag a `.txt` onto deadwax's window - or onto the EQ's sheet, a window of its own - or onto deadwax's
    icon in the Dock.
  - **Paste**, the EQ page's button, as on the phone: copy the setting's text anywhere, then click Paste. There's no ⌘V
    for it - Edit > Paste is the text fields'.

  The file stays where it was, unchanged: deadwax only reads it. deadwax may read a file you choose, open with it or
  drop, and write one you save, and nothing else outside its own folder. **Export…** has four items on the Mac:
  **Save the Whole Curve…** and **Save the Correction Alone…** open the Mac's Save panel, the file named
  `<output name> EQ.txt` as the phone's share names it, and write it where you save it; then **Share the Whole Curve**
  and **Share the Correction Alone** hand it to the Mac's Share menu - AirDrop, Mail. The correction alone needs a
  correction, as on the phone (dimmed otherwise). A file saved or shared imports again.
- **Managing on a big screen.**
  - **Edit album** is a sheet 760 points wide - the width an artist's page reads at - and as tall as the window less 40
    points above and below, so it always fits inside the window, whatever its size (on macOS 15 or later; on macOS 14
    it's the size macOS gives a sheet). Release, Tags, Artwork, Lyrics and Delete album… open inside it, as on the phone.
  - **Manage's pages** - Edit an album's Choose the folder, Needs a look, Library care, In nobody's library, Server
    settings and each of its groups, the event log, People and a person's page - sit in the middle of the page at the
    same readable width as an album's, scrolling with the pointer anywhere across the page.
  - **Tab** goes to the next field, and **Shift-Tab** back, in the order they're drawn: Edit album's Release and Edit
    tags, People's Add a person and Reset password. Past the last field (or before the first) Tab is the Mac's own.
  - **Return in a field never applies, saves or deletes** there: Apply, Save changes and Delete permanently are clicks.
    In Add a person and Reset password, Return goes to the next field; in People's Unlock, it unlocks; in Choose a
    release, it searches. Change password is as on the phone: Return in its last field changes it.
  - **File > Save changes** ⌘S is Server settings' **Save changes**, the same as clicking it: on while a Server settings
    page is in front with something unsaved; dimmed while nothing is, while a save is on its way, with deadwax out of
    reach, and with another page or sheet in front.
  - **The event log's lines** are selected as a Mac list's rows are: click a line, ⌘-click to add another, ⇧-click for
    a run of them, or - once a line is selected - **Edit > Select All** ⌘A for every one. **Edit > Copy** ⌘C copies
    them as they're shown - each line's time, level, part and words, one to a line, newest first - ready to paste into
    Notes or a message. Copy is dimmed with no line selected. Right-click a line for Copy of that one line, as before.
  - **A run and ⌘Q.** While a Library care run (or Re-time saved lyrics) is under way its page says what quitting
    does: "Quitting deadwax stops the run - open deadwax again, and Get covers carries on." (Get CD art or Get lyrics
    for theirs; "Quitting deadwax stops it - open deadwax again, and running it again carries on." for Re-time). ⌘Q
    doesn't ask first: deadwax's own Quit could ask, but quitting from the Dock, by logging out or restarting can't
    be asked about in an app like this one, so the page says it instead - and the run stops there. Started again, a run
    takes only the albums still without, and Re-time leaves an album already at the lead as it is.
- **The Mac's Now Playing** - in Control Center and the menu bar - shows the song, its artist and cover, and whether
  it's playing or paused; its buttons, the keyboard's media keys (F7, F8, F9) and AirPods' presses play, pause and
  skip, as the lock screen's do on the phone.
- **Picking up where you left off** calls the Mac "Mac", as the web app does for Safari on a Mac: play on the Mac,
  and the phone's notice says "Picked up from your Mac".
- **The Mac's own words.** Where the phone says this phone, the Mac says this Mac: Settings' **This Mac** (the
  phone's This phone), Downloads and Download your library ("Waiting for space on this Mac", "Downloads stay on this
  Mac when you sign out."), an album's and a playlist's download lines, Album info's **On this Mac**, the offline
  banner ("Offline - showing what's on this Mac", then "Join a network to play what isn't on this Mac." - a Mac has no
  Airplane Mode), Pull to shuffle's "songs on this Mac", Lyrics' "not on this Mac", Change password's and
  Normalization's lines. Where the phone says to close deadwax from the app switcher and open it again (downloads it
  can't read, the EQ), the Mac says to quit it. The EQ calls the Mac's own speakers **Mac speakers**, with a speaker
  for their picture - their EQ the same one the Mac kept before, under another name - and its Import from Files… is
  **Import…**. The address screen says macOS 15 or later asks about the local network, and when deadwax can't be
  reached the words point to the Mac's **System Settings > Privacy & Security > Local Network** - on macOS 15 or
  later: macOS 14 has no such switch, and never asks. **Settings > This Mac > Debug** says "This install doesn't
  expire: a Mac keeps opening deadwax without installing it again." - see below - or, for a build installed with a
  provisioning profile (`install-mac.sh --allow-profile`), the date it runs out.
- **Sleep.** Playing when the Mac goes to sleep - the lid closed, Apple menu > Sleep, or asleep by itself when left -
  pauses the music, and the Mac wakes with it paused at the same place: nothing plays until you press Play, which goes
  on from there - never music out of a laptop opened in a meeting. With the lid closed on an external display the Mac
  doesn't sleep, so it plays on.
- **Headphones out.** Unplugging headphones, AirPods or a Bluetooth speaker disconnecting, a USB DAC pulled out: the
  music pauses, as on the phone. Choosing another output yourself (the menu bar's Sound, say) doesn't pause.
- **Download over** (Settings > Downloads) is **Wi-Fi or Ethernet only** (the default) or **Any connection** - "Downloads
  use Wi-Fi or a cable alone - never a hotspot or Low Data Mode." and "Downloads use a hotspot too, when this Mac is on
  one." Under it the Mac says "On Wi-Fi or Ethernet now." (a cable counts as Wi-Fi), and on a phone's hotspot -
  over Wi-Fi, a cable or Bluetooth - "On a hotspot now - downloads wait until you're off it." A download waiting for
  it says "Waiting for Wi-Fi or Ethernet". It's the same setting the phone keeps, by its Mac names.
- **Only while charging** reads where the Mac's power comes from: plugged in, your library downloads; on battery it
  waits ("Waiting for the Mac to charge") until you plug in. A Mac with no battery (a Mac mini, an iMac, a Studio) is
  always plugged in, so it never waits. Debug's Power says "Plugged in" or "On battery".
- **A long run keeps the display on.** A Library care run, or Re-time saved lyrics, keeps the Mac's display awake
  while its page is in front, as the phone keeps its screen on, until the run ends.
- **Work goes on out of sight.** A download or an apply (Edit album's, say) carries on at full speed while the window
  is hidden (⌘H) or covered by other apps - macOS doesn't slow it down. So does a Library care run or Re-time while
  its window is covered. Hiding deadwax or minimizing its window may count as the app going to the background, as
  switching apps does on the phone - only a Mac can tell - and then a run stops after the album it's on and says so,
  as on the phone: running it again carries on. A download still lets the Mac sleep when it's left alone, as it would anyway (a MacBook downloading a whole library
  on battery isn't kept awake for hours); a run or an apply keeps it awake until it ends.
- **Clicks, not taps**: where the phone's words say tap, the Mac's say click - "Couldn't open it - click to try
  again." in Requests, "Click a track's name…" in Edit album, Settings > Getting albums' **When I click Get**, the
  Library's downloaded playlists, Debug's test sounds. After People's permissions are saved: "Saved - Sam has them
  from the next thing they do in deadwax." The note after a force quit says "force quit", not the app switcher.
- **Still the phone's words**: in Debug (an admin's), some of the audio engine's rarer errors, which say "phone" or
  "iOS".

That is the last of the Mac app's planned builds. What comes next is what its checks find - tables in place of Needs
a look's or People's lists, say, if [457](#the-mac-apps-managing-checks-452-458) finds the lists don't read well wide.

### What the Mac needs

- **A Mac with Apple silicon** (M1 or later), on **macOS 14 or later**.
- **Xcode 16 or later**, opened once, with your Apple ID added (Xcode > Settings > Accounts) - steps 2 and 3 of
  [Once](#once). No iPhone is needed, nor any Simulator.
- **Your team in `ios/Config/Local.xcconfig`** - step 4 of [Once](#once): `ios/scripts/install.sh` writes it the
  first time you run it, or copy `Local.xcconfig.example` and put your team id in it. If you already install on the
  phone, it's there. install-mac.sh signs with that team.
- **About 4 GB free**: the build's own files are about 1 GB, and Xcode needs room on the way there.

### Installing it, and again for a new build

```
~/Developer/deadwax/ios/scripts/install-mac.sh
```

It pulls the latest code, asks GitHub whether the app's checks passed on it (they build the Mac app too) and asks
you before building one that failed or is still running, then builds the Mac app (Release, for Apple silicon) and
checks what it made: signed, in the App Sandbox, allowed out to the network and to open and save a file you choose, with the
app's id, and with no provisioning profile in it - one Xcode added after all would make the app stop opening when it
ran out, so install-mac.sh stops there and installs nothing, saying how to be rid of it (`--allow-profile` installs
it anyway). If deadwax is open, it asks "deadwax is open - quit it to install the new one? (If it's playing, the music
stops.)": on yes - or Enter - it asks deadwax to quit, as ⌘Q would - never by force; on no it stops and installs
nothing. `--quit` quits it without asking; `--yes` never does. Then it copies the new app to
**`~/Applications/deadwax.app`** - your own Applications folder, never the Mac's - keeping the old one until the
new one is in place, and opens it. It ends with the version, how long it took and the free space before and after:
`Installed deadwax 0.13 (13) in ~/Applications - it doesn't run out`.

| option | what it does |
| --- | --- |
| `--no-pull` | builds what's checked out, without `git pull` |
| `--yes` | doesn't ask about GitHub's checks: builds even if they failed or are still running. Only that - it never quits deadwax for you |
| `--quit` | quits deadwax if it's open without asking (which stops the music) |
| `--debug` | builds Debug instead of Release |
| `--dry-run` | says what it would do - the build, the quit, the copy, the open - and does none of it |
| `--allow-profile` | installs a build Xcode signed with a provisioning profile after all - which then stops opening when the profile runs out, until install-mac.sh runs again. Without it, such a build isn't installed |

The build happens in `~/Library/Caches/deadwax-build-mac`, and the last build's whole log is `last-build.log` there.
Deleting that folder only means the next build starts afresh.

**It doesn't run out.** The Mac app is signed with your team and no provisioning profile, so - unlike the phone's
free install - it opens for as long as you like, and takes none of a free account's three devices. Run
install-mac.sh again only for a new build. Everything the app keeps - your sign-in, settings, downloads and EQ - is
in its own folder, `~/Library/Containers/net.lizardlounge.deadwax`, so a new install keeps it all. Deleting the app
leaves that folder; deleting the folder too (with deadwax quit) starts it afresh.

**The first time it opens**, macOS may ask a few things:

- **"deadwax would like to find devices on your local network"** (macOS 15 or later - macOS 14 doesn't ask):
  **Allow**, as on the phone - deadwax at a `192.168.…` address or a name on your network can't be reached without it.
- If macOS says it **can't check deadwax for malicious software**, or that it **can't be opened**: an app you built
  yourself shouldn't be stopped, but if it is, open **System Settings > Privacy & Security**, and under the message
  about deadwax choose **Open Anyway**.
- The first time install-mac.sh quits deadwax for you, macOS may ask whether **Terminal may control deadwax**: OK lets
  it ask deadwax to quit. If you said no, install-mac.sh says so - quit deadwax yourself (deadwax > Quit deadwax) and
  run it again, or allow it in System Settings > Privacy & Security > Automation.

Then deadwax's address and the sign-in, as in [The first time you open it](#the-first-time-you-open-it).

### Where the Mac keeps your sign-in

On the phone, the session deadwax gives you at sign-in is kept in the Keychain. On a Mac the Keychain would need a
provisioning profile, and a free account's runs out after seven days - so the Mac keeps it in a file in the app's
own folder:

```
~/Library/Containers/net.lizardlounge.deadwax/Data/Library/Application Support/deadwax/sessions/
```

one file for each deadwax address you've signed in at, named after the address, that only your account on the Mac
can read or change (`-rw-------`, in a folder only you can open). It holds the session and nothing else: **your
password is never kept**, on the Mac as on the phone. **Sign out** (Settings > Account) deletes that address's file
once deadwax has answered it, as the phone's Sign out clears the Keychain. When your sign-in ends some other way - it
ran out, or an admin reset your password - the session ends on deadwax, so the file left behind opens nothing, and
signing in again replaces it. Deleting the file yourself, with deadwax quit, signs the Mac out.

The `sessions` folder is kept out of Time Machine (deadwax marks it so each time it saves a sign-in), as the phone's
Keychain item is kept to that phone: a backup restored to another Mac brings everything of deadwax's but the sign-in,
and you sign in again there. The rest of the app's folder - settings, downloads, the EQ - is backed up as usual.

Looking in that folder from Terminal (`ls`, or deleting the file), macOS may ask whether **"Terminal" would like to
access data from other apps**: **Allow** is right - it's deadwax's own folder you're asking to see, and deadwax
itself never needs that. If you chose Don't Allow, macOS remembers it, and `ls` says "Operation not permitted": that's
macOS keeping one app's data from another, not a missing file.

## The first time you open it

1. **deadwax's address**: the address you open deadwax at, by IP (`192.168.1.20:8090`) or by name.
   `http://` is assumed when you don't type it, and a pasted web-app link (`.../player/`) works too.
   **Check** asks deadwax whether it's there, and the address is kept only once it answers. The first
   time, iOS asks to let deadwax **find devices on your local network**: say yes. Give the address deadwax
   answers at itself: the app follows a redirect only within that address - the same `http://` or `https://`, name
   and port - since every request carries your sign-in (and a sign-in or Change password your password). A proxy
   that sends `http://` on to `https://`, or one name on to another, is refused, so Check fails at that address;
   type the `https://` address (or the other name) instead.
2. **Sign in**, when logins are on: your Navidrome user name and password, as on the web app (a
   password manager can fill them in). The password isn't kept on the phone. Only the session
   deadwax gives back is kept, in the Keychain, for that address (on a Mac, in a file of the app's own - see [Where
   the Mac keeps your sign-in](#where-the-mac-keeps-your-sign-in)). With logins off there's no sign-in,
   and the app opens on the Library.

From then on the app opens straight into your music. It keeps who deadwax last said you are, so it
opens at once and asks deadwax behind it: if your sign-in has ended, the sign-in comes up over the
app, and if deadwax doesn't answer, the app stays open (Settings > About says it couldn't check). Only a phone that
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

The app has four tabs, **Library**, **Search**, **Requests** and **Settings** (a gear - the web app's tab of that
name), along a bar at the foot of the screen: square, the full width, flush with the bottom edge, black with a thin
line along its top. The tab you're on is purple, with a short purple line over it on the
bar's top edge; the others are grey. Requests carries a small purple count over its icon's top right corner, of the
downloads on their way, as on the web app, and none when there are none. Tapping the tab you're on goes back to its
first screen, or to the top of it. Once something is playing, the mini player is the top of the tab bar: one solid
block with the tabs, a thin line between them (see [Playing](#playing)). Every screen scrolls far enough for its last
row to come up above the whole block. While the keyboard is up, the tab bar and the mini player both stay under it.
VoiceOver reads the bar as a tab bar, the tab you're on as selected, and Requests with its count ("Requests, 2
arriving"); at the largest text sizes its words stop growing, and holding a finger on a tab shows it large.

Everything is squarer since the build after app 0.11's Search (still 0.11): album covers have the smallest of
corners, everywhere they're drawn - the album page, Now Playing, the tiles and the rows - and the notices, cards,
buttons and chips small square ones. The mini player is square, as the tab bar it sits on. Artists' pictures and
the avatar stay round.

**The phone is flat** since the build after the Library's one-row top (still 0.13): it is drawn as Now Playing is,
words and glyphs straight on the page with thin lines between things, and nothing grey laid on top. Four kinds of
thing keep a face: the purple button (and the red ones, **Cancel download** and **Forget This Output**), a sunken
track (the EQ's sliders, a download's meter), a picture, and anywhere you type - every field is still a box. Any
other button is its words or its glyph in purple, as tall as before, fading while your finger is on it. A card (a
download on Requests) has no panel, a thin line under it; a group (Info's This song, the EQ's Correction) is a grey
heading over its rows. A switch or a strip of choices (the Library's pages, the Now Playing sheet's Queue, Info and
EQ) is words over a thin line, the chosen one white over a short purple line. A chip (an album's In your library) is
coloured words, a dot before the green, amber, red and purple ones. The mini player and the tab bar are black under a
thin line. Menus, toggles, the count on Requests' tab, covers, the scrubber and Now Playing are as they were, and the
Mac's look is unchanged.

The app's words are in **Libre Franklin**, on the iPhone and the Mac, since the build after the Mac redesign's
slices (still 0.13): every screen's titles, rows, buttons and notes, the navigation bars' titles, and the search
fields. Its readouts are in **Courier Prime**, a typewriter face: the numbers the new look draws as data (a song's
length, its number on the album, the time left in the Queue on the iPhone, a download's progress in Requests), and
the ones that change as you watch them - the clocks under the scrubber and in the player bar, the speeds in Requests
and the Mac's status bar, the EQ's values (deadwax's own preamp too), the size of this device's downloads in
Settings, Library care's last scan and Debug's measurements. Every Courier Prime letter is the same width, so a
number that changes keeps its place as it counts. A count inside a sentence stays in Libre Franklin, as the new look
draws it - "Downloading - 4 of 12 songs", Settings > Downloads' amount and counts while songs come, an album's
download line, the Mac Queue's time left - so its figures can shift a little as they change. A readout beside words
sits on the same line as them. (Until this build the app was in Noto Sans, the web app's face, which the web app
keeps.) Libre Franklin covers Latin with every European
language's accents, Vietnamese and Cyrillic, but not Greek; Courier Prime covers Latin. Anything either face hasn't
got - Greek, Japanese, Korean, Arabic, or Cyrillic in a readout - is drawn in iOS's own face, a letter at a time. Both
grow and shrink with your text size as iOS's own did. A few things are still in iOS's face: the symbols, the menus,
alerts and swipe buttons (iOS draws those itself), and ids, paths and versions on screens the new look hasn't
redrawn, which keep the phone's monospace. **Bold Text** (the iPhone's Settings > Accessibility > Display & Text Size)
makes iOS's face heavier, but not Libre Franklin or Courier Prime.

## The Library

The Library opens on its pages, side by side: **Albums**, **Playlists**, **Artists** and - without a
library of your own - **Songs**. Its top is one row: the **magnifying glass** (Find - below) at the left, the
**•••** at the right - two bare white glyphs - and between them a switch with a word for each page, in the order you
keep (Edit order - below), a thin line under them; the page you're on is white over a short purple line, the others
grey. Tap a page's word to go to it, or swipe left and right between the pages, the purple line following you. The
switch's words grow with the text size, up to the tab bar's largest; where the pages don't fit across beside the two
glyphs with room between their words (four pages - logins off - on most phones at the standard text size; on a
narrow phone, Yours' three at the two largest standard sizes and All's at the largest), the switch moves onto a row of
its own under them, rather than cut a word short. The Library opens on the first page each time the app starts,
and when someone else signs in; after that it stays on the page you left it on. Tap the Library tab while you're on
it, and the page goes back to its top.

Under the top each page has its own quiet line, all words, nothing boxed: how many there are ("3012 albums"), then -
on Albums and Artists - its order, in purple (tap it to choose another), or on Playlists **New playlist…**. At the
end of Albums' line are its **grid** and **list** marks, and - with a library of your own - every page's line ends
with **Yours | All** (below). On the line, white is where you are and purple is what a tap takes you to: the layout
showing and the side you're on are white, the other of each purple. Where a line is too long for the phone's width
(a long order, a big count, Find's "12 of 140", a larger text size), the count gives way first - "140 · Recently
added", the number without its word (VoiceOver still says "140 albums") - and only where even that is too long does
the line's end move onto a line of its own under the words, at the right, the count saying its word again. The
order's words are never shortened, and no word is ever cut.

**Find** is hidden until you tap the magnifying glass: then its field comes up under the top, for the page
you're on ("Find in albums", "Find in playlists"...), with the keyboard up. Each page keeps its own words while
Find is open - swipe to another page, or tap its part of the switch, and the field shows that page's. **Cancel**
puts Find away and clears the words of every page, so no page is ever left filtered with Find hidden. The keyboard's
Search key puts the keyboard away and leaves the words. At the larger text sizes, holding a finger on the
magnifying glass or the ••• shows it large.

With logins on, **Albums** is **Your albums**: the albums in your library, as the web app's Library has them
([sharing deadwax](sharing.md) says how an album gets there), and **All**, at the end of the page's line, shows the
whole collection's instead: its Albums, Artists and Songs as the pages, and **Yours** your own again. Yours | All shows
while the Library is on your albums and deadwax can be reached - and stays while you're on **All** when deadwax drops
out: All keeps its pages, showing what the app already has, until you tap **Yours**. On Yours it's put away until
deadwax is back. With logins off, and for the break-glass `deadwax` sign-in, Albums is the whole
collection. **Playlists** is your playlists (see [Playlists](#playlists)), **Artists** the artists of
your albums (see [Artists](#artists)), and **Songs**, with logins off and for the break-glass sign-in, every
song in the collection (see [Songs](#songs)). With logins on there's no Songs page: Navidrome can't list
your library's songs alone, so every song is the collection's: Songs is a page of **All**, never beside your own
albums.

**The •••** at the top's right (VoiceOver reads it "More for the Library"):

- **Shuffle**: your whole library, shuffled - see [Shuffling your library](#shuffling-your-library). Until
  it's ready it reads "Getting ready…", dimmed.
- **Downloaded**: what's on this phone (below), opened over the Library. While deadwax can't be reached the
  Albums page is Downloaded itself, so this is **Your albums** (or **Albums**) instead, the way back to the list.
- **Refresh**: your albums, your playlists and the artists asked for again now - and the Songs page, once
  you've opened it, from its top.
- **Edit order**: the pages as rows - drag them by their handles into the order you want, and **Done**. The
  Library opens on the first, and this phone remembers the order. A page that's new since you last
  arranged them (Artists and Songs, for an order arranged before they came) joins at the end. With logins
  on, Songs isn't a page, so it isn't listed, and keeps its place for a sign-in without a library.

The orders and Grid or list moved into the ••• when Artists joined, and Playlists' **+** became the •••'s New
playlist when the top got its magnifying glass. In the redesign they came out again, onto each page's line, and All
music became **Yours | All**. For a day the top was "Library" over a row of buttons, Downloaded the last of them;
now it's the one row again, and Downloaded is back in the •••.

On the Albums page:

- **Grid or list**: the list mark at the end of the page's line switches to rows, the grid mark back to
  covers. It starts as a grid, and this phone remembers your choice - apart from a Mac's.
- **The order** (on the page's line): **Artist** (the first time), **Title**, **Recently added**,
  **Year, newest first** or **Year, oldest first**, under headers: the first letter (names that don't
  start with a letter come last, under #), the month it was added ("Date unknown" when deadwax
  doesn't know), or the year ("No year"). In Your albums, Recently added means when the album came
  into your library; in All albums, when the collection got it. This phone remembers the order.
- **Find** (the magnifying glass) keeps the albums whose title or artist holds every word you type, in any
  order and anywhere in a word ("eat" finds the Beatles). The count above the albums then says "12 of
  3012 albums". Each page keeps its own words in Find.
- **The index** down the right edge, once a list has 50 albums or more: A to Z and # for Artist and
  Title, decades for the two Year orders. There's none for Recently added, or while you're finding.
  Touch or slide along it to jump - even while the list is still gliding from a flick: the touch stops it and
  jumps.
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
for itself as it comes into view, and ••• > Refresh asks now. **All**'s pages shuffle the whole collection. The
lists opened over the Library - Downloaded, Downloaded playlists, and All albums from See All music - still refresh
when pulled. An album's page and a
playlist's pull the same way, shuffling that album or playlist (see [An album's page](#an-albums-page)).

It's deadwax's shuffle, the web app's Library > Shuffle: every song of your library (of the collection,
without a library of your own) once, in an order deadwax makes, played from the first. Its first 200
songs are fetched before you ask - as the Library comes into view, and again when that was more than ten
minutes ago - so the music starts the moment you let go. More are added to the end of the Queue as it plays,
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

**Downloaded** (in the Library's •••) is every album with a song on this phone, whoever's library it's in, drawn as
the other lists are: the same orders, Find, headers and index. An album your library is downloading by
itself shows there once a song of it is here or downloading, never while it only waits its turn.
Its **Recently added** means downloaded to this phone, newest first. Each album there has a third
line: "12 songs", "3 of 12 songs", "Downloading", "Waiting", or, in amber, "Didn't download". With
nothing on the phone it says "Nothing downloaded yet." At its top, **Downloaded playlists** when you've
[downloaded a playlist](#downloading-a-playlist).

**Keep your library on this phone?** The first time you open Downloaded while your library has albums, a
card at its top asks whether to [download your library](#your-library-on-this-phone) by itself ("Keep the
collection on this phone?" with logins off), as much as fits in your storage limit. **Turn On** turns it
on; **Not Now** puts the card away. Either way it doesn't come back, and the setting is in Settings > Downloads.

**The download marks**, at the end of an album's artist line on every list (and on a song's row on an
album's page): a filled arrow for downloaded (all of it, or some of its songs), a dotted one while it
waits, a ring filling as it downloads, and an amber **!** for didn't download. VoiceOver says them in
words after the artist: "Downloaded", "Partly downloaded", "Downloading", "Waiting to download",
"Didn't download".

**The Library needs Navidrome**: it's the albums Navidrome lists, through deadwax. If deadwax can't
reach Navidrome, or hasn't been told where it is, the Library says so in place of its pages (see
[When something goes wrong](#when-something-goes-wrong)) - with **On this phone > Downloaded** under
it when anything is downloaded, since those play from the phone. It checks again each time you come
back to the Library tab or the app, and when you pull down. When deadwax hasn't been told where Navidrome is, an
admin sees **Set up Navidrome**: it opens [Server settings](#server-settings)' Connections page in a sheet over the
Library - see [Set up Navidrome](#set-up-navidrome).

## An album's page

- **At the top**: the cover, the title, the artist, and a line like "Electronic · 1998 · FLAC" (the
  genre, the year, and the format when all its songs share one). It says whether the album is **In
  your library** or only **In the collection**. With logins off, and for the break-glass `deadwax`
  sign-in, every album reads In your library.
- **Play** plays the album from its first song. **Shuffle** plays it in a random order, with Shuffle
  on. Play is the purple button, square, and Shuffle beside it its word in purple with no face (at the largest text
  sizes one over the other).
- **The top row**: ‹ back, and at the right **Edit** (see below), then the **•••**.
- **Pull down** at the top of the page, a good way past it, as on the Library's pages (see [Shuffling your
  library](#shuffling-your-library)): the ring over the cover fills, "Pull to shuffle"; at the line a tick and the
  purple disc, "Release to shuffle"; let go and the album plays just as **Shuffle** plays it. While deadwax can't be
  reached, or for an album gone from the collection, it's only the album's songs on the phone ("Pull to shuffle the
  songs on this phone"), or "Nothing on this phone to shuffle" with none. While the album is still loading, or
  couldn't be loaded, the pull shows nothing and plays nothing. A pull doesn't refresh the page any more: ••• >
  **Refresh** does (while deadwax can't be reached, it checks whether it's back), and an album that couldn't be
  loaded has **Try again** under why.
- **The songs**, under a heading for each disc when there's more than one, or a disc has a title
  ("Disc 2", or "Disc 2 · Live" with its title). The song playing has moving bars instead of its
  number. **Tap a song** to play the album from it. **Swipe a song right** to add it to the queue (see [Adding
  to the queue](#adding-to-the-queue)). Under the songs: how many and how long ("10 songs, 42 min").
- **•••** at the end of a song's row has **Add to Queue** and **Add to a playlist…** for that song; the
  **•••** at the top has them for the whole album (see [the Queue](#queue) and [Add to a
  playlist](#add-to-a-playlist)). Each menu opens from the ••• you tapped, and a tap anywhere else
  closes it.
- **Edit**, at the top right before the •••, for someone who may edit albums (Edit albums or Look after the library -
  an admin, or everyone with logins off): the album's editor, on a sheet over the tabs - see [Edit
  album](#edit-album). It's dimmed while deadwax can't be reached, and for an album gone from the collection. (A
  right-click on the album elsewhere on the Mac still has **Edit album** in its menu.)
- **Album info**, in the last part of the top •••'s menu, for everyone: everything known about the album, on a sheet
  of its own with **Done**. See [Album info](#album-info). **Refresh** ends that part: the album asked for again now.
- **Add to my library** and **Remove from my library**, with logins on. Removing takes the album out
  of your library only: "it's still in the collection, and nothing was deleted."
- **The artist's name**, in purple, opens [their page](#artists). An album that names no artist to go to
  shows the name in grey, and it opens nothing. While the album is still loading, and the list you came
  from didn't say who its artist is, the name is purple but can't be tapped yet, so it never changes
  colour as the album comes in. If the album doesn't come - it couldn't be loaded, it's gone, or deadwax
  can't be reached and it isn't on the phone - the name is grey.

**Downloading it** (see [Downloads](#downloads)):

- **Download**, in the top •••'s menu (where the download button at the top right was until the new look): it
  downloads every song of the album that isn't on the phone yet. Once it's asked for, that part of the menu is
  headed with how it's going, in words ("Downloading - 4 of 12", "Waiting for Wi-Fi" with "Download over is Wi-Fi
  only - in Settings > Downloads." under it, "Downloaded · 412 MB", "2 songs didn't download" and why), with
  **Remove Download** (and **Download Again** when a song didn't download). VoiceOver says when it has finished.
- **Under the title**, the same in words: "Downloading - 4 of 12", "Waiting for Wi-Fi", "Downloaded",
  "3 of 12 songs downloaded", "2 songs didn't download".
- **Each song** has its mark before its time, and its **•••** has **Download** (or **Remove
  Download**, or **Download Again**); the **•••** at the top has them for the whole album. Removing
  says "Removed from this phone: Dummy".
- **Under the songs**: "412 MB on this phone", or "3 of 12 songs on this phone · 92 MB".
- An album that's gone from the collection, with songs of it still on the phone, says "This album
  isn't in the collection any more - the songs on this phone still play.", and its ••• has only
  Remove Download.

With [Download your library](#your-library-on-this-phone) on:

- An album it downloaded has the same Download part in the •••, headed "Downloaded with your library". **Remove
  Download** removes it, and your library then leaves it off this phone - the page says "You removed
  this download - your library leaves it off this phone." - until you download it again with **Download**.
- An album of your library that doesn't fit says, under the title, "Your library doesn't all fit in 20
  GB - this one waits for room." **Download** downloads it anyway, as yours: first in line, and never
  removed to make room.
- A song your library downloaded has no Remove Download of its own (it would only come back): remove
  its album instead.
- **Remove from my library**, when your library downloaded the album and you downloaded none of it
  yourself, says "Its download goes from this phone too." - and it does, as soon as deadwax's list
  agrees, usually at once.

With Normalization on, opening an album that has FLAC songs asks deadwax to measure it, if it hasn't
yet, so its first song is less likely to wait when you play it.

### Album info

**Album info** (the album page's top **•••**, or under the album in [Info](#info)) is everything known about an
album as a whole, grouped. A line with nothing to say is left out, never shown as "Unknown".

- **Quality**: **Format** - "FLAC · 24-bit / 96 kHz · all 10 songs", or one line for each kind when the songs
  differ ("FLAC · 16-bit / 44.1 kHz · 8 of 10 songs", "MP3 · 320 kbps · 2 of 10 songs"). Only a lossless format
  (FLAC, ALAC, APE, WAV, AIFF, WavPack) shows a bit depth; anything else - MP3, AAC, Opus, DSF - shows its bitrate on
  the same line instead ("MP3 · 245 kbps on average"). An M4A says which of the two is inside it: **ALAC** when the
  file's type names ALAC, **AAC** when it names AAC, and otherwise - Navidrome calls both "audio/mp4" - ALAC only when
  the album's M4As average over 400 kbps (iTunes' and Apple Music's AAC is at most 320; ALAC is rarely under 500), so
  an AAC is never shown as "16-bit / 44.1 kHz". **Bitrate**, for an album that is all lossless: "1,411 kbps" when
  every song has the same, otherwise "1,350 kbps on average" (each song's bitrate weighed by its length). An album
  that mixes lossless and lossy files has no Bitrate line - each kind says its own. **Channels**: Mono, Stereo, 5.1
  surround, 7.1 surround.
- **The album**: how many **Songs**; **Discs** when there's more than one, with each disc's title and songs ("Disc
  2 · Live at Wembley · 3 songs"), or the **Disc title** of a single disc that has one; its **Length** and **Size**.
- **On this phone**: **Downloaded** - "All 10 songs · 412 MB", "3 of 12 songs · 92 MB" or "Not downloaded", with
  what's under way ("Downloading - 4 of 12 songs", "Waiting for Wi-Fi") under it.
- **The release**: **Media** ("CD", "2×CD + DVD-Video", 12" Vinyl, "Digital Media"), **Label**, **Catalogue
  number**, **Barcode**, **Country** ("United Kingdom", "Worldwide", "Europe", and the countries MusicBrainz still
  lists that have gone: "Soviet Union", "East Germany", "Czechoslovakia", "Yugoslavia", "Serbia and Montenegro";
  MusicBrainz's "unknown country" is left out), **Released** and **First released** (when it isn't the same: "26
  September 2011", "1 March 1973"), **Type** ("Album · Live", "Compilation", "DJ mix", "Mixtape/Street"),
  **Status** ("Official", "Promotion"), **Edition**, **Genres**, and **Added** - when deadwax first saw the album,
  with "downloaded by deadwax" when that first copy is one deadwax downloaded and filed itself.
- **MusicBrainz**: the **Release** and **Release group** ids, each with a **Copy** button, and **This pressing on
  MusicBrainz** and **Every pressing on MusicBrainz**, which open those pages in Safari.
- **On the server**, for an admin: the album's **Folder** (one per disc for a set kept that way), with **Copy**.

The media, catalogue number, barcode, country and status come from the album's files themselves, read as the sheet
opens - so they show only for an album whose files carry them. MusicBrainz Picard writes all five. When deadwax files
an album it writes the country into every file, and the media and catalogue number into a FLAC or MP3 but not an M4A
(the tag library it writes with has no M4A names for those two); it never writes the barcode or status. Its media
is the whole release's ("CD + CD" in every file of a 2-CD set), which Album info says once, as "2×CD". An album that
isn't matched to MusicBrainz has no folder deadwax knows by its id, so none of the five show for it - the sheet says
"deadwax doesn't know where this album's files are, so nothing was read from them."

The first three parts show at once. The rest comes from deadwax: "Reading the album's files…" shows for a moment
in their place (a box set on a disk that's asleep can take a while - its folders are read two at a time), then they
appear. While deadwax can't be reached, the sheet shows what the phone has - with the label, year and genre the album
already said - and, while anything is still missing, "The rest shows once deadwax is back."; it fills in by itself
when deadwax is back. If something couldn't be asked - the album itself, where its files are, or the files - the
sheet says which, and why, in a line of its own ("The album's files couldn't be read just now. …"), so a missing line
never looks like a tag the files don't have.

Opened from Info, it stays on the album it was opened for: if the song changes to another album while you're reading
it, the page doesn't change under you. Back returns to Info, which by then shows the song now playing.

Each id, the barcode, the catalogue number and the folder are in the typewriter face; you can select them, and
**Copy** puts the whole of one on the clipboard, its button a tick for a moment. If Safari can't open a MusicBrainz
page (turned off in Screen Time), the sheet says so under the link.

### Edit album

**Edit album** is the web app's album editor, on the phone: which release the album on disk really is, and its tags
and folder put right to match. It opens from an album page's top **•••** (**Edit album**, between Album info and
Refresh), from Settings > Manage > **Edit an album**, or from a row of [Needs a look](#needs-a-look) - with ‹, Skip and
Next album at its foot to work through the list - for someone who may edit albums - Edit albums or Look after the
library: an admin, or everyone with logins off. It's a sheet over the tabs, titled Edit album, laid out as iOS
Settings is: a header, then rows that each open a page. **Close** is at its top left.

**Finding the folder.** The editor works on the album's folder in deadwax's library, which the phone finds as the web
app does: the folder deadwax knows the album by, else the folder tagged with the album's release, else an untagged one
with its name and artist. "Finding the album's folder…" shows while deadwax reads the library (the first time on a big
library, a minute or more). When it can't find one it says why ("deadwax can't find this album's folder: …") with
**Look again** and **Choose the folder**. Several folders with the album's name and nothing to tell them apart:
"Which folder is this album?" over a **Folder** menu of their paths - pick the right one. An album kept as one folder
per disc opens on the first, with the Folder menu to move between them.

**Choose the folder** (Settings > Manage > Edit an album, or the editor's own when it can't find the folder) is every
album folder deadwax's library has, with a search at the top ("Folder, artist or album"): type any words of its
artist, album or path, accents and capitals aside. The first 50 matches show, and the line over them says how many
there are ("The first 50 of 1060 folders - type more of the folder's name to narrow them."). Each row is the folder's
cover, its album, its artist and its path. Tap one and Edit album opens for it - the way to a folder Navidrome
doesn't list. Pull down to read the library again.

**The editor's first page:**

- **The header**: the folder's cover, the album, the artist (and its edition), the folder's formats and track count
  ("FLAC · 12 tracks · 2 discs"), and the folder's path under them, which you can select.
- **Folder**, a menu, when the album is in more than one folder.
- **Needs a look**, with Edit albums, when something's wrong with the album: each issue, with what it means ("Not
  matched to MusicBrainz", "No cover art"...), as Needs a look in the web app says them. With **Look after the
  library** too, **It's fine as it is** under them takes the album out of Needs a look for those issues; after it,
  "Marked fine: …" says which, with **Ask about it again** to put it back. A mark deadwax refuses says why under them;
  one it doesn't answer (or answers with a server error) may still have been kept, so the album is read again and shows
  what deadwax now holds - as an apply that got no answer is. Someone with Edit albums alone sees the
  issues, but not the two buttons - marking an album fine is the library's keeper's call - and someone with Look after
  the library alone has only Delete album…, as in the web app.
- **Edit**, with Edit albums: **Release** - the release the album is matched to, or "Not matched to a release" - opens
  the Release page (below), **Tags** ("12 tracks") the album's files, **Artwork** ("Cover, CD art", "No cover") its
  cover and CD art, and **Lyrics** ("8 of 12") how many tracks have lyrics (all below).
- **Delete album…**, in red, with Look after the library, opens the Delete album page (below).

**Release** is the release, the fields, the cover and what Apply will do, top to bottom:

- **Release**: the pressing chosen - its cover, title, artist, its year and what tells it apart ("2011 · CD · GB ·
  SHVL 804"), its track count (in amber when it isn't the folder's), and **Current** when the folder is already tagged
  with it. Tap it to **Choose a release**. With none chosen yet, "Choose a release".
- **Fields**: **Artist**, **Album**, **Year**, **Original year** and **Edition**, as the web app's editor has them -
  the years with the number pad, **Done** above the keyboard. Choosing a release fills them in from it (Edition left
  blank, worked out from the release). "Blank fields are left alone rather than cleared. The folder is named after the
  original year and the edition, so a remaster files under the album's own year."
- **Cover**: a switch, "Download cover art" - or "Replace cover.jpg" when the folder has one - on at first only when it
  has none, with where it comes from and the size it's saved at under it. **Compare covers…** opens the folder's cover
  beside the release's (below).
- **What Apply does**, worked out by deadwax as you go: "Working out the changes…" (or "Fetching the tracklist…" while
  a release you chose loads), then anything worth reading first - a track count that differs, files the tracklist
  didn't reach - in amber; when the folder will be renamed, **Folder** with its path now and → its new path (**Merge**
  when the discs of one release join one folder, and what moves where); when the rename waits, why ("Writes the tags
  first and renames the folder once Navidrome has scanned them (usually a few seconds), so Navidrome keeps this
  album's plays, ratings and favourites."); and "3 of 12 files would change, and the folder would be renamed", which
  opens **Changes** - each file's tags, what each holds now and what it would hold. Or "Nothing to change." It's worked
  out again a moment after you stop typing.
- **Apply**: on once What Apply does is for what the page shows now and has something to change. It writes the tags,
  renames the folder and saves the cover, as the web app's Apply does; nothing on the sheet can close it while it runs,
  and it says what it's waiting for: "Applying, waiting for Navidrome", or "Applying, renaming in 20s". Then what it
  did: "Updated the tags in 12 files, moved the folder to match its tags." The folder is read again, and the album page
  under the sheet shows the album as it is now.

**Choose a release** is MusicBrainz's pressings of the album, best first, as the web app's editor lists them: it
searches for the fields' artist and album (or for words you type at the top), takes the three albums that match best
and lists every pressing of them, the closest first - the one the folder is tagged with marked Current. Each row is as
on Release. Tap one: its tracklist loads (a spinner on the row), the fields fill in, and you're back on Release. While
MusicBrainz is away: "MusicBrainz is unreachable right now, so there's nothing to match against. You can still correct
the fields by hand." - and the fields still apply.

**Compare covers** shows the folder's cover ("Current", or "No cover on disk") beside the release's ("From this
release", through deadwax). Tap either for it full screen. **Replace cover only** (or **Save cover only**, when the
folder has none) saves the release's cover into the folder and changes nothing else: "Saved cover.jpg, replacing
cover.png." It's off until the release's cover has shown, so you never save one you haven't seen - and while an Apply
runs, or the folder is still being read again after one. If its answer never comes, it's said as an Apply's is (below).

**Tags** is the album's files as deadwax reads them from the disk when it opens ("Reading the files…"), in running
order - a section for each disc on a set ("Disc 1", "Disc 2"). Each row is the track's number (its disc first on a
set: "2-04") and its title, with its artist under it when it isn't the album's. Tap a track for its page. **Select**
(top right) lets you tick tracks, with **Select every track** at the bottom; **Edit 3 tracks…** at the bottom (or
**Edit all tracks…** with none ticked) opens Edit tags for them, and **Done** ends Select. Choosing other tracks while
Edit tags holds changes you haven't applied asks "Discard changes?" first.

**A track's page** is everything in its file, as the web app's track view shows it: its title (or its file's name, with
"No title tag - this is the file's name."), where it sits ("Track 3, disc 2 of 2 · 4:07 · FLAC"), **Edit this
track…**, then what the file holds under **Tags**, **Audio**, **MusicBrainz** and **File** - only the fields it has,
a default dimmed with why under it ("No disc number on the file - it reads as disc 1"). **Pictures in this file** is
each picture inside it - its kind ("Front cover"), its size once it has loaded ("500 × 500 · 61 KB · JPEG"); tap one
to see it full screen - or "None - a player shows the album's cover for this song, or its CD art if the song has a disc
number." Last, **All tags in this file (24)**: every tag under its own name, and the file's name; you can select them.

**Edit tags** is the web app's tag editor: **Title**, **Artist** and **Track**; **Album**, **Album artist**, **Disc**
and **Disc title**; **Year** and **Original year**; **Genre** and **Composer** - each showing what the tracks say, or
"Several values" where they disagree ("Differs between tracks - left alone, each keeps its own"); tapping into one
and out again changes nothing - only typing does. Type over a field and only that field is written, to every track
chosen; **Undo** under it puts back what the files say, and emptying a
field removes the tag ("Will be removed"). A track or disc number has to be a number ("3" or "3/12"), a year a year
or a date ("2022" or "2022-07-29"): anything else is said under the field in amber, and nothing is asked until it's
put right. **What would change** is worked out by deadwax a moment after you stop typing: each file that would change,
each tag with what it says now and what it would say ("removed" for a tag taken away) - or "Nothing to change - every
track already says that." **Apply** writes them, as the web app's does: "Saved 12 files." No file is renamed and the
folder stays where it is - Release moves an album's folder to where its tags say it belongs. Then the files are read
again - until they have been, Edit tags shows "Saved 12 files." and "Reading the files…" rather than the fields, which
would still say what the files said before (if they can't be read, it says why, with **Look again**) - and the album
page under the sheet shows the album as it is now. A big album takes longer to write - a file is sometimes written out
whole - so the phone waits two minutes and more by how much the files hold. An Apply whose answer never comes is said
as Release's is (below), and the files read again before Apply comes back on.

**Artwork** is the web app's Artwork tab. **Cover**: the folder's cover - tap it to see it full screen - and where it
is ("A cover is saved beside the tracks.", "The cover is inside the files, with none beside them.", or "No cover is
saved with the album."). With none, and the album matched to a release, **Get cover** saves the release's front from
the Cover Art Archive beside the tracks - "Getting the cover…" while it does - and once the folder has been read
again the cover shows, here and on the album page. When the Archive has none for that release it says so ("The Cover
Art Archive has no front cover for that release.") and the button becomes **Look again**. With no release, "To get a
cover, first match the album to a release on the Release page." opens Release; with a cover, "To replace it, compare
it with the release's on the Release page (Compare covers…)." opens Compare covers. **CD art**: the pictures of the
disc beside the tracks, in a grid with their names ("Beside the tracks - what players show for a song with a disc
number:") - tap one to see it full screen - or "No picture of the disc beside the tracks." With the album matched to a
release and no CD art deadwax saved itself (a `disc` picture), **Get CD art** saves a picture of each disc - the
Cover Art Archive's, else fanart.tv's when deadwax has its key - and after it "deadwax never replaces CD art it
saved.": a second Get is never offered.

**Lyrics** is the web app's Lyrics tab: "8 of 12 tracks have lyrics saved beside them, as a .lrc.", then **Get
lyrics** while any track has none. It asks LRCLIB for each track without a .lrc - never replacing one that's there -
"Getting lyrics…" while it does, and then says what it came to ("Saved lyrics for 3 tracks (2 synced), 8 already had
them, 1 not on LRCLIB."), the button now "Lyrics · 11 of 12" to ask again. With every track done, "Every track has
lyrics." Lyrics saved show on Now Playing once Navidrome has scanned the folder. Under it, where to re-time synced
lyrics - Lyrics in [Server settings](#server-settings), whose **Re-time saved lyrics** moves them to a new lead.

**The Gets are writes**, like Apply: one at a time, never while Release or Edit tags applies (and those are dimmed
while a Get runs), and off until the folder has been read again after any of them. Each says what went wrong under
its button, with **Try again**. A Get can take minutes when LRCLIB or the Cover Art Archive is slow, and the phone
waits as long as that album could take at worst: for lyrics at least ten minutes, more for each track without them
(23 for twelve), and for CD art at least seven, more for each disc. If its answer never comes, it's said as an
Apply's is (below): the folder is read again, so whatever deadwax saved meanwhile shows.

**Delete album** is the web app's Delete tab: it removes the album's folder from deadwax's library, with everything
in it, for good. As it opens, deadwax reads the folder as it is now ("Checking what's in there…"): how many tracks
and how big ("12 tracks · 412 MB"), then any other files in it by name, in amber, since one might be the only copy
("and 2 other files:" over "rip.log, album.cue" - pictures and each track's own .lrc aren't counted), and, with logins
on, whose libraries it's in, in amber: "In ana and bo's libraries: deleting it takes it out, and they'll see it was
removed by an admin.", "In your library: deleting it takes it out.", or "Nobody has it in their library." When deadwax
couldn't read who has it, it says so - never "nobody". If the folder can't be read, "Couldn't read that folder." and
why, with **Look again**. Then, in red, "This deletes the folder and everything in it, permanently. There is no
undo." over **Delete permanently**, which is off until all that has been read - and, when the library couldn't be read
again after a write, says so ("Couldn't read the library.", with **Look again**) rather than staying dimmed with no
reason. Tap it and the phone asks once more - "Delete Dummy?", "There is no undo." - **Delete** in red, or
**Cancel**, the one a stray tap lands on. The question is about that folder as it was just read: if the page moves to
another folder while it's up (the library read again found the album moved), it goes away, and if what's in the
folder has changed meanwhile, nothing is deleted. "Deleting…";
then the sheet closes (VoiceOver says "Deleted Portishead/Dummy (1994).") and the Library asks for its albums again,
now and once Navidrome has scanned. When that folder was all the album had, its page goes back as well; an album in
several folders keeps its page, which shows the rest once Navidrome has scanned. Songs of it downloaded to the phone
still play from there, its page saying "This album isn't in the collection any more - the songs on this phone still
play." Deleting is a write, as an Apply is: never beside one, or a Get, and off until the folder has been read again
after one; nothing on the sheet can close it while it runs. If its answer never comes - or comes as a server error -
it says "deadwax may have finished this - looking again" and reads the library again: the folder gone, it went, and
the sheet closes; still there, "Couldn't delete it." under the button, and what's in it read again. A refusal says
why, as deadwax put it ("That folder is not there any more.").

**Typed work isn't lost by a swipe.** With something typed or chosen and not applied, the sheet can't be swiped away,
and Close asks "Discard changes?" - **Discard**, or **Keep editing**.

**An Apply that waits can take minutes** - up to five on the timer in deadwax's settings, or until Navidrome has
scanned - and the phone waits up to eight. Locked, it keeps waiting only as long as iOS lets an app run in the
background (often under a minute); deadwax carries on either way. If the answer never comes (the phone locked too
long, WireGuard dropped) - or comes as a server error, from deadwax or from a reverse proxy in front of it giving up on
the wait - the sheet says "deadwax may have finished this - looking again", reads the folder again and works What Apply
does out afresh: never the same Apply again on the old answer. Only a refusal (deadwax saying no before it wrote
anything) keeps What Apply does as it was. If the library can't be read then, the sheet says "Couldn't read the
library." with **Look again** - on every page waiting for it, Delete album's too - and nothing can be applied until it
has been read. Only one write runs at a time: while
Release applies or saves a cover, Edit tags' Apply, the Gets and Delete permanently are dimmed, and the other way round
- and after any of them, the others' previews are worked out again once the folder has been read.

**When Navidrome gives the album a new id** - an applied release can - the album page under the sheet becomes the
album's page as Navidrome has it now, on every tab it was open in, and VoiceOver says "The album page now shows the
album as Navidrome has it after the change."

**While deadwax can't be reached**, Edit album says "Managing needs deadwax. This opens once it's back." and asks
nothing, opening by itself once deadwax is back. If deadwax goes out of reach with it open, every page keeps what it
showed under an amber line - "deadwax is out of reach - this is how it was, and nothing here can change until it's
back." - and Apply, the cover and the marks are off; what you typed is kept. Once deadwax is back, the folder and What
Apply does are asked again before Apply comes back on, and a search that didn't work (or the release's tracklist that
never came) is asked for again. Nothing of it is kept on the phone.

**Errors** that deadwax put into words are shown as it said them, as the web app's editor shows them ("The Cover Art
Archive has no front cover for that release."); anything else in the app's own words, what failed added in brackets
for whoever runs deadwax. "This page needs a permission an admin hasn't given you - ask one if you need it." means an
admin took Edit albums (or Look after the library) away since the app last asked: pull down on Settings and it asks
again.

VoiceOver reads each folder and pressing row as one ("Third, Portishead, Portishead/Third (2008)"), a pressing's with
Current and its track count, and the header as a heading. Every word grows with the text size.

## Playlists

**The Library's Playlists page** lists your playlists as Navidrome keeps them - the same ones the web app,
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
(a pull down [shuffles your library](#shuffling-your-library), as on Albums). **Find** (the magnifying glass)
keeps the playlists whose name holds every word you type, in any order, From files opened while it
finds; with none, "No playlists match “…”." If deadwax can't be asked, it says "Couldn't list your
playlists." and why - over the list as it was, or with **Try again** when there's no list to show.
With none at all: "No playlists yet.", how to make one, and **New playlist**. **Tap a playlist** to
open its page. Nothing plays from the list itself.

**New playlist…** is at the end of the Playlists page's line, under the Library's buttons (it was the **+** at
the top, then the Library's •••'s), offered while deadwax can be reached: type its name (up
to 200 letters) and **Create**. It's made in Navidrome, as you, empty, and its page opens - add songs to it
with **Add to a playlist…**. If it can't be made, the sheet stays open and says why. **Create** and **Cancel** sit
side by side - one over the other at the largest text sizes.

**A playlist's page** is laid out as an album's:

- **At the top**: its cover (Navidrome's four-cover mosaic), its name, whose it is ("Yours", "Yours ·
  Shared with everyone", "Sam's · Shared with you", or "From a file in the music folders"), why it
  can't be changed here when it can't ("Only Sam can change this playlist."), its description, and how
  many songs and how long ("12 songs, 48 min").
- **Play** plays it from its first song. **Shuffle** plays it in a random order, with Shuffle on. **Tap
  a song** to play the playlist from it.
- **Pull down** at the top of the page, as on an [album's page](#an-albums-page): let go at the purple disc and the
  playlist plays just as **Shuffle** plays it - offline, only its songs on the phone, or "Nothing on this phone to
  shuffle". It shows nothing while the playlist is loading, couldn't be loaded, has gone or is empty, and while
  **Edit** is open. A pull doesn't refresh the page any more: it's asked for as it shows, as before, and ••• >
  **Refresh** (at the end of the top •••'s menu) asks now.
- **The songs**, each with its artist and album under its title (no cover of its own since the new look); the song
  playing has its title in purple, with moving bars before it. A song that's in the playlist twice is there twice. **Swipe a
  song right** to add it to the queue (see [Adding to the queue](#adding-to-the-queue)). Under the songs: how
  many and how long.
- **•••** at the end of a song's row has **Add to Queue** and **Add to a playlist…** for that song, and
  **Download** (or **Remove Download**, or **Download Again**) for it alone; the **•••** at the top has Add
  to Queue and Add to a playlist… for the whole playlist, and **Download** for the playlist as one (see
  [Downloading a playlist](#downloading-a-playlist)), headed with how far it has got. **Edit** sits before the
  •••, for a playlist you may change.
- When Navidrome counts songs it isn't listing just now: "2 songs in this playlist aren't in the
  library just now - deleted, or being moved."
- A playlist deleted elsewhere says "This playlist isn't on Navidrome any more - deleted in another
  app, maybe." An empty one says "Nothing in this playlist yet. Add songs from a song's or an album's
  ••• menu - Add to a playlist - or from Now Playing's ••• while a song plays." Either one's **•••** at the top
  still has **Remove Download** while a download of it is on the phone.
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
  as in the Queue. With VoiceOver, each song has Move up, Move down and Remove. Edit only takes songs
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

**Download** a playlist with **Download** in the ••• at the top right of its page (on the Mac, the
toolbar's **Download**). Its songs come as an album's do - each the very file deadwax has - and the
whole playlist is planned at once: it waits for room under the storage limit, or for space on the
phone, as one, never half of it. A song of it already on its way - one you were downloading yourself,
say - carries on, and the rest wait together. The playlist itself is kept on the phone, so it opens
and plays with no connection. While its songs come, the page says how far it
has got ("Downloading - 4 of 12 songs"); once they're all here, "This playlist is downloaded - it plays
with no connection." The •••'s Download part says what it's doing, with **Remove Download** - and **Download
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
  many - a list of them that opens with no connection too. In Settings > Downloads, **Downloading** has a
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

**The Artists page** is a page of the Library. With logins on it's **Your artists**: the artists of
the albums in your library, each with how many of your albums are theirs ("2 albums"), as the web app's
Library > Artists has them - and how many songs, once your albums have come ("2 albums · 21 songs"). **All**, at
the Library's top, makes it every artist in the collection, each with how many albums the collection has of theirs
("12 albums · 140 songs in the collection"). With logins off, and
for the break-glass `deadwax` sign-in, the page is **Artists**, the whole collection's.

- **A row** is the artist's round picture (Navidrome's, as the web app shows it), their name and their
  count, with an arrow at its end. **Tap it** to open their page. Nothing plays from the list but the pull.
- **The order** (on the page's line): **Name** (the first time) or **Most albums**. Name sorts by
  deadwax's own spelling of a name - "The" at the start, accents and case set aside - under letter headers,
  with names that don't start with a letter under # at the end. Most albums has no headers. This phone
  remembers the order.
- **Find** (the magnifying glass) keeps the artists whose name holds every word you type, in any order and
  anywhere in a word. The count then says "3 of 120 artists".
- **The index** down the right edge for Name, once a list has 50 artists or more, as the albums' is.

The list is asked for each time the page comes into view, and with ••• > Refresh; until it comes, what was
last listed shows. If deadwax can't be asked, the list stays as it was, under "Couldn't update this list -
showing it as it was." An empty Your artists says "No artists in your library yet.", with **See All
music**. A pull shuffles, as on the other pages.

**An artist's page**: their round picture beside their name, with who they are on MusicBrainz under it ("Group ·
Sydney · since 1973") once deadwax has asked - its place kept, blank until it comes, so Play doesn't move as it lands;
**Play** and **Shuffle** side by side; a strip of **Studio only** and **Everything** (below); and **Albums**, its count
at the heading's end ("16 · 6 yours") - their albums in the
collection, newest first (undated ones last), each on a thin line with its cover, its title, and a line like "1994 ·
in your library" ("in the collection" for the rest; with logins off every one says "in your library"). **Tap an
album** to open its page.

- **Play** plays every album of theirs, in the page's order, each as an album - from the first song of the
  newest. **Shuffle** plays every song of them once, in a random order. With Normalization on, Play levels
  each album as a whole and Shuffle each song on its own, as the web app does.
- As the page opens it fetches every album's songs, four albums at a time, so the music starts the moment
  you tap. Until they're in, the line under the buttons says "Getting the songs of the 3 albums you have…"
  ("in the collection" with a library of your own), and Play and Shuffle are dimmed. Then "Plays the 3
  albums you have". An album that wouldn't come is left out - "Plays 2 of the 3 albums you have - the rest
  didn't load" - with **Try again** under it.
- **Their albums you don't have** come in among yours a moment later, from MusicBrainz, as the web app's
  artist page lists them: newest first, each once, with its cover, its title and a line like "2008 · Live
  album · not in your library", and **Get** at its end - tap it, or the row: the album you don't have's page, as
  from Search. (Get is only for someone who can get albums - with logins on, an admin gives **Get albums**; anyone
  else's row has the arrow, and opens the same page.) One the library holds that Navidrome lists under another artist
  says "in your library", has no Get, and opens your album. **Studio only**, on the strip over the albums (under Play,
  or under Top Songs when they're there), is chosen until you tap **Everything**; then their
  live albums, compilations and the rest join the list. It's kept for each artist, and shared with that
  artist's page in Search. Your own albums don't change: the same rows, ticks and lines, and **Play** and
  **Shuffle** still play only what you have. Under the list: "Loading their albums…" while they come,
  "Showing their first 500 albums." for an artist with more, or - if MusicBrainz couldn't list them -
  "Their other albums can't be shown right now - try again in a few minutes." and **Try again**.
- deadwax finds the artist on MusicBrainz by Navidrome's MusicBrainz id for them, or else by the
  MusicBrainz tags in their albums' folders. For an artist it can't find, or while deadwax can't be
  reached, the page lists only your albums and says nothing about the rest.
- An artist deadwax no longer has says "This artist isn't here any more - their albums may have been moved
  or deleted."
- Not on the phone yet: the description and pins. Their pictures and the names their albums are filed
  under are [managed from the page](#managing-an-artist).

**From Last.fm** (with `LASTFM_API_KEY` set on deadwax - see [configuration](configuration.md) - and **deadwax
2.1.41 or later**): under the name, how many people listen to them on Last.fm ("2.3M listeners"), and **Top Songs**
between Play and Albums - their five most played songs on Last.fm, of all time, with **See All** at the heading's end
for all ten. Under them, **From Last.fm** opens their page on last.fm in the browser, beside the app.

- **A song you have** shows its cover and "{album} · {year}" ("Currents · 2015"), of the earliest of your albums it is
  on - so the studio take, not a later live album's. Tap it: it plays, with the other top songs you have after it in
  the Queue, in Last.fm's order. Its **•••** (on the Mac, a right-click) is a song's, as on an album's page, and a swipe
  right adds it to the queue.
- **A song you don't have** says "Not in your library". Tap it: it spins while MusicBrainz is asked for the song
  (by its title without a "- 2015 Remaster" or a "(feat. …)", as it's matched), then the album you don't have opens,
  the song marked in its tracklist. If none is found the row says "Couldn't find its album on MusicBrainz." - and
  "MusicBrainz isn't answering - try again in a few minutes." while MusicBrainz is away - until you leave the page.
- **A song that may be on an album whose songs didn't load** (the line under Play says "the rest didn't load") is
  never called "Not in your library": it's dimmed, with no line under its title, and does nothing until Try again
  brings that album's songs.
- Last.fm's "Let It Happen - 2015 Remaster" and "Lost in Yesterday (feat. X)" are your "Let It Happen" and "Lost in
  Yesterday"; a remix, an edit, a demo or a live take Last.fm names as one is a song of its own.
- Until the songs of your albums are in, the rows show their titles and do nothing. The first time an artist is
  opened, what's below Play waits a moment (0.8 s at most) for Last.fm, so nothing jumps; an answer later than that
  puts Top Songs under the albums instead, for as long as the page is open. Last.fm's answer is kept while the app
  runs, so an artist opened again draws it at once (one deadwax could only partly get, or not at all, is asked for
  again when the artist is opened a minute or more later). Pulling the page down asks Last.fm again. Once the
  listeners line has its place under the name it keeps it, blank if need be, for as long as the page is open - if
  deadwax then says Last.fm is off, or can't be reached - so Play never moves.
- An artist Last.fm doesn't know has no Top Songs and no listeners line - nothing empty.
- With no key on deadwax, or a key Last.fm refuses, the page has none of it. Whoever runs deadwax sees a line at the
  page's foot saying so - "Top songs, similar artists and radio come from Last.fm - add a Last.fm API key in Server
  settings to see them." or "Last.fm refused deadwax's API key - check LASTFM_API_KEY in Server settings. It's the API
  key, not the shared secret." - with **Server settings**, which opens its Connections, where `LASTFM_API_KEY` is.
  Nobody else sees a line.
- **Offline**, an artist whose Last.fm answer the app has from this time it's been open keeps their Top Songs, a song
  not on this phone dimmed (it plays nothing, and one you don't have opens nothing). A song that may be on one of
  their albums the phone hasn't the songs of (one not downloaded, on a page opened since deadwax went away) is
  dimmed with no line under it, never "Not in your library". Any other artist has nothing of Last.fm's, and no gap.

**Offline**, the Artists page lists what it last listed, an artist with nothing on this phone dimmed (it
opens nothing). With no list in hand it lists the artists of the albums on the phone, under "Only the
artists of downloaded albums show until deadwax is back." - each named as most of their albums here name
them, so an album they made with someone else ("Portishead & Tricky") doesn't rename them. An artist's page that's one of the last 20 you
opened since the app started shows their albums as it last had them - any other, the ones on the phone -
with the albums not on the phone dimmed, and Play and Shuffle playing only the songs here ("Only
downloaded albums play until deadwax is back.").

### Managing an artist

For someone who can **Edit albums** or **Look after the library** (everyone while logins are off; with
them on, Navidrome's admins and whoever an admin gave those), an artist's page offers what the web app's
artist page offers them - only while deadwax can be reached, and only what that person may do. On the phone
**Artist images…** and **Move albums…** are on the strip over the albums, after Studio only and Everything, and
**Which artist is this?** is in the **•••** at the top right; on the Mac all three are at the end of the page's
toolbar (in its **•••** in a narrow window):

- **Artist images…** (Edit albums), once the library files albums under their name. It's dimmed for a
  moment as the page opens, while deadwax says which folder is theirs.
- **Which artist is this?** (Edit albums), while nothing says who they are on MusicBrainz - neither
  Navidrome nor their albums' MusicBrainz tags - and after you've chosen, to choose again.
- **Move albums to Ye…** (Look after the library), when the library files some of their albums under a
  name that isn't the one MusicBrainz has for them now ("Kanye West", with MusicBrainz calling them Ye).

They act on the names the library's folders go by, as the web app's do, which may not be the name the
page shows. Each opens a sheet, and each needs deadwax: opened while it can't be reached, a sheet says
"Managing needs deadwax. This opens once it's back." and starts by itself once it is; if deadwax goes
away while one is open, what it shows stays under "deadwax is out of reach - this is how it was, and
nothing here can change until it's back.", with Save or Move dimmed until it's back and has been asked
again.

**Artist images** looks for pictures ("Looking for pictures of Ye…"), then says whose they are -
"Showing Ye (rapper)" - with **Not them?**, which searches MusicBrainz for another artist ("as Kanye
West" beside one an old name of theirs matched); tap one for their pictures instead. When MusicBrainz
can't say who they are, the search is open from the start, under what went wrong. Next come the
sources it couldn't ask - with no fanart.tv or TheAudioDB key in deadwax's [Server settings](#server-settings) (under
Connections), "Banners, logos and backgrounds come from fanart.tv and TheAudioDB, and both need a
key…" - and then a section for each slot: **Square image**, **Banner**, **Background**, **Logo**,
**Wide image** and **Clear art**, each with the file already in their folder ("artist.jpg on disk") or
"none found for this" beside its name.

- The best picture of each slot is chosen to start with, and shown large with its name and its source,
  as the web app names them ("fanart.tv Thumb (3) · fanarttv", the 3 its likes on fanart.tv); a slot
  with nothing chosen shows what's in their folder ("Banner on disk").
- **Use another picture (7)** - the 7 counting the pictures found for the other slots, as the web app
  counts them - opens every picture the slot can take, its own first, then the rest, so a photo can be
  the background, as a grid. Tap one to choose it; tap the chosen one again to leave that slot alone, so
  it isn't written. A slot with pictures of its own but none of another kind shows **Pictures for this
  slot (2)** instead.
- If deadwax goes away and comes back, or you look again, your choices are kept - except one it no
  longer finds, which is dropped and said ("The picture you chose for the banner isn't offered any
  more, so it won't be saved - choose another.").
- **Replace pictures that are already there** (off to start) says whether a slot with a file in it is
  written over. **In their folder now** shows the pictures already there, with their file names.
- **Save** writes the chosen pictures into their folder, then says what it wrote ("Saved artist.jpg,
  banner.jpg."), or why nothing needed writing. Saving a square image makes it the page's picture.
- Every picture is passed on by deadwax (2.1.32 or later), which fetches it from Wikimedia Commons,
  TheAudioDB or fanart.tv: the phone never asks those sites itself. A picture deadwax couldn't get is
  shown as its name and where it's from, with "deadwax couldn't get that picture just now." - never as
  a blank. Pictures load as they scroll into view, a few at a time.
- When their albums aren't in one folder the sheet says why, and nothing more: "Their albums are filed
  under 2 names - move them under Ye first, so their pictures have one folder", or that they have no
  folder of their own.

**Which artist is this?** says what choosing does, then searches MusicBrainz for the page's name, and
lists every artist going by it, each with what tells them apart ("as Kanye West · rapper · Person").
Search again with other words if they aren't there. Tap one: the sheet closes and the page is theirs
for this visit - their albums you don't have, and their pictures in Artist images - saying "You chose
who this is, for this visit." under their name. Nothing is written; applying an album's release in
[Edit album](#edit-album) writes who it's by into its files, for good.

**Move albums to Ye** works out the moves for every name that isn't theirs now ("Working out the
moves…"), then says what happens - "Each album moves into **Ye/** keeping its own folder name, and its
album artist tag becomes Ye…" - and lists **Albums that move**, each with its folder, where it goes
("→ Ye/Donda (2021)") and how many tracks and how many are retagged ("12 tracks, 12 retagged"), and
**Albums that stay**, each with why (a collaboration, a folder of that name already there, a track
deadwax can't read). **Move 2 albums** moves them ("Moving…"), then says what happened - "Moved 2
albums into Ye/. Their pictures came too: artist.jpg. Kanye West/ was left empty and removed." - with
anything that didn't move in amber, and **Done**. The page asks deadwax and Navidrome again at once, and
again once Navidrome has had time to scan. The page of an old name every album of which moved then
says the artist isn't here any more (the web app's page follows them to their new name; the phone's
doesn't yet) - open them from the Artists page.

While Save or Move runs, the sheet can't be closed. If the phone locks or loses deadwax before the
answer comes, the sheet says "deadwax may have finished this - looking again", with what it knows
moved, and looks again before offering Save or Move once more - it never sends the same thing twice
unseen. For a move, looking again works out how far it got: "deadwax had finished: 2 albums from Kanye
West moved into Ye/." (then **Done**), or "deadwax had moved 1 of the 2 albums under Kanye West - the
rest are below, to move again." with **Move** offered for the rest. Move needs to know how big each
name's albums are, to know how long to wait: if deadwax can't say just then, nothing moves and the
sheet says "Couldn't read their folders just now, so nothing was moved - try again." If someone else
signs in on the phone while albums are moving, the rest aren't moved ("Stopped before the rest -
someone else signed in."). With a picture chosen or taken back, or Replace changed, and not saved, a swipe doesn't close
Artist images, and Close asks first.

## Songs

**Songs** is every song in the collection, as the web app's Library > Songs has it: in Navidrome's order,
100 at a time, the next 100 fetched as you scroll near the end of them. With logins off, and for the
break-glass `deadwax` sign-in, it's the Library's fourth page. With logins on, Navidrome can't list the songs
of your library alone, so they're the collection's: a page of **All**, beside its Albums and Artists, rather than
a page among your own albums and artists.

- **A row** is the song's cover, its title, and its artist and album ("Portishead · Dummy"). **Tap it** to
  open its album's page, and play it from there - nothing plays from the list but the pull and Shuffle. Its
  **•••** is the song's own menu, as on an album's page: Add to Queue, Add to a playlist…, and Download. **Swipe
  it right** to add it to the queue (see [Adding to the queue](#adding-to-the-queue)) - on the Library's Songs
  page too, where a swipe right that starts on a song adds it rather than turning back a page: start it at the
  very left edge of the screen (or tap the page's button) to go to the page before. A swipe left still turns the page.
  The swipe needs iOS 18; on iOS 17 the ••• adds.
- **Find** (the magnifying glass, or All songs' own field), asks Navidrome for the songs that match what you type -
  by title, artist or album, as Navidrome's own search matches them - a moment after you stop typing. The
  songs come 100 at a time, so the phone can't look through the ones it hasn't fetched; Find here is
  Navidrome's search, not the other pages' filter. Nothing found says "No songs match “…”."
- **The count**, "12480 songs" on the page's line (at the top of All songs), shows once every song has been
  fetched, as the web app's does.
- **All songs' Shuffle**, at its top: every song of the collection once, in an order deadwax makes, played
  as the Library's Shuffle plays your library (see [Shuffling your library](#shuffling-your-library)) -
  its first songs fetched as All songs opens, so it plays the moment you tap. Until then it reads "Getting
  ready…", dimmed; if deadwax couldn't get them ready, it stays dimmed with why under it ("Couldn't get your
  songs ready to shuffle"), and tries again the next time All songs opens. The Library's own Shuffle still
  shuffles only your library. On the Songs page (logins off) the ••• Shuffle and the pull shuffle the
  collection, as on the other pages.
- The songs are fetched the first time Songs opens, and kept while the app runs, with your place in them.
  ••• > Refresh (the Songs page) or a pull (All songs) fetches them again from the top. If the next 100
  can't be fetched, the songs so far stay, with why and **Try again** under them; if a refresh can't be,
  "Couldn't update this list - showing it as it was." With no songs at all: "No songs yet."
- **Offline**, the songs already fetched stay, the ones not on this phone dimmed (they open nothing), and no
  more are fetched until deadwax is back - then the next 100 come, if you had got near the end. With none
  fetched yet: "Songs show here once deadwax is back."

## Search

**Search** is the tab between Library and Requests. Its field is always there at the top - tap it to type -
with "Search your library and albums you don't have yet." under it while it's empty ("Search your
library, the collection, and albums nobody has yet." with a library of your own). It searches what
deadwax has, as the web app's Search does, and the artists, albums and songs you don't have yet from
MusicBrainz - and an album you don't have is got from its page (see [Getting an album](#getting-an-album)).

A fifth of a second after you stop typing - or at once when you press **Search** on the keyboard - it
asks Navidrome, and shows **one list**, the web app's:

- **Top results**: the three best matches of any kind, as the web app picks them - the album or artist
  your words name first ("dummy portishead" and "portishead dummy" both lead with Dummy), then what fits
  best, an album you don't have among them when it fits best.
- Then **Artists** (the first 2), **Albums** and **Songs** (3 each), each with **See all**. With a library
  of your own, the rows of your library come first in each, and each row says whose it is: "in your
  library", or "in the collection" for one of an album you haven't added.
- **Albums you don't have** come after yours in Albums: up to 3 of them, each with its cover, its kind
  when it isn't a plain album ("EP", "Live", "Compilation"), its artist and year ("Portishead · 2008").
  They're asked for once you've stopped typing for longer (seven tenths of a second, three letters or more)
  or pressed Search. An album a folder of yours may already be - its name matches, but it has no
  MusicBrainz ids - says "maybe in your library". The albums you already have aren't listed again.
- **Artists you don't have** come after yours in Artists, each with what tells them apart ("Bristol trip
  hop group · Group · GB", and "as Kanye West" for one found by a name they also go by). An artist of yours
  MusicBrainz finds is drawn once, as yours - never twice.
  Words read as an album by an artist you have ("dummy portishead") ask for no other artists.
- **Songs you don't have** come after yours in Songs, each take of a song by one artist as one row, its
  line naming the album it's on ("Massive Attack · Mezzanine"). A song you have isn't listed again. Words
  that are an artist's name alone find no songs you don't have: the Songs chip then says "Type a song's
  title with the artist (“roads portishead”) to find songs you don't have yet."
- Words that name an artist you have, alone ("portishead"), find **their studio albums and EPs**, with
  "Studio albums and EPs - See all for everything they made." under them; **See all** finds everything.
- Under three letters, "Type a little more, or press Search, to find albums you don't have yet." - press
  Search to ask anyway.
- **The chips** under the field - **All**, **Artists**, **Albums**, **Songs** - show one kind in full: up
  to 50 artists or albums, or 100 songs, with **More from your library** ("More from the collection")
  when there are more. **Albums** lists the albums you don't have after yours. **All** puts the list
  back as it was.

**The list is drawn once for the words, and nothing moves under your finger.** Your library answers in a
fraction of a second and MusicBrainz in a second or more, so the list comes in steps, as the web app's
does: Top results first (with a place kept for a pick still to come), "Searching…" where the sections will
go, then the sections once the albums are in - or a second and a half on, with "Searching…" in Albums'
place, the albums landing there when they come (or, if something you could tap is already under them,
behind **Show 2 more albums**). If your library is slow, the list is drawn without it after a second and a
half, "Searching your library…" at its top, then **Show 5 from your library** to draw it in. Each of those
places is one line of one height whatever it holds - "Searching…", a Show button, why there's nothing, or
what went wrong with **Try again** at its end - so nothing below it moves when it changes, at any text size.
Typing on keeps the list where it is until the new words' list is in. Clearing the field brings the hint
back.

**What's saved.** deadwax keeps every answer MusicBrainz has given it, for anyone's search, and searches them
too. For words MusicBrainz is asked for (three letters or more, or Search pressed), what it has saved of the
artists, albums and songs you don't have is drawn with your library, at its moment, before MusicBrainz has
answered - so an album found before can lead Top results at once. The list waits at most four tenths of a
second for it; slower than that, it's left out for those words, and MusicBrainz's answer comes as it would
without it. Until deadwax knows which albums your library holds (the first look after the deadwax container
starts can take a while on a sleeping disk), saved albums wait - saved artists and songs don't - and
MusicBrainz's albums come as ever. MusicBrainz's answer adds only what isn't there already, and nothing drawn moves; VoiceOver says "Found earlier: 1 album." as
the list is drawn, then "More found: 2 albums." (or "Nothing more found."). If MusicBrainz can't be asked, what's
saved stays, and where MusicBrainz's rows would be: "Showing earlier results - searching for more isn't working
right now." (or "…try again in a moment for more."), with **Try again**.

**Words searched before.** The phone keeps the last 24 answers MusicBrainz gave it, each for an hour from when it
came (as long as deadwax keeps one in memory), and words searched again - typed again, gone back to, or a chip
chosen - are drawn from them whole as your library answers, nothing asked of MusicBrainz. After the hour the words
are asked again. They're kept for whoever signs in next, as MusicBrainz's data is nobody's.

**More from MusicBrainz.** A chip's view - Artists, Albums or Songs - ends, once MusicBrainz has answered and
has more, with **More artists**, **More albums** or **More songs**: the next page of the same search, added below
the rows already there, nothing above them moving. It says "Loading…" while it asks, and "Try again" if it
couldn't, with why above it. Each chip's More is its own: asking More songs leaves More albums asking. Typing new
words lets any More still asking go - its page never lands under them. A page that brings nothing new says so - "The next 3 albums found are all in your
library already." ("…in the collection already." with a library of your own), "No new songs - 2 more albums
for the songs above.", or "No more results." - and VoiceOver says what came ("11 more albums found"). A thousand
results in, it stops: "That's all for this search - add a word to narrow it." In a chip's view what's saved leads
MusicBrainz's rows, and rows that come after something was drawn go below it. New words let a More still asking
go.

- **A song**: tap it to play it, with its album's songs after it in the Queue. The phone fetches the albums
  of the first songs found as the list comes in, so a song with **▶** after it plays the moment you tap.
  One without (its album not fetched yet) opens its album's page instead. Its **•••** is the song's own
  menu: Add to Queue, Add to a playlist… and Download. **Swipe it right** to add it to the queue (see [Adding
  to the queue](#adding-to-the-queue)) - on iOS 18 and later; on iOS 17 the ••• adds. A song you don't have
  (MusicBrainz's) has no ••• and no swipe.
- **An album** opens its page; **an artist**, theirs. Back takes you to the list as you left it.
- **An album you don't have** opens its page: its cover, its title and artist, "2008 · Album · not in your
  library", then **Pressing** - tap it for every pressing MusicBrainz knows, the usual one ticked, each
  with its format, year, country and label, how it compares with the usual tracklist ("+1 bonus track: …"), and
  "In your library" for one you have; an album of more than 30 pressings has a filter ("JP, CD, a label or
  catalogue no."). Under it the chosen pressing's facts (its catalogue number and barcode), then its
  **tracklist**: what it is against the usual one ("The usual tracklist, shared by 9 of 10 pressings", or
  "This pressing adds 3 tracks"), each track marked where it differs (**Bonus**, **Other version**,
  **Renamed**), and **Not on this pressing** for what it leaves out. The artist is a link when one artist of
  your library is theirs. **Get the album**, under the pressing's facts, gets the pressing chosen - see
  [Getting an album](#getting-an-album).
- **A song you don't have** opens under itself the albums it's on, the studio album first, each with its
  kind and year ("Live album · Bootleg · 2008") and "in your library" for one you have it on; compilations,
  live albums and soundtracks are folded behind **On 4 compilations and live albums** - tap it to show them.
  Tap an album: its page opens with a pressing that has the song chosen, the song's track tinted, and
  brought into view if it's further down (only if you haven't scrolled the page yourself). One of yours
  opens your album's page. In Top results a song you don't have opens the album its line names.
- **An artist you don't have** opens their page: their name, who they are ("Group · Bristol · since
  1991"), and **Albums** - their albums from MusicBrainz, newest first, each with its cover and "1994 · in
  your library · 2 pressings" or "2008 · Live album · not in your library", the one you have ticked.
  **Studio only** (on until you turn it off, kept for each artist) leaves out live albums, compilations and
  the like; off, it lists everything. Tap an album: the album you don't have's page, or yours. An artist with
  over 500 says "Showing their first 500 albums."; if MusicBrainz couldn't list them, "Their other albums
  can't be shown right now - try again in a few minutes." and **Try again**. Their description and links
  come later. On an album you don't have's page the artist is a link to theirs when they aren't in your
  library.
- **An album of yours MusicBrainz finds** that Navidrome's search didn't list is drawn among yours, "in
  your library", and opens your album's page. Finding that page can take a moment (the row shows it's
  working); open something else, or go to another tab, meanwhile and it doesn't open over what you went to.
- Nothing found says "No results for “…”." and "Check the spelling or try a new search." (a chip's:
  "No albums for “…”."). If Navidrome couldn't be asked, why, and **Try again**. If MusicBrainz couldn't be,
  "Searching for more isn't working right now - try again in a few minutes." (or "Too many searches just now -
  try again in a moment.") and **Try again**, your library's rows still there. If deadwax can't reach
  Navidrome at all, the Library's words for it ("Can't reach Navidrome", or "Your music isn't available right
  now") stand above the list, with Try again once Navidrome is set up; albums you don't have are still found.
- **Covers** of albums you don't have come from the Cover Art Archive, through deadwax: they need deadwax
  2.1.24 or later (`:experimental` for now), and show as an empty square on an older one - see
  [the troubleshooting page](troubleshooting.md#the-iphone-app-shows-no-cover-for-an-album-you-dont-have).
  A cover that couldn't load while deadwax was out of reach loads as soon as it's back.
- **Offline**, a list already drawn for the words stays, without the albums you don't have, the songs not
  on this phone dimmed (a tap does nothing) and the ones on it playing; albums and artists with nothing here
  dimmed. New words say "Search works once deadwax is back." - never an empty list - and are searched once
  it is, your library's rows in the list with the rest. The artists, albums and songs you don't have - what's
  saved of them, and More, with them - leave the list while deadwax is away and come back with it; nothing is
  asked of MusicBrainz meanwhile, nor taken from the answers kept. An album you
  don't have's page keeps what it has shown; one that hasn't loaded its pressings says "This album's
  pressings load once deadwax is back." and loads them when it is. An artist you don't have's page says
  "Their albums show once deadwax is back." where their albums go, and lists them once it is.
- **VoiceOver** reads a row as one: its title, its line, and for a song "plays it from its album" or "opens
  its album" - for a song you don't have, "Shows the albums it's on." (or "Hides…" once open). The list is
  announced as it comes in ("In your library: 1 artist, 2 albums, 11 songs.", then "Also found: 2 artists, 3
  albums, 4 songs."), and a chip as it's chosen ("Showing albums."). A chip's view says what it drew as it
  comes in: "In your library: 2 albums.", then "Found earlier: 1 album. More found: 3 albums." (each once for
  the words). On an album opened from a song, its track reads "…, the song you searched for".

## Getting an album

On an album you don't have's page (see [Search](#search)), once its pressings are in, **Get the album** stands under
the chosen pressing's facts: the page's one big button, for the pressing chosen above it. To get another pressing,
choose it first. Without **Get albums** (with logins on, an admin gives it) there's no button, and in its place
"Getting albums is off for you - ask an admin."

For an album MusicBrainz doesn't have, or one you'd rather find by name, **Search Soulseek…** at the top of
[Requests](#requests) searches by the artist and album you type, and opens the same Choose a source page.

**The line under it** says what deadwax already has of that pressing before you tap anything, in the web app's
words (see [Downloading](downloading.md#when-you-already-have-it)). deadwax looks without searching Soulseek: as the
pressing is chosen, as a download is filed, and each time the page comes back into view - from another tab, from the
background, or as the sheet below closes - so a Get or a cancel in Requests shows on it when you come back. While it
looks again, the line keeps what it said until the new answer comes, and another pressing's answer never stands for
the one chosen.

- **"Already in your library"**, its folder, and "10 of 10 tracks · FLAC".
- **"Already downloading"**: "From mellotron · 3 of 11 files", and "To get it from another source, cancel it in
  Requests first." - or **"Already downloaded"** while it's being added to your library.
- With logins on, **"Already downloading for someone else"**: who from, the copy ("FLAC 16/44.1") and how far it's
  got - and a line when that copy may be below your quality floor. **"In the collection, not in your library"** for
  a pressing someone else has.
- Notes under it: part of the pressing already here, and what a download would do about that ("Getting it adds only
  the tracks that folder doesn't have yet."); a download of part of it running; another pressing you have.

When deadwax has none of it, there's no line.

**Join this download**, under "Already downloading for someone else" (with Get albums): one download, everyone who
asked waiting for it, rather than a second copy fetched. Tap it: "Joining…", then "Joined - it's in your Requests.",
and the line asks deadwax again and says it's yours ("Already downloading"); the download is in your Requests. If it
has finished, stopped or been cleared since the line was drawn, deadwax says so under the button ("That download
has been cleared from the list since - get it again.") and the button stays, to try again. Without Get albums
there's no Join, and the line says nothing of joining. A join can wait for another Get of the same album to reach
its source, so the phone waits up to a minute; if no answer comes, the join may still have gone through, so the
line asks deadwax again, and Requests looks again. If you're on it, the line says so; if not, "deadwax didn't
answer in time, so you may have joined it anyway. If it isn't in your Requests soon, join it again." Joining twice
does no harm.

**Add to my library**, under "In the collection, not in your library" (with logins on): the pressing someone else
has, put in your library rather than downloaded again. Tap it: "Adding…", then "Added to your library.", and the
line asks deadwax again: "Already in your library". Your albums in the Library show it the next time you look, and
Search marks it as yours. A refusal is said under the button, as for Join. deadwax puts it in your library, then
stars it in Navidrome for you before it answers, which takes longer while Navidrome is slow; the phone waits up to
a minute. If no answer comes, the line asks again, and if it isn't yours yet: "deadwax didn't answer in time, so it
may have been added anyway. If it isn't in your library soon, add it again." Adding twice does no harm.

**Choose a source.** Tap Get the album and a sheet opens, **Choose a source**, the album and pressing under its title
("Dummy · CD · 1994 · GB · Go! Beat"). deadwax searches Soulseek for that pressing - "Looking for “Dummy” by
Portishead…" and "This takes a few seconds." while it does - and each folder found is a card, as in the web app's
sheet (see [Downloading](downloading.md#choosing-a-source)):

- **The score** ("92%" - green from 75, amber under it), the folder's name and who it's from, and **Get**. The best
  match through the chips is edged in purple and has the one solid Get, wherever the sort puts it.
- **Speed** first, with its bar: what you got from that person before ("what you got from them"), their usual speed,
  or "no speed reported yet". Then **Tracks** ("11 of 11", amber with some missing), **Quality** ("FLAC 16/44.1",
  "MP3 VBR 245k"), **Size** and **Starts** ("now", "after 3 others"), and in amber what's missing ('Missing “Roads”
  and 2 more').
- **Tap the score** for **Why it's a 92% match**: the edition words in the folder's name (DELUXE, REMASTER…), then
  the score's six parts, each with its percentage and what it measures - **Track names**, **Track count**, **Track
  lengths**, **Edition**, **Format** and **Availability**. Tap the score again to fold it away.
- **The chips** - **Lossless**, **24-bit**, **Starts now** and **Complete albums only** (and **320 kbps** with that
  quality floor) - narrow the list, and **the sort** orders it: **Best match**, **Highest quality**, **Largest first**
  or **Smallest first**. The chips start as your **quality floor**, the sort at Best match, and the search is scored
  by your **Format**, both chosen in [Settings](#settings) > Getting albums (or the web app's Settings) and kept for
  you on deadwax.
- **Search again** - at the right of "Choose a source" at the top, and under the cards - opens the words searched in
  a field: the top one's above the chips, the other's just under it. Change them and tap **Search**. Changed words
  are searched exactly as typed; unchanged, it searches as Get did. At larger text sizes the top one is a magnifying
  glass, so the title isn't cut short.

Under the cards, what was searched: 'Searched for “Portishead Dummy” · 41 sources, 4 match your filters'. Otherwise:

- **Nothing found**: 'Nothing found for “Portishead Dummy”.', the words there to change, with Search.
- With your Format **Lossless only** and no lossless copy found: 'Nothing lossless found for “Portishead Dummy”.'
  and why - your Format leaves the rest out, and "You can change it in Settings, under Getting albums."
- **None through the chips**: "41 sources found - none match your filters." and **Clear filters**.
- **Already in your library**, or **already downloading**: the line from the page, in the cards' place. deadwax
  searched nothing.
- **Soulseek couldn't be searched**: why - slskd's own sentence where it gave one ("slskd is not connected to the
  Soulseek network, so it cannot search"), otherwise "Downloads aren't working right now." - with **Try again**.

**Pick the best source for me** (Settings > Getting albums' When I tap Get): Get the album opens the sheet and searches
as ever, and as the answer comes, the best match through the chips as they are then (your quality floor's, unless
you've tapped one) at 75% or more is got for you, as a card's Get would be: the sheet closes onto Requests, the
download there. Never for a pressing you have or that's on its way, nor one deadwax can't judge (a pressing
MusicBrainz lists no tracks for: there's nothing to check the sources against). When nothing qualifies, the sources
show, with why above them: "No close match that passes your filters - choose a source yourself.", or "You already
have part of it - choose a source yourself." (VoiceOver says it with the outcome). **Try again** picks too;
**Search** never does. If deadwax goes out of reach just as the sources come in, nothing is got for you: the
sources show, with "deadwax went out of reach as the sources came in - choose a source yourself once it's back.",
and nothing is picked later by itself.

**In the sheet**, the line's **Join this download** joins and closes the sheet onto Requests, as a Get does. **Add
to my library** adds the pressing, and the box says "Already in your library" with "Added to your library." under
it. If deadwax doesn't answer either in time, the sheet asks deadwax whether it went through: a join that did
closes the sheet onto Requests, and an add that did says it's in your library, as if the answer had come.

**A card's Get** closes the sheet and shows Requests, the download already there from your tap, under Waiting,
"starting…", until deadwax and slskd take it. If deadwax refuses it (someone got it meanwhile, say), it moves to
Needs attention, "didn't start", with why ("It's already downloading.", "It's already in your library."). The Get
also hands deadwax the next sources in the list as you had it, for **Another source** if this one fails. **Cancel**,
or the sheet swiped down, stops the search, in slskd too, as soon as you let go of the swipe: a pick whose sources
come in while the sheet slides away isn't got. A swipe pulled back leaves the search running. Get the album again
searches afresh.

deadwax waits as long as it takes for the person sharing the album to be reached, and the phone waits up to five
minutes for its answer. If none comes, the row isn't marked as failed - the download may well have started. It
stays "starting…" while Requests looks for it, and is replaced by the download as soon as it shows. Only after ten
minutes with nothing found does it move to Needs attention, "no answer", with "deadwax didn't answer in time, so
this may have started anyway. If it doesn't appear here soon, get it again." **Clear done** takes it away.

**Offline**, there's no Get the album, and "Getting albums works once deadwax is back." stands in the line's place
(with Get albums). In a sheet already open, the same words stand at its top (VoiceOver says them as it happens).
What it found stays, dimmed, and its **Get**, **Join this download**, **Add to my library**, **Try again** and
**Search** are off until deadwax is back - a Get then would close onto a Requests that can't show it. Once deadwax is
back they're on again, and Search again is at the top and under the cards if you want a fresh search. A search still under way when
deadwax went out of reach carries on waiting for its answer. If the phone gives up on it first, the sheet says why,
then runs the same search again by itself once deadwax is back: after a Search with your own words, those words
again with the chips as you left them, and never picking a source for you.

**VoiceOver** reads the line as one, and says what it now says as it changes. The sheet says each outcome as it lands
("Looking for “Dummy” by Portishead…", then "12 sources."). The score reads "92% match", collapsed or expanded, and a
card's Get names its folder and who it's from ("Get Dummy [FLAC] from mellotron"), as one person often shares the
same album twice. At the largest text sizes a card's facts go two by two, then one over another, each on up to three
lines rather than cut short.

## Requests

The **Requests** tab, between Search and Settings, lists every download you asked for - on this phone (see [Getting an
album](#getting-an-album)), in the web app, or on another phone - under the web app's four headings, in the web
app's words. A heading shows only when it has something under it. Each download is a card with no grey face - its
cover, its words and its meter on the page, a thin line under it - and its ✕, and a Done row's ▶, are bare purple
glyphs.

**Search Soulseek…**, the first row - above the headings, and there with nothing requested yet - gets an album by
its name rather than by MusicBrainz's pressing: one MusicBrainz doesn't have, or one you'd rather find by name. It's
there only with **Get albums** (with logins on, an admin gives it), and dimmed while deadwax can't be reached. Tap
it: **Search Soulseek**, with **Artist** (the cursor in it) and **Album**. Return in Artist goes to Album, and Return
in Album searches, as **Search** under them does once both have words. Offline, the form says "Getting albums works
once deadwax is back." and Search is off.

Search opens **Choose a source** - the page an album's Get the album opens (see [Getting an
album](#getting-an-album)) - for "Your own search · filed by its own tags": "Looking for “OK Computer” by
Radiohead…", then the folders people share, ranked first by how closely each folder's name is the artist and album
you typed, then by format and availability. A card's score shows **Folder name** first and no track parts - there's
no tracklist to check against, so its tracks read "12 files". There's no **Complete albums only**, and **Pick the
best source for me** picks nothing here: you choose. **Search again** works as it does there; **Back** returns to
your two fields as you left them. **Get** on a card closes it all, and the download is in Requests at once as "OK
Computer · manual search". It's filed by the files' own tags, never into a pressing you've matched (see
[Organizing](organizing.md#filed-by-its-own-tags)), and its Done row says so: "Filed by its own tags. Edit album >
Release can match it to a pressing." - or, without **Edit albums**, "Filed by its own tags, not matched to a
pressing." Once it's filed, the row is titled as the tags name the album - "OK Computer OKNOTOK 1997 2017 · manual
search", say, whatever you typed - and, as any Done row, a tap opens the album and ▶ plays it from its first song
(with **deadwax 2.1.40 or later**; before that, find it in the Library). **It needs deadwax 2.1.38 or later**: on an
older server the cards' Gets are off and the page says "This needs a newer deadwax - ask whoever runs it." (whoever
runs deadwax reads "This needs deadwax 2.1.38 or later on the server."). On the Mac, Tab and Shift-Tab move between
the two fields, and Escape closes the form while both are empty.

- **Downloading**: the pressing's cover, the album and its edition ("Mezzanine · 1998 CD"), the artist and who
  it's coming from ("Massive Attack · from mellotron", with "2nd try" once it's on another source), the bar, and
  "6 of 10 files · 1.8 MB/s" - the speed measured on the phone over the last second or more, never slskd's
  average since the start. While it's being filed: "adding to your library…".
- **Waiting**: its place in the peer's queue ("4th in their queue"), or "starting" - in amber with "2 failed" when
  the peer has already refused some of its files.
- **Needs attention**: why it stopped, in red ("Tell whoever runs deadwax." after it where only they can put it
  right; whoever runs deadwax reads the error's own words, folded under it, instead), and the two ways on:
  **Another source · 2 left** (solid on the first such card only) and **Same source again**. While one runs
  both wait, the one you tapped saying "Trying another source…" or "Trying again…"; if it couldn't start, why, in
  red under the reason ("No other source would send it."). Without **Get albums** (with logins on, an admin
  gives it) neither is there, and the card says "Getting albums is off for you - ask an admin."
- **Done**: how it ended and how long ago ("In your library · 12 minutes ago", "You already had it", or in amber
  "In your library - 2 files couldn't be added"). A download whose album is in your library opens the album's page
  when you tap it, on the Requests tab; one this download filed has **▶**, which plays the album from its first
  song. The first five Done albums are looked for ahead - Navidrome given 10 seconds to scan what was just filed -
  so ▶ plays the moment you tap it; one not found yet opens its page instead. An album that can't be opened says
  why under its row: "Not ready to play yet - it may still be scanning.", "Can't find this album to open it - it
  may have moved, or isn't matched to a pressing.", or the music server's own trouble ("Can't open this album
  right now - the music server can't be reached. Try again in a minute."). Open something else, or go to another
  tab, while it looks, and it doesn't open over what you went to.

With logins on, a row says who else is waiting for it: "Someone else asked for it too" - and, for an admin, who
("Asked by you and ethan", or "Nobody is waiting for this any more").

**The ✕** on a downloading or waiting card cancels it. With **Confirm before cancelling** on (Settings > Getting
albums - on unless you turn it off, and kept on this phone, not your account) it asks first, in the card: "Cancel
this download? You'll lose your place in their queue." with **Keep it** and **Cancel download**. A second tap on
the ✕ closes the question, and one card asks at a time. With logins on, a download someone else is waiting for
too asks "Leave this download? Someone else asked for it too, so it carries on for them." with **Leave it**: only
your request goes, and its ✕ reads "Leave …" to VoiceOver. An admin cancelling one that ethan asked for as well is
asked "Cancel this download for everyone? ethan asked for it too." with **Cancel for everyone**. The card dims at once,
"cancelling…", until deadwax agrees. Nothing can be cancelled once it's being filed.

**Clear done**, at the top, takes every finished, failed and cancelled download off your list at once (with logins
off, deadwax forgets them). It's dimmed with nothing to clear.

**The badge** on the tab counts what's on its way - downloading, waiting, and anything being tried again - with
none at 0, as the web app's does. VoiceOver reads the tab as "Requests, 2 arriving".

**How often it asks.** Twice a second while Requests is what you're looking at (not a page opened from it, and not
with Now Playing over it); otherwise once a second while an album is being filed, every 5 seconds while anything is
on its way, and not at all when nothing is - nor with the app in the background, music playing or not, nor while
deadwax can't be reached. Coming back to the app, or deadwax coming back, asks once at once. An album filed
meanwhile shows as yours in Search at once.

**When it can't ask.** If deadwax answers with an error: "Can't update your requests right now", what went wrong,
and "It keeps asking while this tab is open; what's below is from the last answer." If deadwax can't keep track of
downloads (its database can't be written): "Downloads aren't being kept track of" - whoever runs deadwax reads
"… Check DB_PATH." Until deadwax first answers, a spinner - never "Nothing requested yet". **Offline**: "Requests
show once deadwax is back." - nothing of the last answer shown as if it were current, no badge, Clear done dimmed.
Once deadwax is back the list is drawn again at once and asked afresh.

**VoiceOver** hears what changes while Requests shows - "Dummy: downloading" as a download moves on, a retry's
refusal, "trying again…", "cancelling…", "Homogenic: left - it carries on for whoever else asked" - and stays
where it was in the list.

## Playing

**The mini player**, the top of the tab bar while something is playing, 60 points tall: the cover flush at its left
edge, the song and its artist, and play/pause - a bare glyph, no circle round it - with room past it so a thumb finds
it. It is solid, black as the tabs under it are, with a thin line along its top and nothing of the page showing
through. There's no next button; instead:

- **The line along its top** is how far in the song is. To seek, put your finger on the mini player's top edge,
  on the line or just under it, and drag sideways: the line thickens, with the time under your finger over it
  ("1:23 / 4:56"), and the song goes there when you let go. Only a sideways drag that starts on the mini player
  seeks. A tap there is the tap of whatever is under it: the cover or the song opens Now Playing, play/pause plays
  or pauses. A drag up there opens Now Playing, and a drag that starts on the page just above the mini player is the
  page's, so a scroll or a tap there never touches the song.
- **Swipe the song's title** left for the next song, right for the song before - however far into this song you
  are, which Now Playing's previous button doesn't do. The title slides away and the new one comes in from the
  other side. A short swipe springs back, and so does one past the first or the last song, or one still held as
  the song changes by itself.
- **Tap the title or the cover**, or drag up on them, for Now Playing. Now Playing opens as you let go, without
  following your finger. A drag down does nothing.

VoiceOver reads it as "Now playing: Roads, Portishead - open", with **Next song** and **Previous song** as its
actions (swipe up or down to hear them): the only way to skip from the mini player without the swipe. The line
reads "Position in the song", "0:12 of 5:00", in 10-second steps. It grows with the text size as far as the tab
bar does.

**Now Playing**: along the top, **Close** at the left and **Turntable** and **•••** at the right, each a purple word
or glyph on the page with no box round it; the cover, as wide as the screen less a margin either side (a little
smaller while paused); the song's title, and under it "artist — album" in purple (tap it to go to the album - a song
that names no album has it in grey, and it goes nowhere). Beside the title, in small typewriter figures, where the song
is in what you queued ("3 of 11") and its format ("FLAC 16/44.1", "MP3"), as the Mac's player bar says them; a song
added with Play Next has no place, and with neither known there's nothing there. VoiceOver reads them as one: "3 of 11,
FLAC, 16-bit, 44.1 kHz". At the accessibility text sizes they go under the title, so it keeps its room. Under them:

- **The scrubber**, a squared-off bar sunk into the page that thickens under your finger: tap a place to go there, or
  drag and let go. The clocks under it, in the same typewriter figures, say how far in the song is
  and how much is left. VoiceOver reads it as "Position in the song", in 5-second steps.
- **Shuffle, previous, play/pause, next, Repeat.** Previous goes back to the song before in a song's
  first 3 seconds; after that, or on the first song, it starts the song again. Repeat goes from off to
  **Repeat all** to **Repeat one** and back to off, and this phone remembers it.
- **Five buttons along the bottom**, each an icon over its name: **Queue**, **Lyrics**, the output, **Info** and
  **EQ**. **Lyrics** (the speech bubble) shows the song's lyrics in the cover's place, and again puts the cover back
  (see [Lyrics](#lyrics)). The output is AirPlay's button - a tap anywhere on it, its name too, opens AirPlay's list -
  with the name of where the music is playing under it, the name the EQ gives it ("iPhone Speaker", or what you
  renamed it); VoiceOver reads it as AirPlay, playing to that name. **Queue**, **Info** and **EQ** open one sheet over
  Now Playing on their page: **‹ Now Playing** at its top puts it away, and under that a strip - **Queue**, **Info**,
  **EQ** - moves between its three pages without closing it. There is no Lyrics in the sheet: they take the cover's
  place. VoiceOver reads the EQ button with the output's setting ("EQ, Bass Boost"), and the Queue with what's on
  ("Queue - Shuffle on").
- **•••**, at the top right beside **Turntable**, has **Info**, **Add to a playlist…** for the song playing (while
  deadwax can be reached), **Go to album**, **Download** (or Remove Download) for the song playing and **Download the
  Queue** - every song still to play that isn't on the phone, when that's two or more. Go to album closes Now Playing
  and opens the album's page on the tab you're on. What a download item did is said for a moment at the top of Now
  Playing ("Downloading: Roads", "Downloading 23 songs from the Queue"), between **Close** and the buttons opposite
  it, never over them - or, at the larger text sizes, where a word of it wouldn't fit between them, across the screen
  just under them, over the top of the cover.
- **The speed**, when it isn't 1x: a purple `1.25x` just above the bottom row, over the gap between the output and
  Info, clear of every button - tap it to go back to 1x. At the largest text sizes it isn't drawn; the **•••** menu's first line says it instead ("Speed
  1.25x - back to normal speed"), and does the same. The speed is set on [the turntable](#the-speed).
- **Turntable**, at the top right beside the •••, shows Now Playing as [a turntable](#the-turntable) instead; there
  it says **Cover**, and puts the cover back.
- **Close** at the top left, or a swipe down from the top of Now Playing, closes it. The top stops growing at the
  largest standard text size; past it, touch and hold one of its buttons to see it large.

**Tap the cover** to see it full screen, on black, as large as Navidrome has it: the cover Now Playing shows comes at
once, and the full-size picture takes its place as it arrives. Pinch to zoom (as far as 3 times for an ordinary cover,
further for a large one, up to 8), double-tap to zoom in where you tapped and again to zoom back out, and drag to look
around while zoomed - it stops at the cover's edges. To close it, swipe down when it isn't zoomed, or tap **✕** at the
top right. Only a tap opens it: a drag down on the cover is Now Playing's from its first few points, and closes it as
before. With Lyrics or the turntable showing, there's no cover to tap. A cover opens once it shows: the grey square of
one still loading, or that couldn't load, opens nothing, and an album with no art of its own opens Navidrome's
placeholder, as Now Playing shows it. The full size is asked of deadwax only while it can be reached, and a file
larger than 30 MB isn't fetched whole - the cover stays at Now Playing's sharpness; offline, a downloaded album's cover
opens at Now Playing's size. Once open, it stays up until you close it, whatever the music does behind it (the next
song, Lyrics taking the cover's place). The music isn't touched by any of it.

With VoiceOver, Now Playing's cover reads "Cover of Dummy - show full screen" (a double-tap on one that hasn't loaded
says so). Full screen, the picture reads "Cover of Dummy, by Portishead" and says how far it's zoomed: swipe up or down
to zoom, scroll with three fingers to look around while zoomed, and the escape gesture (a two-finger Z) or **Close**
closes it.

### The turntable

Now Playing has a second look, as the web app's does: the song on a record turning on a turntable.
**The button at the top right** - **Turntable** on the cover, **Cover** on the turntable - switches
between the two for as long as Now Playing stays open. Which one it opens as is **Now Playing opens
as** in [Settings](#settings) > Playback: **Cover**, the default, or **Turntable**. The button never changes
that: close Now Playing and open it again, and it's back to what Settings says. With lyrics showing, the
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
  pause from either winds the record down (see **Pause winds the record down** in [Settings](#settings) > Playback). If
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
- **VoiceOver**: after **Cover** (the look button), the record is a button that says what a tap does ("The
  record: a tap pauses the song"), and the arm is "Tonearm: position in the song", read as "2:31 of
  7:05": swipe up or down to move 5 seconds.
- **Closing**: on the turntable, only a swipe down from the top row (or **Close**) closes Now
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
- **The cover** says the speed too, just above the bottom row between the output and Info (see
  [Playing](#playing)). The mini
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

### Adding to the queue

**Add to Queue** puts a song - or a whole album or playlist - after the songs you've already added that are
waiting straight after the song playing, still ahead of the rest of the album, playlist or shuffle that's
playing. So with nothing added yet, the first song you add plays next, the second after it, and so on, in
the order you added them; once they've played, the next one you add plays next again. A line above the mini
player says so ("Added to Queue: Roads") for 5 seconds, and VoiceOver reads it. With nothing playing, it
just plays.

Two times the order isn't that simple (the web app's Play Last works the same way after going back):

- **After going back.** Previous, or a song tapped in the Queue's history, leaves the songs you'd added where
  they were - after the song you went back from. A song you add now goes straight after the one playing,
  ahead of them. Say you play an album of six to song 5, add **a** then **b**, and press Previous: song 4
  plays, then 5, a, b, 6. Add **c** now and it plays next: c, 5, a, b, 6.
- **In a song's last two or three seconds.** By then the next song is already lined up to follow without a
  gap, so a song you add waits for it and goes in as it starts: it plays after that next song, not straight
  after the one that was ending. If the next song was one you'd added, the order comes out as usual.

It's the one way to add songs on the phone (since app 0.13 (13)'s build of 16 Nov): every **•••** has
**Add to Queue** where it had Play Next and Play Last - a song's, and the one at the top of an album's or a
playlist's page for all of it. The web app keeps **Play Next** and **Play Last**; the phone's Add to Queue
is the web app's Play Last.

**Swipe a song right** to add it, as Apple Music's rows swipe: on an album's page, a playlist's, the
Library's Songs and All songs, and Search's songs. **On iOS 17**, the Library's Songs and All songs and
Search's songs have no swipe (it needs iOS 18): their **•••** and VoiceOver's Add to Queue still add the
song. Album and playlist pages swipe on iOS 17 too.

- **A full swipe** adds the song as you let go, with a short tap you can feel. On an album's and a
  playlist's page the swipe is iOS's own, as in Mail: how far is "full" is iOS's. On the Library's Songs and
  All songs and in Search it's past half the row, with a light tick as you pass it.
- **A shorter swipe** leaves one purple button, **Add to Queue**, standing beside the row: tap it to add the
  song. Tap the row, swipe it back, or touch anywhere else - scroll, another row or its •••, the search
  field, the Library's pages - and it closes, the purple shrinking back with the row. With **Reduce Motion**
  on, the row on the Library's Songs and All songs and in Search opens and closes at once, without sliding.
- It does just what the song's **•••** > Add to Queue does, and it's on every song row whose ••• has Add to
  Queue: while deadwax can't be reached, only on the songs on the phone (as the ••• offers it). The
  Queue's own rows, the Library's grids and a song you don't have (Search's MusicBrainz songs) have no swipe.
- **VoiceOver**: on the song itself (not its •••), the actions (swipe up or down) include **Add to Queue**.
- A swipe that starts at the very left edge of the screen still goes back, on a page you opened - and on the
  Library's Songs page, turns back to the page before (a swipe right that starts on a song adds it there).

### Queue

**Queue** along the bottom of Now Playing opens what plays after the song playing - and, above it, what you've
already played - in Now Playing's sheet, its first page (the strip at its top moves to Info and the EQ; **‹ Now
Playing** puts it away). The web app calls it Up Next:

- **What you've played**, above the song playing (app 0.8, as the web app's Up Next since deadwax
  2.1.15): one list, the newest nearest the song playing, with no headings, dates or times - scroll up
  and it keeps going, back through every song you've started, on the phone and in the web app. The Queue
  opens at the song playing, even with only a song or two left after it; scroll up for the rest.
  Nearest the song playing is what has played since you started the album, list or shuffle - songs a
  tap skipped past included, where they are on the album; above that, everything you played before it,
  in the order you played it. A song Repeat One played again, or that you started again, is one row;
  Repeat All's earlier times round are there as they played. A song you skipped after a second is there
  like any other. As you scroll near the top the next older songs come, a spinner over the top of the
  list while they do (VoiceOver: "Loading earlier songs") - and nothing you're looking at moves when
  they land. If they can't come, the top of the list says "Couldn't load the songs you played before.",
  with **Try again**. **Tap any of them to go back to it** (as the web app does since deadwax 2.1.18):
  it plays now, from its start, and everything played after it moves back down into the Queue, in the
  order you see it - the songs between, the song that was playing (from its start, when it comes round),
  then Playing Next and the rest of the album or list, as they were. The song you tapped is where your
  finger was. Nothing is lost or reshuffled: songs you added (Add to Queue) that were still waiting keep
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
  which refuses the Queue's account of a queue you went back in, the app saves that queue as just its
  songs, the one playing and the second (it used to try again every 30 seconds and keep nothing):
  [picked up](#picking-up-where-you-left-off) it comes back as that plain list, every song in order,
  without Playing Next or the Shuffle chip.
  What goes in it, and where it's kept: [What you've played](#what-youve-played).
- **The song playing**, where the Queue opens - on the phone the first row, lit as the selected row - and
  with Repeat One on, "Repeat one: this song plays again until you skip it." On the Mac, **Shuffle** and **Repeat**
  are under it, the same settings as on Now Playing; on the phone they're along the Queue's foot (below).
- **Playing Next**: the songs you've added, in the order they'll play, with **Clear** to take them all
  out (on the phone Clear is at the top). It's there only when you've added some.
- **The rest of the album or list this time round**, headed "From Mezzanine" for one album's songs - on the
  phone "Next from Mezzanine", and each row just its title, as the heading has said the album - or
  "Still to play" for several albums', up to 100 of them, then "And 380 more songs." Under it, what
  comes after: "Then Mezzanine again from the top." with Repeat All ("Then Mezzanine again, in a new
  order." with Shuffle on too), or "Nothing after this song." at the last song with Repeat off.
- **Tap a song** to play it now, even from a pause. Nothing is taken out: tap a song further down the
  album and the songs between stay where they are, behind it - playing song 5, tap song 8, and Previous
  plays 7, then 6, as on the album - and Playing Next stays next, after it. Tap one in Playing Next and
  the songs added above it are behind it the same way. The Queue puts the song playing back at the top
  whenever it changes - a tap, a song ending, Next or Previous - and when Edit starts or ends; Shuffle,
  Repeat, Clear and Edit's changes leave the list where you've scrolled it.
- **After Previous**, a song you'd added that was still waiting stays where it was - after the song you
  went back from - so the Queue lists it there, in the album's group, rather than under Playing Next;
  **Clear** takes only the songs under Playing Next.
- **On the phone, the top and the foot**: at the top, beside **‹ Now Playing**, **History** - which scrolls up to
  what you've played - **Clear** and **Edit**; from the text size after the standard one, History and Clear are in a
  **•••** beside Edit. Along the foot, **Shuffle** and **Repeat**, lit while on, and the time left: "8 songs · 33 min
  left" - the songs after the one playing, and how long they take with the rest of this one, at the speed it's
  playing. What you've played never counts. Under a minute it says "under 1 min left", and nothing at all once
  nothing is left. It says "over 33 min left" when a song's length isn't known or there are more songs than are
  listed (and just the songs, "8 songs", when what's known is under a minute); with Repeat One on, just "8 songs";
  with Repeat All on, it counts what's listed - the rest of this time through, not every time after it. Where the
  three don't fit on one line, the time left goes under the two. On the Mac the time left is at the left of the
  foot of the panel's Queue tab.
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
  (VoiceOver reads it after the song: "Roads, play now, Downloaded"). The Queue has no download button
  of its own: Now Playing's **•••** > **Download the Queue** is it. While deadwax can't be reached, songs
  not on the phone are dimmed and a tap on one does nothing; in Edit you can still move or take them
  out. The song playing is never dimmed.

**Shuffle**, turned on while a song plays, keeps that song going and shuffles every song of the album
or list you haven't heard this time round. Turned off, the album's own order carries on from the song
playing. Either way the song playing goes on, untouched, and songs you added keep their order, ahead of
the rest.

### Lyrics

**Lyrics**, second in Now Playing's bottom row, shows the song's lyrics in the cover's place, as
Apple Music does: the title, the scrubber and the buttons stay where they are. The speech bubble is
filled and purple while lyrics are on. Tap it again for the cover. Lyrics stay on from song to song,
and each time you open Now Playing, until you tap **Lyrics** again or quit the app.

- **Synced lyrics** (most of what deadwax saves): the line being sung is white, the rest dimmer, and
  it's kept about a third of the way down, the lyrics moving up as each line comes. In a long break,
  or an intro of four seconds or more, three dots light one by one until the next line.
- **Scroll** to read ahead or back: the lyrics stay where you put them, the line being sung still
  lighting up. About four seconds after they come to rest they go back to the line being sung, while
  the song plays. Paused, they stay put until you press play. Scrolling them never closes Now
  Playing; a swipe down from the top row, Close's, does.
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

**Info** (Now Playing's bottom row, or its **•••**) opens in Now Playing's sheet, on its Info page, and has an
**About** tab (on the Mac, the side panel's Info tab - see [The Mac app](#the-mac-app)). On the phone:

- **The song** at the top: its cover, title and artist, and its album and year ("Wilco (The Album) · 2009").
- **This song**: **Format**, **Track** ("4 of 10"), **Disc**, **Length**, **Size** - the file's size and bit rate,
  "24 MB · 921 kbps", when Navidrome gives them - **Played** - "19 times · today", the
  day ("yesterday", "3 days ago", "12 Nov") only when Navidrome says when it last played, and no Played row for a
  song never played - and **Written by** when Navidrome says; then the rest of **Sound** (below), **Plays from** and
  the **EQ**.
- **The album**: **Released**, **Label**, **Songs**, with logins on **This pressing** - which pressing it is - and
  for an admin **Folder**, its folder on the server. **Album info**, under them, opens [everything known about the
  album](#album-info) inside Info - its Back goes back to Info. From a playlist, it's the whole album's, not only
  the playlist's songs of it.
- **Go to album** and **Go to artist**: each puts Now Playing away and opens the page.

On the Mac:

- **The song**: its title and artist, then its **Track**, **Disc**, **Length**, **Size**, **Played** and **Written
  by**, as the phone's This song has them.
- **The album**: click it to go to its page. With logins on, it says which pressing it is, and an admin
  also sees its folder on the server. **Album info**, under it, opens everything known about the album inside Info.
- **The artist.**

On both:

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

## Settings

**Settings** is the web app's **Settings** too (the phone called the tab You until the build after app 0.13's Manage -
still 0.13 (13) - and the web app until deadwax 2.1.35). Its first screen is a short list, as the iPhone's own
Settings is: each row opens a page of its own, and **Back**, or a swipe in from the left edge, comes back. Tap
**Settings** in the tab bar on one of its pages and it goes back to the first screen; tap it again there, and it goes
to the top.

- **At the top**: who you're signed in as, or "No sign-in needed" with logins off - and, in amber, "Some things an
  admin let you do are off for now - sign out and in again to get them back." when deadwax says so.
- **Getting albums**, **Playback** and **Downloads**, each opening its page - Downloads with what's on this phone at its
  right ("2.1 GB"). Under the three, only while something is happening: "Downloading - 6 songs to go", what it's
  waiting for, or, in amber, "2 songs didn't download".
- **Manage**, for someone who may look after deadwax - an admin, everyone with logins off, or someone an admin gave
  a permission to: the tools you may use, each a page of the app's own (see [Manage](#manage)).
- **Account**, with logins on.
- **This phone**, with the name or IP deadwax is at on its right ("192.168.1.20", "bearded-dragon").
- **About**, with the app's own version on its right, **0.13 (13)**.

The first screen asks deadwax who you are the first time it shows, and again when you pull it down: Manage, Account
and About follow what it last said.

**Each choice is one row with a menu.** A row says the setting's name, and what's chosen at its right. Tap it and a
menu of the choices opens, the chosen one ticked; tap another to choose it. What a choice does is said under the row -
for Normalization and Download over, what the chosen one does, first. VoiceOver reads the row's name and what's chosen
("Normalization, Automatic"), and Normalization and Download over add what the chosen one does; a double tap opens the
menu. A switch (Confirm before cancelling, Pause winds the record down) is still a switch.

### Getting albums

The web app's three, each a menu:

- **When I tap Get**: **Show me the sources** (the default) or **Pick the best source for me**.
- **Quality floor**: **Any** (the default), **320 kbps**, **Lossless** or **24-bit**.
- **Format**: **Any**, **Prefer lossless** (the default) or **Lossless only**.

Under them, the web app's note: "“Show me the sources” lets you choose each download yourself. “Pick the best
source for me” downloads the best match that meets your quality floor, and shows you the sources instead when
nothing matches well, or when you already have the album or are getting it." - and how the floor and the Format
are used (see [Getting an album](#getting-an-album)). They're your account's, kept on deadwax, so a choice on the
phone is the web app's too, and the other way round: the page asks deadwax for them each time it opens, on a pull
down and when deadwax can be reached again, so one changed in the web app shows here. A choice shows at once and is
saved behind it. Until deadwax has first answered, the three rows show nothing chosen and can't be tapped; while it
can't be reached, they show what was chosen but can't be tapped, and "Getting albums works once deadwax is back."
says why. A choice deadwax doesn't keep goes back, with "Not saved." and why under the three (VoiceOver says it).
With deadwax's database unwritable, "deadwax can't keep these: its database isn't writable." - and "Tell whoever
runs deadwax." for anyone but an admin.

Then **Confirm before cancelling**, a switch, on by default - "The ✕ on a download in Requests asks first. Kept on
this device." Off, the ✕ on a card in [Requests](#requests) cancels at once. It's this phone's, not your account's,
as it is each browser's in the web app.

### Playback

- **Gapless**: On. "Albums play straight through, with no gap between songs." It isn't a setting:
  the app always plays this way.
- **Now Playing opens as**, a menu: **Cover** (the default) or **Turntable** - what Now Playing shows each
  time it opens. "What you see first when you open Now Playing. The button at its top right switches
  between the two while it's open." See [The turntable](#the-turntable).
- **Pause winds the record down**, a switch: on by default. On the turntable, a pause - a tap on the record,
  or play/pause while it shows - slows the music to a stop over about a second, as a real record deck
  does, and the song stays paused where the sound stopped. Off, the sound stops at once (the record
  still spins down). Pausing from the cover, the lock screen or the mini player always stops at once.
  Both are kept on this phone.
- **Normalization**, a menu: brings songs to an even loudness, the way the web app's does. Four choices, and under
  the row what the chosen one does:

  | choice | what it does |
  | --- | --- |
  | **Automatic** (the default) | An album you play keeps one level for the whole album, so its quiet songs stay quiet beside its loud ones. Anything else - a playlist, a shuffle, a song you add with Add to Queue - is levelled song by song. |
  | **By song** | Every song brought to the same loudness, even the quiet and loud songs of one album. |
  | **By album** | Every song at its album's level, even when it plays on its own or in a playlist. |
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

### Downloads, Account, This phone and About

- **Downloads** is [Settings > Downloads](#settings--downloads).
- **Account**, with logins on: **Change password**, then **Sign out**. Change password opens a page of its own
  ([Change password](#change-password)) - your Navidrome password changed from the phone. It isn't there for the
  emergency `deadwax` sign-in, which has no Navidrome password to change. **Sign out** ends this phone's session and
  stops what's playing. With anything downloaded, it adds that your downloads stay on this phone for when you sign in
  again. If deadwax can't be reached, it says "Couldn't reach deadwax, so you're still signed in - try again."
- **This phone**: deadwax's address, **Change address**, and **Debug**, for an admin (with logins
  off, everyone is one).
- **About**: deadwax's version, whether logins are on (for an admin), and the app's own version,
  **0.13 (13)**. If deadwax didn't answer when it was last asked who you are, why is said under them, and deadwax's
  version stays the one it last gave ("Not known" only if it has never answered); pull the page down to ask again.

Account and About ask deadwax again when you pull them down, as the first screen does.

### Manage

Settings > **Manage** is deadwax's tools for looking after it, as many of them as you may use. They came into the app
one build at a time (Phase 8), and every one is a page of the app's own - none opens Safari. Top to bottom, each only
for someone who may use it:

| row | who has it | opens |
| --- | --- | --- |
| **Edit an album** | Edit albums or Look after the library | **Choose the folder**, in the app: every album folder deadwax's library has, with a search at the top - tap one and [Edit album](#edit-album) opens for it. It's the way to a folder Navidrome doesn't list. An album's top **•••** has **Edit album** too ([An album's page](#an-albums-page)). |
| **Needs a look** | Look after the library | [**Needs a look**](#needs-a-look), in the app: the albums that need fixing and the new downloads nobody has looked at, worked through one after another in Edit album. How many albums it lists is at the row's right. |
| **Library care** | Look after the library or Edit albums | [**Library care**](#library-care), in the app: Rescan (Look after the library's), and covers, CD art and lyrics fetched for every album without (Edit albums') - and, with logins on, In nobody's library. |
| **People** | an admin, with logins on | [**People**](#people), in the app: unlocked with your own Navidrome password, every Navidrome account - each with its permissions, Reset password…, Make admin and Remove… - Add a person, and the names deadwax keeps things for with no account. |
| **Server settings** | Settings and the log | [**Server settings**](#server-settings), in the app: whether deadwax reaches MusicBrainz, slskd and Navidrome, and every setting of the server's, a group to a page, saved together. |
| **Event log** | Settings and the log | [**Event log**](#event-log), in the app: what deadwax has said since it started - the last 500 lines - newest first, each new line as deadwax logs it. |

An admin has every row. With logins off everyone does, but People: there's nobody to manage. Someone with none of
these permissions has no Manage at all ([Sharing deadwax](sharing.md#admins-permissions-and-everyone-else) has what each
one gives). The rows follow what deadwax last said of you: Settings asks again the first time it shows and on a pull
down. If an admin took a permission away since, the page it opens says "This page needs a permission an admin hasn't
given you - ask one if you need it." - and People, its own words: "Only an admin can open People - it comes with
being a Navidrome admin."

Nothing is said under the rows. Every row opens while deadwax can't be reached: each page says it needs deadwax, and
reads what it shows once it's back. All of them open as whoever is signed in to the app.

VoiceOver reads each row as one that opens a page, Needs a look with its count ("Needs a look, 3 albums"). The rows
grow with the text size.

An artist's pictures and names are managed from [the artist's page](#managing-an-artist), as in the web app. The web
app's **Connections**, in its Settings, is at the top of [Server settings](#server-settings) on the phone.

**Nothing in the app takes you to the web app.** Every managing tool - Manage's rows, an album's **Edit album**, an
artist's **Artist images…**, **Which artist is this?** and **Move albums to …**, Account's **Change password** and the
Library's **Set up Navidrome** - is a page or a sheet of the app's own. (Until the build after People, the app still
had the pieces of its old way out to the web app in Safari, unused; that build took them out, and deadwax's own tests
now refuse a new one.) The app has three links out, and none of them is to deadwax:

| link | where | opens |
| --- | --- | --- |
| **This pressing on MusicBrainz**, **Every pressing on MusicBrainz** | [Album info](#album-info) | the release's and the release group's pages on musicbrainz.org |
| **AutoEq on GitHub** | the foot of a correction's page in the [EQ](#autoeq-a-correction-for-your-headphones) | AutoEq's project on GitHub |
| **Sharing deadwax** | [People](#people), only if logins are turned off on deadwax while the app is open (People isn't in Manage with them off) | the [Sharing deadwax](sharing.md) guide, on GitHub - deadwax's tests keep it to that page |

Each opens in your browser (Safari unless you've changed it), beside the app; the music keeps playing.

### Needs a look

**Needs a look** (Settings > Manage > Needs a look, for someone with **Look after the library** - an admin, or
everyone while logins are off) is the web app's review queue on the phone: the albums whose tags, folder or cover need
fixing, the albums Navidrome doesn't list, and the new downloads nobody has looked at yet. It's a page pushed on
Settings, and each album on it opens [Edit album](#edit-album).

**Its count** - how many albums it lists - is at the right of its row in Settings > Manage ("99+" past 99; nothing
when there are none, or before deadwax has said), never on a tab. It's asked only while Settings or Needs a look is
on screen: as either comes up, on a pull down on either, as the app comes back from the background with one of them
up, and after anything Edit album or an artist's tools write while one of them is up - an apply, a Get, a delete, a
mark, an album noted as looked at, Save, Move. It isn't asked as the app starts on another tab: opening Settings asks
it. deadwax answers it from its saved scan, without reading the disk. A count that can't be had leaves the last one.
Someone without Look after the library has no row, so no count.

**At the top**, what the page is for: "Albums whose tags, folder or cover need fixing, albums Navidrome doesn't list,
and new downloads nobody has looked at yet. Open one to fix it, or to mark it fine as it is." Without Edit albums it
ends "Open one to see what it has, or to delete it.", and "Fixing it needs Edit albums, which an admin hasn't given
you." follows. When deadwax can't save to its database, an amber line warns that an album you mark "It's fine as it
is" will come back (check `DB_PATH`).

**The list.** "Reading the library" while deadwax reads the library (the first time on a big library, a minute or
more); if that fails, "Couldn't read the library." with **Try again**. Then a section headed by what it shows and how
many ("All · 12"), and a line under that heading, there even when empty so nothing jumps: "Checking the library…"
while it's read again, "Couldn't check the library just now." with **Try again** when that failed, or why some albums
may not have been checked against Navidrome ("Navidrome isn't set up, so no album is checked against what it lists.
…"). Each row is the album's cover, its name, its artist and edition, and what's wrong, in amber: **New** for a
download nobody has looked at, then each issue as Edit album names it ("No cover art", "Not matched to MusicBrainz"…).
"Nothing needs a look." when nothing does. When deadwax has no library to read (`LIBRARY_PATH` unset or missing), it
says so in the list's place. Pull down to read the library again; it's read again too each time the page shows anew,
and when deadwax comes back into reach. These words are the page's own: a read Edit album makes that fails says
"Couldn't read the library." in Edit album, and "Couldn't check the library just now." here.

**Show**, the menu at the top right (filled while it narrows the list), picks what the list shows, as the web app's
chips do, each with how many: **All**, **Newly added** (when there are any), one per kind of issue (the most albums
first), and **Marked fine** (when there are any) - the albums whose every issue you marked fine, the one way back to
such an album's Edit album when Navidrome doesn't list it, each with "Marked fine" in its row. A choice that empties
goes back to All.

**Working through it.** Tap an album: Edit album opens on its folder, with ‹, where you are ("2 of 9") and **Skip ›**
along its foot. Do whatever the album needs - apply a release, edit its tags, get its cover, mark it fine, delete it -
and **Skip** becomes **Next album ›**; ‹ goes back one. Each step opens that album in the same Edit album. Underneath,
the list holds still while you work: an album you fixed, marked fine or deleted keeps its row, saying **Fixed**,
**Marked fine** or **Deleted** in green, followed through a rename, and the one open is shaded. Stepping away from an
album - ‹, Skip, Next album, or closing Edit album - notes it as looked at, which is what stops a new download being
New (its issues stay), and the count follows. Deleting an album leaves Edit album up, saying "Deleted …", with **Next
album** to go on. If the album you step to has gone from the library since the list was read (deleted or moved
elsewhere), the run ends and Edit album closes. Once it ends, the list stays as it was until deadwax has read the
library again, then it's worked out afresh - albums put right leave it. The steps are dimmed until everything done to
the album on screen has settled: while something is being written or marked and until the library has been read again
after it, while the library is being read, while Release or Tags waits for that read (Look again, if it failed), while
a delete that got no answer waits to be found gone or not - and while deadwax can't be reached. With something typed
and not applied, a step asks "Discard changes?" first, as Close does, and Discard steps only if the steps are still on.
Opening a picture full size (Compare covers, the cover or CD art, a track's picture) and closing it again leaves the
run as it was; only Edit album closing ends it.

**While deadwax can't be reached**, a page that hasn't read the library yet says "Managing needs deadwax. This opens
once it's back." and reads it once deadwax is back; one that has keeps its list under the amber line Edit album shows
("deadwax is out of reach - this is how it was, and nothing here can change until it's back."), its rows can't be
tapped and a pull asks nothing - and the library is read again once deadwax is back. If an
admin took Look after the library away, it says "This page needs a permission an admin hasn't given you - ask one if
you need it.", and asks nothing. When your session ends, nothing is read, noted or counted under the sign-in; sign in
again and the page reads the library again, and the count follows.

VoiceOver reads each row once - its album, artist and edition, and what's wrong with it or what became of it ("The
Slow Rush, Tame Impala, New, No cover art"), with "Open" on the one Edit album has open - and the Show menu as "Show,
All". Edit album's foot reads as "Previous album", "2 of 9" and "Skip" (with "Leave this one for now and move on") or
"Next album", and each step is said: "3 of 9: The Slow Rush". With Reduce Motion on, rows don't slide as the list
changes. Every line grows with the text size.

### Library care

**Library care** (Settings > Manage > Library care) is the web app's Library care on the phone: **Rescan**, for
someone with **Look after the library**, and the runs that fetch **covers, CD art and lyrics** for every album
without, for someone with **Edit albums** - an admin, or everyone while logins are off, has both. It's a page pushed
on Settings. Each part shows only for whoever has it, and the line at the top names only those: "Rescan the library
after changing tags in another program, and fill in missing covers, CD art and lyrics across many albums at once -
one album at a time, and Stop ends a run after the album it's on." with both; with Rescan alone, "Rescan reads every
file of the library again - use it after changing tags in another program."; with the runs alone, "Fill in missing
covers, CD art and lyrics across many albums at once - one album at a time, and Stop ends a run after the album it's
on."

"Reading the library" while deadwax reads it; if that fails, "Couldn't read the library." with **Try again**; when
deadwax has no library to read (`LIBRARY_PATH` unset or missing), it says so instead. Then:

- **Rescan**: what the library holds and how old the scan is ("7 albums · 87 tracks · 425 MB · Scanned 3 min ago in
  2s"), the **Rescan** button, and under it why it's there: "Use Rescan after editing tags in another program:
  deadwax spots a changed album by its folder's date, and editing tags in place doesn't change it. Albums added from a
  download show up without it." Rescan reads every file again - "Rescanning…" on the button, "Rescanning - reading
  every file again…" in the line above, a minute or more on a big library - and the count beside Needs a look follows
  once it's done. If it gets no answer in five minutes, it says "deadwax may have finished this - looking again" and
  reads the library to see. If reading it again fails, "Couldn't read the library just now." with **Try again**.
- **Covers, CD art and lyrics**: **Narrow to** (Artist, album or folder) and what the runs act on ("The runs act on
  the whole library: 8 album folders.", or "The runs act on 3 of 8 album folders: those matching "portishead"."),
  then **Covers**, **CD art** and **Lyrics**, each with **Get covers · N**, **Get CD art · N** or **Get lyrics · N** -
  N the album folders it would take, and no button when there are none - and what it will do, as the web app says it
  ("14 album folders matched to a release with no cover in the whole library. Each cover comes from the Cover Art
  Archive…"). A cover is fetched for an album matched to a release with no cover, CD art for one matched to a release
  with no disc picture from deadwax yet, lyrics for one with no lyrics at all.

**A run** fetches one album at a time, each through the same step as that album's own **Get** in [Edit
album](#edit-album). While it runs, its button is **Stop after this album · 3 of 12** (the third album is the one
being fetched): tap it and it says "Stopping after 3 of 12", finishes that album and goes no further. When it ends it
says what it did, as the web app does ("Got 10 covers. 1 has none in the Cover Art Archive. 1 failed - run it again to
try it again."; lyrics are counted in tracks), VoiceOver reads it, and it stays on the page until that run starts
again. Needs a look's count follows each album a run saved something for. After a run that saved something, the page
reads the library again before offering that run again - "Checking the library…" for that moment - so its button
never comes back over the albums it has just done.

**One run at a time on the phone** (the web app runs the three at once): while one goes, the others' buttons are
dimmed, with "One run at a time - this one can start once Covers has finished." under them. The run is the app's, not
the page's: go back to Settings, or to another tab, and it carries on, its result still there when you come back. **The
screen stays on** while a run goes and Library care is in front ("The screen stays on while a run is under way and this
page shows." under its button) - and only then. **A run stops after the album it's on** when the app goes to the
background (lock the phone, or switch apps: iOS stops an app soon after), when deadwax goes out of reach, when your
session ends, or when an admin takes Edit albums away (deadwax refuses the next album - counted as failed - and the run
stops there) - and says so after its result: "Got 14 covers. Stopped at 14 of 60. It stopped as the app went to the
background - Get covers carries on." (With Edit albums gone, the runs go from the page, and only VoiceOver says it.)
Start it again and it takes only the albums still without, since it asks again which those are. When your session
ends, nothing is read under the sign-in; sign in again and Library care reads the library again. Signing out stops a
run before its next album, and the next person's Library care starts afresh.

**In nobody's library** (with logins on, for someone with Look after the library) is a row under the runs, opening a
page of its own: how many albums nobody has in their library ("3 albums nobody has in their library", or "Every album
in the collection is in somebody's library."), the first 20 of them with their folders, then **Show all 37** (and
**Show fewer**). Under **Flagged downloads**, each download nobody was given because every file was already in a
folder that holds another pressing or an untagged copy - who asked for it and why - with **Add for them** (it goes
into the libraries of those who asked) and **Dismiss**. One at a time: the buttons are dimmed while one is being done,
and while the list is read again after it. VoiceOver reads what was done ("Third · Portishead: given to ethan, sam"); if deadwax
refuses, its own words are said under the list ("That has been dealt with already."). Pull it down to read it again.

**While deadwax can't be reached**, a page that hasn't read the library yet says "Managing needs deadwax. This opens
once it's back."; one that has keeps what it showed under the amber line Edit album shows, and nothing can be started
or pressed until deadwax is back and the library has been read again. Without Look after the library and without Edit
albums - an admin took them away - it says "This page needs a permission an admin hasn't given you - ask one if you
need it." and asks nothing. VoiceOver reads each line once; with Reduce Motion on, nothing slides; every line grows
with the text size.

### Server settings

**Server settings** (Settings > Manage > Server settings, for someone with **Settings and the log** - an admin, or
everyone while logins are off) is the web app's Server settings on the phone, with the web app's **Connections** at its
top. It's a page pushed on Settings, and a list, top to bottom:

- **What it's for**: "How deadwax runs, as your compose file or .env sets it. A change saved here takes effect at once,
  with no restart, and is used instead of what the file says until you revert it. Your own choices - what Get does,
  the quality floor, Format and whether cancelling asks first - are in Settings, under Getting albums."
- **Connections**: MusicBrainz, slskd and Navidrome, each "Checking…" until it answers, then **Connected** (Navidrome's
  own name and version, when it gives one) in green or what is wrong in red, in a word - "Can't reach it", "Not set
  up", "Key refused", "Not running", "Not on Soulseek", "Couldn't check" - with the sentence saying why under it (the
  web app's, which you can select and copy). **Check again** asks all three again; it's dimmed until they've been asked
  once and while deadwax can't be reached. They're asked the first time the page shows - MusicBrainz's is a real
  request to a service that limits how often it's asked, so never more - and again on Check again, after a save that
  changed one of the Connections settings, once deadwax is back after being out of reach, and once you've signed in
  again.
- **The organizing verdict**: "Organizing is active — finished downloads will be moved into the library, tagged and
  filed." in green, or "Organizing will not file anything right now." in amber with what stops it under it ("•
  SLSKD_DOWNLOAD_PATH is not set").
- **Library** (Paths, Organizing, Cover art, Lyrics), **Downloads** (Soulseek searches, When a download fails) and
  **Connections** (Connections, MusicBrainz's saved answers, Logins) - the web app's three tabs - each group a row that
  opens its own page, marked **Needs attention** (amber: one of its settings is wrong, or Organizing while it's
  blocked) or **Unsaved** (a change of yours not saved yet). Under each section what it holds ("Paths, organizing,
  covers and lyrics").

**A group's page** has the group's note, then a section for each setting, headed by its name (`LIBRARY_PATH`): a menu
for one that takes certain values, a field for the rest, with no capitals or corrections, and the address keyboard for
an address (`NAVIDROME_URL`). A secret - a password or an API key - is a secure field that never shows what's saved:
"•••••••• (set)" in it when there is one, "not set" when not; type a new one to replace it. One deadwax won't let you
change here (`DB_PATH`, say) says **Locked**, and why. Under each: where its value came from ("Set here", "From the
container environment", "From .env"), **Unsaved** or **Needs attention**, what it does, and what is wrong with it.
Once a setting has been set here, **Revert to the environment (…)** brings back the compose file's value (shown in the
brackets) on the next save - "Will revert to the environment on save." until then. Change `NAVIDROME_URL` or
`SLSKD_URL` and the password or API key under it says "Type the password again to go with the new address - deadwax
won't send the saved one to an address it wasn't entered for." until you do.

**Saving is one press for every change, on every page.** Changes are kept as you go from group to group, and back to
Settings and other tabs - they stay until saved or discarded, as long as the app runs. While there are any, every
Server settings page has a bar at its foot: "2 unsaved changes", **Discard** and **Save changes**. Save changes sends
them all at once: **Saving…** on the button, then "Saved." (VoiceOver reads it), each row's Unsaved gone, its new
value in force. If deadwax refuses, nothing at all is saved: "Not saved: SLSKD_SEARCH_TIMEOUT: expected whole seconds,
3 to 60 - 8 is the default" in red, as deadwax said it, every change still there to put right. If the save gets no
answer - the network dropped, or deadwax answered with an error of its own - the bar says "deadwax may have finished
this - looking again" while the settings are read again; what was saved is no longer Unsaved, and only what still
differs is left to save. "Saved." comes only when everything that save sent is what the settings now hold. If reading
them fails, the bar says so ("Couldn't read the settings again just now.") with **Try again**. **Discard** while it
looks ends the look - nothing is said of how the save came out, and the settings are read again to show what's
there. Save changes is dimmed while a save is going, while one that got no answer is being looked at, and from the
moment deadwax goes out of reach until the settings have been read again after it's back. The fields can be typed in
while a save goes, as in the web app.

Two groups do more than their settings:

- **Lyrics** has **Re-time saved lyrics** under `LYRICS_LEAD_MS`: it moves the timings of synced lyrics already
  saved to the lead in force, one album at a time - "Re-timing 4 of 60 albums · Stop after this album" while it goes
  (tap it to stop after that album), then what it did ("Re-timed 212 tracks, 40 already at this lead."). Change the
  lead and it says "Save the new lead first." until it's saved. As with Library care's runs, **the screen stays on**
  while it runs and the page shows ("The screen stays on while it runs and this page shows."), and it stops after the
  album it's on when the app goes to the background, deadwax goes out of reach, your session ends or Edit albums is
  taken away, saying why ("It stopped as the app went to the background - running it again carries on."): running it
  again is safe, an album already at the lead is left as it is. It needs **Edit albums** too: without it, "Re-timing
  needs Edit albums, which an admin hasn't given you."
- **MusicBrainz's saved answers** says what deadwax keeps of MusicBrainz's answers ("1,234 answers in 3.2 MB saved,
  of 200 MB.", read each time the page shows), and **Clear MusicBrainz's saved answers** asks first ("Clear
  MusicBrainz's saved answers?" - **Clear** or **Cancel**), then clears them: "Cleared. The next answers are asked of
  MusicBrainz again." Only speed is lost. It's dimmed with nothing saved, and while a new path is unsaved ("Save the
  new path first.").

**While deadwax can't be reached**, a page that hasn't read the settings yet says "Managing needs deadwax. This opens
once it's back."; one that has keeps what it showed under the amber line Edit album shows - your changes can still be
typed, but not saved - and reads them again once deadwax is back. If the first read fails, "Couldn't read the
settings." with **Try again**; a later one, "Couldn't read the settings again just now." over what was there. Without
Settings and the log - an admin took it away - it says "This page needs a permission an admin hasn't given you - ask
one if you need it." and asks nothing. When your session ends, nothing is asked under the sign-in; sign in again and
the settings are read again. Signing out drops any unsaved change, and the next person's Server settings starts
afresh. VoiceOver reads each row once - a group with its mark, a Connections row with its state and why; with Reduce
Motion on, nothing slides; every line grows with the text size.

#### Set up Navidrome

When deadwax hasn't been told where Navidrome is, the Library shows "Connect Navidrome", and an admin **Set up
Navidrome**. It opens Server settings' **Connections** page as a sheet over the Library, Connections' three rows at its
top: fill in `NAVIDROME_URL`, `NAVIDROME_USER` and `NAVIDROME_PASSWORD` and **Save changes**. The Library asks
Navidrome again as the save lands; once Navidrome answers, the sheet goes and the Library fills. If it doesn't, the
Navidrome row says why. Losing deadwax doesn't close it: the sheet stays up with the amber line, your typing kept, and
Save changes comes back once deadwax does. **Close** puts the sheet away - unsaved changes stay, for the next time it
opens or for Settings > Manage > Server settings - and it can't be closed, or swiped away, while a save goes.

### Event log

**Event log** (Settings > Manage > Event log, for someone with **Settings and the log** - an admin, or everyone while
logins are off) is the web app's event log on the phone: what deadwax has said since it started - the last 500 lines it
keeps - newest first, and each new line as deadwax logs it. It's a page pushed on Settings:

- **Under the bar**, where the live feed stands, in one line: "Connecting…" with a grey dot, "Live" with a green one
  once deadwax is sending, and "Lost the live feed - reconnecting…" in amber while it's gone. It's never a line of the
  log itself, so a feed that drops and comes back fills nothing with failures.
- **What it's for**: "What deadwax has said since it started - the last 500 lines - newest first. Clear empties this
  view only."
- **The lines**, newest at the top: each its time on the phone's clock (14:03:27), its level - ERROR (and CRITICAL) in
  red and WARNING in amber, their words the same colour; the rest plain - and which part of deadwax said it, over what
  it said, which wraps. "Reading what deadwax kept…" until the first read answers; "Nothing logged yet." when there's
  nothing.

**Copy**: a long press on a line offers **Copy**, which puts it on the clipboard as drawn - its time, level and part,
then its words, all on one line unless the words run over several - to paste into a message or an issue. VoiceOver has
Copy among a line's actions. (The web app has no Copy: select the text there.)

**Clear**, in the bar, empties the page on this phone: "Cleared. New lines show here as deadwax logs them." Nothing is
cleared on deadwax - the web app's log still has every line - and what was cleared doesn't come back when you leave and
return: only what deadwax logs after it does. It's dimmed with nothing to clear.

**The feed is live only while the page shows with the app in front.** Go back to Settings, to another tab, or out of
the app, or open Now Playing over it, and it stops: nothing keeps the phone awake or runs in the background for it.
Come back and the lines deadwax kept are read again, then the feed picks up from the last line the page has - what was
logged meanwhile fills in, nothing twice. If the feed drops, the line says "Lost the live feed - reconnecting…" and it's
asked for again 5 seconds later from the last line held, so nothing logged meanwhile is missed (as long as deadwax
still keeps it: its last 500). While deadwax answers with an error - restarting behind a proxy, say - it's asked again
every 5 seconds until it's back. If nothing answers at all - WireGuard off, the Wi-Fi gone - the app soon finds
deadwax out of reach (the amber line below), stops asking, and picks up once deadwax is back in reach. deadwax sends a
keepalive every 15 seconds while it has nothing to say, so a connection that goes quiet without a word is taken as
lost within 45 seconds. When deadwax has restarted, its new lines come in above the last run's.

**While deadwax can't be reached**, a page that has heard nothing yet says "Managing needs deadwax. This opens once
it's back."; one that has keeps its lines under the amber line Edit album shows, with "Lost the live feed -
reconnecting…" under the bar, and picks up once deadwax is back. If the kept lines can't be read, it says so in red -
"Couldn't load the lines deadwax kept - what happens from now still shows.", or why ("Can't connect to deadwax. Check
your connection.") - with **Try again**, and the feed opens all the same: new lines still come in, and the next read
fills in the rest. If deadwax refuses the feed, the line says "Not live", why is said in red ("Couldn't open the live
feed." when deadwax gave no words of its own) with Try again, and it isn't asked for again until you tap it - or until
the page is shown again, the app comes back from the background, deadwax comes back in reach, or Now Playing is put
away. Without Settings and the log - an admin took it away - it says "This page needs a permission an admin
hasn't given you - ask one if you need it." and asks nothing. When your session ends, nothing is asked under the
sign-in; sign in again and the page picks up. Signing out, or someone else signing in, empties it. VoiceOver reads each
line once - its words, then its level, time and part - and says when the feed is lost, when it's refused (with why, in
the same breath: "Not live. Couldn't open the live feed."), and when it's live again after either, and when the kept
lines couldn't be read; when deadwax goes out of reach, the app's own banner line and its "Back online" say it instead.
With Reduce Motion on, new lines don't slide in; at the largest text sizes a line's time, level and part stack over
its words, the part wrapping rather than cut short.

### People

**People** (Settings > Manage > People, for a Navidrome admin with logins on) is the web app's People on the phone:
Navidrome's accounts, changed by deadwax in Navidrome as you. It's a page pushed on Settings, and each person a page
pushed on it. Someone who isn't one of Navidrome's admins sees "Only an admin can open People - it comes with being a
Navidrome admin." and nothing is asked. With logins off, or signed in as the emergency `deadwax`, deadwax's own words
say why People can't work here ("People needs logins on - with them off, anyone who can reach deadwax is its admin.")
- with logins off, with a link to the [Sharing deadwax](sharing.md) guide.

**Unlock People.** It opens locked: "People changes Navidrome's accounts as you, *you*. Navidrome needs your password
for that; deadwax uses it once and doesn't keep it." Type your Navidrome password in **Your Navidrome password** (the
phone's password manager knows it) and tap **Unlock** - "Unlocking…" while it asks. On a plain `http://` address the
note under it says the password crosses your network readable, as Change password's does. A wrong one is said in red
as deadwax says it - "That isn't the password you signed in to deadwax with - if you've changed it since, sign out and
in again." - the field emptied, and the cursor put back in it (not with VoiceOver on, where it would cut off what was
just read). It counts against your sign-ins, as a wrong password at the sign-in screen does.

**Unlocked**: "Unlocked on this device until it's left alone for 15 minutes. Lock ends it now." with **Lock** and
**+** (Add a person) in the bar. If Navidrome isn't the version People was checked with, an amber line says so and to
use Navidrome's own Users page if something doesn't work. Then:

- **Everyone in Navidrome**, you first: each person's name, their user name, what they are ("You", "Admin", "deadwax's
  own account", "Can't sign in to deadwax"), their deadwax sign-ins ("Signed in on 2 devices", "Last signed in 3 days
  ago", "Never signed in to deadwax"), how many albums are in their library - and, in amber, "Navidrome gives them no
  library - they'll see nothing. Choose one for them in Navidrome's Users page." for someone Navidrome gives none.
  VoiceOver reads each row once. Tap one for their page.
- **Known only to deadwax**, when there are any: names deadwax still keeps things for that have no Navidrome account -
  deleted in Navidrome's own Users page, or a removal deadwax couldn't finish - each with what's kept ("deadwax keeps 1
  sign-in, a kept login, 3 pins.") and **Forget…**, which asks first: "Forget what deadwax keeps for *them*? Their
  library list, pins, settings and permissions go - the albums stay in the collection." **Forget** or **Keep it**.

**A person's page**: who they are, as their row has it, then **Permissions** - Get albums, Edit albums, Look after the
library, Everyone's downloads and Settings and the log, each a switch with what it opens under it, and its warning in
amber ("This includes deleting albums from disk, which can't be undone." with Look after the library on, "They can still
play, look through and add what the collection has." with Get albums off). An admin's are all on and can't be changed
("Admins can do everything."), and yours, deadwax's own account's and a reserved name's are locked with deadwax's reason
under them. **Save permissions** sends all five - on only once one differs from what's saved - and "Saved - *they*
have them from their next tap." Under them, the changes deadwax offers for this person:

- **Reset password…** opens a sheet: **New password** and **New password again** (the password manager's new-password
  fields), what's wrong as you type (the same rules as Change password's), the plain-http note, and **Reset password**.
  Done, the sheet goes and their page says "Done. *They're* signed out of deadwax on 2 devices and sign in with the new
  password - their other music apps need it too."
- **Make admin** (or **No longer admin**) asks first, saying what it gives - "In deadwax they'll edit and delete
  albums, … In Navidrome they become an admin too …" - or what they keep. **Make admin** / **No longer admin**, or
  **Keep as it is**. After it the app asks deadwax who you are again, so your own Manage follows.
- **Remove…** opens a sheet saying what goes - in Navidrome, for good, and in deadwax - what stays, and "There's no
  undo. If they might come back, reset their password instead." in red. Type their user name exactly in **Type their
  user name to remove them** (Return only puts the keyboard away): **Remove *them*** is on only once it matches. Done,
  their page goes and People says "Removed *them* from Navidrome and deadwax."

What deadwax won't do for someone is said under their changes, in its words: you can't reset your own password here
("That's you - change your own password in Settings → Account → Change password."), remove yourself or take your own
admin role away, nor change deadwax's own account or Navidrome's last admin.

**Add a person** (the **+**) opens a sheet: "Makes a Navidrome account for an ordinary listener. You can make them an
admin afterwards." **User name**, **Display name (optional)**, **Password** and **Password again**, what's wrong as you
type (lowercase letters, digits, dots, underscores and hyphens; at most 32; not `local` or `deadwax`; the password
rules), the plain-http note, and **Make account**. Made: "Made *them*. Tell them their user name, the password you
chose and deadwax's address (http://…/player/) - their other music apps sign in with the same user name and password."
with deadwax's warning in amber when it gives one, the form emptied, and **Done** to close it. (The web app's Add a
person sits on the page and has a Show passwords box; the phone's is a sheet, and has none.)

**One change at a time.** While one is out its button says so ("Making…", "Resetting…", "Changing…", "Removing…",
"Saving…", "Forgetting…"), the others are dimmed, and the page can't be left by Back or a swipe, nor by tapping Settings
again; a sheet can't be closed. A refusal is said in red, in deadwax's words, with what to do under it when deadwax
names it - "That's a lot of changes in a minute - wait … seconds and try again." after ten. If deadwax's answer never
comes, "deadwax may have finished this - looking again": People is read again to see, and nothing is sent again by
itself. After every change People is read again, and VoiceOver says what came of it once.

**Locked again.** deadwax forgets an unlock 15 minutes after it was last used, and when you Lock, sign out or your
session ends. The phone notices on its own: a little after 15 minutes left alone (time in the background counts),
the page reads People again - or as soon as you come back to it - and Unlock People comes back. If that read fails
(deadwax restarting, say), it's said in red under the list, and nothing more is asked by itself until you pull down,
come back to the app or People, or deadwax answers a change. A change refused because People locked meanwhile brings
Unlock People back at once; a sheet still up says "People locked again - close this and unlock it with your Navidrome
password. The passwords typed here are gone." What you typed in Add a person's names is kept for when it opens again;
a person's unsaved switches are kept too.

**Your password and theirs never stay on the phone**: none is saved, logged or put in an address. Each field is
emptied once it's sent or done with, when you leave People, when a sheet closes, when Now Playing comes up over it,
and when the sign-in screen comes over the app (a sheet goes with it - once a change it sent has answered, if one was
out). Going to the background leaves them, so a password pasted from another app is still there. While deadwax can't
be reached, a page that has read nothing yet says "Managing needs deadwax. This opens once it's back."; one that has
keeps what it showed under the amber line, with every change dimmed until deadwax is back and People has been read
again. Pull down to read it again at any time. With Reduce Motion on, nothing slides; at the largest text sizes
everything wraps.

### Change password

**Change password** (Settings > Account > Change password, with logins on - for anyone who signed in with their own
Navidrome account; not the emergency `deadwax` sign-in, which has no Navidrome password) changes your Navidrome
password from the phone, as the web app's Settings > Account does. It's a page pushed on Account:

- **At the top**: "Your Navidrome password, *you* - the one you sign in to deadwax, Navidrome and Amperfy with. deadwax
  changes it in Navidrome as you, and doesn't keep it."
- **Current password**, **New password** and **New password again** - each hides what you type, and the phone's
  password manager knows the first for your current password and the other two for a new one. No capitals or
  corrections are made as you type. (The web app's third field is called Again, and it has a Show box; the phone has
  neither.)
- **Under them, what's wrong as you type**, once both new fields have something in them - the web app's rules, in its
  words: "A password is at least 8 characters.", "A password is at most 128 characters.", "A password can't have
  control characters in it.", "A password can't be the user name.", "The two passwords aren't the same.", and "That's
  the password you have now - type a new one."
- **Under the fields**: on a plain `http://` address, "This page isn't over HTTPS: a password typed here crosses your
  network readable, as everyone's sign-in does. That's fine on your own network or over a VPN; anywhere else, put HTTPS
  in front of deadwax first." Then, always: "Amperfy and any other app you use with Navidrome need the new password
  too." - before you change it, not only after.
- **Change** (the web app's Save) - only once every rule is met and deadwax is in reach. While it asks it says
  "Changing…", and the page can't be left by Back or a swipe, nor by tapping Settings again: what came of it is said
  here.

**Changed**: "Password changed. You're still signed in here." - or, when your other phones, browsers and devices were
signed in, "Password changed. Signed out of your other device - it signs in again with the new one. You're still signed
in here." (or "your other 2 devices - they sign"), in green, with any warning deadwax gave in amber under it. Every field
is emptied. deadwax signs every other sign-in of yours out and gives this phone a new one at the same moment: the app
keeps it (in the Keychain, as at sign-in) and goes on with it at once, so the music plays on and nothing asks you to
sign in. Amperfy and other apps signed in to Navidrome with the old password need the new one.

**Refused**: deadwax's own words, in red, as the web app says them - the fields kept so you can correct them - with
what to change, when deadwax names it, under it. "That isn't your current password - …": the current one is emptied,
and the cursor put back in it. Navidrome set not to let people change their own details, Navidrome not answering, or
"That's a lot of tries in a minute - wait … seconds and try again." (five tries a minute) are said the same way. A
mistyped current password counts against your sign-ins too, as a wrong one at the sign-in screen does.

**No answer**: if deadwax's answer never comes - WireGuard drops, the Wi-Fi goes, it takes over four minutes - the
page can't tell whether the change went through. It says "deadwax may have changed your password - its answer never
came. If deadwax asks you to sign in again, it did: sign in with the new password. If it doesn't, try again." and asks
deadwax at once who you are: had it gone through, this phone's old sign-in is over, and the sign-in screen comes up
with why. Nothing is ever sent again by itself. The fields are kept. If deadwax said this phone's sign-in was over
while the change was out and no new one came back, the sign-in screen says "This phone's sign-in ended while your
password was being changed - sign in again, with the new password if the change went through." (and nothing more is
said on the page under it).

**Your password never stays on the phone**: it isn't saved, logged or put in an address; only deadwax's new sign-in is
kept. The fields are emptied once it's changed, when you leave the page (going back, another tab), when Now Playing
comes up over it, and when the sign-in screen comes over the app (Change is dimmed under it). While deadwax can't be
reached, the amber line Edit album shows is at the top and Change is dimmed. VoiceOver reads each field once, and says
what came of a change once; at the largest text sizes the words wrap.

**Downloads going at that moment** were asked for under the old sign-in. One deadwax was already sending finishes as
it was; one it hadn't started answering is refused, as the old sign-in is over. The app sees that it went out under the
old one, not the one it has now, and asks for that song again under the new one - the other downloads aren't held up,
and nothing asks you to sign in (check 377). One refused in the moment before the change's own answer reaches the
phone waits for that answer - only that song; the rest carry on - and is asked for again under the new sign-in once
it comes. Had the change not gone through, it is taken as the sign-in being over, as any download's refusal is.
Saving where you are in the queue, and the event log's live feed, carry on under the new sign-in the same way.

### Debug

Debug, under Settings > This phone for an admin, is where Phase 0's test screen lives now:

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
  on and off in Settings > Downloads (this section had its own switch while that was being built). On, it
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
    (Remove)" after you answered Remove to Settings > Downloads' question, "kept them" after Keep Them.
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
    "Not charging" or "Not known" (on the Mac "Plugged in" or "On battery") - and "only while charging" when
    that's on. **Albums out**: how many
    of your library's albums have downloads handed to iOS now (with Only while charging on, never more
    than one).
  - **In the background**: the last five times iOS ran the app in the background for your library,
    newest first - "Refresh · checked, 3 read, 1 album downloading, charging · 4.20 s · 2 h ago" (the
    refresh, or **Charger** for the run iOS starts when the phone is plugged in), or "ended by iOS" (on the Mac
    "ended by macOS", and "plugged in" or "on battery" where the phone says charging),
    "couldn't ask deadwax", "nothing to ask: Download your library is off". "No background runs yet"
    until iOS has run one: iOS decides when, and may not at all. A run before the phone's first unlock
    after a restart does nothing and isn't listed (the Downloads events say so).
- **Library**: how many albums each list had, whether it came new or the kept one still stood, and
  how long it took to come. **Top**: the Library's top row as it was last measured, for when the row
  sits in the Dynamic Island - "row 0 · window 62 · down 62 · nothing presented · SwiftUI 0, safe 0 ·
  after presentation gone": where the row's top was in the app's window, the window's room at its top
  (the status bar's and the island's), how far the row came down, whether a sheet or Now Playing was
  over it then (its room is kept as it was while one is), what SwiftUI itself said of the row, and
  what asked for the measure. "Not measured yet" until the Library has shown.
- At the bottom, how long this install runs. In its last two days, it also says to run install.sh
  before then.

## EQ

The EQ shapes the sound on this phone, **for each output on its own**: your AirPods, wired
headphones, the iPhone's speaker, the car, an AirPlay speaker each keep their own EQ, and the phone
switches to the right one by itself whenever the output changes - AirPods connecting mid-song have
their own EQ from the first sound in them. An output the phone hasn't met before starts **Off**.

Open it from **Settings > Playback > EQ**, or from **EQ** at the right of Now Playing's bottom row, which opens
it in Now Playing's sheet, on its EQ page (**‹ Now Playing** puts the sheet away, as **Done** does on a page opened from it; the strip at its top
moves to the Queue or Info). Either way it opens on the output playing now. On the Mac it's the side panel's EQ tab
(**View > EQ** ⌥⌘E), and Settings > Playback's **EQ** row opens that tab.

**The EQ page**, top to bottom:

- **The output**: its name and "Connected now" (or "Not connected"), and the **EQ** switch. Over
  AirPlay, a note says a change is heard about 2 seconds later. On the phone the output is a button across the
  page - "Output" and its name, "· Not connected" after it for one that isn't - which opens AirPlay's list, as Now
  Playing's does - VoiceOver reads it as the output's name and whether it's connected; and the switch is **EQ on**,
  at the top of Now Playing's sheet beside the **•••** (at the largest text size the switch alone, without its
  words; from Settings, under the output's button). The page's parts are groups, as drawn: Correction, Tone,
  Preamp, Other outputs and Advanced.
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
  page, which stays on that output. Swipe one for **Rename** and **Forget** (not the speaker) - on the phone, touch
  and hold it instead; they're also the output's own page's (its **•••** > **Rename…**, and **Forget This
  Output**), and VoiceOver's actions on the row.
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

**The page follows the output.** Opened from Settings or Now Playing, it changes to the output that's
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

It's only ever a suggestion - nothing changes until you tap **Use**. Tap **Not now** beside it (on the Mac,
swipe it; or use VoiceOver's action) and it doesn't come back for those headphones. It isn't shown offline, or
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

**Headphone Accommodations.** iOS's own Headphone Accommodations (the iPhone's Settings > Accessibility > Audio &
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
output plays, so it's left out." Tap a filter to edit it; swipe it for **Delete** (on the phone, touch and hold
it; or **Delete Filter** in its editor, or VoiceOver's action). On the phone each filter's switch is the purple
one. Leaving the editor with a number still being typed - **Back**, the strip, or the sheet put away - keeps it, as
leaving the field does, if it's in range. Under the filters:

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
  over whatever was showing - over Now Playing, in its sheet on the EQ page: the sheet moves there from the Queue or
  Info, and with a cover full screen that closes first. deadwax gets a copy, and deletes it once read.

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

Every song that starts playing on the phone goes into your play history on deadwax - the one the Queue
scrolls back through, here and in the web app (see [the Queue](#queue)). It goes in at the song's first
sound, the moment Navidrome is told "now playing", skips included:

- **Not a new song**: pausing and playing again, seeking (the arm or the record on the turntable too),
  a wait for the network, a song tried again from where it stopped, or a change of
  [speed](#the-speed). The next song, Previous, Repeat One playing a song again and a tap in the Queue
  are each a new one - though a song started again straight after itself shows as one row.
- **Picked up where you left off**: a queue put back paused in the middle of a song carries on that
  song's play - it was already in the list when it began, on whichever device began it - so it isn't
  added again. Put back at a song's start, it's a new one.
- **Offline**: a song started with deadwax out of reach shows in the Queue at once, and is kept on the
  phone (in your own downloads' store, so closing the app doesn't lose it) until deadwax answers - then
  sent, oldest first, before the [plays](#plays) waiting with it, up to 500 at a time. A week away is
  sent in one go of several batches. If deadwax answers but can't take them just then, the phone tries
  again 30 seconds on, then a minute, two, and so on up to every 10 minutes, and at the next song.
  Signed out, they wait for you to sign in again as the same person; they're never sent for anyone
  else. If the phone can't read that store ("This phone couldn't read its downloads"), the songs you
  start are held while the app is open and sent from there.
- **The newest 100** are also kept on the phone each time they come, so the Queue shows what you played
  lately with deadwax out of reach. Older ones need deadwax.
- **Kept by deadwax, for ever** - with logins on, each person's own; with logins off, one list for
  everyone who uses this deadwax. There's no Clear, here or in the web app. Removing someone in People,
  or Forget, takes theirs with the rest of what deadwax kept for them.

The Queue asks deadwax for the newest songs each time it opens, again when you come back to the app with
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
going back a second time included (until this build, going back again after changing the Queue while
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

Download an album from its page (**Download** in the top •••, or the toolbar's on the Mac), a song from its **•••**, or what's
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

### Settings > Downloads

- **Storage**: what's downloaded ("2.1 GB of 20 GB"), a bar, and "12 albums · 148 songs · 41.2 GB
  free on this phone". **Storage limit**: 5, 10, **20 GB** (the default), 50, 100 GB, or No limit.
  Lowering it below what's here removes nothing you downloaded yourself: new downloads wait for
  room, and it says so in amber. (Albums [your library](#your-library-on-this-phone) downloaded by
  itself make way, from the bottom.) The 2 GB of songs kept from streaming are apart from it. With other accounts' downloads on
  the phone, **Other accounts on this phone** has their size and **Remove** (it asks first).
- **Your library** ("The collection" with logins off): **Download your library**, what it's doing,
  and **Only while charging** - see [Your library on this phone](#your-library-on-this-phone).
- **Download over**, a menu, as Storage limit is: **Wi-Fi only** (the default) or **Wi-Fi and cellular**. Under it,
  what the chosen one does ("Downloads use Wi-Fi alone - never mobile data, a hotspot or Low Data Mode.", or
  "Downloads use mobile data too, whenever there's no Wi-Fi."), then what the phone is on now ("On mobile data now -
  downloads wait for Wi-Fi."), in amber while a download waits for it. Changing it applies at once. Both settings
  are kept on this phone.
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

**Download your library** (Settings > Downloads, off until you turn it on - or Turn On on the Library's
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
  my library - and when you pull down on Settings > Downloads. A check that fails doesn't put off the
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
  more than half of them at once (more than 10) - **nothing goes**. Settings > Downloads asks instead, in
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
  charge" - in an album's download menu, with "Only while charging is on - in Settings > Downloads." under
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
  (the iPhone's Settings > General > Background App Refresh), or Low Power Mode, can stop it. It follows the same
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

- **The Library's Albums page is Downloaded**, under the same buttons (Downloaded's own goes, the Albums page being
  it, and Yours | All is put away until deadwax is back - on **All**, All stays as it was, showing what's in hand,
  with Yours | All to come back by): headed Downloaded, with
  Downloaded playlists and "Only downloaded albums play until deadwax is back." at its top. It changes
  only when you're not looking at it (another tab, an album open over it, the app in the background), so
  it never moves under your finger; until then the list you were on stays, with every album not on the
  phone dimmed. ••• > **Your albums** (or **Albums**, without a library of your own) takes you to the full
  list, dimmed but for what's here; ••• > Refresh checks whether deadwax is back; ••• > **Shuffle
  downloads**, or a pull, shuffles the songs on the phone (see [Shuffling your
  library](#shuffling-your-library)).
- **The Queue** dims the songs that aren't on the phone; a tap on one does nothing (see [the Queue](#queue)).
- **An album's page** shows what's on the phone, dims the rest, and Play, Shuffle and a pull down play only
  the songs here ("Pull to shuffle the songs on this phone"). An album with nothing here says "This album isn't on
  this phone - it plays once deadwax is back."
- **Songs**: the songs already fetched stay, the ones not on the phone dimmed, and no more are fetched (see
  [Songs](#songs)).
- **Search**: a list already drawn for the words stays, what isn't on the phone dimmed; new words wait for
  deadwax: "Search works once deadwax is back." (see [Search](#search)).
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
- **The Queue** still shows what you've played: the newest 100 the phone kept, and every song started
  since, here at once (see [What you've played](#what-youve-played)). Scrolling further up asks deadwax
  for more, and says it couldn't.
- Plays, and the songs you started, are kept and sent later; downloads waiting carry on once the phone,
  or deadwax, is back.

## The checks

**Written while the tab was called You.** Where the checks below send you to it, they name the tab and its pages as
Settings has them now - Settings > Getting albums, Playback, Downloads, Account and About, and Debug under Settings >
This phone - and the web app's managing pages as its desktop sidebar has them, under Manage. Read a list of ticks as a
row with a menu ([Settings](#settings)). Checks 310-319 are the new layout's own.

Phase 1 exists to answer these on the phone. Note what you see for each.

1. **Sign in and count.** Sign in with your Navidrome account. The Library shows your albums: does
   the count above them match the web app's Library? And All albums against the web app's All music?
   If you're an admin, Settings > This phone > Debug > Library says how many each list had and how long it took to
   come: note the times.
2. **The joins.** Find the test album under All music > All albums ("start test" in Find), tap song 9
   and let it run into song 10: one unbroken tone, with no gap, click or blip. Then a live or
   continuous album you know well: is every join seamless? Then previous: in a song's first 3 seconds
   it goes to the song before, and after that it starts the song again.
3. **Normalization, Automatic.** With Normalization on Automatic (Settings > Playback), play an album. Info
   > About > Sound > Normalization says "Album volume matching, ..." with the same change for every
   song of it. While it plays, add a song from another album with **•••** > Add to Queue (Play Next until
   16 Nov): when it plays, Info says "Song volume matching, ...". (The app had no Search yet, so a song added
   stands in for a song played on its own.) Then set Normalization to Off and play the album again: Info
   says "Off". Note how long the first song of an album never measured before takes to start.
4. **Quiet and loud.** A quiet old album, then a loud new one (add it with Add to Queue): about the same
   loudness, and no distortion on the quiet one brought up. Info says how much each was changed.
5. **Up Next.** While an album plays: add a song with Add to Queue, then another, then open Up Next. Are
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
- **Repeat One, or a change in Up Next (move or take out a song, Add to Queue), in a song's last two or
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
  measure of free space, the one iOS uses for what it would make room for. Does the iPhone's Settings > General >
  iPhone Storage agree with what Settings > Downloads says, and does anything else on the phone complain?
  When the phone dips under 2 GB, Debug says "under the reserve · confirming", then after a few minutes
  "giving way" - does only the bottom album go, and only as much as was needed?

### Phase 2's checks: downloads

1. **An album, on Wi-Fi.** Tap an album's download arrow: the ring fills, the line under the title
   counts the songs, and Settings > Downloads shows it under Downloading with a bar. Once it's here: the
   filled arrow, "Downloaded · ... MB" in its menu, and Settings > Downloads lists it with **Checked** (or
   Checking… for a moment). Does a 24-bit 192 kHz album check in reasonable time (Debug > Downloads)?
2. **Locked.** Ask for a big album, lock the phone and leave it for ten minutes: is it all here?
3. **Wi-Fi only.** On mobile data, ask for an album: "Waiting for Wi-Fi", and Settings > Downloads' line
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
   Settings > Downloads says downloads stopped, and they carry on.
10. **The storage limit.** Set it to 5 GB with more than that here: the amber line, and nothing
    removed. A new album waits for room.
11. **Sign out and in.** Your downloads stay through a sign-out; signed in as someone else, they're
    "Other accounts on this phone".
12. **Remove All Downloads**: it asks, then the screen is empty and the Library's Downloaded row goes,
    and the iPhone's Settings > General > iPhone Storage > deadwax shows the space back.
13. **A downloaded album opens at once**, online too: no spinner before its songs.
14. **deadwax up, Navidrome down** (Navidrome's container stopped): the Library's "isn't available"
    screen has On this phone > Downloaded under it, and a downloaded album plays.
15. **The strip under every bar**: on the Library (with Find), an album's page and Settings > Downloads,
    offline, the strip sits under the bar and the list scrolls under it without showing through.
16. **VoiceOver and the largest text size**: the download button ("Download, Downloading, 40
    percent"), a song's actions, the strip as it comes and "Back online" as it goes; at the largest
    text size, Settings > Downloads and an album's page with nothing cut off.
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
19. **Up Next's marks.** Play a downloaded album, then add one that isn't with Add to Queue; open Up Next: the
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
  bubble, filled and purple while on. (Since R3 the row is Queue, Lyrics, AirPlay, Info and EQ, each a
  word under its icon, the ••• beside the look button at the top: checks 532-538.)
- **P2 Opening.** **Not done yet.** Play "Roads", open Now Playing, tap Lyrics: the lyrics take the cover's place, the
  title and the buttons don't move, the line being sung is white and about a third of the way down,
  and the lyrics move up smoothly as each line comes. Tap Lyrics again: the cover. Scroll the lyrics
  hard: Now Playing never starts closing; a swipe down from the top row (Close's, since R4b) closes it.
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
- **P7 Larger Text.** The iPhone's Settings > Accessibility > Display & Text Size > Larger Text at the largest:
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
test (Settings > This phone > Debug > EQ); they still hold. Install the usual way, not with `--debug`: a Debug build's
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

- **E1 Playback's row.** Settings > Playback: after Normalization, **EQ**, with "iPhone speaker" under it and
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
  Off - flat. Put them back in and play: Bass Boost again from the first sound. Then Settings > This phone > Debug > EQ:
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
- **E16 The largest text.** The iPhone's Settings > Accessibility > Display & Text Size > Larger Text at the
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
- **E21 Headphone Accommodations.** If you use Headphone Accommodations (the iPhone's Settings > Accessibility >
  Audio & Visual), turn it off with a correction on: the two stack otherwise.

### Advanced's checks (app 0.5)

AirPods with an AutoEq correction on (E17), unless it says. Import and export need nothing of
deadwax.

- **E22 Advanced on.** At the bottom of the EQ page, turn **Advanced** on: the curve grows, with a
  handle for each filter; Correction lists the filters, lowest first; **Preamp** after Tone says
  "Automatic". Then Settings > This phone > Debug's EQ section, **Render**: tell me both numbers.
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
Settings > This phone > Debug > Test sounds > **The record's engine beside the song**. Install the usual way, not with
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

- **1 The settings.** Settings > Playback: Gapless, then **Now Playing opens as** (Cover ticked), then
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
  row moved; tap it - 1x, and it's gone. The mini player shows nothing. (Since R3 the chip sits just
  above the bottom row, over the gap between AirPlay and Info, clear of every button: check 536.)
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
  one is counted in Debug. Turn on Airplane Mode and play a downloaded album, with Settings > This phone > Debug >
  Downloads' **Starts waiting to be sent** a look away: it goes up by one as each song starts. While
  one plays: pause and play, drag the arm on the turntable, take hold of the record and let go, move
  the speed fader off 1x and back, and lock the phone for a minute - the count doesn't move. Next: up
  by one. Airplane Mode off: it goes to 0.
- **44 Picked up.** Play a downloaded album, pause it in the middle of a song, and close the app (swipe
  it away). Turn on Airplane Mode and open it: the song is back, paused. Note **Starts waiting to be
  sent**, press play, look again: the same - the song carries on its play rather than starting a new
  one. Next: up by one. Airplane Mode off afterwards.
- **45 Offline.** Turn on Airplane Mode and play three downloaded songs: each shows in Up Next as it
  starts, and Settings > This phone > Debug > Downloads counts them under **Starts waiting to be sent**. Close the app
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
your library by itself, when nothing downloaded yet. Settings > This phone > Debug > **Your library**, with **Follow
your library** on - in the build after it, that switch is Settings > Downloads' **Download your library**,
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
- **L0f Would fit.** Note the "… fit in 20 GB" line; set Settings > Downloads' **Storage limit** to 5 GB:
  the line says fewer fit in 5 GB. Back to 20 GB: as before.
- **L0g Nothing else moved.** Settings > Downloads is as it was, nothing is downloading that you didn't ask
  for, and Debug's Downloads counts haven't moved.

### Your library's checks (50-63)

These come with the builds that download your library by itself (54 and 61-63 with app 0.9). Debug's own switch is
gone: **Settings > Downloads > Download your library** does what it did, and downloads too, so L0a-L0f above now run
with it (L0g no longer holds: things download). Note what you see for each; the Downloads events in Settings > This
phone > Debug have a "library" line for everything it asks for and lets go, and why.

- **50 Overnight.** At home on Wi-Fi, turn on Download your library with the phone on charge, open the app, then lock
  the phone: in the morning your library is downloaded - or as much as fits, said in numbers in Settings > Downloads.
  Note the time it took, and the size, and what Settings > This phone > Debug > Your library > In the background
  lists. (If little came, try once more with the app open and Auto-Lock off: that tells iOS's background apart from
  the app's.)
- **51 A star elsewhere.** Add an album in the web app (or star one in Amperfy): within 15 minutes of
  the app being open, or straight away when you come back to it, it starts downloading.
- **52 An unstar.** Remove an album from your library in the web app: it stays on the phone at the
  first check that misses it, and goes at the next check ten minutes or more later (pull down on Settings >
  Downloads to check now). Try it once more with an album you'd also downloaded a song of yourself:
  that song stays.
- **53 Add and Remove here.** **Add to my library** on an album's page: it starts downloading within
  seconds (if it fits). **Remove from my library** on one it downloaded: the line under the button says
  "Its download goes from this phone too.", and it goes within seconds.
- **54 Only while charging.** Turn it on (Settings > Downloads, under the line of what fits) and unplug the
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
  nothing downloads again, and Settings > Downloads shows it off.
- **60 An empty list.** Only if it can be arranged safely - unstar everything on a test account, or
  stop Navidrome's music folder from mounting: nothing goes from the phone, and Settings > Downloads asks.
  Keep Them keeps them, and the question goes. If you try Remove: still nothing goes at once, and the
  albums go only if a check ten minutes or more later says the same.

- **61 In the background.** Add an album in the web app on the Mac, and leave the phone locked and not
  playing for an hour (the app not swiped away): note whether it came down without opening the app.
  iOS decides when, and may not at all - Settings > This phone > Debug > Your library > In the background says whether
  iOS ran the app, when, and what came of it. Please send me those lines either way.
- **62 Unplugged overnight.** With Only while charging on, start a big library downloading on the
  charger, note how many albums are on the phone (Settings > Downloads > Downloaded), then unplug the phone
  and lock it. In the morning: at most one album more than when you unplugged, and the rest say
  "Waiting for the phone to charge". Then plug it in overnight with the app closed: note in the morning
  whether it carried on by itself (In the background has a **Charger** line if iOS ran it).
- **63 VoiceOver and the largest text.** With VoiceOver on, and again at the largest text size
  (the iPhone's Settings > Accessibility > Display & Text Size > Larger Text): Settings > Downloads' Your library section
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
- **67 Add to Queue from a playlist** (Play Next until 16 Nov). A song's •••: Add to Queue queues that song;
  the ••• at the top queues the whole playlist. Go to album from Now Playing opens the song's own album, whole.
- **68 Changed elsewhere.** Add a song to a playlist in the web app or Amperfy; back on the phone, go
  back to Playlists and open the playlist again: it has the song. Delete a playlist in the web app with
  its page open on the phone, then pull down on it (since check 286, ••• > Refresh: a pull shuffles): it says it
  isn't on Navidrome any more.
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
  becomes a ring, the page says "Downloading - 4 of 12 songs" as they come, and Settings > Downloads has its
  row ("3 of 12 songs to go") with a bar. Once all are here: "This playlist is downloaded - it plays with
  no connection." Then Airplane Mode, force-quit the app and open it again: in the Library (it may open
  on Downloaded), Downloaded has **Downloaded playlists** with its count; the playlist opens, every song
  is bright, and Play, Shuffle and a song's tap play it - across albums, each with its own cover. Library
  > Playlists, still in Airplane Mode: it's listed, bright.
- **78 Kept in step.** Add a song to it in the web app, then open it on the phone: the song comes (the
  ring, then here). Take a song out in the web app and open it again at once: the song has left the
  page, but it's still on the phone - the song count under Storage in Settings > Downloads hasn't dropped;
  ten minutes or more later (open it again, or leave the app open) it's gone from the phone. Take a song
  out with **Edit** on the phone, Done: it's gone from the phone at once.
- **79 What stays.** Download a song of the playlist by hand first (its •••), and an album one of its
  songs is on. Download the playlist; then a song only the playlist brought: its ••• says "Downloaded
  with …" and has no Remove Download. **Remove Download** on the playlist (the mark, or its •••): the song
  you downloaded yourself and the album's songs stay; the rest go. With Download your library on and an
  album of your library in the playlist, turn the switch off: the playlist's songs stay.
- **80 Where it is.** Library > Downloaded > **Downloaded playlists**: the playlist, by name. Settings >
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

- **85 A song you played, tapped.** Play the album from song 1 to song 5 (Next is fine), then add two songs
  from another album with Add to Queue. Open Up Next and tap song 2 above the song playing: it plays at once,
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
  Settings and back: the same page. Scroll a long way down and tap the Library tab: the page goes to its top.
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

### Songs' checks (112-120)

**Not done yet.** These come with the build that adds Songs and All songs' Shuffle - **app 0.10 (10)**,
the end of Phase 4. Check 113 on wants a few hundred songs or more; 117 wants logins off, or the
break-glass `deadwax` sign-in.

- **112 The version.** install.sh says "Installed deadwax 0.10 (10), runs until …", and Settings > About reads
  0.10 (10). The Library opens as before: the order you'd arranged, the page you were on.
- **113 All songs.** With logins on, the switch is still Albums | Playlists | Artists, and Edit order lists
  those three. ••• > All music: All albums, All artists, All songs. All songs: every song, each with its
  cover, title and "artist · album", in the web app's Library > All songs order. Scroll a long way, fast:
  more songs come before you reach the end, never stopping at 100 or 200. At the very end, "12480 songs"
  (your count) at the top - the web app's number.
- **114 A row.** Tap a song: its album's page. Back: All songs where you left it, nothing fetched again.
  A song's •••: Add to Queue - Up Next has it next, with nothing added before it; Add to a playlist… adds it;
  Download downloads it. Does the music start from Add to Queue with nothing playing?
- **115 Find.** On All songs, type "roads": the songs Navidrome finds for it, by title, artist or album -
  songs further down the list than you've scrolled among them. Type a word quickly: one list, not one a
  letter. Clear Find: every song again, from the top - a spinner first, never "No songs yet.". Nonsense:
  "No songs match “…”."; type on from it: the line keeps naming what was searched until the new words are.
- **116 All songs' Shuffle.** Open All songs: Shuffle at its top ("Getting ready…" for a moment the first
  time). Tap it: the collection shuffled - songs of albums not in your library among them - starting the
  moment you tap. Press Next 160 times or so: it keeps going past 200. Then ••• > Shuffle on the Library:
  only your library's songs. Pull down on All songs: it refreshes, no shuffle - the spinner staying until
  the songs are back.
- **117 Songs as a page** (logins off, or the break-glass `deadwax`). The switch reads Albums | Playlists |
  Artists | Songs - Songs at the end of an order you'd arranged before. Swipe to Songs: every song. Pull
  down: the collection shuffles, as on the other pages. The ••• has no order or layout on Songs; Refresh
  fetches it again from the top. Edit order lists four: drag Songs first, Done, force-quit and open - the
  Library opens on Songs. Sign in with logins on again: no Songs page, the others in your order, and the
  Library on the first of them.
- **118 Find on the Songs page.** Type part of a title: Navidrome's songs for it; switch to Albums and back:
  each page keeps its own words, and Songs' list is still the found one.
- **119 Offline.** With All songs scrolled some way, turn on Airplane Mode: the songs stay, those not
  downloaded dimmed (a tap does nothing); scrolling to the end fetches no more and shows no spinner.
  Shuffle reads "Shuffle downloads" and plays only songs on the phone. The Library's ••• has no All
  music offline, so for the empty page use logins off (117's): force-quit, open in Airplane Mode and
  swipe to Songs - "Songs show here once deadwax is back." And at the very end of what All songs has
  fetched, turn on Airplane Mode, wait, and turn it off without scrolling: more songs come.
- **120 VoiceOver.** A row reads "Roads, Portishead · Dummy, opens its album" (a song with no album, its
  title and line alone), its ••• "More for Roads", and a dimmed one adds "Not on this phone". All songs'
  Shuffle reads "Shuffle". With logins off the switch reads Albums, Playlists, Artists and Songs.

### Search's checks (121-129)

**Not done yet.** These come with the build that adds Search's first half - your library's (still app
0.10). Check 126 wants logins on and a library of your own; the rest work either way. The web app's Search
is the one to compare with: it should give the same lists.

- **121 The tab.** The tabs read Library | Search | You (Settings now). Search shows the field and "Search your
  library." (with logins on and a library of your own, "Search your library and the collection."). Open an
  album from a list, then tap Search: back to the list; tap it again at the list: its top.
- **122 A song you have.** Type "roads" (or a song of yours): Top results and Songs list it, with ▶ after
  it. Tap it: it plays from that song, its album's songs after it in Up Next - in the tap, no wait. A song
  further down Songs (See all) with no ▶: its album's page opens.
- **123 Top results, as the web's.** Type the same three searches in the web app's Search and on the phone -
  "portishead", "roads", "glory box" (or your own artist, song and album): Top results are the same three,
  in the same order, and each section the same rows (the phone shows 2 artists, 3 albums and 3 songs, as
  the web app does on a phone).
- **124 Album and artist.** "dummy portishead" and "portishead dummy": Dummy first. Tap an album: its page.
  Tap an artist: theirs. Back: the list as you left it, the words still in the field.
- **125 The chips.** Albums: every album found (up to 50), More from your library when there are more; All:
  the list as it was. See all under Songs: the Songs chip, every song found.
- **126 Whose** (logins on, a library of your own). A song of an album you haven't added says "in the
  collection", after your own in its section; your own, "in your library". Add an album to your library in
  the web app, then search it on the phone: "in your library".
- **127 Typing fast.** Type "portishead" quickly, then delete back to "port" and on to "portis": one list
  at a time, never a row jumping under your finger while you watch. Clear the field: the hint again.
- **128 Offline.** With a list drawn, turn on Airplane Mode: the list stays, the songs not downloaded
  dimmed (a tap does nothing), a downloaded one plays. Type new words: "Search works once deadwax is back."
  Turn Airplane Mode off: the new words are searched.
- **129 VoiceOver.** A song's row reads its title, its line ("Song · Portishead · Dummy · in your library"
  in Top results), and "plays it from its album" (or "opens its album"); the list found is announced ("In
  your library: 1 artist, 2 albums, 11 songs."); a chip as it's chosen ("Showing albums.").

### Search's checks, slice 2 (130-143)

**Not done yet.** These come with the build that adds MusicBrainz's albums to Search, and the album you don't
have (still app 0.10). Check 137 wants deadwax 2.1.24 or later (`:experimental` for now) and then 2.1.23; the
rest work on either. As with 121-129, the web app's Search is the one to compare with.

- **130 The hint.** Search shows "Search your library and albums you don't have yet." (with logins on and a
  library of your own, "Search your library, the collection, and albums nobody has yet.").
- **131 An album you don't have** (the plan's second check). Type an album you don't have, with its artist:
  a moment after you stop typing it's in Albums, after yours, with its cover, its artist and year. Tap it: its
  page opens - the cover, the title and artist, "1994 · Album · not in your library" (its own year), Pressing,
  and the tracklist. Back: the list as you left it.
- **132 Pressings.** On that page tap **Pressing**: every pressing, the usual one ticked, each with its format,
  year, country and label and how it compares ("+1 bonus track: …"). Pick another: its facts and tracklist
  under Pressing, a track it adds marked **Bonus**, one it leaves out under "Not on this pressing", the line
  above the tracklist saying what it is ("This pressing adds 1 track"). An album of more than 30 pressings
  (a famous one): the filter; type "JP" and it says how many match.
- **133 Held, and maybe.** An album of yours with no MusicBrainz ids (a folder never matched to a release):
  its MusicBrainz row says "maybe in your library", and its page "maybe in your library" dashed after its
  line, with "You may already have this - …" under Pressing. If MusicBrainz finds an album of yours that
  Navidrome's search didn't list, it's drawn among yours, "in your library"; tap it: your album's page.
- **134 The moments, as the web's.** Type "portishead" (or an artist of yours) and watch: Top results
  first, "Searching…" where the sections go, then the sections - nothing moving under your finger. The same
  words in the web app: the same steps and, once they're in, the same rows.
- **135 An artist alone.** "portishead": Albums ends with "Studio albums and EPs - See all for everything
  they made."; See all under Albums: everything MusicBrainz has of theirs, live albums and compilations too,
  after yours.
- **136 Short words.** Type "ab": your library's rows, and "Type a little more, or press Search, to find
  albums you don't have yet." where the albums would go. Press Search: the albums are asked, and land.
- **137 Covers.** On deadwax 2.1.24 or later: the albums you don't have show their covers, in the list and on
  their page. On 2.1.23: the empty square in their place - nothing else changes, and nothing says an error.
- **138 Offline.** With a list drawn, turn on Airplane Mode: the albums you don't have go, yours stay. On an
  album you don't have's page, Airplane Mode on: the page stays as it was, and Pressing still chooses among
  its pressings. Airplane Mode off: the albums you don't have are back in the list.
- **139 VoiceOver.** An album you don't have's row reads its title and its line ("Portishead · 2008"); the list
  is announced as it comes in ("In your library: …", then "Also found: 3 albums."). On its page, **Pressing**
  reads the pressing chosen; in the picker, the one ticked reads as selected.
- **140 Typing offline.** Airplane Mode on, type new words ("portishead", then "ab"), and wait a few seconds:
  "Search works once deadwax is back." stays - never an empty list. Airplane Mode off: the words are searched,
  your library's rows drawn in the list, never left behind "Show 3 from your library".
- **141 The places hold their height.** Words whose albums are slow to come (a busy evening for MusicBrainz,
  or the Wi-Fi throttled): watch the "Searching…" line in Albums become the albums, **Show 2 more albums**, or
  the failure with **Try again** at its end - the sections below never move. The same at the largest text size
  (Settings, Accessibility, Larger Text): one line, the words cut short with "…", Try again still on it.
- **142 A held album, left.** Tap an album of yours that MusicBrainz found (the row spins), and before it opens
  tap the Library tab: Library stays as it was, and back in Search nothing has opened. Tap one again and,
  while it spins, open another row: only that row's page opens.
- **143 Covers, back online.** Airplane Mode on: scroll the Library's Albums to ones whose covers haven't shown
  yet (empty squares), and on an album you don't have's page pick a pressing you haven't looked at (the album's
  cover stays). Airplane Mode off: those covers load where you are, without scrolling away or leaving the page,
  the pressing's own cover in place of the album's if it has one. An album with no cover at all stays the empty
  square.

### Search's checks, slice 3 (144-155)

**Not done yet.** These come with the build that adds MusicBrainz's artists and songs to Search, and an
artist you don't have's page (still app 0.10). Compare with the web app's Search, as for 121-143.

- **144 An artist you don't have.** Type an artist none of whose albums you have: Artists lists them after
  yours, their line saying who they are ("Bristol trip hop group · Group · GB"). Tap them: their page - their
  name, "Group · Bristol · since 1988" under it, then Albums with **Studio only** on, their studio albums
  newest first, each with its cover and "1998 · not in your library". The same artist in the web app: the
  same albums in the same order. Tap one: the album you don't have's page. With the largest text size (Settings >
  Accessibility > Display & Text Size > Larger Text), open another artist's page: Albums doesn't move down as
  the line under their name comes in.
- **145 An artist you have, once.** Type an artist you have ("portishead"): Artists shows yours once, with
  its albums in your library - never a second row for them from MusicBrainz - and other artists of that name
  below it. Type "dummy portishead": no artists you don't have.
- **146 Studio only.** On that page turn **Studio only** off: their live albums and compilations join the list
  ("2008 · Live album · not in your library"), the list on screen until they're in. Go back and open the page
  again: Studio only as you left it, and the albums there at once. An artist with only live albums, Studio only
  on: "No studio albums found - turn off Studio only to see them all."
- **147 Their albums you have.** On an album you don't have's page whose artist isn't in your library, tap the
  artist: their page. On a MusicBrainz artist's page, an album you have is ticked, "in your library" (with "2
  pressings" if you have two); tap it: the row spins, then your album's page.
- **148 A song you don't have.** Type a song you don't have with its artist ("teardrop massive attack"): Songs
  lists it after yours, "Massive Attack · Mezzanine". Tap it: the albums it's on open under it, the studio
  album first ("Album · 1998"), compilations and live albums behind **On 4 compilations and live albums**;
  tap that and they show. Tap the song again: they fold away. The same words in the web app: the same song,
  the same albums in the same order.
- **149 The song on its album.** Tap one of those albums: its page opens with a pressing that has the song
  chosen, the song's track tinted with a bar at its edge, brought into view if it's below the screen. Choose
  another pressing: your choice stays, the song marked wherever it's on it. On a slow connection, open
  another song's album and scroll down before its tracklist comes: the page stays where you put it. Open
  another, switch to the Library tab before its tracklist comes, then come back to Search: the song is
  brought into view as you do.
- **150 A song you have, once.** Type "roads portishead" (a song of yours with its artist): Songs shows your
  Roads with ▶, and no Roads by Portishead from MusicBrainz under it. Type "portishead" and tap the Songs
  chip: your songs, then "Type a song's title with the artist (“roads portishead”) to find songs you don't
  have yet."
- **151 A song in Top results.** Type a song you don't have with its artist, and wait for it to lead Top
  results: "Song · Massive Attack · Mezzanine". Tap it: Mezzanine's page, the song marked.
- **152 A song's album you have.** A song MusicBrainz finds on an album of yours (one Navidrome's search
  doesn't list): under the song, that album says "in your library"; tap it: the row spins, then your album's
  page. Tap it and switch to the Library tab before it opens: nothing opens there, nor back in Search.
- **153 Offline.** With a list drawn, Airplane Mode on: the artists and songs you don't have leave it, yours
  stay; off: they're back. On a MusicBrainz artist's page, Airplane Mode on: "Their albums show once deadwax
  is back." where the albums were, and no Studio only; off: their albums again.
- **154 Left before it opens.** On a MusicBrainz artist's page tap an album you have (it spins) and, before
  it opens, switch tab or open Now Playing: nothing opens over what you went to, nor when you come back.
- **155 VoiceOver.** A song you don't have reads its title and line, then "Shows the albums it's on."; open,
  "Hides the albums it's on."; its fold, "Shows them.". On the album opened from it, the song's track reads
  "…, the song you searched for". On an artist's page, a row reads its title and line ("Mezzanine, 1998 ·
  not in your library"), and Studio only says whether it's on.

### Search's checks, slice 4 (156-165)

**Not done yet.** These come with the build that adds what's saved, the kept answers and More from MusicBrainz -
**app 0.11 (11)**, the end of Phase 5. Compare with the web app's Search, as for 121-155.

- **156 The version.** install.sh says "Installed deadwax 0.11 (11), runs until …", and Settings > About reads
  0.11 (11). Search opens as before: the field, and the hint under it.
- **157 What's saved, at once.** In the web app search an album you don't have ("roseland nyc live"), so deadwax
  has MusicBrainz's answer saved. On the phone type the same words: the album is in the list with your library's
  rows, before "Searching…" would have gone - in Top results if it fits best, and in Albums. VoiceOver: "Found
  earlier: 1 album.", then "More found: …" or "Nothing more found." once MusicBrainz has answered. Nothing drawn
  moves when it does.
- **158 Saved, then more.** Type words for which deadwax has some albums saved and MusicBrainz finds more: the
  saved ones are drawn first, MusicBrainz's after them, none twice. The same words in the web app: the same
  rows in the same order.
- **159 MusicBrainz away under what's saved.** With deadwax unable to reach MusicBrainz (or past its rate
  limit), type saved words: what's saved drawn, and under it "Showing earlier results - searching for more isn't
  working right now." with **Try again**; tap it once MusicBrainz is back: its rows added below.
- **160 A chip's rows stay put.** Type an album's words and tap **Albums** at once, then watch while MusicBrainz
  answers: what's saved first, MusicBrainz's albums below it, and a row once drawn never moves - at the largest
  text size too. Tap **All** and **Albums** again: the same rows, in the same places.
- **161 More albums.** In the Albums view of words with many albums ("live"): at the foot, **More albums**; tap it:
  "Loading…", then up to 12 more below, nothing above them moving, VoiceOver saying "12 more albums found" (fewer
  when some are yours; a page all of yours says "The next 3 albums found are all in your library already."). Keep tapping: the list grows a page
  at a time; at the end "No more results." or "That's all for this search - add a word to narrow it." The same
  in Artists (**More artists**) and Songs (**More songs**).
- **162 More, left behind.** Tap **More albums** and type a letter before it comes: the page doesn't land under
  the new words, and nothing is said of it; delete the letter: **More albums** again, not "Loading…". On a slow
  connection, tap **More albums**, then the **Songs** chip and **More songs**, then **Albums** again: More albums
  still asking, then its page - never stuck on "Loading…". On a slow connection, tap **More albums** and, with
  "Loading…" showing, Airplane Mode on: the button and MusicBrainz's rows go; off: they're back, More with Try
  again or the page.
- **163 Words searched before.** Search some words, then others, then the first again: the first list is drawn
  whole as your library's rows come, with no "Searching…" for MusicBrainz. An hour later (or after closing the app
  by swiping it away), the same words: "Searching…" again, MusicBrainz asked afresh.
- **164 Offline.** Airplane Mode on, type words searched earlier this session: "Search works once deadwax is
  back." - nothing drawn from the answers kept; off: searched, your library's rows with the rest.
- **165 VoiceOver in a chip's view.** Tap **Albums** with words typed: "Showing albums.", then "In your library: 2
  albums.", then what MusicBrainz and what's saved brought ("Found earlier: 1 album. More found: 3 albums."), each
  once. More's button reads its words ("More albums", "Loading…", "Try again").

### Requests' checks, slice 1 (166-179)

**Not done yet.** These come with the build that adds Requests - still **app 0.11 (11)**, the first part of Phase 6.
Compare with the web app's Requests on the Mac: the phone should show the same rows, in the same order, in the
same words. Check 175 wants logins on; the rest work either way. Check 167 gets its album in the web app; getting
one on the phone is checked from 180.

- **166 The tab.** The tabs read Library | Search | Requests | Settings, Requests' icon an arrow into a tray. Tap it:
  the heading Requests, and Clear done at the top right, dimmed with nothing to clear. With nothing ever asked
  for, "Nothing requested yet" and "Albums you get show here while they download, and once they've arrived - find
  one in Search and tap Get." A spinner shows only until deadwax first answers. With a long list and something
  playing, scroll to its end: the last card clears the whole bar at the foot, the mini player at its top included.
- **167 A download from the web app.** In the web app, Get an album. On the phone, Requests: its row under
  Waiting ("starting", or "4th in their queue"), then under Downloading with its cover, the bar and "3 of 11 files
  · 1.2 MB/s" - the web app's speed, within a moment. The data line doesn't jump as the speed comes and goes, at
  the largest text size too.
- **168 The badge.** With the Library shown and something on its way, Requests' badge counts it - the web app's
  count, a small purple square over the icon's top right corner, as on the web app's tab bar - and at 0 there's
  none. At the largest text size it grows and stays clear of the tab's name. With VoiceOver, the tab reads
  "Requests, 2 arriving": note what it says if not.
- **169 Filed.** Let the download finish: under Done, "In your library · just now", and the badge goes. Search the
  album's words: it's yours ("In your library"), with no pull.
- **170 Play from Done.** About 10 seconds after it's filed, tap **▶** on its Done row: the album plays from its
  first song at once, in Up Next as from its page. Tap the row itself: the album's page opens on the Requests tab;
  Back is Requests. Close and reopen the app: ▶ on a row done before it opened plays at once.
- **171 Opening, left behind.** On a slow connection, tap a Done row below the first five, then tap Library before
  the page opens: nothing opens over the Library, and nothing opens by itself back on Requests. The same with Now
  Playing opened meanwhile. A row that can't open says why under it.
- **172 Cancel, asked first.** Tap ✕ on a waiting download: the question in the card, **Keep it** and **Cancel
  download**; tap ✕ again: it closes. Tap ✕ on another card while one asks: only the new one asks. Tap **Cancel
  download**: the card dims, "cancelling…", then goes to Needs attention as Cancelled. In Settings > Getting albums turn
  **Confirm before cancelling** off: ✕ cancels at once. Turn it back on.
- **173 Another source and Same source again.** A download under Needs attention with sources left: **Another
  source · 2 left**; tap it: both buttons wait, "Trying another source…", then the row moves to Waiting, a try on.
  **Same source again** on one a peer stopped: "Trying again…" - and if it's refused, why in red under the reason.
- **174 Clear done.** Tap **Clear done**: the Done rows and the finished ones under Needs attention go at once and
  stay gone; the web app's Requests agrees after its next look.
- **175 Logins on.** As a user, a download someone else asked for too: "Someone else asked for it too", its ✕
  read as "Leave …", the question "Leave this download? …" with **Leave it** - it goes from your list and carries
  on in theirs, and VoiceOver says "…: left - it carries on for whoever else asked". As an admin: "Asked by you
  and ethan", and **Cancel for everyone**. As someone without Get albums: no buttons under Needs attention, and
  "Getting albums is off for you - ask an admin."
- **176 Offline and the background.** Airplane Mode on with Requests showing: the offline banner and "Requests
  show once deadwax is back." - no rows, no badge, Clear done dimmed. Off: the rows back at once, then current.
  With something on its way and music playing, put the app in the background for a few minutes and bring it
  back: the board is current within a moment, as if it had been watching.
- **177 Twice a second, and VoiceOver.** Leave Requests open over WireGuard for ten minutes with a download on its
  way: does it keep up, and what does it cost the battery (the iPhone's Settings > Battery)? With VoiceOver on, watch a
  download move from Waiting to Downloading: "…: downloading" is heard, and VoiceOver stays where it was. Open and
  close a card's question at the largest text size: does the row jump?
- **178 Now Playing over the tabs.** With a download on its way and the Library shown, play something and open Now
  Playing; wait a few seconds and close it. Without opening Requests, the badge still counts as the download moves,
  and goes once it's filed. The same with Now Playing opened from Search, and opened twice in a row.
- **179 The largest text** (the iPhone's Settings > Accessibility > Display & Text Size > Larger Text, all the way up). On
  Requests the covers stay small and each title reads, on up to three lines; the ✕ and ▶ stay small. A
  card's question puts **Keep it** over **Cancel download**, and Needs attention puts **Another source · 2 left**
  over **Same source again**, each read whole. Nothing overlaps, and the last card clears the whole bar at the
  foot, the mini player included; the badge sits clear of the mini player above it. Tap a Done row below the first
  five: its album opens; go Back and tap its ▶: it plays at once.

### Get's checks, slice 2 (180-192)

**Not done yet.** These come with the build that adds Get - still **app 0.11 (11)**, the second part of Phase 6.
Compare with the web app on the Mac, the same album and pressing open in both: the phone should say the same, in the
same words. Check 187 wants logins on; the rest work either way. Use an album you're happy to have in your library.

- **180 Get an album, end to end.** In Search, find an album you don't have and open it. Under the pressing's facts:
  **Get the album**. Tap it: **Choose a source** slides up, the album and pressing under its title, "Looking for …"
  and "This takes a few seconds.", then the cards. Tap the best match's **Get** (the solid one): the sheet closes and
  Requests shows at its top, the album already there under Waiting, "starting…", before deadwax has answered. Let it
  download and be filed, then tap its **▶** under Done: it plays. Go back to Search: you're on the album's page as you
  left it, and the line under Get the album now says "Already in your library".
- **181 The pressing chosen.** On an album of several pressings, choose one that isn't the usual: the sheet's line
  under its title names that pressing, and the search is for it. Before the pressings have loaded there's no Get the
  album. On an album deadwax has nothing of, there's no line under the button.
- **182 The line.** While 180's download is under Waiting or Downloading, open the album's page again: "Already
  downloading", "From … · 3 of 11 files" and "To get it from another source, cancel it in Requests first." - the web
  app's page for the same pressing says the same. Cancel it in Requests and go back to the page: the line goes within
  a moment. Put the app in the background for a minute and bring it back: the line is asked again, and nothing on the
  page jumps when it lands.
- **183 Why it scored that.** In the sheet, tap a card's score: **Why it's a 92% match**, the edition words in the
  folder's name, and the six parts with their percentages and what each measures. The same card in the web app's
  sheet has the same score, parts and words. Tap the score again: it folds, and nothing above it moved.
- **184 The chips and the sort.** Tap **Lossless**: the list narrows, and the purple edge and solid Get move to the
  best match left. Sort by **Highest quality**: the best match keeps its edge wherever it lands. Press chips until
  none match: "41 sources found - none match your filters." and **Clear filters**, which brings them all back. Under
  the cards, "Searched for “…” · 41 sources, 4 match your filters" agrees with what's shown.
- **185 Search again, and Cancel.** Tap **Search again**: a field opens with the words searched, the keyboard up.
  Change them (drop the artist, say) and tap **Search**: "Looking for …" again, then cards, the line under them naming
  your words. Words that find nothing: "Nothing found for “…”." with the field there to try again. Tap **Cancel**
  while it searches: the sheet goes, and Get the album searches afresh.
- **186 A refusal.** Open the sheet on the phone and wait for the cards. Then, in the web app, Get the same pressing.
  Back on the phone, tap a card's Get: Requests shows the row "starting…", then under Needs attention "didn't start"
  with "It's already downloading." (if it was filed meanwhile, "It's already in your library." - "…in the
  collection." with logins on). Clear done takes it away.
- **187 Get albums, and someone else's download.** As an admin, take **Get albums** from a user in the web app's
  People. On their phone, open Settings (it asks deadwax again), then an album they don't have: no Get the album, and
  "Getting albums is off for you - ask an admin." in its place, the line under it still saying what's here. Give it
  back, open Settings again: Get the album is back. As that user, open an album another user is downloading: "Already
  downloading for someone else", the copy and how far it's got - the web app's words, without its Join.
- **188 Offline.** On an album you don't have's page, turn Airplane Mode on: Get the album goes, and "Getting albums
  works once deadwax is back." stands in the line's place. Turn it off: the button is back, and the line is asked
  again. Open the sheet and wait for the cards, then turn Airplane Mode on: the same words at the sheet's top, the
  cards dimmed, every Get dimmed - tap one: nothing happens, and Requests doesn't open. Turn it off: the cards and
  their Gets are back. Turn Airplane Mode on while the sheet is still searching and leave it: once the phone gives up,
  it says why; turn it off, and it searches again by itself.
- **189 Only the newest answer.** On a slow connection, choose one pressing and then another quickly: the line never
  shows the first pressing's answer under the second. Open the sheet, Cancel, and Get the album again at once: only
  the second search's cards ever show.
- **190 The largest text** (the iPhone's Settings > Accessibility > Display & Text Size > Larger Text, all the way up). Get the
  album reads whole; the line wraps rather than clips. In the sheet the chips scroll sideways, a card's facts go two
  by two and then one over another, each fact read whole ("FLAC, MP3 VBR 128-320k" on two lines, not cut off with
  "…"), the reasons read whole, and every Get stays in reach. Nothing overlaps.
- **191 VoiceOver.** On the album's page, the line reads as one, and when it changes (Get something, come back) its
  new title is heard. In the sheet, "Looking for “…” by …" is heard, then "12 sources." (or why there are none). A
  score reads "92% match, collapsed", and double-tapping it reads expanded, the reasons after it. A card's Get reads
  "Get <folder> from <who>", and the chips' row "Filter the sources", the sort "Sort the sources". Note what it says
  if not.
- **192 A slow peer.** (Only if you come across one: a Get whose peer takes minutes to answer.) Its row stays under
  Waiting, "starting…", however long deadwax takes, and becomes the download when it shows - never "didn't start"
  beside it. Note how long it took.

### Getting albums' checks, slice 3 (193-199, 229-236)

**Not done yet.** These come with **app 0.12 (12)**, the end of Phase 6: Join, Add to my library, Pick the best
source for me and Settings' Getting albums. They take 193-199, then go on at 229 - the look's builds took 200-228
meanwhile. Compare with the web app on the Mac, the same album open in both. 196-199 want logins on and
two accounts (one can be an admin); the rest work either way.

- **193 The version, and Getting albums' three.** install.sh says "Installed deadwax 0.12 (12), runs until …", and
  Settings > About reads 0.12 (12). Settings > Getting albums: **When I tap Get** (Show me the sources, Pick the best
  source for me), **Quality floor** (Any, 320 kbps, Lossless, 24-bit) and **Format** (Any, Prefer lossless, Lossless
  only), each with a tick on what the web app's Settings shows, the web app's note under them, then Confirm before
  cancelling.
- **194 Chosen on the phone, kept on deadwax.** On the phone choose **Lossless** and **Lossless only**: the ticks move
  at once. In the web app's Settings (reload it), the same two are chosen. Choose **Any** there, then open Settings >
  Getting albums on the phone (or pull down): Any is ticked. Get an album: the sheet's chips start at the floor you
  chose.
- **195 Pick the best source for me.** Choose it, then Get an album that's well shared ("Dummy" on CD): the sheet
  says it's looking, then closes onto Requests, the download under Waiting or Downloading, its source the one the
  web app would mark as the best match. Then Get an obscure album, or one whose sources are all MP3 with the floor
  at Lossless: the sources show, and above them "No close match that passes your filters - choose a source
  yourself." With VoiceOver, it's said after how many sources there are. Tap **Search again** and **Search**:
  nothing is picked. Choose Show me the sources again afterwards.
- **196 Join from the album's page.** Logins on: as one person, Get an album and leave it downloading. As the
  other, on the phone, open the same album and pressing: "Already downloading for someone else", "Join it to have
  it in your Requests too - …" and **Join this download**. Tap it: "Joining…", then "Joined - it's in your
  Requests.", and the line becomes "Already downloading". Requests lists the download, as "Someone else asked for it
  too". Without Get albums (an admin takes it in the web app's People, then open Settings), the line has no Join and
  says nothing of joining.
- **197 Add to my library.** Logins on: as one person, have an album filed. As the other, open it on the phone:
  "In the collection, not in your library", "It's already here - add it to your library to keep it with your
  music." and **Add to my library**. Tap it: "Adding…", then "Added to your library.", and the line becomes
  "Already in your library". The Library's Your albums show it, and Search marks it as yours. In the web app, it's
  in that person's library too.
- **198 Join and Add in the sheet.** With **Pick the best source for me** on, Get a pressing that's downloading
  for someone else: nothing is picked - the sheet shows the line, with **Join this download**; tap it: the sheet
  closes onto Requests, the download there. Get one that's in the collection but not yours: **Add to my library**
  in the sheet's box; tap it: the box says "Already in your library", with "Added to your library." under it.
- **199 A Join refused.** Open a page with Join on the phone, then in the web app (as whoever asked for it)
  cancel the download and Clear done. Tap Join on the phone: under the button, which stays, why it can't be
  joined now ("That download has been cleared from the list since - get it again.", or that it has been
  cancelled). Go back and open the album again: the line says nothing's on its way.
- **229 Offline.** With Settings > Getting albums showing, Airplane Mode on: "Getting albums works once deadwax is
  back." under the three, which can't be chosen. Back, they can, and a choice made in the web app meanwhile shows.
- **230 Not saved.** (Only if you can make deadwax's database read-only for a minute, or you see it anyway.) A
  choice goes back to what it was, with "Not saved." and why under the three; VoiceOver says it. "deadwax can't
  keep these: its database isn't writable." under them while it lasts - and "Tell whoever runs deadwax." for
  someone who isn't an admin.
- **231 The largest text.** Getting albums' three rows and their note read whole, the ticks at the right. Join this
  download and Add to my library, and the words that replace them, wrap rather than clip, in the page's line and in
  the sheet.
- **232 VoiceOver.** Getting albums' rows read their names, the chosen one "Selected", and dimmed until deadwax has
  answered. Join and Add read as buttons; "Joining…" stays where it is with the focus on it, then "Joined - it's in
  your Requests." is heard (and "Added to your library."). A refusal is heard as it's said.

After review, four more, for what the review changed:

- **233 Swiped away while it looks.** With **Pick the best source for me** on, Get a well-shared album and, while
  it says it's looking, swipe the sheet down and let go: the sheet goes, and nothing is got - Requests has no new
  download, then or a minute later. Get it again, swipe halfway and pull the sheet back up: it carries on, and
  picks as it would have.
- **234 Back after a Search of your own.** With Pick the best source for me on, Get an album, tap **Search
  again**, change the words and tap a chip off. Tap **Search** and, while it's looking, turn Airplane Mode on;
  wait for the sheet to say why (up to five minutes, if iOS keeps the search open). Airplane Mode off: the sheet
  searches your words again, the chips as you left them, and shows the sources - nothing is picked, and the sheet
  stays.
- **235 Join and Add out of reach.** With the sheet showing **Join this download** or **Add to my library**,
  Airplane Mode on: the box dims and the button can't be tapped. Off again: it can.
- **236 No answer in time.** (Hard to make happen - skip it if it won't.) In the sheet, tap **Join this
  download** (or **Add to my library**) and at once turn WireGuard off. After about a minute the box says "deadwax
  didn't answer in time, so you may have joined it anyway. …" (or "… it may have been added anyway. …"), never that
  it was refused; if it says deadwax couldn't be reached instead, iOS dropped the connection at once, which is fine
  too. WireGuard back on: Requests (or Your albums) shows whether it went through, and a second tap does no harm.

### The squared look's checks (200-209)

**Not done yet.** These come with the build that squares the app off (still app 0.11 (11)). They start at 200,
not 166: Phase 6's checks are being written at the same time and take the numbers after 165.

- **200 The tab bar.** Square, the full width, flush with the bottom edge, a thin line along its top - no
  floating capsule. The tab you're on is purple. Tap each tab; tap the one you're on: back to its first screen,
  then to its top. Open an album and swipe back: the bar never moves or flickers, and iOS's own never shows.
- **201 Above the bar.** With something playing, the mini player is the top of the bar (since the build after Noto
  Sans: checks 218-228); add a song to the queue: the line above the mini player. Scroll to the end of an album, Your
  albums (grid and list), Playlists, Artists and Settings: the last row clears the mini player and the bar, and the
  letter index's last letter is above them. Nothing playing: the last row clears the bar, with no gap under it. Now
  Playing opens over everything, the bar included.
- **202 The keyboard.** In Search, tap the field: the keyboard comes up over the tab bar - the bar doesn't ride
  up on it - and over the mini player with it (until the build after Noto Sans the mini player sat on the
  keyboard). Scroll the results to the end: the last row clears the keyboard, with no gap the bar's height above
  it. Put the keyboard away: the bar and the mini player are back where they were. The same with the Library's
  Find and Settings > This phone > Change address.
- **203 The Library's top.** On Albums: the magnifying glass, the switch, the •••, evenly spaced - the switch
  filling the room - and no Find field. Swipe to Playlists and Artists: the same top, no **+**. The switch's
  purple line moves to the page as you swipe and as you tap. Does the top look complete?
- **204 Find.** Tap the magnifying glass: the field under the switch, "Find in albums", the keyboard up. Type:
  the albums found. Swipe to Playlists: the field empty, "Find in playlists"; type there; swipe back: the albums'
  words again. **Cancel**: the field goes, and every page shows everything (look at Playlists too). Open it again
  and press the keyboard's Search: the keyboard goes, the words stay; tap the magnifying glass: the keyboard back.
- **205 New playlist.** On Playlists, ••• > **New playlist**: the sheet the **+** opened, and Create opens the new
  playlist's page. In Airplane Mode it's dimmed.
- **206 Square corners.** The album page's cover, Now Playing's, the tiles and rows, Up Next's and Info's covers,
  Search's rows: the smallest of corners. The line over the mini player, the first ask on Downloaded, the
  sign-in's fields, the "In your library" badge, Up Next's Shuffle and Repeat, the EQ's held value, the Try again
  buttons: small square corners, no round ends. Still round: artists' pictures, your initial on Settings, the download
  rings, the EQ's knobs, the two buttons at the Library's top. The turntable as it was.
- **207 VoiceOver.** The bar reads as a tab bar, each tab its name, the one you're on selected. The switch reads
  "Library pages", each page a button, the one shown selected; the magnifying glass "Find in albums" (the page's
  own words); the ••• "More for the Library"; then Find's field and **Cancel**.
- **208 The largest text** (the iPhone's Settings > Accessibility > Display & Text Size > Larger Text, all the way up): the
  tab bar's words stop growing; hold a finger on a tab: it shows large. The switch's names grow, then hold; one too
  long for its segment shrinks a little, then ends in "…", and holding a finger on it shows it large. Nothing
  overlaps, and every list still ends above the mini player and the bar.
- **209 Reduce Motion** (the iPhone's Settings > Accessibility > Motion): a tap on the switch moves the page and its purple at
  once, with no slide; Find comes and goes without sliding.

### Noto Sans's checks (210-217)

**Not done yet.** These come with the build that sets the app in Noto Sans (still app 0.11 (11)), and follow
the squared look's.

- **210 The face.** Go through the Library, an album, Now Playing, Up Next, Search and Settings with the web app open
  beside them: the same face as the web's. Check the navigation bars' titles too, large and then small once you
  scroll (Search, Settings, All music's pages, an artist), and the back button's word.
- **211 Its weights.** An album's title and Now Playing's song are bold; the switch's names, the tab bar's words
  and the track titles keep the weights they had. Nothing looks smeared or faked-bold.
- **212 Other alphabets.** Find a name with Polish or Czech letters (Łódź, Dvořák), Turkish (ş, ğ, ı), Vietnamese,
  Greek and Cyrillic: each is drawn in the same face as the Latin beside it, not a different one. Japanese, Korean
  and Arabic are iOS's face, as they were.
- **213 Numbers that count.** Now Playing's times, the mini player's line, a track's number and length, and
  Downloads' sizes: the digits hold still as they change, with no jiggle.
- **214 Text size.** At the smallest and the largest text sizes, Noto Sans shrinks and grows as iOS's face did.
  The navigation bars' titles take the size the app opened at: change the size with the app open, and they catch up
  the next time it opens. A page's small title, the bars' buttons, the search fields and the segmented controls
  stop growing at the largest of the standard sizes, as the tab bar does; the big titles keep growing.
- **215 What iOS draws for the app.** These are in Noto Sans: Settings' and Info's section headings and the small notes
  under sections, the segmented controls (Search's filter, Info's, the EQ's ear), what you type in a search field,
  and the bars' buttons (**Done**, **Edit**). The menus, alerts, swipe buttons and Paste stay in iOS's face.
- **216 Bold Text** on: what's in iOS's face gets heavier, Noto Sans doesn't. Say whether that reads badly.
- **217 Fit.** Noto Sans is a little wider than iOS's face, and its lines a little taller. Look where room was
  tight: the switch's names, the tab bar's words, the mini player's two lines, Now Playing's song, the tiles'
  title and artist, Up Next's rows, the EQ's numbers. Is anything cut off sooner than before, or overlapping?

### The mini player on the tab bar's checks (218-228)

**Not done yet.** These come with the build that joins the mini player to the tab bar (still app 0.11 (11)), and
follow Noto Sans's.

- **218 One block.** Play something: the mini player sits right on the tabs, the full width, square, with no gap,
  no card and no room at its sides, and a thin line between it and the tabs. Scroll a page under it: it's solid
  from its top down to the bottom edge, with nothing showing through. The cover is at the very left, the mini
  player's full height. With nothing queued (sign in as someone else, before anything plays): the tab bar alone,
  as before.
- **219 Play/Pause, one-handed.** Holding the phone in one hand, tap Play/Pause with your thumb a few times, then
  with the other hand's: is it easy to hit, and clear of the screen's edge? The spinner shows while a song loads.
  There's no next button.
- **220 Seeking by the line.** The line along the mini player's top shows how far in the song is. Put your thumb on
  the mini player's top edge and drag sideways: the line thickens, and the time under your thumb shows over it,
  "1:23 / 4:56", kept on the screen at either end. Let go: the song goes there, once, and the line doesn't jump back
  while it gets there. Paused, the same, and it stays paused. Is the line easy to catch with a thumb, aiming at the
  top edge? Tap the top edge over the cover or the song: Now Playing opens; over play/pause: it plays or pauses.
- **221 Swiping the title.** Swipe it left: the title slides away to the left, the next song's slides in from the
  right, and it plays (or stays paused). Swipe right well into a song: the song before, never the same song again.
  A short swipe springs back; a quick flick is enough. With Shuffle on, left and right follow Up Next's order.
- **222 The queue's ends.** On the first song, swipe right: the title pulls a little way and springs back, and
  nothing changes. On the last song with Repeat off, swipe left: the same. With Repeat All on, the last song's
  swipe left goes to the first. In a song's last seconds, start a swipe left and hold it until the next song begins,
  then let go: the title springs back, and no song is skipped.
- **223 A tap opens Now Playing.** Tap the title, the artist's line or the cover: Now Playing opens. A swipe across
  never opens it.
- **224 A drag up opens Now Playing.** Drag up on the title or the cover and let go: Now Playing opens as you let
  go. It doesn't follow your finger: say whether that feels wrong. A short drag up does nothing, and so does a drag
  down; a drag up never skips.
- **225 VoiceOver.** The mini player reads "Now playing: Roads, Portishead - open"; double-tap opens Now Playing.
  Swipe up or down on it: **Next song** and **Previous song**, each only when there's a song that way. Then
  Play/Pause, then the line: "Position in the song", "0:12 of 5:00", and swiping up or down moves it 10 seconds.
- **226 The last row.** Scroll to the end of an album, Your albums (grid and list), Playlists, Artists, Settings and
  Search's results: the last row clears the mini player and the tabs, with no gap. Add a song to the queue: the line above
  the mini player, and the last row clears that too. In Search, tap the field: the keyboard covers the mini player
  and the tabs, and the last result clears the keyboard alone.
- **227 The largest text and Reduce Motion.** At the largest text sizes, the mini player grows with its words as
  far as the tab bar's do, the cover with it; hold a finger on Play/Pause: it shows large. With Reduce Motion on, a
  swipe's titles fade instead of sliding. Look at the navigation bars too: a page's small title, **Done**, the
  back button, Search's field and the segmented controls (Search's filter, Info's) stop growing at the largest
  standard size, so nothing is cut off in them. The big titles (Search, Settings, All music's pages) still grow: are
  any cut off at the top or bottom?
- **228 Scrolling near the mini player.** On a long list (an album, Your albums, Search's results), start a scroll
  with your thumb just above the mini player, so close it nearly touches, going up and going down, slowly and
  quickly, a little sideways too: the list scrolls, and the song never jumps. Tap the bottom edge of a row just
  above the mini player: it opens. Start a drag up on the mini player's top edge: Now Playing opens as you let go,
  and the song doesn't jump.

### Managing's checks (237-246)

**Not done yet.** These come with **app 0.13 (13)**, Phase 7: Settings' [Manage](#manage), each row opening the web app
in Safari. Use deadwax's plain `http://` address, as the app has it - once on the home Wi-Fi, once over WireGuard
with Wi-Fi off. 237-243 want logins on, and 241 two accounts (one an admin); 244-246 work either way. Since the build
with [Edit album](#edit-album), Edit an album opens Choose the folder in the app (no line under it, no arrow) and an
album's ••• has **Edit album** where Edit in the web app was: those parts of 237, 238, 241 and 242 are 320 and 321's
now, and the footer says "Edit an album is the app's own; the others open in the web app, in Safari." Since the
build with [Server settings](#server-settings), Server settings opens in the app, and the Library's Set up Navidrome
opens its Connections page over the Library: 244 is 369's now. Since the build with the [Event log](#event-log), it
opens in the app too: in 239, tap People (as an admin) where it says Event log, and the page itself is 370-373's.
Since the build with [Change password](#change-password), Account's Change password opens a page in the app, with no
line under it and no arrow: 243 is 374-378's now. Since the build with [People](#people), People opens in the app too,
and no row of Manage opens Safari: nothing is said under the rows, and the Safari parts of 237-241, 245 and 246 no
longer apply - 379-387 check People's page. 241's rows following the permissions still hold: give and take them in
the Mac's People (or the phone's), and look at the app alone. Since the build that takes the web app's way out away,
nothing of 237-246's Safari is left in the app at all: 388-391 check that.

- **237 The version, and Manage.** install.sh says "Installed deadwax 0.13 (13), runs until …", and Settings > About
  reads 0.13 (13). As an admin, Settings has **Manage** between Downloads and Account: **Edit an album** (with "Opens the
  web app's Library: open an album there, then Edit. An album's ••• here has Edit in the web app too." under it),
  **Needs a look**, **Library care**, **People**, **Server settings** and **Event log**, each with an arrow at its
  right, and under them "These open in the web app, in Safari." and the line about Safari's own sign-in.
- **238 Each row opens its page.** Tap each row in turn, coming back to the app between them: Edit an album opens the
  web app's Library; Needs a look, Library care, People, Server settings and Event log each open that very page in
  Safari, its title at the top, not the web app's Home. Its Back goes to the web app's You (its Settings now). Does
  Safari open a new tab each time, or go back to the one it has?
- **239 Safari's first sign-in.** Sign out of deadwax in Safari first (the web app's Sign out), then tap
  Needs a look in the app: Safari shows the web app's sign-in. Sign in with the name and password you use in the
  app: Needs a look opens, not Home. Back in the app, tap Event log: it opens at once, with no sign-in. The app is
  still signed in throughout.
- **240 Plain http and the network.** On Wi-Fi and over WireGuard, the pages open at `http://…` with Not Secure in
  the address bar and no other warning - unless Safari is set to warn about pages that aren't secure (Settings >
  Apps > Safari), in which case say what it shows. Safari doesn't ask about the local network, and the address isn't
  turned into `https://`.
- **241 The rows follow the permissions.** Do the admin's part on **another device** - the web app on the Mac, signed
  in as the admin - never in Safari on this phone: that would sign Safari in as the admin, and every page would then
  open with the admin's access. On the phone, sign Safari in as the person under test (Sign out in the web app, in
  Safari, then sign in as them), and the app too. As them, with no permissions: no Manage in Settings, and the album's
  ••• has no Edit in the web app. On the Mac, give them **Edit albums** in People; on the phone pull down on Settings:
  Edit an album and Library care appear, and nothing else. Give them **Settings and the log**: Server settings and
  Event log join them. Take Edit albums away on the Mac and tap Library care on the phone before pulling down: Safari,
  signed in as them, says "This page needs a permission an admin hasn't given you - ask one if you need it." Pull
  down: the row goes.
- **242 An album's Edit in the web app.** As an admin, open an album and tap the top •••: after the download items,
  **Edit in the web app**, with Safari's compass. Tap it: the same album's page in the web app, with **Edit** at
  its top. Try an album whose name has an accent or a slash in it. A song's ••• has no such item.
- **243 Change password.** Settings > Account has **Change password** above Sign out, with "Opens the web app's You:
  Change password is under Account there. It changes the password of whoever is signed in in Safari." under it. Tap
  it: the web app's You (its Settings now), with Safari's signed-in name at its top and Change password under Account.
  (Don't change it unless you mean to.) Signed in as `deadwax` (the emergency admin), Account has Sign out alone.
- **244 Set up Navidrome.** Only if you can take Navidrome's address away for a moment (in the web app's Server
  settings > Connections, on a test setup): the Library shows "Connect Navidrome" with **Set up Navidrome**. Tap it:
  Safari opens the web app's Server settings, at its first tab; Connections is the third. Put the address back.
- **245 Offline, and Safari turned off.** Turn off Wi-Fi and WireGuard: Manage's rows dim and do nothing when
  tapped, the footer says "These open once deadwax is back.", Change password dims, and the album's ••• has no Edit
  in the web app. Turn the network back on: all of it works again without leaving Settings. Then, only if you're happy
  to change Screen Time for a minute: turn Safari off (the iPhone's Settings > Screen Time > Content & Privacy Restrictions >
  Allowed Apps) and tap Needs a look: nothing opens, and "Couldn't open the web app - Safari may be turned off in
  Screen Time." shows over the tabs for a few seconds. Turn Safari back on.
- **246 The largest text, and VoiceOver.** At the largest text sizes, Manage's rows and the line under Edit an
  album wrap, nothing cut off, the arrows growing with them. With VoiceOver, each row reads as one button - "Needs
  a look, button, Opens in Safari." - and Edit an album reads its line too; dimmed rows read as dimmed.

### Search again at the top's check (247)

**Not done yet.** This comes with the build that puts Search again at the top of Choose a source as well (still app
0.13 (13)).

- **247 Search again, at the top.** Get an album that many peers share, so the cards run past the screen. At the
  top, **Cancel** at the left, "Choose a source" whole in the middle (not cut short) and **Search again** at the
  right - there only once sources are shown, not while it's looking. Scroll down a little and tap it: the field opens
  above the chips with the words searched, the keyboard up, the list still where you left it; change them and tap
  **Search** - "Looking for …", then the cards. Tap the top one, then scroll to the end and tap the one under the
  cards: the field moves down there; tap that one again and it closes. At a larger text size (the iPhone's Settings > Display &
  Brightness > Text Size, one step up), the top one is a magnifying glass and the title still reads whole. With
  VoiceOver, both read "Search again, button, collapsed" (expanded once open).

### The smooth progress bars' check (248)

**Not done yet.** This comes with the build that draws the progress smooth (still app 0.13 (13)).

- **248 Smooth, and still on pause.** Play a short song (two or three minutes, so the line moves quickly) and
  watch the line along the mini player's top: it creeps along evenly, with no step twice a second. Open Now Playing:
  its bar does the same, and its two clocks still change once a second, each in step with the bar - "1:23" never
  lingers after the bar has passed a second, nor comes before it. Pause: both stop dead at once, with no creep on
  and no jump back; play: on from there. Seek on each (drag the mini player's line, drag and tap Now Playing's bar):
  it lands where you let go and carries on from there, never jumping back first. Change the speed on the turntable
  (the fader, or a tap on the readout to 2x), then flip back to the cover with the look button: the bar is where the
  song is and runs at the new speed. On the cover, tap the speed chip back to 1x, then pick a speed from the •••
  menu: each time the bar keeps up, with no jump. If a change ever brings up the spinner over Play/Pause (a slow
  restart), the bar stands still under it and goes on from there - never back. Open Up Next over Now Playing and
  close it, then Info, then flip to the turntable and back: each time the bar is where the song is. Do it all again
  at the largest text size. With VoiceOver on, the line and the bar still read their time ("0:12 of 5:00") without
  repeating it as the song plays. Say whether anything feels slower or warmer than before.

### The Library's top under the Dynamic Island's check (249)

**Partly done (15 Nov).** This comes with the build that lays the Library's top out under the status bar (still app
0.13 (13)). The first build of it (282e9b9) still had the row in the island's strip; the build after that one (267ea8f)
makes the row measure where it is on the screen and come down by what it lacks of the window's own top safe area. On
it, James: "the library top clears the island now" - the first sentence below. The rest of 249 (scrolling, Find, the
offline banner, the largest text size, another phone, no jump as sheets and pages come and go) is not done yet.

On 18 Nov James found the row back in the island after Now Playing: "after pulling up the play screen and going back
to library, the top bar is back inside the Dynamic Island". The build after that (still app 0.13 (13)) measures the row
through UIKit, in its own window, and measures it again once Now Playing or a sheet has gone - the new step after the
first sentence below.

On 20 Nov James found that build put it too low instead: "well now the whole screen is too low", "It's after I leave
the player, but not first when I open the app". Its Debug line said why: as the Library came back from under Now
Playing it was measured for a moment far above the screen's top edge, came down twice the island's room, and wasn't
measured again once it settled. The build after that (still app 0.13 (13)) ignores a measure taken above the screen's
edge, and measures again for three seconds after each time it measures - the same step, now also: no lower than
when the app opened. On it, James, after Now Playing: "Right height now".

On 25 Nov, after the redesign's new Library top, James found the row under the island again as soon as the app opened.
Its Debug line said the row stood 15 points above the screen's top edge, measure after measure, and the build ignored
it as it had the moment after Now Playing. The build after that (still app 0.13 (13)) brings down a row that stands
still above the edge - the same on two measures a quarter of a second apart, nothing open over it - by what it stands
above the edge and the island's room, so the row ends up under the island. One that is still moving is ignored, as
before. **Not done yet** on that build: the first sentence below, from a cold start (swipe deadwax away in the app
switcher, then open it) and from the Home Screen with it already running, then the rest of the check.

- **249 Clear of the Dynamic Island.** Open the Library: the magnifying glass, the switch and the ••• sit wholly
  below the Dynamic Island and the status bar's time and battery, none of them touching it, with the bar's colour
  running up behind the status bar and nothing of the pages showing there. The row's foot and the line under it (the
  count, the order, Yours | All) are whole too, and a page's last row still clears the tab bar. Open Now Playing, close it: the row is
  still clear, and no lower than when the app opened - do it a few times, closing it each way you can (its control, a
  swipe down), and once with Find open first. Scroll a page up: it goes under the row's foot, never up behind the status bar. Tap the magnifying glass:
  Find's field opens under the row, the keyboard up, and the row stays put; type, Cancel. Swipe between the pages, and tap the switch: as before. Turn off Wi-Fi and
  WireGuard: the offline banner shows under the row, not over it. Do it all again at the largest text size. If you
  can, try a phone with a notch, or an SE. Open Now Playing, an album's •••, Find and a sheet (the switch's Edit
  order), and close each: the row is where it was, with no jump as each goes. Push an album and swipe back: the row
  doesn't move. If any of the row still touches the island, or sits lower than it did, a screenshot of it says where
  it stands - and then,
  without opening anything else first, Settings > This phone > Debug's **Library** section: its **Top** line
  ("row … · window … · down … · …") is the row's last measure; send it as it reads. "held, row settled above the
  window" in it means the row stood above the screen's edge and was brought down from there.

### The tab bar, lower's check (250)

**Not done yet.** This comes with the build that brings the tabs down into the home indicator's room (still app 0.13
(13)).

- **250 The room under the tabs.** On the iPhone 17 Pro, look at the tabs' words: they sit nearer the bottom edge
  than before, with clear room between them and the home indicator - the indicator never touches or overlaps a
  word, and the bar's colour still runs down to the very edge. Does the gap look right, or still too much (or now
  too little)? Tap each tab near its foot: it opens. Scroll a long list to its end (an album, Your albums, Search's
  results): the last row clears the bar, with no gap and nothing under it; add a song to the queue: its notice sits just
  over the bar. In Search, tap the field: the keyboard comes up over the bar, as before, and the bar is back in its
  place once it goes. At the largest text size, the words still clear the home indicator. Swipe deadwax away in the
  app switcher and open it again: from the first frame the tabs are in their place, never over the home indicator,
  even for a moment. If you can, an SE: a small margin under the words, not flush with the edge.

### Actual corners' checks (251-252)

**Not done yet.** These come with the build that takes every squared corner to a true corner and draws the transport
and the Library's icon sharp (still app 0.13 (13)).

- **251 Square corners.** **Not done yet.** Look for any rounding left on what was squared: covers (an album's page, Now Playing, the
  Library's tiles, the rows, the play bar's), the album page's Play, the pills, the badges (New, Requests' count),
  Find's field, the notice, the first ask, the sign-in's fields, the EQ's Paste, Settings > Downloads' bars, and on
  Now Playing the speed chip on the cover off 1x (the look button at the top right is a word with no box since
  R4b, so it has no corners). Every corner is a point. Say if any reads badly square - Play's light line along its top, a badge
  over the Requests icon. Still round, as they should be: the dots, your avatar, artists' pictures, the rings, the
  sliders' knobs. Still slightly
  rounded, as hardware: the turntable's plinth and the speed readout's well at its bottom right - say if you'd rather
  they were square too.
- **252 Sharp glyphs, and the Library icon.** Play, pause, next and previous have sharp points and square bars,
  the same size as before: the play bar's Play/Pause, Now Playing's three, the album and playlist pages' Play,
  Requests' ▶, Search's ▶ beside a song, and Debug's. Tap Play/Pause on each: it turns between the two with a short
  fade. The Library tab's icon is a square stack with sharp corners, the same size and weight as Search's, Requests'
  and Settings' beside it, in the accent when the Library is shown and grey when not. At the largest text size, all of
  them grow as the words do; hold a finger on Play/Pause in the play bar and on the Library tab: the large view
  shows the sharp glyph. With VoiceOver, each still reads its name ("Pause", "Next", "Library").

### Album info's checks (260-270)

**Not done yet.** These come with the build that adds [Album info](#album-info) (still app 0.13 (13)). No server
change is needed: it works with the deadwax you already run.

- **260 From an album's •••.** Open an album of FLACs (a 24-bit one if there is one) and tap the top •••: the last part
  of the menu has **Album info** with an ⓘ - above Edit album (Edit in the web app before Phase 8), as an admin. Tap
  it: a sheet with the cover, title and artist, then **Quality** ("FLAC · 24-bit / 96 kHz · all 10 songs", Bitrate,
  Channels "Stereo"), **The
  album** (Songs, Length, Size) and **On this phone**, at once. Then, after a moment of "Reading the album's
  files…", **The release** and **MusicBrainz**. Does the reading line show for long? **Done** closes it. A song's
  ••• has no Album info.
- **261 The format, against the files.** For the same album, compare Format and Bitrate with the web app's Debug or
  the files on the server: the depth and rate are the files' own, and the bitrate is about what Navidrome says
  for a song of it (Info's Debug). An album of MP3s says "MP3 · 320 kbps" (or "MP3 · 245 kbps on average" for a
  VBR one), never a bit depth, and no Bitrate line under it. An album bought from iTunes (AAC in .m4a files) says
  "AAC · 256 kbps" (or "AAC · 259 kbps on average"), never "M4A" and never "16-bit / 44.1 kHz"; an ALAC album, if there is one, "ALAC · 16-bit / 44.1
  kHz" with a Bitrate line.
- **262 A mix.** An album whose songs differ - some 16-bit and some 24-bit, or FLAC and MP3 - says the commonest
  first ("FLAC · 16-bit / 44.1 kHz · 8 of 10 songs") with the others under it, each "N of 10 songs".
- **263 The release, from Picard's tags.** Open an album tagged by MusicBrainz Picard and compare The release with
  its page on MusicBrainz (This pressing on MusicBrainz): Media ("CD", "2×CD", 12" Vinyl), Label, Catalogue
  number, Barcode, Country, Released, First released (only when it differs), Type, Status, Genres. Say any line that is
  missing or reads oddly - and whether anything shows as "Unknown" or empty (nothing should). Then an album deadwax
  downloaded and filed: Media (a 2-CD set "2×CD", never "2×CD + CD"), Country and Catalogue number, and Added "…,
  downloaded by deadwax". And an M4A album deadwax filed, if there is one: Country, but no Media or Catalogue number.
- **264 A box set.** An album of two or more discs: Discs "2", each disc's line ("Disc 2 · Live at Wembley · 3 songs"
  when it has a title), Media "2×CD" or "CD + DVD-Video". One kept as a folder per disc: as an admin, On the server
  says **Folders**, each on its own line.
- **265 Copy and MusicBrainz.** Tap Copy beside Release: the button is a tick for a moment; paste in Notes - the id
  whole, nothing else. The same for Barcode and (as an admin) the Folder. Tap **This pressing on MusicBrainz**:
  Safari opens musicbrainz.org's page for that release, beside the app; back in the app the sheet is still open.
  **Every pressing on MusicBrainz** opens the release group's page, its other pressings listed.
- **266 Offline.** Turn off Wi-Fi and WireGuard, open a downloaded album and its Album info: Quality, The album, and
  On this phone "All 10 songs · 412 MB" (or "3 of 12 songs · …"); The release with only what the album says itself
  (the label, the year, the genre), and "The rest shows once deadwax is back." Turn the network back on with the sheet
  open: the rest arrives without closing it. Open it online, and turn the network off while "Reading the album's
  files…" shows: the reading line goes, and "The rest shows once deadwax is back." takes its place - never a spinner
  left turning.
- **267 From Info.** Play an album, open Now Playing's ••• > Info: under the album's card, **Album info**. Tap it: the
  same lines, pushed inside Info; its Back returns to Info. Leave it open until the song changes to another album's
  (or skip to one): the page stays on the album you opened it for, and Back shows Info for the song now playing. Then
  play a playlist and do the same for a song of it: Songs and Size are the whole album's, not the playlist's songs
  of it.
- **268 Someone else.** With logins on, signed in as someone who isn't an admin: no On the server, everything else
  the same. With logins off (if you can try it), the release lines still come.
- **269 A big one, asleep.** Let the server's disks spin down (leave it an hour), then open Album info for the
  biggest box set: how long "Reading the album's files…" shows before The release appears - and whether it ever says
  "The album's files couldn't be read just now." instead. And an album you know isn't matched to MusicBrainz: "deadwax
  doesn't know where this album's files are, so nothing was read from them.", quietly, under the rest.
- **270 The largest text, and VoiceOver.** At the largest text sizes every line wraps, nothing cut off, the Copy
  buttons beside their ids and the arrows beside the links growing with them. With VoiceOver: each line reads as one
  ("Format, FLAC · 24-bit / 96 kHz · all 10 songs"); a Copy button reads "Copy release, button" and says "Copied";
  a link reads "This pressing on MusicBrainz, button, Opens in Safari."

### The cover full screen's checks (271-278)

**Not done yet.** These come with the build that lets Now Playing's cover open full screen (still app 0.13 (13)).

- **271 A tap, or a drag.** Play something and open Now Playing. Tap the cover: it fades in full screen on black, the
  status bar gone, **✕** at the top right. Close it. Now drag down on the cover: Now Playing follows your finger from
  its first few points, with no catch or jump as it starts, and closes as it always has; the cover never opens. Drag
  it down a little and let go: it springs back, and the cover doesn't open. A tap with a slight wobble still opens it
  (a drag is Now Playing's after 6 points). Does a slow drag that starts very gently ever open the cover instead? With
  Lyrics on, and with the turntable, tapping their place opens nothing, and the record and the lyrics scroll as before.
- **272 The full size, and covers that aren't there.** Open a cover you know is large in its file (a scan of 3000
  pixels or more): Now Playing's cover shows at once, then sharpens a moment later without moving or jumping. Zoom
  right in: the detail holds. Close and open it again: it sharpens almost at once, with nothing fetched again. Over
  WireGuard, the same, slower. With Wi-Fi and WireGuard off, a downloaded album's cover still opens, at Now Playing's
  sharpness. An album with no art of its own shows Navidrome's placeholder on Now Playing: a tap opens the placeholder
  full screen, as it's drawn. While a cover is still loading, or if it couldn't load (the grey square), a tap opens
  nothing; with VoiceOver a double-tap says "The cover hasn't loaded."
- **273 Pinching.** Pinch to zoom in: it zooms about your fingers and stops at a sensible most - about 3 times for an
  ordinary cover, more for a big one - with a small spring past it. Pinch it smaller than the screen: it springs back.
- **274 Double-tap.** Double-tap near a corner of the cover: it zooms in on that corner. Double-tap again: back to the
  whole cover. Both slide smoothly (at once with Reduce Motion on).
- **275 Panning.** Zoomed in, drag around: it follows, carries on a little when flicked, and stops at each of the
  cover's edges - no black opens past them, and it never pulls past an edge and springs back. Does stopping dead at an
  edge feel right, or would Photos' little spring be better?
- **276 Closing.** Not zoomed, drag the cover down: it follows your finger and the black fades; let go a short way down
  and it springs back; let go further (about a thumb's length), or flick it down, and it fades away to Now Playing just
  as you left it. As you drag, does Now Playing show through the fading black, or is it black behind? Zoomed in, a drag
  down moves around the cover instead and never closes it. **✕** closes it. At the largest text size (Settings >
  Accessibility > Display & Text Size > Larger Text), **✕** is a little bigger and its cross sits inside its square.
- **277 VoiceOver.** On Now Playing, the cover reads "Cover of Dummy - show full screen, button"; a double-tap opens it.
  Full screen, **Close** reads "Close, button" and the picture "Cover of Dummy, by Portishead, Not zoomed, adjustable,
  image". Swipe up: "Zoomed 2 times", then twice that, up to the most (3 times for most covers); swipe down goes back,
  to "Not zoomed". Zoomed, a three-finger swipe moves about it and says where ("Showing the top left of the cover");
  at an edge it says there's no more. The two-finger Z closes it, from the picture and from Close.
- **278 The music, and what happens behind it.** Open, zoom and close the cover a few times while a song plays: the
  song plays on with no gap or glitch, and the lock screen and Control Center don't change. Turn Lyrics on and play a
  song that has none, so the cover shows; open it full screen and let the song end, or skip from Control Center: the
  viewer stays up, on the cover you opened, until you close it - then Now Playing shows the new song (and its lyrics,
  if it has some). With the cover full screen, share an EQ file to deadwax from Files: the viewer goes and the EQ opens
  with the file's preview.

### The index during a fling's checks (279-281)

**Not done yet.** These come with the build that lets the Library's index beat the list's momentum (still app 0.13
(13)).

- **279 Albums, mid-fling.** In Library > Albums, sorted by Title, flick the list hard so it glides. While it's still
  moving, touch a letter on the index at the right: the list stops dead and is at that letter at once, with one tick.
  Slide on along the index: it follows letter by letter, a tick each. Try it a few times, early in the glide and near
  its end, and at the bottom of the list as it bounces. Does the first touch ever miss - a tick but no jump, or no tick
  at all? The same in the grid and as a list (••• > **Show as list**). The index needs 50 albums or more.
- **280 Artists, and the years.** The same in Library > Artists, ordered by Name. Then Albums ordered **Year, newest
  first** and **Year, oldest first**: flick it and touch a decade: it stops and jumps there.
- **281 At rest, and the rest.** With the list still, the index jumps as before. Pull down at the top: the pull to
  shuffle still shuffles. Flick the list and touch the list itself (not the index): it stops where it is, as it always
  has. Swipe back across the Library's pages: nothing changed. With VoiceOver, flick the list with three fingers and
  double-tap a "Jump to" letter: it lands there.

### Pull to shuffle on an album and a playlist's checks (282-288)

**Partly done (15 Nov).** These come with the build that adds pull to shuffle to an album's page and a playlist's
(still app 0.13 (13), 267ea8f). No server change is needed. On it, James: "pull to shuffle works on albums and
playlists too" - the heart of 282 and 283. Their details (the graphic's place at your text size, Edit on a playlist)
and 284-288 are not done yet.

- **282 An album.** Open an album and, at the top of its page, pull down slowly: above the cover the ring fills and the
  mark grows and turns, "Pull to shuffle". At the line: a tick, the purple disc, "Release to shuffle". Push back up a
  little: the ring again, no tick; down again: another tick. Let go armed: "Shuffling", and the album plays shuffled,
  as its **Shuffle** button plays it - Shuffle on in Now Playing, only this album's songs in Up Next. Let go before
  the line: nothing plays. Does the graphic sit in the gap above the cover, clear of the bar at the top, at your text
  size? Does the music start the moment you let go?
- **283 A playlist.** The same on a playlist's page: it plays the playlist shuffled, each song as itself (Now
  Playing's cover and Go to album are the song's own album). Tap **Edit** and pull: nothing shows and nothing plays.
  Done (or Cancel), and it pulls again.
- **284 Nothing to play.** Open an album and pull at once, while it's still loading (WireGuard over mobile data
  helps): nothing shows, nothing plays. An empty playlist: the same. An album that couldn't be loaded says why, with
  **Try again** under it: tap it and the album comes (or says why again); the pull shows nothing meanwhile.
- **285 Offline.** Turn on Airplane Mode. Open an album with only some of its songs on the phone and pull: "Pull to
  shuffle the songs on this phone", and only those play, shuffled. An album you had open before going offline with
  none of it downloaded: the ring fills but never turns purple, "Nothing on this phone to shuffle", and nothing plays.
  The same on a playlist. Back online, an album gone from the collection with songs on the phone says "the songs on
  this phone" too.
- **286 Refresh.** A pull no longer refreshes either page. An album's top •••: **Refresh** at the end. Change the
  album in the web app (its Edit), then ••• > Refresh: the change shows. A playlist: add a song to it in the web app,
  then ••• > Refresh: it's there. Offline, ••• > Refresh checks whether deadwax is back.
- **287 Nothing else changes.** On an album, swipe in from the left edge - at the top and scrolled down - it goes back,
  and nothing plays. The top ••• and a song's ••• open as before; Album info opens and closes. Scroll the songs and
  fling back to the top: the bounce shows nothing and never shuffles. Pull to the purple disc, then pull down
  Notification Center (or take a call) before letting go: nothing plays. A song's tap plays from it, as before.
- **288 VoiceOver and Reduce Motion.** VoiceOver doesn't read the graphic: the page's **Shuffle** is the way there.
  With Reduce Motion on, the mark doesn't grow or turn, and the states change at once, as on the Library.

### The artist's albums you don't have's checks (300-309)

**Not done yet.** These come with the build that lists an artist's albums you don't have on their page in the
Library (still app 0.13 (13)). Compare each with the same artist's page in the web app.

- **300 Their albums among yours.** In Library > Artists, open an artist with albums on MusicBrainz you don't have.
  Your albums show at once, as before; a moment later their others come in among them, newest first, each with its
  cover, its title and "2008 · not in your library", with no tick. The web app's page for them: the same albums of
  theirs, in the same places among yours. (Yours keep their own titles and years on the phone; the web app shows
  MusicBrainz's.) Is any album listed twice, or one you have listed as one you don't?
- **301 Yours as they were.** Your albums keep their lines and ticks; tap one: its page. **Play** and **Shuffle**
  play only your albums, and the line under them counts only yours ("Plays the 3 albums you have"). Tap one of
  theirs: the album you don't have's page, with its pressings.
- **302 Studio only.** At the end of the Albums heading, **Studio only** is on. Turn it off: their live albums,
  compilations and the like join the list ("1998 · Live album · not in your library"), the list on screen until
  they're in. Search for the same artist and open their page from Search's MusicBrainz artists: Studio only is off
  there too. Turn it back on.
- **303 Nothing jumps.** Open an artist you haven't opened since the app started: as their albums come in, does
  anything you're looking at jump, or a row appear and then go? Over WireGuard, scroll down to your albums before
  theirs come in: does the row under your finger stay put? Does the Albums heading keep its height as Studio only
  appears? Go back and open the artist again: everything is there at once.
- **304 One you have elsewhere.** If you have an album filed under another artist (a collaboration, a different
  spelling) that MusicBrainz lists as theirs: it's ticked, "in your library"; tap it: the row spins, then your
  album's page. Tap it and switch tab before it opens: nothing opens there, nor when you come back.
- **305 An artist MusicBrainz doesn't know.** An artist with no MusicBrainz tags in their files (and none in
  Navidrome): the page is as before - your albums, no Studio only, nothing said about the rest.
- **306 When MusicBrainz is away.** If MusicBrainz can't answer (it goes away for minutes at a time): under your
  albums, once, "Their other albums can't be shown right now - try again in a few minutes." and **Try again**; your
  albums still open and play. Pull down to refresh: it asks again.
- **307 Offline.** With the page open, turn on Airplane Mode: their albums leave the page, and Studio only and the
  line under the list go too; your albums stay as before (dimmed if nothing of them is on the phone). Turn it off:
  their albums come back.
- **308 Someone else's.** With logins on, an album as in 304 that someone else has, not you: "in the collection", with
  no tick. With logins off, the same album is ticked, "in your library", as every album of yours is.
- **309 VoiceOver.** A row of theirs reads its title and line ("Third, 2008 · not in your library"); Studio only says
  whether it's on. Before their albums are known, VoiceOver doesn't find Studio only.

### Settings' checks (310-319)

**Not done yet.** These come with the build that makes You into Settings, a list of pages with a menu for each
choice (still app 0.13 (13)). No server change is needed. Compare the choices with the web app's Settings.

- **310 The tab.** The fourth tab says **Settings**, with a gear, and its first screen is titled Settings. VoiceOver
  reads it as "Settings"; holding a finger on it shows the gear and "Settings" large. Nothing calls the tab You any
  more: an album's download menu, waiting for Wi-Fi, says "Download over is Wi-Fi only - in Settings > Downloads.",
  and Choose a source with Lossless only and nothing lossless says "You can change it in Settings, under Getting
  albums."
- **311 The first screen.** Top to bottom: you (the avatar and your name, or "No sign-in needed"); **Getting
  albums**, **Playback** and **Downloads** (its size at the right); Manage's rows, if you may look after deadwax;
  then **Account** (with logins on only), **This phone** - at its right the name or IP of deadwax's address: is it
  the address's? - and **About**, "0.13 (13)" at its right. Each opens its page, with **Back** and the
  edge swipe home again; Manage's rows have their arrow, each opening the app's own page (Safari, before Phase 8).
  Pull the first screen down: it asks deadwax again (no spinner left behind).
- **312 Getting albums' menus.** Open Getting albums: **When I tap Get**, **Quality floor** and **Format**, each one
  row with its choice at the right. Tap Quality floor: a menu of Any, 320 kbps, Lossless and 24-bit, the chosen one
  ticked; choose Lossless and the row says Lossless at once. The web app's Settings says Lossless too. Change Format
  in the web app, then open Getting albums again: the web app's choice shows. Change it once more in the web app and
  pull the page down: it shows. **Confirm before cancelling** is still a switch, and the ✕ in Requests follows it.
- **313 Before deadwax answers, and offline.** Turn on Airplane Mode and open Getting albums: the three rows are
  dimmed and don't open, what was chosen still shows, and "Getting albums works once deadwax is back." is under them.
  Turn Airplane Mode off with the page open: the rows come back, and a choice changed in the web app meanwhile shows.
  Over a slow connection (WireGuard on mobile data), straight after opening the app: do the rows show nothing chosen
  until deadwax answers - never a default?
- **314 Playback's menus.** Open Playback: **Gapless** On; **Now Playing opens as** a menu of Cover and Turntable;
  **Pause winds the record down** a switch; **Normalization** a menu of four; **EQ**. Choose Turntable, then open Now
  Playing: it opens on the turntable. Choose **By album**: the first line under it says "Every song at its album's
  level, even when it plays on its own or in a playlist.", then the FLAC note and "This is kept on this phone.
  Normalization changes from the next thing you play." Play an album: Info's Normalization says "Album volume
  matching". **EQ** opens the EQ for the output playing, and Back comes back to Playback.
- **315 Download over.** Settings > Downloads: **Download over** is one row now, "Wi-Fi only" at its right, a menu
  like Storage limit above it. Under it: "Downloads use Wi-Fi alone - never mobile data, a hotspot or Low Data
  Mode.", then what the phone is on now. On mobile data with a download waiting for Wi-Fi, choose **Wi-Fi and
  cellular**: the line under it changes, and the download starts.
- **316 Account, This phone and About.** With logins on, Account: **Change password**, then **Sign out** with your
  name; Sign out from the page signs you out - every page goes and the sign-in shows. This phone: the whole address,
  **Change address**, and **Debug** for an admin alone (signed in as someone who isn't one: no Debug). About:
  deadwax's version, Logins for an admin, App 0.13 (13). With logins off there's no Account row.
- **317 About, when deadwax didn't answer.** Stop deadwax (or turn on Airplane Mode) and pull the first screen down,
  then open About: deadwax's version stays the one it last gave, with why it didn't answer under it. Start deadwax
  again (or turn Airplane Mode off) and pull About down: the note goes.
- **318 Back up.** Open Settings > Playback > EQ, then tap **Settings** in the tab bar: the first screen. At a large
  text size, scroll the first screen down and tap Settings again: its top. Library, Search and Requests do as they
  did.
- **319 VoiceOver and text sizes.** With VoiceOver, each menu row reads its name and its choice ("Quality floor,
  Any"), Normalization and Download over adding what the chosen one does; a double tap opens the menu, and choosing
  reads the new choice. A row that can't be used is read as dimmed. At the largest text sizes, does each row's name
  and choice still show whole (wrapped, never over each other)? Do This phone's and About's values on the first
  screen stay clear of their names?

### Edit album's checks (320-329)

**Not done yet.** These come with the build that brings [Edit album](#edit-album) into the app - Phase 8's first part
(still app 0.13 (13)). No server change is needed: deadwax 2.1.28 or later sends the library without its tracks, which
an older one sends whole - slower, the same. Use deadwax's plain
`http://` address, on the home Wi-Fi and over WireGuard with Wi-Fi off, as an admin unless said. Compare each with the
same album's Edit in the web app.

- **320 Edit album is the app's.** An album's top ••• ends with Album info, **Edit album**, Refresh - nothing opens
  Safari. It opens a sheet titled Edit album: the cover, name, artist, the folder's path, then Release, Tags, Artwork,
  Lyrics and Delete album…. Artwork, Lyrics and Delete album… still open the album in the web app (the line under
  them says so); Release opens a page in the sheet, and so does Tags since the build after it (330), and Artwork and
  Lyrics since the one after that (335).
- **321 The folder.** An album kept as one folder per disc shows a **Folder** menu with each disc's folder; choosing
  another opens the editor on it. Settings > Manage > **Edit an album** opens Choose the folder: type part of a name,
  the list narrows (the line over it says how many), pick one - Edit album opens for that folder.
- **322 What's wrong.** An album in Needs a look shows its issues with their hints under Needs a look. **It's fine as
  it is**: "Marked fine: …" with **Ask about it again**; the web app's Needs a look no longer lists it. Ask about it
  again: it's back, in both.
- **323 Choose a release.** Release > the release row: a list of pressings, the album's own among the first and marked
  Current. Pick another: a spinner on its row, then back on Release with the fields filled in. Within a second of
  typing in a field, What Apply does changes.
- **324 Apply, with Navidrome.** Pick a pressing that renames the folder: What Apply does says the folder's new path
  and that it renames once Navidrome has scanned. Apply: the button says "Applying, waiting for Navidrome", then what it
  did. The album page behind the sheet shows the new pressing; Navidrome still has its plays and stars. If its id
  changed, the album page is the new one (and VoiceOver says so).
- **325 Locked mid-apply.** Start an apply that waits and lock the phone at once. Unlock after a minute: does it say
  what it did, or "deadwax may have finished this - looking again" - and never offer the same Apply again? Does the web
  app show the album as applied?
- **326 Covers.** Release > **Compare covers…**: the folder's and the release's side by side; a tap opens one full
  screen. **Replace cover only**: "Saved cover.jpg, replacing …", the header's cover changes, and so does the album
  page's after a moment.
- **327 Typed work.** Type in a field, then swipe the sheet down: it stays. **Close**: "Discard changes?" - Keep editing
  keeps what you typed; Discard closes it. During an Apply, Close is dimmed.
- **328 Out of reach mid-edit.** With the editor open on Release, turn Wi-Fi and WireGuard off: the amber line at the
  top, Apply dimmed, the fields as you typed them. Turn them back on: "Working out the changes…" again before Apply
  comes back. Turn them off again the moment Edit album has opened, before Choose a release has its list (it says the
  search didn't work); turn them back on: the list comes without a pull. Open Edit album with deadwax out of reach:
  "Managing needs deadwax. This opens once it's back." - and it opens by itself when deadwax is back.
- **329 The largest text, and VoiceOver** across the sheet, Release, Choose a release, Changes and Choose the folder:
  every word whole, wrapped rather than cut off; each folder and pressing read as one line (a pressing with Current
  and its track count), the header as a heading, the Folder menu its choice, and the Discard question's two buttons.

### Edit album's Tags checks (330-334)

**Not done yet.** These come with the build that brings Edit album's [Tags](#edit-album) into the app - Phase 8's
second part (still app 0.13 (13)). No server change is needed: any deadwax the first part works with. As in 320-329:
deadwax's plain `http://` address, on the home Wi-Fi and over WireGuard with Wi-Fi off, as an admin; compare each with
the same album's Tags in the web app.

- **330 Tags.** Edit album > **Tags**: "Reading the files…", then every track in running order - on a set a section
  for each disc and numbers like "2-04"; a guest artist's track shows them under its title. **Select**, tick three:
  "3 of 12 selected", and **Edit 3 tracks…** at the bottom opens Edit tags with the fields they share filled in and
  those that differ saying "Several values" ("Differs between tracks - left alone, each keeps its own"); tap into one
  and out again without typing: it still says "Several values", never "Will be removed", and nothing is worked out.
  **Select every track**, then **Deselect every track**; **Done** clears the ticks, and with none ticked the button is
  **Edit all tracks…**.
- **331 A genre for all.** Edit all tracks…, type a genre: within a second What would change lists each file's change,
  its genre now struck through and the new one under it; a field left at "Several values" changes no file's own.
  **Apply**: "Saved 12 files." with "Reading the files…" under it - not the old genre in the field - then the fields
  again, with the new genre, and Navidrome - and the web app's Tags - shows it. Again, locking the phone
  the moment you tap Apply: unlocked, does it say what it did, or "deadwax may have finished this - looking again" -
  and never offer the same Apply on the old preview?
- **332 Remove and undo.** Empty a field the track has (Composer, say): "Will be removed" under it, and the preview says
  "removed". **Undo** puts back what the files say, and the preview goes. Turn Wi-Fi and WireGuard off with a field
  typed over: the amber line, Apply dimmed, what you typed kept; back on, the files are read and worked out again
  before Apply comes back.
- **333 Refused as typed.** Type "July 2022" into **Year**: the field says why in amber, "Fix the marked field first.",
  nothing is worked out and Apply is dimmed; "2022-07" puts it right. ("2024-13" is taken, by deadwax too: neither
  checks the month.)
- **334 A track's page.** Tap a track: where it sits ("Track 3, disc 2 of 2 · 4:07 · FLAC"), its tags, its audio, its
  MusicBrainz ids, its file and **All tags in this file** - the same as the web app's track view - and a track with a
  picture inside it lists it ("Front cover", its size once it has loaded), a tap showing it full screen. **Edit this
  track…** opens Edit tags for that track alone. With the largest text and VoiceOver: each track row read as one
  ("Track 3, Title, Artist"), each picture row as "Front cover - see it full size", Undo with its hint, every word
  whole.

### Edit album's Artwork and Lyrics checks (335-337)

**Not done yet.** These come with the build that brings Edit album's [Artwork and Lyrics](#edit-album) into the app -
Phase 8's third part (still app 0.13 (13)). No server change is needed: any deadwax the first part works with. As in
320-329: deadwax's plain `http://` address, on the home Wi-Fi and over WireGuard with Wi-Fi off, as an admin; compare
each with the same album's Artwork and Lyrics in the web app. Edit album's root now has Release, Tags, Artwork and
Lyrics as pages of its own, and only Delete album… opening the web app, "Delete album… opens the album in the web app,
in Safari, until the app has it." under it.

- **335 A missing cover.** An album matched to a release with no cover (Needs a look's "No cover art"): Edit album >
  **Artwork** says "No cover is saved with the album." over **Get cover**. Tap it: "Getting the cover…", then the
  cover shows here, on the root's header and - after a moment - on the album page, and the button has gone. An album
  whose release has none on the Cover Art Archive: "The Cover Art Archive has no front cover for that release." and
  **Look again**. An album with a cover: tap it for full screen; "To replace it, … (Compare covers…)" opens Compare
  covers. An album with no release: "To get a cover, first match the album to a release on the Release page." opens
  Release.
- **336 CD art.** An album matched to a release with CD art on the Cover Art Archive (or with a fanart.tv key set):
  **Get CD art**: "Getting CD art…", then the pictures in the grid with their names - "disc.jpg", or one a disc - each
  opening full screen on a tap, and "deadwax never replaces CD art it saved." where the button was: there is no second
  Get. Does the web app's Artwork show the same pictures?
- **337 Lyrics.** An album with tracks missing lyrics: **Lyrics** says "8 of 12 tracks have lyrics saved beside them,
  as a .lrc." **Get lyrics**: "Getting lyrics…", then how many it saved ("Saved lyrics for 3 tracks (2 synced), 1 not
  on LRCLIB."), the line over it counting them and the root's row with it; the button says "Lyrics · 11 of 12". Play a
  track it saved them for, once Navidrome has scanned: Now Playing shows them. With every track done: "Every track
  has lyrics." Then, as 325: lock the phone the moment you tap Get lyrics on a long album - unlocked, does it say what
  it saved, or "deadwax may have finished this - looking again" with the count read again? While a Get runs, are
  Release's and Edit tags' Apply dimmed, and Close? With the largest text and VoiceOver: each CD art picture read as
  "disc.jpg - see it full size", the cover as "See the cover full size", every word whole.

### Edit album's Delete checks (338-342)

**Not done yet.** These come with the build that brings Edit album's [Delete album](#edit-album) into the app - Phase
8's fourth part (still app 0.13 (13)). No server change is needed: any deadwax the first part works with. As in
320-329: deadwax's plain `http://` address, on the home Wi-Fi and over WireGuard with Wi-Fi off; compare each with the
same album's Delete tab in the web app. **There is no undo**: delete only folders put in the library for these checks
(a test album filed from a download, or copied in), never one you want. Edit album opens the web app nowhere now -
Release, Tags, Artwork, Lyrics and Delete album… are all pages of its own.

- **338 Edit albums alone.** Signed in as someone an admin gave Edit albums but not Look after the library: Edit album
  has Release, Tags, Artwork and Lyrics, and Needs a look's issues - but no **Delete album…** and no **It's fine as it
  is**.
- **339 What it deletes.** As an admin, a test album with a rip log or a cue sheet beside its tracks: **Delete
  album…** says "Checking what's in there…", then its tracks and size ("12 tracks · 412 MB", as the web app's Delete
  tab says), "and 1 other file:" in amber over "rip.log", and - with logins on - who has it ("In your library and
  ana's: …", "Nobody has it in their library."). **Delete permanently** is dimmed until all of that has shown. Open it
  with Wi-Fi and WireGuard off: the amber line, Delete permanently dimmed; back on, it's read again.
- **340 Delete.** **Delete permanently**: "Delete Dummy?" and "There is no undo.", Delete in red and Cancel in bold -
  **Cancel** deletes nothing. Again, and **Delete**: "Deleting…", then the sheet closes, the album page goes back, and
  the Library no longer lists the album (pull down if it still does once Navidrome has scanned); nor does the web app's,
  and the folder has gone from the disk. An album kept as one folder per disc: deleting one disc's folder keeps the
  album page, which shows the other discs once Navidrome has scanned.
- **341 Downloaded, then deleted.** Download a test album to the phone, then delete it: its songs still play from the
  phone (find it under the Library's Downloaded), and its page says "This album isn't in the collection any more - the
  songs on this phone still play.", with only Remove Download.
- **342 Look after the library alone.** Signed in as someone with Look after the library but not Edit albums: Edit
  album has the header and **Delete album…** only - no Release, Tags, Artwork, Lyrics or Needs a look. With the
  largest text and VoiceOver on the Delete page: every line whole, Delete permanently read as a button, and the
  question's Delete and Cancel.

### The artist tools' checks (343-348)

**Not done yet.** These come with the build that brings [the artist tools](#managing-an-artist) into the app - Phase
8's fifth part (still app 0.13 (13)). Artist images' pictures need deadwax **2.1.32** or later (`:experimental`):
an older one has no relay, and every picture shows as its name with why. As in 320-329: deadwax's plain `http://`
address, on the home Wi-Fi and over WireGuard with Wi-Fi off; compare each with the same artist's page in the web app.
Artist images and Move albums write into the library: use an artist whose pictures and folders you don't mind changing
(a test album filed under an old name, or copied in).

- **343 The artist's •••.** As an admin: an artist with albums has **•••** at the top right with **Artist images…**;
  one the page can't say who is on MusicBrainz (no MusicBrainz tags in their albums, and none in Navidrome) has **Which
  artist is this?** too; one the library files under an old name as well as their name now (a test album tagged
  "Kanye West", with Ye's MusicBrainz id) has **Move albums to Ye…**. Does each match what the web app's artist page
  offers? With Wi-Fi and WireGuard off, the ••• has gone; back, it's back.
- **344 Pictures.** **Artist images…**: "Looking for pictures of …", then "Showing … (…)" and a section per slot, the
  best picture of each large. Does each picture appear, scrolling smoothly - none left blank? **Use another picture
  (N)**: the grid; tap one (it's ringed, with a tick), tap it again (not chosen). Choose a square image, **Save**:
  "Saved artist.jpg." (or the names it wrote), and the page's round picture is the new one; **In their folder now**
  lists it. Do the same pictures show in the web app's Artist images? With no fanart.tv or TheAudioDB key set: the note
  about the keys, and only Wikimedia Commons' pictures. Choose another picture for a slot, then turn Wi-Fi and
  WireGuard off and on: once deadwax is back and has looked again, is your choice still chosen? Lock the phone the
  moment you tap Save: unlocked, does it say what it saved, or "deadwax may have finished this - looking again" and the
  folder looked at again? Open Artist images again after a save: is the new picture shown, not the old one?
- **345 Replace.** With a square image already in their folder, choose another and **Save** with **Replace pictures
  that are already there** off: "Nothing needed writing.", and the folder's picture is the one it was. On, Save again:
  the new picture is in the folder and on the page. Choose something else, then Close: "Discard changes?" (Edit
  album's question), and a swipe down doesn't close it.
- **346 Which artist.** On an artist the page can't place, **Which artist is this?**: its note, then every artist going
  by the name, each with what tells them apart. Search other words: only the newest list shows. Pick one: the sheet
  closes, "You chose who this is, for this visit." under their name, their albums you don't have join the list, and
  **Artist images…** shows that artist's pictures. Leave the page and open it again from the Artists page: still
  chosen until the app is closed (or you sign out).
- **347 Move albums.** On the test artist, **Move albums to Ye…**: "Working out the moves…", then the note with
  **Ye/** in bold, **Albums that move** - each folder, "→ Ye/…" and "12 tracks, 12 retagged" - and **Albums that stay**
  with why. Does it list what the web app's Move albums lists? **Move 1 album**: "Moving…" (Cancel dimmed, a swipe
  doesn't close it), then "Moved 1 album into Ye/." with what came with it, and **Done**. Once Navidrome has scanned,
  does it list the album under Ye alone, and the web app's page agree? The old name's page, if every album moved,
  says the artist isn't here any more. Then as 344, lock the phone the moment you tap Move: unlocked, does it say
  "deadwax had finished: …" with **Done**, or how many had moved with the rest offered to move again - never stuck on
  "looking again"?
- **348 Without the permissions.** Signed in as someone with neither Edit albums nor Look after the library: no
  **•••** on any artist's page. With Edit albums alone: Artist images… (and Which artist is this? where 343 had it),
  never Move albums. With Look after the library alone: only Move albums, and no ••• on an artist with nothing to
  move. With the largest text and VoiceOver: the ••• read as "More for
  this artist", each picture read with its name and where it's from ("…, from fanarttv") and "Chosen" on the one
  chosen, every line whole in all three sheets.

### Needs a look's checks (349-354)

**Not done yet.** These come with the build that brings [Needs a look](#needs-a-look) into the app - Phase 8's sixth
part (still app 0.13 (13)). No server change is needed: any deadwax the first part works with. As in 320-329:
deadwax's plain `http://` address, on the home Wi-Fi and over WireGuard with Wi-Fi off, as an admin unless said;
compare each with the web app's Needs a look (the desktop sidebar's Manage → Needs a look). Fixing and deleting write
into the library: use albums put in it for these checks (a test album filed from a download, or copied in).

- **349 The count.** Settings > Manage > **Needs a look** has a number at its right: is it the web app's count beside
  Needs a look? With VoiceOver: "Needs a look, 3 albums" (the number it shows). Open an album from it, mark it fine,
  close Edit album and go back: is the number one less, without a pull? On Settings, lock and unlock the phone after
  marking one fine in the web app: does the number follow? Leave the app on the Library tab, mark another fine in the
  web app, then open Settings: the number follows as it opens. With nothing to look at, nothing at the row's right -
  and no tab ever shows the count. With Wi-Fi and WireGuard off, the number stays as it was.
- **350 The list and Show.** Open Needs a look: "Reading the library", then the same albums in the same order as the
  web app's All, each with the same chips (New, then its issues), headed "All · N". **Show** (top right): All, Newly
  added, each kind of issue and Marked fine, with the web app's counts. Pick Newly added: only the new downloads, the
  heading "Newly added · N", the menu's symbol filled. Pick Marked fine: the albums you marked fine, each saying so.
  Back to All. Pull down: "Checking the library…" under the heading while it's read, and no row moves when the line
  comes and goes.
- **351 Working through.** Tap the first album: Edit album, with ‹ (dimmed), "1 of N" and **Skip ›** at its foot.
  Skip: "2 of N", the second album, and ‹ is on; ‹ goes back to the first. Mark one fine (or apply a release): Skip
  becomes **Next album ›**. On "2 of N", open a picture full size - Release > Compare covers, Artwork's cover, or a
  track's picture in Tags - and close it: ‹, "2 of N" and Skip are still at the foot, and Skip goes on to the third.
  Close: its row says **Marked fine** (or **Fixed**) in green and stays where it was; once the library has been read
  again, is it gone from the list - and from the web app's?
- **352 Looked at.** A test album filed from a download (New): open it from Needs a look and Skip past it (or Close).
  Once the list is read again, is it no longer New - in the web app too - and the count one less, if New was all that
  was wrong with it?
- **353 Not in Navidrome, deleted and gone.** An album Navidrome doesn't list (a folder Navidrome can't read, or
  before its scan) shows "Not in Navidrome" and opens by its folder. Delete a test album from the run (Delete album… >
  Delete permanently): Edit album stays up, saying "Deleted …", with Next album; its row says **Deleted**. In the web
  app, delete (or move) the album after the one open on the phone, then tap Skip on the phone: Edit album closes, and
  the list is read again.
- **354 Edits, reach, and who.** Type in a Release field, go back to Edit album's first page and tap Skip: "Discard
  changes?" - Keep editing keeps it, Discard steps on. On an album that needs a release, tap Apply on its Release
  page, then go straight back to the first page: ‹ and Skip are dimmed until the apply is done and the library has
  been read again - Skip then says Next album. Tap "It's fine as it is": the same, until the album has been read
  again. Wi-Fi and WireGuard off: the steps dimmed; on Needs a look the amber line at the top, the rows can't be
  tapped, and a pull asks nothing - back on, "Checking the library…" and the list read again. Open Needs a look from
  Settings while off: "Managing needs deadwax. This opens once it's back.", then the list once it's back. As a second
  person (logins on) on Needs a look, have an admin reset their password in People on the Mac (it ends their
  sessions): the sign-in comes over the app; lock and unlock the phone, Wi-Fi off and on - then sign in again: the list
  is read again, with no "Couldn't check the library just now." left over, and Settings' count is the web app's. As
  someone with Look after the library but not Edit albums: the top line ends "to see what it has, or to delete it." with
  "Fixing it needs Edit albums, which an admin hasn't given you."; an album opens with Delete album… alone. With the
  largest text and VoiceOver: each row read once ("The Slow Rush, Tame Impala, New, No cover art"), Show as "Show,
  All", the foot's "Previous album", "2 of 9" and "Skip", each step said ("3 of 9: …"), every line whole. With Reduce
  Motion on, rows don't slide.

### Library care's checks (355-360)

**Not done yet.** These come with the build that brings [Library care](#library-care) into the app - Phase 8's seventh
part (still app 0.13 (13)). No server change is needed: deadwax 2.1.28 or later rescans without the tracks, which an
older one sends whole - slower, the same. As in 349-354: deadwax's plain `http://` address, on the home Wi-Fi and over
WireGuard with Wi-Fi off, as an admin unless said; compare each with the web app's Library care (the desktop sidebar's
Manage → Library care). The runs write covers, CD art and lyrics into album folders: narrow them to albums put in the
library for these checks.

- **355 Rescan.** Settings > Manage > **Library care**: the line at the top, then Rescan with the web app's totals
  ("7 albums · 87 tracks · 425 MB") and "Scanned … ago in …s". Tap **Rescan**: "Rescanning…" on the button and
  "Rescanning - reading every file again…" above it, then "Scanned just now", and the same totals as the web app's.
  Leave the page up a few minutes: does the age move on ("Scanned 2 min ago")? Change a tag of a test album in another
  program, Rescan: does Edit album show the new tag?
- **356 Fill in covers.** Narrow to a test album without a cover (its Get cover in Edit album not pressed). **Get
  covers · 1**: the button says "Stop after this album · 1 of 1" with a spinner, and "The screen stays on while a run
  is under way and this page shows." under it; then "Got 1 cover." (VoiceOver reads it), "Checking the library…" for a
  moment, and no Get covers button for it after. Does the album show its cover in the Library? With a run of several
  albums (Narrow to an artist with a few), tap Stop: "Stopping after 2 of 5", then "Got … Stopped at 2 of 5." Leave the
  phone untouched through a long run on the page: does the screen stay on? On another page, does it dim and lock as it
  usually does? Do the same with CD art and lyrics.
- **357 Narrow to.** Type an artist's name: "The runs act on 3 of 8 album folders: those matching "…"." and each
  run's count and words follow, as in the web app with the same words typed. Type something nothing matches: "No album
  folder matches "…".", and no button. While a run goes, the other two buttons are dimmed, with "One run at a time -
  this one can start once Covers has finished."
- **358 Locked mid-run.** Start a run of a dozen albums or more, then lock the phone. Unlock after a minute and open
  Library care: does it say "Stopped at N of M. It stopped as the app went to the background - Get covers carries on."
  - and N the album it was on, not fewer? Start again: is the count only the albums still without? The same switching
  to another app instead of locking. Start one, go back to Settings and to the Library tab, come back: is it still
  going (or done), its result there? Wi-Fi and WireGuard off mid-run: "… It stopped as deadwax went out of reach - Get
  covers carries on once it's back.", the amber line, nothing can be pressed - back on, "Checking the library…", then
  Start is offered again. Off and straight back on while "Checking the library…" shows: does Start still come back,
  rather than the note staying? As a second person (logins on), start a run, then on the Mac reset their password in
  People (it ends their sessions): the sign-in comes over the app - sign in again: "… It stopped as your session ended
  - sign in again, and Get covers carries on.", the library read again with no "Couldn't read the library just now."
  left over, and Start offered again. The same on In nobody's library: no "Couldn't read who has which albums." left
  once signed in again.
- **359 In nobody's library** (logins on). Under the runs, **In nobody's library**: tap it - the same count and the
  same first 20 albums as the web app's, Show all and Show fewer. With a flagged download (a download of a pressing
  whose folder already held another): its name, who asked and why, **Add for them** and **Dismiss**. Add for them: the
  flag goes, and the people who asked have the album in their library (the web app's Your library, as them). Dismiss
  another: it goes. Press Dismiss on one already dealt with in the web app: "That has been dealt with already." With
  logins off there's no such row.
- **360 One part each.** As someone with Look after the library but not Edit albums: Rescan, and In nobody's library,
  no runs - the top line "Rescan reads every file of the library again - use it after changing tags in another
  program.". As someone with Edit albums but not Look after the library: the runs alone, no Rescan, no In nobody's
  library - and the Manage footer "Edit an album and Library care are the app's own; …" (or none, if those are their
  only rows). Take Edit albums away on the Mac during a long run, and leave the phone on Library care: deadwax refuses
  the next album and the run stops there, with nothing pulled down - with VoiceOver on, it says "… 1 failed - run it
  again to try it again. Stopped at N of M. It stopped: running it needs Edit albums, which an admin hasn't given
  you." - and Library care has no runs any more (or says it needs a permission, if they were all the person had).
  With the largest text and VoiceOver: each line read once, the run's button read with its count, every line whole.
  With Reduce Motion on, nothing slides.

### Server settings' checks (361-369)

**Not done yet.** These come with the build that brings [Server settings](#server-settings) into the app - Phase 8's
eighth part (still app 0.13 (13)). No server change is needed: any deadwax the first part works with. As in 355-360:
deadwax's plain `http://` address, on the home Wi-Fi and over WireGuard with Wi-Fi off, as an admin unless said;
compare each with the web app's Server settings (the desktop sidebar's Manage → Server settings) and Connections (a
section of the web app's Settings). These
change how the server runs: change only what you'll put back, and note each setting's value before you start.

- **361 The root.** Settings > Manage > **Server settings**: the line about the compose file, then **Connections** -
  MusicBrainz, slskd and Navidrome, "Checking…", then each as the web app's Settings says it (Connected, Navidrome
  with its version). Then the organizing verdict, the web app's, and **Library**, **Downloads** and **Connections**,
  each group the web app shows under that tab, in its order. Is any group marked **Needs attention** where the web
  app's tab has its dot? Tap **Check again**: "Checking…", then the same. Stop slskd for a moment (only if you can):
  Check again says "Can't reach it" or "Not on Soulseek" under slskd, with the web app's sentence - press and hold it
  to select it. Start it, Check again: Connected. With VoiceOver: each row read once ("slskd, Connected").
- **362 A menu.** Open **Cover art** (or When a download fails): a setting with choices is a menu, its value the web
  app's. Pick another: the group's row and the setting say **Unsaved**, and the bar at the foot "1 unsaved change".
  **Save changes**: "Saving…" on the button, then "Saved." (VoiceOver reads it), and "Set here" under it. Does the
  web app's page, read again, show the new value? Put it back the same way.
- **363 Changes across pages.** Change a setting in Cover art, go back, change one in Soulseek searches, go back to
  Settings, to the Library tab, then back to Server settings: both rows say Unsaved, the bar "2 unsaved changes" on
  every Server settings page. **Discard**: both gone. Make them again, and one **Save changes** saves both. Type
  `abc` in `SLSKD_SEARCH_TIMEOUT` and save: "Not saved: SLSKD_SEARCH_TIMEOUT: expected whole seconds, 3 to 60 - 8 is
  the default" in red, nothing saved - the other change still Unsaved. Put the timeout right and save.
- **364 A secret.** Connections' `SLSKD_APIKEY` (or `FANARTTV_KEY`): "•••••••• (set)" in the field, never the key,
  and a secure field when you type (the keyboard has no suggestions). Type the same key again and save: "Saved.", and
  the field shows "•••••••• (set)" again, empty of what you typed. Does slskd still say Connected?
- **365 An address without its secret.** Change `NAVIDROME_URL` to another address (one letter different), and
  leave the password: under `NAVIDROME_PASSWORD`, "Type the password again to go with the new address - deadwax
  won't send the saved one to an address it wasn't entered for." Save: "Not saved: NAVIDROME_URL: type the Navidrome
  password again with the new address - deadwax won't send the saved one to an address it wasn't entered for", and
  nothing saved. Discard.
- **366 Revert to the environment.** A setting saved here (362's, before you put it back): "Set here", and **Revert
  to the environment (…)** with the compose file's value. Tap it: "Will revert to the environment on save.", Unsaved,
  the bar "1 unsaved change". Save: "From the container environment" (or "From .env"), the compose file's value, and
  no Revert. Does the web app agree?
- **367 MusicBrainz's saved answers.** Open **MusicBrainz's saved answers**: the line is the web app's ("… answers in
  … MB saved, of 200 MB."). Tap **Clear MusicBrainz's saved answers**: "Clear MusicBrainz's saved answers?" with
  Clear and Cancel. Cancel: nothing changes. Clear: "Cleared. The next answers are asked of MusicBrainz again.", and
  the button dimmed with nothing to clear. Search for an artist in the app, come back: the line counts again. Change
  `MUSICBRAINZ_CACHE_PATH` without saving: "Save the new path first.", Clear dimmed. Discard.
- **368 Re-time saved lyrics.** Open **Lyrics**: **Re-time saved lyrics** under the lead. Tap it: "Reading the
  library…", then "Re-timing 1 of N albums · Stop after this album" and "The screen stays on while it runs and this
  page shows."; it ends saying what it did, as the web app's would ("Re-timed … tracks, … already at this lead.").
  Change `LYRICS_LEAD_MS` without saving: "Save the new lead first.", the button dimmed - Discard. Start it again and
  tap the button: it stops after the album it's on ("… Stopped at 3 of N albums."). Start it and lock the phone:
  unlock, and does it say "It stopped as the app went to the background - running it again carries on."? As someone
  with Settings and the log but not Edit albums: "Re-timing needs Edit albums, which an admin hasn't given you." and
  the button dimmed.
- **369 Set up Navidrome.** Only if you can take Navidrome's address away for a moment (on a test setup, with logins
  off - with them on, signing in needs Navidrome too): in Server settings > Connections, note `NAVIDROME_URL`, clear
  it and save. On the Library tab (pull down if it still shows albums): "Connect Navidrome" with **Set up
  Navidrome**. Tap it: the Connections page as a sheet, Navidrome "Not set up". Type the address back, and the
  password again (the note under it asks for it), and **Save changes**: does the sheet go and the Library fill,
  without a pull? Again, but tap **Close** after typing: the sheet goes, and Settings > Manage > Server settings has
  the changes Unsaved, ready to save. While a save goes, Close is dimmed and the sheet can't be swiped away. With the
  sheet up and something typed, turn Wi-Fi and WireGuard off: the sheet stays (it doesn't close as the Library's gate
  gives way), with the amber line, Save changes dimmed - your typing kept; back on, the settings read again and Save
  changes on, and saving it still closes the sheet as Navidrome answers. Tap Save changes and turn Wi-Fi and
  WireGuard off straight away: the sheet stays; if the save got no answer, once back "deadwax may have finished this -
  looking again", then "Saved." (or what is left to save). Signed in as someone without Settings and the log: no
  Server settings in Manage.

### Event log's checks (370-373)

**Not done yet.** These come with the build that brings the [Event log](#event-log) into the app - Phase 8's ninth
part (still app 0.13 (13)). No server change is needed: any deadwax the first part works with. As in 361-369:
deadwax's plain `http://` address, on the home Wi-Fi and over WireGuard with Wi-Fi off, as an admin unless said;
compare each with the web app's event log (the desktop sidebar's Manage → Event log) open on the Mac beside it.

- **370 Live.** Settings > Manage > **Event log**: "Connecting…" under the bar, then "Live" with a green dot, the
  line about the page, and the lines newest first - the same lines as the web app's, in its order. Search for an
  album in the app (or tap Find on a request): do its lines arrive at the top as the search runs, at the same moment
  as on the Mac, without a pull? Leave the page open and quiet for two minutes: does it stay "Live"? With VoiceOver,
  each line is read once, its words first.
- **371 Levels and Copy.** Find an ERROR line and a WARNING line (a search slskd refuses, or a download that fails,
  makes one): the error's level and words red, the warning's amber, an INFO line plain. Each line's time is the
  phone's clock, as the Mac's page has it. Press and hold a line: **Copy**. Paste it into Notes: its time, level,
  part and words, as drawn. At the largest text size (Settings > Accessibility > Display & Text Size > Larger Text),
  a line's time, level and part stack over its words, nothing cut off.
- **372 Clear.** Tap **Clear** in the bar: "Cleared. New lines show here as deadwax logs them.", and Clear dimmed. Is
  the web app's log still full (reload it)? Go back to Settings, search for something, come back to Event log: only
  the lines since - none of what was cleared. Put the app in the background for a minute, search on the Mac, come
  back: the lines logged meanwhile are there, each once. The same with Now Playing opened over the page instead
  (the mini player), and put away.
- **373 Dropped.** With the page live over WireGuard, turn WireGuard off: within 45 seconds, "Lost the live feed -
  reconnecting…" in amber (and the amber line, if the app notices deadwax is out of reach), the lines kept. Search on
  the Mac meanwhile. Turn WireGuard on: "Live" again, and the Mac's search's lines are there - none missing, none
  twice. With VoiceOver: "Lost the live feed - reconnecting…" as it drops, unless the app's own out-of-reach line
  is said at that moment instead (then "Back online", and not "Live", as it returns) - never two said over each
  other. Signed in as someone without Settings and the log: no Event log in Manage.

### Change password's checks (374-378)

**Not done yet.** These come with the build that brings [Change password](#change-password) into the app - Phase 8's
tenth part (still app 0.13 (13)). No server change is needed: any deadwax the first part works with. Use deadwax's
plain `http://` address, on the home Wi-Fi, signed in as yourself (not the emergency `deadwax` sign-in), with the web
app open on the Mac as you too. You'll change your Navidrome password twice - to a new one, and back - so have both to
hand, and Amperfy's settings open to put it in there after.

- **374 The form.** Settings > Account > **Change password**: the line with your name at the top, **Current
  password**, **New password** and **New password again**, then the plain-http note in amber and "Amperfy and any
  other app you use with Navidrome need the new password too." under them, and **Change**, dimmed. Type a new password
  of 4 characters in both new fields: "A password is at least 8 characters." under them. Make the two differ: "The two
  passwords aren't the same." Type your current password as the new one: "That's the password you have now - type a
  new one." Change is dimmed throughout. Does the password manager offer to fill Current password, and to suggest a
  new one? With VoiceOver: each field read once by its name. Turn on Airplane Mode: the amber line at the top, Change
  dimmed.
- **375 Wrong current.** Type a wrong current password and a good new one twice: **Change** - "Changing…", then
  deadwax's words in red, "That isn't your current password - …", the current field emptied with the cursor in it,
  the new ones kept. (With VoiceOver on, the cursor stays put and the words are read once.) Is your password unchanged
  - does the web app on the Mac still work, and Amperfy?
- **376 Changed.** Play an album. With the web app open on the Mac (and Amperfy signed in), type the right current
  password and a new one twice: **Change**. The page says "Password changed. Signed out of your other device - it signs
  in again with the new one. You're still signed in here." (or how many), every field emptied. Does the music play
  on, and does the app go on working - pull down the Library, open an album - without asking you to sign in? On the
  Mac, reload the web app: the sign-in, saying your password changed. Sign in there with the new one. Amperfy needs
  the new one too.
- **377 Downloads across it.** Start downloading an album of ten or more songs (Settings > Downloads shows them going).
  Mid-way, change the password (back to the old one, say). Does every song still download - the ones going at that
  moment carried on, none left waiting, no sign-in asked? Settings > Downloads afterwards: nothing waiting or failed.
- **378 Kill and reopen.** After a change, swipe the app away in the app switcher and open it again: still signed in,
  straight to the Library, no sign-in. Put the password back to the one you started with (Change password again), and
  in Amperfy.

### People's checks (379-387)

**Not done yet.** These come with the build that brings [People](#people) into the app - Phase 8's eleventh part
(still app 0.13 (13)). No server change is needed: any deadwax the first part works with. Use deadwax's plain
`http://` address, on the home Wi-Fi, with logins on, signed in as a Navidrome admin, with the web app's People open on
the Mac beside it. You'll make a throwaway account and remove it again: pick a name nobody uses ("phonetest").

- **379 Unlock.** Settings > Manage > **People**: the page, not Safari. "People changes Navidrome's accounts as you, …",
  **Your Navidrome password**, **Unlock** dimmed until something is typed, and the plain-http note. Does the password
  manager offer your password? Type a wrong one: **Unlock** - "Unlocking…", then "That isn't the password you signed in
  to deadwax with - …" in red, the field emptied with the cursor in it. Type the right one: the unlocked line, **Lock**
  and **+** in the bar, Everyone in Navidrome - the same people as the Mac's, you first - and Known only to deadwax if
  the Mac shows it. With VoiceOver, each row is read once.
- **380 A person.** Tap someone who isn't an admin: their page - their name and facts, then the five switches with
  their lines, and Reset password…, Make admin and Remove…. Tap your own row: the switches all on and dimmed, "Admins can
  do everything." and "That's you - change your own password in Settings → Account → Change password." under the
  changes, with no Reset password… or Remove….
- **381 Add a person.** **+**: the sheet. Type "Phone Test" as the user name: "A user name is lowercase letters, …"
  under the fields, **Make account** dimmed. Type "phonetest", a display name, and a password of 4 characters twice:
  "A password is at least 8 characters." Fix it: **Make account** - "Making…", then "Made phonetest. Tell them their
  user name, …" with deadwax's address, the form emptied and **Done**. Close it: phonetest is in the list, and in the
  Mac's People when it's read again.
- **382 Permissions.** Open phonetest: turn **Edit albums** on - **Save permissions** comes on - and **Save
  permissions**: "Saved - phonetest has them from their next tap." Reload the Mac's People: Edit albums ticked there.
  Turn **Look after the library** on: its amber line about deleting albums. Go back without saving and open phonetest
  again: the switch is as you left it, still unsaved.
- **383 Reset and the admin role.** On phonetest's page, **Reset password…**: two new-password fields, the plain-http
  note; a good password twice, **Reset password**: the sheet goes and "Done. phonetest is signed out of deadwax on 0
  devices …" on their page. **Make admin**: the question, saying what it gives - **Make admin**: "phonetest is an admin
  now.", the switches all on and dimmed. **No longer admin**: the question says they keep every library and what they
  had ticked - **No longer admin**, and the switches are back as they were.
- **384 Remove.** **Remove…**: what goes, what stays, "There's no undo. …" in red. Type "Phonetest": **Remove
  phonetest** stays dimmed; press Return: only the keyboard goes. Type "phonetest": **Remove phonetest** - "Removing…",
  then the sheet and the page go, and "Removed phonetest from Navidrome and deadwax." over the list, without them. The
  Mac's People agrees when read again.
- **385 Locked again.** Unlock, then leave People open and the phone alone (or locked) for 16 minutes: back on the
  page, Unlock People is there, not the list. Unlock again, and tap **Lock** in the web app on the Mac: that ends the
  Mac's unlock, not the phone's - the phone's list stays. Tap **Lock** on the phone: Unlock People at once.
- **386 Busy, and out of reach.** Unlock, open **+** and type a user name and two passwords, then turn on Airplane
  Mode: the amber line at the top, **Make account** dimmed. Turn it off, close the sheet, pull down on People, open **+**
  again: the names are still there, the passwords not. Type them and make the account: while "Making…" shows, Close is
  dimmed and a swipe down doesn't close the sheet. Remove it again (384). Then **Lock**, type your password into Unlock
  People without tapping Unlock, open Now Playing from the mini player and put it away: the field is empty.
- **387 The largest text, and VoiceOver.** At the largest text size, every row, switch line and sheet wraps, nothing
  cut off. With VoiceOver: each person's row read once ("Ethan, ethan, Signed in on 2 devices, 3 albums in their
  library"), each switch with its line and whether it's on, and what each change said read once - nothing read while
  the sign-in is over the app.

### No way out to the web app's checks (388-391)

**Not done yet.** These come with the build that takes the last of the app's way out to the web app away - Phase 8's
last part (still app 0.13 (13)). No server change is needed. Sign in as an admin, with logins on, on deadwax's plain
`http://` address; 390 wants Wi-Fi and WireGuard off for a while. Nothing in these should open Safari unless it says
so - if Safari comes up anywhere else, say where.

- **388 Nothing opens Safari to deadwax.** Settings > Manage: tap **Edit an album**, **Needs a look**, **Library
  care**, **People**, **Server settings** and **Event log** in turn - each pushes a page of the app's own, with Back,
  and no row has an arrow out at its right or a line under it about the web app; nothing is said under the rows. An
  album's top **•••**: **Edit album** opens its sheet over the tabs, **Album info** its own. An artist's top **•••**:
  **Artist images…**, **Which artist is this?** and **Move albums to …** (where they show) each open in the app.
  Settings > Account: **Change password** pushes its page, with no line under it. And, only if you can take
  Navidrome's address away for a moment on a test setup, the Library's **Set up Navidrome** opens Server settings'
  Connections over the Library. Safari opens for none of them.
- **389 What still opens outside.** Album info's **This pressing on MusicBrainz** and **Every pressing on
  MusicBrainz** open musicbrainz.org's pages in your browser (Safari unless you've changed it); the foot of an EQ
  correction's page, **AutoEq on GitHub**, AutoEq's page there. Each time the music keeps playing, and coming back to
  the app finds the page you left. Is there anywhere else something opens outside the app? (The third link out,
  People's **Sharing deadwax**, shows only if logins are turned off on deadwax while the app is open, so it isn't a
  step here; deadwax's tests keep it to the guide on GitHub.)
- **390 Offline.** Quit the app from the app switcher and open it again, so nothing managing has been read yet; turn
  off Wi-Fi and WireGuard, then open each of Manage's rows: no row is dimmed, none opens Safari, and each page says
  "Managing needs deadwax. This opens once it's back." and asks nothing (Account's Change password shows the amber line
  at its top and **Change** dimmed). Open Server settings while still offline, then turn the network back on: it fills
  in by itself, without going back. Open Needs a look with the network on, then turn it off: what it shows stays, under
  "deadwax is out of reach - this is how it was, and nothing here can change until it's back."; turn it on again and
  the line goes by itself.
- **391 The largest text, and VoiceOver.** At the largest text size, go through Manage's six pages, Edit album's,
  the artist's sheets, Change password and People: every row and line wraps, nothing cut off. With VoiceOver, Manage's
  rows read as rows that open a page ("Needs a look, 3 albums"), never "Opens in Safari."; Album info's MusicBrainz
  links are the only ones that say "Opens in Safari.".

### Add to Queue's checks (392-403)

**Not done yet.** These come with the build that makes [Add to Queue](#adding-to-the-queue) the phone's one way to add
songs - a swipe right on a song, and the one item where every ••• had Play Next and Play Last (still app 0.13 (13)).
No server change is needed. Use an album of a dozen songs, headphones on; the web app keeps Play Next and Play Last.

- **392 The menus.** A song's ••• on an album's page: **Add to Queue**, then Add to a playlist… - no Play Next, no Play
  Last. The same on a playlist's page, All songs (or the Library's Songs page), Search's songs, and the ••• at the
  top of an album's and of a playlist's page. Its symbol is Play Last's (lines, an arrow at the foot).
- **393 The order.** Play an album from song 1. A song of another album, ••• > Add to Queue: "Added to Up Next: …"
  above the mini player; Up Next has it first under Playing Next - it plays next. Add two more: they follow it, in
  the order you added them, all before song 2. Next: the first you added plays; add another: it goes after the two
  still waiting, not straight after the one playing. Once the songs you added have played, the next one you add
  plays next again.
- **394 A whole album, a playlist, and nothing playing.** Another album's top ••• > Add to Queue: all its songs under
  Playing Next, in its order, after any you'd added. A playlist's top •••: the same. With nothing playing (a fresh
  start, or after the queue ended), Add to Queue on a song plays it at once - no line, the mini player shows it.
- **395 Swipe all the way.** On an album's page, swipe a song right as far as it goes and let go: a short tap you can
  feel, the row slides back, and "Added to Up Next: …" - just as its •••'s Add to Queue. There the swipe is iOS's own
  (as in Mail), so where "all the way" begins, and any tick on the way, are iOS's. Then on a playlist's page (the
  same), and on All songs and a song in Search (Top results and Songs), where the swipe is deadwax's: a light tick as
  you pass half the row, and letting go past it adds. Do all four look and feel alike - the purple out from the
  screen's edge, the symbol by the row?
- **396 Swipe part way.** Swipe a song a little way and let go: one purple Add to Queue button stands beside it. Tap it:
  added, and it closes, the purple shrinking back with the row. Swipe again a little, then tap the row: it closes, and
  nothing plays or opens. Again, then scroll: it closes. Again, then swipe another row: the first closes. Swipe an
  open row back left: it closes. On All songs and in Search, open one again and touch somewhere else - another song's
  •••, the search field, the tab bar: it closes as your finger goes down, and what you touched still works (the •••
  opens, the field takes the typing). On the Library's Songs page, open one and turn the page with the switch: it's
  closed when you come back. Then turn on Settings > Accessibility > Motion > Reduce Motion: on All songs and in
  Search the row opens and closes at once, without sliding.
- **397 Nothing else changes.** On each of those lists, flick up and down starting on a song: the list scrolls, no row
  slides, nothing is added. A song's tap and its ••• work as before. On an album's page and All songs, swipe in from
  the very left edge: it goes back, nothing added. The pull to shuffle on an album, a playlist and the Library still
  shuffles. Up Next's rows and the Library's grids have no swipe.
- **398 The Library's Songs page** (logins off, Songs not the first page). A swipe right that starts on a song adds
  it; one that starts at the very left edge of the screen turns back to the page before; a swipe left anywhere turns
  to the page after (if there is one). Is that how you'd want it, or should turning the page win there?
- **399 Offline.** Turn on Airplane Mode. An album with only some songs on the phone: a dimmed song has no swipe and
  no Add to Queue in its •••; a song on the phone swipes and adds. The album's top •••'s Add to Queue adds only the
  songs on the phone.
- **400 VoiceOver.** Focus a song itself (not its •••) on an album's page, a playlist's, All songs and Search, and
  swipe up or down through its actions. On All songs and in Search you should hear **Add to Queue** once. On an
  album's and a playlist's page you should hear it at least once, among the song's download items (Download,
  Remove Download…); you may hear it twice there, one deadwax's and one iOS's own from the swipe - either adds the
  song once. Tell me if it's twice, or if the ••• has one too. Whichever you choose, it adds the song and VoiceOver
  reads "Added to Up Next: …". Settings > Playback > Normalization, Automatic's line: "… a song you add with Add to
  Queue …".
- **401 After going back.** Play an album of six or more to song 5, add a song **a**, then **b** (Add to Queue), and
  press Previous within its first seconds: song 4 plays, and Up Next shows 5, a, b, 6. Add **c**: it goes straight
  after song 4 - c, 5, a, b, 6 - ahead of a and b, as [Adding to the queue](#adding-to-the-queue) says. The same after
  tapping a song in Up Next's history instead of Previous.
- **402 In a song's last seconds.** Play an album, and in the last two or three seconds of song 1, with nothing added,
  Add to Queue a song **a**: song 2 plays next as it would have, and **a** after it (Up Next shows a, 3, …), not
  between 1 and 2. Then add a song early in a song: it plays next, as usual. Does the join into song 2 still sound
  seamless?
- **403 Songs refreshed under an open row.** At the top of All songs, swipe the third song part way open, then pull
  to refresh; on the Library's Songs page (logins off), the same with the Library's ••• > Refresh. The row closes, and
  no other song stands open in its place: a row only ever stands open on the song it was opened on, and its button
  adds that song. Then open one, scroll down until the next page loads, and come back: nothing stands open.

### The Mac app's checks (404-415)

**Not done yet.** These come with [the Mac app](#the-mac-app)'s first build - it runs and plays (still app 0.13
(13)). No server change is needed, and nothing changes on the phone. Use deadwax's plain `http://` address, on the
home Wi-Fi, signed in as an admin with logins on. Install with `ios/scripts/install-mac.sh` from the repo. Say
"pass", or what you saw.

- **404 Install.** First `ios/scripts/install-mac.sh --dry-run`: it says what it would do and does none of it. Then
  `ios/scripts/install-mac.sh`. It says Xcode's version and the free space, "Signing with team …, with no
  provisioning profile", builds (a few minutes the first time - note how long it says), then "Signed, sandboxed,
  allowed out to the network and to open and save a file you choose; net.lizardlounge.deadwax." (before the sixth
  build: "to read a file you choose") and opens deadwax from
  ~/Applications. Does it stop instead with "Not installed: Xcode signed this build with a provisioning profile…"? If
  so, say what it names, and don't use `--allow-profile`. Does macOS ask anything before deadwax opens - and if so,
  what exactly? *Seen on 17 Nov (slice 1's build, installed for you): it built in 2 min 45 s and opened from
  ~/Applications with nothing asked first - no Gatekeeper question and no Open Anyway step, for a build made on this
  Mac. Still to say: the dry run's lines, and the install's own words.*
- **405 The app.** The Dock shows the record icon, on the Mac's own rounded square (not a square inside another).
  The menu bar says **deadwax**: About deadwax (0.13 (13)), Hide deadwax, Quit deadwax - lowercase. The File menu has
  no New Window, and there's no deadwax Help: is the Help menu gone, or still there with only its search field? The
  window is phone-shaped, opens at about 430 x 860, won't go narrower than a phone (390) or shorter than 640, nor
  wider than 600, and shows no title in its title bar. Quit and open: the same size and place.
- **406 Local Network.** macOS asks whether deadwax may find devices on your local network: **Allow**. deadwax connects
  at its `http://` address - try the IP and the name. Does macOS ask for both, or for neither? *Seen on 17 Nov: the
  question came up and you allowed it - "the Mac app opened fine". Still to say: whether it asked once, or once for
  the IP and again for the name.*
- **407 Signed in, kept.** Sign in. Quit (⌘Q) and open it again: still signed in, straight into the Library. In
  Terminal, `ls -l ~/Library/Containers/net.lizardlounge.deadwax/Data/Library/Application\ Support/deadwax/sessions/`
  shows one file, `-rw-------`, named after deadwax's address (macOS may ask whether "Terminal" would like to access
  data from other apps: **Allow** - see [Where the Mac keeps your sign-in](#where-the-mac-keeps-your-sign-in)), and
  `tmutil isexcluded` with the same path says `[Excluded]`: kept out of Time Machine. Sign out (Settings > Account),
  quit, open: the sign-in - and the same `ls` shows no file.
- **408 It plays.** Play an album: the first song starts within a couple of seconds. Click the play bar: Now Playing
  opens over the window, and its Up Next, Info and EQ each open over it and close again; the join between two songs
  that run into each other is gapless (the test album's songs 9 and 10); dragging the scrubber lands where you let go.
  Headphones in: the sound moves to them.
- **409 The media keys.** With another app in front: F8 pauses and plays, F9 next, F7 previous. AirPods: a press pauses.
- **410 The menu bar's Now Playing.** Control Center (or the menu bar's Now Playing) shows the song, the artist and the
  cover; its buttons work; dragging its time moves the song; paused, it shows paused - not playing. Play another app's
  music and come back: does deadwax take Now Playing back when it plays again?
- **411 Picked up.** Play on the Mac, pause. Open the app on the iPhone: its notice says "Picked up from your Mac" (not
  iPhone). And the other way: play on the iPhone, pause, open the Mac app: "Picked up from your iPhone".
- **412 The EQ.** Settings > Playback > EQ on: the sound changes on the speakers; headphones in, they have their own
  (Off until set). What does the EQ call the Mac's speakers? On an EQ page, **Import…** (Import from Files… before the
  fourth build): the Mac's Open panel, and a ParametricEQ `.txt` you choose there (one in Downloads, say) shows its
  preview - no "couldn't be opened" or permission error. **Export…** > The Whole Curve: what does the Mac's Share menu
  offer?
- **413 Every tab, once.** Library (its pages, an album, an artist), Search (yours and MusicBrainz's), Requests (Get an
  album), Lyrics on Now Playing, Up Next, Settings' pages, and Manage's six. Anything that doesn't open, closes the
  app, or looks broken? There's no pull to refresh anywhere on the Mac - the Library's ••• > Refresh brings the
  Library up to date: does it? Does the pull down that shuffles your library work with the trackpad? Which controls
  look like the Mac's rather than the phone's, and is any text too small or too big? Does Now Playing's AirPlay button
  list the house's speakers?
- **414 Install over it.** With deadwax open and playing, run install-mac.sh again: once it has built, it asks to quit
  deadwax; yes - the music stops, the new build opens, still signed in, settings and downloads kept. The first time,
  does macOS ask whether Terminal may control deadwax? Then once more with **n**: it stops, saying the new build is
  ready, and deadwax plays on. Once with `--yes --no-pull`: it still asks. And once with `--quit --no-pull`: it says
  "Quitting deadwax (--quit).", asks nothing, and the new build opens.
- **415 A week on.** Eight days after an install, deadwax still opens. Settings > This Mac > Debug says "This install
  doesn't expire: a Mac keeps opening deadwax without installing it again." (Builds before the fourth: Settings > This
  phone > Debug, "No install date to show: this build wasn't signed for a phone.")

### The Mac app's menus, keys and window checks (416-423)

**Not done yet.** These come with [the Mac app](#the-mac-app)'s second build - menus, keys, right-click and the window
(still app 0.13 (13)). No server change is needed, and nothing changes on the phone. As for 404-415: deadwax's plain
`http://` address, the home Wi-Fi, signed in as an admin with logins on, installed with `ios/scripts/install-mac.sh`.
Say "pass", or what you saw.

- **416 The menus.** The deadwax menu has **Settings…** ⌘, - it opens the Settings tab. **Controls** has Play, Next,
  Previous, Forward 10 Seconds, Back 10 Seconds, Shuffle, Repeat (a submenu: Repeat off, Repeat all, Repeat one) and Go
  to Current Song - every one dimmed with nothing queued. Play an album: Play becomes **Pause** while it plays, without
  opening the menu twice? Repeat's tick follows Up Next's button, and Shuffle's tick its Shuffle; during the Library's
  Shuffle, the item reads **Shuffle - shuffling your whole library** (**Shuffle - shuffling all music** in All), ticked
  and dimmed. **Edit** has **Find** ⌘F: are Spelling and Grammar, Substitutions and the rest gone from it - and are
  Undo to Select All still there? **View** has **Refresh** ⌘R. File has no New Window, there's no Help menu - and is
  there a Format menu at all, or an empty one? Open Up Next, or Edit album: Settings…, Find, Refresh and Go to Current
  Song are dimmed until it's closed.
- **417 Space.** With the window in front, Space pauses and plays, on any page. Click in Search's field and type two
  words: Space types a space and the music doesn't stop; ⌘← and ⌘→ go to the start and end of the line, nothing skips.
  The same in the Library's Find. Click out of the field (on a song's page, say): Space pauses again.
- **418 The arrows.** ⌘→ goes to the next song, ⌘← to the one before (past the first few seconds, the song again from
  its start, as Previous does). ⌥⌘→ and ⌥⌘← move 10 seconds; near the end, ⌥⌘→ goes no further than the end, and near
  the start ⌥⌘← no further back than the start.
- **419 Find, Refresh, Settings, Go to Current Song.** From the Library, ⌘F: Search, at its top page, the cursor in its
  field - type at once (on macOS 14, the field needs a click). ⌘F with Now Playing open: it closes, and the same. ⌘R on
  the Library: it's asked again, as its ••• > Refresh does; on an album's page and a playlist's; on Settings (its pull
  on the phone). Is ⌘R dimmed on Search, on Requests, and with Now Playing open? ⌘,: Settings, from any tab, Now Playing
  closed. ⌘L: the album of the song playing, on the tab you're on. Open Edit album from Settings > Needs a look and
  press ⌘R: nothing happens under it (Refresh is dimmed) - and on its release page, ⌘R asks that page again. Close
  Edit album: ⌘R asks Needs a look again. Closing a sheet never leaves Refresh dimmed.
- **420 Right-click.** Each the same as its •••, the page's Refresh left out. A song on an album's page: **Add to
  Queue**, **Add to a playlist…**, and its download item (**Download**, or **Remove Download**) - the same with a song
  on a playlist's page, in All songs and in Search. An album's tile in the Library (rest the pointer on it a moment
  first): Add to Queue, Add to a playlist…, the album's download items, **Album info** - which opens its sheet - and
  **Edit album**; the same on an album's row (the Library's list), in Search and on an artist's page. Right-click a tile
  the instant the pointer reaches it: it says Loading - and again: the menu. A downloaded album's tile: its menu at
  once, even offline. Retag an album in Edit album, then right-click its tile: Loading (or the downloaded one's menu)
  until deadwax answers, then Add to Queue queues its songs as they are now. A playlist's row: Add to Queue, Add to a
  playlist…, the playlist's download items. An artist: no menu. Does the trackpad's two-finger swipe on a song still
  add it to the queue?
- **421 Closing the window.** Playing, close the window (⌘W): the music plays on, and the media keys and the menu bar's
  Now Playing still work. Is deadwax still in the Dock, with its dot? Click its Dock icon: the window comes back on the
  page you left - try it with an album's page open over the Library, and with the Library on its Playlists page. ⌘Q:
  the music stops and deadwax quits. With Edit album open and nothing changed, close the window and bring it back: what
  shows? Change a tag in Edit album: Close Window is dimmed and the red button does nothing - Discard, and ⌘W closes
  it again. The same with a playlist's Edit after a change, and Cancel. Does any of these open a second window: View >
  Show Tab Bar then its +, System Settings > Desktop & Dock > Prefer tabs when opening documents set to Always, the Dock
  icon's own menu? Say what each did. Typing in Search after the window came back, does Space type a space (not
  pause), and with the cursor out of the field, pause?
- **422 Escape and Return.** Edit album with nothing typed: Escape closes it. Type in a field, Escape: it asks to
  discard - and Return there keeps editing, it doesn't discard. Escape closes Up Next, Info, Album info, the Sources
  sheet, Add to a playlist, a cover full size and Now Playing. A playlist's Edit: Escape leaves it, asking first after
  a change. Settings > Downloads > Remove All Downloads: Return cancels, nothing removed. A playlist's Delete: Return
  keeps it. Edit album's Delete permanently, and People's Forget: Return cancels, nothing deleted or forgotten. In a
  playlist's Edit, and in the EQ's import preview, does Return press Done or Import? It shouldn't. Type a password in
  Add a person, or Reset password, or other words in Choose a source's search or a new playlist's name: Escape does
  nothing - empty the field, and Escape closes. A playlist page in Edit, then Now Playing opened over it: Escape
  closes Now Playing alone - is the playlist still in Edit, with no discard question raised behind?
- **423 VoiceOver** (⌘F5) reads the menus, a song row, a right-click menu's items and the player's buttons by name.

### The Mac app's desktop frame checks (424-433)

**Not done yet.** These come with [the Mac app](#the-mac-app)'s third build - the desktop frame (still app 0.13 (13)).
No server change is needed, and nothing changes on the phone. As for 404-423: deadwax's plain `http://` address, the
home Wi-Fi, signed in as an admin with logins on, installed with `ios/scripts/install-mac.sh`. Say "pass", or what you
saw.

- **424 The sidebar.** At the top the search field, then Requests (with its count while something's arriving),
  Library with **Yours | All**, Playlists, Manage, and Settings at the foot - each row with its glyph (words alone since
  the redesign's first slice, check 519). Yours lists your
  Library pages in the order you keep for the Library's switch, then Downloaded; All lists Albums, Artists, Songs, then
  Downloaded. Click each row: its page fills the window beside it, and the row is lit. On All's Albums, turn the switch
  to Yours: your Albums open. Open an album from All's Albums, then turn the switch: the album stays, only the rows
  change. Fold Playlists and Manage: quit and reopen - still folded? Folded, does Manage's heading show Needs a look's
  count? Manage has only what your permissions allow. Twenty playlists and Manage's rows: does Settings stay in view at
  the foot as the rest scrolls? ⌃⌘S hides the sidebar and shows it again; View's item says Hide Sidebar or Show Sidebar,
  and View still has Enter Full Screen. Scroll Requests down a way, click Library, then Requests: still where you
  were? Start a playlist's Edit, click Requests and back: still in Edit, your changes kept. In Edit, click another
  playlist's row: it opens over the one you're editing, and Back returns to your Edit.
- **425 Search from the sidebar.** Type in its field from the Library: Search's results fill the page as you type -
  and Return asks MusicBrainz at once. Open an album from the results, then type again: back to the results. Escape
  with the cursor in the field empties it. ⌘F from any page (and with the sidebar hidden): the sidebar shows, the
  cursor in its field, the page unchanged. Does Space type a space there, not pause?
- **426 The player bar.** Along the foot, with something playing: the cover, the title, Artist — Album, Shuffle,
  Previous, Play/Pause, Next, Repeat, the progress with the time played and the time left, Lyrics, Up Next, AirPlay and
  •••. Each button does what Now Playing's did on the phone; Shuffle and Repeat light while on; Artist — Album opens the
  album's page; click the progress and drag along it: the song moves where you let go. Click the cover: the cover full
  size, Escape closes it. The •••: Info opens the Info panel, Add to a playlist… the picker, the EQ its sheet, Go to
  album the album. Nothing queued (a fresh sign-in, say): **Nothing playing**, and the bar keeps its height.
- **427 The panels.** With the window 1280 wide or more, Up Next opens at the right, the page narrower beside it; drag
  the window narrower: it lies over the page's right edge instead, with a shadow. Lyrics in its place, then Info - one
  at a time; each button (and ⌥⌘U, ⌥⌘L, ⌘I) opens and closes its own, the menu item ticked while it shows. With one
  open, the page still scrolls, its songs play and the sidebar's rows work. Done and Escape close it - but Escape with
  the cursor in a text field doesn't. With a playlist's Edit open too, Escape closes the panel first, then cancels Edit.
  Widen or narrow the window across 1280 with Up Next in Edit, or Lyrics following a song: the panel stays as it was. Lyrics follow the song as it's sung; a song with none says No lyrics for this
  song, and Lyrics is dimmed in the bar until it's open. Info's album card opens the album: with the panel over the
  page's edge it closes; as a column it stays. Let the queue run out (or clear it): Up Next and Info close, Lyrics says
  Nothing playing.
- **428 Albums wide.** The Library's albums as a grid: as many covers in a row as fit, none smaller than a phone's.
  Widen the window and the rows take more; narrow it and fewer - the list keeps your place. An album's page, an
  artist's and an album you don't have sit in the middle at a readable width, the window's sides left plain - and
  they scroll with the pointer over those sides too, the scroll bar at the page's right edge.
- **429 Resizing while playing.** Drag the window from its smallest to full screen (View > Enter Full Screen, or the
  green button) and back while a song plays: the music doesn't stop or skip, and the page you're on stays where it was.
- **430 The smallest window.** Narrow and shorten the window as far as it goes: the sidebar, a page and the bar still
  fit and read, nothing cut off; with a panel open over the page, the page's left part still shows.
- **431 Sign-in and can't-reach.** Sign out (Settings > Account) - the sign-in fills the window and reads well; sign
  in. With deadwax unreachable (the network off), the can't-reach screen too. With a sheet open (Edit album, say), is
  the sheet its own size - not 880 points wide? Sign in as someone else: the sidebar's playlists are theirs, and Needs
  a look's count shows if they may look after the library.
- **432 No turntable.** Nothing on the Mac opens Now Playing or the record: the bar's cover opens the cover full size,
  its title does nothing, and Settings > Playback has no turntable rows.
- **433 The phones.** Both iPhones on the same build: the tabs, the play bar on the tab bar, Now Playing (and its
  turntable), Search's field and the Library's albums grid exactly as before.

### The Mac app's words checks (434-438)

**Not done yet.** These come with [the Mac app](#the-mac-app)'s fourth build - the Mac's own words (still app 0.13
(13)). No server change is needed, and no word on the phone changes. As for 404-433: deadwax's plain `http://` address,
the home Wi-Fi, signed in as an admin with logins on, installed with `ios/scripts/install-mac.sh`. Say "pass", or what
you saw - and anywhere on the Mac that still says "phone" or "iPhone", which page and which words.

- **434 This Mac.** Settings: the row is **This Mac**, with the server's address at its right; About below it. Open
  This Mac: its title is This Mac. Its Debug (an admin's): the foot says "deadwax for Mac 0.13 (13)", and the install
  line "This install doesn't expire: a Mac keeps opening deadwax without installing it again." (On a build installed
  with `--allow-profile`, the line says the date it runs out instead - say so if you have one.) Settings > Playback,
  under Normalization: "This is kept on this Mac."
- **435 Downloads.** Settings > Downloads: the foot says "Downloads stay on this Mac when you sign out.", and the line
  for what's downloaded says this Mac. Download your library's note, an album's download line and Album info's **On
  this Mac** say this Mac; so does the card at the top of the Library's Downloaded, while it asks ("Keep your library
  on this Mac?"). Turn the Mac's Wi-Fi off: the banner says "Offline - showing what's on this Mac", and under it
  "Join a network to play what isn't on this Mac." Offline, a song with no
  lyrics kept on this Mac has Lyrics dimmed, and the Lyrics panel says "Lyrics - not on this Mac" - if you come across
  one. Never phone.
- **436 Outputs.** The EQ page: the Mac's own speakers are **Mac speakers**, with a speaker for their picture - with
  the EQ you gave them in an earlier build, if you did. Headphones in the jack, then AirPods: each its own output, AirPods
  by their name. Settings > Playback, under the EQ: the foot names "the Mac's speakers, a USB DAC" and says it's kept
  on this Mac. The EQ page's **Import…** (not Import from Files…) opens the Open panel. Are the Mac's own speakers
  "Mac speakers" at all, or listed under another name (what macOS calls them, "MacBook Air Speakers" say)?
- **437 Local Network refused** (macOS 15 or later; on macOS 14 there's no such switch - say which macOS the Mac
  has). In System Settings > Privacy & Security > Local Network, turn deadwax off; quit deadwax and open it: the
  words under "Couldn't reach deadwax at …" say "Is the Mac on your home network, or on WireGuard? On macOS 15 or
  later, if you said no when asked about the local network, turn deadwax on in System Settings > Privacy & Security >
  Local Network." - as does the address screen's Check. Turn it on there, quit and open deadwax: it connects.
- **438 The phones' words.** Both iPhones on the same build: Settings' **This phone**, Settings > Downloads' foot
  ("Closing deadwax from the app switcher stops downloads…"), the EQ's **iPhone speaker** and **Import from Files…**,
  Debug's install line ("This install runs until …") and "deadwax for iPhone" - every word as before.

### The Mac app's sleep, power and downloads checks (439-446)

**Not done yet.** These come with [the Mac app](#the-mac-app)'s fifth build - sleep, power and downloads (still app
0.13 (13)). No server change is needed, and nothing on the phone changes. As for 404-438: deadwax's plain `http://`
address, the home Wi-Fi, signed in as an admin with logins on, installed with `ios/scripts/install-mac.sh`. Say
"pass", or what you saw - and for 439 and 440, copy Settings > This Mac > Debug's engine log after it: its "power:"
and "output gone:" lines say what macOS told deadwax.

- **439 The lid.** Playing on the speakers, close the lid for a minute (no external display). Open it: paused, at the
  same place; Play goes on from there.
- **440 Headphones out.** Playing on wired headphones or AirPods, take them out: it pauses, as the phone does.
- **441 A care run.** Library care, a run over many albums, the Mac left alone: the display stays on until it ends.
- **442 A download, hidden.** Download an album, then ⌘H and use other apps: it carries on and lands.
- **443 Quit mid-download.** ⌘Q with a download half done; open again: it carries on.
- **444 Only while charging.** On battery with Only while charging on: Download your library waits, said so; plug in:
  it starts.
- **445 The library, later.** Download your library on, deadwax quit overnight: next morning, did new albums arrive
  before you opened it? (macOS's to decide; either answer is fine - it is written up.)
- **446 A hotspot.** On the iPhone's hotspot with Download over Wi-Fi only: downloads wait, and say why.

### The Mac app's EQ files checks (447-451)

**Not done yet.** These come with [the Mac app](#the-mac-app)'s sixth build - EQ files (still app 0.13 (13)). No server
change is needed, and nothing on the phone changes. As for 404-446: deadwax's plain `http://` address, the home Wi-Fi,
signed in as an admin with logins on, installed with `ios/scripts/install-mac.sh` - whose check now says "allowed out
to the network and to open and save a file you choose". Have a `.txt` from AutoEq in the Mac's Downloads folder and
something playing, so For names an output. **If deadwax quits as it opens, say so before anything else**: macOS throws
out an app whose menus have one key twice, and only a Mac can say whether its File menu has a ⌘O of its own. Say
"pass", or what you saw.

- **447 Import.** File > Import EQ File… (⌘O): the Mac's Open panel; a `.txt` from AutoEq; its preview; For an output.
  With Edit album up, is Import EQ File… dimmed? Then the EQ page's own **Import…**, both in the EQ sheet (the bar's
  ••• > EQ) and on Settings > Playback > EQ: does each still open the Open panel? With the page's own Open panel (or
  Export's Save panel) up on Settings > Playback > EQ, press ⌘O, then cancel that panel: does a second panel come up
  by itself? And does ⌘O open the panel again afterwards?
- **448 Export.** Export a preset: the Save panel; the file is where you saved it, and imports again. (Export… > Save
  the Whole Curve…: the panel names it `<output name> EQ.txt`; then Import EQ File… that file.) Save from the EQ sheet
  and from Settings > Playback > EQ: does the panel open from both? Does Share the Whole Curve offer AirDrop and Mail?
- **449 Open With.** In Finder, right-click a `.txt` > Open With > deadwax: its preview. The file is still where it was,
  unchanged. Again with deadwax's window closed (⌘W, the music playing): the window comes back with the preview, and
  the Window menu lists one deadwax window, not two. Does a double-click on the `.txt` still open TextEdit?
- **450 Dropped.** Drag a `.txt` onto deadwax's window, and onto its Dock icon: the same preview. And onto the EQ's
  sheet with it up. One from the Desktop or iCloud Drive too: its preview, or "deadwax couldn't read this file."?
- **451 Paste.** Copy an EQ's text in a browser; Paste on an EQ page: its preview. Is the Paste button there on the
  Mac's EQ page, and does macOS ask before deadwax reads what you copied?

### The Mac app's managing checks (452-458)

**Not done yet.** These come with [the Mac app](#the-mac-app)'s seventh build - managing on a big screen (still app
0.13 (13)). No server change is needed, and nothing on the phone changes. As for 404-451: deadwax's plain `http://`
address, the home Wi-Fi, signed in as an admin with logins on, installed with `ios/scripts/install-mac.sh`. **If
deadwax quits as it opens, say so before anything else**: macOS throws out an app whose menus have one key twice, and
only a Mac can say whether its File menu has a ⌘S of its own (none was found in macOS's own menus). Say "pass", or what
you saw.

- **452 Edit album.** An album's ••• > Edit album: the sheet fits the window; Release, Tags, Artwork, Lyrics, Delete
  album… each open. Is the sheet 760 points wide and nearly as tall as the window - or the size it was before (say
  which macOS the Mac has)? Narrow and shorten the window as far as it goes with Edit album shut, then open it: does
  it still fit? Does it follow the window if you resize it with the sheet up?
- **453 The keyboard in the editor.** Tab moves between the fields; Return in a field doesn't apply; Apply is a click.
  In Release: Artist, Tab, Album, Tab, Year… in that order, and Shift-Tab back. In Edit tags the same, through all
  eleven fields, from Track's into Album's. Does Tab ever skip a field, or move two at once? Return in any of them:
  nothing applies. Then People > Add a person: Tab through its four fields.
- **454 Delete.** Delete permanently's dialog: Cancel is the default; Return and Escape both cancel. Nothing is deleted.
- **455 Server settings.** Change a setting: ⌘S saves, as Save changes does; Unsaved is cleared. Is File > Save changes
  dimmed with nothing changed, and on another page? With a sheet up over Server settings - Add to a playlist from the
  player bar, say? And in the Library's Set up Navidrome sheet, with an address typed, does ⌘S save it?
- **456 The event log.** Select lines, ⌘C, paste into Notes: the lines as shown. Click one, ⇧-click another: the run
  between is selected. Then ⌘A: every line. Does Edit > Copy dim with no line selected - and is it on once you click
  one? If Copy stays dimmed with lines selected, click another line and say so. Do the arrow keys still move the
  selection after a click? Are an error's red words readable on a selected row?
- **457 People and Needs a look** read well at full width - or say which wants a table. Full screen too.
- **458 A run, then quit.** A Library care run, ⌘Q midway: it asks first, or says what happens to the run. It says,
  under Stop: "Quitting deadwax stops the run - open deadwax again, and Get covers carries on." Quit; open deadwax;
  Library care: Get covers counts only the albums still without a cover. Was the album it was on when you quit given
  its cover?

### Manual search's checks (459-475)

**Not done yet.** These come with manual search's two slices - [Search Soulseek…](#requests) in Requests (still app
0.13 (13)); 475, opening its Done row and ▶ on it, with the second. They need **deadwax 2.1.38 or later** on the
server (main's `:experimental` has it), and 475 needs **2.1.40**: an older one answers the search but keeps every Get
off. On the phone and on the Mac, deadwax's plain `http://` address, signed in as an admin with logins on. Use one
album MusicBrainz has (Portishead
"Dummy", for comparing), one it may not (a bootleg or a self-released record you know is shared), and one you already
have matched. Say "pass", or what you saw.

- **459 The row and the form.** Requests: Search Soulseek… is the first row, above the headings - and there with
  nothing requested. Tap it: Search Soulseek, the cursor in Artist. Type an artist; Return goes to Album; Search stays
  dimmed until both have words.
- **460 A search.** Search "Portishead" / "Dummy": "Looking for “Dummy” by Portishead…", then cards. Is the top card a
  folder called Dummy? Tap its score: Folder name first, then Edition, Format, Availability, and no track parts.
  There's no Complete albums only chip.
- **461 The ranking.** Among the first five cards, is every folder the album you typed, before any other album, live
  record or reissue? Among those, lossless before MP3, and Starts now before a long queue? Would you have picked the
  top one yourself?
- **462 Back.** Search again with other words, then Back: the form, your two fields as you left them. Change Album
  and Search: a fresh list. On the phone, start swiping back from the left edge and let go halfway, so the results
  stay: do Search again and Get still work?
- **463 Get.** Get the top card: the sheet closes, and the row is under Waiting, "Dummy · manual search",
  "starting…", then downloading.
- **464 Done.** When it's done: "In your library", and "Filed by its own tags. Edit album > Release can match it to a
  pressing." In the Library, the album is under the artist and title its tags give (try typing them in lowercase:
  the folder and the Library still show the tags' spelling), and it plays.
- **465 Needs a look.** The album newly imported, "Not matched to MusicBrainz", and no "Folder name doesn't match the
  tags". Edit album > Release, Choose a release, Apply: matched, the folder renamed, the issue gone.
- **466 An album MusicBrainz may not have.** Get one. Filed, playing, and staying "Not matched to MusicBrainz". Ignore
  that issue: it stays quiet.
- **467 An album you have matched.** Search it by hand and Get another copy. It's filed beside yours as
  "… [unmatched]", not into your folder. Does Navidrome show it as a second album, or join them?
- **468 Two discs.** A two-disc set shared as CD1/CD2 with the same file names: every track arrives, as "1-01…" and
  "2-01…".
- **469 Pick the best source for me** on (Settings > Getting albums): a manual search shows the cards, picks nothing,
  and says nothing about why.
- **470 Offline** (Wi-Fi and WireGuard off): the Search Soulseek… row is dimmed. With the form open, "Getting albums
  works once deadwax is back." and Search off; on the results, dimmed cards with Gets off. Back on: all live.
- **471 Without Get albums.** An account without it: no Search Soulseek… row in Requests.
- **472 An album page's Get the album, after the split.** The Choose a source sheet is exactly as before: Cancel,
  Search again at the top, a swipe to close stopping the search.
- **473 On the Mac.** Requests' first row is Search Soulseek… there too; the form as a sheet; Tab and Shift-Tab
  between the fields; Return in Album searches. Escape closes the form while both fields are empty - with words
  typed it does nothing, and Cancel closes it. Then the results, a Get, and the row in Requests.
- **474 VoiceOver.** "Search Soulseek, button"; the two fields by name; the outcome said as the results land.
- **475 The Done row opens.** Get one whose tags differ from your typing (type it in lowercase, or a shorter title).
  Once it's done, is the row titled as the tags name it, "… · manual search", with the tags' artist under it? Tap it:
  its album opens. Back, then ▶: it plays from its first song. Then one with no ▶ (everything already there): a tap
  still opens it. On the Mac too. If a tap says "Can't find this album to open it…", say what's under it - and is the
  album in the Library under the same name?

### Last.fm's checks (476-487)

**Not done yet.** These come with Last.fm's first slice on the app - [the listeners line and Top Songs](#artists) on
an artist's page (still app 0.13 (13)). They need **deadwax 2.1.41 or later** on the server (main's `:experimental`
once it's out). On 2.1.36-2.1.40, which say Last.fm is on but have no route for it, the page shows a blank line
under the name and no Top Songs; before 2.1.36, nothing of Last.fm's at all.
Marked **[key]** where `LASTFM_API_KEY` must be set on deadwax, **[no key]** where it must not. Run them on both
phones and the Mac, over deadwax's plain `http://` address with logins on: James's phone and the Mac as an admin,
Ethan's phone as a listener (the one that sees no foot line). Say "pass", or what you saw.

- **476 [no key] Nothing there.** On the web and in the app, artist pages are as before. Server settings >
  Connections shows LASTFM_API_KEY unset, with its words. As an admin, the foot of an artist page in the app says "Top
  songs, similar artists and radio come from Last.fm - add a Last.fm API key in Server settings to see them.", and
  its Server settings button opens Connections. On Ethan's phone, no such line.
- **477 [key] The key in.** Paste the key into Server settings in the app and save. The row says set; the web's says
  set too. Leave the app and come back: artist pages now have Last.fm's line and Top Songs, and no foot line.
- **478 [key] Tame Impala.** Under the name, "x.xM listeners". Then Play, then Top Songs: 5 rows, and See All shows
  10 on a page titled Top Songs. Is the order the one Last.fm's own page for them gives (all time)? Is any song there
  twice, or a feature listed as a song of its own?
- **479 [key] A song you have.** Its row shows its album and year, and the studio album's cover rather than a live
  one's. Tap it: it plays, and Up Next holds the other top songs you have after it, in Last.fm's order. Swipe one
  right: added to the queue.
- **480 [key] A song you don't have.** "Not in your library". Tap it: the row spins, then the album you don't have
  opens, the song marked in its tracklist. Is it the right album (the studio one, not a compilation)? Tap it, and
  before it opens switch tab: nothing opens over the other tab.
- **481 [key] Dance Gavin Dance.** 478-480 again, for the artist with feature credits: no song doubled, and a
  "(feat. …)" title matched to your song without it.
- **482 [key] Nothing jumps.** Over WireGuard, open an artist you haven't opened in the app this week (deadwax keeps
  Last.fm's answers a week, so it asks Last.fm itself). Does Play move as the listeners line fills? Does Albums jump
  down as Top Songs arrives, or does Top Songs come in below the albums instead? Go back and open the artist again:
  all in place at once.
- **483 [key] An artist Last.fm doesn't know** (a small Soulseek find): no Top Songs, no listeners figure, nothing
  empty; their albums as before.
- **484 [key] Offline.** With Tame Impala open, turn on Airplane Mode (and WireGuard off). Top Songs stays; rows not
  downloaded are dimmed and do nothing, and one you don't have does nothing; the listeners line keeps its place. Go
  back and open Tame Impala again: a top song you have on an album that isn't downloaded is dimmed with no line,
  never "Not in your library". Open an artist not opened yet: nothing of Last.fm's, and no gap.
- **485 [key] A wrong key.** In Server settings, paste the shared secret instead. Leave the app and come back, then
  open an artist page: nothing of Last.fm's for anyone. As an admin, the foot says "Last.fm refused deadwax's API key
  - check LASTFM_API_KEY in Server settings. It's the API key, not the shared secret." The row says refused with the
  time; the event log says so once. Put the real key back, leave the app and come back: it works at once.
- **486 [key] The Mac.** The same page at the readable width. Right-click a top song you have: the same menu as its
  ••• (no Start Radio yet - that's a later slice). See All opens the list; From Last.fm opens last.fm in the browser.
- **487 [key] VoiceOver.** A top song reads its title and line ("Let It Happen, Currents · 2015"); a missing one
  "…, Not in your library"; "From Last.fm" reads as a link; the listeners line is read under the name.

### The Mac redesign's checks (518-614)

The new look, drawn on the design canvas and built a slice at a time (still app 0.13 (13)): the Mac's first, and the
phones' from the slices after 524-525, each screen redrawn in its own slice. No server change is needed. Until a slice
redraws a phone screen it should look and work exactly as before - each slice's last check is the phones'. As for
404-458: deadwax's plain `http://` address, the home Wi-Fi, signed in as an admin with logins on, installed with
`ios/scripts/install-mac.sh`. Say "pass", or what you saw.

#### The frame and the shared pieces (518-523)

**Not done yet.** The first slice: the title strip, the sidebar as drawn, and the colours, corners, type and controls
every later slice builds its pages from. The pages themselves are still the phone's.

- **518 The title strip.** **Not done yet.** Along the top of the window, 28 points tall with a gradient: the traffic
  lights at its left and the page's name in its middle (Albums, an album's name, Settings, ...). Drag the window by
  the strip: it moves. Open a few pages: does the **Window** menu name each one? Rename a playlist in its Edit: the
  strip and the Window menu take the new name. Sign out: the Window menu says Sign in.
- **519 The sidebar.** **Not done yet.** At its top **deadwax**, then the search field, then text rows with no glyphs.
  Click every row: each opens its page, and the row is lit in purple with its edge. ⌘F puts the cursor in the search
  field; the field's edge turns purple while it has the cursor.
- **520 The look.** **Not done yet.** Open the canvas's Albums beside the Mac app: do the sidebar's colours, the title
  strip's and the purple of the lit row match it?
- **521 Buttons and fields.** **Not done yet.** So far only the sidebar has the Mac's own controls. The search field
  is sunken, and its edge turns purple while it has the cursor. **Yours | All** is drawn as the canvas draws a
  segmented control: a dark well with a thin grey edge, the words grey, the chosen one in light purple on a faint purple
  fill inside its own purple edge - flat, nothing raised. Tab to the switch: its edge turns purple, and ← and → turn
  it. (The raised buttons - glossy, pressed in while held, faded while they can't be used - and the purple one that
  takes Return come with the first page that has them.)
- **522 Everything still works.** **Not done yet.** Every page opens from the sidebar and goes back as before - an
  album, an artist, a playlist, Search, Requests, Settings and each of its pages, Manage's pages and Edit album. Make
  the window as small as it goes (880 x 600): the strip, the sidebar, the page and the bar all fit, nothing cut off.
- **523 The phones.** **Not done yet.** On Green Anole, every tab, the player, Now Playing, Edit album and the EQ are
  as before. The same on Ethan's phone, or "not done yet".

#### The shared look, and the phone's pieces (524-525)

**Not done yet.** The second slice moves the Mac's buttons, fields, chips, switches and colours to where both devices
can use them, and makes the phone's own pieces, which are drawn nowhere yet. Nothing on either screen should change.

- **524 The Mac as R1 left it.** **Not done yet.** The title strip, the sidebar, the colours and the buttons are as
  518-521 found them.
- **525 Both phones.** **Not done yet.** On Green Anole, every tab, the player, Now Playing, Edit album and the EQ are
  as before. The same on Ethan's phone, or "not done yet".

#### Albums and Artists, and the Library's top (526-531)

**Not done yet.** The Mac's Albums and Artists become column lists under their own toolbar - Play, Shuffle, Sort,
Grid | List and Find - with their counts in the status bar. On the phone the Library's top is redrawn as one row: the
magnifying glass at the left, the ••• at the right - bare white glyphs (612) - and between them the switch of the
pages, in the order you keep (Edit order), the page you're on white over a purple line - no "Library" title and no
row of buttons under it. Under the row each
page has one quiet line of words: how many, its order (tap it to change it) or Playlists' **New playlist…**, and at its
end Albums' grid and list marks, then **Yours | All** with a library of your own - white where you are, purple what a
tap goes to. **All** shows the whole collection's albums, artists and songs as the pages, where the •••'s All music
used to push them. The ••• is Shuffle, **Downloaded**, Refresh and Edit order.

- **526 Albums as a list.** **Not done yet.** On the Mac, choose **List** in the Albums toolbar: every other row is
  faintly striped, and a clicked row is lit purple inside a purple edge. ↑ and ↓ move the lit row, ⌘↑ and ⌘↓ to the
  first and the last; Return, or a double-click, opens the album; a right-click gives the album's menu. Play is
  dimmed until the lit album's songs have come, then plays it - and the playing album has a purple ▶ after its
  title. Hold ↓ down a long list: the lit row runs down it, and Play wakes only once it stops. Choose **Grid**:
  nothing is lit, Play is dimmed and its tooltip says "Select an album in List to play it.", Shuffle still shuffles.
- **527 Grid and List.** **Not done yet.** On the Mac, choose Grid or List, quit the app and open it again: it is as
  you left it. The phone keeps its own choice: changing one doesn't change the other.
- **528 Artists.** **Not done yet.** On the Mac's Artists, as a list, pick an artist: their Songs, Plays and Last played
  agree with Navidrome's own pages for them (Last played says today, yesterday, "3 days ago", "last week" or a date).
  An artist on a split album or a compilation whose album artist is someone else counts it in their Albums but not
  in their Songs or Plays - Navidrome's own count against the album's own artist. The status bar's albums count
  each album once. Left open past midnight, "today" becomes "yesterday".
- **529 The Library's top.** **Not done yet.** On the phone, the Library's top is one row - the magnifying glass, the
  switch of the pages and the •••, 16 points in from each edge - clear of the Dynamic Island, and still clear after
  opening Now Playing and going back. The page's quiet line is under it, its words and marks bare, nothing boxed.
  VoiceOver reads the magnifying glass by the page's Find ("Find in albums"), the switch as "Library pages" with the
  page you're on selected, then "More for the Library"; on the line, Grid and List with the one showing selected, and
  Yours | All as "Your library or all music" with the side you're on selected. At the largest text size (and the
  accessibility sizes) on a narrow phone, nothing is cut short: with four pages (logins off) the switch moves under
  the glyphs - at the standard text size too, on most phones - and Yours' three pages at the two largest standard
  sizes, All's at the largest (VoiceOver then reads the magnifying glass and the ••• before the switch under them), and
  a line too long for one first drops its count's word ("140 · Recently added"), then goes on to a second.
- **530 The pages.** **Not done yet.** Tap each page in the switch: the page moves to it and it lights. Swipe between
  the pages: the lit page follows. **••• > Downloaded** opens Downloaded; turn WireGuard off on Yours and the ••• has
  **Your albums** in its place instead. The order on a page's line changes the order, the grid and list marks at the
  end of Albums' line switch it (the one showing white, the other purple), and pulling a page down still shuffles.
  With a library of your own, **All** at the end of a page's line shows the whole collection's Albums, Artists and
  Songs, and **Yours** your own again - Songs never beside your own albums; the side you're on is white, the other
  purple. On All's Songs, turn WireGuard off: All and its Songs stay; tap Yours, and Yours | All goes until deadwax is
  back. The magnifying glass opens Find under the top; Cancel closes it.
- **531 Both phones.** **Not done yet.** On Green Anole, the rest - the other tabs, the player, Now Playing, an album,
  Edit album and the EQ - are as before. On Ethan's phone, 529 and 530, or "not done yet". At the standard text size,
  Albums' line on Green Anole drops its count's word with a count in the thousands and **Year, newest first**, or
  while Find finds under a longer order ("12 of 140 · Recently added") - say whether the bare number reads well. Should
  either be 375 points wide (an SE or a mini), the line keeps to one line for a library's count under any order;
  Find's count still sends grid, list and Yours | All on to a second line as you type under **Year, newest first**,
  or under **Recently added** or **Year, oldest first** in a library in the thousands ("12 of 2318") - say whether
  that reads well.

#### The side panel's tabs, and the Now Playing sheet (532-538)

**Not done yet.** The third slice: on the Mac the side panel becomes one panel with tabs along its top - Queue, Lyrics,
Info and EQ - and on the phone Now Playing's Queue, Info and the EQ become one sheet with a strip of its own, opened
from a new row of five buttons along Now Playing's foot. Every word that said Up Next says **Queue** now, on the phone
and the Mac (the web app keeps Up Next). Each tab's page is still the one it was until a later slice redraws it.

- **532 The tabs.** **Not done yet.** On the Mac, open the side panel (**View > Queue**): along its top four tabs,
  **Queue**, **Lyrics**, **Info** and **EQ**, the one showing lit, and the panel 400 points wide. With the window 1280
  points wide or more it sits beside the page, which narrows for it; narrower, it lies over the page's right edge with
  a shadow. Click each tab: its page shows, and only its.
- **533 The keys.** **Not done yet.** ⌥⌘U, ⌥⌘L, ⌘I and ⌥⌘E each show their tab - opening the panel if it's shut,
  switching to it if another tab shows - and the View menu ticks it. The same key again closes the panel, as Escape
  does (with the cursor in a text field, Escape leaves the field first). The bar's Queue, Lyrics, Info and EQ buttons do
  the same (since the bar's redraw, 546).
- **534 Info's subject.** **Not done yet.** With nothing selected, Info's heading says **Playing** and the song playing's
  Info is under it. With Lyrics showing and nothing selected, let the last song play out (Repeat off), then click the
  **Info** and **Queue** folder tabs: each says **Nothing playing** under its name, never a blank page. Once the
  Library's lists select a row on a click (the next slice), select an album: the heading says **Selected album**, with
  the album's Album info under it - and an artist: **Selected artist**, their name and **Go to artist**. Until then,
  "not done yet".
- **535 The EQ in the panel.** **Not done yet.** On the EQ tab, every control works as on the EQ page: the switch,
  Preset, the sliders, Correction, Other outputs, Advanced. Settings > Playback's **EQ** row opens the tab. **Import…**
  on it opens its preview as a sheet over the window. With the panel shut, or on Lyrics, choose a file in **File >
  Import EQ File…**: the panel shows the EQ tab and the preview comes up over the window, as before - one EQ, never a
  second EQ page over the tab. Again by dropping a `.txt` on the window, and with Finder's **Open With**. Import and
  Cancel each put the preview away and leave the tab showing.
- **536 The bottom row.** **Not done yet.** On the phone, Now Playing's foot has five, each an icon over its name:
  **Queue**, **Lyrics**, the output (AirPlay, the name of where it's playing under it), **Info** and **EQ**. Each opens
  what it names. **Lyrics** shows the lyrics in the cover's place, and again puts the cover back - it never opens the
  sheet. The **•••** is at the top right beside the look button (**Turntable** since R4b). Tap the output's name, not its icon: AirPlay's list
  opens. With VoiceOver, the output reads "AirPlay", then where it's playing. Set a speed off 1x on the turntable:
  back on the cover, the chip shows just above the row, over the gap between the output and Info. Tap the very left
  and right of Info and the output's right edge, close beside the chip: each opens what it should and the speed stays;
  only a tap on the chip goes back to 1x. Is the band it sits in a gap that looks meant, with the chip off 1x and at
  1x? On the phone with the smaller screen, is the cover (and the turntable) still a comfortable size? Download the
  Queue from the •••: "Downloading 23 songs from the Queue" stays between **Close** (the arrow until R4b) and the look
  button, and the look button works while it shows. With Shuffle on, VoiceOver reads the Queue as "Queue - Shuffle on" and the EQ as "EQ,"
  and its setting.
- **537 The sheet.** **Not done yet.** **Queue**, **Info** or **EQ** opens one sheet: **‹ Now Playing** at its top,
  then the strip - **Queue**, **Info**, **EQ** - and the page. Tap the strip: the sheet moves between its pages without
  closing. The EQ works there as on its own page. Share an EQ `.txt` file to deadwax while Now Playing is up, with the
  sheet on the Queue: it moves to EQ, the file's preview over it. Again with the cover full screen: the cover closes,
  then the sheet opens on EQ with the preview. A swipe down from Now Playing's top still closes Now Playing.
- **538 Both phones.** **Not done yet.** On Green Anole, everything else - every tab, the player, Edit album, Settings'
  EQ - is as before. On Ethan's phone, 536-537, or "not done yet".

#### The Queue, Info and the EQ inside (539-542)

**Not done yet.** The sheet's three pages in the new look, on the phone: the **Queue**, **Info** and the **EQ** as
drawn, each with **‹ Now Playing** and the strip at its top. On the Mac the side panel's Queue and Info tabs get the
time left and Played. Play an album with songs still to come, and add a song or two with Add to Queue.

- **539 The Queue.** **Not done yet.** On the phone, open **Queue**: **History**, **Clear** and **Edit** at the top
  right; the song playing first, lit, with no heading over it; the songs you added after it, each with its artist and
  album; then "Next from" the album with each row its title; and along the foot **Shuffle**, **Repeat** and the time
  left ("8 songs · 33 min left"). Count the songs after the one playing: the number matches, and the minutes come
  down as the song plays - what you've played isn't counted. History scrolls up to what you've played; a tap on a
  song there goes back to it, as before. Clear takes Playing Next out. Edit's handles move songs and its minus takes
  one out; Done ends it. A tap on a song plays it. At the largest text sizes History and Clear are in the **•••**
  beside Edit, nothing at the top is cut off, and the time left goes under Shuffle and Repeat. Near the end of the
  last song it says "under 1 min left", never "0 min". On the Mac, the panel's Queue tab shows the time left at the
  left of its foot, in the status bar's type.
- **540 Info.** **Not done yet.** On the phone, open **Info**: the song at the top, then **This song** - Format,
  Track, Length, Size ("24 MB · 921 kbps"), Played ("19 times · today", or the day it last played) and the rest - and
  **The album**, then **Go to album** and **Go to artist**, each opening its page with Now Playing put away. A song
  never played has no Played row. Leave Info up past midnight (or set the phone's clock past it): "today" becomes
  "yesterday". As an admin, choose **Debug**, move to the Queue and back: Debug is still chosen. On the Mac, the
  panel's Info tab has Played among the song's rows.
- **541 The EQ.** **Not done yet.** On the phone, open **EQ**: the output's button at the top - "Output" and its
  name - opens AirPlay's list, and VoiceOver reads it as the output, "Connected now" or "Not connected"; **EQ on** at the
  top right is a purple switch, and VoiceOver reads it as a switch, "EQ for" the output, on or off - at the largest
  text size the switch alone, nothing cut off. Touch and hold a filter in Advanced: **Delete**; an output under Other
  outputs: **Rename** and **Forget**; Correction, after changing an AutoEq correction in Advanced: **Back to
  AutoEq's** - none of them opens the filter or the output first. The filters' switches are purple. The curve sits on
  the page, with no well; Correction, Tone and Advanced are groups, each a grey heading over its rows with no panel;
  the output's name and its caret are purple, with no face; the sliders' tracks are sunken and their knobs round.
  Every control does what it did, and the sound is as before: the switch, Preset, the sliders, Correction, AutoEq's
  suggestion and its **Not now**, Other outputs, Advanced and its filters. Connect other headphones with the EQ up:
  the page follows the output - but not with Preset's list or a filter's page open over it, and it catches up when
  you come back. In Advanced, open a filter, type a frequency and go **Back** without tapping elsewhere: the new
  frequency is kept. Again with the strip, and with the sheet swiped away. From Settings > Playback > EQ the page is
  the same, with the switch under the output's button. On the Mac, the panel's EQ tab in Advanced: each filter's row
  in the List's own type, its switch in the app's colour, as before.
- **542 Both phones.** **Not done yet.** On Green Anole, everything else - every tab, the player, Now Playing, Edit
  album, the EQ from Settings - is as before. On Ethan's phone, 539-541, or "not done yet".

#### The player bar, the mini player and the tab bar (543-549)

**Not done yet.** On the Mac the player bar along the window's foot is redrawn: the five keys in one row, a display
the bar's whole height, and the tools - Queue, Lyrics and Info joined in one strip, then the EQ, where it's playing and
the **•••**. On the phone the mini player and the tab bar take the new look. Queue an album or two first.

- **543 The bar.** **Not done yet.** On the Mac the display fills the bar's height, its three lines as drawn. (The bar
  is 66 points tall. The display's cover sits flush at its left, the bar's height, with no gap round it; beside it the
  title, with **Next** and the song that then plays at the right; under it the artist and album, with a readout like
  "3 of 11 · FLAC 16/44.1" at its right; then the time played, the scrubber and the time left. Click the artist and
  album: the album opens. Click the cover: it opens full size. Hold the pointer over a cut-short title: it shows
  whole. Narrow the window: the first line leaves out Next when it has no room for it, and the second line its
  readout, each on its own - so either can go first, by how long the names are; nothing runs past the display.)
- **544 Next.** **Not done yet.** Under shuffle, both repeats and at the last song, it names the song that then plays,
  or nothing. (With Shuffle on, Next is the song Next on the keys plays. At an album's last song with Repeat off it
  names nothing; with Repeat all, the album's first song; with Repeat one, nothing - the song plays again. A shuffled
  album's last song with Repeat all names nothing until the next round is shuffled, a moment later. The readout's "3
  of 11" is the song's place in what you queued: played in order, its place in the album or playlist; shuffled, in the
  order they play; a song you added with Play Next has none. Quit and reopen the app some 50 songs or more into a
  shuffle, in a list of more than 2,000 songs shuffled, or in a library's shuffle you took a song out of: no number
  until the next time round, never a wrong one. A list played in order keeps its number, however long.)
- **545 The keys.** **Not done yet.** All five work. Space plays and pauses, except in a field. (Shuffle and Repeat
  light while on; Repeat goes off, all, one. Play shows a spinner while a song loads. During a library's shuffle,
  Shuffle is dimmed. With the cursor in the sidebar's search field, Space types a space.)
- **546 The strip and the output.** **Not done yet.** Each button opens its tab. The output names the route; AirPlay
  picks another. (Queue, Lyrics, Info and EQ each open their tab of the side panel and light while it shows; the same
  button again closes the panel. Lyrics is dimmed for a song with none. The **•••**'s Info and EQ show theirs too.
  The output's name is the one the EQ uses. In a window under 1000 points wide the name is left out, the AirPlay
  button kept, and the name shows when you hold the pointer over it.)
- **547 The mini player.** **Not done yet.** On the phone, as drawn. A tap or a drag up opens Now Playing; across the
  title skips, across the top seeks; VoiceOver offers Next and Previous. (60 points tall, black under a thin line,
  the cover flush at the left with no line at its right, a thin purple line along the top for the time played, and
  Play and Pause alone at the right with no circle round them. There is no skip button. A drag across the very top
  seeks, the time shown over your finger.)
- **548 The tab bar.** **Not done yet.** The lit line over the shown tab, the badge, at the largest text size too.
  (The bar is black under a thin line. The shown tab is purple, with a short purple line on the bar's top edge over
  it; the others grey. Requests' count sits over its icon's top right corner. At the largest text sizes the bar
  grows only so far; touch and hold a tab to see it bigger.)
- **549 Both phones.** **Not done yet.** Green Anole: the rest as before. Ethan's: 547-548, or "not done yet".

#### Now Playing's face (550-552)

**Not done yet.** On the phone alone (the Mac never opens Now Playing): Now Playing's top, its cover, its title and its
scrubber take the drawn look - the phone's flat look was drawn from this screen. Queue an album of a dozen songs or so,
FLAC if you have one, and open Now Playing.

- **550 The face.** **Not done yet.** As drawn. "3 of 11" and the format match the song; the transport works as
  before. (Along the top, **Close** at the left, **Turntable** and **•••** at the right: purple, with no box round any
  of them, each easy to tap. Close closes Now Playing; so does a swipe down from the top row or the cover. The cover
  is as wide as the screen less the same margin either side as everything under it. The title is white and bold,
  "Artist — Album" under it in purple - tap it: the album opens. Beside the title, at its right, two small typewriter
  lines in grey, "3 of 11" over "FLAC 16/44.1" (or "MP3" for a lossy song), its first line level with the title's -
  skip a song: the number moves on; add a song with Play Next and play it: no number, the format alone. Make the text
  the largest accessibility size: the two lines go under the title, and the title keeps its room. The scrubber is
  sunk into the page - a dark track with a thin line round it, the part played grey inside it - and grows under your
  finger as before; tap and drag still seek where you let go, and VoiceOver still reads "Position in the song" and
  moves 5 seconds a swipe. Its times under it are in the typewriter figures and hold still as they count. Shuffle,
  previous, play/pause, next and Repeat look and work as they did. Download the Queue from the •••: the notice shows
  between Close and the buttons at the right and covers none of them. Make the text two sizes up from the default
  (xxLarge) and do it again: the notice lies across the screen just under the top row, over the cover, no word broken
  in half - and at the largest accessibility size it is no bigger than at the largest standard one. Touch and hold
  Close, Turntable or the ••• at the accessibility sizes: each shows large.)
- **551 The turntable.** **Not done yet.** Turntable swaps the look, the speed shows, and Lyrics take the cover's
  place, as before. (Tap **Turntable**: the record, with **Cover** where Turntable was; tap Cover: the cover again.
  VoiceOver reads them "Show as a turntable" and "Show the cover", as before. On the turntable the title and "Artist —
  Album" are as they were - centred, "Artist — Album" grey - with no number or format beside them. Set a speed off 1x: the readout on the turntable, the
  chip above the bottom row on the cover. Tap **Lyrics**: they take the cover's place, the top, the title and the
  buttons stay put, and scrolling them never closes Now Playing; tap Lyrics again: the cover. A song whose lyrics
  can't be fetched shows **Try again** as a purple word, with no box.)
- **552 Both phones.** **Not done yet.** Green Anole: the rest as before. Ethan's: 550-551, or "not done yet".

#### An album, Playlists, a playlist (553-558)

**Not done yet.** On the Mac an album's page, Playlists and a playlist's page become its own: a toolbar, a column list
of the songs (or the playlists) and the facts in the status bar. On the phone an album's page and a playlist's are
redrawn: square, the cover at the top, **Play** and **Shuffle** side by side, and the bar's **•••** holding Download
where the download button was. Nothing is played, added or downloaded any differently.

- **553 An album.** **Not done yet.** On the Mac every toolbar action works. Plays match Navidrome's; Properties matches
  the folder. (The toolbar: **Play**, **Shuffle**, **Add to Queue**, **Add to a playlist…**, **Download** and, if you
  may edit the album, **Edit** at its end; it fits a window of 880 and one of 1280 with the side panel open - should it
  ever not, it folds to Play, Shuffle and a **•••** with the rest. Download downloads at once with nothing of the
  album on this Mac, otherwise it is a menu saying how far it has got. A song played no times shows no number under
  **Plays**, never 0. An album of several discs, or with a disc titled, has a heading row above each disc's first
  song ("Disc 2 · Live"), its songs numbered 1, 2, 3 under it. A double-click or Return plays from a song; a
  right-click on a song, or on the top of the page, gives its menu. **Properties** shows Released, Added, Format, Size
  - only when every song gives its size - and, for an admin, the Folder (Folders for more than one) as Album info
  shows it, with logins off too. Under the album's name: "Played yesterday · 12 times", once it has been played.)
- **554 Playlists.** **Not done yet.** The columns are right. On a playlist, Play, Edit order, Rename and Delete work.
  (Playlists' columns: Playlist, Songs, Length, Whose - Yours, the owner's name, or From a file - Changed and On this
  Mac, the name keeping room in a window of 880 and one of 1280 with the side panel open. Yours come first, then
  those shared with you, then those from files. **New playlist…** makes one and opens it; Play and Shuffle play the
  playlist selected once its songs have come - type in Find until it's hidden and they dim. Offline with nothing
  downloaded, the status bar says nothing, never "0 playlists". A playlist's **Edit** opens the form - drag the songs
  into order, change the name, **Delete playlist** at its foot - and **Done** saves it.)
- **555 Played.** **Not done yet.** Albums' Info and the album page agree on when and how often it was played. (Leave
  the page open past midnight: "today" becomes "yesterday" on both.)
- **556 An album on the phone.** **Not done yet.** As drawn. The ••• adds to the queue, to a playlist, and downloads,
  saying the download's state. Play, Shuffle, the pull and a row's swipe work. (The top row: ‹ back, **Edit** if you
  may edit the album, then the **•••**: Add to Queue, Add to a playlist…, Download - headed with how far it has got -
  then Album info and Refresh. No Play Next or Play Last. Play and Shuffle are 48 points tall, side by side - Play
  the purple button, Shuffle its word in purple with no face; at the
  largest text sizes they stand one over the other. At the largest text size a song's number - even 100 or more - has
  its room before the title. With VoiceOver a song reads its number first, then its title, and its actions hold
  **Add to Queue** once.)
- **557 A playlist on the phone.** **Not done yet.** Edit, Play, Shuffle and Download work. (The •••'s Download items
  are headed with the playlist's line; each song's album shows under its title. A playlist that has gone, or has no
  songs, still offers **Remove Download** in the ••• while a download of it is here. **New playlist…**'s Create and
  Cancel stand one over the other at the largest text sizes.)
- **558 Both phones.** **Not done yet.** Green Anole: the rest as before. Ethan's: 556-557, or "not done yet".

#### An artist (559-563)

**Not done yet.** On the Mac an artist's page becomes its own: a toolbar, a band with their picture, name and facts, Top
Songs, the discography as a table, and the songs of theirs you have played most. On the phone the page under the top is
redrawn flat: **Play** and **Shuffle** side by side, a strip of Studio only and Everything, and the albums on thin lines.
Nothing is played, asked or opened any differently. Open an artist with a few albums of yours and some you don't have,
with Last.fm on.

- **559 The band.** **Not done yet.** On the Mac: the name, the facts, the listeners and the chips. (Their round
  picture, their name, who they are on MusicBrainz - "Group · Sydney · since 1973" - under it, then "2.3M listeners"
  once Last.fm answers, and at the band's right the chips: "6 in your library" in green, "2 in the collection", "10
  more to get". The toolbar: **Play**, **Shuffle**, then Studio only | Everything once their albums on MusicBrainz are
  asked, and - only for someone who may - **Artist images…**, **Move albums…** and **Which artist is this?** at its end;
  in a window of 880 those three fold into a **•••**. The status bar: "16 albums", "6 in your library", "59 songs".)
- **560 Top Songs and Most played.** **Not done yet.** Each plays from the tap; Most played matches the albums' plays.
  (On the Mac a double-click or Return plays from a song, as an album's songs do; a top song you don't have opens the
  album you don't have, its row spinning while it's asked; a right-click on a song you have gives its menu. Top Songs
  shows all ten, with "From Last.fm" under it, and comes after the discography when Last.fm answered late. Most played
  lists each song once - a song on two pressings is one row, its number the most-played copy's, the number its album's
  page shows under **Plays**. A song you have never played isn't listed.)
- **561 The discography.** **Not done yet.** Each album shows its format; Play, Open and Get work. (Columns: Album,
  Year, Songs, In your library - the chip, then the album's format, "FLAC · 24-bit / 96 kHz", once its songs have come,
  or "2 pressings" for one of theirs you hold twice, or "not in your library" - and the buttons. An album of yours has
  **Play** and **Open**; one nobody has, **Get**, which opens the album you don't have; one of theirs the library holds,
  **Open**. A double-click or Return opens a row; a right-click on an album of yours gives its menu. Studio only and
  Everything change the rows. Offline an album with nothing on this Mac is dimmed and does nothing. The table is as
  tall as its rows at every View > Row Size: the page scrolls, never the table.)
- **562 An artist on the phone.** **Not done yet.** As drawn. Top Songs plays; Get opens the album you don't have; the
  managers' two open their sheets. (Under the round picture and the name, who they are on MusicBrainz and the
  listeners; **Play** the purple button and **Shuffle** its word in purple, side by side - one over the other at the
  largest text sizes; Top Songs' five on thin lines with **See All**; then the strip: **Studio only** and
  **Everything**, the chosen one white over a short purple line, then - only for someone who may - **Artist images…**
  and **Move albums…**, which open their sheets and are never shown chosen; then **Albums** with its count at its end,
  "16 · 6 yours", and each album on a thin line: yours and theirs the library holds with the chevron, one nobody has
  with **Get** in purple words. The bar's **•••** holds Which artist is this?. With VoiceOver an album is one item -
  "Low, 1977 · not in your library" - its actions holding Get; a top song you have is one item whose actions hold Add
  to Queue and Add to a playlist….)
- **563 Both phones.** **Not done yet.** Green Anole: the rest as before. Ethan's: 562, or "not done yet".

#### Requests (570-573)

**Not done yet.** Requests in the new look: on the Mac a table of its own, with Search Soulseek in the toolbar and the
counts and speed in the status bar; on the phone the drawing's cards with their meters. Start a download or two first,
so something is downloading, waiting and done.

- **570 The table.** **Not done yet.** On the Mac the groups, the progress and the speeds match slskd. Cancel and Next
  peer work. (The groups are Downloading, Waiting, Needs attention and Done, each only with rows; All | Active | Done
  narrows them; the status bar counts each and sums the speed. Next peer is the row's **Another source**; **Same source
  again** is in its **•••** and its right-click. ↑ and ↓ move between rows. A word cut short in Progress shows whole
  when you hold the pointer over it. In a narrow window the toolbar's fields narrow, and beside a side panel All,
  Active, Done and Clear done fold into one pop-up.)
- **571 Manual search.** **Not done yet.** Search from the toolbar; a Done row opens its album. (Artist, Album and
  **Search** open Choose a source - Return in Artist goes to Album, Return in Album searches; a Get from it shows in
  the table. A done row's **Open**, a double click or Return opens the album; **Play** plays it.)
- **572 Requests on the phone.** **Not done yet.** As drawn. Meters and speeds match slskd; Cancel, Next peer and the
  manual search work; a Done row's ▶ plays. (A card has no grey face, a thin line under it, the cards one under
  the other; the ✕ and the ▶ are bare purple glyphs; everything is square; the line under a meter reads like "3 of 11
  files · 244 KB/s". Next peer is **Another source**; Search Soulseek… is the first row.
  At the largest text sizes a card's two buttons stand one over the other, their words on more than one line.)
- **573 Both phones.** **Not done yet.** Green Anole: the rest as before. Ethan's: 572, or "not done yet".

#### Row Size (608-609)

**Not done yet.** On the Mac, **View > Row Size** makes every list's rows Small, Medium or Large, and ⌘+ and ⌘− step
between them. Nothing on the phone changes. Have a few albums, a playlist and a request or two to look at.

- **608 View > Row Size and the keys.** **Not done yet.** Each size works, the tick follows it, the ends dim, and it's
  kept after a quit. (The submenu, under View's **Refresh**: **Small**, **Medium** and **Large**, the one in use
  ticked, then **Make Bigger** ⌘+ and **Make Smaller** ⌘−. A new install starts at Small, the rows as they were. ⌘+
  grows the rows one size - typed as ⌘⇧=, or as ⌘= in the main window - and ⌘− shrinks them one; at Large Make Bigger
  is dimmed and ⌘+ and ⌘= do nothing, at Small Make Smaller is dimmed and ⌘− does nothing. After each key the tick
  has moved to the new size. Choose Large, quit with ⌘Q, open deadwax again: still Large, still ticked. Tab through
  the main window with keyboard navigation on: nothing invisible takes a stop. Say what ⌘+, ⌘− and ⌘= do with a sheet
  open, and before you sign in. With VoiceOver the submenu and its items read as any Mac menu's.)
- **609 Every list follows it.** **Not done yet.** Albums, Artists, an album, Playlists, a playlist and Requests all
  change together, and Large still fits at the smallest window with the side panel open. (Albums and Artists in
  List, an album's songs, Playlists, a playlist's songs and Requests: at each size the rows and their covers grow and
  shrink, the words stay their size in the middle of the row, and the column headings and a disc's heading row don't
  change. An album's songs box is as tall as its songs at each size, scrolling inside only when the window is too
  short. Requests' meters stay readable, nothing in a cell touches its edge. At Large, with the window at its
  smallest (880) and the side panel open over the page, Playlists shows every column with the names readable, and
  Requests scrolls sideways as it does at Small; in a window as it first opens (1280) Requests fits without
  scrolling. An album with many songs in a window made short (about 600 tall) at Large: Properties is still on the
  page, the songs scrolling inside their box. Select a row far down a long list, then change the size: the row is
  still in view. Rows still select, open and right-click as before, and VoiceOver reads each as before.)

#### The new faces: Libre Franklin and Courier Prime (610-611)

**Not done yet.** The app's words in Libre Franklin and its readouts in Courier Prime, on the iPhone and the Mac, in
place of Noto Sans. Nothing else should have moved: the same sizes, the same layouts.

- **610 The faces.** **Not done yet.** On both phones and the Mac, the words are Libre Franklin and the readouts
  Courier Prime, as the design canvas draws them, and both read well at the largest text size too. (Look at a page of
  each kind: the Library, an album, Now Playing, the Queue, the EQ, Requests, Settings. Words are the titles, rows,
  buttons and notes; readouts are the clocks, the time left on the phone's Queue, a song's length and number on a
  redrawn album page, Requests' progress and speeds, the EQ's values and its preamp, and the size in Settings'
  Downloads row - Settings > Downloads' own amount and counts are words, as drawn. Where a readout sits beside words,
  in Settings' Downloads row, the EQ's preamp, Info's facts, the Mac's tables and status bar and the player bar's
  line under the title, both sit on one line, the readout not a point or two higher. At the largest text size, under
  Settings > Accessibility > Display & Text Size > Larger Text, nothing is cut off or overlapping that wasn't before,
  and on the phone the Queue's and the EQ's tops still fold where they
  did: the Queue's History and Clear into its ••• from one size above the standard, the EQ's "EQ on" at the largest
  size before the accessibility ones. Say anything that looks too heavy, too light or out of place.)
- **611 Numbers that hold still, and other alphabets.** **Not done yet.** Numbers that change hold still, and a
  Greek or Cyrillic artist's name draws. (Play a song and watch the scrubber's clocks and, on the phone, the Queue's
  time left: their figures don't shift sideways as they count. On the Mac, the same for the player bar's clocks and
  Requests' speed in the status bar while something downloads; the Mac Queue's time left is in words, as drawn, and
  changes once a minute. Drag an EQ slider or handle: the value over it, and deadwax's own preamp, keep their width.
  A count inside a sentence - Settings > Downloads while songs come - is in words and may shift a little: that's as
  the new look draws it.
  Then find an artist or album with a Greek name and one with a Cyrillic name (in Search, if the library has none):
  every letter draws - none is a box or a question mark - though a Greek name, and Cyrillic in a readout, is in iOS's
  own face.)

#### The phone, flat (612-614)

**Not done yet.** The phone is redrawn flat, as Now Playing is drawn (James: "get rid of all the grey boxes"): words
and glyphs on the page, thin lines between things. Only the purple button (and the red ones), a sunken
track, a picture and anywhere you type keep a face. Nothing works any differently, and the Mac doesn't change. Have a
download or two on Requests and something queued.

**Not flat yet**, each until the slice that redraws it: Settings and its pages, Sign in and the server address (R9);
Search, an album's Get and Choose a source's cards (R7); Edit album's pages (R10 and R11); Needs a look (R12); Library
care and the Event log (R13); People and Server settings (R14); and the EQ's own pages - Correction's search and a
filter's editor - and an artist's Artist images and Move albums sheets, which no slice has taken yet. Those keep iOS's
grouped lists and their grey rows for now: don't count them in 612.

- **612 The flat look.** **Not done yet.** Go through the Library (Albums, Artists, Songs, Playlists and Downloaded),
  Requests, an album, a playlist, an artist's page, Now Playing's sheet and Search Soulseek…'s sheet - not the screens
  above that aren't flat yet: is anything still a grey box laid on top? Is every button still plainly a button, and
  does a tap show? (Any button that isn't purple is its words or its glyph in purple, as tall as before, faded while
  your finger is on it - an album's Shuffle, **Same source again**, a card's ✕, the EQ's output, Downloaded's **Not
  Now**, an empty library's **See All music**. A group - Info's This song, the EQ's Correction - is a grey heading
  over its rows, with no panel; a download's card, and Downloaded's question about downloading your library, are words
  on the page with a thin line under them. The Library's magnifying glass and ••• are bare white glyphs; its switch,
  and the sheet's Queue, Info and EQ, are words over a thin line, the chosen one white over a short purple line as
  wide as it. **In your library** is green words after a green dot; the **New** mark on a cover keeps its small
  purple box, as the count on Requests' tab keeps its own. The mini player and the tab bar are black under a thin
  line, the same black as the page under them - an album's and a playlist's page too, with no seam where they meet -
  and the mini player's cover has no line at its right; drag along its line and the time over your finger is in a
  small dark box. A Done row's ▶ is a bare purple glyph. An artist's page opens on their round picture beside their
  name, and its albums and top songs sit on thin lines.) A tap a little beside a small button still takes: between two of the sheet's Queue, Info and EQ, the nearer
  one opens; just beside the Queue's Edit or its •••, that button. With four pages (logins off), the Library's switch
  sits under the glyphs at the standard text size on a narrow phone: say whether that's all right. On the Queue,
  Shuffle and Repeat are purple words, bold while on: can you tell on from off? With the •••'s menu open, the •••
  stays white (the drawing has it purple): say if you miss it. VoiceOver reads every button, switch and strip as
  before; at the accessibility sizes, touch and hold a page's word in the Library's switch: it shows large.
- **613 Every place you type is still a box.** **Not done yet.** None of them has gone flat: the Library's Find (a dark
  sunken box, its edge purple while it has the cursor), Search's field, Requests' **Search Soulseek…** sheet's Artist
  and Album, a playlist's Edit name and description, Edit album's fields, Server settings' values, sign-in's two,
  People's and Change password's. (The manual search's two and a playlist's Edit two are now dark sunken boxes like
  Find's, square, the edge purple while you type in one, and a tap on the box or just above or below it puts the
  cursor there; a playlist's description grows a line at a time as before. Apart from those and Find, each is drawn as
  it was before this build.) Requests' **Search Soulseek…** row itself is purple words on a thin line, with no box -
  James's rule is about where you type - and its sheet is black with no grey rows: the two boxes, the note under them
  in grey words, and the purple **Search**. Return in Artist still goes to Album, and Return in Album searches.
- **614 Both phones.** **Not done yet.** On Green Anole, 612-613, and the menus, toggles, covers, the scrubber, the
  meters, Now Playing and the turntable as before. On Ethan's phone, 612-613, or "not done yet". On the Mac nothing
  has changed: the buttons glossy and raised, the chips tinted, the segmented controls in their wells - say if
  anything looks different.

## What it can't do yet

These are the web app's for now - open deadwax's address in a browser for them, since nothing in the app takes you
there. Looking after deadwax isn't among them any more: every managing tool is the app's own (see [Manage](#manage)).

- **The visualizer**: it stays the web app's, on a desktop.
- On an artist's page their **description**, and the page following an artist whose albums
  [Move albums](#managing-an-artist) moved to their name now.
- In **Search**, an artist you don't have's page lists their albums, without their description or links. A search
  of what's downloaded while deadwax can't be reached isn't built: offline, Search keeps a list already drawn, and
  new words wait for deadwax.
- **Home** and **pins** - and so Home's Arriving: outside Requests, the tab's badge is the phone's only sign of a
  download on its way.

## When something goes wrong

| what you see | what to do |
| --- | --- |
| **"Couldn't reach deadwax at ..."** on the address screen | Check the address, and that the phone is on your home Wi-Fi or WireGuard. If you said no to the local network question, turn deadwax on in the iPhone's Settings > Privacy & Security > Local Network. |
| **"Can't reach deadwax. Check you're on the right network (or your VPN is on) and try again."** as the app opens | The same: the phone's network, or deadwax itself. **Try again**, or **Change address** if deadwax has moved. What failed, for whoever runs deadwax, is folded away under it. |
| **"Something went wrong on the server - try again in a moment."** as the app opens | deadwax answered, with an error. **Try again**; if it lasts, deadwax's log says why. |
| Sign in: **"That user name and password didn't work."** | Your Navidrome user name and password, as on the web app. |
| Sign in: **"Too many tries for ... - wait ... seconds and try again."** | deadwax holds off so Navidrome doesn't lock the account. Wait, then try again. |
| Sign in: **"Navidrome isn't answering, so deadwax can't check your password right now - try again in a moment."** | deadwax signs people in through Navidrome, and Navidrome is down, or deadwax can't reach it. Check that Navidrome is running, then sign in again. |
| Sign in: **"deadwax can't reach the music server, so nobody can sign in just now. Tell whoever runs deadwax."** | deadwax hasn't been told where Navidrome is, or the address it has can't be used. Whoever runs deadwax sets it in [Navidrome settings](configuration.md#navidrome-settings--connections); what's wrong is folded under "For whoever runs deadwax". (A deadwax older than 2.0.4 says "Something went wrong on the server - try again in a moment." here instead.) |
| The sign-in comes up over the app, with a reason ("Your sign-in ran out after 30 days without use - sign in again.") | Sign in again. The music plays on underneath. |
| Library: **"Your music isn't available right now"** (an admin sees **"Can't reach Navidrome"**) | deadwax can't reach Navidrome. Check Navidrome is running, then **Try again**. |
| Library: **"Your music isn't available yet"** (an admin sees **"Connect Navidrome"**) | deadwax hasn't been told where Navidrome is. An admin's **Set up Navidrome** opens Server settings' Connections page over the Library: fill in Navidrome's address, user and password, **Save changes**, and the Library fills once Navidrome answers ([Set up Navidrome](#set-up-navidrome)). |
| Server settings: **"Not saved: …"** | deadwax refused the whole save, naming each setting and what's wrong with it - nothing was saved. Every change is still there to put right; then **Save changes** again. "Type the password again to go with the new address" (or the API key) means an address changed without its secret: type it on the same page. |
| Server settings: **"deadwax may have finished this - looking again"** | The save's answer never reached the phone (it locked, or the network dropped). The settings are read again: what was saved is no longer marked Unsaved, and only what still differs stays to save. If they can't be read, the bar says so with **Try again**; **Discard** gives up on the save's outcome and shows the settings as they are. |
| A row of Settings > Manage opens a page saying **"This page needs a permission an admin hasn't given you"** (People: **"Only an admin can open People - it comes with being a Navidrome admin."**) | An admin took that permission away since deadwax last told the app (or, for People, Navidrome no longer has you as one of its admins). Pull down on Settings: the row goes. Ask an admin if you need it. |
| People: **Unlock People** again, after it was unlocked | deadwax forgets an unlock 15 minutes after it was last used, and when you tap Lock - this is that. Type your Navidrome password and **Unlock** again. See [People](#people). |
| People: **"That isn't the password you signed in to deadwax with - if you've changed it since, sign out and in again."** | Unlock wants the Navidrome password this phone signed in with. If you changed it elsewhere since, sign out of the app and in again with the new one, then unlock. |
| People: **"That's a lot of changes in a minute - wait … seconds and try again."** | deadwax takes ten changes a minute from each admin, so a slip can't run away with Navidrome's accounts. Wait as long as it says. |
| People: **"deadwax may have finished this - looking again"** | The change's answer never reached the phone. People is read again: the list says whether it went through - check before trying again. Nothing is sent again by itself. |
| People: **Make account**, **Reset password** or **Remove** stays dimmed | What's typed breaks a rule (said under the fields), Remove's name isn't typed exactly, another change is out, People is being read again after one, or deadwax can't be reached. |
| Edit album: **"deadwax can't find this album's folder: …"** | No folder in deadwax's library is matched to the album, or none has its name. **Choose the folder** and pick it yourself - or, if it was only just filed, **Look again** in a moment. See [Edit album](#edit-album). |
| Edit album: **"deadwax may have finished this - looking again"** | The Apply's answer didn't reach the phone (locked too long, or the connection dropped); deadwax carried on regardless. The sheet reads the folder again: check What Apply does - often "Nothing to change." - before applying again. |
| Edit album's **Apply** stays dimmed | What Apply does is still being worked out (or a release's tracklist is loading), there's nothing to change, or deadwax can't be reached. |
| Edit tags' **Apply** stays dimmed | A field says in amber what's wrong with it, What would change says "Nothing to change", it's still being worked out - or Release is applying or saving a cover, and Edit tags waits for it. |
| Edit album's **Delete permanently** stays dimmed | deadwax is still reading what's in the folder ("Checking what's in there…"), or couldn't ("Couldn't read that folder." - **Look again**); another write is running, or the folder is still being read again after one; or deadwax can't be reached. |
| Delete album: **"Couldn't delete it."** after "deadwax may have finished this - looking again" | The delete's answer never reached the phone, and the library read again still has the folder: it wasn't deleted. What's in it has been read again - **Delete permanently** to try again. |
| Edit album's **Get cover**, **Get CD art** or **Get lyrics** stays dimmed | Another write is running (an Apply, a cover, another Get), the folder is still being read again after one, or deadwax can't be reached. Wait for it; after "Couldn't read the library.", **Look again**. |
| Get CD art: **"No CD art on the Cover Art Archive for this release - a fanart.tv key in Server settings adds another source."** | Nobody has uploaded a picture of this pressing's disc. A fanart.tv key ([Server settings](#server-settings) > Connections) lets deadwax look there too; then **Look again**. |
| Get lyrics: **"… 2 failed - try again."** | LRCLIB didn't answer for those tracks just then (it's busy at times). Tap **Lyrics · …** to ask again: only the tracks still without lyrics are asked. "Not on LRCLIB" is LRCLIB having none - asking again won't change it. |
| Edit album's Tags: **"Couldn't read the files."**, with **Look again** | deadwax couldn't read the folder's files just then - the disk asleep, or the folder moved. **Look again**; if the album was just applied with a new release, its files were renamed, so go back to Tags and choose them again. |
| Library: **"Couldn't update this list - showing it as it was."** | deadwax didn't answer just then. ••• > Refresh to try again (pull down, on a list opened from the •••). |
| An album's page: **"This album isn't here any more - it may have been moved or deleted."** | Go back, and ••• > Refresh in the Library to bring it up to date. |
| An artist's page: **"This artist isn't here any more - their albums may have been moved or deleted."** | The same: go back, and ••• > Refresh. |
| An artist's page: **"Plays 2 of the 5 albums you have - the rest didn't load"**, or **"Couldn't load their songs."** | deadwax didn't send those albums' songs just then. **Try again** under it; Play and Shuffle meanwhile play the albums that came. |
| A song's line says **"The connection dropped while this song was loading"**, or the next song's says **"Skipped "..." - it wouldn't play"** | The app asks for a song once more after a moment, then goes on past it. Check the phone's network. |
| **"This device couldn't play this song's audio"**, or **"Skipped "..." - this device couldn't play its audio"** | The file is damaged, or in a form iPhones can't play. Try it on the web app; an admin finds the details in Settings > This phone > Debug > Playing. |
| Info's Normalization: **"Not this time - the album's volume couldn't be checked"** ("the song's" for a song levelled on its own) | deadwax is older than 2.1.1, or didn't answer in time. The song plays as it is; with 2.1.1 or later, the album's next play is levelled. |
| Lyrics: **"Couldn't load the lyrics."** | deadwax, or Navidrome behind it, couldn't give them just then: **Try again**. If it's every song, deadwax may be older than 2.1.5, which has no lyrics for the app (an admin sees why, folded under it). |
| Lyrics: **"This song isn't here any more - it may have been moved or deleted."** | Navidrome no longer has the song the queue names (a rescan moved it). Play it again from its album. |
| A playlist has no **Edit**: "Only Sam can change this playlist." | It's Sam's: only they can change it. A playlist from a file, or one of more than 2,000 songs, says why there's no Edit too - change those in Amperfy or Navidrome. |
| Edit: **"This playlist changed in another app while you were editing it - here it is now. Your changes weren't saved."** | It was changed elsewhere after you tapped Edit, so nothing was saved. Tap Edit and make your changes again on the playlist as it is now. |
| Edit: **"The songs were saved, but Navidrome didn't take the name, description or sharing."** | Edit stays open: **Done** again saves the rest. |
| Edit: **"Saved - but Navidrome didn't answer when deadwax asked for the playlist again."** | It's saved. **Done** again, or **Cancel**, and the page asks for it again. |
| The app's notice: **"Couldn't add to Late night."** and why | An add you'd closed Add to a playlist on was refused, or its answer didn't come back. Try again: if the songs did get in, it asks before adding them twice. |
| **Lyrics** is dimmed | The song has none - none on LRCLIB, or none fetched yet (**Get lyrics** in the album's [Edit album](#edit-album) > Lyrics, or Library care's lyrics, for someone who can edit albums). Offline, "Lyrics - not on this phone": none were kept for it, which happens to a song downloaded with app 0.3 until the app has been opened with deadwax in reach. |
| The EQ's correction picker: **"Something went wrong."**, with **Try again** | deadwax answered with an error. If it's every search, deadwax may be older than 2.1.7, which has no AutoEq for the app (an admin sees why, folded under it). |
| Search: **"Searching for more isn't working right now - try again in a few minutes."** (or **"Too many searches just now - try again in a moment."**), or an album you don't have says **"This album's details can't be loaded right now - try again in a few minutes."** | MusicBrainz is away, or turning searches away, for a while - it does, for minutes at a time. Your library's rows are still there; **Try again** in a minute. **"That took too long."** is the same, MusicBrainz slow enough that the phone stopped waiting. [The troubleshooting page](troubleshooting.md#the-apps-search-says-it-cant-search-for-more-or-keeps-searching) has the rest. |
| Search: an album you don't have shows an **empty square** for its cover | Its cover comes from the Cover Art Archive through deadwax, which needs deadwax 2.1.24 or later - see [the troubleshooting page](troubleshooting.md#the-iphone-app-shows-no-cover-for-an-album-you-dont-have). |
| Choose a source: **"slskd is not connected to the Soulseek network, so it cannot search"** (or **"Downloads aren't working right now."**), with **Try again** | slskd isn't logged in to Soulseek, or deadwax can't reach slskd. Whoever runs deadwax checks Connections, at the top of Settings > Manage > [Server settings](#server-settings) - [troubleshooting](troubleshooting.md#a-search-fails-with-not-logged-in-or-slskd-refused-it) has the rest - then **Try again**. |
| Choose a source: **'Nothing lossless found for “…”.'** | Your Format is Lossless only, which leaves out every copy that isn't. Change it in Settings > Getting albums, or **Search again** with other words. |
| Choose a source, with **Pick the best source for me** on: **"No close match that passes your filters - choose a source yourself."** (or **"You already have part of it - …"**, **"Part of it is already downloading - …"**) | Nothing through the chips scored 75% or more, or the pressing is partly here or on its way, so nothing was picked: choose one yourself. Clearing a chip, or a lower quality floor in Settings > Getting albums, lets more through. [The troubleshooting page](troubleshooting.md#get-shows-downloads-arent-working-right-now-or-nothing-to-choose-from) has the rest. |
| **Join this download** says **"That download has been cleared from the list since - get it again."** (or that it has finished, failed or been cancelled) | The download moved on after the line was drawn. Get the album again: the line then says what's true now. [The troubleshooting page](troubleshooting.md#join-this-download-says-the-download-has-finished-failed-or-been-cancelled) has the rest. |
| **Join this download** says **"deadwax didn't answer in time, so you may have joined it anyway. …"** (or **Add to my library**, **"… it may have been added anyway. …"**) | The phone waited a minute with no answer - a join waits for any other Get of the album to reach its source, and an add stars the album in Navidrome before it answers, so a slow slskd or Navidrome (or the connection dropping) does this. It may well have gone through: look in Requests (or Your albums) in a moment, and if it isn't there, tap it again - a second Join or Add does no harm. |
| Choose a source, with **Pick the best source for me** on: **"deadwax went out of reach as the sources came in - choose a source yourself once it's back."** | The phone lost deadwax just as the answer came, so nothing was got for you - a Get then would close onto a Requests that can't show it - and nothing is got later by itself. Once deadwax is back, tap a source's **Get**. |
| Settings > Getting albums: **"deadwax can't keep these: its database isn't writable."**, or a choice going back with **"Not saved. …"** | deadwax keeps the three in its database. Whoever runs deadwax checks `DB_PATH`, and that its folder can be written as `PUID`/`PGID`, then restarts the deadwax container - the choices in hand still apply to a Get meanwhile. |
| A Get's row under Needs attention says **"didn't start"** and **"It's already downloading."** (or **"…already in your library."**) | It was got - by you elsewhere, or by someone else - after the sheet searched. It's already in Requests, or already yours; **Clear done** takes the refused row away. |
| A Get's row under Needs attention says **"no answer"** and **"deadwax didn't answer in time, so this may have started anyway."** | The person sharing it took more than ten minutes to be reached, or deadwax was stuck. Look under Waiting and Downloading - it may be there - and if it isn't, get it again. **Clear done** takes the row away. |
| An album you don't have says **"Getting albums is off for you - ask an admin."** where Get the album goes | With logins on, an admin gives **Get albums** in [People](#people) (on their phone, or the web app's). Open Settings afterwards, so the phone asks deadwax again. |
| An album stays on **"Waiting for Wi-Fi"** (on the Mac, **"Waiting for Wi-Fi or Ethernet"**) | Download over is Wi-Fi only (Settings > Downloads): join a Wi-Fi network that isn't a phone's hotspot, with Low Data Mode off - or choose Wi-Fi and cellular. On the Mac it's **Wi-Fi or Ethernet only**: join a Wi-Fi network or plug in a cable, not a phone's hotspot - or choose **Any connection**. |
| **"Waiting for room - the storage limit is reached"** | Raise the Storage limit in Settings > Downloads, or remove something there (largest first). |
| Your library's albums stay on **"Waiting for the phone to charge"** (on the Mac, **"…the Mac to charge"**) | Only while charging is on (Settings > Downloads, under Download your library): plug the phone in, or turn it off. Albums you download yourself don't wait for it. On a Mac it waits only while the Mac is on battery: plug it in. A Mac with no battery (a Mac mini, an iMac, a Studio) counts as always plugged in, so it never waits there. |
| Your library didn't download with the app closed | iOS decides when the app runs in the background, and may not for hours; Background App Refresh off (the iPhone's Settings > General) or Low Power Mode stops it, and so does swiping deadwax away in the app switcher. Opening the app checks and downloads at once. Settings > This phone > Debug > Your library > In the background (an admin's) says whether iOS ran it. |
| **"Waiting for space on this phone"** (on the Mac, **"…on this Mac"**) | The phone itself is full: make room in the iPhone's Settings > General > iPhone Storage. On the Mac, its disk is: make room (System Settings > General > Storage). |
| **"2 songs didn't download"**, with why ("The copy kept arriving the wrong size.", "The copy's sound didn't match the original.", "This song isn't on deadwax any more.") | **Try again** in Settings > Downloads. If it keeps failing, the file on the server may be damaged: play it on the web app. |
| Settings > Downloads: **"This phone couldn't read its downloads - close deadwax from the app switcher and open it again."** (on the Mac, **"This Mac couldn't read its downloads - quit deadwax and open it again."**) | Downloads are off until the app opens again; nothing is deleted, and downloaded songs stream meanwhile. If it lasts, the phone (or the Mac) may be nearly full. |
| **"Not on this phone - it plays once deadwax is back."** | The song isn't downloaded and deadwax can't be reached. Download what you want offline before you go. |
| The beep album isn't found | Make it with `make-test-album.py` into your music library (see "What you need"), let Navidrome scan it, then Check again in Settings > This phone > Debug (an admin's). |
| **"Untrusted Developer"** when opening the app | The iPhone's Settings > General > VPN & Device Management > your Apple ID > Trust. |
| The app won't open at all after a week | The free install ran out. Run `install.sh` again: nothing on the phone is lost. |
| install.sh: **"No paired iPhone the Mac can reach now"** | Connect the cable and unlock the phone (or turn on Connect via network in Xcode, with the Mac and the phone on the same Wi-Fi), then run it again. |
| install.sh: **"Xcode has changed ios/Deadwax.xcodeproj here"** | A team was picked in Xcode's Signing & Capabilities. Run `git checkout ios/Deadwax.xcodeproj`, keep the team in `ios/Config/Local.xcconfig`, and run install.sh again. |
| install.sh: **the build failed** with a signing or profile error | The first install has to come from Xcode with the cable (step 5 of "Once"). After that, the script renews the signing by itself. |
| install.sh: **Xcode knows no Apple ID** | Add it in Xcode > Settings > Accounts, then run the script again. |
| A free account says it can't install more apps | A free account can have only 3 of its own apps on the phone at once. Delete one you don't need. |
| The Mac app: **"Couldn't reach deadwax at ..."** on the address screen | On macOS 15 or later, if you said no to "find devices on your local network", turn deadwax on in the Mac's System Settings > Privacy & Security > Local Network, then quit deadwax and open it again (macOS 14 has no such switch). Otherwise the same as on the phone: the address, and that the Mac is on your home network or WireGuard. |
| The Mac app: macOS says deadwax **can't be opened**, or that it **can't check it for malicious software** | Open System Settings > Privacy & Security, and under the message about deadwax choose **Open Anyway**. An app built and signed on your own Mac isn't expected to be stopped - say so if it is. |
| The Mac app asks you to sign in **every time it opens** | Its sign-in can't be kept in its folder (see [Where the Mac keeps your sign-in](#where-the-mac-keeps-your-sign-in)). Check the Mac's disk isn't full; then, with deadwax quit, delete `~/Library/Containers/net.lizardlounge.deadwax/Data/Library/Application Support/deadwax/sessions` and sign in again - it's made afresh. If macOS asks whether "Terminal" would like to access data from other apps, **Allow** is right: it's deadwax's own folder. |
| The Mac app: **Import EQ File…**, the EQ's **Import…**, Open With or a file dropped says **"deadwax couldn't read this file."** for a `.txt` you can open in TextEdit | The Mac app is meant to be allowed to read the file you choose in the Open panel, open with it or drop - say so, with any words under it. Meanwhile **Paste** brings it in: open the file in TextEdit, Select All, Copy, and Paste on the EQ page. |
| The Mac app: Export…'s **Save the Whole Curve…** (or the Correction Alone) puts no file where you saved it | The Mac app is meant to be allowed to write the file you save in the Save panel - say so. Meanwhile **Share the Whole Curve** hands the same file to AirDrop or Mail. |
| The Mac app **quits the moment it opens**, after a new build | macOS throws out an app whose menus have one key twice. Say so, with the build - deadwax's menus were checked against macOS's own, but only a Mac can show it. Meanwhile install the build before it. |
| The Mac app: **Edit > Copy** stays dimmed in the event log with lines selected | Copy answers for the lines once the list has the keyboard: click another line (clicking the same one again changes nothing). If a text field has the cursor (the sidebar's search, say), Copy is that field's - press Tab or click away from the field, and Copy is the lines' again. Meanwhile right-click a line for its own Copy. |
| The Mac app: **File > Save changes** (⌘S) stays dimmed on Server settings | It's on only with something changed and not yet saved, deadwax in reach, no save on its way, and Server settings' page in front - not with another sheet over it. The bar's **Save changes** says the same: if that's on and ⌘S isn't, say so. |
| The Mac app: closing its window **stopped the music** | Closing the window is meant to leave the music playing (check 421) - say so, and whether it happens every time. Meanwhile keep the window open, or minimised (⌘M), while you listen. |
| install-mac.sh: **"There's no ios/Config/Local.xcconfig"** or **"has no team id in it"** | Run `ios/scripts/install.sh` once - it offers to write the file from the teams Xcode knows - or copy `Local.xcconfig.example` beside it and put your team id in it (step 4 of [Once](#once)). |
| install-mac.sh: **"Only … free. A build of the Mac app needs about 4 GB free"** | Free some space - emptying the Trash, or deleting `~/Library/Caches/deadwax-build-mac`, which only makes the next build start afresh - and run it again. |
| install-mac.sh: **the build failed** with a signing or certificate error | Xcode has no Apple Development certificate for your team yet: Xcode > Settings > Accounts, select your Apple ID, **Manage Certificates…**, **+** > **Apple Development**. Then run it again. The whole log is `~/Library/Caches/deadwax-build-mac/last-build.log`. |
| install-mac.sh: **"The new app wasn't signed as the Mac app must be"** or **"The new app's bundle id is …"** | Something changed the Mac's build settings in `ios/Config/Base.xcconfig`; `xcrun python3 ios/scripts/check_project.py` says what. Nothing was installed: the deadwax.app in ~/Applications is as it was. |
| install-mac.sh: **"deadwax couldn't be asked to quit"** | macOS didn't let Terminal control deadwax. Quit deadwax yourself (deadwax > Quit deadwax) and run `install-mac.sh --no-pull`, or allow Terminal to control deadwax in System Settings > Privacy & Security > Automation. |
| install-mac.sh: **"deadwax didn't quit within 20 seconds"** | deadwax may be asking something in its window. Look, quit it yourself, and run `install-mac.sh --no-pull`. It's never quit by force. |
| install-mac.sh: **"Not installed: Xcode signed this build with a provisioning profile…"** | The Mac app is signed with no profile so that it never runs out; one added after all would stop it opening on the date it names. Nothing was installed: the deadwax.app in ~/Applications is as it was, and deadwax wasn't quit. Run `xcrun python3 ios/scripts/check_project.py` - it names any setting in `ios/Config` that would need one. Then delete the profile it names from `~/Library/Developer/Xcode/UserData/Provisioning Profiles`, and `~/Library/Caches/deadwax-build-mac`, and run install-mac.sh again - and say you saw this. `--allow-profile` installs such a build anyway (`--yes` doesn't). |
| install-mac.sh: **"Note: Xcode signed this one with a provisioning profile, which runs out on …"** | Only with `--allow-profile`. It will stop opening on that date until install-mac.sh runs again without one. |
