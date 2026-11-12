# Lyrics on Now Playing - the design (server, web app, iPhone app)

> Copied into the repo as reviewed (`deadwax-plans/lyrics-spec.md`, 2026-11-12), unchanged but for one thing: the
> example lines of a real song in 1.2, 3.2 and 3.6 are our own words here. What was built, and every departure from
> the spec, is at the end: "Built (2.1.5)" and "Built (2.1.6)".

Design spec, written 2026-11-12. James asked: **"Oh and I forgot I want to make sure you can view lyrics as well"**, and
chose: **both apps**; **like Apple Music** (synced lyrics with the line being sung lit and kept in view as the song plays,
a tap on a line to play from there; plain lyrics just scroll; opened from a **Lyrics** button on Now Playing); built
**right after Phase 2 (Downloads)**, so a downloaded song keeps its lyrics offline; and "let's not cut corners on design,
I like the direction things have been going" - so this is drawn as carefully as Phase 1's `screens.md`: every word
verbatim, VoiceOver, Dynamic Type, errors in a listener's words.

**Read against**: main `0d3e580` (deadwax 2.1.3) for the server and the web app, read with `git show main:<path>`; the
Phase 2 worktree `p2/downloads` `c650c19` (`.claude/worktrees/p2`) for the iPhone app, which is where the phone's code
will be when this is built; Navidrome **v0.64.2**'s own source (what James runs), fetched from
`github.com/navidrome/navidrome` at that tag; the OpenSubsonic spec (`opensubsonic/open-subsonic-api`,
`content/en/docs/Responses/structuredLyrics.md` and `line.md`). Every line number below is the file's at those commits.
**Re-checked in review** against main `985b5d6` (deadwax 2.1.4, which landed meanwhile): of the files cited, 2.1.4
touched only `src/routes/navidrome.py`, `tests/test_navidrome.py`, `tests/test_player_as_you.py`, `docs/player.md` and
`notes/player.md`; every line cited in the first three is where it was, the docs' may sit a few lines lower.
Where the apps have no precedent, Apple Music's own behaviour is followed **as remembered from iOS 16-18 and macOS
Music, not seen here** - section 5 says which, and how sure.

**In one paragraph, for James.** deadwax gains one read-only route, `GET /deadwax/navidrome/lyrics/{song_id}`, that asks
Navidrome for the song's lyrics as you (the same `.lrc` files deadwax already writes, which Navidrome reads by
default) and answers them in one plain shape: timed lines, plain lines, or none. On a phone, Now Playing gets a
**Lyrics** button beside Up Next; tapped, the lyrics take the cover's place - the line being sung lit, kept a third of
the way down, scrolling on its own until you scroll it yourself (it comes back four seconds after you let go, or when
you press play), a tap on any line playing from there; the button dims for a song with none. On a desktop, the player
bar's **Lyrics** opens them as the side panel, as Up Next does. The iPhone app draws the same thing natively, keeps
each downloaded song's lyrics with its download, and shows them on a plane. Nothing about how the music plays changes;
the lock screen is untouched.

---

## 0. The foundation - checked

### 0.1 What exists

- **Writing lyrics**: `src/lyrics.py` - LRCLIB, written as a `.lrc` beside each track, the sixth writer
  (`src/lyrics.py:1-46`). Synced when LRCLIB has timings, plain otherwise, with no header (`:20-24`), never replacing a
  `.lrc` already there (`:26-27`). The full story: `notes/library.md` "### Lyrics (v0.7.0)" (`:632-689`).
- **The lead**: `LYRICS_LEAD_MS` (`src/config.py:492`, read by `Config.lyrics_lead_ms()` `:682`) moves every synced
  timestamp earlier **as the file is written** - "It is written into the timestamps themselves, not as an `[offset:]`
  tag: Amperfy reads that tag and never applies it, and a player that did apply it on top of shifted timestamps would
  move them twice." (`src/lyrics.py:34-37`; `notes/library.md:706-712`). So **a file deadwax wrote already carries the
  lead**, and anything that reads it as it is shows the lines at the lead's times. (See 1.2: the route never applies the
  lead again.)
- **Reading lyrics today**: `GET /deadwax/library/lyrics?album=&file=` (`src/routes/library.py:1091-1105`), one track's
  lyrics from the `.lrc` beside it, else the file's own tags (`read_track_lyrics`, `src/lyrics.py:384-426`), answering
  `TrackLyrics` (`ui/src/api/types.ts:976-989`: `lines: LyricLine[]`, each `{ time: number | null; text: string }`,
  `time` in seconds). It is the Edit panel's track inspector's (`ui/src/app/TrackInspector.tsx:236-295`, "for the
  track viewer"), keyed by **a folder and a file name** - which a listener's app doesn't have.
- **The words and the clock**: `ui/src/lib/lyrics.ts` - pure: `describeLyrics`, `describeRetime` and `lyricTime`
  (`:63-67`, "`83.4` -> `1:23`. How a synced line's time is shown beside it."). The editor's side:
  `ui/src/components/RetimeLyrics.tsx`.
- **The web app's Now Playing kept a place for it**: "The board's Lyrics icon isn't drawn until there is something for
  it to open" (`ui/src/player/NowPlaying.tsx:136`); `notes/app.md:254-256`: "Only what does something today: no
  Lyrics, Up next or turntable buttons". Up Next and the turntable have since been drawn; Lyrics is the last of the
  three.

### 0.2 Why the listener's route goes through Navidrome, by song id

The apps know a song only by its **Navidrome id**. deadwax can't turn that into a folder and a file of its own:

- Pairing Navidrome's songs with files "needs paths Navidrome reports only with ReportRealPath, and an untagged file -
  the case hand edits are for - has no track number to pair by" (`notes/app-desktop.md:236-238`). Navidrome's Subsonic
  `path` is a made-up one by default.
- The id bridge (`src/routes/store_album.py:1-40`) joins **albums** through the MusicBrainz release id - an untagged
  album has none, and it says nothing about which file is which song.

**Navidrome already answers lyrics by song id** - OpenSubsonic's `getLyricsBySongId` (`server/subsonic/api.go:186`,
`server/subsonic/media_retrieval.go:125-146`), and reads exactly what deadwax writes:

- **The order of sources** is `LyricsPriority`, default `".ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded"`
  (`conf/configuration.go:1018`); the first source with any lyrics wins (`core/lyrics/lyrics.go:89-114`). A `.lrc`
  with the audio file's own name is found with no configuration (`notes/library.md:642-644` says the same, verified in
  its source then).
- **A sidecar is read from disk on every ask** (`core/lyrics/sources.go:28-69`: `fsys.Open(sidecarRelPath)`), so
  lyrics deadwax has just fetched or re-timed show at once, with no Navidrome scan. **Embedded lyrics** come from the
  scan (`sources.go:17-26`, `mf.Lyrics`).
- **Access is Navidrome's own**: the song is looked up through the media file repository, whose every read is
  filtered to the libraries the asker may see (`persistence/mediafile_repository.go:206-221`,
  `applyLibraryFilter`). A song that isn't theirs is "not found" (Subsonic code 70).
