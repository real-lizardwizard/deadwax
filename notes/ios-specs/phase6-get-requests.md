# Phase 6 - Get and Requests: what the iPhone app shows and does (app 0.12)

Design spec for the iPhone app's Phase 6 ("Get and Requests"), read 2026-11-14 at `ios` 3fc9a17 (app 0.11 (11), server
2.1.25). Area: the Requests tab - every download you asked for, as the web's Requests board draws it: Downloading,
Waiting, Needs attention and Done, with Cancel, Another source, Same source again, Clear done and a Done album's ▶ -
and Get, on the album you don't have: what deadwax already has of a pressing, the Sources sheet (Soulseek's folders
ranked against that pressing's tracklist, each with its reasoning), the download asked for, Join and Add to my library -
with the phase's checks. Every path is repo-relative and every line number is the code's at 3fc9a17.

**What binds it.** The plan (`~/Desktop/Code/deadwax-ios-plan.md`, outside the repo): James's answers at its top (the
app talks only to deadwax; a free account; no Simulator); its section 5's "Phase 6 - Get and Requests" ("Get with
sources (`find_candidates`) shown by default, the candidate's reasoning, enqueue; Requests (`/download/jobs`),
progress, Cancel, Next peer, Ask again, Clear done, a request's ▶ once filed. Permission-aware: Get albums taken away
shows the web's words."; checks "get an album end to end from the phone and play it from Requests when it's filed;
cancel one"); section 2's routes table ("Get, Requests | `/download/store_state`, `find_candidates` (request),
`enqueue` (request), `jobs`, `jobs/{id}/cancel`, `retry`/`retry_same`/`join` (request), `jobs/clear`;
`/monitor_slskd/ping`"); section 4's offline rule ("Search, Get, Requests and managing say they need deadwax, and show
nothing stale as if live"). Phase 7 (managing as links into the web) is not this phase's. Then what is built: Phases
1-5 (`notes/ios.md`) - the player, the Library, Search and the album you don't have (`GroupView`, which left room for
Get: `ios/App/Search/GroupView.swift`'s "Phase 6's Get the album goes here"), which this phase opens and plays through
and rebuilds none of.

