# deadwax for iPhone

The native iPhone app: a SwiftUI app over the `DeadwaxKit` Swift package (its `DeadwaxCore` logic,
tested on Linux, its `DeadwaxAudio` engine and its `DeadwaxTurntable` drawing), built on a Mac with
Xcode and a free Apple account. It is early: app 0.12 - Phase 1's player (your library, album pages,
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
collection added to your library, and You's When I tap Get, Quality floor and Format chosen on the phone - kept
on the `ios` branch while it's being built. Nothing of Phase 2, the lyrics, the EQ, the turntable, play history,
Phase 3, Phase 4, Search, Requests or Get has been seen on an iPhone yet.
Phase 0's test screen lives on in the app's Debug.

- **To install it, and every week after:** [docs/ios.md](../docs/ios.md) - the steps once on the Mac
  and the iPhone, the weekly `ios/scripts/install.sh`, the test album
  (`ios/scripts/make-test-album.py`), what the app does, and the checks: Phase 1's, and Phase 2's twenty.
- **How it is built, and why:** [notes/ios.md](../notes/ios.md).
- **Before pushing a change here, on Linux:** `ios/scripts/check-linux.sh`. GitHub's `ios.yml` compiles
  the rest on macOS.
