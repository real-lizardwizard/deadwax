# Phase 1 spec: Up Next and the queue (app 0.2)

Scouted on `ios` = main at 2.1.0 (`1199330`). Sources read in full: `ui/src/lib/upNext.ts` (595 lines),
`ui/src/lib/playQueue.ts` (225), `ui/src/app/UpNext.tsx` (364), `ui/src/app/QueueMenu.tsx` (88),
`ui/test/upnext.sim.cjs` (814), `ui/test/playqueue.sim.cjs` (320), `ios/DeadwaxKit/Sources/DeadwaxCore/PlayQueue.swift`;
the queue parts of `ui/src/player/usePlayer.ts`, `App.tsx`, `NowPlaying.tsx`, `PlayerBar.tsx`, `player.sim.cjs`
4758-5480, `notes/ios.md`, and the plan's sections 1-3 and 5.

**`ui/test/queue.sim.cjs` is not about this area**: it pins the metadata REVIEW queue's badge (`lib/metadataQueue.ts`).
The play queue's sims are `playqueue.sim.cjs` (previous, next, startQueue) and `upnext.sim.cjs`; the engine's use of
Up Next is pinned by `player.sim.cjs`'s Up Next sections (listed in section 9).

**No server change** for this area. Nothing here sends or reads JSON of its own; Up Next reaches the server only
inside the resume snapshot (a separate area, `lib/resume.ts`), which serialises the types in section 1.

### What changed since 2.0.0 (`git log 85aa7be..HEAD`)

| file | commits | what the port must follow |
| --- | --- | --- |
| lib/upNext.ts | 6452ff3 (2.0.5), 92a58dc (2.0.7), 7bb0a85 (2.0.14) | paged list title `All music, shuffled` (was `Everything`); then-line name `all music` (was `everything`); `upNextLabel` says `Up Next` (capital N, was `Up next`); new `shuffleLabel(scope)` |
| app/UpNext.tsx | 92a58dc, e04ac43 (2.0.9) | comment only; `dir="auto"` on the titles and lines (natural writing direction: SwiftUI `Text` does this by itself) |
| player/NowPlaying.tsx | 7bb0a85 (2.0.14) | Shuffle (first) and Repeat (last) on the transport row; the Up Next button no longer tinted, named by `upNextLabel` |
| usePlayer.ts | 92a58dc | words only: skip notice `Skipped "<title>" - this device couldn't play its audio` (decode) / `Skipped "<title>" - it wouldn't play` |
| playQueue.ts, QueueMenu.tsx, useShuffleFeed.ts, resume.ts | none | - |

---

## 1. Types (DeadwaxCore, pure Swift + Foundation)

TS: upNext.ts:35-108, playQueue.ts:12-47. Value types, `Sendable, Equatable`.

```swift
public struct QueueTrack: Sendable, Equatable, Hashable {   // playQueue.ts:12 + loudness.ts:39 (level)
    public var id: String; title: String; artist: String; album: String
    public var albumId: String?; coverArt: String?
    public var duration: Double        // seconds, 0 when unknown
    public var contentType: String?; suffix: String?
    public var sampleRate: Int; bitDepth: Int; channels: Int   // 0 when Navidrome didn't say
    public var level: Level?           // .album / .track; nil = Off (the Normalization area sets it)
}
public enum Level: String { case album, track }
public enum Repeat: String, CaseIterable { case off, all, one }          // REPEATS order: off, all, one
public enum MarkFrom: String { case source, added, one }                 // snapshot chars s, a, o
public struct Mark { public var key: Int; from: MarkFrom; at: Int; pass: Int }
public struct LeftOut { public var pass: Int; at: Int }                  // state.left's {pass, at}
public enum PagedScope: String { case yours, store }
public struct Paged { var token: String; total: Int; fetched: Int; scope: PagedScope; level: Level? }
public struct PagedRound { var pass: Int; paged: Paged }
public struct UpNextState {
    var marks: [Mark]          // one per entry of tracks, same length always
    var source: [QueueTrack]   // the list as playTracks was given it, own order
    var shuffle: Bool
    var nextKey: Int
    var startedAt: Int         // the index playTracks started at (0 when shuffled)
    var left: [LeftOut]        // list songs taken out of a round (removed or jumped over); never pruned
    var paged: Paged?          // (Part B) a library's shuffle
    var pagedRounds: [PagedRound]?   // nil and [] are DIFFERENT states (withRepeat can leave [])
}
public struct UpNextQueue { var tracks: [QueueTrack]; var index: Int; var upNext: UpNextState?
    static let empty = UpNextQueue(tracks: [], index: -1, upNext: nil) }   // EMPTY_QUEUE, index -1
public enum PreviousAction { case restart; case go(Int) }
public struct UpNextRow { let key: Int; let track: QueueTrack }
public struct UpNextView { let playing: QueueTrack?; let added: [UpNextRow]
    let list: (title: String, rows: [UpNextRow], more: Int)?   // a small struct in practice
    let then: String?; let repeatOne: Bool }
public enum QueuedAs: String { case album, songs }
public struct QueuePick { var label: String; var tracks: [QueueTrack]; var albums: [AlbumRef]; var queuedAs: QueuedAs }
```

