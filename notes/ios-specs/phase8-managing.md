# Phase 8 - Managing natively: every managing tool in the app, none in the web app

Design spec for the iPhone app's Phase 8, read 2026-11-16 at `ios` c571580 (app 0.13 (13), server 2.1.26). Area: every
managing tool the web app has, rebuilt natively: the album editor (Release, Tags, Artwork, Lyrics, Delete), the artist
page's tools, Needs a look, Library care, Server settings (with Connections), the event log, People and Change password
- and, last, the removal of every way out of the app to the web app. Every path is repo-relative and every line number
  is
the code's at c571580. No Swift is written here.

**What binds it.** James, 2026-11-16: "can we also get all the management stuff on the app? like editing albums, etc? so
nothing in the app should take you to the web app". Asked which first, he chose **editing albums**. And, of the Settings
tab being reorganised beside this: "with maybe some better organization, and maybe some dropdowns instead of big lists".
This **overrules** the plan's Choice 17 ("Rebuilding them natively is a choice for later, one at a time if ever") and
Phase 7's question 1 (`phase7-managing.md:226`, Safari through `openURL`): Phase 7's rows were the bridge, and each goes
as its native page lands. The plan's offline rule still holds (section 4 of the plan: "managing say[s] it needs deadwax,
and show[s] nothing stale as if live"), as do every standing rule and settled decision in CLAUDE.md - above all **every
writer is plan/execute and every apply recomputes its plan**, **deleting carries every guard and a real dialog: there is
no undo**, and **bulk runs are driven from the client, one album at a time**.

**Beside it.** Another session is turning You into **Settings**, laid out as iOS Settings: a root list of groups, each
pushing a page, choices as menu Pickers. Its **Manage** group holds Edit an album, Needs a look, Library care, People,
Server settings and Event log - still Phase 7's Safari rows (`WebAppRow`) when it lands. Its checks are 310-319; this
phase's start at **320**. This spec names that group "Settings > Manage" and changes its rows one slice at a time.

**Where the rules come from.** The web app as it is: `ui/src/app/EditPanel.tsx`, `ui/src/components/MetadataEditor.tsx`,
`TrackTagEditor.tsx`, `DeleteAlbumDialog.tsx`, `LibraryParts.tsx`, `SettingsView.tsx`, `RetimeLyrics.tsx`;
`ui/src/app/ArtistPanel.tsx`, `NeedsALook.tsx`, `LibraryCare.tsx`, `HeldByNobody.tsx`, `ServerSettings.tsx`,
`EventLog.tsx`, `People.tsx` (with `UnlockPeople`, `AddPerson`, `ResetPassword`, `RemovePerson`, `usePeople`),
`ChangePassword.tsx`, `You.tsx` (Connections); their pure rules in `ui/src/lib/` (`albumEdit.ts`, `release.ts`,
`tagEdit.ts`, `getResults.ts`, `metadataQueue.ts`, `needsLook.ts`, `bulkTargets.ts`, `libraryCare.ts`,
`artistManage.ts`, `serverSettings.ts`, `eventLog.ts`, `people.ts`, `ownPassword.ts`, `permissions.ts`, `myLibrary.ts`);
the routes in `src/routes/` (section 0's table); `notes/app-desktop.md` (the Edit panel, Needs a look, Server settings
and the log, Library care), `notes/fixes-1.0.md` (the two-step apply), `notes/logins.md` ("Managing accounts", "Changing
your own password"), `notes/library.md` (the editors, CD art, lyrics, the folder template). Held to the TypeScript by
committed exporters, as every port since Phase 1 (`notes/ios.md` "How the ports are kept in step with the web", line
840).

## 0. The foundation - checked

- **The branch.** `worktree-agent-a4d596d0f93cb45e1`, reset to `ios` c571580, clean. `src/__init__.py` says `2.1.26`;
  `ios/Config/Base.xcconfig:11-12` say 0.13 and 13. Each slice installed takes the next build after the Settings
  reorganisation's, pinned with check_project.py, ios.yml, tests/test_ios_install.py, ios/README.md and docs/ios.md as
  0.3 to 0.13 were. `__version__` is never changed on `ios`; the server changes below go on `main` as 2.1.x patches and
  are merged into `ios`.
- **Every route a managing tool needs already exists** but two (section 12), and each is decided in
  `tests/test_logins.py` ROUTES (lines 90-238). The phone may call any of them: the router is checked by
  `current_user`/`require(permission)`, never by who is asking.

  | route | file:line | needs |
  | --- | --- | --- |
  | `GET /deadwax/library/albums?snapshot=` (the scan, ETag, headers) | `src/routes/library.py:303` | user |
  | `POST /deadwax/library/rescan` | `library.py:398` | library |
  | `GET /deadwax/library/art?album=`, `/disc_art?album=&file=`, `/tracks?album=`, `/tracks/picture?album=&file=&index=` | `:455`, `:1159`, `:504`, `:1130` | user |
  | `POST /library/retag/preview`, `/retag/apply` (`RetagRequest`, `:559`) | `:568`, `:602` | edit |
  | `POST /library/art/fetch` (`CoverArtRequest`, `:975`), `/lyrics/fetch` (`LyricsRequest`, `:1050`), `/disc_art/fetch` (`DiscArtRequest`, `:1273`) | `:986`, `:1062`, `:1278` | edit |
  | `POST /library/tags/preview`, `/tags/apply` (`TagEditRequest`, `:1345`) | `:1351`, `:1373` | edit |
  | `GET /library/queue/summary`; `POST /queue/ignore`, `/unignore`, `/reviewed` (`QueueRequest`, `:1425`) | `:1454`, `:1517`, `:1542`, `:1554` | library |
  | `GET /library/deletion_summary?album=`; `POST /library/delete` (`DeleteRequest`, `:1573`) | `:1624`, `:1578` | library |
  | `GET /library/artist?name=`, `/artist/art?artist=&kind=` | `:1770`, `:1799` | user |
  | `POST /library/artist/images/preview`, `/apply` (`ArtistImagesRequest`, `:1679`), `/artist/search` | `:1829`, `:1907`, `:2064` | edit |
  | `POST /library/artist/refile/preview`, `/apply` (`ArtistRefileRequest`, `:1983`) | `:2017`, `:2027` | library |
  | `GET /deadwax/library/held`; `POST /held/flags/{flag_id}/add`, `/dismiss` | `src/routes/held.py:51`, `:61`, `:89` | library |
  | `GET /deadwax/search_musicbrainz/releases?release_group_mbid=&tracks=`, `/release?release_mbid=` | `src/routes/search_musicbrainz.py:294`, `:390` | user |
  | `GET`/`PUT /deadwax/settings`; `GET /settings/musicbrainz_cache`, `POST /musicbrainz_cache/clear` | `src/routes/settings.py:847`, `:1383`, `:1520`, `:1530` | server |
  | `GET /deadwax/interface_logs/recent`, `/interface_logs/interface_logs?after=&boot=` (SSE) | `src/routes/interface_logs.py:13`, `:41` | server |
  | `GET /deadwax/people`; `POST` `/unlock`, `/lock`, `/create`, `/{person_id}/password`, `/admin`, `/remove`, `/forget`, `/{person_id}/permissions` | `src/routes/people.py:294`, `:360`, `:392`, `:415`, `:458`, `:495`, `:546`, `:583`, `:607` | people |
  | `POST /deadwax/me/password` | `src/routes/own_password.py:203` | user (signed in) |
  | `GET /deadwax/search_musicbrainz/ping`, `/deadwax/monitor_slskd/ping` (Connections) | ROUTES `:116-117` | user |

- **The same-origin guard needs nothing.** `src/api/same_origin.py` lets a write with neither Origin nor Referer
  through; `DeadwaxClient.request` (`DeadwaxClient.swift:64-72`) sets only Accept, Cookie and Content-Type, which is how
  every write the phone makes today (Get, playlists, plays, queue saves) passes.
- **Permissions are mostly ported.** Core's `Managing.parts` (`Managing.swift:40`) and `albumEdit` (`:63`) are the web's
  `managing` and `albumEdit` (`permissions.ts`), replayed by `ManagingVectorTests`; `Access.seesDetail`
  (`Access.swift:60`) is `access.ts seesDetail`. Three more of `permissions.ts` are ported beside them, into the same
  exporter: `careParts` (`:127`: rescan and held library's, the runs edit's), `artistManaging` (`:156`: images and Which
  artist edit's, Move library's) and `asksQueueSummary` (`:168`, library). The pages gate by these and nothing else: the
  editors by `albumEdit.editors` (edit), Delete by `albumEdit.delete` (library), Needs a look by `parts.queue`, Library
  care by `parts.care` and its parts by `careParts`, the artist tools by `artistManaging`, Server settings and the log
  by `parts.settings`/`.log` (server), People by `parts.people` (people, logins on). The server refuses for itself (403)
  whatever the phone shows, so a row shown a moment too long (a permission taken away since /me last answered) only
  reaches a refusal said in words (section 2).
- **What Phase 7 left that this phase replaces** (each removed by the slice that brings its native page, the machinery
  by slice 12): Settings > Manage's six `WebAppRow`s (today `ios/App/You/ManageSection.swift:17-45`, the row `:67-107`,
  the `openURL.webApp` extension `:47-59`); the album page's ••• "Edit in the web app" (`QueueMenu.swift:107-118`, set
  by `AlbumView.swift:257-265` through `QueueMenuRequest.webEdit`, `QueueMenu.swift:22`); Account's Change password
  (`AccountSection.swift:24-27`); the Library gate's Set up Navidrome (`LibraryView.swift:622`,
  `NavidromeGate.setUpURL`, `NavidromeGate.swift:85-87`); Core's addresses and Safari words (`Managing.swift:100-152`,
  `ManagingWords` `:155-212`). Two links out remain and are not the web app: Album info's MusicBrainz links
  (`AlbumInfoView.swift:286-300`) and the EQ's GitHub link (`EQProfileScreen.swift:91`); People's "Sharing deadwax"
  (`people.ts:30`, a GitHub page) joins them.