**Where the words come from.** The web app has every one of these features, so its words and rules are the app's -
ported, and held to its TypeScript by a committed exporter wherever they are pure. The web's files: `ui/src/lib/
requestsView.ts` (the board's sections, every word of every row, what is arriving, the badge, what the app watches and
when it asks, what a screen reader hears, the Done rows' looks), `ui/src/lib/downloadOverlay.ts` (the overlays laid on
the polled jobs - cancelling, cleared, pending, retrying), `ui/src/lib/speed.ts` (a real rate from byte counts),
`ui/src/lib/perPerson.ts` (who asked, what a cancel does, the store line for somebody else's download),
`ui/src/lib/myLibrary.ts` (`grantWords`, `partlyWords`), `ui/src/lib/errorWords.ts` (`jobErrorWords`, `safeWords` -
already ported), `ui/src/hooks/useDownloadJobs.ts` (the one poll and the actions), `ui/src/app/Requests.tsx` and
`ui/src/app/JobCard.tsx` (the tab and its cards); for Get, `ui/src/lib/releasePayload.ts` and `ui/src/lib/release.ts`
(what a Get sends), `ui/src/lib/candidates.ts` (the Sources' rules and words, the store line), `ui/src/lib/
getSettings.ts` (You > Getting albums, the chips), `ui/src/app/{ReleaseGroupPage,Sources,SourceCard,StoreState,
useCandidateSearch,GettingChoices,ConfirmCancelChoice,useGetSettings}.tsx|ts`, `ui/src/lib/permissions.ts`
(`GET_OFF`, `gets`); `notes/app-requests-search-get.md` ("Requests", "Sources and Get", "the album you don't have") and
`notes/logins.md` ("Downloads per person", "Personal libraries"). Where the phone has something the web hasn't
(offline, the app in the background), the words and rules are new and listed in sections 1 and 2.7.

## 0. The foundation - checked

- **The branch.** `phase6-get`, from `ios` 3fc9a17, clean. `src/__init__.py` says `2.1.25`; `ios/Config/
  Base.xcconfig:11-12` say `MARKETING_VERSION = 0.11`, `CURRENT_PROJECT_VERSION = 11`. Phase 6's commits leave both
  alone until its last slice, which makes the app **0.12 (12)** with check_project.py, ios.yml,
  tests/test_ios_install.py, ios/README.md and docs/ios.md pinned with it (as 0.3 to 0.11 were). `__version__` is never
  changed on this branch.
- **Whose answers.** Every route below is the person's own. `/download/jobs` answers a user's own downloads - the ones
  they are waiting for, joined ones too - and, for an admin or anyone given Everyone's downloads, everyone's but those
  they cleared, each row saying who asked (`_per_person`, `src/routes/download.py:684`); with logins off the one user
  is the admin and every download is theirs. `cancel`, `retry`, `retry_same` and `join` act on a download the person
  may see (`_job_for`, `:801`: anyone else's is a 404, as for none). The app sends the person's cookie and nothing
  else, as every route since Phase 1; deadwax's same-origin guard lets a request with no `Origin` through, as every
  POST since Phase 1 has shown.
- **Permissions.** `find_candidates`, `enqueue`, `retry`, `retry_same` and `join` need `request` (Get albums -
  `GET_ALBUMS = [Depends(require("request"))]`, `download.py:40`); `jobs`, `cancel`, `clear` and `store_state` need
  only a signed-in person (`current_user`). The phone's `Access.can(.request)` reads it from `/me`
  (`ios/DeadwaxKit/Sources/DeadwaxCore/Access.swift`); without it every Get, Join, Another source and Same source again
  is replaced by the web's `GET_OFF` ("Getting albums is off for you - ask an admin.", `ui/src/lib/permissions.ts`).
- **The routes** (all exist; none is in the app's `Routes` today):

  | route | answers | slice |
  | --- | --- | --- |
  | `GET /deadwax/download/jobs` (`download.py:699`) | `{jobs, tracking_enabled}`; each job: `id, artist, album, year, username, directory, status, error, created_at, updated_at, release_mbid, release_group_mbid, edition, outcome, queue_position, attempt`, the transfer summary (`progress, state, speed, bytes_transferred, files_done, files_total, files_failed?, failure_reason?, matched` - `src/store.py summarize_transfers`), `alternatives_left` (only where a retry can move it), and with logins on `mine, shared, requested_by` (an admin's) and `library` | 1 |
  | `POST .../jobs/{job_id}/cancel` (`:818`) | `{status, left, cancelled, partials_removed, partials_problem}`; a user's cancel of a shared download only leaves it (`left` true) | 1 |
  | `POST .../jobs/{job_id}/retry` (`:918`, request) | `{moved, username, directory, left, problem}` - 200 either way, `moved` false with the problem; 409 for one not failed or cancelled | 1 |
  | `POST .../jobs/{job_id}/retry_same` (`:941`, request) | `{retried, username, files, problem}` - 200 either way | 1 |
  | `POST .../jobs/clear` (`:962`) | `{status, removed}` - the asker's finished rows hidden (logins on) or deleted (off) | 1 |
  | `GET /deadwax/store/album?release_mbid=` (already `Routes.storeAlbum`) | Navidrome's album of a Done row's release (`navidrome_id`, `present`) - the row opening it | 1 (no change) |
  | `GET /deadwax/navidrome/albums/{album_id}` (already `Routes.album`) | the album's songs - a Done row's ▶ | 1 (no change) |
  | `GET /deadwax/coverart/{kind}/{mbid}?size=` (already `Routes.archiveCover`, server 2.1.24) | a row's cover: the release's front at 250 (the web's `jobCoverUrl`) | 1 (no change) |
  | `POST /deadwax/download/store_state` (`:390`) | `{downloading, downloading_part, held, other_pressings}` for a `FindCandidatesRequest` - what the store and the downloads already have of a pressing, no search | 2 |
  | `POST .../find_candidates` (`:404`, request) | `{query, queries, response_count, candidates, ...store_state}`; no search while it is downloading or held whole; waits `SLSKD_SEARCH_TIMEOUT` + 17 s at most (`SEARCH_TIMEOUT_RANGE` 3-60, `src/config.py:1092`) | 2 |
  | `POST .../enqueue` (`:615`, request) | `{status, queued, job_id}` or, joined, `{status, queued: 0, job_id, joined: true}`; 409 in words (`already_have`), 502 slskd's refusal | 2 |
  | `GET /deadwax/me/preferences` (`src/routes/me.py:127`) | You > Getting albums as kept on deadwax: `get_mode`, `quality_floor`, `format_preference` (the Sources' format and floor) | 2 |
  | `POST .../jobs/{job_id}/join` (`:1005`, request) | `{status, job_id, joined}`; 409 `CLEARED_SINCE` | 3 |
  | `PUT /deadwax/me/preferences` (`me.py:133`) | You > Getting albums changed on the phone | 3 |

  tests/test_ios_contract.py's ROUTE_COUNT moves 49 -> 54 (slice 1: jobs, cancel, retry, retry_same, clear), 58
  (slice 2: store_state, find_candidates, enqueue, GET preferences), 60 (slice 3: join, PUT preferences).
- **`/monitor_slskd/ping`** is in the plan's table, but the web asks it only in You's Connections (`You.tsx`,
  `pingSlskd`) - whoever runs deadwax's check that slskd answers - never in Requests or Get. Not this phase's
  (question 2): it comes with You's Connections, a managing page (Phase 7).
- **What Core has already.** `ErrorWords.jobErrorWords` and `safeWords` (every word a job's error is said in - ported
  in Phase 1 with `Fixtures/errors/error-words.json`), `Access` (`can`, `seesDetail`, `hasLibrary`), `StoreAlbum` and
  `DeadwaxClient.navidromeAlbum(releaseMbid:)` (the id bridge), `AddRelease` (Add to my library's body - a
  `FindCandidatesRequest` subset), `ArchiveCoverID` and the relay, `AlbumTime.ms` (JavaScript's `Date.parse` for
  ISO forms - `updated_at` is `datetime.isoformat(timespec="seconds")` with `+00:00`, `src/store.py:656`), `jsFixed`
  (`toFixed`), `JSMath`, `JSText.trim`. The MusicBrainz models (`MusicBrainz.swift`: `PageRelease`, `MBMedium`,
  `MBTrack`) lack what a Get sends - a track's credit and a recording's, `video`, the release's packaging and its
  events' countries - which `/release_group` already answers (full MusicBrainz releases): slice 2 reads them, leniently.
- **The tabs.** The web's are Home, Library, Search, Requests and You (`ui/src/app/TabBar.tsx`); the phone's are
  Library, Search and You (`ios/App/Root/MainTabs.swift`, `AppTab` in `ios/App/Shared/Routes.swift`). Requests becomes
  the fourth, between Search and You - the web's order with Home left out (question 1).
- **The phone's "Downloads".** You > Downloads (Phase 2) is what is on this phone - offline copies, `DownloadModel`,
  `DownloadWords`. Nothing of it is touched; this phase's names say Requests (`RequestsModel`, `RequestsView`,
  `RequestRow`) or job (`DownloadJob` is the server's name for a row of `/download/jobs`, kept), never "downloads" for
  a type of the phone's own.

## 1. Words

Every line is the web's, from the file named; the exporter reads each from the TypeScript (or, for a component's,
from its source) so a change on the web fails the phone's tests until ported.

| where | words | source |
| --- | --- | --- |
| the tab | Requests; badge `n` (none at 0, "99+" past 99); VoiceOver "Requests, 2 arriving" | requestsView.ts `badgeText`, `badgeLabel` |
| headings | Downloading · Waiting · Needs attention · Done | `SECTION_TITLES` |
| the page | Requests; Clear done | Requests.tsx |
| before the first answer | a spinner (never "Nothing requested yet") | Requests.tsx |
| nothing | Nothing requested yet / "Albums you get show here while they download, and once they've arrived - find one in Search and tap Get." (without Get albums, `GET_OFF`) | `REQUESTS_EMPTY`, `REQUESTS_EMPTY_JOIN` |
| a failed look | Can't update your requests right now / the error in a listener's words / "It keeps asking while this tab is open." (rows below: "It keeps asking while this tab is open; what's below is from the last answer.") | `REQUESTS_UNREACHED`, Requests.tsx |
| untracked | Downloads aren't being kept track of / "Requests can't be shown right now: deadwax can't keep track of downloads. Tell whoever runs deadwax." (whoever runs deadwax: "deadwax can't write its database. Downloads still arrive in slskd's folder, but they can't be listed here or added to your library. Check DB_PATH.") | `UNTRACKED`, `UNTRACKED_TEXT`, Requests.tsx |
| Downloading | "Massive Attack · from mellotron · 2nd try"; "6 of 10 files · 2 failed · 1.8 MB/s"; organizing "10 of 10 files · adding to your library…"; "cancelling…" / "leaving…" | `jobRow`, `formatSpeed` |
| Waiting | "… · 4th in their queue" / "… · starting" (amber with "· 3 failed"); a request not a job yet "… · starting…" | `jobRow`, `pendingRow` |
| Needs attention | the reason (jobErrorWords; "Cancelled", "It stopped without saying why"); "Another source · 2 left" / "Trying another source…"; "Same source again" / "Trying again…"; a retry's refusal (`RETRY_WORDS`, the "already …" words, "They refused - try another source.", "No other source would send it.", "That didn't work."); a refused request "… · didn't start", "The download couldn't be started." | `jobRow`, `retryProblemWords`, useDownloadJobs.ts |
| Done | "In your library · 12 minutes ago", "You already had it", "In your library - 2 files couldn't be added", "Stopped while being added to your library", "Downloaded, but not added to your library", the grants' words (logins on); "just now", "N minute(s) ago", "N hour(s) ago", "yesterday", "N days ago" | `outcomeWords`, `grantWords`, `partlyWords`, `ageText` |
| a Done row that can't open | "Not ready to play yet - it may still be scanning." · "Can't find this album to open it - it may have moved, or isn't matched to a pressing." · "Couldn't open it - tap to try again." · the three music-server lines (`CANT_OPEN_UNSET`, `_DOWN`, `_OFFLINE`) | Requests.tsx |
| who asked | "Asked by ethan", "Asked by you and ethan", "Someone else asked for it too", "Nobody is waiting for this any more" | perPerson.ts `askedByText` |
| the ✕ | VoiceOver "Cancel Dummy" / "Leave Dummy"; in the card "Cancel this download? You'll lose your place in their queue." with Keep it / Cancel download (a shared one's: "Leave this download? …" Leave it; an admin's "Cancel this download for everyone? ethan asked for it too." Cancel for everyone) | JobCard.tsx, `cancelWords` |
| a Done row's ▶ | VoiceOver "Play Dummy · 2014 vinyl" | JobCard.tsx `DoneRow` |
| without Get albums | "Getting albums is off for you - ask an admin." in a card that would have had Another source or Same source again | JobCard.tsx `AttentionCard`, permissions.ts |
| You > Getting albums | Confirm before cancelling / "The ✕ on a download in Requests asks first. Kept on this device." (slice 1); When I tap Get, Quality floor, Format and their footnote (slice 3) | ConfirmCancelChoice.tsx, You.tsx, GettingChoices.tsx |
| Get (slice 2) | Get the album; the store line (`storeStatusFor`: "Already in your library", "Already downloading", "Already downloading for someone else", "In the store, not in your library" …); the Sources sheet ("Choose a source", Cancel, "Looking for “Dummy” by Portishead…", "This takes a few seconds.", the chips, the sort's Best match / Highest quality / Largest first / Smallest first, a card's Speed / Tracks / Quality / Size / Starts, "Why it's a 92% match", Get, "Search for", Search, Try again, Clear filters, Search again, `nothingFoundLine`, `noneMatchLine`, `NOTHING_LOSSLESS_NOTE`) | candidates.ts, perPerson.ts, Sources.tsx, SourceCard.tsx, StoreState.tsx |
| Join, Add (slice 3) | Join this download / Joining… / "Joined - it's in your Requests."; Add to my library / Adding… | StoreState.tsx |

The phone's own (nothing on the web says them - the web has no offline):

| where | words | why |
| --- | --- | --- |
| Requests, deadwax out of reach | "Requests show once deadwax is back." (under the offline banner, as Search's "Search works once deadwax is back.") | question 4 |
| Get, deadwax out of reach (slice 2) | "Getting albums works once deadwax is back." in the store line's place | question 4 |

## 2. Rules for Core, held to the web

### 2.1 The board (requestsView.ts)

`RequestsView.make(input, now:)` is `requestsView` to the character: each job to its section by `sectionOf`
(downloading or organizing - Downloading; queued - Downloading with progress over 0, else Waiting; failed or cancelled
- Needs attention; `not_filed` - Needs attention; anything else - Done); a request not yet a job (`PendingDownload`)
Waiting while it asks, Needs attention once refused; Waiting and Needs attention list the requests first; Done newest
first by `updated_at` (unreadable is 0), then by id; ONE primary button - the first Another source in Needs attention -
the rest tinted. Every field of `RequestRow` as the web's (`key`, `jobId`, `section`, `title`, `artist`, `line`,
`lineTone`, `reason`, `reasonTell`, `reasonDetail`, `problem`, `problemDetail`, `progress`, `data`, `brief`, `cancel`,
`nextPeer`, `askAgain`, `busy`, `dimmed`, `arriving`, `album`, `release`, `plays`, `askedBy`, `cancelWords`) - except
`cover`, which the web makes a Cover Art Archive URL of and the phone keeps as the release's id, for the relay
(`ArchiveCoverID(.release, id)` at 250, question 9). `arriving` - the badge's count - is every Downloading, Waiting
and Needs attention row marked arriving (not being cancelled; a retry under way; a request still asking); `clearable`
is a finished job or a refused request; `empty` no job and no request.

`ageText`, `outcomeWords` (`grantWords` first), `badgeText`, `badgeLabel`, `ordinal`, `retryProblemWords` (`RETRY_WORDS`,
the "already …" starts, `safeWords`), `formatSpeed` are each the web's. `jobErrorWords` is Core's already.

### 2.2 The overlays (downloadOverlay.ts)

`RequestOverlays` is `Overlays`: cancels asked for and not yet seen (`cancelling`), finished rows cleared and not yet
gone (`cleared`), requests not yet jobs (`pending`), retries not yet seen moving (`retrying`); `reconcile` drops each
the moment a poll agrees (a cancel when the job stops being active or goes; a clear when it goes; a retry when it is
active again or gone; a request when its job is listed), and `visibleJobs`, `visiblePending`, `activeCount`,
`finishedIds`, `withPending`, `settlePending`, `withoutRefused` as the web's. An overlay is set BEFORE its request goes
out, rolled back when the request fails (a cancel, a clear), and dropped after 15 s (`OPTIMISTIC_TTL_MS`) when the
server never agrees - useDownloadJobs.ts's rules, in the App's model. `retryingSame` and `retryProblems` are kept
beside them, as the hook keeps them.

### 2.3 Speeds (speed.ts)

`SpeedSamples.sample(jobs, now:)` is `sampleSpeeds`: a rate only over a window of a second or more with bytes moved,
the last rate kept 6 s across quiet polls, a negative delta or no time starting the job afresh, a job no longer active
(or gone) forgotten. `now` in milliseconds on the monotonic clock. Never `job.speed` (slskd's cumulative average).

### 2.4 Who asked, and what a cancel does (perPerson.ts, myLibrary.ts)

`askedByText`, `cancelWords` (its `leaves`), `leavesOnCancel`, `SHARED_TEXT`, `NOBODY_TEXT`, `CANCEL_WORDS`;
`grantWords` and `partlyWords` - each the web's. With logins off the server sends none of `mine`, `shared`,
`requested_by` or `library`, and every word is the one it always was.

### 2.5 What the app watches, and when it asks (requestsView.ts, useDownloadJobs.ts)

`Watching` (`requests`, `home`, `other`, `hidden`), `watchingOf(shown:tab:depth:sheetOpen:)`, `stallsOn` and
`asksAgain` are the web's. The phone has no Home, so `home` never comes; its `shown` is the scene being active, its
`tab` "requests" for the Requests tab, `depth` that tab's pages, `sheetOpen` Now Playing.

The poll is the web's hook, with three rules of the phone's own (`RequestsPolling`, question 3):

- **Open** - Requests' root showing, or `stallsOn` - asks every 0.5 s (`POLL_OPEN_MS`); with nothing open, every 1 s
  while an album is being filed (`POLL_FILING_MS`), every 5 s while anything is active (`POLL_BACKGROUND_MS`), and
  not at all otherwise - the web's.
- **Not while deadwax can't be reached** (`Reachability.online` false): no poll at all; asked once at once when it is
  back.
- **Not while the app is in the background** (`watching == .hidden`): the web's page is suspended by iOS there, but the
  app runs on while it plays music, and nothing of the badge can be seen - a poll there is battery and the tunnel's
  data for nobody. Asked once as the app comes back to the front (`asksAgain`: from `hidden`, on any tab).
- And once as deadwax is first known for this person (the app's start, a sign-in), so the badge is right from the
  start - the web's hook asks once as the app mounts.

A turn of `open` (on or off) asks at once, as the web's effect re-runs on `open`; a tap's action asks at once when it
answers (`refresh`). Each look is its own task; a look whose answer comes after the person changed, or after a newer
look began, is dropped. The constants are read from useDownloadJobs.ts by the exporter.

### 2.6 A Done row's album (requestsView.ts `doneLooks`, Requests.tsx)

`DoneLooks.looks(rows:held:now:)` is `doneLooks`: for the first five Done rows that play (`DONE_PREFETCHED`), the
id bridge is asked for the release's album - never before Navidrome can have scanned what the row filed
(`DONE_SCAN_SETTLE_MS` 10 s after it first showed as done, by this phone's clock; 0 for a row already done in the first
answer), and after a look that found nothing again only after 5 s doubling to 60 s - and an album's songs asked for when
never asked, when asked before the newest row's filing could have been scanned, or when asked over 30 s before
Requests last came into view. `nextIn` says when the next falls due. The looks run only while Requests' root is what
shows; leaving it lets every look still out go (their answers drawn nowhere).

A Done row's tap opens its album on the Requests tab - Navidrome's album for the release, from what the looks found or a
look of its own - but only while Requests' root is still what shows when the answer comes (the tab, no page over it,
Now Playing not over it): otherwise it opens nothing. A second tap supersedes the first. A row that can't open says why
(`noteFor`): Navidrome's own problem, no folder tagged with the release, or Navidrome not having found it yet - and the
note goes once a later look finds it. A row's ▶ plays its album from the first song, in the tap, with the songs in hand;
without them it does what the row's tap does (question 6).

### 2.7 What a screen reader hears (requestsView.ts `changes`)

`RequestChanges.changes(before:now:)` is `changes` (and `focusAfterGone`, which it uses): a row under another heading,
a retry's refusal appearing, a tap's answer starting, a download you left gone from your list. The phone says `said`
as a VoiceOver announcement while Requests' root shows; it moves no focus (question 10).

### 2.8 What a Get sends (slice 2 - releasePayload.ts, release.ts)

`GetRelease` is `buildDownloadRelease(group, pressing)`: the group's context (its title, first release date and
credit), the pressing's title, credit (`creditName`, `currentName`, `creditIds`), year and original year, every
track's position, title, length, disc, disc position, artist and video flag (`isVideoTrack`), the disc titles, format,
country, catalogue number, label, packaging and the edition tags (`detectEditionTags`) - or the group's fallback with
no pressing - encoded with `FindCandidatesRequest`'s field names, `format_preference` the person's. Held by the exporter
over the real groups in `tests/fixtures/pressings/` and `tests/fixtures/payloads/find-buttons.json`.

### 2.9 The store line (slice 2 - candidates.ts `storeStatus`, perPerson.ts `storeStatusFor`)

What deadwax already has of the pressing shown, asked through `/store_state` as the pressing is chosen and as the page
shows: held whole ("Already in your library", with the tracks held), held in part, downloading (yours: the peer and how
far; somebody else's: "Already downloading for someone else", the copy, the quality floor's word, what Join does),
being filed, in the store but not your library (Add to my library). `withoutJoin` for someone without Get albums. Drawn
under Get the album, in one region whose height is kept while it is asked again.

### 2.10 The Sources (slice 2 - candidates.ts, getSettings.ts, useCandidateSearch.ts, Sources.tsx)

The sheet asks `find_candidates` once per Get (newest answer only), with the person's Format; its chips start as their
quality floor (`floorFilters`, `sourceChips`), the sort at Best match; the cards in `sortCandidates`' order, each with
its score (`scoreClass`), its facts (`speedFact`, `startsFact`, `qualityText`, `tracksText`, `missingLine`,
`editionTags`) and, tapped, its reasoning (`signalChips` with `SIGNAL_LABELS` and `SIGNAL_MEANINGS`); every state's
line (`searchingLine`, `nothingFoundLine`, `noneMatchLine`, `nothingLosslessLine`, `searchedLine`) and the
announcement (`sourcesAnnouncement`). A card's Get sends `enqueue` with the folder, the release, the quality
(`candidateQuality`) and up to ten alternatives as shown (the next peers) - a pending row up in Requests from the tap -
and the sheet closes on Requests' root, as the web's `gotten`. Search for (a query of your own, `queryOverride`) and
Search again.

### 2.11 Join, Add to my library, Pick the best source for me (slice 3)

Join (`/jobs/{id}/join`) from the store line, Add to my library (`/me/library/add`, already `Routes.libraryAdd`) from
it, and "Pick the best source for me" (`autoGrabPick` at `AUTO_GRAB_MIN_SCORE` 75, `autoPickBlocked`, `notPickedLine`):
the web's rules.

### 2.12 You > Getting albums (slice 1's one setting; slice 3's three)

"Confirm before cancelling" is this phone's (`ConfirmCancel`, UserDefaults under the web's key
`deadwax-player-confirm-cancel`: "off" is off, anything else - nothing stored included - on). Slice 3 adds When I tap
Get, Quality floor and Format above it - kept per user on deadwax (`/me/preferences`), asked each time You shows.

## 3. Screens

### 3.1 The tab bar

```
 [ Library ]  [ Search ]  [ Requests (2) ]  [ You ]