- `Mark.at`: a source entry's place in `source` (a copy: its original's); `-1` for an added song (and for a copy of
  an added song). `Mark.pass`: time round of the list (0 first; Repeat All's 1, 2...); `-1` for added (and its copies).
- Only `UpNextQueue.empty` has `upNext == nil` (resume's "plain list" is `startUpNext(levelled, index)`, resume.ts:315-322).
- `current(q)` = `q.tracks[q.index]` if in range, else nil (playQueue.ts:49).
- **Phase 0's `PlayQueue.swift` is replaced** by `UpNextQueue` + free functions. Phase 0 clamps an empty queue's index
  to 0 (PlayQueue.swift:19); the port uses -1 as TS does. Port `PhaseZeroTests.PlayQueueTests` (PhaseZeroTests.swift:169)
  onto `startUpNext` (clamp: index 9 -> 2; empty -> `.empty`, `current == nil`) and `backward`/`onward`.
- **QueueTrack from Navidrome's song JSON** (`toQueueTrack`, player/api.ts:621): `id`; `title` (Swift `Song.name`:
  title, or the id); `artist = song.artist ?? album.artist ?? ""`; `album = song.album ?? album.name`;
  `albumId = song.albumId ?? album.id`; `coverArt = song.coverArt ?? album.coverArt ?? nil`;
  `duration = song.duration ?? 0`; `contentType`, `suffix` as sent or nil; `sampleRate = samplingRate ?? 0`,
  `bitDepth ?? 0`, `channels = channelCount ?? 0`. All Song fields optional but `id` (Models.swift:40) - already
  decoded by Phase 0's `Song`. Pinned by playqueue.sim.cjs:308-317.

## 2. Constants

| name | value | where |
| --- | --- | --- |
| `REPEAT_AHEAD` | 2 - entries Repeat keeps queued past the song playing | upNext.ts:104 |
| `UP_NEXT_DRAWN` | 100 - list rows drawn; "And N more songs." past it | upNext.ts:106 |
| `TOP_UP_HEARD_S` | 2 - seconds heard (or half a shorter song) before Repeat tops up | upNext.ts:108 |
| `REPEATS` | `[off, all, one]` - the Repeat button's cycle | upNext.ts:38 |
| `RESTART_AFTER_SECONDS` | 3 (Phase 0 has it: `PlayQueue.restartAfterSeconds`) | playQueue.ts:47 |

## 3. The invariant (upNext.ts:20-27; checked by upnext.sim.cjs:157-231 after every step of 2,000 runs)

1. `marks.count == tracks.count`; keys unique; every key `< nextKey`.
2. After `index` the entries run: Repeat One copies (`one`), then added songs (`added`), then list songs (`source`)
   time round by time round, `pass` never decreasing. (Not held after Previous goes back across another song's
   copies - toppedUp's own comment, upNext.ts:197: e.g. `1s* 1o 1o 2s 2o 2o 2o 3s`. The sim's property loop has no
   Previous in it; the Swift property test must not either. Golden traces include Previous and pin the result.)
3. Every edit keeps `tracks[0...index]`, `marks[0...index]` and `index` exactly. `jumpedTo` alone puts the row first
   (ahead of the added songs) until the engine moves onto it.
4. A source mark has `at >= 0`; any mark with `at >= 0` names its song: `source[at].id == tracks[i].id`.
5. **An edit that changes nothing hands back the same queue** (TS: the same object). Swift: return the parameter
   unmodified (so its arrays share storage and `==` takes Array's buffer-identity fast path, O(1)); callers detect
   "nothing changed" with `==`. A queue with no `upNext` (`.empty`): every edit returns it as it is; `onward`,
   `backward`, `pastCopies` answer as `nextIndex` and `previousAction` would.

## 4. Randomness - how it enters, exactly

Only three functions take `random`, each a parameter defaulting to the system's (`Math.random`): `startUpNext`,
`toppedUp`, `withShuffle`. Nothing else is random. Swift: `random: () -> Double` (non-escaping), default
`{ Double.random(in: 0..<1) }`. Every draw is `j = floor(random() * (i + 1))` in doubles - Swift
`Int((r * Double(i + 1)).rounded(.down))`, then `min(j, i)` as a guard (can't change any result for r < 1 - 2^-40;
JS's Math.random can't reach that, nor can Park-Miller).

**`shuffled(list)`** (upNext.ts:113, private): Fisher-Yates over a copy, `for i in stride(from: n-1, to: 0, by: -1)`:
one call per `i`, `swapAt(i, j)`. Calls: `max(0, n - 1)`.

Calls per function, in this order:

| function | calls of `random()` |
| --- | --- |
| `startUpNext(tracks, start, shuffle)` | not shuffled: 0. `start == nil`: `shuffled(places)` = n-1. `start != nil`: `shuffled(places without index)` = max(0, n-2). Never for n <= 1. |
| `toppedUp(q, .all)` | per round appended (the while loop): if `state.shuffle`: `shuffled(order)` = L-1 (L = source.count), THEN one more call if `round.count > 1 && ending != nil && source[round[0]].id == ending` - **made even when `later` is empty** (`later[floor(random()*0)]` -> nil, no swap; e.g. source `[a, a]`: 2 calls, verified). Not shuffled: 0. Rounds loop until `count - index - 1 >= REPEAT_AHEAD` (a one-song list appends 2 rounds). |
| `toppedUp(q, .one / .off)` | 0 |
| `withShuffle(q, true)` | `shuffled(wanted)` = max(0, wanted.count - 1), only if it gets past its early returns |
| `withShuffle(q, false)` | 0 |

A Swift port fed the same numbers in the same order gives identical results (traces pin it: section 10).

**The sims' generator** (upnext.sim.cjs:106, playqueue.sim.cjs:51), Park-Miller, seeds 1...2147483646 only (0 sticks
at 0 and returns a negative): `s = (s * 16807) % 2147483647; return Double(s - 1) / 2147483646`. Swift with `Int64`
is bit-identical to JS (`s * 16807 < 2^46`, exact in a double).

## 5. Functions (lib/upNext.ts) - every rule

Helpers (private):
- `rebuilt(q, state, tracks, marks, more)` :123 - `{...q, tracks, upNext: {...state, marks, ...more}}`; index kept.
- `layout(q, state)` :128 - `copiesEnd` = first place after `index` whose mark isn't `one` (counts ANY song's
  copies); `addedEnd` = from copiesEnd, first place whose mark isn't `added`.