- **What it answers** (`server/subsonic/lyrics.go:16-71`, `server/subsonic/responses/responses.go:547-590`):
  `lyricsList.structuredLyrics[]`, each `{ displayArtist, displayTitle, lang, line: [{ start?, value }], offset?,
  synced }` - `start` in milliseconds, absent on a plain line (OpenSubsonic `line.md`: "If this is not part of synced
  lyrics, `start` **must** be omitted"). With no lyrics, `lyricsList` is `{}` (Navidrome's own snapshot, "Responses
  LyricsList without data"). Without `enhanced=true` only main-kind entries come back (`lyrics.go:18-26`).
- **`offset`** comes from an `[offset:]` tag in an LRC file (`model/lyrics_lrc.go:89-97`); OpenSubsonic: "Positive
  means lyrics appear sooner, negative means later" (`structuredLyrics.md:322`). deadwax never writes one (0.1).
- **Blank lines** (`model/lyrics_lrc.go:70-77`): a TIMED empty line is kept as a line with `value: ""` - the break
  LRCLIB writes between verses ("keeps empty break lines", `notes/library.md:699`). An UNTIMED blank line is dropped,
  in synced and plain text alike - so **plain lyrics reach the apps with their verses run together** (Open question 9).
  An untimed text line inside synced lyrics is joined to the line before it with a newline (`:122-127`). (Re-read in
  review: in unsynced text `validLine` is never set, so `if line == "" { if validLine {...}; continue }` skips every
  blank line; in synced text an untimed blank line only appends a newline to the line before, which
  `parseEnhancedLine`'s `strings.TrimSpace` then takes off again.)
- **A file is "synced" if any line starts with a stamp** (`syncRegex`), whatever the stamps say - so a file LRCLIB holds
  with every line at `[00:00.00]` arrives as synced lyrics whose every line is at 0 (1.2's rule 3).

This is also what Amperfy shows, so the phone, the web app and Amperfy agree on what a song's lyrics are.

---

## 1. The server: `GET /deadwax/navidrome/lyrics/{song_id}` (a 2.1.x patch on main)

### 1.1 The route

- In `src/routes/navidrome.py`, after `/songs/{song_id}` (`:435-447`), whose shape it copies:
  `song_id: str = PathParam(..., min_length=1, max_length=ID_MAX)` (`ID_MAX = 256`, `:394`).
- **One Subsonic call, as the asker**: `client_for(request).call("getLyricsBySongId", {"id": song_id})`. Nothing else
  the page sends reaches Navidrome - no `enhanced`, no query parameters at all. Not added to `SHARED_ACCOUNT_USES`
  (`src/api/navidrome_endpoint.py:304-307`): it never asks as the shared account but with logins off or for the
  break-glass admin, through `client_for` as every route does.
- **deadwax's own answer, not a relay**: Navidrome's body is shaped by a pure function in `src/lyrics.py`,
  `song_lyrics(body: dict) -> dict` (1.2), and sent with `json_with_etag` (`src/api/json_etag.py:13-31`).
- The module's docstring (`navidrome.py:1-14`) gains its sentence, as each addition has: "Lyrics, 2.1.N's
  /lyrics/{song_id}: getLyricsBySongId as the asker with the id alone, shaped by src/lyrics.py song_lyrics() - see
  after /songs."

### 1.2 What it answers

```json
{ "synced": true,
  "lines": [ { "time": 0.0, "text": "" },
             { "time": 25.1, "text": "The first line sung" },
             { "time": 26.56, "text": "The second line" } ] }
```

The same `lines` as `TrackLyrics` (`LyricLine`: `time` in seconds or `null`, `text`), so the web's type is reused.
Three cases, and only three:

| case | answer |
| --- | --- |
| synced | `synced: true`, every line timed, in time order |
| plain | `synced: false`, every `time` `null`, in the file's order |
| none | `synced: false`, `lines: []` - a **200**, never a 404: "none" is a fact about the song, kept apart from a failure as `lyrics.py` keeps `missing` apart from `failed` (`notes/library.md:656-660`) |

`song_lyrics()`'s rules, each its own test (1.7):

1. **Which entry.** From `lyricsList.structuredLyrics` (missing, or not a list: none), take the **first synced entry
   with a line that has words**; else the **first entry with a line that has words**; else none. (Several entries are
   possible: an embedded tag per language. Translations aren't asked for - no `enhanced`.)
2. **Times**: `time = max(0, start - offset) / 1000`, rounded to the millisecond (`round(x, 3)`), `offset` 0 when absent
   - "lyrics appear sooner" for a positive offset, as the spec says. **`LYRICS_LEAD_MS` is never applied here**: it is
   already in the timestamps of every file deadwax wrote (0.1), and applying it again would "move them twice"
   (`src/lyrics.py:36-37`); lyrics deadwax didn't write (embedded, hand-made) are another source's timings, which the
   lead was never about (Open question 10).
3. **Synced or plain is decided by the lines**: synced only when every line with words has a `start` **and those starts
   are not all one time**. An entry that says `synced` but has a line with words and no time is answered as plain
   (times dropped), and so is one whose every worded line carries the same stamp (0.2: LRCLIB holds some at all zeros,
   which would light the first line for the whole song) - a lit line that can't be trusted is worse than none.
4. **Synced lines are sorted by time**, stably (a hand-made `.lrc` can be out of order; Navidrome sorts only when a line
   carries several stamps, `model/lyrics_lrc.go:169-175`). A timed empty line stays: it is the break the apps draw
   (2.4).
5. **Text**: `value` with trailing spaces taken off each of its own lines; a newline inside a value kept (an untimed
   line Navidrome joined on, 0.2); nothing else changed. Leading and trailing EMPTY lines of plain lyrics dropped; of
   synced lyrics kept (the first is an intro's break, at 0).
6. **Bounded**: at most 2,000 lines and 1,000 characters a line (`LYRICS_LINES_MAX`, `LYRICS_TEXT_MAX`, `#?`-commented
   like the module's other limits) - far past any song; a file that isn't lyrics doesn't become a megabyte answer.

`displayArtist`, `displayTitle` and `lang` aren't passed on: nothing draws them (the apps show the song's own title,
and Navidrome's `lang` is ISO 639-2, "xxx" for an LRC, which a browser's `lang` attribute doesn't take as English).

### 1.3 Where it reads from

Navidrome, only: the song's `.lrc` (or `.ttml`, `.elrc`, `.srt`, `.txt`, `.yaml`) beside it by `LyricsPriority`, else
its embedded tags. deadwax reads no file and asks LRCLIB nothing on this route. **A listener never causes a write**:
"Get lyrics" stays the Edit panel's and Library care's (Open question 6).

### 1.4 Who may ask

- **`"user"`** in `tests/test_logins.py` `ROUTES`, beside `("GET", "/deadwax/navidrome/songs/{song_id}"): "user"`
  (`:172`) - anyone signed in, no permission: lyrics are part of playing a song, as the stream and Info's song are.
- **Which songs**: Navidrome's library filter decides (0.2). With logins off, or the break-glass admin, it asks as the
  shared account, which sees everything - as every player route does.
- A GET that writes nothing: the same-origin guard has nothing to guard.

### 1.5 Caching

- **No cache on the server.** Navidrome reads a sidecar from disk per ask (cheap, local); a cache in deadwax would show
  old lyrics for its lifetime after a Get lyrics or a re-time - the one moment someone is looking.
- **An ETag on the answer** (`json_with_etag`: `Cache-Control: no-cache` and `ETag`, a 304 when unchanged) - the
  browser revalidates every ask and a phone over WireGuard gets a 304 with no body, as `/album_index` does
  (`src/api/json_etag.py:1-4`). The apps keep the last answer per song in memory (2.6) only to draw at once while the
  revalidation is on its way.

### 1.6 Failures (each through `_fail`, `navidrome.py:110-111`, as every route)

| what | status | detail |
| --- | --- | --- |
| a song Navidrome won't give them, or gone (code 70) | 404 | Navidrome's "not found" words (`SUBSONIC_ERRORS` `:79`, "Navidrome has nothing by that id"; code 70 is 404 in `subsonic_body`, `navidrome_endpoint.py:139-151`) - never shown to a listener: errorWords' not-found says a fit detail as sent when the page passes no `gone`, and this one names Navidrome, so both apps pass `SONG_GONE` (2.1) |
| Navidrome's login refused mid-session | 401 | as every route (the session ends - `notes/logins.md`) |
| Navidrome not set up | 503 | `NOT_CONFIGURED`'s "Server settings (Connections)" sentence |
| Navidrome down, or an answer that isn't Subsonic's | 502 | `unreachable()` / "the answer wasn't..." |
| `song_id` over 256 characters | 422 | FastAPI's, nothing asked |

The apps say each in a listener's words (2.1).

### 1.7 Tests

- **`tests/test_navidrome_lyrics.py`** (new), against the fake upstream the other route tests use, answers shaped from
  Navidrome's own snapshot (`server/subsonic/responses/.snapshots/Responses LyricsList with data should match .JSON`:
  two entries, `offset: 100`, one synced with `start` 18800 and 22801, one plain):
  - synced: times in seconds, the offset taken off (18.7, 22.701), sorted, a timed empty line kept;
  - the first synced entry chosen over a plain one listed before it; the first with words over an empty one;
  - plain: every `time` null, an untimed newline-joined value kept with its newline, edge blank lines dropped;
  - a negative result held at 0; a negative offset moving lines later;
  - "synced" with an untimed worded line answered as plain; "synced" with every worded line at `start: 0` (or at any
    one time) answered as plain; two worded lines at one time and a third later stay synced (a duet's shared stamp);
  - none: `lyricsList: {}`, a missing `lyricsList`, entries whose lines are all empty - each `{synced: false, lines: []}`
    with 200;
  - **only `id` is sent** to Navidrome, and only `getLyricsBySongId` is called;
  - code 70 -> 404; a 401 ends the session as elsewhere; not configured -> 503; 257 characters -> 422 with nothing asked;
  - the ETag: a second ask with `If-None-Match` is a 304 with no body; a changed `.lrc` (the fake's answer changed) is a
    200 with a new ETag;
  - the bounds: 2,001 lines answer 2,000; a 5,000-character line is cut at 1,000.
- **`song_lyrics()` pure**, in the same file (no client): the rules of 1.2 one by one.
- **`tests/test_navidrome.py` `test_there_is_no_general_proxy`** (`:229-298`): `"/lyrics/{song_id}"` added to the
  sorted list, and its paragraph in the docstring, as every addition has: "`/lyrics/{song_id}` joined it in 2.1.N,
  deliberately: a song's lyrics for Now Playing - getLyricsBySongId as the asker with the id alone, bounded, and
  deadwax's own shape of what it answers (src/lyrics.py song_lyrics()); nothing else the page sends is passed on - see
  test_navidrome_lyrics.py."
- **`tests/test_logins.py`**: the `ROUTES` entry (1.4), with a `#?` line: "(2.1.N) a song's lyrics, as the asker -
  Navidrome's access".
- **`tests/test_player_as_you.py`**: `WALK` (`:397`) gains `"/lyrics/{song_id}": [("get", f"/lyrics/{SONG}")]` - the
  walk test (`:481`) fails until it does - and the fake answers `getLyricsBySongId`; the as-you test (`:485`) then holds
  it to `[("ethan", "getLyricsBySongId")]`.
- **`tests/test_ios_contract.py`** on main is unchanged by this commit (main's Swift has no `Routes.lyrics`); the phone's
  commit moves `ROUTE_COUNT` (`:49`) from 23 to 24 on the ios branch (4.8).

### 1.8 Docs and notes (same commit)

The route alone changes nothing anyone can see, so it can ship as its own patch whose message says so; or with the web
app's part (3), which needs the docs. Either way:

- `notes/player.md` (the Navidrome relay's notes): a section "### Lyrics by song id (2.1.N)" - the route, why through
  Navidrome (0.2), the rules of 1.2, what Navidrome drops (blank lines of plain lyrics).
- `notes/library.md` "### Lyrics (v0.7.0)": one line pointing to it ("Since 2.1.N the apps show a song's lyrics on Now
  Playing, read through Navidrome - notes/player.md "Lyrics by song id"").

### 1.9 The commits on main

1. **deadwax 2.1.N**: the route, `song_lyrics()`, its tests and notes. "Changes nothing a user could notice" (the web
   app doesn't ask it yet) - said in the message, per CLAUDE.md's Conventions.
2. **deadwax 2.1.N+1**: the web app's Lyrics (section 3), with README, `docs/player.md`, `docs/troubleshooting.md` and
   `docs/configuration.md` (3.8). This is the one James sees; `:experimental` has it on the next push.

Then main merges into ios (as every 2.1.x has), and the phone's part (section 4) is built on ios after Phase 2's merge.
If James tags either, its release notes are written then (CLAUDE.md "Branches and versions"): **New**: lyrics on Now
Playing; **Upgrading**: nothing to do - and, first, "deadwax reads lyrics through Navidrome: if you set
`ND_LYRICSPRIORITY` and left `.lrc` out, deadwax's own lyrics files won't show".

---

## 2. What both apps share: the words and the rules

Pure, in a new **`ui/src/lib/lyricsView.ts`** (importing `lyricTime` from `lib/lyrics.ts`), and in the phone's Core as
`Lyrics.swift`, held to the TypeScript by an exporter (4.8). Every rule below is one exported function or constant.
Not added to `lib/lyrics.ts` itself: that module is the editor's (`describeLyrics`, `describeRetime`, whose words say
"LRCLIB" to whoever runs deadwax), and a listener's words are kept in files of their own - as Debug's are kept out of
Now Playing's in `lib/debugRows.ts` - so `vocabulary.sim.cjs` can hold the new file to a listener's words, and the
exporter ports exactly the view's rules and nothing of the editor's.

### 2.1 The words (verbatim)

| where | words | constant |
| --- | --- | --- |
| the Lyrics button, its name (off and on - "on" is said by `aria-pressed` / VoiceOver's "Selected") | **Lyrics** | `LYRICS` |
| ...when this song has none (dimmed, unless lyrics are on - 2.7) | **Lyrics - none for this song** | `LYRICS_NONE` |
| ...the phone only, offline, with none kept for this song | **Lyrics - not on this phone** | `LYRICS_NOT_KEPT` |
| the desktop panel's title, and its button | **Lyrics**, **Done** | `LYRICS`; Info's `Done` |
| while asking - the spinner's name | **Loading lyrics** | `LOADING_LYRICS` |
| none, where a place must say something (the desktop panel) | **No lyrics for this song.** | `NO_LYRICS` |
| the desktop panel with nothing playing - the player bar's own words (`PlayerBar.tsx:69`) | **Nothing playing** | `NOTHING_PLAYING` |
| plain lyrics, above the first line | **These lyrics aren't synced to the song.** | `NOT_SYNCED` |
| a failure | `errorNote(error, { failed: "Couldn't load the lyrics.", gone: SONG_GONE, retry: true })` and a **Try again** button - no Try again for a gone (`errorKind` `not-found`): there is nothing to try | `LYRICS_FAILED` |
| ...a 404: the song isn't Navidrome's any more (a queue older than a rescan) or not theirs - `ALBUM_GONE`'s pattern (`player/AlbumPage.tsx:122`) | **This song isn't here any more - it may have been moved or deleted.** | `SONG_GONE` |
| a line's time, for VoiceOver | `lyricTime(time)` - **1:23** | (existing, `lib/lyrics.ts:63-67`) |
| the lit line, the phone's VoiceOver value | **1:23, now** | `lineValue(time, lit)` |
| a line's VoiceOver hint (the phone) | **Plays from here.** | `LINE_HINT` |
| the lyrics' VoiceOver action (the phone) | **Go to the line being sung** | `GO_TO_LIT` |

- The failure: `errorWords` (`ui/src/lib/errorWords.ts:82-95`) says "Couldn't load the lyrics." in place of an
  unreachable's or an other's sentence; offline it is still "Can't connect to deadwax." with "Check your connection."
  (`OFFLINE`, `OFFLINE_RETRY`, `:54-57`), a 401 "Your sign-in has ended - sign in again." (`:59`). The service is the
  music server's, from the path (`/navidrome/...`). Whoever runs deadwax sees the detail under it (`seesDetail`). The
  phone: `ErrorWords.of(error, gone: SONG_GONE, failed:, retry: true)` (`ErrorWords.swift:153-154`) through `ErrorNote`
  (`ios/App/Shared/ErrorNote.swift:20`), and `LibraryWords.tryAgain` "Try again" (`LibraryWords.swift:25`).
- Never "Navidrome", "LRCLIB", "sidecar", ".lrc", "embedded" or "offset" for a listener (`ui/test/vocabulary.sim.cjs`
  `:5-12`'s rule). "synced" is already a listener's word in deadwax (the track view's mark, "Saved lyrics for 9 tracks
  (all synced)").
- Title case for the button's one word, sentence case for sentences - as Phase 1's. "Lyrics - none for this song"
  is the app's own pattern for a control named with its state: "Up Next - Shuffle and Repeat all", "Shuffle -
  shuffling your whole library" (`upNextLabel`, `shuffleLabel`) - a spaced hyphen, the state in lower case.
- "Couldn't load the lyrics." beside the app's other listener failures ("Couldn't load their songs.",
  `lib/artistPage.ts:361`; "Couldn't load that release.") - not the Edit panel's "Couldn't read this track's lyrics."
  (`TrackInspector.tsx:255`), which is about a file.

### 2.2 The clock

- **Web**: the lit line is judged by `lyricsClock(raw, reported)`: `raw` is `player.position()` (the element's own time
  in the song, `usePlayer.ts:439-442 songPosition()` - exact to the frame) and `reported` the last `usePosition` value
  (`usePlayer.ts:2191-2195`, which shows a seek's target until it lands - `reportedPosition`, `lib/scrub.ts:130`).
  `|raw - reported| > LANDED_WITHIN_S` (1.5 s, `lib/scrub.ts:44`) means a seek is on its way: `reported`; else `raw`. So
  a tap on a line lights it at once, and nothing flickers back while the seek lands. No engine file changes: both are
  the player's existing API.
- **Phone**: `PlayerModel.clock()` (new, a read): `Scrub.reportedPosition(pendingSeek, position: heard, now:
  Self.nowMs())` - the same rule, from the engine's position "how far in as heard" rather than the 0.5 s ticker's
  `position` (`PlayerModel.swift:37-38`, `:872`). `heard` is `link.position()`'s seconds **only when its key is the
  entry heard's** - the tick's own check (`:888-890`: `at.key == link.engineKey(entry.key)`) - else `position`: at a
  join the engine can still be answering for the song before, and `heardSeconds()` (`:903`, private) checks no key, so
  `clock()` doesn't call it. The pending seek is let go by the tick (`Scrub.settled`, `:892`), as the scrubber's is.
- **Paused, or covered**: on both, the clock stops - while the song is paused, while Up Next, Info or the ••• menu is
  over Now Playing (the web's `covered`, `NowPlaying.tsx`; the phone's `showsUpNext || showsInfo`), and while the page
  is hidden or the app isn't active. Stopped, the view still redraws on a seek: the web from `usePosition`, the phone
  because the view reads `player.shownPosition` (observed) beside the clock - so a scrub while paused lights its line.
- **Speed** (the web's 0.25x-2x): song time is song time; nothing to do.
- **How often**: the web reads it once per animation frame while the lyrics show, the song plays and the page is
  visible, and draws only when the lit line (or a dot, 2.4) changes; the phone in a `TimelineView(.animation(
  minimumInterval: 0.1, paused: !player.isPlaying))` - ten a second, Amperfy's own rate (`notes/library.md:700-701`).
- **No display lead of the apps' own.** `LYRICS_LEAD_MS` is the one setting for "a beat late", in every player at once
  (Amperfy included). Check W4 and P4 are how James sets it.

### 2.3 The lit line

- `litRange(lines, t)`: the lines whose time is the greatest time not after `t` - one line, or several sharing a stamp
  (a duet written once per voice). Before the first timed line: none lit (an intro, 2.4). Binary search; the lines are
  sorted (1.2).
- Lit: full text colour. Every other line - before and after - one dimmer colour (3.5, 4.3). No size change, no scale:
  a lit line growing would rewrap and move the lines under the reader.
- Plain lyrics have no lit line.

### 2.4 Breaks, and the dots

- **A timed empty line is a break** (LRCLIB's between verses, 0.2). Not lit, it is a gap of `--dw-lyric-break` (half a
  line) - so verses read as verses.
- **Dots while nothing is sung**: when the lit line is a break **and** the next line with words is at least
  `GAP_DOTS_S` (4 s) away, the break draws three dots in the lyric's own size, lighting one by one - the first at the
  break's start, the second a third of the way to the next line, the third two thirds (`gapDots(lines, i, t) -> 0...3`).
  An **intro** of 4 s or more before the first line is drawn the same, as a break at 0 (`withIntro(lines)` adds it for
  the view when the lyrics don't start with one). A break with no line after it (an outro) draws no dots.
- Driven by the clock, not an animation: it steps, and Reduce Motion changes nothing about it.
- Decorative: hidden from VoiceOver.

### 2.5 Following the song, and the listener's own scroll

- **Following**: the lit line is scrolled to `LYRICS_ANCHOR` (0.3) of the lyrics' height from its top -
  `followTop(lineTop, height) = max(0, lineTop - height * LYRICS_ANCHOR)`. Room after the last line (`(1 - 0.3)` of the
  height) lets the last line reach the anchor too. A new lit line scrolls smoothly; Reduce Motion jumps.
- **The listener's own scroll holds it**: a touch that moves the lyrics, a wheel, a scroll key in them, a drag of the
  scroll bar - each sets `heldAt = now`. While held, the lit line still lights, and the lyrics stay where the listener
  put them.
- **It comes back** `FOLLOW_AGAIN_MS` (4,000 ms) after the last such input **while the song plays**
  (`follows(now, heldAt, playing)`), scrolling back smoothly. Measured from the last input, not the last scroll, so a
  fling's momentum (no input, still scrolling) runs out first. **Paused, it stays where the listener put it** - nothing
  is moving to follow, and someone reading ahead with the song paused is reading; a play (the transport's, or a tap on
  a line) brings it back at once, the 4 s long past. A timer, not the clock: it fires with no frame being drawn.
- **The lit line is never under a fade**: the lines start below the top fade (the list's top padding is the fade's
  height, `--dw-lyrics-fade` / 24 pt), so the first line at the very top isn't half faded out, and the anchor (0.3 of
  the height) sits below the fade at any height the lyrics are given (the shortest, a phone on its side, has the
  smallest fade - 3.5).
- **A change of size re-follows at once** (no animation) while following: a phone turned, the desktop panel's column
  appearing, Dynamic Type changed - a `ResizeObserver` on the scroller on the web, the `GeometryReader`'s size on the
  phone.
- **At once** when the listener taps a line (it seeks, and that line is followed), when the song changes (the new
  song's lyrics start at their top, no animation), and when the lyrics are opened again.
- **Keyboard and VoiceOver focus inside the lyrics hold it** for as long as they are inside, and for
  `FOLLOW_AGAIN_MS` after they leave - following never scrolls the line being read out from under the reader.

### 2.6 When lyrics are asked for, and kept

- **The song playing's** are asked **at each song change**, on both frames and in the phone app, Now Playing open or
  not - and, if not in hand, when the page becomes visible / the app active again. One small ask a song (a 304 for a
  song asked before), and it buys the right button the moment Now Playing opens: asked only on opening, the button
  would start enabled and dim a moment later for an instrumental, and lyrics left on would open on a spinner. (The
  desktop needs it anyway: its bar's Lyrics is always in view and dims for a song with none.) Never while the page is
  hidden or the app is in the background - a locked phone asks nothing.
- **The phone asks with the answer's ETag** (`DeadwaxClient.fetch(_, ifNoneMatch:)`, `DeadwaxClient.swift:112-122`, as
  `/album_index` is asked - `AlbumIndexState.swift:36`): `.unchanged` keeps the answer in hand. It has no URL cache
  doing this for it, as Safari does for the web app.
- **The next song's** too, while the lyrics show, once the song playing has 20 s or less left (`NEXT_LYRICS_S`) - so
  they're in hand at the join.
- **Kept in memory per song**: the last 50 answers (`LYRICS_KEPT`), least recently used going first - to draw at once,
  while the ask (a 304, usually) is on its way. Never stored by the web app.
- Through `latestOnly()` (`ui/src/lib/latest.ts:21`) per song: a song changing mid-ask never draws the last one's words.
- A failed ask keeps nothing; the next opening or song change asks again. (The phone keeps downloaded songs' answers,
  4.7.)

### 2.7 The Lyrics button's states

| the song's lyrics | lyrics off | lyrics on |
| --- | --- | --- |
| not asked yet, or being asked, or the ask failed (a gone included) | enabled, **Lyrics** | pressed, **Lyrics** - the face shows the spinner or the failure |
| synced or plain | enabled, **Lyrics** | pressed (accent), **Lyrics** - the face shows them |
| none | dimmed (`aria-disabled`, `--app-pin-off`), **Lyrics - none for this song**, a tap does nothing | pressed, **Lyrics - none for this song** - the face shows **the cover** (3.1); a tap turns lyrics off |
| (phone) offline, none kept | dimmed, **Lyrics - not on this phone** | pressed, the same words, the cover shows |

A button that is on can always be turned off; one that is off is dimmed only when we know it would open nothing. While
an answer is on its way it is enabled - most songs filed by deadwax have lyrics, so the button starts as it usually ends.

---

## 3. The web app

### 3.1 Now Playing on a phone

**The button.** In the footer (`NowPlaying.tsx:434-468`), between AirPlay and Up Next:

```
[speed chip …]            [AirPlay?] [Lyrics] [Up Next] [•••]
```

- The footer's rule (its comment, `:430-433`): "••• is always there, at the right end, and Up Next always beside it;
  AirPlay comes and goes to their left, so nothing moves when a speaker does". Lyrics is always there too, so it joins
  the fixed group, left of Up Next - AirPlay still comes and goes at the group's left and moves nothing. (Apple Music's
  own order is Lyrics, AirPlay, Up Next; with an AirPlay that comes and goes, Lyrics can't sit left of it without moving.)
- `<button type="button" class="pl-icon-button app-np-lyrics{on ? ' is-on' : ''}" aria-pressed={on}
  aria-disabled={dimmed} aria-label={lyricsLabel(state)}>` with `LyricsIcon` - a speech bubble holding a quote mark,
  drawn in `player/icons.tsx` with its `line` helper (`:17-25`: 24-unit box, 2.2 stroke, round caps), the set's own
  manner. Off, the footer's own `--pl-text-2` (`player.css:860`), as Up Next and •••; on, `--dw-accent`, exactly as
  Shuffle and Repeat are on the transport (`app.css:5641 .pl-transport .app-np-mode.is-on { color: var(--dw-accent) }`;
  "one control lit for one state", `notes/app.md` "### Shuffle and Repeat on Now Playing's main screen (2.0.14)").
  Dimmed: `opacity: var(--app-pin-off)` (`app.css:298`), and no press drawn (`:active { background: none }`, as
  `app.css:5644` for the dimmed Shuffle).
- **At 320 wide** the footer must still fit: the body's content is 264px (320 less the 28px sides), and the speed
  chip ("1.25x", about 55px), AirPlay, Lyrics, Up Next and ••• with their 12px gaps (`--pl-footer-gap`,
  `player.css:155`) need 279. The gaps give way before anything else: under `(max-width: 359px)` the footer's gap is
  `--pl-footer-gap-narrow` (4px) - 235px - and every button keeps its 44px target. (2.0.14 holds the transport to 320
  the same way: "there (and only that narrow) the middle three give up width".)
- The ••• button's name (`:460`) doesn't change: Lyrics isn't in the menu.

**The face.** Lyrics on, the lyrics take the cover's place - the art box inside the grip (`:347-352`) - and everything
from the title down stays exactly where it is:

- **The body doesn't move.** "THE BODY IS ANCHORED TO THE BOTTOM of the sheet ... Everything from the title down is
  therefore a fixed height" (`:150-155`). The title, "Artist — Album", the scrubber, the transport and the footer are
  drawn as with the cover. (Apple Music moves the title up beside a small cover when its lyrics show; deadwax's anchored
  body keeps it where a finger already knows it - section 5, Open question 4.)
- **The grip is the top row alone while lyrics show**, as on the turntable: `class="pl-sheet-grip app-grip-top"`
  (`:328`, `app.css:1140 .pl-sheet-grip.app-grip-top { flex: none; }`). The lyrics sit OUTSIDE the grip, so scrolling
  them never drags the sheet down, and a drag down from the chevron's row still closes it.
- **The lyrics fill the room the grip gave up** (`flex: 1 1 auto; min-height: 0`), between the top row and the body,
  **in the body's own box**: `width: 100%; max-width: 520px; margin: 0 auto` and the 28px sides, as `.pl-sheet-body`
  has them (`player.css:684-690`; the 28px as a token, 3.5). So a line starts exactly where the title does - on a
  phone, and on a wider window still in the phone frame (an iPad upright), where the body is centred at 520px and lyrics
  as wide as the sheet would start somewhere else.
- **The sheet is drawn as the cover's while lyrics show**: no `app-is-turntable` class, whichever look is under them -
  that class centres the titles, lays a failure over the plinth and hides the speed chip (`app.css:1144-1160`, `:1463`) for the record's sake, and
  with the record gone they'd be centred under nothing.
- **The look button stays** at the top right (`:337-343`) and keeps its meaning: it shows the other look - and lyrics
  give way to it (lyrics off). "Show as a turntable" from lyrics over the cover shows the turntable; "Show the cover"
  from lyrics opened over the turntable shows the cover.
- **Lyrics over the turntable** are drawn as over the cover: the record and its arm aren't mounted while lyrics show
  (the deck stops, as the look button's switch to the cover stops it), and the body has the cover look's Scrubber in
  place of `TurntableTime`. Lyrics off goes back to the look it came from - to the turntable with `wakeDeckAudio()` in
  that tap, as `onLook` does (`:311-315`).
- **A song with none, lyrics on**: the face is the cover (never the turntable - it is not a tap's moment to start a
  deck), the button pressed and named "Lyrics - none for this song"; the next song with lyrics shows them again.
- **Kept on while the page lives** (Open question 1): close Now Playing with lyrics on and open it again, and they are on.
  In memory (App's), not a setting, not stored. Unlike the look, which "every opening starts as the setting says"
  (`:233-236`) - the look is a setting; lyrics are something you're doing.
- The failure line above the title (`:374`) and the silent record's (`:376`) are unchanged.

### 3.2 The view (`ui/src/player/Lyrics.tsx`, both frames)

One component, drawn by Now Playing's face (phone) and by the desktop's panel (3.4), given `player`, the song's
answer state (from `app/useLyrics.ts`, 2.6) and whether it shows.

```
<section class="app-lyrics" aria-label="Lyrics">                               (padding-top: the fade, 2.5)
  <p class="app-lyrics-note">These lyrics aren't synced to the song.</p>      (plain only)
  <ol class="app-lyric-lines">
    <li class="app-lyric-break" aria-hidden="true">  [• • •] </li>          (a break; dots per 2.4)
    <li><button type="button" class="app-lyric" aria-current="true" tabIndex="0">
          The first line sung<span class="app-visually-hidden">, 0:25</span></button></li>
    <li><button type="button" class="app-lyric" tabIndex="-1">The second line<span …>, 0:26</span></button></li>
    …
  </ol>
  <div class="app-lyrics-end" />                                               (the room after the last line, 2.5)
</section>
```

- **The scroller** is `.app-lyrics` itself: `overflow-y: auto`, `overscroll-behavior: contain`, **`touch-action:
  pan-y`** (the sheet is `touch-action: none`, `player.css:605`; the touch's allowed actions are worked out up to the
  scroll container, so the scroller's own `pan-y` wins - check W10), no scroll bar drawn on a phone
  (`scrollbar-width: none`), a fade at its top and bottom edges (`mask-image`, `--dw-lyrics-fade`) so lines come in and
  go out softly rather than being cut - a gradient, not a blur (the restyle's "no blur, no glow", `theme.css:445`).
- **Synced lines are buttons** (a tap plays from there, 3.3); **plain lines are `<p>`s** in the `<li>`s - nothing to
  tap. Every line `dir="auto"` (as the title is, `:377`), `white-space: pre-line` (a joined line keeps its break, 1.2).
- **A line's tap target is the line and half the space either side of it**: the space between lines is the buttons'
  own vertical padding (`calc(var(--dw-lyric-space) / 2)` each side, no margin), so the targets abut - no dead gap a
  tap between two lines falls into - and a one-line lyric is 26 x 1.25 + 12 = 44.5px tall, a tap target. Each button is
  the line's whole width; its press (`--dw-pressed`, `--dw-radius-control`) reaches `--dw-lyric-press-reach` (8px) past
  the text either side (`padding-inline` with the same negative `margin-inline`), so the words stay in line with the
  title while the press is a box around them, as Apple Music flashes one.
- **The lit line**: `aria-current="true"` and the lit colour; `transition: color var(--dw-duration) var(--dw-ease)`.
- **Loading**: `<div class="pl-spinner" aria-label="Loading lyrics" />`, centred in the area - the app's own spinner on
  every listener page (`Home.tsx:116`, `PlaylistPage.tsx:507`, `NeedsALook.tsx:375`'s "Reading the library").
  **Not** `components/Loading.tsx`: that is the retired main page's sweeping bar, drawn now only inside the desktop's
  Edit panel and Server settings (`app-desktop.css:1435-1466`, `:3237`) - on Now Playing it would be unstyled text.
  Shown only when there is no kept answer to draw.
- **A failure**: `errorNote(error, { class: 'app-lyrics-error', failed: LYRICS_FAILED, gone: SONG_GONE, retry: true })`
  and a **Try again** button (the app's secondary button) that asks again - none for a gone - centred where the lyrics
  would be. A kept answer is drawn instead of a failure when there is one (a revalidation that failed is no news).
- **None**: the phone's face shows the cover (3.1); the desktop panel says **No lyrics for this song.** in its body, in
  `--dw-text-3`, a footnote's size.
- **Following** (2.5): `scroller.scrollTo({ top: followTop(...), behavior: reduced ? 'auto' : 'smooth' })`, `reduced`
  read from `matchMedia('(prefers-reduced-motion: reduce)')` - an explicit `smooth` would override the theme's
  `scroll-behavior: auto !important` (`theme.css:420-430`). Listener input from `wheel`, `touchmove`, `keydown` (scroll
  keys) and `pointerdown` on the scroller itself (its scroll bar) - never the `scroll` event, which following's own
  scrolls fire too.
- **Its clock runs** (2.2) only while it shows, the song plays, nothing is over it (`covered`) and
  `document.visibilityState === 'visible'`; stopped, it redraws only on `usePosition`'s updates (a seek).
- **On a desktop, a line under the mouse** shows it can be clicked: `cursor: pointer`, the press box's
  `--app-desk-hover` background and the line in `--dw-text-2` if it isn't lit - as the bar's own buttons answer a hover
  (`app-desktop.css:482`), and as Mac Music's lyrics do. Inside the desktop queries only.
- **The song changing**: the new song's state, lines at their top, following on.
- `latestOnly()` for every ask (CLAUDE.md "Only the newest answer draws").

### 3.3 A tap on a line

- **Seek, and play if paused**: `player.seek(line.time)`, then, when `!player.playing`, `player.toggle()` - both in the
  click, nothing awaited before them (CLAUDE.md's gesture rule), and following comes back at once on that line.
  (Apple Music plays from a tapped line - whether it does so from a pause is the one thing here not remembered for sure:
  check W3 compares it on James's phone; Open question 2.)
- **The gesture rule** (`ui/test/app-rules.sim.cjs`): `seek` isn't one of the watched actions (`actionsIn`, `:355-358`
  finds `playTracks…restoreQueue`, and `toggle`, `next`, `previous` as members), but `toggle` is. So `ALLOWED`
  (`:310-348`) gains `'player/Lyrics.tsx': ['toggle']` with its comment line - "(2.1.N) a line of the lyrics: a tap plays
  from it - its seek, and play when paused" - and the "where they are reached" check (`:415-435`) gains the same entry.
  `player/Lyrics.tsx` is the one place both frames' taps go through; App, the panel and Now Playing pass nothing of the
  player's to it but `player`. The header's list (`:234-246`) gains a bullet.
- Plain lines aren't buttons: there is nowhere to seek.

### 3.4 The desktop: the player bar and the side panel

- **The bar's button**: in `app-playbar-tools` (`PlayerBar.tsx:141`), before Up Next (`:150-157`) - as Mac Music has
  Lyrics before Playing Next:
  `[AirPlay?] [Lyrics] [Up Next] [Add to a playlist] [Info] [visualizer]`. AirPlay comes and goes at the group's left,
  as now. `class="app-playbar-button{panel open ? ' is-on' : ''}" aria-label={lyricsLabel(state)} aria-expanded={open}`
  - Up Next's own pattern (`:150-157`); dimmed and `aria-disabled` for a song with none **while the panel is closed**
  (2.7). Its click: App's `toggleLyrics`, the event taken as the opener. Lit while open by the bar's existing
  `.app-desk .app-playbar-tools .app-playbar-button.is-on { color: var(--dw-accent) }` (`app-desktop.css:483`); the
  dimmed state is new there: `[aria-disabled='true'] { opacity: var(--app-pin-off) }` and no hover background.
- **The panel**: `app/LyricsPanel.tsx`, in **Up Next's panel shell** - the other panel the bar opens
  (`app/UpNext.tsx:444-459`: `app-layer app-info-layer app-lyrics-layer is-panel is-{panel}`, the box `app-info
  app-lyrics-panel` with `role="dialog"`, `aria-modal="false"`, `tabIndex={-1}`, `aria-labelledby` its title;
  `app-info-head` with the title **Lyrics** and **Done**), which is Info's shell too, so `app-desktop.css:896-931`'s
  `.app-layer.is-panel .app-info` rules place, slide and colour it with nothing new. `useSheet` with `modal: false`,
  `first: done`, `area: box` (`ui/src/app/useSheet.ts:24-29`, its desktop side panel paragraph) - focus in to Done as it
  opens, back to the bar's Lyrics as it closes, Escape from inside it. Its body is `player/Lyrics.tsx`.
- **The song changing with the panel open**: the next song's lyrics, at their top - or **No lyrics for this song.**
  **Nothing playing** (the queue ended or cleared - the bar shows the same words, `PlayerBar.tsx:66-71`): the panel
  stays until closed, saying so. Its opener has gone from the bar by then - the case Up Next's panel already has
  (its button goes too): whatever `useSheet` does with an opener no longer in the page, it does here (not read for
  this spec; the build checks it, D1).
- **One panel at a time**: `lib/appFrame.ts` `Side` (`:75`) gains `'lyrics'`; `sideOf` (`:81-84`) takes `lyrics` after
  `upnext`; App's `toggleLyrics` puts Info, Sources, Edit, the artist's and Up Next away as `toggleUpNext` does
  (`App.tsx:732-747`), and each of theirs puts Lyrics away. `closesOnCrossing` (`:112-116`) gains `lyricsPanel` - true
  going to the phone, as Up Next's (the phone's lyrics are Now Playing's face, which isn't open). Going to the desktop,
  lyrics on in Now Playing don't become the panel (Now Playing closes, as now).
- On the desktop there is no Now Playing sheet (`appFrame.ts:105-111`), so the panel is the desktop's only lyrics.
- Not on the visualizer (Open question 7).

### 3.5 The look, in tokens

**`interface/styles/theme.css` section 10** gains (phone values; the desktop block, `:673-`, redefines the two sizes):

| token | phone | desktop | what |
| --- | --- | --- | --- |
| `--dw-text-lyric` | 26px | 22px | a line of lyrics - between `--dw-text-title` (22, the song in Now Playing, `:472`) and `--dw-text-title-2` (28, `:471`); the panel is narrower than a phone's face is tall |
| `--dw-leading-lyric` | `var(--leading-tight)` (1.25) | - | a lyric's own lines when it wraps |
| `--dw-lyric-space` | 12px | 10px | between two lines - drawn as the line buttons' own padding, half each side (3.2), so the targets abut |
| `--dw-lyric-press-reach` | 8px | - | how far a line's press box reaches past its words, either side (3.2) |
| `--dw-lyric-break` | 0.5em | - | a break's height (2.4) |
| `--dw-lyric-dim` | `var(--dw-text-3)` | - | every line but the lit one: #8e8ea3, 5.7:1 on `--dw-bg-now-playing` #121016 (`:485`, `:506`), about the same on the desktop panel's `--dw-side-panel` #131219 (`:623`) - readable when scrolled to, plainly not the lit one |
| `--dw-lyric-lit` | `var(--dw-text)` | - | the lit line, and every plain line: #fff (`:501`) |
| `--dw-lyrics-fade` | 28px | 20px | the soft edge at the scroller's top and bottom, and the list's top padding (2.5) |

**A phone on its side** (`@media (max-height: 500px)`, the app's own query for it, `app.css:408`): the body takes
most of a 390px-tall screen, and the room left between the top row and the title is a few lines. There
`--dw-text-lyric` is `var(--dw-text-title)` (22px) and `--dw-lyrics-fade` 8px, so the lit line - at 0.3 of the room -
is clear of both fades and the next line shows under it. (The phone app is upright only, `ios/Config/Info.plist`
`UISupportedInterfaceOrientations`: no such case there.)

**At 320 wide**: player.css's `--pl-*` layer gains `--pl-footer-gap-narrow` (4px) under `(max-width: 359px)` (3.1).

- **Face**: `--dw-font-title` (Noto Sans SemiCondensed, "the large titles", `:457`), `--dw-weight-bold`. Lines left
  aligned, as Apple Music's and as the title is.
- **Gutter**: the body's 28px side padding (`player.css:688`, the grip's too, `:641`) - player.css's `--pl-*` layer
  gains `--pl-lyrics-side` for it, mechanics being player.css's (`notes/app.md:171-180`); the box's 520px is the body's.
- **A line under a finger**: `--dw-pressed` as the app's bare buttons; **focus**: the app's focus ring
  (`outline: var(--app-ring) solid var(--dw-accent)`), drawn on the press box.
- **The dots**: three `•` at the lyric's size, `--dw-lyric-dim` until lit, `--dw-lyric-lit` once.
- **The button**: `.app-np-lyrics.is-on { color: var(--dw-accent) }` as `.app-np-mode.is-on` (`app.css:5641`); dimmed
  `.app-np-lyrics[aria-disabled='true'] { opacity: var(--app-pin-off) }` and `:active { background: none }`.
- `interface/player/app.css`: a new section **"===== Lyrics (2.1.N+1) ====="** inserted above the phone frame's
  ("looking after deadwax from a phone (2.0.0-player.47)", `:5646`, which `tests/test_app_css.py` holds to be the last),
  insertions only, as 2.0.14's was. `app-desktop.css`: the panel's body, a line's hover, and the bar button's dimmed
  state, inside its desktop queries only (CLAUDE.md). No raw value anywhere; `test_app_css.py` fails on a token
  nothing reads.

### 3.6 VoiceOver and the keyboard

- **The button**: its name per 2.7; `aria-pressed` (phone) / `aria-expanded` (desktop); dimmed is `aria-disabled` -
  still focusable, its tap nothing, as Shuffle during a library's shuffle (`NowPlaying.tsx:399-406`).
- **The lyrics**: `<section aria-label="Lyrics">` holding an `<ol>` - VoiceOver says "list, 64 items". Each synced line
  is a button whose name is its words then its time ("The first line sung, 0:25" - the time in `app-visually-hidden`,
  `app.css:1809`); the lit one is `aria-current="true"` ("current"). A double-tap plays from it (3.3). Breaks and dots
  are hidden. Plain lyrics: the note, then each line as text.
- **Nothing is announced as lines change**: no live region - VoiceOver talking over the song every few seconds is the
  opposite of reading along. (Apple Music doesn't either, as remembered.)
- **Keyboard: one tab stop.** A roving `tabIndex`: the lit line (else the first) is 0, the rest -1; **Up/Down** move to
  the previous/next line with words, **Home/End** to the first/last, **Enter/Space** play from it (a button's own), and
  Tab leaves the list. Focus inside holds following (2.5). On the desktop Escape closes the panel (useSheet's `area`); on
  a phone it closes Now Playing, as now.
- **Opening lyrics doesn't move focus** on a phone: the button is a toggle in place, not a dialog. On the desktop focus
  goes to the panel's Done, as Info's.

### 3.7 Files, sims and tests (the web)

| file | what |
| --- | --- |
| `ui/src/lib/lyricsView.ts` (new) | the words of 2.1, `lyricsClock`, `litRange`, `withIntro`, `gapDots`, `followTop`, `follows`, `lyricsLabel`, `lineValue`, the constants (`LYRICS_ANCHOR` 0.3, `FOLLOW_AGAIN_MS` 4000, `GAP_DOTS_S` 4, `NEXT_LYRICS_S` 20, `LYRICS_KEPT` 50) - pure; `lyricTime` imported from `lib/lyrics.ts`, which is otherwise untouched |
| `ui/src/player/api.ts` | `songLyrics(id, signal)`: `get<SongLyrics>(`/navidrome/lyrics/${encodeURIComponent(id)}`, signal)`, beside `songDetails` (`:215-217`) |
| `ui/src/api/types.ts` | `SongLyrics { synced: boolean; lines: LyricLine[] }` beside `TrackLyrics` |
| `ui/src/app/useLyrics.ts` | the song's answer state, the 50 kept, the next song's ask (2.6) |
| `ui/src/player/Lyrics.tsx` | the view (3.2), its taps (3.3) |
| `ui/src/app/LyricsPanel.tsx` | the desktop panel (3.4) |
| `ui/src/player/NowPlaying.tsx` | the button, the face, the grip, the look's give-way (3.1); its header comment's "The board's Lyrics icon isn't drawn until..." becomes what it now does |
| `ui/src/player/PlayerBar.tsx`, `ui/src/app/App.tsx`, `ui/src/lib/appFrame.ts` | the bar's button, the panel, the one-panel rule, the face's on-state |
| `ui/src/player/icons.tsx` | `LyricsIcon` |
| CSS | theme.css section 10, app.css's new section, app-desktop.css, player.css's one `--pl-` |

- **The engine files have no diff** (`usePlayer.ts`, `streamSource.ts`, `lib/{playQueue,gapless,scrub,streamWrap,
  streamPlan,fmp4}.ts`, `player.sim.cjs`): the view reads `position()`, `onPosition`, `seek`, `toggle`, `playing` and
  imports `LANDED_WITHIN_S` - all there.
- **`ui/test/lyrics.sim.cjs`** (new, picked up by CI's glob): `litRange` (before the first line, exactly on a stamp,
  between, after the last, a shared stamp, a break lit); `lyricsClock` (a pending seek, a landed one, 2x speed's 0.5 s
  of drift kept raw); `gapDots` (3.9 s gap none, 4 s three steps, an outro none, an intro added and not doubled);
  `follows` (held, 3,999 ms, 4,000 ms, focus held, paused held past 4 s, played again after it); `followTop` (the top,
  the anchor, the end); `lyricsLabel` for every row of 2.7; the words verbatim.
- **`ui/test/app-rules.sim.cjs`**: `ALLOWED` and "where they are reached" (3.3); the footer's order pinned (Up Next
  before •••, Lyrics before Up Next, AirPlay before Lyrics); Now Playing's body order still as pinned.
- **`ui/test/errors.sim.cjs`**: `LISTENER_FILES` (`:430-436`) gains `player/Lyrics.tsx`, `app/useLyrics.ts` and
  `app/LyricsPanel.tsx` - a listener's pages: no error in their own words.
- **`ui/test/vocabulary.sim.cjs`**: `player/Lyrics.tsx`, `app/LyricsPanel.tsx`, `app/useLyrics.ts` and
  `lib/lyricsView.ts` in **BATCH4** - Now Playing's batch (Info's About, Now Playing, the mini player, the turntable):
  no "Navidrome", "Up next" or engine words - and, a rule of this batch's own, no "LRCLIB", "offset", ".lrc" or
  "sidecar" in them (each checked on a sample that breaks it, as the sim's header requires).
- **A sim of the view** in the fake-Preact style of `info.sim.cjs` (`app/useSheet.ts:5-7`): lyrics on/off, a song with none
  shows the cover, a tap seeks and plays when paused, focus held, a stale answer for the previous song never drawn.
- `tests/test_app_css.py`: the new tokens read; app.css's last section still the phone frame's.

### 3.8 Docs (in the web app's commit)

- **README** "### Lyrics" (`README.md:271-283`): after "A track's page shows its lyrics, with the time beside each line
  when they're synced." add: "So does Now Playing, as the song plays: **Lyrics** beside Up Next shows them in the cover's
  place - the line being sung lit and kept in view, a tap on any line playing from there - and on a desktop the player
  bar's **Lyrics** opens them beside the page. The iPhone app has them too." And under "If lines land a beat late":
  "...in your player - deadwax's own Now Playing included".
- **`docs/player.md`**: a bullet after **Now playing**'s (`:279-293`) - **Lyrics**: the button, the face, following and
  the four-second return (held while paused), a tap on a line, plain lyrics' note, the dimmed button, lyrics staying
  on, the look button giving way; its footer sentence ("then an **AirPlay** button ... **Up Next** ... and **•••**") gains **Lyrics**; "On a
  desktop" (`:948-`) gains the bar's **Lyrics** and its panel beside Up Next's sentence (`:365`); "Known gaps" gains
  "plain lyrics' verses run together" (Open question 9).
- **`docs/troubleshooting.md`** "## Lyrics are missing, or land late" (`:553-560`) gains: "**Now Playing's Lyrics is
  dimmed** for a song: Navidrome has no lyrics for it - none on LRCLIB, or none fetched yet (**Get lyrics** in the album's
  Edit). If an album has `.lrc` files and still shows none, check Navidrome's `ND_LYRICSPRIORITY` includes `.lrc` (its
  default does). **Couldn't load the lyrics.**: Navidrome didn't answer - as for the music itself."
- **`docs/configuration.md`**: `LYRICS_LEAD_MS`'s row (`:222`) - "if lines light up a beat late in your player (Now
  Playing's lyrics included)".
- **`notes/app.md`**: "### Lyrics on Now Playing (2.1.N+1)" - James's words, the choices, what was built, what was
  verified and what wasn't; `notes/app.md:255`'s "no Lyrics" line marked *(Changed in 2.1.N+1)*.

---

## 4. The iPhone app

Built on ios after Phase 2 merges (James chose "right after Phase 2"), from the server's 2.1.N (merged from main).
Phase 1's look: SF, the dark blurred backdrop, `Palette`, SF Symbols (`screens.md` 7).

### 4.1 The button, in the footer

The footer (`NowPlayingView.swift:169-189`) is AirPlay, Up Next and ••• spread by Spacers. It becomes:

```
[Lyrics]   [AirPlay]   [Up Next]   [•••]
```

- Apple Music's own order (Lyrics, AirPlay, Up Next), ••• at the right end as Phase 1 has it. The phone's AirPlay is
  always there (`AVRoutePickerView`, `screens.md` 7), so nothing comes and goes, and Lyrics can take Apple's place.
- `Image(systemName: on ? "quote.bubble.fill" : "quote.bubble")` - both iOS 13.0 (this Mac's
  `name_availability.plist`: year 2019 -> iOS 13.0), Apple Music's own lyrics glyph. `.font(.title3)`, a 44 x 44 target
  as Up Next's (`:175-181`). `Palette.accent` while on, `.primary` otherwise; dimmed: `.disabled(true)` and
  `.opacity(Palette.off)` (0.45, p2's `DeadwaxApp.swift`), which VoiceOver says as "dimmed".
- `.accessibilityLabel(LyricsWords.label(state))` (2.1, 2.7), `.accessibilityAddTraits(on ? .isSelected : [])` - as
  `ModeButton` (`:210-231`).
- The ••• name (`NowPlayingWords.more`, `Info.swift:422-424`) is unchanged.

### 4.2 The face

- **In the cover's place**: the top `VStack` (`:42-76`) is the chevron row, a Spacer, the cover (`:66-72`) and a Spacer,
  all of it the grip (`:75-76`, `.gesture(grip)`). With lyrics on: the chevron row keeps `.gesture(grip)` **alone**, and
  `LyricsView` takes the cover and both Spacers' room, outside the gesture - a scroll never drags the sheet, a drag down
  the top row still closes it. The cover's paused scale (`:70-71`) doesn't apply.
- **The title, the byline, the scrubber, the transport and the footer stay** (`:78-98`), as on the web (3.1).
- **`LyricsView`** (`ios/App/Player/LyricsView.swift`):
  - `ScrollViewReader` around a `ScrollView(.vertical, showsIndicators: false)` of a plain **`VStack(alignment:
    .leading, spacing: 0)`**: 24 pt of top room (the fade's, 2.5), the note (plain), the lines, a trailing clear `Color`
    of 70% of the view's height (2.5's room; from a `GeometryReader` on the scroll view). Not a `LazyVStack`: its rows
    not yet drawn have estimated heights, and `scrollTo` with an anchor lands off by the estimate's error on wrapped
    lines - lyrics run to a hundred lines or so (2,000 at most, 1.2), which a `VStack` draws without trouble.
  - Synced lines are `Button`s (`.buttonStyle(.plain)`), plain lines `Text`s; each `.multilineTextAlignment(.leading)`,
    `.frame(maxWidth: .infinity, alignment: .leading)`, `.padding(.vertical, 7)` (the 14 pt between lines, as the
    web's: targets that abut, a one-line lyric 34 + 14 = 48 pt tall), `.contentShape(Rectangle())`, `.id(index)`.
  - A soft top and bottom edge: `.mask(LinearGradient(...))`, 24 pt of fade each end.
  - **A new song starts at its top**: the scroll view is `.id(songID)`, so it is made afresh, unscrolled, unanimated.
  - The clock is stopped while Up Next or Info is over Now Playing (`showsUpNext || showsInfo`) as well as paused (2.2).
  - **The clock**: `TimelineView(.animation(minimumInterval: 0.1, paused: !player.isPlaying))` around the lines, reading
    `player.clock()` (2.2); the lit range and the dots worked out by Core's `Lyrics` (2.3, 2.4).
  - **Following**: `withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.9)) {
    proxy.scrollTo(lit, anchor: UnitPoint(x: 0, y: Lyrics.anchor)) }` on each change of the lit line while
    `Lyrics.follows(...)`. (`scrollTo`'s anchor puts the line's own 0.3 point at the view's 0.3, where the web puts the
    line's top there: the same place for a one-line lyric, a third of a line higher for a three-line one. Accepted.)
  - **The listener's scroll**: `onScrollPhaseChange` (iOS 18) - `.interacting` holds; back to `.idle` from an interaction
    starts `FOLLOW_AGAIN_MS`; under `if #available(iOS 18, *)`, with a `.simultaneousGesture(DragGesture(minimumDistance:
    10))` doing the same on iOS 17 (the app's target is 17.0, `ios/Config/Base.xcconfig:21`; James's phone runs 27).
  - **Loading**: `ProgressView()` centred, `.accessibilityLabel(LyricsWords.loading)`. **A failure**: `ErrorNote(error,
    gone: LyricsWords.songGone, failed: LyricsWords.failed, retry: true)` and a **Try again** button (`.bordered`, as the
    album page's) - none for a gone. **None**: the cover, in the face's place (2.7).
- **On while the app lives** (Open question 1): `LyricsModel.showing`, not `@State` in the view - a `fullScreenCover`'s
  state goes when it closes (`MainTabs.swift:22`).
- The notice capsule over the top row (p2: `:54-64`) is unchanged and covers no lyric.

### 4.3 The look

- **Lines**: `.font(.system(.title, weight: .bold))` - 28 pt at the default size, scaling with Dynamic Type (Apple Music
  draws its lyrics large and bold, section 5) - beside the title's `.title2.bold()` (22 pt, `:86`), as the web's 26px sits
  beside its 22px title. The lit line `.primary`; the rest `Color.primary.opacity(Lyrics.dim)`.
- **The backdrop darkens while lyrics show**, and that is what makes the dim lines readable. Now Playing's backdrop is
  the cover blurred under a 0.55 black overlay (`Backdrop`, `:235-249`); over a white cover that is #737373, where a
  white line at the draft's 0.4 is 2.1:1 - under the 3:1 floor for large text - and even at 0.6 only 2.8:1. So with
  lyrics on, the overlay is **0.7** (`Backdrop(dim:)`, animated with the swap, back to 0.55 with lyrics off): the
  backdrop at its brightest is then #4c4c4c, and `dim` **0.5** is 3.5:1 there (the lit line 8.5:1) - and far more over
  any real cover, whose blur averages it darker. **Increase Contrast**
  (`@Environment(\.colorSchemeContrast) == .increased`): overlay 0.75, `dim` 0.65. The title, byline and scrubber sit on
  the same backdrop and gain from it too. The web needs none of this: its sheet is the solid `--dw-bg-now-playing`
  (the blurred backdrop is off since the restyle, `player.css:622-633`). Check P8 looks at the brightest cover James has.
- `.animation(.easeOut(duration: 0.14), value: lit)` on the colour - `--duration-fast`'s 140 ms (`theme.css:402`).
- **Breaks**: a clear 14 pt; **the dots** three `Circle()`s of 8 pt, `.primary` at `dim` until lit, then full -
  `accessibilityHidden(true)`.
- **The plain note**: `.font(.footnote)`, `Palette.quiet`, above the first line.
- Side padding: the content's 24 pt (`:100`), so the lyrics line up with the title.

### 4.4 VoiceOver

- **A line is one element**: label its words, value its time (`LyricsWords.lineValue`: "0:25"; the lit line "0:25,
  now"), hint "Plays from here." (synced only), trait `.isButton`. Double-tap plays from it (seek, and play when paused:
  `player.seek(to:)` `PlayerModel.swift:358`, `player.toggle()` `:286`, straight from the tap).
- **The lyrics as a whole**: `.accessibilityElement(children: .contain)` and `.accessibilityLabel(LyricsWords.lyrics)`
  - a container VoiceOver names as it enters, never focuses itself.
- **"Go to the line being sung"** is a custom action **on every line** (`.accessibilityAction(named:
  LyricsWords.goToLit)`), not on the container: VoiceOver offers the actions of the element it is on, and a `.contain`
  container is never that element - an action there would never be offered. It moves VoiceOver's focus to the lit line
  (an `@AccessibilityFocusState` on the lines' indices); on the lit line itself it isn't added.
- **Focus holds following**: while that focus state is a line, following holds; `FOLLOW_AGAIN_MS` after it leaves, it
  comes back (2.5). A three-finger scroll is a scroll phase like a finger's.
- **Nothing announced as lines change** (3.6's reason).
- Breaks and dots hidden; the plain note read first.

### 4.5 Dynamic Type and the other settings

- Lines scale to the largest accessibility size and wrap - nothing truncates (`lineLimit(nil)`); the anchor stays a
  third of the way down. At the largest sizes the body under them (the title, byline, scrubber and footer, all Dynamic
  Type) grows too, so the lyrics become a window of a few lines - the lit line still clear of the fades (2.5). Check P7
  at AX5.
- The footer's four symbols scale with `.title3`; four 44 pt targets fit the narrowest phone at every size.
- **Bold Text**: the lines are bold already; the note follows the system.
- **Reduce Motion**: no spring, no smooth scroll - following jumps; the colour change stays (it moves nothing).
- **Increase Contrast**: the overlay 0.75 and `dim` 0.65 (4.3) - 5.5:1 over a white cover's backdrop.
- **Reduce Transparency**: the edge fade goes (a hard edge), as the system's own lists lose theirs.

### 4.6 The lock screen, untouched

- Nothing is added to `MPNowPlayingInfoCenter` or the remote commands: it has no place for lyrics, and Apple Music shows
  none there (section 5's table). The engine, the ticker (`PlayerModel.swift:868-881`) and the background audio are as
  they were.
- The view's clock runs only while Now Playing is on screen and the scene is active; a locked phone renders nothing and
  asks nothing (2.6's "app active").

### 4.7 Offline: kept with a download (Phase 2's store)

- **`DownloadDatabase` version 2** (`DownloadDatabase.swift:17-18`, `version = 1`; its migration `:104-114`). One table,
  added `if current < 2`:

  ```sql
  CREATE TABLE lyrics (            -- GET /navidrome/lyrics/{song_id}'s body, as answered - none included
    song_id    TEXT PRIMARY KEY,
    json       BLOB NOT NULL,
    etag       TEXT,               -- its ETag, so the next ask can be a 304 (2.6)
    fetched_at INTEGER NOT NULL);  -- ms since 1970
  CREATE TRIGGER song_lyrics_go AFTER DELETE ON song
    BEGIN DELETE FROM lyrics WHERE song_id = OLD.id; END;
  ```

  An answer of none is kept too: offline, "none" and "not kept" are different buttons (2.7).
- **Gone with the song, by every path**: a song's row leaves the `song` table three ways - `deleteSong` (`:147`),
  `removeOrigins` when a song's last origin goes (`:191-204`: an album's or a playlist's Remove Download taking a song
  nothing else asked for) and `removeAll` (`:325-328`). The draft named only the first and last; the trigger takes the
  song's lyrics with its row whichever way it goes, in the same transaction, and any way added later. Swift Testing
  holds all three to it. Other accounts' stores keep theirs (`phase2-downloads.md` 8.1).
- **Asked as each song's file arrives**: `DownloadModel.arrive` (`DownloadModel.swift:926-956`) queues
  `keepLyrics(songID)` as it queues the sound check (`queueCheck`, `:958`) - one ask at a time, never holding a download
  up, guarded as `keepAlbum` is (`:1024-1056`): a `lyricsAsked` set so a song is asked once at a time, and nothing kept
  if the store changed meanwhile (`self.store === store` - another person signed in) or the song is no longer
  downloaded.
- **Kept fresh by playing**: an answer the player gets online for a song that is downloaded replaces the kept one
  (`putLyrics`) when it differs (a 304 changes nothing), so a Get lyrics or a re-time reaches the phone the next time the
  song plays.
- **Filled in at every settle**, as album answers are (`settle`, `:551`, which calls `keepAlbum` for every album with
  none, `:583-585`): every `done` song with no `lyrics` row is queued, while deadwax can be reached. That covers the
  songs downloaded under 0.3, before lyrics existed, and any ask that failed - the next launch or return to the front
  tries again, with nothing kept of the failure.
- **Not counted** against the storage limit: a few KB a song, like the album answers the planner doesn't count
  (`phase2-downloads.md` 8.5).
- **What the player shows**: `LyricsModel` asks the route when `reachability.online` (p2 `Reachability.swift:31`);
  the kept answer is drawn at once if there is one, and drawn instead of a failure. Offline: the kept answer, else the
  dimmed **Lyrics - not on this phone**. Plays offline only from the phone (`phase2-downloads.md` 7.3), so a song
  playing offline is a downloaded one.

### 4.8 Core, the App, tests and the exporter

| DeadwaxCore (pure, tested on Linux) | the App |
| --- | --- |
| `Lyrics.swift`: `SongLyrics`, `LyricLine` (Codable, the route's keys), `litRange`, `withIntro`, `gapDots`, `followTop`, `follows`, `lyricsClock`, the constants; `LyricsWords` (2.1) | `ios/App/Models/LyricsModel.swift` (@MainActor @Observable): the 50 kept, the asks (2.6), `showing`, the kept answers through the download store |
| `Routes.lyrics = Endpoint(method: "GET", path: "/deadwax/navidrome/lyrics/{song_id}", query: [])`, in `Routes.all` (`Routes.swift:68`) | `ios/App/Player/LyricsView.swift` (4.2-4.4); NowPlayingView's footer and face; `PlayerModel.clock()` |
| `DownloadDatabase` v2: `putLyrics`, `lyrics(_:)`, the delete and Remove All (4.7) | DownloadModel's `keepLyrics`, the backfill |

- **The ports kept in step** (`notes/ios.md` "### How the ports are kept in step with the web", `:814-838`): a new
  exporter **`ios/scripts/export-lyrics-vectors.cjs`** runs `lib/lyricsView.ts` compiled (every function of 2.2-2.7
  over a grid of cases, the words) and writes `Tests/DeadwaxCoreTests/Fixtures/lyrics/`; **`ui/test/ioslyrics.sim.cjs`** runs it
  with `--check`. A web rule changing fails the sim; the exporter's run then fails ios.yml until the Swift agrees.
  `notes/ios.md`'s table gains the row.
- **Swift Testing**: the vectors replayed; `SongLyrics` decoded from the Python test's own answers (the fixture JSON
  committed beside them); the migration from a version-1 file (rows kept, the table added, `user_version` 2);
  `deleteSong`, `removeOrigins` (a song's last origin) and `removeAll` each taking its lyrics, and a song keeping its
  lyrics while another origin still holds it; `LyricsWords` verbatim.
- **`tests/test_ios_contract.py`**: `ROUTE_COUNT` 23 -> 24 (`:49`); its model check holds `SongLyrics`' keys
  (`synced`, `lines`, `time`, `text`) to the route's answer.
- No `.xcodeproj` change: new files go in the synchronized folders (`notes/ios.md` "### The project without Xcode");
  `check_project.py` must pass.
- **`docs/ios.md`** (p2: "## Playing", `:252`): a "### Lyrics" after "### Up Next" - the button, the face, a tap,
  following and its return, kept with a download and offline; "## The checks" gains section 6's phone checks.
  `notes/ios.md`: the build's section.
- **The app's version**: Open question 11.

---

## 5. Apple Music's lyrics, where deadwax has no precedent

As remembered from iOS 16-18 and macOS Music - **not seen here** (no Simulator; Apple Music on James's phone is the
check). How sure, and what this spec does:

| Apple Music | how sure | here |
| --- | --- | --- |
| A Lyrics button (`quote.bubble`, filled while on) at the left of Now Playing's bottom row, before AirPlay and Up Next | sure | the phone app exactly; the web left of Up Next, since its AirPlay comes and goes (3.1) |
| The button dimmed for a song with no lyrics | fairly sure | yes (2.7) |
| Lyrics replace the artwork in place; the artwork shrinks to a small one beside the title at the top | sure of the first, fairly sure of the second | in place; the title stays in the anchored body (Open question 4) |
| The line being sung bright, the rest dimmed; kept in the upper part of the screen; a smooth, springy scroll | sure; fairly sure of "upper third" | yes; anchor 0.3 |
| Lines not being sung slightly blurred | fairly sure (iOS 16+) | no - deadwax's "no blur" (theme.css:445); the phone could, Open question 5 |
| A tap on a line plays from it | sure | yes |
| ...from a pause too | not sure | seek and play (Open question 2, check W3/P3) |
| Scrolling by hand stops the following; it returns after a few seconds | sure it stops; fairly sure it returns; not sure of the delay | 4 s from the last input while playing; paused, held until play (check W2, W15; Open question 14) |
| While scrolling by hand, the other lines lose their blur, to be read | fairly sure (iOS 16+) | the dim lines are readable all along: 5.7:1 on the web; on the phone the backdrop darkens under lyrics so they are (4.3) |
| Three dots filling during an instrumental break or intro | fairly sure | yes, lit one by one by the clock (2.4) |
| The playback controls fade away after a few seconds while lyrics play; a tap brings them back | fairly sure (iOS 16+) | no (Open question 3) |
| Lyrics stay on after closing and reopening Now Playing, and from song to song | fairly sure | yes, for the app's life (Open question 1) |
| A song without lyrics while lyrics are on: the artwork | not sure | the cover, the button still on (2.7) |
| Static (unsynced) lyrics: scrollable, nothing lit | fairly sure; their type size not sure | same face, all lines bright, a note above (deadwax's own) |
| Word-by-word fill on Apple's own lyrics | sure it exists | no: LRCLIB is line-level (Open question 8) |
| Mac Music: lyrics in the right sidebar, its toolbar's Lyrics before Playing Next | sure | the desktop side panel, Lyrics before Up Next |
| No lyrics on the lock screen | fairly sure | none (4.6) |
| VoiceOver: lines readable one by one; nothing announced as they change | fairly sure | yes, with times and "now" (3.6, 4.4) |

---

## 6. The checks for James

Use songs whose albums deadwax filed (synced from LRCLIB - e.g. Dummy's "Roads"), one with plain lyrics, one with none
(an instrumental), and Five Finger Death Punch's "American Capitalist" (the song the lead was made for,
`notes/library.md:693-705`).

**The web app on the iPhone** (Safari, deadwax's plain `http://` address):

- **W1** Play "Roads", open Now Playing. **Lyrics** is between AirPlay's place and Up Next. Tap it: the lyrics take the
  cover's place, the title and the buttons don't move, the line being sung is white and about a third of the way down,
  and the lyrics move up smoothly as each line comes. Tap it again: the cover.
- **W2** Scroll up to read ahead: it stays where you put it, the lit line still changing. Let go; about four seconds
  later it scrolls back to the line being sung. Compare with Apple Music: sooner, later, or the same?
- **W3** Tap a line further on: the song jumps there and plays on. Pause, tap a line: it plays from there. Do the same in
  Apple Music while paused - does it start playing too?
- **W4** The lead: tap a line and listen - does its line light as the words start, a beat after, or before? On "American
  Capitalist", does the lit line ever show the line just sung? (This settles `LYRICS_LEAD_MS`, never verified -
  `notes/library.md:740-742`.)
- **W5** A song with a long intro or a guitar break: three dots, lighting one by one, then the next line.
- **W6** The plain-lyrics song: "These lyrics aren't synced to the song." above them, every line white, nothing moving
  on its own.
- **W7** The instrumental: **Lyrics** is dimmed and does nothing. With lyrics on, let a song with lyrics run into it:
  the cover shows and Lyrics stays lit; the next song with lyrics shows them again.
- **W8** Close Now Playing with lyrics on, open it again: still lyrics.
- **W9** With lyrics on, tap the record button: the turntable, lyrics off. Tap Lyrics: lyrics; tap it again: the
  turntable back, its sound working.
- **W10** Scroll the lyrics hard: the sheet never starts closing. Drag down from the arrow's row: it closes.
- **W11** Turn the phone on its side: the lyrics fit between the top row and the title, still scroll, nothing overlaps.
- **W12** Lock the phone mid-song; the music plays on as before. Unlock: the line being sung is lit.
- **W13** VoiceOver on: swipe through the lyrics - each line says its words and its time, the lit one "current";
  double-tap one: it plays from there; while you're on a line, the lyrics don't scroll away.
- **W14** Turn Wi-Fi and WireGuard off, open lyrics on a song not opened before: "Can't connect to deadwax." and **Try
  again**. On again, Try again: the lyrics.
- **W15** Pause, scroll the lyrics down to read ahead, wait ten seconds: they stay where you put them. Press Play: they
  go back to the line being sung.
- **W16** Open the app after a while away (the queue put back, paused) and open Now Playing: the lyrics are already
  there, or Lyrics is already dimmed for an instrumental - no flicker. Tap a line: it plays from there.
- **W17** Tap in the gap between two lines: one of them plays from its start - never nothing.

**On a desktop**:

- **D1** The player bar's **Lyrics** (left of Up Next) opens Lyrics beside the page; Up Next or Info put it away and
  it puts them away; **Done** and Escape close it, focus back on the button.
- **D2** Wheel up through the lyrics: they hold, and come back four seconds after. Tab into them: the focus lands on
  the line being sung; arrow keys move; Enter plays from there.
- **D3** The instrumental with the panel open: "No lyrics for this song."; closed, the bar's Lyrics dimmed.
- **D4** Narrow the window below 1024: the panel closes, the music plays on.
- **D5** Move the mouse over a line that isn't lit: it brightens a little and shows a hand; click it: it plays from
  there. Let the queue end with the panel open: it says "Nothing playing"; Done closes it.

**The iPhone app** (after the build):

- **P1** The footer: Lyrics, AirPlay, Up Next, ••• - the speech bubble filled and purple while on.
- **P2-P6** W1, W2, W3, W5, W6, W7 again, natively (P3 includes the paused tap; P4 is W4 on the app).
- **P7** Settings > Accessibility > Larger Text at the largest: lines wrap and stay readable, the footer fits.
- **P8** Increase Contrast, Reduce Motion (following jumps, no spring), Bold Text; and lyrics over the brightest cover
  you have (a white sleeve): the background goes darker as lyrics open, and the dim lines are still easy to read.
- **P9** VoiceOver: each line its words, its time, "now" on the lit one; "Plays from here."; the rotor's Actions has
  "Go to the line being sung".
- **P10** Download an album, Airplane Mode, play it: its lyrics show and follow. A song downloaded under 0.3 shows
  lyrics offline once the app has been opened online once since the update.
- **P11** AirPlay to a speaker: do the lines still land with the words (AirPlay delays the sound by a second or two)?
- **P12** The lock screen: as before - no change at all.

---

## 7. What only a device can tell

- Whether `touch-action: pan-y` on the lyrics scroller inside the sheet's `touch-action: none` scrolls in Safari on the
  phone (W10) - the spec's reading says yes.
- Safari's `currentTime` precision on the gapless stream's fMP4 (the clock, 2.2) - W4.
- How far AirPlay's delay is in the engine's "as heard" position on the phone app (`PlaybackEngine.swift:183-186`
  sets it from `outputLatency + ioBufferDuration`) - P11; on the web, the element's time.
- `onScrollPhaseChange` with VoiceOver's three-finger scroll (P9).
- The 4 s return against Apple Music's own (W2) and the paused tap (W3).

---

## Open questions (each with what the build does until James answers)

1. **Lyrics on across openings of Now Playing?** Apple Music keeps them on (fairly sure). **The build: on until the
   page reloads or the app quits** - in memory, not a setting. (A "Now Playing opens as: Lyrics" setting in You >
   Playback is the alternative; not built.)
2. **A tap on a line while paused** - play from there, or only move there? **The build: seek and play** (3.3, 4.4).
   W3 and P3 compare with Apple Music; changing it is one line each side.
3. **The controls fading away while lyrics play** (Apple Music's, fairly sure) - **not built**: the transport would be a
   tap away instead of under the thumb, deadwax's body is anchored so a finger knows where Play is, and a tap that
   brings controls back competes with a tap that plays a line. Asked again after W1.
4. **Apple Music's small cover and title at the top in lyrics** - **not built**: the title, byline and buttons stay
   where they are (the anchored body), and the lyrics get the room.
5. **Blur on the lines not being sung** - **not on the web** (the restyle allows no blur). The phone app's backdrop is
   already blurred and native; **the build: no blur there either**, so both apps look alike - one `.blur(radius: 1.5)`
   if James wants Apple's.
6. **"Get lyrics" from Now Playing** for someone with Edit albums, on a song with none - **not built**: it needs the
   song's folder (the id bridge, by release) and is a write from a listener's page; the album's Edit > Lyrics has it.
7. **Lyrics on the desktop's full-screen visualizer** - **not built**.
8. **Word-by-word lyrics** (Navidrome 0.64.2 answers word timings with `enhanced=true` for `.elrc` and `.ttml`) -
   **not asked**: deadwax writes line-level LRC from LRCLIB.
9. **Plain lyrics' verses run together** - Navidrome's parser drops their blank lines (0.2), so a plain `.lrc` reaches the
   apps (and Amperfy) as one block. **Accepted**, and said in `docs/player.md`'s Known gaps. A fix would be deadwax
   reading its own `.lrc` - which needs the song's file (0.2) - or a change in Navidrome. The one way to the file that
   exists: for an album deadwax filed (tagged, so the id bridge finds it by its release, `store_album.py`), the song's
   disc and track numbers pick its file, and the route puts the `.lrc`'s blank lines back between Navidrome's lines - a
   read, no write; a song it can't pair stays as Navidrome answers. Not built: plain lyrics are LRCLIB's fallback, the
   rarer case; W6 says how often James meets them.
10. **`LYRICS_LEAD_MS` for lyrics deadwax didn't write** (embedded, hand-made) - **no**: it is in deadwax's own files'
    timestamps; applying it at read time would move those twice, and other sources' timings aren't LRCLIB's lateness.
11. **The iPhone app's version** - Phase 2 ships as 0.3. **The build: 0.4** (`MARKETING_VERSION`, `ios/Config/
    Base.xcconfig:11`, with check_project.py, ios.yml and `tests/test_ios_install.py` pinned with it, as 0.2 and 0.3 were),
    and the plan's Phase 3 ships as 0.5 - a version says what shipped, not which phase.
12. **The follow-again delay** - **4 s** from the last touch, wheel or key; changed after W2 if Apple Music's feels
    different.
13. **One commit or two on main** (1.9) - **two**: the route as 2.1.N (nothing visible), the web app as 2.1.N+1 with the
    docs - so the route is on `:experimental` for the phone's build even if the web's needs another pass.
14. **Reading ahead while paused** (added in review) - does following come back on its own while the song is paused?
    **The build: no** - it stays where the listener put it until the song plays again, then comes back at once (2.5).
    Nothing is moving to follow, and a paused listener scrolling the lyrics is reading them. W15 shows it; Apple Music's
    own (not remembered) is worth a look beside it.

---

## Design review (2026-11-12)

Read against main `985b5d6`, the p2 worktree `c650c19`, and Navidrome v0.64.2's `model/lyrics_lrc.go`,
`model/lyrics_parse.go`, `core/lyrics/sources.go`, `server/subsonic/lyrics.go` and `media_retrieval.go`, fetched
again. What changed in the spec, and what was looked at and kept.

**Changed**

1. **A 404 would have said "Navidrome" to a listener.** errorWords' not-found says a fit detail as sent unless the page
   passes `gone`, and code 70's detail is "Navidrome has nothing by that id". Both apps now pass `SONG_GONE`, in
   `ALBUM_GONE`'s words, and draw no Try again for it (1.6, 2.1).
2. **The spinner was the retired main page's.** `components/Loading.tsx` is styled only inside the desktop's Edit panel
   and Server settings; on Now Playing it would have been bare text. Now the app's own `pl-spinner`, as every listener
   page has it (3.2).
3. **The on-colour was the wrong token**: `--pl-accent` where the transport's Shuffle and Repeat use `--dw-accent`
   (`app.css:5641`). Fixed, with the dimmed button's press suppressed as theirs is (3.1, 3.5).
4. **Orphaned lyrics on the phone.** The draft deleted a song's lyrics in `deleteSong` and `removeAll` only;
   `removeOrigins` deletes song rows too (an album's or playlist's Remove Download). A trigger on `song` now takes them
   whichever way, tested for all three (4.7, 4.8).
5. **The phone's dim lines failed contrast over a bright cover**: 2.1:1 at 0.4 over the backdrop a white sleeve makes.
   The backdrop darkens to 0.7 while lyrics show and `dim` is 0.5 - 3.5:1 at worst, 5.5:1 with Increase Contrast (4.3).
   The web's solid sheet was already fine (5.7:1).
6. **"Go to the line being sung" was on the container**, where VoiceOver never offers it. Now on every line (4.4).
7. **The phone's clock could read the song before at a join**: `heardSeconds()` checks no key. `clock()` now uses the
   engine's position only when it is the entry heard's, as the tick does (2.2).
8. **The first line sat under the top fade** at the start of every song. The list now starts below the fade (2.5, 3.2,
   4.2).
9. **The footer overflowed at 320 wide** with the speed chip and AirPlay showing (279px in 264). The gaps give way,
   never a target (3.1, 3.5).
10. **The lyrics were as wide as the sheet** while the body is centred at 520px: on a wide phone frame they started
    left of the title. They now share the body's box (3.1).
11. **Lyrics over the turntable kept `app-is-turntable`**, which centres the titles and hides the speed chip for a
    record no longer there. Dropped while lyrics show (3.1).
12. **A phone on its side** was "lyrics fit" with nothing drawn: a few lines' room under 28px fades. It now has its own
    size and fade so the lit line is always clear (3.5); the phone app is upright only.
13. **Asking on opening made the button flicker** (enabled, then dimmed) and opened lyrics-on onto a spinner. Lyrics
    are now asked at every song change on both frames and in the phone app, while visible or active (2.6).
14. **The phone app asked with no ETag**: it has no URL cache, so "a 304 over WireGuard" held only for Safari. It now
    asks with `If-None-Match` through `DeadwaxClient.fetch`, and keeps the ETag with a downloaded song's lyrics (2.6, 4.7).
15. **The backfill ran "once"**; a failed ask would never be tried again. It now runs at every settle, as album answers
    do, with `keepAlbum`'s guards (4.7).
16. **A file whose every line is stamped 0:00** (LRCLIB has some) would light the first line for the whole song. Same
    stamp on every worded line now means plain (1.2, 1.7).
17. **Gaps between lines were dead to a tap**, and a one-line lyric wasn't a tap target. The space between lines is now
    the buttons' own padding: targets abut, 44px tall (3.2, 4.2).
18. **The desktop had no hover**, so nothing said a line could be clicked (3.2, D5).
19. **Following came back while paused** and would pull lyrics out from under someone reading them. Paused, it holds
    until play (2.5, Open question 14).
20. **The listener's words were going into the editor's module** (`lib/lyrics.ts`, which says "LRCLIB"). They now live
    in `lib/lyricsView.ts`, which `vocabulary.sim.cjs`'s BATCH4 holds and the exporter ports (2, 3.7, 4.8).
21. **The phone's `LazyVStack`** would land anchored scrolls off by its height estimates on wrapped lines. Now a
    `VStack`, with the new song's view made afresh so it starts at the top (4.2).
22. Smaller: the clock stops while anything covers Now Playing; a resize re-follows; the desktop panel uses Up Next's
    shell (the bar's other panel) and says **Nothing playing** when the queue ends; a 404 has no Try again; line
    numbers re-cited where 2.1.4 or the draft had them wrong.

**Looked at and kept**

- **The route through Navidrome, by song id** (0.2): confirmed in v0.64.2's source - a sidecar read on every ask,
  `LyricsPriority`'s default with `.lrc`, the library filter on `MediaFile.Get`. No id-to-file path in deadwax could do
  it for an untagged album.
- **"user", not a permission; not in `SHARED_ACCOUNT_USES`; no server cache; one Subsonic call with the id alone**
  (1.1-1.5): each as every player route has it, and the fixed list grows by one deliberate entry.
- **The web's Lyrics between AirPlay and Up Next**, not first as Apple's: the web's AirPlay comes and goes, and the
  footer's rule is that nothing moves when it does. The phone's AirPlay is always there, so it takes Apple's order. The
  two apps differ here on purpose.
- **"Lyrics - none for this song"**: the app's own pattern for a control named with its state ("Up Next - Shuffle on").
- **The anchored body** over Apple's small cover and title, and **no fading controls** (Open questions 3 and 4): the
  body is anchored so a thumb knows where Play is.
- **No blur** on either app (Open question 5): the restyle allows none on the web, and the phone matches it.
- **The cover, button still lit, for a song with none while lyrics are on** (2.7): a lit button over a cover says
  "lyrics are on, this song has none" without a sentence in the cover's place; the button's name says it to VoiceOver.
- **`touch-action: pan-y` inside the sheet's `none`**: the spec's reading is right - the allowed touch actions are
  worked out from the target up to the nearest scroll container, which is the lyrics, so the sheet's `none` is never
  reached. W10 confirms on the phone.
- **The gesture rule**: `seek` isn't watched and `toggle` is, so `player/Lyrics.tsx` joins the allowlist for `toggle`
  alone; `seek` on a queue put back moves its parked second and loads nothing (`usePlayer.ts:947-954`), so a tap on a
  line after the app reopens plays from there.
- **`LYRICS_LEAD_MS` never applied at read time** (Open question 10): it is in deadwax's files' timestamps already.
- **Rejected: deadwax pairing songs with its own files to restore plain lyrics' verse breaks** - possible for albums it
  filed (Open question 9), not worth it before W6 says how common plain lyrics are.
- **Rejected: a "Lyrics" row in Info, or lyrics on the mini player** - neither has a precedent in Apple Music, and the
  button on Now Playing is one tap from the mini player.

---

## Built (2.1.5)

The route, as section 1 has it: `GET /deadwax/navidrome/lyrics/{song_id}` in `src/routes/navidrome.py` after `/songs`,
one `getLyricsBySongId` as the asker with the id alone, `src/lyrics.py song_lyrics()` shaping the answer, sent with
`json_with_etag`; `"user"` in test_logins' ROUTES; the fixed list in `test_there_is_no_general_proxy` grown by this one
entry and its paragraph; test_player_as_you's WALK and fake (which now answers `getLyricsBySongId`), and the as-you
walk holding it to `[("ethan", "getLyricsBySongId")]`. `tests/test_navidrome_lyrics.py`: 54 tests. The write-up is
`notes/player.md` "Lyrics by song id (2.1.5)"; `notes/library.md` "Lyrics (v0.7.0)" points to it.

Where the spec was silent or read one way of two, and what was done:

- **"The first synced entry" is judged by rule 3, not by the entry's own `synced`.** An entry that says synced but
  can't be lit (all one stamp, a worded line untimed) is not "a synced entry", so a later entry that CAN be lit is
  chosen over it; with none that can, the first with words is answered plain. Rule 3 says synced-or-plain "is
  decided by the lines", and choosing by the same rule keeps one test of "synced" in the module. (Also, then, an
  entry flagged `synced: false` whose lines all carry distinct starts - which OpenSubsonic forbids and Navidrome
  never sends - would be answered synced: the lines decide.)
- **"Not all one time" is judged on the times as lit** - after the offset and the hold at 0 - not on Navidrome's
  raw `start`s: two stamps an offset's hold brings to 0 would light together, which is what the rule guards.
- **A line with no words is `""`** - whitespace, or only newlines, after the trailing spaces are off. "Nothing else
  changed" otherwise. The view tells a break by its empty text, and a value of "\n" would have been a break that
  wasn't empty.
- **What isn't Navidrome's shape is left out, never a failure**: a `start` that isn't a JSON number (a string, a
  bool) is no start; a `value` that isn't text is an empty line; an entry or a line that isn't an object is skipped;
  an `offset` that isn't a number is 0. Navidrome sends none of these; a 500 for one would be worse than a plain
  answer.
- **The bounds apply last**: synced lines are sorted and then cut to the earliest 2,000; plain lyrics lose their
  edge blank lines and then are cut; a line's text is cut at 1,000 characters after its trailing spaces are off.
- **The 401 that ends a session** is tested in test_navidrome_lyrics.py with test_player_as_you's `player`
  fixture (logins on, token auth checked), as test_play_queue.py reuses it - the spec's file, the existing fixture.

Verified: the whole suite, 3971 passed, and each of the route's decisions mutated once and caught (17) - `enhanced`
sent, no ETag, asked as the shared account, the offset added, no hold at 0, all-one-time allowed, unsorted, an
untimed worded line ignored, plain edge blanks kept, the first entry taken synced or not, either bound removed,
text over-trimmed, an empty entry chosen, a bool taken as a number, the id's length unbounded, a failure not through
`_fail`. Not verified: a real Navidrome.

## Built (2.1.6)

The web app, sections 2 and 3: `lib/lyricsView.ts` (2's words and rules), `player/Lyrics.tsx` (the view, both frames),
`app/useLyrics.ts` (2.6's answers, called once in App), `app/LyricsPanel.tsx` (3.4's panel), the Lyrics button on
Now Playing's footer (3.1) and the player bar (3.4), `LyricsIcon`, `SongLyrics` and `songLyrics()`; the `lyrics`
side in lib/appFrame.ts; theme.css section 10's lyric tokens and the side's and desktop's blocks, player.css's
`--pl-footer-gap-narrow`, `--pl-lyrics-side` and `--pl-lyrics-max`, app.css's "Lyrics on Now Playing (2.1.6)"
section and app-desktop.css's "Lyrics on a desktop (2.1.6)". Tests (3.7): `ui/test/lyrics.sim.cjs` (new, 105
checks), app-rules (the allowlist, the footer's order, one panel at a time with Lyrics, the frame loops, the deck's
wakes), routes (the side and the crossing), info (the icon row), errors and vocabulary (the four files, and the
batch's own rule), and six rules in tests/test_app_css.py. Docs (3.8): README, docs/player.md, docs/troubleshooting.md,
docs/configuration.md; the write-up is `notes/app.md` "Lyrics on Now Playing (2.1.6)".

Where the spec was silent, or read one way of two, and what was done:

- **"The iPhone app has them too" is left out of the README** (3.8): it isn't true until section 4 lands; that commit
  adds it.
- **On its side, the space between lines grows to 17px** (`--dw-lyric-space` in theme.css's side block): 3.5 gives the
  side the title's 22px and an 8px fade but keeps the 12px space, and a one-line lyric would be 39.5px - not the tap
  target 3.2 makes it upright. 22 x 1.25 + 17 = 44.5, as upright's 26 x 1.25 + 12. test_app_css holds both frames to it.
- **The side's block is kept to the phone's frame** - `(max-height: 500px) and (max-width: 1023px)`, not app.css's bare
  `(max-height: 500px)` - so a short desktop window keeps the panel's 22px rather than taking the title's (larger on a
  desktop).
- **A break's dots are drawn inside its half line** (`--dw-lyric-break`, 0.5em), centred, so their coming and going
  moves nothing - 2.4 says where they light, not where they sit.
- **Following, three ways** (2.5 says "followed"): smoothly as the lit line changes or after a hold; at once, with no
  scroll, as the lyrics open, as the answer arrives and as the size changes (a phone turned, the column appearing); a
  new song starts at its top. A tap on a line follows it once - by the lit line's own effect when it lights a new line,
  directly when it was already lit - never two smooth scrolls at once.
- **Focus a tap or a click put on a line never holds following** (2.5 holds it for "keyboard and VoiceOver focus"):
  Chromium focuses a clicked button, and holding for that would stop following for good after one click. A pointer
  press marks the next focus as the pointer's; a key marks it as the keyboard's. VoiceOver's focus on the web doesn't
  always fire focusin - W13 is the check. `follows()` takes the held-by-focus as its fourth argument (`focused`).
- **A press on the scroller itself** (not a line) holds it as its scroll bar - the one pointer input that scrolls
  without a wheel or a touch.
- **The end room** (so the last lines can reach the anchor) is a block after the list, `--app-lyrics-room`, set from
  the view's height by a ResizeObserver - 0.7 of it.
- **Plain lyrics' section is a tab stop**, so a keyboard can scroll them (they have no buttons); while it has focus the
  ring is drawn whole and the soft edges are off, which would otherwise fade the ring away.
- **The none, note and failure looks follow precedent**: the note and "No lyrics for this song." / "Nothing playing"
  in the footnote size and the dim text colour (the album page's notes); a failure in the album page's `.pl-notice`
  words and size, Try again the app's `.app-button`; the spinner the player's own.
- **The panel is never modal and is drawn on a desktop alone**: `useSheet` with `modal: false` (focus to Done, back to
  the bar's button, Escape from inside), so its lock class `app-lyrics-open` is never put on - app-rules' sheet list
  names it so. A phone's lyrics are Now Playing's face; a panel left open crossing to the phone closes
  (`closesOnCrossing`), as Up Next's.
- **As a drawer, the panel closes going to an album or an artist from the player**, as Up Next's does (3.4 is silent;
  `leaveInfoDrawer`'s rule for every drawer).
- **The next song's ask listens to the position** (`player.onPosition`) rather than reading it as state, so nothing
  re-renders App as the song plays (2.6 says when, not how).
- **Lines are `text-align: left`**, not `start`: test_type holds every stylesheet to it - a line's own direction
  (`dir="auto"`, an Arabic line) never moves it to the other side.
- **The look button's icon follows the look**, not whether the record is drawn: with lyrics on over the turntable it
  still names the cover, the look it shows when tapped (lyrics off).
- **Tokens the spec didn't name**: `--pl-lyrics-max` (the body's 520px, beside 3.5's `--pl-lyrics-side`),
  `--app-lyric-dot-gap`, and `--app-lyrics-room` (the end room, set inline). `LYRICS_NOT_KEPT` is exported though the
  web never says it - 2.1's table is one table for both apps.
- **Pure helpers beyond 2's list**, each pinned by lyrics.sim: `withIntro`, `litAt`/`sameLit`, `clockRuns`, `endRoom`,
  `tabStop`, `lineAfterKey`, `SCROLL_KEYS`, `lineValue`, `asksAhead`, `keptLyrics`/`keepLyrics`.
- **vocabulary.sim's batch rule also holds "embedded"** - 2.1 names it beside the four 3.7 lists.

Verified: `npm run typecheck`; every sim on its own (69); lyrics.sim's 105 checks, and 13 mutations of the new code
each failing it (a paused tap not playing, a click's focus holding, any press holding, focus not holding, following
again while paused, a shared stamp lighting one line, the clock always the reported position, a stale answer drawn
over a newer one for the same song, asking while hidden, the next song asked twice, a song with none hiding its cover,
the record not woken, the bar's dimmed click); the whole pytest suite; the bundle built with the rolldown workaround.
Not verified: a real browser, the phone, a real Navidrome - section 6's W1-W17 and D1-D5.

### Review

The same day, read against the spec and both commits; no version bump (still 2.1.6). Five fixes, all in
`player/Lyrics.tsx`, each with a check in lyrics.sim that fails without it (a section of its own, "the view, after
review"):

1. **Plain lyrics were "followed" back to their top** - four seconds after the listener scrolled down to read them
   (while playing), at every play after a pause, at every change of size: `follow()` scrolls to the lit line or else
   the top, and plain lyrics have none. Following is synced lyrics' alone now, as 2.5 and docs/player.md ("don't move
   by themselves") already said.
2. **A press stayed "the pointer's" until a key was pressed in the lyrics**: in Safari, which focuses no button it
   clicks, the next keyboard focus after a tap on a line - a Tab in from outside - was taken for the press's and held
   nothing. A press is over at its click or its pointercancel, or once it has given its one focus.
3. **Keyboard focus kept its hold after a click** on another line: `focused` stayed on until focus left the lyrics.
   The press's focus lets go of it.
4. **Focus taken away held following for good**: a focused line removed with the last song's lines (the spinner
   while the next song's are asked) fires no focusout in Safari. Focus holds only while it is in the lyrics
   (`document.activeElement`), and the tab stop goes back to the lit line when the line it was on has gone.
5. **A finger resting on the scroller's own padding** (its 28px sides, the top fade) held following as its scroll bar
   does. Only a mouse's or a pen's press on the scroller holds now; a finger that scrolls holds by its touchmove.

Looked at and kept: the route as built (one getLyricsBySongId as the asker with the id alone, "user", `_fail`, the
ETag, all-one-stamp answered plain, LYRICS_LEAD_MS never applied at read time); useLyrics (latestOnly per ask, the
render-time guard against another song's answer, the retry, the next song's ask, the 50 kept); Now Playing (no record
mounted under lyrics, the transport the cover's while they show, the deck woken turning them off over the
turntable, the grip the top row); the panel and the one-panel rule; the tokens, errorWords, no secure-context API, the
engine files untouched; and every departure in "Built (2.1.6)". Not changed: in the gapless stream, a tap on a line
less than 1.5 s from where the song is can light the line before for the frames until its seek lands - 2.2's rule
(LANDED_WITHIN_S), which can't see the engine's pending seek without an engine change; the next song's ask and the
join's can both be on their way for one song (the second a 304). For James: a synced file with ONE line of words is
answered plain - rule 3's "all one time" holds trivially for it (a lone shout at 1:23); lighting it would need a rule
of its own.

Verified: the whole pytest suite; `npm run typecheck`; every sim on its own (69; lyrics.sim 111 checks); each fix
mutated back and caught; the bundle rebuilt. And deadwax run against a stand-in Navidrome (a small fake Subsonic
server outside the repo, shaped as the route's tests fake v0.64.2) - the page, the album, streaming, and the route
answering synced, plain, none, all-one-stamp and a duet's shared stamp, a 304 and a 404. Not verified: a real
browser, the phone, a real Navidrome - section 6's checks still stand.

## Built on the iPhone (app 0.4)

Section 4, on `ios`, from the server's 2.1.5 route and the web's 2.1.6 view as reviewed (merged into ios with main's
2.1.4-2.1.6), in four commits: Core, its fixtures and the exporter; the store; the App's view and button; the version,
0.4 (4) (Open question 11). Where the files are: notes/ios.md "Lyrics (app 0.4)".

As section 4 has it, by part:

- **4.1** The footer is `[Lyrics] [AirPlay] [Up Next] [•••]`, spread by Spacers: `quote.bubble` / `quote.bubble.fill`,
  `.title3`, a 44 x 44 target, `Palette.accent` on and `.primary` off; dimmed with `.disabled` and `Palette.off`
  (only off, for a song known to have none or, offline, none kept - `Lyrics.dimmed`); named `LyricsWords.label(have)`,
  `.isSelected` while on. Turning lyrics on or off is eased (0.25 s), the face's swap and the backdrop's darkening with it.
- **4.2** With lyrics showing (`Lyrics.shows`: on, and the song has some, or they're being asked, or the ask failed),
  the chevron's row alone is the grip and `LyricsView` takes the cover's and both Spacers' room; the notice, title,
  byline, scrubber, transport and footer are as they were. A plain `VStack`: 24 pt of top room (the fade's), the plain
  note, the lines (`.id(index)`), then `Lyrics.endRoom(height)` - 0.7 of the view's height, from `onGeometryChange`.
  The 24 pt fades are a `.mask`. The view is `.id(track.id)`. The clock is a `TimelineView(.animation(minimumInterval:
  0.1, paused:))`, paused unless `Lyrics.clockRuns` (synced, playing, Up Next and Info closed, the scene active), reading
  `PlayerModel.clock()` (2.2's, the key checked). Following is `scrollTo(lit, anchor: (0, 0.3))` in a
  `.spring(response: 0.5, dampingFraction: 0.9)`, or with animations disabled for Reduce Motion; before anything is lit,
  the top. Loading: a large `ProgressView` named **Loading lyrics**. A failure: `ErrorNote(gone: SONG_GONE, failed:
  LYRICS_FAILED, retry: true)` and a `.bordered` **Try again** - none for a gone. None: the cover.
- **4.3** Lines `.system(.title, weight: .bold)`, the lit one `.primary`, the rest `.primary` at `Lyrics.lineDim` (0.5;
  0.65 with Increase Contrast); the backdrop's black 0.55, 0.7 under lyrics, 0.75 with Increase Contrast
  (`Lyrics.backdropDim`), eased; the lit colour's change `.easeOut(duration: 0.14)`. A break is a clear 14 pt, its dots
  three 8 pt circles inside it; the plain note `.footnote` in `Palette.quiet`; the content's 24 pt sides.
- **4.4** A synced line is a `Button` (`.plain`): its words, `LyricsWords.lineValue` ("1:23", the lit one "1:23, now"),
  **Plays from here.**; a double tap seeks and, paused, plays - straight from the tap. **Go to the line being sung** on
  every line but the lit one (and on none while nothing is lit), moving an `@AccessibilityFocusState` there; that focus
  on a line holds following (`LyricsHold.focus`), the wait starting as it leaves. The lyrics are a `.contain` element
  named **Lyrics**; breaks, dots and the two rooms hidden; nothing announced.
- **4.5** The lines scale with Dynamic Type and wrap (`fixedSize(horizontal: false, vertical: true)`, no line limit);
  a size change re-follows at once. Reduce Motion: following jumps, the colour's ease stays. Reduce Transparency: no
  mask - a hard edge. Bold Text: the note follows the system.
- **4.6** Nothing added to `MPNowPlayingInfoCenter` or the remote commands; no diff under `DeadwaxAudio/`;
  `PlayerModel` gains only `clock()`, a read. `LyricsModel` asks only while the app is active (`UIApplication`'s
  state, kept by its didBecomeActive and didEnterBackground notifications), the clock runs only with the scene active.
- **4.7** As written: version 2, the table and the trigger, `putLyrics` / `lyrics(_:)` / `lyricsSongs()`; asked at
  each arrival and filled in at every settle while reachable, one ask at a time, `keepAlbum`'s guards; an answer got
  online replaces the kept one when it differs; a kept answer drawn at once, and drawn over a failure; offline with
  none kept, **Lyrics - not on this phone**. Not counted against storage.
- **4.8** As the table: Core (`Lyrics.swift`, `Routes.lyrics`), the App (`LyricsModel`, `LyricsView`, Now Playing,
  `PlayerModel.clock()`), the store, `export-lyrics-vectors.cjs` and `ioslyrics.sim.cjs`, `ROUTE_COUNT` 24 and the
  model check in test_ios_contract.py; no `.xcodeproj` change.
- **Open questions**, each the recommended answer: lyrics on for the app's life, in `LyricsModel` (1); a paused tap
  plays (2); no fading controls (3), no small cover (4), no blur (5), no Get lyrics (6); plain lyrics' verses as
  Navidrome sends them (9); the app 0.4 (4) (11); 4 s (12); paused, following waits for play (14).
- **The design review's changes** that reach the phone, each built: SONG_GONE with no Try again (1); the trigger (4);
  the darker backdrop and dim lines (5); the action on every line (6); the clock's key check (7); the list below the
  fade (8); asked at each song change while active (13); asked with the ETag (14); the backfill at every settle (15);
  abutting targets - each line's 14 pt split as 7 above and 7 below (17); paused, following holds (19); a `VStack`,
  made afresh per song (21); the clock stopped while covered and a size change re-following (22).

Where the spec was silent, read one way of two, or couldn't be built as written - each built as said here:

1. **The ask is `DeadwaxClient.lyrics(songID:ifNoneMatch:)`, not `fetch`** (2.6 and the review's 14 name `fetch`):
   `fetch` hands back the decoded value, and 4.7 keeps the route's body as it came. Same rule as `fetch`'s: a 304 is
   `.unchanged`, taken only when an `If-None-Match` went out.
2. **A deadwax older than 2.1.5** (silent): it has no lyrics route, and FastAPI's bare 404 ("Not Found") would be read
   as SONG_GONE - "This song isn't here any more" for every song that plays, and no Try again. `Lyrics.failure(_:)`
   makes a 404 with no words or FastAPI's "Not Found" a failure - "Couldn't load the lyrics.", Try again, and for whoever
   runs deadwax "lyrics need deadwax 2.1.5 or later" under it; the route's own 404 (Navidrome's code 70, its detail
   "Navidrome has nothing by that id", 1.6) is still the song gone. docs/ios.md says 2.1.5 is needed.
3. **The listener's scroll, iOS 18: the wait counts from the end of the fling** (4.2's "back to `.idle` from an
   interaction") where the web counts from the last input (2.5) - so it is 4 s plus a fling's second or so. Read one
   way of two in `LyricsHold.phase`: `.interacting` holds, `.decelerating` (or `.tracking`) after it still holds,
   `.idle` or `.animating` after it starts the wait; a touch that never scrolled (`.tracking` then `.idle` - a tap on
   a line) and following's own `scrollTo` (`.animating`) hold nothing. Tested.
4. **iOS 17's stand-in is a `@GestureState` drag** (4.2: a `.simultaneousGesture(DragGesture(minimumDistance: 10))`):
   `onEnded` doesn't run for a drag the scroll view takes over, which would hold following for good; a `GestureState`
   resets either way. The wait counts from the finger lifting (17 has no phases to see a fling end). Only on 17: on
   18 a simultaneous drag can keep the scroll view from scrolling.
5. **The `TimelineView` is behind the lines, not around them** (4.2), driving a `lit` state, so the lines are redrawn
   only when the lit line or a dot changes, not ten times a second. Its pause is 2.2's whole list (`clockRuns`), where
   4.2's snippet has `!player.isPlaying` alone.
6. **Stopped, a seek still lights its line** (2.2 has the view read `player.shownPosition`): `clock()` reads
   `position` and the pending seek, both observed, so the view is redrawn by either - a scrub or a tap while paused.
7. **Opening is placed, not scrolled** (2.5's "at once ... when the lyrics are opened again"): the lit line is set as
   the view appears and gone to without animation once it is laid out (the next turn of the main queue); following is
   smooth only after that.
8. **The next song's ask is made from the lyrics' view** (2.6 says when, not how): `onChange(of: player.position)` -
   the half-second tick - calls `LyricsModel.ahead()`, so only while they show; once a song, and not when memory or
   the store already has it.
9. **`Lyrics.clock(raw:reported:)` is ported though the phone doesn't use it** (2.2's phone rule is
   `PlayerModel.clock()`): one table of rules for both apps, held by the vectors, as the web exports
   `LYRICS_NOT_KEPT`. **The keyboard's rules aren't ported** (3.6's `tabStop`, `lineAfterKey`, `SCROLL_KEYS`): the
   phone has no tab stop.
10. **Lyrics on outlives a change of person** (silent): it is the phone's, not the person's. Their answers in memory
    go (`reset()`, with the other models'); the store is per person already.
11. **A tap on a line follows it once** - by the lit line's own change when it lights a new line, directly when it
    was already lit - the web's rule ("Built (2.1.6)").
12. **The view's id is the song's** (4.2's `songID`): a Repeat One replay is the same song, so its lyrics follow back
    up to the top rather than being made afresh.
13. **The failure's layout** (4.2 names its parts): the note and Try again stacked 12 pt apart, centred in the lyrics'
    room. Try again asks only while the app is active and deadwax can be reached.
14. **The store's asks send the kept ETag** (4.7 says the ETag is kept "so the next ask can be a 304"; the arrival and
    the backfill use it too). `putLyrics` keeps nothing for a song no longer in the table (removed while its ask was
    out), and `put`'s INSERT OR REPLACE of a song already there keeps its lyrics - no delete trigger fires with
    recursive_triggers off. Both tested.
15. **The turntable's parts of section 3 don't arise**: the phone app has none.

Verified on this Mac: `swift test`, 655 tests in 86 suites and the 93 audio ones (LyricsVectorTests replaying the
exporter's 385 lit-line times over 10 sets, 128 following cases and the rest; LyricsAnswerTests; LyricsPhoneTests;
the client's ETag test; three store tests); the app built for a device (Xcode's `generic/platform=iOS`, Debug, unsigned)
with no new warnings, the `.xcodeproj` unchanged and check_project.py passing; the ios sims, lyrics.sim and
vocabulary.sim; test_source_bytes and the four iOS pytest files (128). Mutations, each caught: the lit-line lookup's
`<=` made `<` (102 failed expectations), the dots' threshold moved (24), `follows`' `>=` made `>` (6, in 3 tests), a
touch that never scrolled holding (2), the trigger deleting nothing (7, in 2 tests). Not verified: any
of it on a phone, a real deadwax or a real Navidrome - section 6's P1-P12 and section 7 (`onScrollPhaseChange` with
VoiceOver's three-finger scroll, AirPlay's delay in the engine's position, the 4 s against Apple Music's); how the
spring and the first placement look; the iOS 17 drag stand-in, which this Mac's iOS 27 SDK compiles but nothing runs.
