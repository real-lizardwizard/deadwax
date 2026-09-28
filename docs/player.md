# The phone player

There's a second page in deadwax, at **`/player/`**: a music player for your library, made to be
added to an iPhone's home screen and opened like an app. It plays from
**[Navidrome](https://www.navidrome.org)**, through deadwax, which keeps Navidrome's login and
passes on the player's requests, so the phone never holds Navidrome's password and only ever
needs to reach deadwax.

It's early. Playing on a locked iPhone, and moving to the next song by itself there, have been
seen working on a real iPhone; other things haven't been confirmed yet.
[The list is below](#not-yet-verified-on-a-real-iphone).

## What you need

- **Navidrome**, reading your music library. The player plays whatever Navidrome has, so point
  Navidrome at the same folder deadwax files albums into.
- **An account on Navidrome for the player to use.** Use one of your own, and not an admin
  account: nothing the player asks Navidrome for needs one. Plays are counted on this account.

## Setting it up

Three settings, all blank by default, in **Settings → Connections** (or in your compose file or
`.env`, like any other setting; see [Configuration](configuration.md#the-phone-player-settings--connections)):

| setting | what to put there |
| --- | --- |
| `NAVIDROME_URL` | Navidrome's address **as seen from inside the deadwax container**, with the `http://` |
| `NAVIDROME_USER` | the Navidrome account the player plays as |
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

Then open `http://your-server:8080/player/`. If something's wrong, the page says what, in place
of the albums: **Connect Navidrome** when the settings aren't all there, or **Can't reach
Navidrome** with the reason and a **Try again** button. [Troubleshooting](troubleshooting.md#the-player-says-connect-navidrome-or-cant-reach-navidrome)
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

## What it does

- **Your albums**, in a grid, in one of four orders: **Recently added**, **Recently played**,
  **Artist** or **Title**. The order you pick is remembered on that device. More albums load as
  you scroll.
- **An album**: its cover, **Play** and **Shuffle**, and its songs, under "Disc 1", "Disc 2"
  headings for a set. Tap a song to play the album from there. Shuffle plays the album's songs
  in a random order.
- **A mini player** along the bottom while something is playing, with play/pause and next. Tap
  it to open the now-playing screen.
- **Now playing**: a large cover (a grey square for an album without one), a scrubber, previous,
  play/pause and next, and an **AirPlay** button when there's a speaker on the network to send
  to. Drag it down, or tap the arrow at its top, to close it.
- **The scrubber** is the whole bar: tap anywhere along it to jump there, or drag from anywhere on
  it and it follows your finger, seeking when you let go. It works from the keyboard too (arrows
  move 5 seconds, Page Up and Page Down 30, Home and End to the ends), and VoiceOver's swipe up
  and down move it. [Seeking](#seeking-and-where-safari-lands) says why a seek in Safari can land
  somewhere other than where you put it.
- **Previous** restarts the song if you're more than three seconds in, and goes back a song if
  you're not, as Apple Music does.
- **A song that won't play doesn't stop the album.** The player asks for it once more a moment
  later, and if that fails too, moves on to the next song, saying **Skipped "…"** and why under
  its title for a few seconds. At the end of the queue it stops, with the reason on screen.
  [Troubleshooting](troubleshooting.md#a-song-in-the-player-wont-start-or-cant-be-skipped-through)
  goes through the reasons.
- **The lock screen and Control Center** show the song, its artist, album and cover, with
  previous, next and a scrubber. There are no 10-second skip buttons: iOS shows either those or
  previous and next, never both.
- **Back** works: an open album is in the page's address, so the browser's back goes back to
  the grid, where you left it.

## Gapless playback (experimental)

Between two songs there's normally a short pause, about a second on an iPhone over a VPN: when
one song ends, the phone has to ask deadwax for the next one and start it from nothing. The
**Gapless** switch on the now-playing screen, beside the album's name, is an experiment in
closing that gap. It's **off** by default. Its setting is kept on the device, and a home-screen
app keeps its settings apart from Safari's, so turn it on in the app itself.

With it on:

- **The next song is got ready while this one plays.** A few seconds into each song, the player
  downloads the whole of the next one into the phone's memory and loads it into a second audio
  player, which is kept silent. When the song ends, the second player starts straight away and
  the two swap places, so the next song is ready in turn. **Next** uses the ready song too.
- **Memory is capped.** Files up to 64 MB are downloaded ahead, which covers about ten minutes of
  CD-quality FLAC. Bigger files (most hi-res FLAC) and transcoded songs aren't downloaded ahead:
  the second player is given the song's address and buffers what Safari lets it.
- **Not on AirPlay.** While the sound is going to an AirPlay speaker nothing is got ready, and
  every song change goes the ordinary way. Once AirPlay stops, the next song is got ready again.
- **The music doesn't stop because of it.** If the next song can't be handed over when this one
  ends (nothing got ready, a song that wouldn't load, AirPlay in use, or iOS refusing to start the
  second player), that change goes the ordinary way, exactly as with the switch off. A song that
  won't play from memory is asked for from Navidrome straight away. The usual rules for songs
  that won't play still apply after that: one more try, then skip.
- **A download that hasn't finished is streamed instead.** If this song ends before the next one
  has finished downloading (a short song, a slow connection), the download is dropped and the
  second player streams the song from its address, which takes as long as the ordinary way.
- **It uses more data.** Each next song is downloaded in full, even if you skip it. **On a slow
  connection** it can use more still and not help at all: when a whole song can't download while
  the one before plays, every download is dropped part-way and the song streamed afresh, so part
  of every song is sent twice, for a change no quicker than with the switch off. If the readout
  keeps saying `download unfinished`, turn the switch off.
- **Turning it off** takes effect at once: whichever player is playing carries on alone, and the
  other lets go of what it was holding.

### The readout

Between the cover and the song's title, the player shows how long the last few song changes took,
newest first, and how the change was made. It's timed with the switch off as well, the same way,
so you can compare the two. (It sits above the title, not under the controls, because it grows
and shrinks as it fills in: under the controls, that moved the bar and the buttons at the moment
you went to tap them. Up there, only the cover moves.)

A change is timed from the moment one song ended to the moment the next one's **sound started**:
when the player's clock for the new song is first seen moving. It isn't timed to the moment the
browser says the song is playing, because Safari says that as soon as it's asked to play a song
it has data for, before any sound comes out. A second player that claims to be ready but has lost
what it buffered would read as a few milliseconds that way; timed on the clock, it reads as the
silence it really is.

| it says | meaning |
| --- | --- |
| `one element` | the switch is off: the ordinary way |
| `handed over, from memory` | the second player started a song held in memory |
| `handed over, streamed` | the second player started a song it had buffered from its address |
| `handed over, streamed (download unfinished)` | the next song hadn't finished downloading, so the second player streamed it instead |
| `…, had to load` | the second player didn't have enough of the song to start at once, so it loaded first: iOS may have thrown away what it had buffered |
| `…, failed before playing` | the new song failed before it made a sound, and the time includes asking for it again (or skipping it) |
| `one element (airplay)` | the switch is on but the change went the ordinary way; also `nothing ready`, `failed to get ready`, `another song ready`, `refused` |

Only songs ending by themselves are timed, and only when the next one went straight to sound.
Changes you make yourself (**Next**, **Previous**, a new song, moving the scrubber, pressing play)
aren't timed, and neither is a change where the music stopped: a pause, iOS stopping for a call or
Siri, iOS refusing to start the next song, or a song that wouldn't play at the end of the queue.
Anything longer than 30 seconds isn't counted either. The readout is hidden with the phone on its
side, to leave room for the cover. If it says the switch isn't helping,
[troubleshooting](troubleshooting.md#with-gapless-on-theres-still-a-pause-between-songs-or-the-player-reloads-by-itself)
says what each answer means.

### What still needs trying on a real iPhone

In a desktop browser (Chromium) it works. Timed on the clock as above, a song change took about
145 ms with the switch off, or about 270 ms with 150 ms added to every answer from Navidrome to
stand in for a VPN; with the switch on it took about 98 ms either way. Much of those 98 ms is the
browser starting its sound output at all, which every device does at its own speed, so what to
look at on the phone is the difference between the switch on and off, not either number alone.
On an iPhone, song changes have read 94 and 96 ms. The parts that matter only an iPhone can
answer. To try it:

1. Turn **Gapless** off, play an album from a tap, and let a few songs change with the screen on,
   to see what the ordinary way takes on your phone and connection. Then turn it on and let a
   few more change. The readout should say `handed over, from memory`, with numbers well below
   the ones before.
2. **Lock the phone** and let at least ten songs change by themselves. Then unlock and open the
   now-playing screen. The readout lists the last five: `from memory` with numbers like those with
   the screen on means it works locked. `had to load`, or numbers as big as the switch-off ones
   or bigger, mean iOS threw away what the second player had buffered, or held back the
   download. `download unfinished` means the download couldn't keep up.
3. While locked, check that the **lock screen** shows the right song and a playing state after
   each change, and that previous, next and the scrubber still work.
4. Try it in Safari as well as in the home-screen app.
5. Play an album of big files (hi-res FLAC) for a while. If the app **reloads by itself**, that's
   iOS taking memory back; say so, and turn the switch off.
6. Try **AirPlay** with the switch on (the readout should say `one element (airplay)`, and the
   AirPlay button should stay put as songs change), and a phone call or Siri during a song change
   (that change shouldn't be timed at all).

Even when it works, it isn't sample-exact: the second player still has to start, so an album
mixed straight through (a live album, a DJ mix) may keep a tiny gap. Closing that completely
would take a different kind of player.

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

**The readout shows it on your phone.** Between the cover and the song's title, below the gapless
readout, the player shows the last seek you made, with the bar or from the lock screen: *Last
seek: asked 2:10, seeking…* while it's on its way, then *Last seek: asked 2:10, the player said
2:10*. If it never got there, because you pressed Previous or Next first or the song failed under
it, the line says *Last seek: asked 2:10, interrupted*. It ends with how the song playing was sent,
in Safari:

| it ends | meaning |
| --- | --- |
| `· FLAC in MP4` | the song came inside an MP4: seeks should land where you put them |
| `· sent as FLAC, not in an MP4` | deadwax sent the FLAC as it is (see above); seeks may land off |
| `· asked for FLAC in MP4` | for a moment, while the player checks what came |

In other browsers it ends with nothing, since they get every file as it is, and so it does in
Safari for a song that isn't a FLAC (an MP3's seeks can still land off; see above). The line
shows it before any seek too: *No seek yet · FLAC in MP4*.

Safari says the time asked for wherever it lands, so "the player said" can't tell you where a seek
really went, but the end of the song can: if the seek landed off, the song runs out before its
clock reaches the end, or plays on after its clock has stopped at the end, by the same amount. If
the song plays to its end with no other seek or pause, the line adds what that showed:

| it adds | meaning |
| --- | --- |
| `the song ended on time, so it landed there` | the seek landed where you put it (to within about a second and a half) |
| `the song ran out 7 s before its clock did, so it really landed at about 2:17` | it landed 7 seconds later in the song than asked |
| `the song played on 7 s after its clock ended, so it really landed at about 2:03` | it landed 7 seconds earlier |

It's hidden with the phone on its side, like the gapless readout. To try it on the iPhone, play a
FLAC and check the line ends `· FLAC in MP4`; then pick a song with a quiet opening and a loud
middle, seek well into the loud part near the end, and let it finish. It should say `the song ended
on time`. [Troubleshooting](troubleshooting.md#a-song-seeks-to-the-wrong-place) says more.

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
- Plays go to the `NAVIDROME_USER` account, and on to Last.fm or ListenBrainz if that account
  has them linked in Navidrome.
- A play that can't be reported doesn't interrupt the music, and nothing on the phone says so.
  If plays aren't turning up, see [troubleshooting](troubleshooting.md#plays-dont-show-up-in-navidrome).

## Formats, and Navidrome's Players page

**Files are sent as they are** whenever the phone says it can play them, which on an iPhone
should cover FLAC, MP3, AAC and ALAC. That's the only kind of file Navidrome can send in pieces (byte ranges), which is
what Safari needs to start a song quickly and to skip around in it. The one change is that Safari
gets a FLAC inside an MP4 of the same audio, so that its seeks land
([Seeking](#seeking-and-where-safari-lands)); that's sent in pieces too.

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

## Using it away from home

There's no login in deadwax, so don't open a port to the internet for it. Reach it over a VPN
instead, such as **WireGuard** or **Tailscale**, and open `/player/` at deadwax's address on that
network. Only deadwax needs to be reachable: the phone never talks to Navidrome.

Behind a reverse proxy that rewrites the `Host` header, the player's plays look to deadwax like
requests from another website, and are refused. [`TRUSTED_ORIGINS`](configuration.md#the-container)
fixes that.

## Known gaps

- **Gapless playback**: there's a short gap between songs, unless you try the
  [experimental Gapless switch](#gapless-playback-experimental).
- **CarPlay**: not something a web page can offer.
- **Offline**: nothing is kept on the phone for listening without a connection.
- **Search**: there isn't any yet. Browse the grid.
- **The queue doesn't survive iOS closing the app.** Reopen it after iOS has cleared it from
  memory and nothing is queued.
- **Siri**, and a lower bit rate for mobile data.
- **The rest of deadwax**: searching MusicBrainz and downloading are on the main page, which
  also works on a phone.
- **On its side**, the now-playing screen shrinks the cover to fit above the controls, which
  leaves it small. There's no landscape layout with the cover beside the controls yet.
- **A saved link to an album can stop working** after you re-apply its release in the metadata
  editor, since Navidrome may give it a new id. The page says Navidrome has nothing by that id;
  go back to the grid and open it again.

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
- how Safari handles a **transcoded** song, and which Ogg files it says it can play;
- whether a song that won't load is **asked for again with the phone locked**: the second try
  comes a moment later, with nothing playing meanwhile, which is exactly when iOS may be holding
  the page back;
- **whether seeks land in the MP4s on the phone**: FLAC was seen landing 3 and 8 seconds out on an
  iPhone, and the MP4s landing exactly was measured on a Mac's Safari engine only (see
  [Seeking](#seeking-and-where-safari-lands)); and how long a song's first play waits there;
- whether the scrubber takes a tap and a drag under a real finger, which a desktop browser can only
  stand in for.