- `lastSourceAt(state, index)` :137 - the last place `<= min(index, marks.count-1)` with a `source` mark; -1 none.
- `passPlaying(state, index)` :144 - that mark's pass; -1 none (an added song or copy is in the round of the list
  song before it).
- `oneAlbum(source)` :150 - nil if `source` empty or `source[0].albumId` is nil OR EMPTY (JS falsy); else
  `source[0].album` if every song's `albumId == first.albumId`, else nil. (An album named `""` gives `"From "` - port as is.)
- `groupOf(q, state, key)` :352 - place = first index of mark with that key; nil if `place <= index` (incl. not
  found, -1). Added mark: `{place, start: copiesEnd, end: addedEnd}` if `place < addedEnd`, else nil. A `one` mark:
  nil. A source mark: `shown = marks[addedEnd]?.pass`; nil unless `mark.pass == shown`; `end` = from addedEnd while
  `source` and `pass == shown`; `{place, start: addedEnd, end}` if `place < end`.
- `added(q, state, tracks, place)` :324 - new marks `{key: nextKey+i, from: added, at: -1, pass: -1}` inserted at
  `place` in tracks and marks; `nextKey += tracks.count`.

Public:

1. **`startUpNext(tracks, start: Int?, shuffle = false, random, paged: Paged? = nil)`** :162 - empty tracks -> `.empty`.
   `index = min(max(start ?? 0, 0), n-1)`. `places = 0..<n`. order = places (not shuffled) / `shuffled(places)`
   (`start == nil`) / `[index] + shuffled(places minus index)`. Result: `tracks = order.map{tracks[$0]}`,
   `index = shuffle ? 0 : index`, marks `order.enumerated().map{ Mark(key: offset, from: .source, at: element,
   pass: 0) }`, `source = tracks` (own order), `shuffle: shuffle || paged != nil`, `nextKey = n`,
   `startedAt = shuffle ? 0 : index`, `left = []`, `paged` if given. Same tracks/index as `startQueue` for the same
   random (sim :142; startQueue itself needn't be ported - nothing in the app calls it). Note: with `paged` and
   `shuffle == false`, index is `start` clamped and startedAt too.
2. **`toppedUp(q, repeat, random)`** :192 - `q` if no state, `.off`, or nothing playing.
   - `.one`: `end` = from index+1 while mark is `one` AND `tracks[end].id == playing.id` (this song's copies only).
     `have = end - index - 1`; `have >= 2` -> `q`. Else insert `2 - have` copies AT `end`: track = the playing
     track, marks `{key: nextKey+i, from: .one, at: marks[index].at, pass: marks[index].pass}`; nextKey += count.
     (Playing an added song: copies have at -1, pass -1.)
   - `.all`: `q` if `paged != nil`, or `source` empty, or `count - index - 1 >= 2`. Else loop while
     `tracks.count - index - 1 < 2`: `last = lastSourceAt(marks so far, end)`; `pass = (last < 0 ? -1 :
     marks[last].pass) + 1`; `round = 0..<L`, shuffled if `state.shuffle`; if shuffled and `L > 1` and
     `ending = tracks[last].id` (last >= 0) and `source[round[0]].id == ending`: `later = round places p > 0 whose
     song id != ending`; draw `pick = later[floor(random()*later.count)]` (draw always made); if pick, swap round[0]
     and round[pick]. Append every `source[at]` with `{key: nextKey++, from: .source, at, pass}`. Added songs are
     never copied. Result `rebuilt(..., {nextKey})`.
3. **`withRepeat(q, repeat)`** :244 - no state -> q. `round = passPlaying(index)`. An entry GOES if `place > index` and
   ((repeat != .one and from == .one) or (repeat != .all and from == .source and pass > round)). None -> `q`.
   Else filter tracks and marks. Paged (Part B): `last = lastSourceAt(kept marks, end)`, `pass` its pass (-1 none);
   if `state.paged != nil` and `pagedRounds` has an entry with that pass: `paged = that entry's paged`,
   `pagedRounds = pagedRounds.filter{ $0.pass < pass }` (may become `[]`). Engine then calls toppedUp.
4. **`withShuffle(q, on, random)`** :280 - `q` if no state, `paged != nil`, `state.shuffle == on`, or nothing playing.
   `round = passPlaying(index)`; `left = {at | left entry with pass == round}`.
   - ON: `roundStart = round == 0 ? startedAt : first place with source mark of pass == round`; if < 0 then `index`.
     `heard` = ats of source marks with `pass == round` at places `roundStart...index` (empty loop if roundStart >
     index - Previous back before startedAt); plus `marks[index].at` if >= 0. `wanted = shuffled(places not heard
     and not left)`.
   - OFF: `last = lastSourceAt(index)`, `lastAt = last < 0 ? -1 : marks[last].at`; `wanted = places > lastAt, not left`
     (in order).
   - Keys: ON only, a map at -> mark of the source marks of pass == round after index; `fresh = wanted.map{ queued[at]
     ?? Mark(key: nextKey++, from: .source, at, pass: max(round, 0)) }`.
   - Result: keep entries `place <= index || from != .source` (copies and added stay in order), then fresh entries'
     tracks `source[at]`; `{shuffle: on, nextKey}`. Later rounds go with the rest; the engine's toppedUp regrows them.
5. **`withNext(q, tracks)`** :335 - `q` if no state, tracks empty, or nothing playing; else `added(at: copiesEnd)`.
6. **`withLast(q, tracks)`** :343 - same guards; `added(at: addedEnd)` (after added songs, before the list).
7. **`withoutKey(q, key)`** :367 - `q` if no state or `groupOf` nil (the song playing, earlier, a copy, a later
   round, unknown key). Removes that place; a source mark appends `LeftOut(pass, at)` to `left`.
8. **`movedKey(q, key, to)`** :382 - `q` if no state or no group. `from = place - start`;
   `dest = clamp(to, 0, end-start-1)` (TS `Math.round(to)`; Swift takes Int); `dest == from` -> `q`. Remove at
   `from` and insert at `dest` within `[start, end)` of tracks and marks alike.
9. **`withoutAdded(q)`** :400 - removes every `added` mark after index; none -> `q`.
10. **`jumpedTo(q, key) -> UpNextQueue?`** :414 - nil if no state or no group. New order by old place:
    `0..<copiesEnd`, then `place`, then every place from copiesEnd on except `start...place` (the rows above it in
    its group go; the other group stays). A source row appends `LeftOut` for each mark in `start..<place` (the
    jumped-over). Never `q` itself: a jump to a group's first row returns a NEW but EQUAL queue (verified).
    The engine then moves onto it with `onward` (it sits at copiesEnd).
11. **`onward(q) -> Int?`** :439 - no state: `nextIndex`. Else first place > index whose mark isn't `one`; nil none.
12. **`backward(q, position: Double) -> PreviousAction`** :451 - `previousAction(q, position)` (playQueue.ts:86:
    `.restart` if `position > 3` or `index <= 0`, else `.go(index-1)`); if `.restart` or no state, that. Else
    `place = index`; while `place > 0 && marks[place].from == .one { place -= 1 }`; `place > 0 ? .go(place-1) : .restart`.
13. **`pastCopies(q, from) -> Int?`** :462 - no state: `from` if `0 <= from < count` else nil. Else first place
    `>= max(from, 0)` whose mark isn't `one`; nil none (the queue stops, as at its end).
14. **`shownPass(q) -> Int`** :470 - the pass of the first source mark after index; -1 none / no state.
15. **`withMore(q, token, tracks, next: Paged?)`** :484 (Part B) - `q` unless state, `paged`, `paged.token == token`,
    tracks non-empty. `round = next != nil && paged.fetched >= paged.total`; `before` = pass of the last source
    mark (0 if none); `pass = before + (round ? 1 : 0)`; marks `{key: nextKey+i, .source, at: source.count+i, pass}`
    appended at the END; `source += tracks`; `nextKey += n`; `paged = next.map{ fetched = n } ?? paged with fetched
    += n`; if round: `pagedRounds = (old ?? []).filter{ $0.pass >= passPlaying(index) } + [PagedRound(before, old paged)]`
    else unchanged (nil stays nil).
16. **`upNextView(q, repeat, limit = 100)`** :526 - nothing playing or no state: `{playing: current(q), added: [],
    list: nil, then: nil, repeatOne: false}`.
    `added` = rows `copiesEnd..<addedEnd` (key, track). `shown = shownPass`; `listed` = places from addedEnd while
    source and `pass == shown` (break at the first other). `pending = paged ? max(0, total - fetched) : 0`;
    `again = shown > passPlaying(index)`. Title: paged -> `"Your library"`/`"All music"` + `", shuffled"` + (again ?
    `", again"` : ""); else `listTitle(source, again)`. `list` = nil unless `listed` non-empty or `pending > 0`:
    `{title, rows: first limit of listed, more: max(0, listed.count - limit) + pending}`. `name` = paged ?
    (`"your library"` / `"all music"`) : (oneAlbum ?? `"the list"`). `then` = repeat .all: shuffle ?
    `"Then \(name) again, in a new order."` : `"Then \(name) again from the top."`; .off and `index >= count-1`:
    `"Nothing after this song."`; else nil. `repeatOne = repeat == .one`. Copies and later rounds never drawn.
17. Words: `listTitle(source, again)` :558 - `"From \(album)"` for one album, else `"Still to play"`; `+ ", again"`.
    `queuedWords(.next, label)` = `"Playing next: \(label)"`; `.last` = `"Added to Up Next: \(label)"` :565.
    `repeatLabel` :570 - off `"Repeat"`, all `"Repeat all"`, one `"Repeat one"`. `shuffleLabel(scope?)` :578 - nil
    `"Shuffle"`, store `"Shuffle - shuffling all music"`, yours `"Shuffle - shuffling your whole library"`.
    `nextRepeat` :584 - off->all->one->off. `upNextLabel(shuffle, repeat)` :590 - both: `"Up Next - Shuffle and
    \(repeatLabel)"`; shuffle: `"Up Next - Shuffle on"`; repeat: `"Up Next - \(repeatLabel)"`; neither `"Up Next"`.

From playQueue.ts also port `nextIndex` :78 (`index+1 < count ? index+1 : nil`) and `previousAction` :86.
(`afterFailure`, `countsAsPlayed`, `listenedStep`, `listenHeard` belong to the playback and plays areas.)

## 6. The player's rules around it (usePlayer.ts, read only) - a Core `QueueController`

Recommended: put this logic in DeadwaxCore as a pure state machine over an `EngineLink` protocol (`play(tracks,
from:)`, `replaceUpcoming(tracks, current:) -> Bool`, `skip(to:)`, `seek(to:)`, `heardIndex() -> Int?`), so it
is tested on Linux with a fake engine as player.sim.cjs tests usePlayer. State: `queue`, `repeat` (device),
`heldEdit: ((UpNextQueue) -> UpNextQueue)?`, `intendsToPlay`, the listen's `heard` seconds.

- **Repeat is the device's** (persisted.ts:200): stored `"all"` or `"one"`; anything else (absent, `"ALL"`,
  `"repeat"`, `""`, unreadable) is off. Web key `deadwax-player-repeat`; iOS: UserDefaults, same key and values.
  **Shuffle is the queue's**: `queue.upNext?.shuffle ?? false` (usePlayer.ts:2165), never stored apart (resume carries it).
- **playTracks(tracks, start, shuffle, paged)** :1490 - `heldEdit = nil`; queue =
  `toppedUp(startUpNext(tracks, start, shuffle, random, paged), repeat)`; engine.play from its index. Album page:
  Play = `(0, false)`, Shuffle = `(nil, true)`, a track's tap = `(i, false)` - all as `QueuedAs.album`
  (AlbumPage.tsx:331-336, 457, 461, 536).
- **catchUp** :1406 - before every action: if the engine's heard song is past `queue.index`, move the queue there
  first (the crossInto path). On iOS: `engine.position()` (a `queue.sync`), since `onChange` arrives later on main.
- **edit(change)** :1451 = catchUp, then **apply** :1442: `all = held.map{ h in { change(h($0)) } } ?? change`
  (a held change goes first; none lost), `next = all(queue)`, then **replaceUpcoming(next)** :1424: `next == queue`
  -> done; if `next.index != queue.index` or the current ids differ -> a fresh `play` (a bug guard); else
  `engine.replaceUpcoming` - refused -> `heldEdit = all` (made at the next song change / tick, against the queue as
  it is then: Play Next held through a join lands after the NEW current song, player.sim.cjs:5403).
- **runHeld** :1457 at each tick and each song change; then **topUp** :1467: `repeat != .off` and `heard >=
  (length > 0 ? min(2, length/2) : 2)` -> `edit(toppedUp(q, repeat))`. Only listening tops up, so a queue whose
  songs all fail still ends (player.sim.cjs:5107).
- **setShuffle(on)** :1638 - if something playing: `edit(toppedUp(withShuffle(q, on), repeat))`. Ignored for a paged
  queue (the buttons are `aria-disabled` and do nothing; withShuffle returns q anyway).
- **setRepeat(mode)** :1641 - same mode -> nothing; store; if playing: `edit(toppedUp(withRepeat(q, mode), mode))`.
- **playNext / playLast(tracks) -> Bool** :1478/1650 - empty -> false; catchUp; nothing playing, or the engine
  ended and `onward == nil` -> `playTracks(tracks, 0)`, return true (no notice); else `apply(withNext/withLast)`,
  false.
- **jumpTo(key)** :1656 - catchUp; `jumpedTo` nil -> nothing; replaceUpcoming refused -> nothing (a tap: now or
  never); else `intendsToPlay = true` and `next()` (plays even from pause).
- **moveInQueue / removeFromQueue / clearPlayingNext** :1665-1673 - `edit(movedKey / withoutKey / withoutAdded)`.
- **next()** :1519 - catchUp; if `repeat == .all && onward == nil` -> `apply(toppedUp(q, .all))` first (the last song
  heard < 2 s, player.sim.cjs:5416); `i = onward(q)`; nil -> nothing; skip to i.
- **previous()** :1537 - catchUp; `backward(q, position)`: `.restart` -> seek 0; `.go(i)` -> skip to i.
- **A song's end with nothing after** (onEnded :1827) - if `repeat != .off && nextIndex == nil`: `queue =
  toppedUp(q, repeat)` (sought to the end before 2 s heard, player.sim.cjs:5442/5455); then `nextIndex` (copies
  included: Repeat One's copy plays) or stop (`intendsToPlay = false`).
- **A failed song's skip** :1927 - `pastCopies(q, nextIndex)`; nil -> stop as at the end.
- **restoreQueue(q, position)** :1680 (resume's one action) - `toppedUp(withRepeat(q, repeat), repeat)`; held and
  pending seek cleared. Lock-screen next/previous are next()/previous() (player.sim.cjs:5234).

## 7. What the engine needs, and when a change must reach it

- **The flattened entries and the index**: the engine plays `queue.tracks` 1:1 - every entry, Repeat One's copies
  and later rounds included, each an `EngineTrack` (song + level for gain) - and `queue.index` IS the engine's index.
  Marks never reach it. The engine's own "next" at a song's end is `index + 1` (copies play); the user's Next is
  `onward`, chosen by the app.
- **Calls**: a new queue -> `play(tracks, from:)`; Next/Previous/jump/failure skip -> `skip(to:)`; restart -> `seek(0)`;
  **every Up Next edit and top-up -> `replaceUpcoming` at once**, in the same main-thread turn. Reason: the engine
  opens the next song when the heard song's decode ends (`endFeed`, PlaybackEngine.swift:661; `pump` keeps `aheadSeconds` decoded, :487-491), about
  `aheadSeconds` (2 s) + one 0.5 s buffer before its end, and schedules it on the same node for a gapless join; an
  edit arriving later plays the old next song.
- **Phase 0's `replaceTracks` (PlaybackEngine.swift:260) only swaps the array** - not enough. Needed
  `replaceUpcoming(tracks, current) -> Bool` (on the engine queue, sync), the web's `StreamSource.replan`
  (streamSource.ts:327) adapted:
  1. refuse (false) if the engine's heard index != `current` (it moved on: the app catches up, holds the edit) or
     `tracks[current].id` differs;
  2. `keep` = from `current`, while the old and new entries at `keep+1` have the same id (and level - recommended:
     another level is another gain), up to the furthest index the engine has opened (`feed.index`, a parked buffer);
  3. songs past `keep` that were opened or scheduled are let go: on another lane, stop and clear that lane; on the
     heard lane, scheduled buffers can't be removed from an AVAudioPlayerNode one by one - stop the node and go on
     from the exact frame reached (`heard()`), as a lane running dry does (open question 1);
  4. if the feed had run out at the old last entry and the new tracks go further (Play Last in the last 2 s; Repeat's
     top-up of a short song), open the next entry and feed on (else fallback: at `.ended` the app's end rule above
     plays from `nextIndex` - a cold start);
  5. accept (true). Compare by id, never by key (Shuffle off re-keys the same songs; by key would cut for nothing).
- The engine reports song changes (`EngineState.index`); the app moves `queue.index` there, then runHeld, then topUp.
- **REPEAT_AHEAD vs. the look-ahead**: 2 entries ahead suffices for songs over ~2.5 s. A song under ~1 s on Repeat
  One can have the engine decode past both copies before topUp runs - step 4 covers it (player.sim.cjs:5468: a
  1.5 s single on Repeat One still going 12 s on, every loop a join).

## 8. What is drawn (Phase 1 screens)

**Up Next sheet** (UpNext.tsx; opened from Now Playing's Up Next button; a SwiftUI sheet):
- Header: `Edit` (left; only when not editing and there is at least one row) - title `Up Next` - `Done` (closes;
  in Edit, ends Edit and closes nothing, sim :640). Every opening starts at the top, out of Edit (:89-95).
- The song playing: cover, title, `artist · album` (empty parts dropped, joined with ` · `). With Repeat One:
  `Repeat one: this song plays again until you skip it.` (REPEATING_ONE :26).
- Two chips (group label `Shuffle and repeat`): `Shuffle` (pressed = queue's shuffle; paged: pressed and disabled,
  tap does nothing) and `repeatLabel(repeat)` with the RepeatOne glyph on One (tap: `nextRepeat`). Paged: the line
  `Shuffling your whole library` (SHUFFLING_LIBRARY :28 - shown for either scope; open question 5).
- `Playing Next` section with `Clear`, only when `view.added` is non-empty.
- The list section headed `view.list.title`; rows (cover, title, song line); `And N more songs.` / `And 1 more
  song.` when `more > 0`, N grouped with commas en-US (`3,997`) - a pure formatter in Core, not NumberFormatter.
- `view.then` under it.
- A row's tap: `jumpTo(row.key)` (keys, so a song in twice is two rows; a key gone does nothing). Row label
  `<title>, play now`.
- Edit: per row `Move <title> up`, `Move <title> down` (disabled at the group's ends), `Remove <title>`, and a drag
  handle; moves stay in their group. SwiftUI: one `ForEach` per group with `.onMove` and `.onDelete`; `.onMove`'s
  `(IndexSet{from}, destination)` -> `to = destination > from ? destination - 1 : destination` -> `moveInQueue(key, to)`;
  up/down as accessibility actions.
- VoiceOver announcements (`said`): `Shuffle on` / `Shuffle off`; `Repeat off` / `Repeat all` / `Repeat one`;
  `Playing Next cleared`; `<title>: <to+1> of <rows in group drawn>`; `<title> removed`.
- Focus after a change (Pinned's rule, :82-116): a move -> that row's button where it went (the other direction's
  if disabled); a removal -> the next row's Remove, the previous at the end, Done with none; Clear -> the Shuffle
  chip; Edit pressed -> Done; a row's tap -> the row after it (Playing Next's last -> the list's first), or Done.
- The sheet closes by itself once nothing is playing (queue empty; App.tsx:1023-1029).

**Song menu** (QueueMenu.tsx; every song row's ••• and the album page's own •••): `Play Next`, `Play Last`
(`Add to a playlist…` is Phase 4), `Cancel`; titled by `pick.label` or `Up Next`. A tap: remember the albums for
Info, then `playNext/playLast(pick.tracks levelled as pick.queuedAs)` (album ••• -> `.album`, a song -> `.songs`),
close, and only when it returned false show `queuedWords(how, label)` as the app's notice.

**Now Playing** (NowPlaying.tsx:393-450, 2.0.14): transport `Shuffle` · Previous · Play/Pause · Next · `Repeat`;
Shuffle labelled `shuffleLabel(paged?.scope)`, pressed = shuffle, disabled while paged; Repeat labelled
`repeatLabel(repeat)`, pressed = not off, RepeatOne glyph on One; both tinted while on. The footer's Up Next
button (queue glyph) is labelled `upNextLabel(shuffle, repeat)`, never tinted.

## 9. Tests that pin each rule (mirror them in Swift)

upnext.sim.cjs (line: label) -> `UpNextTests` (Core, Linux):
- start: 142 same as startQueue; 143 empty -> `.empty` with no state; 145 one song shuffled; 147-148 marks, keys
  0..n-1, nextKey n, startedAt; 151 a song twice; 152 source order, Shuffle as asked.
- invariant: 157-231 (port the loop literally: `seeded(run+1)` drives both the ops and the functions; 2,000 runs x
  30 steps, the 12 ops 0-11 as written; checks 212-227) - same Park-Miller, so the same 2,000 runs as the sim.
- Play Next/Last: 239, 241, 242, 244 (after copies), 245, 246 (same queue).
- row out/moved/Clear: 252, 254 (left), 256, 258, 259, 260 (clamp; same), 262 (copies), 263, 265.
- jump: 273, 274, 277, 278 (nil cases), 281.
- Shuffle on: 291, 292 (1-4 and 8-12), 293, 295 (keys kept), 296, 299, 301, 304, 308, 309, 310. Off: 320, 322, 324,
  327, 328.
- Repeat All: 336, 338, 339, 341, 343, 345, 354 (1,000 seeds x sizes 2 and 4), 356. One: 363, 364, 366.
  Changes: 372, 374, 375, 376, 377, 379.
- Next/Previous/skip: 387-396.
- view and words: 405-432 (exact strings above).
- Part B: 441-464.
- Components 548-810: what is drawn and the read-outs - mirror as view-model tests where the logic is in Core;
  the rest is checked on the phone.

playqueue.sim.cjs: 81-92 (next, previous, first song restarts) - already in Phase 0's tests; 61-76 (start clamps,
shuffle keeps the tapped song first) - via startUpNext.

player.sim.cjs (usePlayer) -> `QueueControllerTests` with a fake engine: 4758 untouched (playTracks tops up once,
no replan); 4778/4797 Play Next mid-song and in the last seconds (replaceUpcoming lets go of the next); 4838 remove,
move, Clear; 4958/4981 a row's tap, a gone key; 4984 Shuffle mid-song (no restart, no seek); 5045 Repeat One (Next
-> the next song, then it repeats; Previous early -> before the run; One off mid-song); 5088-5117 failures with
Repeat (once more, then past copies; all failing stops within the queued round); 5147/5179 held edits; 5207 Play
Next after the queue played out returns true; 5234 lock screen; 5257-5277 Repeat stored and read; 5344 actions
just after an unseen join act on the heard song; 5377-5412 held edits composed, made at the join, dropped by a new
queue; 5416-5455 Repeat with the last song < 2 s heard; 5458-5470 short songs. Engine-level (DeadwaxAudio offline
renders, macOS): Play Next in a song's last 2 s plays the new next song; Repeat All's wrap and Repeat One's loop
join sample-exact; a feed that ran out goes on when entries are appended.

## 10. Golden traces: `ios/scripts/export-traces.cjs`

**Purpose**: Swift replays exactly what the TypeScript did - same inputs, same random numbers, same state after
every op (the plan's R12).

**Run**: `TMPDIR=<writable> node ios/scripts/export-traces.cjs` writes
`ios/DeadwaxKit/Fixtures/upnext-traces.json` (the plan's Fixtures/ folder: outside the test target, so no
Package.swift change and no "unhandled file" warning; the test finds it from `#filePath`, up three folders).
`--check` regenerates in memory and exits 1 if the committed file differs ("traces are stale: run node
ios/scripts/export-traces.cjs"). Needs `npm ci` in ui/.

**Compile** exactly as upnext.sim.cjs:45-55, without DOM or JSX:
```js
const UI = path.resolve(__dirname, '../../ui')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-traces-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), ['src/lib/upNext.ts', 'src/lib/playQueue.ts', '--rootDir', 'src',
  '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022'], { cwd: UI, stdio: 'inherit' })
const U = require(path.join(OUT, 'lib/upNext.js')), Q = require(path.join(OUT, 'lib/playQueue.js'))
// ... fs.rmSync(OUT, { recursive: true, force: true }) at the end
```
(Verified: compiles; tsc also emits lib/loudness.js and lib/streamWrap.js, unused.)

**Two generators per trace, both Park-Miller** (section 4): the DRIVER `PM(seed)` chooses ops and arguments, which
are written into the ops, so Swift never re-derives them; the TAPE `PM(seed + 1_000_000)` is the ONLY `random`
handed to `startUpNext`/`toppedUp`/`withShuffle`, wrapped to log each draw. Each op records the tape's draws as the
generator's INTEGER states `s` (value = `Double(s - 1) / 2147483646`, bit-identical in both languages, no
float-through-JSON question).

**Songs**: one table `songs: {id: QueueTrack}`; an id names one song. Id grammar: first letter picks the album -
`m` Mezzanine/`mez`, `d` Dummy/`dum`, `x` Loose/albumId null (for "Still to play" and `oneAlbum` nil); title
`song <id>`, artist `Massive Attack`, coverArt = albumId, duration 200, flac, 44100/16/2. Lists draw ids so the same
id appears twice sometimes; added songs `<letter>n<k>`/`<letter>l<k>`, sometimes an id already in the list.

**Ops** (`op` and its arguments, exactly the function's):

| op | args | calls | records |
| --- | --- | --- | --- |
| `start` | `ids`, `start` (int or null), `shuffle`, `paged?` | startUpNext | state |
| `withNext` / `withLast` | `ids` | withNext / withLast | state |
| `withoutKey` | `key` | withoutKey | state |
| `movedKey` | `key`, `to` (int 0-5; sometimes 9) | movedKey | state |
| `withoutAdded` | - | withoutAdded | state |
| `withShuffle` | `on` | withShuffle | state |
| `withRepeat` | `repeat` | withRepeat | state |
| `toppedUp` | `repeat` | toppedUp | state |
| `jumpedTo` | `key` | jumpedTo | state, or `result: null` |
| `withMore` | `token`, `ids`, `next?` | withMore | state |
| `setIndex` | `index` | `{...q, index}` (the engine moving) | state |
| `onward`, `nextIndex`, `shownPass` | - | query | `result` |
| `backward` | `position` (0, 1, 3, 3.5, 40) | query | `result: {kind, index?}` |
| `pastCopies` | `from` (index, index+1) | query | `result` |
| `upNextView` | `repeat`, `limit` (1, 3, 100) | query | `result` (view, below) |

Every state-changing op records `same: true|false` (TS identity: `next === q`) and, when not same, `state`:
```json
{"index":2,"ids":["m1","m2","mn0"],"marks":[[0,"s",0,0],[1,"s",1,0],[5,"a",-1,-1]],"source":["m1","m2"],
 "shuffle":false,"nextKey":6,"startedAt":0,"left":[[0,3]],"paged":{...},"pagedRounds":[...]}
```
`marks` as resume's snapshot writes them (`[key, from char, at, pass]`); `marks`..`left` absent when there is no
`upNext`; `paged`/`pagedRounds` only when present (`[]` kept as `[]`). Every op with draws records `randoms: [s, ...]`.
A view: `{"playing": id|null, "added": [[key, id]], "list": {"title", "rows": [[key, id]], "more"}|null, "then",
"repeatOne"}`.

**Random traces** (150 seeds x 40 steps): start with a list of 1-6 songs (10% 12, 2% 130 for the cap), `start`
null 30%, shuffle 50% (75% of traces lean shuffled, so Shuffle x Repeat All draws), 10% paged
(`{token: "t1", total: n + 3k, fetched: n, scope}`); then `toppedUp(repeat)`. Each step one of: withNext, withLast,
withoutKey, movedKey, withoutAdded, setShuffle (`withShuffle` then `toppedUp`), setRepeat (`withRepeat` then
`toppedUp`), toppedUp, jump (`jumpedTo`; if not null `onward` then `setIndex`), Next (`onward`, `setIndex`,
`toppedUp`), end (`nextIndex`, `setIndex`, `toppedUp`), Previous (`backward`, `setIndex` on go), pastCopies,
shownPass, upNextView, and withMore when paged (token `t1` or a wrong `t0`; with `next` once fetched >= total).
Keys: 85% a row after index, else any int in `0..<nextKey+2` (covers the song playing, earlier songs, copies, later
rounds, unknown keys). Prototyped: deterministic (byte-identical re-runs), about 9 KB a trace (200 traces: 1.8 MB,
12,184 ops, 593 draws); 150 traces plus scenarios stays under 2 MB.

**Named scenarios** (`scenarios: [{name, ops}]`, same op format): one per upnext.sim.cjs check of lines 133-465,
named by its label, built as the sim builds it (album sizes, starts, seeds `PM(n)` used as the tape), plus: Previous
back across another song's copies (`1s* 1o 1o 2s 2o 2o 2o 3s`); Repeat One while an added song plays; a source of
two equal ids under Shuffle + Repeat All (the draw with `later` empty); Shuffle on at a song before `startedAt`;
withShuffle with no source mark at or before index (`round == -1`).

**File layout**: `{"version":1,"made_from":{"ui/src/lib/upNext.ts":"<sha256>","ui/src/lib/playQueue.ts":"<sha256>"},
"songs":{...},"scenarios":[...],"traces":[` then one trace per line (`{"seed":n,"ops":[...]}`), so a behaviour
change reads as a diff of the traces it touched.

**Swift replay** (`Tests/DeadwaxCoreTests/UpNextTraceTests.swift`): decode into test-only `Codable` structs; per trace
`q = .empty`; per op load a `Tape` with its `randoms`, call the function with `random: tape.next` (an exhausted tape
records an issue naming seed and op, and returns 0.5), then require `tape.remaining == 0`; `same` -> `result == q`;
else compare a projection of the result to `state` FIELD BY FIELD and report the first difference with seed, op
number and field - never `#expect(a == b)` on whole arrays (notes/ios.md "First run on macOS": Swift Testing's
collection diff killed the test process). Queries compare `result`. Add `ParkMiller` (Int64) to the test target for
the property test.

**Drift**: add `ui/test/iostraces.sim.cjs` running `node ../ios/scripts/export-traces.cjs --check`, so tests.yml
(which runs every sim, and runs for web-only commits that ios.yml's `ios/**` filter skips) fails when upNext.ts
changes behaviour without new traces; regenerating then touches `ios/**`, which runs ios.yml's Swift replay.

## 11. Order of work (suggested)

1. Core types and functions (sections 1-5) with `UpNextTests` (section 9's upnext.sim lines).
2. The exporter, the fixture and `UpNextTraceTests`; the drift sim.
3. `QueueController` + fake engine tests (player.sim sections).
4. `PlaybackEngine.replaceUpcoming` (section 7) with offline renders.
5. The views (section 8); replace Phase 0's `PlayQueue` in AppModel.

## Open questions

1. **An edit that changes a next song already scheduled on the heard song's node** (the last ~2.5 s of a song):
   AVAudioPlayerNode can't drop some scheduled buffers. Recommended: stop that node and go on from the exact frame
   reached (the lane-ran-dry path) - a short gap, only in that window - and listen for it on the phone; not two
   nodes per format (a bigger engine change for a rare moment).
2. **The drift sim** touches the web's test folder. Recommended: add it - it is the only check that runs when only
   upNext.ts changes.
3. **The lock screen's queue index and count** (Phase 0 sets both): with Repeat unrolled into the queue they grow
   without meaning. Recommended: stop setting `MPNowPlayingInfoPropertyPlaybackQueueIndex/Count` (the web sets none).
   Keep the lock screen's shuffle and repeat commands disabled, as Phase 0 and the web do.
4. **A library-shuffle (paged) queue resumed from the web in Phase 1**, before the feed (useShuffleFeed.ts, Phase 4):
   it would play what was fetched, then stop, while Up Next counts the unfetched songs. Recommended: port the paged
   state and `withMore` now (pure; traced), and port the feed (134 lines, two existing routes) with resume in Phase 1,
   since resume makes the queue reachable.
5. **`Shuffling your whole library` shows for a shuffle of all music too** (UpNext.tsx:333, any scope), while
   `shuffleLabel` says "all music". Recommended: port as is now; offer James the web fix on main first (CLAUDE.md's rule).
6. **Next or Previous while paused**: the web keeps the pause (`intendsToPlay`); Phase 0's app resumes
   (`resumeIfPaused`). A row's tap plays in both. Recommended: follow the web (Phase 1 follows the web app as it is).
