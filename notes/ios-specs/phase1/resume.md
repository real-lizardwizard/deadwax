# Phase 1 spec: Resume what was playing (the iPhone app)

Scout's spec for porting the web app's "Resume what was playing" (2.0.0-player.64) to DeadwaxCore, with the app's
wiring. Read at `ios` = main = 2.1.0 (`1199330`). Everything below was read from the code and the tests; where a
claim was run, it says so.

## 0. Status against 2.1.0 / 2.0.15, and what "works out" needs

- **Nothing in resume has changed since 2.0.0.** `git log --oneline 85aa7be..HEAD` is EMPTY for
  `ui/src/lib/resume.ts`, `ui/src/app/useResume.ts`, `src/play_queue.py`, `tests/test_play_queue.py`,
  `ui/test/resume.sim.cjs`, `ui/test/playqueue.sim.cjs`, `ui/src/lib/playQueue.ts`, `ui/src/lib/loudness.ts`,
  `ui/src/state/persisted.ts`, `ui/src/app/useShuffleFeed.ts`. The touching commits are not resume's:
  `src/routes/navidrome.py` bec8e8c (2.0.4: playlists' `Explained`), `src/store.py` 142268e (2.0.2) / 88ed659
  (2.0.13), `ui/src/player/api.ts` bec8e8c (an `offline?` on NavidromeStatus), `ui/src/lib/upNext.ts` 6452ff3 (2.0.5
  "All music"), 92a58dc (2.0.7 "Up Next" capitalised), 7bb0a85 (2.0.14 `shuffleLabel`) - words only, the snapshot
  untouched. `usePlayer.ts` 92a58dc (2.0.7, words) - `restoreQueue` (usePlayer.ts:1680) unchanged.
- Ran on 2.1.0: `ui/test/resume.sim.cjs` all passed (126 PASS); `pytest tests/test_play_queue.py` 63 passed.
- **The server needs nothing new for resume.** The three routes exist and are `"user"` in tests/test_logins.py:192-194.
- **In the repo, the implementer must change** (all in the Phase 1 work): `ios/.../DeadwaxCore/Routes.swift` (three
  Endpoint lines + `Routes.all`), and **tests/test_ios_contract.py**, whose
  `test_the_app_names_its_routes_in_the_form_this_test_reads` asserts `len(found) == 7` (it becomes 10 with resume's
  three, more with the other Phase 1 routes) - see section 9.3 for the contract checks to add.
- App version: 0.2 for Phase 1 (`MARKETING_VERSION` in ios/Config/Base.xcconfig is 0.1 today).

## 1. Where it lives in Swift

| Swift (proposed) | from | what |
| --- | --- | --- |
| `DeadwaxCore/Resume.swift` | lib/resume.ts (all 484 lines) | constants, `windowOf`, `toSave`, `relevel`, `savedLevels`, `fromSnapshot`, `resumed`, `pickedUpWords`, `changedSince`, `saveDue`; pure |
| `DeadwaxCore/SnapshotJSON.swift` | JSON.stringify / JSON.parse semantics | a `JSONValue` reader and an ordered writer that matches JSON.stringify (section 4.3) |
| `DeadwaxCore/ResumeModels.swift` (or Models.swift) | api.ts:263-311, play_queue.py:102-137 | `QueueAnswer`, `KeptQueue`, `QueueSaveBody`, `QueueAtBody`, `SavedQueue` |
| `DeadwaxCore/ResumeController.swift` | app/useResume.ts (351 lines) | the saving/putting-back state machine, `@MainActor`, clock, timers and server injected - Linux-testable |
| `DeadwaxCore/DeviceID.swift` | state/persisted.ts:315-335 | make / validate the device id (storage is the app's) |
| `DeadwaxCore/Routes.swift` | - | `queue`, `saveQueue`, `saveQueueAt` endpoints |
| App: `AppModel` | usePlayer.ts:1680 `restoreQueue`, App.tsx:1035 | the engine's `restoreQueue`; feeding the controller; scenePhase; UserDefaults; the notice |

**What resume needs from the Up Next port** (use whatever names that spec settles; these are the members read):

- `QueueTrack` - exactly the 12 fields of playQueue.ts:12-32 plus the level of loudness.ts:38 (`LevelledTrack`):
  `id: String`, `title: String`, `artist: String`, `album: String`, `albumId: String?`, `coverArt: String?`,
  `duration: Double` (seconds, 0 unknown), `contentType: String?`, `suffix: String?`, `sampleRate: Int`,
  `bitDepth: Int`, `channels: Int` (0 unknown), `level: Level?`. **Equatable** (value equality replaces the web's
  object identity - section 6.1). title/artist/album must be non-optional: the web's `readSong` (resume.ts:205)
  refuses a snapshot whose kept-whole song lacks any of them.
- `Level` (`album` | `track`), `Normalization` (`auto` | `song` | `album` | `off`, default `auto`), `Repeat`
  (`off` | `all` | `one`).
- `Mark { key: Int, from: From (source|added|one), at: Int, pass: Int }`, `Paged { token: String, total: Int,
  fetched: Int, scope: (yours|store), level: Level? }`, `PagedRound { pass: Int, paged: Paged }`,
  `Left { pass: Int, at: Int }`.
- `UpNextState { marks, source: [QueueTrack], shuffle: Bool, nextKey: Int, startedAt: Int, left: [Left],
  paged: Paged?, pagedRounds: [PagedRound]? }` - note `pagedRounds` nil and `[]` are different values in TS
  (absent vs present-and-empty); keep them distinct.
- `UpNextQueue { tracks: [QueueTrack], index: Int (-1 none), upNext: UpNextState? }`, `EMPTY_QUEUE`, `current()`.
- `startUpNext(tracks, start: Int?, shuffle: Bool = false, random, paged: Paged? = nil)` (upNext.ts:162) - resume
  calls it only as `startUpNext(tracks, index)`; `withRepeat` (upNext.ts:244) and `toppedUp` (upNext.ts:192), for the
  engine's restoreQueue. Its tests exercise `withNext`, `withLast`, `withoutKey`, `movedKey`, `withoutAdded`,
  `withShuffle`, `withMore`, `jumpedTo`, `onward`, `backward` only through recorded traces (section 10).

## 2. Constants

| name | value | TS | Python |
| --- | --- | --- | --- |
| RESUME_MAX (entries saved) | 2000 | resume.ts:33 | play_queue.py:33 `RESUME_MAX` |
| RESUME_BEFORE (before the song playing) | 50 | resume.ts:34 | play_queue.py:34 |
| RESUME_SNAPSHOT_MAX (characters) | 262_144 | resume.ts:36 (JS `.length` = UTF-16 units) | play_queue.py:36 `SNAPSHOT_MAX` (`len` = code points) |
| RESUME_EVERY_S | 30 | resume.ts:38 | - |
| RESUME_FULL_WAIT_MS | 2000 | resume.ts:40 | - |
| RESUME_AT_WAIT_MS | 1000 | resume.ts:41 | - |
| RESUME_RECHECK_MS | 15_000 | resume.ts:43 | - |
| RESUME_FOCUS_GRACE_MS | 500 | resume.ts:48 | **not ported** (no window focus on iOS) |
| BEACON_MAX | 60_000 | resume.ts:52 | **not ported** (no keepalive budget) |
| DEADWAX_CLIENT | "deadwax" | resume.ts:54 | navidrome_endpoint.py:59 `CLIENT_NAME` |
| MARGIN_MS (added to each wait) | 50 | useResume.ts:22 | - |
| OWED_ORDER | pause, wait, position | useResume.ts:25 | - |
| POSITION_MAX (s) | 86_400.0 | - | play_queue.py:38 |
| CHANGED_BY_MAX | 64 | - | play_queue.py:40 |
| DEVICE_PATTERN | `^[A-Za-z0-9_-]{8,64}$` | persisted.ts:316 | play_queue.py:42 |
| LABEL_PATTERN | `^[A-Za-z0-9 ]{1,40}$` | - | play_queue.py:43 |
| ID_MAX (each song id) | 256 | - | navidrome.py:393 (`SongId`, :967) |

Sizes: count the snapshot cap in **UTF-16 units** (`snapshot.utf16.count`) as the web does - never fewer than the
server's code points, so a snapshot the phone keeps is never one the server refuses.

## 3. The wire

All three answer with `Cache-Control: no-store` (navidrome.py:1392 `_no_store`), the break-glass admin's too. The
app's POSTs carry no `Origin`, so the same-origin guard lets them through (notes/ios.md; tests/test_play_queue.py
`test_the_pages_own_json_post_passes_the_guard_and_another_sites_does_not` shows a foreign Origin is a 403).

### 3.1 `GET /deadwax/navidrome/queue` (navidrome.py:1401-1428; play_queue.py:107-137 `answer`)

```json
{"tracks": [{"id": "q-1", "title": "Song 1", "artist": "Portishead", "album": "Dummy", "albumId": "nd-dummy",
             "coverArt": "al-1", "duration": 200, "contentType": "audio/flac", "suffix": "flac",
             "samplingRate": 44100, "bitDepth": 16, "channelCount": 2, "track": 1, "discNumber": 1}],
 "index": 2, "position": 95.25, "changed_by": "deadwax", "shared": false,
 "kept": {"rev": 1, "ids_rev": 1, "ids": ["q-1", "q-2", "q-1", "q-3"], "index": 2, "position": 95.25,
          "snapshot": "{\"v\":1,...}", "device": "phone-device-01", "label": "iPhone"}}
```

| field | type | notes |
| --- | --- | --- |
| `tracks` | `[Song]` | Navidrome's entries in its order, each trimmed to `SHUFFLE_FIELDS` (navidrome.py:729: id, title, artist, album, albumId, coverArt, duration, contentType, suffix, samplingRate, bitDepth, channelCount, track, discNumber) - **only the keys Navidrome sent**, so every field but `id` is optional. Songs Navidrome no longer has are already dropped. Over 2,000: the window around its index (play_queue.py:121-125). |
| `index` | `Int?` | Navidrome's `currentIndex` AS IT SAID IT - `null` when it said none or the list is empty; after a deletion it can name the wrong song or be past the end (test `test_songs_gone_are_left_out_and_the_stored_index_is_answered_as_navidrome_does`). Never trust it unaligned. |
| `position` | `Double` | seconds (Navidrome's ms / 1000); `0` (a JSON int) when none or not positive. |
| `changed_by` | `String` | Navidrome's `changedBy`, control characters out, trimmed, at most 64 (`cleaned_name`); `""` for none. |
| `shared` | `Bool` | true with logins off (one queue for everyone). |
| `kept` | `KeptQueue?` | only when `changed_by == "deadwax"`, a record exists and `tracks` is non-empty. |

`KeptQueue` (play_queue.py:102 `kept_view`; store.py:3190): `rev: Int`, `ids_rev: Int`, `ids: [String]`,
`index: Int`, `position: Double` (SQLite REAL - may come as `12.0`), `snapshot: String?`, `device: String`,
`label: String`. All required.

Empty / break-glass answer (exact, tests `test_an_empty_navidrome_queue_is_answered_as_one`,
`test_the_break_glass_admin_keeps_no_queue_and_asks_nothing`):
`{"tracks": [], "index": null, "position": 0, "changed_by": "", "shared": <logins off>, "kept": null}`.

Errors: 401 (session gone, or Navidrome refused the login: `auth.LOGIN_GONE`, test
`test_navidrome_refusing_the_login_ends_the_session_and_writes_nothing`); Navidrome failing: `_fail`
(navidrome.py:109) passes `NavidromeError.status` (502 by default). The record failing to read is NOT an error: 200
with `kept: null` (test `test_the_record_failing_to_read_still_answers_navidromes_queue`). The GET is read under
the user's save lock (navidrome.py:1416), so it never sees a save half written.

### 3.2 `POST /deadwax/navidrome/queue` - a full save (navidrome.py:1309-1333 `QueueSave`, :1431-1456)

Body, `extra="forbid"` (an undeclared key is a 422):

| field | type | rule (a breach is a 422) |
| --- | --- | --- |
| `ids` | `[String]` | 1...2000 items, each 1...256 chars; duplicates kept, order kept |
| `index` | `Int` | `>= 0` and `< ids.count` ("The song playing isn't in the queue sent") |
| `position` | `Double` | `0...86400`, finite (`allow_inf_nan=False`) |
| `device` | `String` | `^[A-Za-z0-9_-]{8,64}$` |
| `label` | `String` | `^[A-Za-z0-9 ]{1,40}$` |
| `snapshot` | `String?` | default null; at most 262,144 code points; must be JSON (`"The queue's account isn't JSON"`), an object (`"... isn't an object"`), with `v` exactly `1` and not a bool (`"The queue's account isn't one deadwax knows (v 1)"`); over the cap: `"The queue's account is over 262144 characters"` (play_queue.py:74-89) |

Answer 200 `{"rev": Int, "ids_rev": Int}` (both equal: `ids_rev = rev`, store.py:3201-3213); break-glass
`{"rev": null, "ids_rev": null}` with nothing asked or written. Navidrome is written FIRST (savePlayQueueByIndex as
a form: `id` repeated, `currentIndex`, `position` = `round(position*1000)` ms - play_queue.py:92), then the record;
a Navidrome failure leaves the record as it was.

Errors: 401; 422 `{"detail": <words>}` - always a string, never FastAPI's list (navidrome.py:991
`validation_words`; app.py:491): a validator's own words, else `QUEUE_FORM` "deadwax couldn't read that queue - the
player sent something it doesn't take"; 502 (Navidrome); 503 `NO_RECORD` "deadwax can't keep your queue just now -
its database isn't available" (no store, or the record write failed; Navidrome NOT written when the store is
missing - test `test_without_its_database_a_save_says_so_and_navidrome_is_not_written`).

