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
- `eq.md` - the EQ (James's decisions of 2026-11-12, ~/Desktop/Code/deadwax-plans/eq.md), designed 2026-11-12
  against 2.1.6 / ios b03ac65: one in-process unit between the main mixer and the output, the RBJ filters in Core in
  Double, Off passing every sample through untouched (and how that is measured), crossfaded changes, the curve put in
  at the engine's start on a new route, the deck and the fader beside it; the automatic preamp; AutoEq through
  deadwax (two routes, a 2.1.x on main); the screen (the output, the curve as an audio graph, Correction, the ten
  sliders, presets, Advanced's filters, handles and preamp, import from Files, Paste and the share sheet with every
  refusal's words, GraphicEQ converted, export), per output naming and switching, storage per phone, five slices,
  James's checks and open questions. Reviewed the same day against Equalizer APO's own source and AutoEq's data
  (its "Design review (2026-11-12)": every form APO plays is played, its reading rules as its code has them, the
  unit's block size and allocation, no denormal flush, the bank copied in and matched by id, the crossfade measured,
  the list's path encoding, "pick yours" when several rows match, a pushed page kept on its output).
- `phase3-autodownload.md` - auto-download your library (Phase 3, app 0.9), designed 2026-11-13 against 2.1.15 / ios
  305f6a8 (app 0.8): the words, your library followed on the phone (the `library` table), when it is checked and what
  a check does (a 304 ending it, removals only after two checks 10 minutes apart agree, an empty list, a large drop
  or a truncated list held back), each album's songs read, the order (the later of the star and a play within 30
  days), the fill to the limit (whole albums, hand downloads first and never given way, the phone's 2 GB), origin
  `library` beside Phase 2's, Only while charging, BGAppRefreshTask and BGProcessingTask; You > Downloads' section,
  the first ask, Downloading's one row, the album page, Debug; no server addition (the `album_songs` route named, built
  only if the first read is slow); three slices, tests, James's checks (L0a-L0g, 50-63) and 16 open questions.
