# The iPhone app's design specs

Each phase of the iPhone app (ios/, notes/ios.md) is designed before it is built: one spec per area, read from
the web app as it is (its screens, words and rules, file by file), the server's routes, the plan and Apple's own
patterns. The app is then built to the spec and reviewed against it. notes/ios.md's sections cite them by name
("screens.md 7" is section 7 of phase1/screens.md).

- `phase1/` - the player (app 0.2), scouted 2026-11-10 against 2.1.0: screens.md (the shell, sign-in, the album
  page, the queue menu, the mini player, Now Playing, You), library.md, upnext.md, levels.md (normalization),
  resume.md, plays-words.md (plays and the words), engine.md (the audio engine). Their line numbers are the
  web's at 2.1.0, kept as written; the code has moved on since.
- `phase2-downloads.md` - Downloads (app 0.3), designed 2026-11-12 against 2.1.3 / app 0.2 (b4ee591): the words
  and marks (Apple Music's arrow, ring and downloaded mark), a song's and an album's state, the album page's
  control, rows and menus, Now Playing's Download and Download Up Next, the Library's Downloaded, You > Downloads
  (the two settings, what's used, downloading, didn't download, Remove All), offline (how the app knows, the
  banner, opening with no network, plays and queue saves kept), the machinery (the store, the background session,
  the checks, the planner), tests, James's checks and open questions. No server addition; its line numbers are
  the code's at b4ee591. Reviewed the same day against Phase 1's screens and Apple's patterns (a second commit:
  the hero's line on its own, Download over drawn as Normalization is, the banner under each page's bar, the
  Library never swapping under a finger, the Navidrome gate and a gone album with music on the phone, Info's
  Plays from).
- `turntable.md` - the turntable and the speed fader (James's decision of 2026-11-12, overruling choice 22),
  designed 2026-11-12 against 2.1.4 / ios 944d787: the screen (the look switch, the plinth, the face, the arm,
  120 Hz drawing, the close drag, every state and word, VoiceOver, Dynamic Type, Reduce Motion, the Palette), the
  deck's rules and the press ported, the clock, the handover timed by the engine's start, the voice ported line
  for line on a second engine, the window from the phone's own file with `/scrub` behind it, the audio session,
  the fader's engine change and what is measured first, the four slices with their fixtures and tests, James's
  checks and open questions. Reviewed the same day (its "Design review (2026-11-12)": the clock anchored on the
  block's end, the handover's predictor, target and judge, the window's grid and its two tests, the porting and
  real-time rules, the press and the deck's owner, the lock screen after a wind-down, the look's faces and type).