### 3.3 `POST /deadwax/navidrome/queue/at` - a position save (navidrome.py:1336-1346 `QueueAt`, :1459-1497)

Body, `extra="forbid"`: `ids_rev: Int (>= 1)`, `index: Int (>= 0)`, `position: Double (0...86400, finite)`,
`device`, `label` (patterns as above). **Exactly these five keys** - `"snapshot": null` or `"ids"` is a 422
(test `test_a_position_save_out_of_bounds_or_with_more_is_a_422`, `{"snapshot": None}` among its cases).

- No record, or `record.ids_rev != ids_rev` -> **409** `QUEUE_CHANGED` "The queue changed on another device or in
  another app", nothing written anywhere (test `test_a_stale_ids_rev_or_no_record_is_a_409_that_writes_nothing`).
- `index >= record.ids.count` -> **422** `NOT_IN_QUEUE` "That song isn't in the queue deadwax kept".
- Else savePlayQueueByIndex with the RECORD's ids, then `move_play_queue` (store.py:3215: index, position, device,
  label moved; `rev + 1`; ids and snapshot unchanged). Answer `{"rev": rev+1, "ids_rev": <unchanged>}`;
  break-glass `{"rev": null, "ids_rev": null}`. 401 / 502 / 503 as for a full save.
- **Consequence for reading**: after a position save, `kept.index` differs from the index the snapshot was made at.
  The snapshot holds no index (its marks run with the entries), so `fromSnapshot(..., kept.index, ...)` is right -
  verified: a snapshot made at index 1, kept.index 3 -> exact, the account back at index 3.