- **The phone already reads half of what the editor needs**: the id bridge (`Routes.storeAlbum`, `/deadwax/store/album`,
  `src/routes/store_album.py:274`, its `present[].path`), an album's files (`Routes.libraryTracks` → `AlbumFiles`,
  `AlbumInfo.swift:109`, though `AlbumFile` declares only `disc`, `tags` and `raw` - slice 2 adds `filename`, `format`,
  `size`, `length`, `position`, `pictures`), MusicBrainz's search (`Routes.fullySearch`), the Cover Art Archive relay
  (`Routes.archiveCover`, `release`/`release-group`, 250/500/1200), the release payload (`GetRelease.swift`, which ports
  `releasePayload.ts` - but see 3.3: the editor's payload is a different function), `/library/owned` (`OwnedIndex`,
  `ArtistJoin.everyOwned`).
- **ROUTE_COUNT is 61** (`tests/test_ios_contract.py:124`). Each slice's new Endpoints raise it (section 13).

## 1. Where managing opens from

| entry | shown when | opens |
| --- | --- | --- |
| album page's bar ••• → **Edit album** (last section, after Album info; `square.and.pencil`) | `albumEdit.shown`, online, not gone | the editor, a sheet (section 3) |
| Settings > Manage > **Edit an album** | `albumEdit.shown` | **Choose the folder** (3.1), then the editor for that folder - the one way to a folder Navidrome doesn't list outside Needs a look |
| Settings > Manage > **Needs a look** (its count trailing) | `parts.queue` | a pushed page (section 5); a row opens the editor in queue mode |
| Settings > Manage > **Library care** | `parts.care` | a pushed page (section 6) |
| Settings > Manage > **People** | `parts.people` | a pushed page (section 10) |
| Settings > Manage > **Server settings** | `parts.settings` | a pushed page (section 7), Connections at its top |
| Settings > Manage > **Event log** | `parts.log` | a pushed page (section 8) |
| artist page's bar ••• → **Artist images…**, **Which artist is this?**, **Move albums to {name}…** | by `artistManaging` and the web's own conditions (section 4) | a sheet each |
| Settings > Account > **Change password** | `Managing.changeOffered(me)` | a pushed form (section 9) |
| the Library's Navidrome gate → **Set up Navidrome** | as now (`closed.setUp`) | Server settings > Connections, natively, in a sheet |

The words are the web's: "Edit album" is the panel's title (`EditPanel.tsx:789`), the tabs' labels are `EDIT_TABS`
(`albumEdit.ts:61-67`), Manage's labels are `permissions.ts LABELS`' and You's rows'. Menu items and rows are in the
app's sentence case, as "Album info" and "Edit in the web app" already are.

## 2. What every managing page does

- **It needs deadwax, and shows nothing stale as live.** Opened while `Reachability.online` is false: a
  `ContentUnavailableView` with the phone's own "Managing needs deadwax. This opens once it's back." and nothing asked.
  Going out of reach while open: what is drawn stays, under a banner (the phone's own, beneath the bar as the offline
  banner is), "deadwax is out of reach - this is how it was, and nothing here can change until it's back.", with every
  control that writes off. Back in reach, the page asks everything again before a control comes back on - never a write
  against an answer from before the gap. Typed work (an editor's fields, Server settings' drafts) is the person's own
  and is kept through the gap. Nothing managing is kept on disk: no cache, no snapshot, no offline copy.
- **Only the newest answer draws** (`lib/latest.ts`): each ask takes the next number and a late answer for an older one
  is dropped, as `AlbumModel.swift:16` does already. Previews debounce **400 ms** as the web's (`MetadataEditor.tsx:553`
  on, `TrackTagEditor.tsx:106`), and Apply is off while a preview is on its way or the release's tracklist loads.
- **Preview before every write, and the plan is never sent.** Every writer is plan/execute: the phone draws the
  preview's answer and sends the same request to apply, and the route recomputes. Apply is enabled only by a current
  preview that has something to change and no problem.
- **No undo, so Delete is the only dialog** (3.6), with Cancel the default button; Remove a person asks for the typed
  name (as `RemovePerson.tsx`). Applies are not dialogs: the preview on the same page is the safety net, as on the web.
- **Typed work isn't lost by a swipe.** A sheet with an unapplied edit has `interactiveDismissDisabled`, and its Close
  asks "Discard changes?" with Discard destructive (the web's backdrop tap closes nothing, `EditPanel.tsx`). Pushed
  Server settings pages keep drafts in a model (`ServerSettingsModel`) that outlives the page, as the web keeps them in
  its module (`ServerSettings.tsx:29`, `kept`), until saved, discarded or the app is quit.
- **Errors.** A refusal deadwax wrote words for - a route's `detail` (and People's and Change password's `kind` and
  `fix`, `people.py:109`) - is shown as it came, as the web's managing pages show it (CLAUDE.md: "The managing pages ...
  still show raw words"). Everything else - nothing answered, a timeout, a 5xx with no words, an answer the app can't
  read - goes through Core's `ErrorWords.notice` (`ErrorWords.swift:204`) with `admin: access.seesDetail`, as the web's
  `sayError` does, the transport's own text only in the brackets for whoever runs deadwax. A 403 is `NO_PERMISSION`
  (`permissions.ts:60`), People's `PEOPLE_ONLY` (`:63`). Core's `APIFailure` reads `detail`, `why` and `kind` but not
  `fix` (`APIFailure.swift:199-218`): slice 10 adds it.
- **A long write that never answers may still have happened.** An apply holds its answer (3.3: up to 300 s and more);
  the server's handler carries on when the phone goes (no `@app.middleware("http")`, CLAUDE.md). So an apply whose
  answer never came - the phone locked, WireGuard dropped - is said as "deadwax may have finished this - looking again"
  (the phone's own), and the page reads the folder again rather than offering Apply on the old preview. Each write
  route's timeout is held above the server's own bound by the contract test (section 13).
- **Plain http.** Nothing here needs a secure context: `SecureField` works over any address, and the stream (section 8)
  is a plain GET. The web's `httpNote(protocol)` (`people.ts:223`) is said under every password field (Unlock, Add a
  person, Reset, Change password) when the server's address is `http:` - the phone knows its scheme
  (`ServerAddress.base`).
- **After a write**, the editor re-reads its folder (the scan, 3.1), the album page underneath does its own Refresh
  (`QueueMenuRequest.refresh`), Settings asks `/library/queue/summary` again (section 5), and the Library's album index
  is asked on its next show. Nothing optimistic: what's drawn is what deadwax said.
- **Dynamic Type and VoiceOver**: every page is a `List`/`Form` of system rows, so the largest sizes wrap rather than
  truncate; a row's state (a mark, a count, "Unsaved") is in its accessibility label; progress is announced
  (`AccessibilityNotification.Announcement`) once per step, not per percent.

## 3. The album editor

### 3.1 Opening it, and finding the folder

