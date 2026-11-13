# deadwax for iPhone

The native iPhone app: a SwiftUI app over the `DeadwaxKit` Swift package (its `DeadwaxCore` logic,
tested on Linux, its `DeadwaxAudio` engine and its `DeadwaxTurntable` drawing), built on a Mac with
Xcode and a free Apple account. It is early: app 0.7 - Phase 1's player (your library, album pages,
Up Next, Now Playing, normalization on the phone, the lock screen, plays and picking up where you
left off), Phase 2's albums and songs downloaded to play offline, lyrics on Now Playing, the EQ (ten
sliders, nine presets and AutoEq's corrections, kept per output) and the turntable on Now Playing (a
record you can scrub by hand, heard as you turn it, and its speed fader, 0.25x to 2x) - kept on the
`ios` branch while it's being built. Nothing of Phase 2, the lyrics, the EQ or the turntable has been
seen on an iPhone yet.
Phase 0's test screen lives on in the app's Debug.

- **To install it, and every week after:** [docs/ios.md](../docs/ios.md) - the steps once on the Mac
  and the iPhone, the weekly `ios/scripts/install.sh`, the test album
  (`ios/scripts/make-test-album.py`), what the app does, and the checks: Phase 1's, and Phase 2's twenty.
- **How it is built, and why:** [notes/ios.md](../notes/ios.md).
- **Before pushing a change here, on Linux:** `ios/scripts/check-linux.sh`. GitHub's `ios.yml` compiles
  the rest on macOS.