### 3.4 Swift models

Name the decoded properties exactly as the JSON (`changed_by`, `ids_rev`), as `SignInBody` does, so
test_ios_contract.py's `required_fields()` regex can read them; no CodingKeys.

```swift
public struct QueueAnswer: Decodable { public let tracks: [Song]; public let index: Int?; public let position: Double
  public let changed_by: String; public let shared: Bool; public let kept: KeptQueue? }
public struct KeptQueue: Decodable, Equatable { rev: Int; ids_rev: Int; ids: [String]; index: Int; position: Double
  snapshot: String?; device: String; label: String }
public struct QueueSaveBody: Encodable { ids: [String]; index: Int; position: Double; device: String; label: String
  snapshot: String? }   // nil may be omitted (server default) or sent as null - both taken
public struct QueueAtBody: Encodable { ids_rev: Int; index: Int; position: Double; device: String; label: String }
public struct SavedQueue: Decodable { rev: Int?; ids_rev: Int? }
```

`Song` is Phase 0's (Models.swift) - every field but `id` optional; it already decodes `samplingRate`,
`bitDepth`, `channelCount`. **Clamp every position sent** to `0...86400` and to 0 for NaN/inf: the web doesn't
(it can't produce one), but a 422 on a position save is read as "save in full", which would 422 again.

### 3.5 A song of the answer as a queue entry: `shuffledTrack` (useShuffleFeed.ts:23 -> api.ts:621 `toQueueTrack`)

`shuffledTrack(song) = toQueueTrack(song, {id: song.albumId ?? "", name: song.album ?? ""})`, so:
`id`; `title = song.title` (port: `?? ""` - Navidrome always sends one; TS would carry `undefined`); `artist =
song.artist ?? ""`; `album = song.album ?? ""`; **`albumId = song.albumId ?? ""` (empty string, not nil)**;
`coverArt = song.coverArt` (nil when absent); `duration = song.duration ?? 0`; `contentType`, `suffix` as sent (nil
when absent); `sampleRate = samplingRate ?? 0`; `bitDepth ?? 0`; `channels = channelCount ?? 0`; no `level`.
Pinned: playqueue.sim.cjs:308-317 (toQueueTrack's 0s and fallbacks).

## 4. Snapshot v1 - the exact JSON

### 4.1 The object (resume.ts:109-122 `SnapshotV1`, written ONLY by `toSave`, read ONLY by `fromSnapshot`)

Keys, in this order (the order `made` is built in, resume.ts:171-184):

| key | JSON | meaning |
| --- | --- | --- |
| `v` | `1` | version |
| `levels` | string, one char per WINDOW entry | `a` album, `t` track, `-` none (resume.ts:124) |
| `marks` | `[[key, from, at, pass], ...]`, one per window entry | `from`: `"s"` source, `"a"` added, `"o"` one (resume.ts:126); the marks sliced `[start, end)`, keys NOT renumbered |
| `source` | `[id, ...]` | the WHOLE source list by id (never windowed) |
| `sourceLevels` | string, one char per source item | as `levels` |
| `extra` | `{id: song}` | the whole song, without level, ONLY for source songs whose id is in no window entry; first occurrence wins |
| `shuffle` | bool | |
| `nextKey` | int | |
| `startedAt` | int | `max(0, state.startedAt - start)` |
| `left` | `[[pass, at], ...]` | as is |
| `paged` | object | ONLY when present: `{"token", "total", "fetched", "scope", "level"?}` - `level` omitted when nil |
| `pagedRounds` | `[{"pass": int, "paged": {...}}]` | ONLY when present (an empty array is written as `[]`) |

An `extra` song (resume.ts:129 `bare`): `{"id","title","artist","album","albumId","coverArt","duration",
"contentType","suffix","sampleRate","bitDepth","channels"}` in that order. **`albumId`, `coverArt`, `contentType`,
`suffix` are written as `null` when nil - never omitted**: the web's `readSong` (resume.ts:206) refuses `undefined`
there, and one refused song makes the whole snapshot fall back to a plain list. Conversely **`paged.level`, `paged`
and `pagedRounds` must be OMITTED when nil - never `null`**: `readPaged` (resume.ts:214) and `fromSnapshot`
(resume.ts:293, :299) refuse a `null` there (run: a `"level":null` paged -> `fromSnapshot` null). Swift's
synthesized `Encodable` gets both wrong (it omits every nil) - hence the hand-written writer (4.3).

### 4.2 Examples, made by the TS (run on 2.1.0's resume.ts)

An album of 3 queued as an album, tapped at song 2, Play Next of one song at track level, position 61.5:

```
toSave -> {"ids":["1","2","x","3"],"index":1,"position":61.5,"start":0,"snapshot":
{"v":1,"levels":"aata","marks":[[0,"s",0,0],[1,"s",1,0],[3,"a",-1,-1],[2,"s",2,0]],"source":["1","2","3"],
 "sourceLevels":"aaa","extra":{},"shuffle":false,"nextKey":4,"startedAt":1,"left":[]}}
```

Repeat One over a 2-song list (Normalization Off - no levels): ids `["1","1","1","2"]`, marks
`[[0,"s",0,0],[2,"o",0,0],[3,"o",0,0],[1,"s",1,0]]`, levels `"----"` (a copy's `at` is its original's place).

A library shuffle page: `...,"left":[],"paged":{"token":"tok","total":9,"fetched":2,"scope":"yours","level":"track"}}`
with `"shuffle":true`.

A kept-whole song: `"extra":{"s1":{"id":"s1","title":"song s1","artist":"A/B","album":"Mezzanine","albumId":null,
"coverArt":null,"duration":200.5,"contentType":"audio/flac","suffix":"flac","sampleRate":44100,"bitDepth":16,
"channels":2},...` - note `A/B` with no escaped slash.

### 4.3 Writing and reading JSON in Swift

**Writer** - make the phone's snapshot byte-identical to JSON.stringify's for the same queue (then the web reads the
phone's exactly as its own, the cap is judged identically, and traces compare strings):

1. Keys in the orders of 4.1; omit / null exactly as 4.1 says.
2. Strings: escape `"` -> `\"`, `\` -> `\\`, U+0008 `\b`, U+000C `\f`, U+000A `\n`, U+000D `\r`, U+0009 `\t`, any
   other U+0000-U+001F as `\u00xx` (lowercase hex); everything else raw - **no `\/`** (JSONEncoder writes `\/` by
   default), no escaping of non-ASCII, U+2028/2029 or U+007F.
3. Numbers: ints as ints; a Double that is integral and below 1e21 in magnitude as an integer (`200`, not `200.0`);
   otherwise the shortest round-trip digits (Swift's `description`), with an exponent written JS's way (`1e-7`,
   `1e+21`; Swift says `1e-07`). Only `duration` is ever a non-integer in practice.
4. `extra`'s key order: JS puts **array-index keys** (canonical decimal of an integer 0...4294967294: `"0"`, `"52"`,
   not `"01"`, `"-1"`) first in ascending numeric order, then the rest in insertion order. Verified: a source of ids
   `"60"` down to `"52"` outside the window serialises as `"extra":{"52":...,"53":...}`. Real Navidrome ids never are
   array indexes, but the traces' ids are (`'1'`, `'2'`); do it (10 lines) so string equality holds.

**Reader** - parse into an enum `JSONValue { null, bool, number(Double), string, array, object([String: JSONValue]) }`
(JSONDecoder single-value container, trying Bool before Double, so `1` never reads as `true` nor `true` as `1`;
JSONSerialization would blur them through NSNumber). Then check by hand, exactly as the TS:

- `isInt(x)`: a number with an integral value - **`1.0` counts** (run: `"v":1.0` and a mark key `1.0` both read
  back). Convert with `Int(exactly:)`; a number beyond Int64 is refused (TS would take it; no writer makes one).
- `isObject`: a JSON object (not null, not an array). `nullableString`: null or a string. A missing key is NOT null.
- `levels` / `sourceLevels` are compared and indexed in UTF-16 units (`levels.utf16`), `a` (0x61) album, `t` (0x74)
  track, anything else none (`charLevel`, resume.ts:125).

## 5. The pure functions (resume.ts), as the port must behave

`utf8Length` (resume.ts:62) is not needed (it served keepalive's byte budget). `deviceLabel` (:403) is not ported
(the phone's label is a constant, section 8).

### 5.1 `windowOf(count, index)` (:138) - also play_queue.py:55 `window`

`count <= 0` -> (0, 0). `at = min(max(index, 0), count - 1)`; `start = max(0, at - 50)`; `end = min(count, start +
2000)`. Table (sim 290, py `test_the_window_is_fifty_before_and_two_thousand_in_all`): (10,3)->(0,10);
(5000,0)->(0,2000); (5000,100)->(50,2050); (2500,2200)->(2150,2500); (3000,9999)->(2949,3000); (0,0)->(0,0).

### 5.2 `toSave(queue, position) -> Saving {ids, index, position, snapshot: String?, start}` (:161-187)

1. `(start, end) = windowOf(tracks.count, queue.index)`; `entries = tracks[start..<end]`; `ids` their ids;
   `index = queue.index - start`.
2. No `upNext` -> `snapshot = nil` (a plain queue has no account).
3. `inWindow = Set(ids)`. For each source song in source order: if its id is not in `inWindow` and not yet in
   `extra`, `extra[id] = bare(song)`.
4. Build 4.1's object (marks sliced `[start, end)`, `startedAt = max(0, startedAt - start)`, `left` as
   `[pass, at]`, paged / pagedRounds only when present).
5. `snapshot = text.utf16.count <= 262_144 ? text : nil`.

`start` is returned because the controller numbers later position saves inside that window.

### 5.3 `relevel(level, setting)` (:191)

off -> nil; song -> track; album -> album; auto -> `level ?? track`. Table (sim 379):
off: nil,nil,nil; song: track x3; album: album x3; auto: album, track, track (for album, track, nil).

### 5.4 `readSong(value, id)` (:202) and `readPaged(value, setting)` (:211)

- readSong: an object; `value.id == id`; `title`, `artist`, `album` strings; `albumId`, `coverArt`, `contentType`,
  `suffix` null-or-string (present); `duration`, `sampleRate`, `bitDepth`, `channels` finite numbers. Returns the
  12 fields only (other keys dropped). Port note: rate/bits/channels are Int in Swift - take a non-integral finite
  value truncated toward zero (TS keeps it; no writer makes one).
- readPaged: an object; `token` string; `total`, `fetched` ints; `scope` `"yours"` or `"store"`; `level` absent,
  `"album"` or `"track"` (null refused). Result `{token, total, fetched, scope, level: relevel(level, setting)}` -
  so **a paged saved with no level reads as `track` under Automatic** (run: confirmed), and has none under Off.

### 5.5 `savedLevels(snapshot, count)` (:220)

Parses; if an object with `v == 1` and `levels` a string of exactly `count` UTF-16 units -> its levels by
`charLevel`; anything else (nil, not JSON, wrong length) -> `count` nils. Never throws.

### 5.6 `fromSnapshot(snapshot, tracks, index, setting) -> UpNextQueue?` (:239-313)

`tracks` are Navidrome's songs for the window entries in order (already `shuffledTrack`ed). Returns nil when:

1. `snapshot` nil, not JSON, not an object, or `v != 1`.
2. `levels` not a string of `n = tracks.count` units; `marks` not an array of `n`; `source` not an array of
   strings; `sourceLevels` not a string of `source.count` units; `extra` not an object; `shuffle` not a bool;
   `nextKey` / `startedAt` not ints; `left` not an array.
3. `index` not in `0..<n`, or `startedAt < 0`. (**`startedAt` may be past `index`** - Previous back before where
   playTracks began; review finding, sim 338-351.)
4. Songs: Navidrome's (by id, bare) where the id is in `tracks`, else `readSong(extra[id], id)`; each entry is
   `song(tracks[i].id, levels[i])`, each source item `song(source[j], sourceLevels[j])`, its level
   `relevel(charLevel(c), setting)` (nil -> no level). Any entry or source song unresolved -> nil.
5. Marks, in order, each: an array of exactly 4; `key`, `at`, `pass` ints; `0 <= key < nextKey`; key unique;
   `from` char `s`/`a`/`o`; `s`: `0 <= at < source.count` AND `source[at].id == entries[i].id` AND `pass >= 0`;
   `a`: `at == -1` AND `pass == -1`; `o`: `-1 <= at < source.count` (pass unchecked).
6. `left`: each an array of exactly 2 ints -> `{pass, at}` (no bounds).
7. `paged` present -> must `readPaged`; `pagedRounds` present -> an array, each an object with int `pass` and a
   valid `paged`.

Result: `{tracks: entries, index, upNext: {marks, source, shuffle, nextKey, startedAt, left, paged?, pagedRounds?}}`.
The web shares one object per (id, level) between entries and source (:259-269); with Swift values, equal values
suffice (the sim's "one object per (id, level)" check has no Swift counterpart).

### 5.7 `plain(tracks, index, levels, setting)` (:317) and `same(a, b)` (:325)

`plain`: each track re-levelled `relevel(levels[i], setting)` (index past `levels` -> nil -> `track` under auto),
then `startUpNext(levelled, index)`: unshuffled, `index` clamped, `startedAt = index`, marks `{key i, source, at i,
pass 0}`, `nextKey = n`, `left []`, no paged. `same`: equal length and ids equal in order.

### 5.8 `resumed(answer, tracks, setting, deviceId) -> Resumed?` (:352-397)

`Resumed { queue, position, from: PickedFrom?, exact: Bool }`, `PickedFrom = .device(label) | .app(name)`.
`tracks = answer.tracks.map(shuffledTrack)`; `ids` theirs; `n = ids.count`.

- `n == 0` -> nil (another app may have cleared it: Navidrome is the authority).
- `keptFrom = (kept != nil && kept.device != deviceId) ? .device(kept.label) : nil`.
- **Exact**: `kept` and `same(ids, kept.ids)` and `kept.index == answer.index` (an `Int?` - nil never equals) ->
  `exact = true`; `queue = fromSnapshot(kept.snapshot, tracks, kept.index, setting) ?? plain(tracks, kept.index,
  savedLevels(kept.snapshot, n), setting)`; `position = kept.position`; `from = keptFrom`.
- **Dropped**: `survivors = kept.ids.filter { idsSet.contains($0) }`; if `survivors.count < kept.ids.count` and
  `same(survivors, ids)`: `levels = savedLevels(kept.snapshot, kept.ids.count)` filtered to present ids;
  `at = clamp(kept.index, 0, kept.ids.count - 1)`; `before` = present ids in `kept.ids[0..<at]`; if `kept.ids[at]`
  present -> `index = before`, `position = kept.position`; else `index = before < n ? before : n - 1`, `position =
  0`. `queue = plain(tracks, index, levels, setting)`; `from = keptFrom`; `exact = false`.
- **Anyone else's**: `said = answer.index`; `index = said == nil ? 0 : clamp(said, 0, n - 1)`;
  `position = said == index ? answer.position : 0`; `queue = plain(tracks, index, [], setting)`;
  `from = kept != nil && same(ids, kept.ids) ? keptFrom : (changed_by != "" && changed_by != "deadwax" ?
  .app(changed_by) : nil)`.
- **Played to its end**, then, on the result: `track = current(queue)`; if `track.duration > 0 && position >=
  track.duration - 1`: move to `index + 1` if there is one; `position = 0` either way.
- Return `position = max(0, position)`.

### 5.9 `pickedUpWords(from, shared)` (:416) - the words, verbatim

nil -> nil. `.app(name)` -> `"Picked up from \(name)"`. `.device(label)` -> `"Picked up from \(whose) \(label)"`,
`whose` = `"your"` unless `shared`; shared: `"an"` if the label starts with a vowel (`/^[aeiou]/i`), else `"a"`.
Sim 402: `Picked up from your Mac`, `Picked up from a Mac`, `Picked up from an iPhone`, `Picked up from an Android
phone`, `Picked up from Symfonium` (shared or not), nil.

### 5.10 `changedSince(saved, queue, position)` (:450) and `saveDue(...)` (:470-484)

`SaveBaseline { tracks, upNext, index, position, start, count }`; `SaveClock { saved: SaveBaseline?, idsRev: Int?,
countFrom: Int64?, changedAt: Int64?, failedAt: Int64? }` (ms). `SaveTrigger = wait | position | pause | hidden`.

changedSince: `saved == nil || queue.tracks != saved.tracks || queue.upNext != saved.upNext` -> `.songs`;
`queue.index != saved.index` -> `.song`; `|position - saved.position| > 1` -> `.position`; else nil. (TS compares
the two by object identity; Swift by value - see 6.1.)

saveDue(clock, queue, position, playing, now, trigger) -> `.full | .at | nil`:

1. `current(queue) == nil` -> nil.
2. `failedAt != nil && now - failedAt < 30_000` -> nil.
3. `change = changedSince(...)`; nil -> nil.
4. `at = change != .songs && idsRev != nil && saved != nil && saved.start <= queue.index < saved.start +
   saved.count`; `kind = at ? .at : .full`.
5. `trigger` pause or hidden -> `kind`.
6. `since = changedAt == nil ? +inf : now - changedAt`.
7. `.songs` -> `since >= 2000 ? .full : nil`. `.song` -> `since >= 1000 ? kind : nil`.
8. `.position`: not playing -> `trigger == .wait ? kind : nil`; playing -> `trigger == .position && (countFrom ==
   nil || now - countFrom >= 30_000) ? kind : nil`.

Pinned by sim 410-438 (table in 9.1).

## 6. The controller (port of app/useResume.ts)

### 6.1 Identity becomes equality

The web compares `queue !== was`, `parked.queue === queue`, `queue !== asked`, `queue.tracks !== saved.tracks`,
`queue.upNext !== saved.upNext` by object identity; Up Next's edits hand back the same object when nothing changes,
so identity there means "the same queue". In Swift compare `UpNextQueue` / `[QueueTrack]` / `UpNextState?` with
`==` (Array's `==` returns at once for shared storage). A difference only for an edit that ends exactly where it
began, which then counts as no change - harmless.

### 6.2 State (useResume.ts:80-111)

`device`, `label`; `queue: UpNextQueue?` and `playing` as last observed; `clock: SaveClock` (all nil);
`lastRev: Int?` (the rev this device last saved or took); `shared: Bool?` (as the last GET said); `parked:
(queue, position)?` (put back, untouched); `taken: String?` (signature of the answer last put back); `askedAt`
(-inf); `flying: Int`; `said: (from: String, ids: String)?`; `owed: Set<SaveTrigger>`; `off: Bool`;
`signedOutUnder: Int?` (a session generation); two timers `fullWait`, `atWait`; two latest-only guards, `asks` and
`albums` (only the newest GET's answer is used - CLAUDE.md's rule).

### 6.3 Events in, and what each does

**observe(queue, playing)** - called synchronously whenever the engine's queue or play state changes
(useResume.ts:302 `render`; the web reads during render because an effect may wait for a frame a locked phone never
draws - on iOS call it from the model's `didSet`). First call only records. Then: if `parked` and (queue != parked
queue or playing) -> `parked = nil`. If the queue changed: `changedAt = now`; arm `wait(changedSince(saved,
queue, position) == .songs ? .full : .at)` - judged against the last SAVE, not the last observation (sim 1056-1058,
review 7e). Playing started -> `countFrom = now` (the 30 s count from playing starting, sim 1021-1023). Playing
stopped -> on the next turn `consider(.pause)` (a pause, the queue's end, a stop).

**position(seconds)** (:292 `onPosition`) - the engine's position reports: the app's 0.5 s ticker while playing,
and **every seek, paused or parked, too**. If `parked` and `|seconds - parked.position| > 0.5` -> `parked = nil`
(a scrubbed put-back queue is no longer "merely put back", sim 1071-1077). Then on the next turn: playing ->
`consider(.position)`; else if `saved` and `|position() - saved.position| > 1` -> `wait(.at)`. The 30 s saves are
counted by these reports, never by a timer of their own (sim 648-651).

**background** (web: `visibilitychange` hidden and `pagehide`, :321-325) -> `consider(.hidden)`.

**foreground** (web: visible, `pageshow`; NOT the focus grace) -> `front()`.

**start** (web `mount`, :320-349) - once the person is signed in (or logins are off): if the queue is empty ->
`ask(.open)`. **stop** (sign-out, a sign-in as someone else): drop pending answers (`asks`/`albums` superseded),
cancel the timers, discard the controller.

### 6.4 The functions (useResume.ts line by line)

- `wait(kind)` (:117): re-arm the kind's own timer (full: 2000 + 50 ms; at: 1000 + 50) to `consider(.wait)`.
- `consider(trigger)` (:127): return if `off` or no queue. If `signedOutUnder != nil`: return while the session
  generation still equals it, else clear it. `due = saveDue(clock, queue, position(), playing, now, trigger)`;
  nil -> return. If `flying > 0 && trigger != .hidden` -> `owed.insert(trigger)`, return. Else `send(due, queue,
  position, leaving: trigger == .hidden, now)`.
- `send(.at)` (:184-199): requires `saved` and `idsRev` (without them it sends in full, as the TS falls through). Body `{ids_rev: idsRev, index: queue.index - saved.start,
  position, device, label}`. `flying += 1`; on answer `answered(baseline: {queue.tracks, queue.upNext, queue.index,
  position, saved.start, saved.count}, answer, sentAt: now, full: false)`; on error `refused(error, position:
  true)`; always `settled()`.
- `send(.full)` (:200-212): `made = toSave(queue, position)`; body `{ids: made.ids, index: made.index, position,
  device, label, snapshot: made.snapshot}`; `flying += 1`; baseline `{tracks, upNext, index, position, start:
  made.start, count: made.ids.count}`; `full: true`.
- `answered(baseline, answer, sentAt, full)` (:145): `answer.rev == nil` -> `off = true` (break-glass: no saving for
  the controller's life), return. Else `saved = baseline`, `failedAt = nil`, `countFrom = sentAt`, `lastRev =
  answer.rev`, and if `full`, `idsRev = answer.ids_rev`.
- `refused(error, position)` (:159): **401** (`DeadwaxError.signedOut`) -> `signedOutUnder = generation`, return
  (no `failedAt`). A position save refused **409 or 422** -> `idsRev = nil`, `owed.insert(.pause)` (a full save at
  once once it settles), return. Anything else (unreachable, 502, 503...) -> `failedAt = now`.
- `settled()` (:173): `flying -= 1`; if still flying or nothing owed, return; take the owed triggers in the order
  pause, wait, position; clear `owed`; `consider` each until one sends (then stop - the rest are dropped, so a
  save already made isn't made twice; resume.sim caught a double send on a slow network).
- `newer(answer)` (:216): kept -> `kept.device != device && kept.rev > (lastRev ?? 0)`; else `changed_by != "" &&
  changed_by != "deadwax"`.
- `signature(answer)` (:75): kept -> `"kept:\(rev)"`, else changed_by, index, position and the ids joined -
  internal only, any stable format.
- `take(answer, why)` (:221-262): `back = resumed(answer, answer.tracks.map(shuffledTrack), normalization (read
  now), device)`; nil -> return. `untouched = parked != nil && parked.queue == queue`. If `why == .front`: return if
  `signature == taken`; return if `current(queue) != nil && !untouched && (answer.shared || !newer(answer))`.
  `put = engine.restoreQueue(back.queue, back.position)`; nil -> return. Then: `taken = signature`;
  `parked = (put, engine.position())`; `saved = {put.tracks, put.upNext, put.index, that position, start: 0, count:
  put.tracks.count}` (**a queue merely put back is the baseline: nothing is saved for it**); `idsRev = (kept != nil
  && back.exact && put's ids == kept.ids) ? kept.ids_rev : nil` (fitting to this device's Repeat can change the ids -
  then the first save is full, sim 1005-1010); `changedAt = failedAt = countFrom = nil`; `lastRev = kept?.rev` when
  kept; cancel both waits. The notice: `from = back.from` as a stable string; `songs` = put's ids joined; `again =
  why == .front && untouched && said?.from == from && said?.ids == songs`; unless `again`, show
  `pickedUpWords(back.from, answer.shared)` when non-nil; `said = from == nil ? nil : (from, songs)`. The album:
  if `current(put).albumId` is non-empty and the app doesn't already hold that album's answer, ask
  `GET /navidrome/albums/{id}` (latest-only) and keep it for Info only if that song is still current when it lands
  (sim 529-532, 574) - only if Phase 1's Info / Now Playing keep album answers as the web's tap does; else skip it.
- `ask(why)` (:264): `asked = queue`; `askedAt = now`; GET. On answer (newest only): `shared = answer.shared`;
  drop it if `queue != asked || playing` (a tap since wins, sim 562, 809); else `take`. On failure: nothing
  (asked again at the next foreground, at most every 15 s).
- `front()` (:279): return if no queue or `playing`; return if `now - askedAt < 15_000`; if the queue has a song and
  `changedSince(saved, queue, position()) != nil` -> `consider(.pause)` (unsaved changes are saved, nothing asked),
  return; if the queue has a song, isn't untouched and `shared == true` -> return (logins off: a paused player never
  takes somebody else's, nor asks once it knows); else `ask(.front)`.

### 6.5 iOS mapping and deliberate differences

| web | phone |
| --- | --- |
| `render` per drawing; `later()` = a microtask | `observe` from the model's didSet; "next turn" through the injected scheduler at 0 ms (tests stay deterministic) |
| `timeupdate` / seek `report` -> onPosition | the 0.5 s ticker while playing (it runs while locked and playing: the app isn't suspended), and every seek |
| hidden + pagehide | `scenePhase == .background` |
| visible / pageshow | `scenePhase == .active` (not the launch's first; `askedAt` stops a double ask anyway) |
| focus + RESUME_FOCUS_GRACE_MS | **none** - a foregrounded app shows before a tap can land |
| `sendBeacon` / `keepalive` / BEACON_MAX / utf8Length | **none** - ordinary requests, each wrapped in `UIApplication.beginBackgroundTask` (ended when it settles or expires) so a pause's save gets out before iOS suspends the paused app |
| a leaving `at` save is taken as saved at once (no answer read) | **sent and answered normally**, counted in `flying` - as the web's leaving full save is. A `.hidden` save is still sent even while another is out (the server serialises per user) |
| `currentSession()` (api/http.ts:94) | `AppModel.sessionGeneration`, +1 at each successful sign-in |
| sign-out reloads the page; signing in as someone else reloads (signIn.ts:66 `afterSignIn`) | sign-out: stop, clear the queue, discard the controller; sign-in as a different user than before: the same; the same user again: carry on, generation + 1 |
| `readPlayerNormalization()` | the phone's Normalization setting, read at each `take` |
| `sayPins(words)` | the app's one notice line |
| `Date.now()` | an injected ms clock (monotonic is fine: only differences are used) |

Not ported: the web's `latestOnly` signal plumbing beyond "newest answer only"; `utf8Length`; `deviceLabel`.

## 7. The engine's `restoreQueue(queue, position) -> UpNextQueue?` (usePlayer.ts:1680-1706; notes/app.md)

- **Refuses (nil)** while the listener means music to play, the engine plays, or a retry is pending.
- Fits the queue to **this device's Repeat**: `toppedUp(withRepeat(queue, repeat), repeat)`; nil if it then has no
  current song. Repeat is per device and never saved; **Shuffle travels in the snapshot** (`upNext.shuffle`); a
  plain list comes back unshuffled; a library shuffle comes back with `shuffle: true` and its `paged`.
- Lets go of whatever a paused queue held (sources, standby, fetches); clears a held edit and a pending seek.
- Parks: the queue shown, its song at `position` held to the song (`duration > 0 ? min(position, duration) :
  position`; below 0 or not finite -> 0), **nothing loaded, fetched or played**, the audio session not activated
  (Phase 0: active at the first play). Lock-screen info may be set paused; iOS shows nothing until something plays.
- The engine's `position()` then answers the parked second; a seek moves it (and reports it, 6.3) without loading;
  Previous / Next / a tapped Up Next row work as on any paused queue.
- Play (in the tap, the remote command included) starts the current song from the parked second through the
  ordinary path (`StartPoint` in seconds - Phase 0's seek rule, right at any rate).
- Returns the fitted queue (the controller's baseline).

## 8. How the phone identifies itself

- **Device id**: 16 characters, each `ALPHABET[byte & 63]` with `ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"` over 16 bytes from
  `SystemRandomNumberGenerator` - the web's rule (persisted.ts:315-335). Kept in `UserDefaults` under
  **`deadwax-player-device`** (the web's key name); on read, a value failing `^[A-Za-z0-9_-]{8,64}$` is made again
  and stored. It survives install.sh's install-over (app data stays) and a sign-out; a deleted app is a new device.
  Core holds `DeviceID.make(using:)` and `DeviceID.isValid(_:)`; the app holds the storage. Not
  `identifierForVendor` (UIKit, can be nil before first unlock) and not the phone's name (private; iOS 16+ answers
  "iPhone" anyway).
- **Label**: the constant **`"iPhone"`** - what the web's `deviceLabel` says for Safari on an iPhone, inside
  `LABEL_PATTERN`, and a vowel: the web shows "Picked up from your iPhone", logins off "Picked up from an iPhone".
- Navidrome's `changedBy` for the phone's saves is `deadwax` (the server's own `c`), so the web believes the
  phone's record as its own kind, and vice versa.
- The phone and Safari's web app on the same phone are two devices (two ids, same label): switching between them
  shows "Picked up from your iPhone" once.

### Logins off, and the break-glass admin

- **Logins off**: everything is `local`'s record and the shared account's Navidrome queue; GET answers `shared:
  true`. The open (empty queue) takes whatever anyone played last ("Picked up from a Mac"); a queue put back and
  untouched takes a newer one on foreground; a paused, touched queue never takes one and, once `shared` is known,
  never asks (`front`, `take`; sim 840-859). Py: `test_with_logins_off_it_is_locals_and_the_shared_accounts_one_queue`.
- **Break-glass** (`_keeps_no_queue`, navidrome.py:1387: logins on AND asking as the shared account - the
  `deadwax` user, auth.py:99): GET answers the empty queue (`resumed` -> nil, nothing put back); every save answers
  `{rev: null, ids_rev: null}` -> `off` for the controller's life (sim 717-731). No special-casing by user name: go
  by the answers, as the web does.

## 9. Tests to mirror

### 9.1 DeadwaxCore, pure (Swift Testing; mirror each resume.sim check by its line)

| sim line(s) | check |
| --- | --- |
| 169-267 | round trip toSave -> fromSnapshot over seeded runs, the invariant kept, Previous before startedAt (traces, section 10) |
| 276 | 5,000-song list from its first: 2,000 ids, start 0, index 0, snapshot nil (over the cap), ids[1999] == "2000" |
| 281 | playing the 101st of 2,500 (`startUpNext(album(2500), 30)` then index 100): start 50, 2,000 ids, index 50, ids[50] "101", startedAt 0, 2,000 marks, marks[0] = [50,"s",50,0] |
| 284 | ...`extra` has 500 songs, has "1" and "2051", not "51"; extra["1"].title "song 1"; no `level` key |
| 288-290 | a 20-song list at 5: all of it (startedAt 5); a plain queue -> nil snapshot; the window table |
| 309-313 | exact: account back (`added` mark at 3, levels a,a,a,t,a,a), from this device nil; another device -> `.device("iPhone")` |
| 328 (loop 314-327) | each of 10 broken snapshots (not JSON, v2, a mark out of its source, a key twice, startedAt -1, an added mark with a place, a copy's mark past the list, an extra song with duration "200" / no title / albumId 7) -> exact, plain list, same ids, index 2, position 61, all marks source, startedAt 2 |
| 338 | the same snapshot with a valid extra song "z": the account back, source ends with z at level album |
| 347-351 | Previous before startedAt (album at song 5, Play Next, Previous): back at index 3, startedAt 4, marks keep the added one; under Repeat All the source stays 10 long |
| 354-360 | songs dropped: playing one survives (index 1, kept.position, levels carried); it's gone (the next survivor at 0); the last gone (the last survivor at 0) |
| 363-374 | another app's at its index (levels track, shuffle off, from `.app`); index past end -> last at 0; index null -> first at 0 (Off: no levels); deadwax with no record -> from nil; ids equal at another index -> plain at Navidrome's, from the label; empty -> nil; played to its end -> next at 0; last song -> it at 0 |
| 379-389 | relevel table; entries, source and paged level re-levelled together under each setting; Off leaves no level |
| 402 | pickedUpWords table (398, deviceLabel: not ported) |
| 416-438 | saveDue: untouched -> nil for every trigger; empty -> nil; songs changed 1,999 ms nil / 2,000 full / pause & hidden full at once; song change 999 nil / 1,000 at / no idsRev full / outside the window full; playing 29,999 nil / 30,000 at / a wait alone never; paused scrub: wait -> at, position -> nil, < 1 s -> nil; pause / hidden -> at; failed 29 s nil, 30 s at; fresh page -> full |

### 9.2 DeadwaxCore, the controller (virtual clock and fake server, as resume.sim's hook section)

Mirror: 526-540 (open: one GET, put back paused, notice once, album asked and kept, then 2 minutes + background /
foreground saves nothing); 546 (own queue: no notice); 562 (a tap before the answer wins); 574 (album not kept when
another song shows); 588-633 (a tap: nothing at 1.75 s, one full save at 2 s with ids/index/device/label/snapshot;
nothing for 20 s; a position save at 30 s against ids_rev; a song change saved 1 s after, not at once; a pause at
once at its second; nothing paused for 60 s; a paused scrub saved 1 s after; two edits a second apart -> one full
save 2 s after the second); 648-651 (90 s playing with no report: no save; the next report saves); 667-674 (one
request at a time; a 409 -> a full save of the queue as it is); 717-731 (401 stops until another generation; no rev
stops for good, foreground included); 748-818 (foreground: failed open not re-asked within 15 s, asked after; put
back and untouched takes a newer save, said; the same answer not taken or said twice; paused after playing takes
only another's newer save, logins on; a newer save of its own (unread rev) kept; never while playing; an answer
dropped when a tap changed the queue meanwhile; another app's taken, said by name); 840-859 (logins off: never
taken, then not asked; unsaved changes saved instead of asking); 916-934 (the same pick-up followed silently, other
songs said again, another device said); 953 (picked up, played here, the same device again: said again); 1005-1010
(a Repeat One record under Repeat off: a song change saved in full); 1021-1023 (30 s from playing starting);
1040 (a 422 -> full save at once); 1056-1058 (paused edit then Next: one full save 2 s after the Next);
1071-1077 (a scrubbed put-back queue not replaced by its own newer save).

**Not mirrored**: 891-900 (focus grace), 968-970 (keepalive by bytes, utf8Length), 986-994 (two keepalives), 1102-1142
(the browser's device id, keepalive fetch, sendBeacon). The leaving checks at 691-702 become: background while
playing sends the position save at once, an ordinary request; an edit then background sends a full save at once.
Add: the device id rule (16 from the alphabet, kept, remade when invalid) and the label against LABEL_PATTERN.

### 9.3 Python (server, unchanged) and the contract test to add

Already pinned server-side by tests/test_play_queue.py (63 tests): the round trip by index as a form and `kept`
byte for byte (`test_a_save_then_a_read_round_trips_as_ethan_by_index_as_a_form`), /at (`..._moves_the_song_and_
second_against_the_full_saves_ids`), 409/422 (`test_a_stale_ids_rev_or_no_record_is_a_409_that_writes_nothing`),
`kept` only after deadwax (`test_kept_is_left_out_when_another_app_saved_last`), the 16 body refusals
(`test_a_body_out_of_bounds_is_a_422_in_words_and_reaches_nothing`), /at's (`test_a_position_save_out_of_bounds_or_
with_more_is_a_422`), break-glass, logins off, privacy, locks, the database failing.

Add to **tests/test_ios_contract.py** (the server's side of the app's promises; mutation-check each):

1. The route count (7 -> 10 for resume's three, plus the other Phase 1 routes) and the three Endpoint lines:
   `Endpoint(method: "GET", path: "/deadwax/navidrome/queue", query: [])`, `Endpoint(method: "POST", path:
   "/deadwax/navidrome/queue", query: [])`, `Endpoint(method: "POST", path: "/deadwax/navidrome/queue/at", query: [])`.
2. `required_fields("QueueAnswer") <= set(GET /queue's answer)` and the same for `KeptQueue` against a kept record
   (logins off with a TestClient and the player fixture, as `test_with_logins_off_...` does).
3. The bodies' field names equal `QueueSave.model_fields` / `QueueAt.model_fields` exactly (as `SignInBody` vs
   `SignIn`) - `extra="forbid"` makes any drift a 422.
4. Swift's `Resume` constants (`max`, `before`, `snapshotMax`) equal play_queue.py's `RESUME_MAX`, `RESUME_BEFORE`,
   `SNAPSHOT_MAX`; the label constant matches `play_queue.LABEL`; `DeviceID`'s length and alphabet match
   `DEVICE_PATTERN`; `deadwaxClient` equals `navidrome_endpoint.CLIENT_NAME`.

## 10. Golden traces: `ios/scripts/export-traces.cjs`

**Run**: `TMPDIR=<writable> node ios/scripts/export-traces.cjs [--check]` from the repo root. It compiles
`src/lib/resume.ts src/lib/upNext.ts src/lib/playQueue.ts src/lib/loudness.ts` (loudness pulls in streamWrap.ts)
with `ui/node_modules/.bin/tsc` into `fs.mkdtempSync(os.tmpdir() + '/deadwax-traces-')`, flags exactly as
upnext.sim.cjs:51-55 (`--rootDir src --module commonjs --target es2022 --skipLibCheck --moduleResolution node`),
`cwd: ui/`. It writes `ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/resume.json` (beside the Up Next spec's
fixture - one script for both). `--check` builds the same JSON in memory and exits 1 if it differs from the file.
**Wire `--check` into the web's CI as a sim** (`ui/test/ios-traces.sim.cjs` running it, picked up by tests.yml's
glob): a TS change that moves any trace then fails where the TS is changed, until the fixtures are regenerated and
the Swift side passes (ios.yml's ubuntu job has no node).

**Deterministic**: no `Math.random`, no `Date` - every random is resume.sim's Park-Miller `seeded(seed)` (seed*16807
mod 2^31-1), the first draw discarded as the sim does. Swift tests read the file by `#filePath`
(`URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/resume.json")`) -
no `resources:` in Package.swift, and it works on Linux.

**Encoding** (format 1):

```json
{"format": 1, "sources": {"resume.ts": "<sha256>", "upNext.ts": "<sha256>"},
 "songs": {"album:1": {"id":"1","title":"song 1",...,"channels":2,"level":"album"}, ":x": {...no level...}},
 "window": [[count, index, start, end], ...],
 "relevel": [[level|null, setting, result|null], ...],
 "toSave": [{"label", "queue": Q, "position", "expect": {"ids","index","position","start","snapshot"}}],
 "fromSnapshot": [{"label", "snapshot", "tracks": [songKey], "index", "setting", "expect": Q|null}],
 "savedLevels": [{"snapshot", "count", "expect": [level|null]}],
 "resumed": [{"label", "answer": {"index","position","changed_by","kept"}, "tracks": [songKey], "setting",
              "device", "expect": {"queue": Q, "position", "from": {"device"|"app": s}|null, "exact"}|null}],
 "pickedUp": [{"from", "shared", "expect"}],
 "roundTrip": [{"run", "step", "queue": Q, "position", "snapshot"}],
 "cap": [{"label", "recipe", "expectLength", "expectNull"}]}
```

`Q` = `{"tracks": [songKey], "index", "upNext": {"marks": [[key, "source"|"added"|"one", at, pass]], "source":
[songKey], "shuffle", "nextKey", "startedAt", "left": [[pass, at]], "paged"?, "pagedRounds"?}}` (`upNext` absent
for a plain queue). A song key is `"<level or empty>:<id>"`; the table holds each once.

**Cases**:

1. `window`, `relevel`, `pickedUp`: the tables of 5.1, 5.3, 5.9.
2. `toSave`: every queue built in resume.sim 272-290 and 296-374 that is small (<= ~150 entries), plus: Repeat One
   copies; Repeat All with two rounds; shuffle on with `left`; a paged shuffle with and without `level`, with
   `pagedRounds` (withMore past `total` under Repeat All) and with `pagedRounds: []`; titles with `/`, `"`, `\`, a
   tab, U+001B, `é`, kana and an emoji; integer-like ids outside the window (`extra` key order); a non-integral
   duration (`200.5`); nil albumId/coverArt/contentType/suffix; 120 songs played at index 100 (start 50, extra 50).
   Swift checks `ids`, `index`, `position`, `start` equal and **`snapshot` string-equal** (4.3 makes it so).
3. `fromSnapshot` - **the snapshots the web wrote, which the phone must read**: each `toSave` case's snapshot read
   back under each of the four settings at its index; the 10 broken ones of sim 314-327 (expect null); `v` as
   `1.0`; a mark key `1.0`; `"level":null` in paged (null); `paged: null` (null); a mark of 3 or 5 items; a `left`
   item of 1; `levels` one short; a source mark naming another song.
4. `savedLevels`: a good snapshot at its count and count +- 1; null; `"{"`.
5. `resumed`: every resume.sim case at 309-374 with its `answer` and tracks; plus **kept.index moved by another
   device's position save** (snapshot made at 1, kept.index 3 == answer.index -> exact at 3, the account intact);
   kept with `index: null` in the answer; dropped songs where the survivors are NOT a subsequence (falls through to
   anyone else's); a duration-0 song at a huge position (no advance); logins-off `shared` is not an input (words
   are 5.9's).
6. `roundTrip`: the sim's generator (sim 192-233: `size = 1 + pick(7)`, ops 0-11 over 25 steps, `paged` every 5th
   run, position 12.5) for **runs 0-39 (1,000 states, about 1.1 MB; measured)**; across them 40 states have
   `startedAt` past the index, 200 are paged, 7 have pagedRounds, 507 have `left`, 282 Repeat One copies, 698 added
   songs, 621 shuffled, 405 a non-empty `extra` (measured with a prototype of this exporter on 2.1.0). Swift, per
   state: `toSave(queue, 12.5).snapshot == snapshot`; `fromSnapshot(snapshot, window tracks without level, index -
   start, .auto) == wanted`, `wanted` = the sim's (sim 240-244: tracks/marks sliced, startedAt floored, the rest as
   is); and the same from its own snapshot. No windows start past 0 here - case 2's 120-song queue covers that.
7. `cap` (generated from a recipe, not stored): `recipe = {"n": 2400, "prefix": "cap-", "index": 50, "pad":
   {"id": "cap-2400", "unit": "😀"|"x", "count": k}}`, the songs being resume.sim's `track(id)` with that one title
   padded. The exporter searches `k` so the TS snapshot is **exactly 262,144** UTF-16 units (kept) and **262,145**
   (nil), once with `x` padding and once with emoji padding (2 units each, 4 UTF-8 bytes, 1 code point) - pinning
   that the count is UTF-16, as the web's. Plus resume.sim 276's 5,000-song list (snapshot nil).

**The reverse direction** (phone writes, web reads) needs no Swift-to-node plumbing: case 2 and 6 make the phone's
snapshot string-equal to the TS's for the same queue, so the web's `fromSnapshot` reads the phone's exactly as its
own. The exporter asserts its own premise: every exported snapshot re-serialised by a reference implementation of
4.3's writer (in the exporter, in JS) equals the TS's string - so a TS change to key order shows up as a failing
export, not a silent Swift mismatch.

**Not traced** (hand-mirrored, 9.2): the controller - it depends on time, the engine and the server.

## 11. Open questions

1. **Label "iPhone" or "iPhone app"?** Recommended: `"iPhone"` - what James's devices are called on the web, and the
   web app and the native app on one phone are rarely both used. ("Picked up from your iPhone app" if he wants to
   tell them apart.)
2. **A paged library shuffle picked up from the web**: Phase 1 lists no Library Shuffle. Without the feed
   (useShuffleFeed.ts, 134 lines: `GET /navidrome/shuffle?scope=` and `/shuffle/{token}?offset=`, FEED_BELOW 50,
   SHUFFLE_STARTED_OVER) the phone plays the window's songs and stops. Recommended: keep `paged` / `pagedRounds`
   intact through read and save in Phase 1 regardless (so the web carries on feeding it), and port the feed in
   Phase 1 if it's cheap for the Up Next work, else Phase 4 with the songs list.
3. **The album answer for Info after a pick-up** (useResume.ts:255-260): only needed if Phase 1's Info / Now
   Playing hold album answers as the web's tap does. Recommended: skip it if Info reads `/navidrome/songs/{id}` alone.
4. **Saves while deadwax is unreachable** (plan choice 20, `queue_pending`): the web just retries at the next
   trigger, at most every 30 s. Recommended: Phase 1 does exactly that (streaming-only, nothing plays offline);
   keep the latest unsent save on disk with Phase 2's database, and on return let Navidrome's newer queue win as the
   409 rule has it.
5. **A save sent at background while another is out** may land first and be overtaken by the older one (the web
   has the same race). Recommended: accept, as the web does - the next save corrects it.
