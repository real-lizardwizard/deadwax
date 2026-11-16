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
- `phase4-library.md` - playlists, artists, songs (Phase 4, app 0.10), designed 2026-11-13 against 2.1.15 / ios b4cf8e0
  (app 0.9): the words (the web's lib/playlists.ts, and the phone's own for offline), whose playlists are (Navidrome's,
  as the asker), the list and its groups, a playlist's page, playing one (each song with its own album, at the songs
  level, the albums Info knows as the web's lib/playedAlbums.ts keeps them), Add to a playlist, New, Edit and Delete,
  Download a playlist with its own origin `playlist:<id>` kept in step by two reads, the artists and an artist's page,
  every song paged, the Library's Shuffle and its feed; no server addition; five slices (the first built), tests,
  James's checks (64 on) and 8 open questions.
- `phase5-search.md` - Search (Phase 5, app 0.11), designed 2026-11-14 against 2.1.23 / ios 3458122 (app 0.10): the
  words (the web's lib/searchList.ts, searchQuery.ts and searchResults.ts, and the phone's own for offline), the box's
  reading, whose a row is, the sections, Top results (tier, source, kind, position; the family; the rounds), the lines,
  what is asked and when, the list drawn once per text and frozen, a song playing in its tap, the album you don't have
  with room for Get; no server addition for slice 1 (a Cover Art Archive relay recommended before slice 2); four slices
  (the first built), tests, James's checks (121 on) and 13 open questions.
- `phase6-get-requests.md` - Get and Requests (Phase 6, app 0.11 and 0.12), designed 2026-11-14 against 2.1.25 / ios
  3fc9a17 (app 0.11): the Requests board and its four headings, Get on the album you don't have, the store's word on a
  pressing, the Sources sheet and its reasoning, the download asked for, Join and Add to my library, Pick the best
  source for me and You's Getting albums; three slices, tests, James's checks (166 on) and its open questions.
- `phase7-managing.md` - Managing (Phase 7, the plan's last, app 0.13), designed 2026-11-15 against 2.1.26 / ios
  8f2d52f (app 0.12): You > Manage's rows, each by the web's permission rule and opening the web app's own address for
  it in Safari (`/player/#/you/...`; the editors, which have no address, by the Library and an album's ••• "Edit in the
  web app"), Account's Change password, Set up Navidrome on Server settings, Safari's own sign-in in a listener's
  words, plain http and ATS, offline, Dynamic Type and VoiceOver; no server addition; James's checks (237-246) and 11
  open questions, each built with its recommendation.
- `phase8-managing.md` - managing on the phone (Phase 8), designed 2026-11-16 at ios c571580, overruling Phase 7's
  "opened in the web app": James asked that nothing in the app take you to the web app. Where managing opens from
  (an album's •••, the artist page's •••, Settings > Manage, Account), every tool the web has - the album editor
  (the folder, its issues, Release, tags by hand, artwork and lyrics, Delete), the artist tools, Needs a look,
  Library care, Server settings and Connections, the event log, Change password, People - with its routes, payloads,
  permission and the rules ported to Core; two server changes on main (A: the library scan without its tracks, B:
  the artist-picture relay) and the web refactors the exporters need; 12 slices in order, editing albums first;
  James's checks (320-391); four decisions, all answered as recommended on 16 Nov.
