# deadwax for iPhone

The native iPhone app: a SwiftUI app over the `DeadwaxKit` Swift package (its `DeadwaxCore` logic,
tested on Linux, and its `DeadwaxAudio` engine), built on a Mac with Xcode and a free Apple account.
It is early: Phase 0, a test screen that proves the install, the connection and the audio engine.

- **To install it, and every week after:** [docs/ios.md](../docs/ios.md) - the steps once on the Mac
  and the iPhone, the weekly `ios/scripts/install.sh`, the test album
  (`ios/scripts/make-test-album.py`) and Phase 0's eight checks.
- **How it is built, and why:** [notes/ios.md](../notes/ios.md).
- **Before pushing a change here, on Linux:** `ios/scripts/check-linux.sh`. GitHub's `ios.yml` compiles
  the rest on macOS.