```

Requests, `square.and.arrow.down` (the web's RequestsIcon is an arrow into an open box), its badge the arriving count
(`badgeText`), none at 0 and none while deadwax can't be reached. Tapping it shown pops its pages, then scrolls to the
top, as every tab.

### 3.2 Requests' root

```
 Requests                                   Clear done
 ┌ Can't update your requests right now ────────────┐   (a failed look only)
 │ The download service isn't answering. …          │
 │ It keeps asking while this tab is open; what's … │
 └──────────────────────────────────────────────────┘
 DOWNLOADING
 [cover] Mezzanine · 1998 CD                      (✕)
         Massive Attack · from mellotron · 2nd try
         Asked by you and ethan
         ▕██████████░░░░░░░░▏
         6 of 10 files · 1.8 MB/s
 WAITING
 [cov] Dummy                                      (✕)
       Portishead · from cratedigger · 4th in their queue
 NEEDS ATTENTION
 [cov] Heligoland
       Massive Attack · from vinylhead
       The person sharing it stopped responding.
       [ Another source · 2 left ] [ Same source again ]
 DONE
 [cov] Blue Lines                                 (▶)
       In your library · 12 minutes ago
```

A List of Sections, each only when it has rows, the title the large navigation title, Clear done the trailing
toolbar button (disabled with nothing to clear). The cover is the release's front through the relay (empty square
without one). Every line one line high where it changes as answers land: the data line keeps its height whether or not a
speed is drawn, the bar a fixed height; the covers' sizes `@ScaledMetric`. The ✕ is a 44-point button, disabled
while its cancel is out, opening the card's question - the line and Keep it / Cancel download (the row's own words) - in
the card; a second tap on the ✕ closes it; with Confirm before cancelling off, it cancels at once. One card asks at a
time. Needs attention's two buttons wait (disabled) while a retry of the row runs, the one tapped saying what it does;
without Get albums neither is drawn and `GET_OFF` is. A Done row of an album in the library is a button opening it; one
this download filed has the ▶.

### 3.3 Offline, and the background

Deadwax out of reach: the offline banner (as every page) and "Requests show once deadwax is back." in the list's place;
no rows from the last answer, no badge, Clear done disabled, nothing asked. Back: the last answer's rows are drawn again
at once and a look asked (question 4). In the background nothing is asked; back in front, one look.

### 3.4 Get on the album you don't have (slice 2)

Under the pressing picker's facts in `GroupView` (its "Phase 6's Get the album goes here"): **Get the album** (prominent),
and under it the store line. Without Get albums: no button, `GET_OFF` as the web's footnote. Get opens the Sources sheet
(3.5) for the pressing chosen (or the group's fallback). Offline: no Get, the phone's line (section 1).

### 3.5 The Sources sheet (slice 2)

A sheet, "Choose a source" with Cancel: the searching line and "This takes a few seconds." while it asks; then the chips
(scrolling), the sort, and the cards - score, the folder's name, the facts, Get; tapping the score shows the card's
reasoning. A Get closes the sheet and shows Requests' root with the new row already up ("starting…").

## 4. The server

**Nothing is missing.** Every route the phase needs exists (section 0) and answers what the phone reads; covers come
through the relay (2.1.24); the per-person rules are the server's. Checked and not needed: a `/download/jobs` ETag (the
answer changes every poll while something moves - it carries progress), a push of job changes (the web polls too; the
plan's "Live queue pick-up, later" is about the play queue), a cover route for jobs (the relay takes a release's id).
If one were found missing while building, it would go to main as a 2.1.x patch first, not on this branch.

## 5. Machinery

| Core (DeadwaxCore, pure, tested on Linux) | App (SwiftUI) |
| --- | --- |
| slice 1: `Requests.swift` - `DownloadJob`, `JobsAnswer` and the actions' answers; `RequestsView` (2.1), `RequestWords`, `RequestChanges` (2.7), `Watching` and `RequestsWatch`, `RequestsPolling` (2.5), `DoneLooks` (2.6), `ConfirmCancel` (2.12) | `RequestsModel` - the one poll, the overlays, the actions, the Done rows' looks, the announcements |
| slice 1: `RequestOverlays.swift` (2.2), `SpeedSamples` (2.3), `PerPerson` (2.4) | `RequestsScreen` and its cards; the tab and its badge in `MainTabs`; `AppTab.requests` and its stack in `AppNavigation`; You's Getting albums with Confirm before cancelling |
| slice 2: `GetRelease.swift` (2.8), `StoreLine.swift` (2.9), `Sources.swift` (2.10) | `GroupView`'s Get and store line, `SourcesSheet`, the pending row |
| slice 3: Join, Add, the auto-pick, `GetSettings` | the store line's buttons, You's three choices |

**Held to the web.** `ios/scripts/export-requests-vectors.cjs` compiles `lib/requestsView.ts`, `lib/downloadOverlay.ts`
and `lib/speed.ts` (with what they import: perPerson, myLibrary, errorWords, format, jobs) and reads the numbers and
words of `useDownloadJobs.ts`, `Requests.tsx`, `JobCard.tsx`, `You.tsx`, `ConfirmCancelChoice.tsx` and
`permissions.ts` from their source; writes `ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/requests/
requests-vectors.json`; `ui/test/iosrequests.sim.cjs` runs it with `--check`; `RequestsVectorTests` replays it. Slice 2
adds `export-get-vectors.cjs` (releasePayload, release, candidates, getSettings, perPerson's store line) with
`iosget.sim.cjs`. What lives in a component the exporter can't compile - useDownloadJobs.ts's hook, Requests.tsx's
Done-row state, `noteFor` - is ported by hand with tests of its own, and says so.

## 6. Slices

### 6.1 Slice 1 - Requests (app stays 0.11)

The Requests tab, whole: the board (2.1-2.4), the poll (2.5), Cancel with the card's question and Confirm before
cancelling in You, Another source, Same source again, Clear done, Done rows opening and playing (2.6), the
announcements (2.7), offline and the background (3.3), Get albums' words, the badge. Routes 49 -> 54. Downloads asked
for elsewhere (the web, another phone) show here; nothing on the phone asks for one yet.

### 6.2 Slice 2 - Get (app stays 0.11)

Get the album on the album you don't have, its store line, the Sources sheet with the reasoning, the download asked for
with its row up in Requests from the tap. Routes 54 -> 58. Checks: "get an album end to end from the phone and play it
from Requests when it's filed".

### 6.3 Slice 3 - Join, Add, the auto-pick and Getting albums (app 0.12 (12))

Join and Add to my library from the store line, Pick the best source for me, You > Getting albums' three choices,
Search again with your own words; the version pinned everywhere it is. Routes 58 -> 60.

### Slice 1, built

See notes/ios.md, "Phase 6, slice 1: Requests".

## 7. Tests

- Core: `RequestsVectorTests` (every vector: the words, the ordinals and badges, the ages, the outcomes, who asked and
  the cancel words, the retry problems, the sections, whole boards from seeded random inputs with every row's every
  field, `changes` over sequences of boards, the overlays' reconcile and its views, speed traces, watching / stalls /
  asks-again grids, `doneLooks` cases) and `RequestsTests` by hand (the polling rule, `ConfirmCancel`, `DownloadJob`
  decoding a real answer of the route's, the client's five requests, the cover's id).
- Python: `tests/test_ios_contract.py` - ROUTE_COUNT 54; every new route's method, path and parameters; `DownloadJob`'s
  fields within what `/jobs` builds, `JobsAnswer`, `CancelAnswer`, `RetryAnswer`, `RetrySameAnswer`, `ClearAnswer` within
  the routes' returns; the permissions the app shows Get albums' words for being the routes' own.
- The sims: `iosrequests.sim.cjs`, and every other as before.

## 8. James's checks

Numbered after docs/ios.md's 165. Slice 1's (166-179, 178 and 179 from its review) are written out in docs/ios.md;
slices 2 and 3 will add theirs (180 on) when they are built: get an album end to end and play it from Requests (the
plan's), its store line, Sources' reasoning, a refusal, Get albums taken away; Join and Add, the auto-pick, You's three
choices.

## 9. What only the phone can tell

- Whether a 0.5 s poll over WireGuard keeps up (the web's own on James's phone does), and what it costs the battery
  with Requests left open.
- Whether the badge's VoiceOver label is read as "Requests, 2 arriving" (`.tabItem`'s label taking an
  `accessibilityLabel` is not documented - it may read "Requests, 2 items").
- Whether announcements while the list redraws are heard, and not cut off by the redraw.
- Whether a card's question opening and closing in a List row animates without the row jumping at the largest text size.
- Real slskd: queue positions, the speed, a refusal, a cancel - the board's words on what slskd really says.

## 10. Open questions, each with the recommendation built

1. **Where Requests lives.** *Recommend, and built:* a fourth tab between Search and You - the web's order (Home,
   Library, Search, Requests, You) less Home - `square.and.arrow.down`, with the badge. Not inside Search or You: the
   web gives it a tab, and a download is something you come back to.
2. **`/monitor_slskd/ping`.** *Recommend, and built:* not asked. The web asks it only in You's Connections, whoever
   runs deadwax's check; Requests says slskd's troubles through `/jobs`' own errors. It comes with Connections in
   Phase 7.
3. **The poll's cadence on a phone.** *Recommend, and built:* the web's (0.5 s open, 1 s filing, 5 s with something on
   its way, none otherwise), but none in the background and none while deadwax can't be reached - each asked once on
   the way back. The web polls on in a backgrounded tab only because iOS suspends it; the app isn't suspended while it
   plays.
4. **Offline.** *Recommend, and built:* the rows hidden, "Requests show once deadwax is back.", no badge - the plan's
   "show nothing stale as if live". Back online, the last answer's rows are drawn at once with a look asked (under a
   second stale - the web keeps a failed look's rows the same way) rather than a spinner replacing the list.
5. **Confirm before cancelling.** *Recommend, and built:* the web's in-card question (not a confirmation dialog), on
   by default, this phone's own, its toggle in You > Getting albums now - slice 3 adds the three choices above it.
6. **A Done row's ▶.** *Recommend, and built:* the web's rule kept though a native app has no gesture to keep - play
   only with the songs in hand (the first five Done rows' asked ahead), else do what the row's tap does - so a ▶ never
   waits on a request before anything plays.
7. **Home's Arriving.** *Recommend, and built:* not built - the phone has no Home. The badge is the only sign of a
   download outside Requests.
8. **An album filed.** *Recommend, and built:* a poll that sees a job newly filed asks Search's owned index again
   (`SearchModel.refreshOwned`), so the album you don't have says you have it. The Library learns as it always does
   (a pull, or its own minute-old refresh as it shows) - the web's `announceAlbumsFiled` has listeners (the Home
   shelves, the owned marks on a desktop) the phone hasn't.
9. **The cover.** *Recommend, and built:* the release's front through the relay at 250 (the web's `jobCoverUrl`), never
   the group's: a pressing you asked for is drawn as that pressing, or the empty square.
10. **VoiceOver focus after a card moves.** *Recommend, and built:* not moved - the web puts a keyboard's focus back on
    a card that moved or beside one that went; VoiceOver on iOS keeps its own place in a List, and `changes`' words are
    announced. `focusAfterGone` is ported (`changes` uses it) and held.
11. **The new routes' time to answer.** *Recommend, and built:* `/jobs` 20 s (it asks slskd for every open download's
    transfers and queue places), cancel 30 s, retry 60 s (up to three peers asked in turn, each an enqueue to slskd),
    same source 30 s, clear 30 s - deadwax bounds none of them, and the transport's 8 s would call a slow slskd a
    failure.
12. **The error card's words on the phone.** *Recommend, and built:* the web's (`REQUESTS_UNREACHED`, the error in a
    listener's words through `ErrorWords.of(service: .downloads)`, "It keeps asking while this tab is open…") - for a
    look deadwax answered with an error; a phone that can't reach deadwax at all says question 4's line instead.
