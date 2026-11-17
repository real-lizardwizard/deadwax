# deadwax for iPhone

The native iPhone app: a SwiftUI app over the `DeadwaxKit` Swift package (its `DeadwaxCore` logic,
tested on Linux, its `DeadwaxAudio` engine and its `DeadwaxTurntable` drawing), built on a Mac with
Xcode and a free Apple account. It is early: app 0.13 - Phase 1's player (your library, album pages,
Up Next, Now Playing, normalization on the phone, the lock screen, plays and picking up where you
left off), Phase 2's albums and songs downloaded to play offline, lyrics on Now Playing, the EQ (ten
sliders, nine presets and AutoEq's corrections, kept per output) and the turntable on Now Playing (a
record you can scrub by hand, heard as you turn it, and its speed fader, 0.25x to 2x), and play history
in Up Next (every song you played, here and on the web, scrolled up past the song playing), and
Phase 3's library downloaded by itself, as much as fits - only while charging if you like, and in the
background when iOS allows - and Phase 4's Library: your playlists read and played, made, added
to, edited, deleted and downloaded, the Library's switch between its pages (Albums, Playlists and
Artists - and Songs with logins off; with them on, every song is under All music > All songs - in an
order you choose, a pull down shuffling your library), artists and their pages, and
every song, a page at a time - and Phase 5's Search: your library and MusicBrainz searched as the web
app's Search searches them, one list with Top results, a song playing from its tap, the albums, artists
and songs you don't have yet after yours (an album opening its pressings and their tracklists, an artist
their albums), what deadwax has saved of MusicBrainz's answers drawn at once, and More from MusicBrainz a
page at a time - and Phase 6's Requests: every download you asked for under the web app's four headings, cancelled,
tried again and cleared on the phone, a finished album opened or played from its row, the tab's badge counting
what's on its way - and Get: an album you don't have got from its page, the store's word on the pressing under
the button, Soulseek's sources in a sheet with each one's reasoning, the one picked in Requests from the tap, or
picked for you with Pick the best source for me; a download somebody else asked for joined, a pressing in the
collection added to your library, and When I tap Get, Quality floor and Format chosen on the phone - and
Phase 7's Manage: the list of the managing tools you may use (editing an album, Needs a look, Library care,
People, Server settings and the event log) and Change password, each first opened in the web app in Safari - and
Phase 8, bringing them into the app one at a time, begun with Edit album: an album's folder, what's wrong with it,
and the release it's matched to, chosen and applied on the phone, then its tags, on one track or many, then its
artwork and lyrics, with Get cover, Get CD art and Get lyrics, then its Delete, what goes read first and asked
once more, then the artist tools from an artist page's •••: Artist images (every picture found, through deadwax's
relay), Which artist is this? and Move albums to their name now, then Needs a look: the review queue, its count
beside it in Settings > Manage, each album worked through in Edit album with Skip and Next album, then Library care:
Rescan, and Get covers, CD art and lyrics over every album without, one album at a time, with In nobody's library,
then Server settings: Connections, the server's settings a group to a page and saved together, Re-time saved lyrics
and MusicBrainz's saved answers, and the Library's Set up Navidrome opening its Connections page, then the event
log: the lines deadwax kept and each new one live, newest first, Copy on a long press and Clear for the phone's view,
then Change password: your Navidrome password changed on the phone, this phone kept signed in under the new sign-in
deadwax gives it while every other sign-in of yours ends, then People: Navidrome's accounts looked after on the
phone, unlocked with your own Navidrome password - a person added, their password reset, made admin or not, removed
with their name typed, each person's permissions ticked and saved, and Forget for what deadwax still keeps for
someone gone from Navidrome -
and last, no way out to the web app left at all: the app's only links out are to MusicBrainz, AutoEq on GitHub and
the Sharing deadwax guide, and a test keeps it so -
and Add to Queue, the phone's one way to add
songs: a swipe right on a song, or the one item on every •••, each song after the ones already added (the web app's
Play Last; the web keeps Play Next too) - kept on the `ios` branch while it's being built. Nothing of Phase 2, the
lyrics, the EQ, the turntable, play history, Phase 3, Phase 4, Search, Requests, Get, Manage, Edit album, the artist
tools, Needs a look, Library care, Server settings, the event log, Change password, People or Add to Queue's swipe
has been seen on an iPhone yet.
Phase 0's test screen lives on in the app's Debug.

- **To install it, and every week after:** [docs/ios.md](../docs/ios.md) - the steps once on the Mac
  and the iPhone, the weekly `ios/scripts/install.sh`, the test album
  (`ios/scripts/make-test-album.py`), what the app does, and the checks, phase by phase - Phase 7's are 237-246,
  Edit album's 320-329, its Tags' 330-334, its Artwork and Lyrics' 335-337, its Delete's 338-342, the artist
  tools' 343-348, Needs a look's 349-354, Library care's 355-360, Server settings' 361-369, the event log's 370-373,
  Change password's 374-378, People's 379-387, no way out to the web app's 388-391, Add to Queue's 392-403.
- **How it is built, and why:** [notes/ios.md](../notes/ios.md).
- **Before pushing a change here, on Linux:** `ios/scripts/check-linux.sh`. GitHub's `ios.yml` compiles
  the rest on macOS.