The web finds the album's folder from the id bridge, then the scan (`EditPanel.tsx`, `albumEdit.ts:133-154`
`editFolders`): the store's `present` paths; else the scan's folders of the release (`answer.release_mbid` or
Navidrome's `musicBrainzId`); else untagged scan folders with the album's folded name and artist, narrowed by
`songCount`. Several by name alone is a choice (`needsChoice`, `:187`); several of one release start on the first, the
others a choice away. None: `editStatus` (`:243`) says why, with **Choose the folder** and **Look again**. From Needs a
look (or Choose the folder) it is that folder alone (`folderOnly`, `:156`).

That needs the scan's albums, which the phone has never read: the web's `/library/albums` carries every track of every
album (`compact_for_wire`, `src/library.py:1384`: "Measured on 1,060 albums: 4.3 MB" before compaction, still most of
the body after), twice per visit (snapshot, then the real one). The phone asks **`GET
/deadwax/library/albums?tracks=false`**
- server change A (section 12): the same answer, ETag and headers, each album's `tracks` and `track_defaults` left out.
Every field the editor reads of an album is album-level (`LibraryAlbum`, `ui/src/api/types.ts:720-790`: `path`,
`artist`, `album`, `year`, `original_year`, `edition`, `release_mbid`, `art`, `art_mtime`, `track_count`, `disc_count`,
`disc_art`, `lyrics_count`, `issues`, `ignored_issues`, `imported`, `reviewed`, ...), and the answer still has
`issue_types` and `queue`. The whole list, not a one-folder route, because several fields are worked out across the
whole scan (`edition_count`, `split_discs`, `disc_label`) and `editFolders`, `folderChoices`, Needs a look and Library
care all read the list. Kept in memory per page with its ETag (a 304 is the common answer), never on disk.

**Choose the folder** (Settings > Manage > Edit an album, and the editor's not-found state): a pushed `List` with
`.searchable`, the scan's folders by `folderChoices(albums, typed)` (`:166`, the first `FOLDER_CHOICES_SHOWN` = 50),
`folderChoicesWords` (`:178`) over them, each row the folder's cover (`/library/art`), album, artist and path. A tap
opens the editor for that folder.

### 3.2 The editor's root

A sheet (`.large`, its own `NavigationStack`), titled "Edit album", **Close** at the leading edge (2: asks about typed
work), drawn as iOS Settings is - a header and sections of rows, each row pushing a page. Five tabs don't fit a phone's
segmented control, and each is a long form; a list of pages is the "better organization" James asked for.

- **Header**: the folder's cover (`/library/art?album=`, cached in memory by path and `art_mtime`), album, artist ·
  edition, formats and track count, and the folder's path under it (caption, selectable).
- **Folder** (several folders): a menu `Picker` of the paths; while `needsChoice`, it is the only section until a folder
  is picked ("Which folder is this album?" over it, the phone's own).
- **Needs a look** (the album has outstanding issues or ones marked fine): each issue's label and hint
  (`metadataQueue.ts` `outstandingIssues`, `issueLabel`, `:22`, `:81`); **It's fine as it is** (`POST queue/ignore` with
  exactly the issues shown, `QueueRequest`'s note); "Marked fine: …" with **Ask about it again** (`queue/unignore`).
  Shown only with Look after the library - the route's permission. The web offers them with Edit albums alone
  (`MetadataEditor.tsx:1006-1016`, `EditPanel.tsx:588-602` check nothing) and gets a 403: decision 2.
- **Edit** (Edit albums - `albumEdit.editors`): **Release** (its value the current release, `describeRelease`, or "Not
  matched to a release"), **Tags** ("12 tracks"), **Artwork** ("Cover, CD art" / "No cover"), **Lyrics** ("8 of 12").
- **Delete album…** (Look after the library - `albumEdit.delete`), destructive, in a section of its own at the end.
- **Queue mode** (opened from Needs a look): the bottom toolbar holds ‹, "2 of 9" and **Skip ›** / **Next album ›**
  (`MetadataEditor.tsx` queue nav), stepping by `stepTarget` (section 5).
- **States** without an album: `editStatus`'s words ("Finding the album's folder…" with a `ProgressView`; "deadwax can't
  find this album's folder: …" with **Choose the folder** and **Look again**; "Deleted X.").

### 3.3 Release (slice 1)

The web's MetadataEditor, split over three pages. Its rules: `release.ts` (`fieldedAlbumQuery`, `plainAlbumQuery`,
`scoreReleaseGroupMatch`, `scoreReleaseMatch`, `isCurrentRelease`, `describeRelease`, `releaseTrackCount`,
`buildRetagRelease` `:217`, `flattenTracks` `:169`, `currentName`), the search (`MetadataEditor.tsx:388-480`), the
payload (`:516-552`), the preview words (`:960-1000`, `discWords` `:1123`, `applyingLabel` `:1132`).

- **Release** (pushed from the root), a `Form`:
  - **Release**: the chosen pressing as a row (title, `describeRelease`, year · `releaseTrackCount` tracks, "Current"
    when `isCurrentRelease`) pushing **Choose a release**; or "Choose a release" alone.
  - **Fields**: Artist, Album, Year, Original year (placeholder: the year), Edition (placeholder: the preview's
    `edition_label` or "worked out from the release", `MetadataEditor.tsx:854`). Years with the number pad. Picking a
    release seeds them as the web does (`:338-355`: the artist by the credit's current name, Edition left blank); the
    current release loaded at open seeds nothing (`:462`).
  - **Cover**: a `Toggle` "Save the release's cover" (`fetch_art`, on by default only when the folder has no art, as the
    web's checkbox), and **Compare covers…** (a release chosen) pushing the comparison: the folder's cover beside the
    release's through the relay (`/deadwax/coverart/release/{mbid}?size=500`; a tap opens it full screen at 1200, the
    phone's "The cover, full screen", `notes/ios.md` 10406) - never the Archive directly - with **Replace cover only**
    (`POST art/fetch` `{album_path, replace: true, release_mbid}`, the web's "Replace cover only"/"Save cover only").
  - **What Apply does**: the preview (`POST retag/preview`), drawn from the web's words - its problems; the folder move
    or merge ("Folder: … → …"); the rename-wait sentence (`rename_wait`, `rename_by`: "navidrome" waits for its scan, at
    most `SCAN_WAIT_CAP_SECONDS` = 90; "timer" a fixed `RETAG_RENAME_WAIT`); "N of M files would change" (`:993`)
    pushing **Changes** (each file's tag changes, old → new) - or "Nothing to change." (`:967`).
  - **Apply**, a prominent button under it; while it runs, `applyingLabel` ("Applying, waiting for Navidrome" /
    "Applying, renaming in Ns") and nothing on the sheet can close it. After, the web's applied sentence (`:596-610`),
    the folder read again, the album followed (3.7).
- **Choose a release** (pushed), a `List` with `.searchable` (empty: the fielded query, placeholder `plainAlbumQuery`):
  `fullySearch(query || fielded, 25, releases: false)`, the loose fallback when the fielded finds nothing, the groups
  ranked by `scoreReleaseGroupMatch` against the **fields**, the top `GROUPS_SEARCHED` = 3 groups' pressings
  (`/search_musicbrainz/releases?tracks=false`), all sorted by `scoreReleaseMatch` - a flat list of pressings, as the
  web's ("an edition IS a release"). Each row: title, artist, `describeRelease`, year, track count, "Current". A tap
  loads the pressing's tracklist (`/search_musicbrainz/release`, a spinner on the row), seeds the fields and goes back.
  While MusicBrainz is away: the web's "MusicBrainz is unreachable right now, so there's nothing to match against. You
  can still correct the fields by hand." (`:470`).
- **The payload is `buildRetagRelease`, not `GetRelease.payload`.** They look alike and differ: the editor's track
  credit is `entry['artist-credit'] ?? recording's` and `creditName(credit) || null` (`release.ts:191-198`), the
  download's `||` and `credited(credit)` - "N/A" for an empty credit (`releasePayload.ts:93-101`); the editor's country
  `?? release.country ?? null`, the download's `||` (`release.ts:246`, `releasePayload.ts:132`); the download sends
  `album_artist`, the editor none (`library.py:538-541`). So Core gets its own `Retag.release(_:context:)` with its own
  vectors; whether the differences are meant is a question for the web, not this phase (reported).
- **The wait.** `retag/apply` answers after the pause: up to `RENAME_WAIT_RANGE`'s 300 s on the timer
  (`src/config.py:1105`), 90 s waiting on Navidrome (`scan_wait.py:53`), plus the cover fetch
  (`coverart_endpoint.py:86`, 45 s read) - so its timeout is 420 s, held above those by the contract test. It is one
  apply per folder at a time on the server (`_apply_lock`, `library.py:631`). While it runs the phone holds a background
  task (`beginBackgroundTask`) for the seconds iOS gives; past them, section 2's "may have finished".

### 3.4 Tags (slice 2)

The web's TagsList, TrackInspector and TrackTagEditor (`EditPanel.tsx:971-1060`, `TrackTagEditor.tsx`), rules
`tagEdit.ts` (`EDIT_FIELDS` `:29`, `sharedValue` `:51`, `buildEdits` `:64`, `tagProblem` `:85`).

- **Tags** (pushed): the folder's files from `/library/tracks?album=` (read from the disk as asked, its 30 s timeout
  already), a section per disc when there are several (`trackLabel`), each row "3 · Title" with its artist when it
  differs. **Select** (the bar's `EditButton`) turns on multi-select; the bottom toolbar says **Edit 3 tracks…** or
  **Edit all tracks…** (the web's words). A tap outside Select pushes the **track's page**: its tags as named rows,
  every raw tag (`raw`), its audio (format, length, bitrate, sample rate, bits, channels, codec), its embedded pictures
  (each a row; a tap shows it, `/library/tracks/picture`), and **Edit tags…** for that one track.
- **Edit tags** (pushed, a `Form`): the eleven `EDIT_FIELDS` in four sections (the phone's own grouping; the web's order
  within each): **Track** (Title, Artist, Track number), **Album** (Album, Album artist, Disc number, Disc subtitle),
  **Dates** (Date, Original date), **More** (Genre, Composer). Each field starts at `sharedValue`; under it the web's
  notes - "Several values", "Will be removed", "Differs between tracks - left alone, each keeps its own", "Not tagged -
  reads as disc 1" (`TrackTagEditor.tsx:334-341`) - and a trailing **Undo** once edited. `tagProblem` refuses as typed
  (numbers, dates, control characters, 1000 characters). Below, the preview (`POST tags/preview`, only `buildEdits`'
  edited fields sent, `null` to remove) with each file's change, then **Apply** (`tags/apply`). Not shift-click ranges
  (`tickTracks`): Select is the phone's way.

### 3.5 Artwork and lyrics (slice 3)

The web's ArtworkTab and LyricsTab (`EditPanel.tsx`), `LibraryParts.tsx` (`GetArtButton`, `GetDiscArtButton`,
`GetLyricsButton`), `getResults.ts` (`GETTING`, `GET_FAILED`, `getProblem`, `lyricsResult`).

- **Artwork**: **Cover** - the folder's cover (a tap: full screen), or "No cover"; **Get cover** when there is none and
  the album has a release (`art/fetch`, `replace: false`; a 404 says there is none and offers **Look again**); to
  replace one, the web's pointer to the Release page's comparison, here a row pushing it. **CD art** - its pictures in a
  grid (`/library/disc_art?album=&file=` for each of the scan's `disc_art`), **Get CD art** when there is a release and
  no `disc*` of deadwax's own (`hasOwnDiscArt`), "deadwax never replaces CD art it saved." under it.
- **Lyrics**: "8 of 12 tracks have lyrics", **Get lyrics** while `lyrics_count < track_count` (`lyrics/fetch`, `replace:
  false`), `lyricsResult` after; the web's pointer to re-timing, here a row to Server settings > Lyrics when the person
  has Settings and the log, else words.

### 3.6 Delete (slice 4)

The web's DeleteAlbumDialog: the summary read live (`/library/deletion_summary`: audio files, total size, the other
files by name, and with logins on who else holds it - `holdersText`, `myLibrary.ts:148`; `holders_unknown` never read as
"nobody"), then "This deletes the folder and everything in it, permanently. There is no undo." with Cancel and **Delete
permanently**; Escape cancels, Enter never confirms.

On the phone: **Delete album…** pushes **Delete album**, a page with the summary as rows and the web's sentence, then
**Delete permanently** (destructive) - which raises a `confirmationDialog` ("Delete *Album*? There is no undo.", the
phone's own) whose Cancel is the default. Two steps where the web has one: decision 3. After it: the sheet closes; when
`deletesAll` (`albumEdit.ts:195`) the album page goes back; the Library's index is asked again. An album downloaded on
this phone keeps playing from its files, as a gone album does today (Phase 2).

### 3.7 After a write: following the album

An applied release can move the folder and re-key the album in Navidrome. The web settles `EDIT_SETTLE_MS` (10 s), then
looks for Navidrome's album of the new release at `FOLLOW_LOOKS_MS` [0, 3000, 6000, 12000, 24000] through the bridge
(`followRelease`, `followsTo`, `noteMove`, `movedTo`, `albumEdit.ts:279-300`). The phone ports the same and, found,
replaces the album page's route under the sheet with the new id; not found, it stays and says nothing new. Downloads of
the old id are not moved (section 16).

## 4. The artist tools (slice 5)

The web's ArtistPanel (`ArtistPanel.tsx`: modes images, refile, who) from the artist page (`ArtistPage.tsx:848` on),
rules `artistManage.ts` (`libraryNames` `:55`, `namesToMove` `:74`, `imagesFolder` `:138`, `toggleChoice`, `byKind`,
`slotLine`, `imageNotes`, `savedLine`, `matchLine`, `refileView`, `canMove` `:335`, `moveLine` `:340`, `moveButton`
`:345`, `refileAfter`, `refileOutcome`). They act on the **library's names** for the artist (`libraryNames` over
`/library/owned`, which the phone reads already), not Navidrome's.

- **Where**: the artist page gets a bar ••• (it has none, `ArtistView.swift:102-110`) holding, by `artistManaging`:
  **Artist images…** (edit; under "In your library" on the web), **Which artist is this?** (edit; no MusicBrainz id),
  **Move albums to {name}…** (library; their albums filed under more than one name). Each opens a sheet.
- **Artist images**: `POST artist/images/preview {artist, artist_mbid}` → a section per kind (`kinds`' labels) with the
  chosen picture large and **Use another picture (N)** pushing that kind's candidates as a grid; a `Toggle` "Replace
  pictures that are already there"; what's in the folder now (`/library/artist/art`); `imageNotes` and the problems (no
  key: "a fanart.tv or TheAudioDB key would add banners and logos"); **Save** → `artist/images/apply` with the choices
  (each must be a URL the sources offered - `library.py:1684`), then `savedLine`. **The pictures are on other hosts**
  (Commons' `Special:FilePath`, fanart.tv, TheAudioDB - `candidate.preview`, `artist_images_endpoint.py:226`), and the
  phone talks only to deadwax: server change B, decision 1.
- **Which artist is this?**: a search field (`POST artist/search {query}`), the matches with `matchLine`, a pick re-asks
  the preview with that `artist_mbid`.
- **Move albums**: `artist/refile/preview` for each of `namesToMove`, drawn as `refileView` (each album that moves, with
  `moveLine` "2 tracks, 2 retagged", and the problems); **Move N albums** (`moveButton`, enabled by `canMove`) applies
  each name in turn, then `refileOutcome`/`refileAfter` (stayed, emptied). The artist page reloads; it is the eighth
  writer, plan/execute like the rest.

## 5. Needs a look (slice 6)

The web's NeedsALook (`NeedsALook.tsx`), rules `needsLook.ts` (`summaryTotal` `:64`, `facets` `:73`, `facetAlbums`,
`facetShown`, `isIgnoredOnly`, `startSession` `:145`, `markFor` `:161`, `rowChanged` `:181`, `stepTarget` `:214`,
`leavingAtEnd` `:224`, `MARK_WORDS`, `NEEDS_LOOK_LINE`, `ignoresUnsaved`, `navidromeNote`, `needsLookLabel` `:284`) and
`metadataQueue.ts` (`queueAlbums` `:63`, `isNewImport` `:45`).

- **The count** on Settings > Manage > Needs a look, trailing as a Settings value: `/library/queue/summary`'s `total`
  (`library.py:1454`, "The count the app's queue page lists, BY CONSTRUCTION", from the saved scan alone), asked as
  Settings shows, on a pull, on the foreground and after every write anywhere in managing - only with `asksQueueSummary`
  (library). Nothing while it isn't known; VoiceOver hears `needsLookLabel` ("Needs a look, 3 albums"). Not on the tab:
  decision 4.
- **The page**: `NEEDS_LOOK_LINE` at its top; **Show** - a menu `Picker` in the bar holding `facets` ("All 12", "Newly
  added 3", one per issue, "Ignored 4") where the web has a row of chips; the albums of that facet as rows (cover,
  album, artist · edition, the issues' labels, "New", and after a session the row's mark: Fixed, Ignored, Deleted); the
  `navidromeNote` and `ignoresUnsaved` notes when they apply. A tap starts a session (`startSession`) and opens the
  editor in queue mode on that folder (`folderOnly`); each write updates the session (`rowChanged`); stepping and
  closing mark the album left reviewed (`stepTarget`'s `leaving`, `leavingAtEnd` → `POST queue/reviewed`). Without Edit
  albums the editor's Edit section is gone and the page says `NEEDS_EDIT` ("Fixing it needs Edit albums, which an admin
  hasn't given you.").

## 6. Library care (slice 7)

The web's LibraryCare and HeldByNobody, rules `libraryCare.ts` (`narrowAlbums` `:36`, `scopeLine`, `planWords` `:65`,
`BULK_LABELS` `:87`, `BULK_TITLES`, `scanTotals` `:102`, `scanAge` `:110`, `careLine` `:129`, `RESCAN_WORDS` `:139`),
`bulkTargets.ts` (`BULK_KINDS`, `bulkTargets`, `startRun`, `addOutcome`, `runBulk`, `bulkSummary`), `useLibraryCare.ts`
(the run kept beyond the page).

- **Rescan** (library): `scanTotals` and `scanAge` over it, `RESCAN_WORDS` under it, **Rescan** (`POST
  /library/rescan?tracks=false`, server change A; no bound on the server, so 300 s and section 2's "may have finished").
- **Fill in** (edit): **Narrow to** (a search field, `narrowAlbums`, `scopeLine`); a row per kind (covers, CD art,
  lyrics) with `planWords` ("N albums have no cover") and **Start**; a running one shows "Stop after this album · N of
  M" with **Stop**, and once done `bulkSummary`. One album at a time from the phone (`runBulk`), as the settled decision
  says. The run lives in a model held by the app, so leaving the page doesn't stop it; while its page is in front the
  screen stays on (`isIdleTimerDisabled`); if the app is suspended mid-run, it stops after the album out and says where
  ("Stopped at 14 of 60 when the app went to the background - Start carries on.", the phone's own) - and Start does,
  since `bulkTargets` asks again which albums still lack one.
- **Held by nobody** (library, logins on): a row pushing the page - `GET /library/held` (the albums nobody holds, and
  the downloads flagged for a look), each flag with **Add to their libraries** (`flags/{id}/add`) and **Put away**
  (`flags/{id}/dismiss`).
- A person with one of the two sees only their part, `careLine` saying so.

## 7. Server settings and Connections (slice 8)

The web's ServerSettings and SettingsView: `GET /deadwax/settings` → `{groups: [{id, label, note, settings: [{key,
value, source, choices, editable, locked_reason, secret, overridden, env_value, status, effect, detail}]}], organizing:
{enabled, blockers}}`; `PUT` of a batch `[{key, value}]` (`null` reverts to the environment), a 400's `detail` said as
it came. Rules: `serverSettings.ts` (`SERVER_TABS` `:13`, `draftsAfterSave` `:31`) and `SettingsView.tsx`'s pure parts
(`tabForGroup` `:23`, `tabMarks` `:35`, `retypeSecretNote` `:78`, `editedEnvDraft` `:147`), `RetimeLyrics.tsx`,
`MusicBrainzAnswers.tsx`.

- **The root** (pushed from Manage): **Connections** first (below); `OrganizingVerdict` (on, or the blockers); then the
  web's three tabs as sections - **Library** (Paths, Organizing, Cover art, Lyrics), **Downloads** (Soulseek searches,
  When a download fails), **Connections** (Connections, MusicBrainz's saved answers, Logins) - by `tabForGroup`, a group
  the phone doesn't know under Library as the web puts it. Each group is a row pushing its page, marked "Needs
  attention" (a setting's `status` error, or organizing blocked) or "Unsaved" by the web's `tabMarks` rule taken per
  group.
- **A group's page** (a `Form`): the group's `note`, then a row per setting - a menu `Picker` where it has `choices`
  (the dropdowns James asked for: today the country, the cover's size, lyrics and the automatic retry -
  `COUNTRY_CHOICES`, `COVER_ART_SIZE_CHOICES`, `LYRICS_CHOICES`, `AUTO_RETRY_CHOICES`, `settings.py:612-763`), a
  `SecureField` for a secret ("•••••••• (set)" as its placeholder, never its value), a `TextField` otherwise (no
  autocorrection or capitals; URL keyboard for an address); its footer the source ("Set here" / "From the environment"),
  `effect`/`detail`/`status` words, "Locked" with `locked_reason`, **Revert to the environment (X)** when `overridden`,
  and `retypeSecretNote` beside an address changed without its secret.
- **One save**: drafts live in `ServerSettingsModel` across every group's page. While any exist, every Server settings
  page has a bottom toolbar - "2 unsaved changes", **Discard**, **Save** - which PUTs all of them at once; after the
  answer `draftsAfterSave` keeps what changed meanwhile, "Saved." is said, and the app re-asks Navidrome's status (the
  web's `onServerSettingsSaved`). The rows stay editable while a save is out, as the web's.
- **Lyrics** carries **Re-time saved lyrics** (`RetimeLyrics.tsx`: refused while the lead has an unsaved change; one
  album at a time through `lyrics/fetch {retime: true}`; kept beyond the page like a care run; Stop). **MusicBrainz's
  saved answers** shows the size (`/settings/musicbrainz_cache`) and **Clear** behind a `confirmationDialog`
  (`musicbrainz_cache/clear`).
- **Connections** at the top (seesDetail - which everyone with Server settings has): the web's three rows from You
  (`You.tsx:42-67`, `:336-365`) - MusicBrainz and slskd by their pings, Navidrome by `/deadwax/navidrome/status`, which
  the phone reads already - each "Connected" or `pingWords` (`ErrorWords.swift:404`, ported) with its line, and **Check
  again**. This settles Phase 7's question 6 (`phase7-managing.md:241`) natively.
- **Set up Navidrome** (the Library's gate, `LibraryView.swift:622`) opens a sheet with Server settings' Connections
  group page; saved, the gate asks again (`onServerSettingsSaved`). `NavidromeGate.setUpURL` goes.

## 8. The event log (slice 9)

The web's EventLog, rules `eventLog.ts` (`LOG_KEPT` 500 `:23`, `joinLine` `:42`, `joinHistory` `:67` with its gap,
`clearLog` `:79`, `EMPTY_WORDS`, `levelOf` `:88`, `lineTime`, `STREAM_RETRY_MS` 5000 `:107`, `STREAM_WORDS` `:109`:
"Connecting…", "Live", "Lost the live feed - reconnecting…").

- **The page**: the web's line ("What deadwax has said since it started - the last 500 lines - newest first. Clear
  empties this view only."), the stream's state under the bar, then the lines newest first: time, level (errors in the
  system red, warnings amber), words; a long press offers **Copy** (the phone's own - the web has none). **Clear** in
  the bar (the view only).
- **How it's read**: `/interface_logs/recent` once (`{lines, last, boot}`), then the stream `GET
  /interface_logs/interface_logs?after=<last>&boot=<boot>` (SSE: ":" at once, the missed lines, `data: {json}` per line,
  a keepalive every 15 s; uncompressed by CompressText). The phone has no streaming transport (`HTTPTransport.send`
  returns a whole answer, `HTTP.swift:61-62`): the slice adds an App-side `lines(for:)` on `URLSession.bytes(for:)` with
  the session's cookie and cookies off as every session has (`URLSessionTransport.swift:34-35`), and a pure Core reader
  of SSE frames. Lost: "Lost the live feed - reconnecting…", again after `STREAM_RETRY_MS` from the last line held. The
  stream stops when the page goes or the app leaves the foreground, and starts from the last line on return. Polling
  `/recent` instead was weighed and not chosen: 500 lines a poll, and never live.

## 9. Change password (slice 10)

The web's ChangePassword (`ChangePassword.tsx`), rules `ownPassword.ts` (`CHANGE_TITLE` `:13`, `SAME_PASSWORD`,
`APPS_LINE` "Amperfy and any other app you use with Navidrome need the new password too.", `changeOffered` `:29`,
`changeLine`, `formProblem` `:39`, `formReady`, `doneWords` `:53`) and `people.ts`' password rules (`PASSWORD_MIN` 8,
`PASSWORD_MAX` 128, `passwordProblem`).

- Settings > Account > **Change password** pushes a `Form`: Current password, New password, New password again
  (`SecureField`s, `.textContentType(.password)` and `.newPassword`), `formProblem` as typed, `httpNote`, `APPS_LINE`,
  **Change** enabled by `formReady`. `POST /deadwax/me/password {current, password, password_again}` - a strict model
  (`own_password.py:107`, extra fields are a 422), at most `CHANGES_PER_MINUTE` = 5 (`:65`). Refusals as they came
  (`NOT_YOUR_PASSWORD`, `EDITING_OFF`, `WRONG_CURRENT`...).
- **The answer re-keys this phone.** A change ends every other session and moves this one under a new id, its cookie set
  on the answer (`own_password.py:292-308`, `_set_cookie`). The phone must read that `Set-Cookie`
  (`SessionCookie.value(fromSetCookie:)`, as `signIn` does, `DeadwaxClient.swift:157`), keep it in the Keychain
  (`SessionKeychain.save`) and hand the client the new session at once - or its next call is a 401 and it signs itself
  out. Downloads out at the moment carry the old cookie; the download store's rule already waits after a 401 "until the
  client changes" (`DownloadModel.swift:184`) - check 377 watches it.
- After: `doneWords(signed_out)` and the answer's `warning` when there is one.

## 10. People (slice 11)

The web's People (`People.tsx`, `UnlockPeople`, `AddPerson`, `ResetPassword`, `RemovePerson`, `usePeople`), rules
`people.ts` (names `NAME_PATTERN` `:10`, `nameProblem`, `displayProblem`, `passwordProblem`, `formProblem`, `formReady`;
`chips` `:86`, `signInWords`, `libraryWords`, `librariesWarning`, `actions` `:136`, `refusals`, `removeReady` `:150`,
`makeAdminWords`, `unmakeAdminWords`, `removeLines`, `knownWords`, `madeWords`, `resetWords`, `versionNote`,
`peopleView` `:240`; words `UNLOCK_TITLE`, `unlockLine`, `UNLOCKED_LINE`, `HTTP_NOTE`, `KNOWN_ONLY_TITLE`,
`KNOWN_ONLY_LINE`) and `permissions.ts` (`LABELS`, `LINES`, `checkboxes`, `lockedReason`, `changed`, `savedWords`).
Every write is made in Navidrome **as the signed-in admin**, with their own password, unlocked for `UNLOCK_IDLE_SECONDS`
= 900 (`navidrome_admin.py:63`), at most `WRITES_PER_MINUTE` = 10 (`people.py:59`); every body is strict (`_Strict`,
`people.py:113`).

- **The page** by `peopleView`: asking (a spinner); unavailable (`problem` and `fix`, `NEEDS_LOGINS` and the like);
  locked - **Unlock People**: `unlockLine(you)`, a `SecureField`, `httpNote`, **Unlock** (`POST /unlock {password}`;
  `NOT_YOUR_PASSWORD` is a 409, the sign-in throttle applies); the list - `UNLOCKED_LINE` and **Lock** in the bar, **+**
  (Add a person), **Everyone in Navidrome** (you first: name, `chips` as a trailing line - You, Admin, deadwax's account
  - and `signInWords` · `libraryWords`, `librariesWarning`), then **Known only to deadwax** (`KNOWN_ONLY_LINE`, each
  `knownWords`, **Forget…** behind a `confirmationDialog`, `POST /forget {user}`). A refusal of `kind` "locked" (the
  unlock ran out) brings the unlock back, as the web's.
- **A person** (pushed): **Permissions** - five `Toggle`s by `checkboxes` (Get albums, Edit albums, Look after the
  library, Everyone's downloads, Settings and the log; `lockedReason` as the footer for an admin, you, deadwax's
  account), **Save** (`POST /{id}/permissions` with all five - a missing one is a 422 by design, `people.py:153`),
  `savedWords`; **Reset password…** (a sheet: two `SecureField`s, `passwordProblem`, `resetWords(user, signed_out)`);
  **Make admin** / **No longer admin** (`actions`' labels) behind a `confirmationDialog` with
  `makeAdminWords`/`unmakeAdminWords`; **Remove…** (a sheet: `removeLines`, a field to type the name, **Remove**
  destructive and enabled by `removeReady`, `{user, confirm}`). Which of them appear is `actions(person)` from the
  server's `can`; refused ones say `refusals(person)` ("That's you - change your own password in You → Account → Change
  password.", `src/people.py:48`).
- **Add a person** (a sheet): user name, display name, two passwords, `formProblem` as typed, `httpNote`; `POST
  /create`; `madeWords` and the answer's `warning`.

## 11. No way out to the web app (slice 12)

Each slice switches its own entry to native as it lands, so no build has two ways to one tool: slice 1 the album's •••
and Manage's Edit an album; 6 Needs a look; 7 Library care; 8 Server settings and Set up Navidrome; 9 Event log; 10
Account's Change password; 11 People. Slice 12 removes what is left: `WebAppRow`, the `openURL.webApp` extension (and
its pause of the player), `QueueMenuRequest.webEdit`, Core's `Managing.appPath`/`fragment`/`albumFragment`/
`youFragment`/`url`/`albumURL`/`youURL`/`notice` and `ManagingWords`' Safari words (`editLine`, `editInWebApp`,
`changePasswordLine`, `opensInSafari`, `opens`, `signIn`, `offline`, `notOpened`, `footer`, `outSymbol`,
`safariSymbol`), the address half of `export-managing-vectors.cjs` and its fixture, `ScreenGateTests`' setUpURL tests
(`ScreenGateTests.swift:98-103`), and docs/ios.md's Safari sign-in text. A test then reads every App source and refuses
an `openURL` or `Link(` outside an allowlist of three (Album info's MusicBrainz, the EQ's GitHub, People's Sharing
deadwax) - the rule "nothing takes you to the web app" kept by CI, not by memory.

## 12. The server, and the web

**Server change A (main, 2.1.27, before slice 1): the scan without its tracks.** `GET /deadwax/library/albums` and `POST
/deadwax/library/rescan` take `tracks: bool = True`; false leaves each album's `tracks` and `track_defaults` out of the
wire body (`_library_response`, `library.py:289`, skipping `compact_for_wire` for the album dict less
`ALBUM_SERVER_ONLY_FIELDS`). Everything else is the same: the scan, the queue decoration, `issue_types`, the headers
(`_SCAN_HEADERS`, `:285`), the ETag (of the body, so the two forms never share one), the snapshot. The default is
unchanged, so the web is untouched. Tests beside the albums route's (tests/test_library_cache.py, tests/test_logins.py's
ROUTES unchanged): the same body without tracks, a 304 on its own ETag, the snapshot form, rescan's. docs: none (no
user-facing change). Considered and not chosen: the full scan on the phone (MBs per visit, twice), and a one-folder
route (the fields worked out across the scan, and three tools read the list anyway).

**Server change B (main, a 2.1.x before slice 5): the artist pictures' previews, through deadwax** (decision 1). A `GET
/deadwax/library/artist/picture?url=` (edit, like the preview that names them), modelled on the Cover Art Archive's
relay (`ArchiveFronts`, `coverart_endpoint.py:309`, `ARCHIVE_HOSTS` `:263`): only `https` URLs on the hosts the
candidates' `preview`s are on (Commons, Wikimedia's upload host it redirects to, fanart.tv's and TheAudioDB's image
hosts - read off `artists.py`'s `from_*` and their fixtures in the slice), redirects followed by hand and only within
them, `MAX_IMAGE_BYTES`-style cap (a preview is `PREVIEW_WIDTH` = 600, `artists.py:82`, so a few MB), a deadline, an
image type checked (`served_image_type`), nothing kept on disk. Not a general proxy, and in `tests/test_logins.py`'s
ROUTES. Without it the phone shows the candidates as words only.

**Web refactors (main, no-change patches, each before the slice that ports it).** The exporters run pure TypeScript;
some of what the phone ports lives in components: the Release preview's and apply's words
(`MetadataEditor.tsx:960-1000`, `:596-610`, `discWords` `:1123`, `applyingLabel` `:1132`) → a new `lib/retagPlan.ts`;
the tag fields' notes (`TrackTagEditor.tsx:334-341`) → `tagEdit.ts` `fieldNote`; the Artwork and Lyrics tabs' and
Delete's inline words → `albumEdit.ts`; `SettingsView.tsx`'s `tabForGroup`, `tabMarks`, `retypeSecretNote`,
`editedEnvDraft` → `serverSettings.ts`. Each changes nothing a user can see, says so in its message, bumps the patch as
every main commit does, and the web's sims hold it. Reading them out of the `.tsx` by pattern (as Phase 7 read You.tsx)
was the alternative; a moved function is replayed as it runs, a pattern only as it reads.

Nothing else: no new permission, no change to a writer, no CORS or same-origin change.

## 13. Machinery

- **Core** (pure, tested on Linux), new files by area: `ScanAlbums.swift` (the scan's album without tracks, the answer
  and its headers), `AlbumEdit.swift` (`albumEdit.ts`), `Retag.swift` (`release.ts`'s editor half and `retagPlan.ts`),
  `TagEdit.swift`, `GetResults.swift`, `MetadataQueue.swift` + `NeedsLook.swift`, `LibraryCare.swift` (`libraryCare.ts`,
  `bulkTargets.ts`), `ArtistManage.swift`, `ServerSettings.swift`, `EventLog.swift` + `EventStream.swift` (the SSE
  reader), `OwnPassword.swift`, `People.swift`; `APIFailure` reads `fix`; `AlbumFile` gains its other fields; the models
  of each answer, every field `loose` as the rest of Core decodes.
- **Exporters** (each with its sim running `--check`, its fixture under `Fixtures/<area>/`, sources hashed):
  `export-edit-vectors.cjs` → `iosedit.sim.cjs` (`albumEdit.ts`, `release.ts`, `retagPlan.ts`, `tagEdit.ts`,
  `getResults.ts`, `myLibrary.ts` `holdersText`), `export-care-vectors.cjs` → `ioscare.sim.cjs` (`metadataQueue.ts`,
  `needsLook.ts`, `libraryCare.ts`, `bulkTargets.ts`), `export-artist-manage-vectors.cjs` → `iosartistmanage.sim.cjs`,
  `export-server-vectors.cjs` → `iosserver.sim.cjs` (`serverSettings.ts`, `eventLog.ts`), `export-people-vectors.cjs` →
  `iospeople.sim.cjs` (`people.ts`, `ownPassword.ts`, `permissions.ts`' People parts). Each runs the TypeScript on
  inputs from the plain to the awkward (folded names, a scan with two folders of one release, a credit of none, a facet
  emptied by a write, a setting with choices and a secret, a stream with a gap), and the Swift `*VectorTests` replay
  them. The sims are picked up by CI's glob.
- **Routes** (`Routes.swift`; ROUTE_COUNT from 61): slice 1 +9 (library albums, releases, release, retag preview and
  apply, art fetch, library art, queue ignore and unignore) → 70; 2 +3 (tags preview and apply, track picture) → 73; 3
  +3 (lyrics fetch, disc art fetch, library disc art) → 76; 4 +2 → 78; 5 +8 (library artist, artist art, images preview
  and apply, artist search, refile preview and apply, the picture relay) → 86; 6 +2 (queue summary, reviewed) → 88; 7 +4
  (rescan, held, flag add, dismiss) → 92; 8 +6 (settings get and put, the cache and its clear, the two pings) → 98; 9 +2
  → 100; 10 +1 → 101; 11 +9 → 110.
- **tests/test_ios_contract.py**: every new route the server's with its parameters (as today); every body the phone
  encodes holds only the server model's declared fields (pydantic drops the rest without a word, CLAUDE.md - and
  People's and Change password's strict models 422 on them); each answer decodes from what the route really sends (made
  by the route in the test, as the lyrics and AutoEq tests do); the timeouts above the server's bounds - retag apply
  above `RENAME_WAIT_RANGE[1]` + the cover fetch's read bound, lyrics fetch above LRCLIB's per-track bound times a
  disc's tracks, rescan and the scan generous where the server has none, the artist and refile applies above their
  fetches.
- **App**: `ios/App/Manage/` for the pages (the Settings reorganisation's group links to them), `ios/App/Edit/` for the
  editor sheet and its pages, a model per tool (`@Observable`, held by the app where a run or a draft must outlive the
  page: `CareRunModel`, `ServerSettingsModel`), the streaming transport beside `URLSessionTransport`.

## 14. Slices, in order

Each slice: Core first with its vectors, then the App, then docs/ios.md (the page and its checks) and notes/ios.md (the
write-up), then a review that runs mutations of the slice's Core rules against its vectors (as Phase 7's twelve), then
James's checks. Sizes: S a day's build, M two or three, L more.

1. **A - the scan without its tracks** (server, main 2.1.27; S). Above. Then the web refactors for slice 1 (main).
2. **Slice 1 - Edit album: the folder, what's wrong, Release** (L). Core: `ScanAlbums`, `AlbumEdit`, `Retag` (search,
   ranking, payload, preview words, follow). App: the sheet, Choose the folder, the root, Release, Choose a release,
   Compare covers, Changes; the album's ••• and Manage's Edit an album switched to native. Tests: `EditVectorTests`
   (folders, choices, status, follow; the three queries, both scores, `buildRetagRelease` against `releasePayload`'s
   differences, the preview words), `RetagModelTests` (newest answer, debounce, Apply's guard, the long wait said),
   contract tests for the nine routes. Checks 320-329.
3. **Slice 2 - Tags** (M). Core: `TagEdit` (fields, shared values, edits, problems, notes), `AlbumFile`'s fields. App:
   the track list with Select, the track's page, Edit tags. Checks 330-334.
4. **Slice 3 - Artwork and lyrics** (S-M). Core: `GetResults`, the tabs' words. App: Artwork, Lyrics. Checks 335-337.
5. **Slice 4 - Delete** (S). Core: the summary's words, `holdersText`, `deletesAll`. App: the page and the dialog.
   Checks 338-342.
6. **B - the picture relay** (server, main 2.1.x; S), then **slice 5 - the artist tools** (L). Core: `ArtistManage`.
   App: the artist page's •••, three sheets. Checks 343-348.
7. **Slice 6 - Needs a look** (M). Core: `MetadataQueue`, `NeedsLook`. App: the count, the page, queue mode. Checks
   349-354.
8. **Slice 7 - Library care** (M). Core: `LibraryCare`. App: Rescan, the runs, Held by nobody. Checks 355-360.
9. **Slice 8 - Server settings, Connections, Set up Navidrome** (L; the web refactor before it). Core: `ServerSettings`.
   App: the root, the group pages, the save bar, Re-time, saved answers, Connections, the gate's sheet. Checks 361-369.
10. **Slice 9 - The event log** (S-M). Core: `EventLog`, `EventStream`. App: the page, the streaming transport. Checks
    370-373.
11. **Slice 10 - Change password** (S). Core: `OwnPassword`, `APIFailure.fix`. App: the form, the re-keying. Checks
    374-378. Small and useful to everyone signed in - it can be built earlier without touching the others.
12. **Slice 11 - People** (L). Core: `People`. App: the page, a person, Add, Reset, Remove, Forget. Checks 379-387.
13. **Slice 12 - No way out to the web app** (S). Section 11. Checks 388-391.

## 15. James's checks (320 on)

Use deadwax's plain `http://` address, on the home Wi-Fi and over WireGuard with Wi-Fi off, as an admin unless said.

- **320 Edit album is the app's.** An album's ••• ends with Album info, **Edit album**, Refresh - no Safari. It opens a
  sheet: the cover, name, artist, the folder's path, and Release, Tags, Artwork, Lyrics, Delete album… .
- **321 The folder.** An album kept as one folder per disc shows a Folder menu; Settings > Manage > Edit an album opens
  Choose the folder - type part of a name, pick one, its editor opens.
- **322 What's wrong.** An album in Needs a look shows its issues with their hints; **It's fine as it is** says "Marked
  fine: …" with Ask about it again, which puts it back.
- **323 Choose a release.** Release > the release row: a list of pressings, the album's own first and marked Current.
  Pick another: the fields fill; within a second of typing in a field, What Apply does changes.
- **324 Apply, with Navidrome.** Pick a pressing that renames the folder: the button says "Applying, waiting for
  Navidrome", then what it did. The album page behind shows the new pressing; Navidrome still has its plays and stars.
- **325 Locked mid-apply.** Start an apply that waits and lock the phone at once. Unlock: does it say what it did, or
  that it may have finished and is looking - and never offer the same Apply again?
- **326 Covers.** Compare covers: the two side by side, a tap full screen; Replace cover only replaces it, the album
  page follows.
- **327 Typed work.** Type in a field, swipe the sheet down: it stays; Close asks to discard.
- **328 Out of reach mid-edit.** Wi-Fi and WireGuard off with the editor open: the banner, Apply off, the fields kept.
  Back: it reads again before Apply comes back.
- **329 The largest text, and VoiceOver** across the sheet, Release and Choose a release.
- **330 Tags.** Tags lists the tracks, a section per disc. Select three, **Edit 3 tracks…**: shared fields filled,
  differing ones say so.
- **331 A genre for all.** Edit all tracks, type a genre: each file's change listed; Apply; Navidrome shows it.
- **332 Remove and undo.** Clear a field: "Will be removed"; Undo brings it back.
- **333 Refused as typed.** A date of "2024-13": refused in words, Apply off.
- **334 A track's page.** Tap a track: its tags, its raw tags, its audio and pictures; Edit tags… edits that one.
- **335 A missing cover.** An album with none: Artwork > Get cover; it appears, and on the album page.
- **336 CD art.** Get CD art; the pictures in the grid; a second Get never replaces them.
- **337 Lyrics.** Get lyrics: how many it saved; Now Playing shows them.
- **338 Edit albums alone.** As a person with Edit albums only: no Delete album…, no It's fine as it is.
- **339 What it deletes.** Delete album…: the files, the size, the other files by name, and who else has it.
- **340 Delete.** Delete permanently: the dialog, Cancel bold. Delete: the sheet closes, the album page goes back, the
  Library no longer has it.
- **341 A downloaded album deleted** still plays from the phone, shown as gone.
- **342 Look after the library alone**: Edit album shows only Delete album… .
- **343 The artist's •••.** An artist with albums: Artist images… ; one with no MusicBrainz id: Which artist is this? ;
  one filed under two names: Move albums to … .
- **344 Pictures.** Artist images shows each kind's picture; Use another picture shows the rest; Save; the artist page
  shows it.
- **345 Replace** pictures that are already there.
- **346 Which artist.** Search, pick one: the pictures and facts are that artist's.
- **347 Move albums.** The preview lists each album with its tracks; Move; Navidrome lists them under one name.
- **348 Without the permissions**, no ••• items.
- **349 The count.** Settings > Manage > Needs a look shows a count; VoiceOver says "Needs a look, 3 albums".
- **350 Show.** The menu holds All, Newly added, each kind of issue, Ignored; each narrows the list.
- **351 A session.** Open a row: the editor says "1 of 9", with Skip and Next album. Fix it: back on the list its row
  says Fixed.
- **352 Reviewed.** A newly added album opened and left: the count drops.
- **353 Not in Navidrome.** An album Navidrome doesn't list opens by its folder.
- **354 Edit albums missing**: the page says fixing needs Edit albums.
- **355 Rescan.** The totals and the age; Rescan; the age resets.
- **356 Fill in covers.** Start: "Stop after this album · N of M", the screen stays on; Stop ends it after the album.
- **357 Narrow to** an artist: the counts follow.
- **358 Locked mid-run.** Lock the phone during a run, come back: it says where it stopped; Start carries on.
- **359 Held by nobody** (logins on): albums and flags; Add to their libraries; Put away.
- **360 One part each.** Look after the library alone: Rescan and Held, no runs; Edit albums alone: the runs alone.
- **361 The root.** Connections' three rows; the organizing verdict; the groups under Library, Downloads, Connections.
- **362 A dropdown.** A setting with choices is a menu; change it: "1 unsaved change"; Save: "Saved.".
- **363 Drafts across pages.** Change a setting in two groups, go back and forth: both kept, both saved by one Save.
- **364 A secret.** "•••••••• (set)"; type a new one; Save; it is never shown.
- **365 Address without its secret.** Change Navidrome's address alone: the row says to type the password again; Save is
  refused in words.
- **366 Revert to the environment.**
- **367 Saved answers.** The size; Clear asks first.
- **368 Re-time saved lyrics** runs and stops.
- **369 Set up Navidrome.** With Navidrome unset, the Library's Set up Navidrome opens Connections here; save it: the
  Library fills.
- **370 Live.** The log's lines arrive as a search runs.
- **371 Levels and Copy.** Errors red, warnings amber; a long press copies a line.
- **372 Clear** empties the view only; leave and come back: the lines since.
- **373 Dropped.** WireGuard off and on: "Lost the live feed - reconnecting…", then Live, no line missing.
- **374 The form.** Account > Change password: three fields, the http note, the Amperfy line.
- **375 Wrong current**: said in words; nothing changed.
- **376 Changed.** It says how many devices were signed out; the app plays on, signed in. The other phone is signed out,
  told why.
- **377 Downloads across it.** Start downloading an album, change the password mid-way: does the download finish?
- **378 Kill and reopen**: still signed in.
- **379 Unlock.** People asks for your password; a wrong one says so.
- **380 The list.** You first; Admin and deadwax's account marked; sign-ins and libraries; Known only to deadwax.
- **381 Add a person**; they sign in on the other phone.
- **382 Permissions.** Turn one off, Save; the other phone sees it on its next open.
- **383 Reset password**: their devices signed out.
- **384 Admin.** Make admin and back; the last admin is refused in words.
- **385 Remove**: type the name; gone. Forget someone known only to deadwax.
- **386 Left alone 15 minutes**: locked again.
- **387 Not a Navidrome admin**: no People.
- **388 Nothing opens Safari to deadwax.** Every Manage row, the album's •••, the artist's •••, Account, the Library's
  gate.
- **389 What still opens outside**: Album info's MusicBrainz, the EQ's GitHub, People's Sharing deadwax.
- **390 Offline**: each managing page says it needs deadwax, and comes back by itself.
- **391 The largest text, and VoiceOver**, across every managing page.

## 16. What only the phone can tell

- Whether a long apply survives the phone locking (`beginBackgroundTask`'s seconds), and what Navidrome's watcher does
  when the answer is lost (325).
- What an applied release does to the album's id in Navidrome 0.64, and so to its downloads on the phone: Navidrome's
  album id follows its PID rule, which tags can change - a downloaded album may then show as gone and need downloading
  again. Not designed around in this phase; 324 and 341 watch it.
- The SSE stream over WireGuard: keepalives through the tunnel, how fast a drop is noticed (373).
- `isIdleTimerDisabled` and a run left on screen; what iOS does to a run when the app is suspended (356, 358).
- The keyboard on the long forms - the year pad, the fields' Done, scrolling a field into view above the keyboard.
- The Keychain re-key after Change password, and a background download's 401 (376-378).

## 17. Decisions for James

1. **Artist pictures' previews.** The candidates are pictures on Commons, fanart.tv and TheAudioDB, and the phone talks
   only to deadwax. *Recommend:* a relay on deadwax (server change B) shaped like the Cover Art Archive's - a fixed list
   of hosts, no redirects off it, a size cap, a deadline, nothing kept. Without it Artist images on the phone chooses
   from words ("Wikimedia Commons, 600 px") - a blind pick of a picture that gets written into the library.
2. **"It's fine as it is" with Edit albums alone.** The web offers it (and Ask about it again) to anyone in the editor,
   but the route needs Look after the library, so someone with Edit albums only taps it and gets a refusal. *Recommend:*
   the phone shows it only with Look after the library, and the web is fixed the same way on main - marking an album
   fine takes it out of the admin's queue, which is Look after the library's call, not an editor's.
3. **Delete takes two steps on the phone** (a page with what goes, then a dialog) where the web has one dialog.
   *Recommend:* two - on a phone the facts and the button can't share one alert, and a tap is easy to land by mistake on
   the one action with no undo.
4. **Needs a look's count on the tab.** The web shows it on You's row and the desktop's sidebar, never on a tab.
   *Recommend:* on the Manage row only, as the web: a badge on Settings would nag a listener's tab bar about admin work.

## 18. What's deliberately different from the web, and what isn't ported

Different, for a phone:

- The editor's five tabs are a list of pages; Release is three pages (the release and fields, Choose a release,
  Changes).
- Server settings' three tabs are sections of group rows, each group its own page; choices are menu Pickers; the one
  save bar is a bottom toolbar on every Server settings page with the count.
- Needs a look's facet chips are one Show menu.
- People's row buttons are on a person's own page; Add, Reset and Remove are sheets.
- Delete is a page and a dialog (decision 3); Forget and Clear the saved answers ask first.
- Tags' ticks with shift-click ranges are Select's multi-select.
- The cover comparison is through deadwax's relay at 500 and 1200, not the Archive at 250.
- Errors: as the web's managing pages for deadwax's own words; a listener's words for everything the phone itself met,
  with the raw words for whoever runs deadwax.
- The event log offers Copy; a care run keeps the screen on.
- It's fine as it is is shown only with Look after the library (decision 2).

Not ported, and why:

- Keyboard shortcuts (Escape, arrow keys between tabs, Enter never confirming) - no keyboard; their intent is kept
  (Cancel is the default in every dialog).
- The desktop frame's panel mechanics (its drag, its width, the desktop visualizer beside it).
- `/library/queue/new_imports` - the summary's `total` already counts them.
- A disk cache of anything managing - section 2.
- Moving a downloaded album's records to its new Navidrome id after an apply - section 16, a question for later.
- The turntable's bench (`/player/lab/`) - not managing.
