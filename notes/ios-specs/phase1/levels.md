# Levels: Normalization on the iPhone, and the album loudness route

Phase 1 (app 0.2). Server side: deadwax **2.1.1 on main** (the first Phase 1 server addition; main and `ios` are
both 1199330 = 2.1.0 today), then main merged into `ios`. Read against the repo at 1199330.

**What changed in this area since 2.0.0** (`git log --oneline 85aa7be..HEAD -- <file>`):

- `ui/src/lib/loudness.ts`, `ui/src/player/levelling.ts`, `src/loudness.py`, `src/levels.py`, `ui/src/state/persisted.ts`,
  `ui/src/app/useInfoDetails.ts`, `tests/test_loudness.py`, `tests/test_normalization.py`, `ui/test/loudness.sim.cjs`: **no change**.
- `ui/src/app/NormalizationChoice.tsx`: 151f90a (2.0.1) rewrote By song's and Off's notes (quoted below as they are now).
- `src/routes/navidrome.py`: bec8e8c (2.0.4) only the playlist edit's errors (`auth.Explained`); the level routes untouched.
- **`ui/src/lib/aboutSound.ts` is new in 92a58dc (2.0.7)**: Info > About's group "Playing" became **"Sound"** (Format,
  Gapless, Normalization) in a listener's words; Debug keeps `describeLevel()`'s words. `debugRows.ts` (2.0.7, 2.0.9
  fonts only), `InfoSheet.tsx` (2.0.5/2.0.7/2.0.9), `info.sim.cjs` (2.0.7, 2.0.14).
- `player/api.ts` 2.0.4 (error words only); `AlbumPage.tsx` 2.0.4/2.0.5/2.0.9/2.0.13 (the warm effect unchanged).

---

## 1. The web's rule, as it is at 2.0.15

### 1.1 The setting (ui/src/app/NormalizationChoice.tsx, ui/src/state/persisted.ts)

- Type `Normalization = 'auto' | 'song' | 'album' | 'off'` (loudness.ts:25); `DEFAULT_NORMALIZATION = 'auto'` (:26).
- Kept **per device**: localStorage key `deadwax-player-normalization` (persisted.ts:45). `readPlayerNormalization()`
  (persisted.ts:232-235): `'song' | 'album' | 'off'` as stored, **anything else (nothing, junk, `'auto'`) -> 'auto'**;
  `writePlayerNormalization(v)` stores the value as is (:237-239). Pinned: settings.sim.cjs:479-505.
- You > Playback, a radio group headed **"Normalization"** (NormalizationChoice.tsx:70), after Maximum quality, the
  chosen one checked; a change applies from the next thing played (nothing already queued changes). Choices, in
  order, `NORMALIZATIONS` (:15-38) - label, then note, verbatim:
  1. `auto` **Automatic** - "An album you play keeps one level for the whole album, so its quiet songs stay quiet
     beside its loud ones. Anything else - a playlist, a shuffle, a song you add with Play Next - is levelled song by song."
  2. `song` **By song** - "Every song brought to the same loudness, even the quiet and loud songs of one album."
  3. `album` **By album** - "Every song at its album's level, even when it plays on its own or in a playlist."
  4. `off` **Off** - "No levelling: every song plays exactly as the file is, bit for bit, unless Maximum quality converts it."
- settings.sim.cjs:473-491 pins: these four word for word; no note reads as a test note (`TESTING` regex: experiment,
  trial, test, verified, a build number); Off's note contains "bit for bit" and not "before this setting"; no em
  dashes; "deadwax" never "Deadwax". The phone has no Maximum quality: see Open question 5 for Off's note.

### 1.2 The rule (ui/src/lib/loudness.ts) - pinned by ui/test/loudness.sim.cjs

- `QueuedAs = 'album' | 'songs'` (:29); `Level = 'album' | 'track'` (:32); `LevelledTrack = QueueTrack & { level?: Level }` (:39).
- **`levelFor(setting, as)`** (:42-47): off -> none; song -> track; album -> album; auto -> `as === 'album' ? 'album' : 'track'`.
  Table in section 5.3 (sim: "Automatic: an album by album, songs by song...", loudness.sim:100-103).
- `atLevel(tracks, level)` (:53-56): no level -> **the same array, the same objects**; else a copy of each with `level`.
  `levelled(tracks, setting, as)` (:59-61) = `atLevel(tracks, levelFor(setting, as))`. Under Off an entry has NO level
  field at all (sim :106-115). Swift: `level: Level?` nil under Off.
- **`levels(track, format)`** (:68-70): `!!track.level && format === 'raw' && isFlac(track)`. `isFlac` (streamWrap.ts:54-57):
  `suffix?.toLowerCase() === 'flac'` or contentType's part before `;`, trimmed, lowercased, is `audio/flac` or
  `audio/x-flac` (Python's twin: album_context.py:107-110 `_is_flac`). On the iPhone a FLAC is always fetched raw
  (DeadwaxCore `StreamFormat`: raw unless ogg/oga/opus/wma), so **levelled = level != nil && isFlac**.
- `unlevelled` (:78-82), `levelParam` (:86-88): web-only (address building); not ported.
- The level is decided **at the tap** and rides on the entry: Repeat's copies, a reshuffle, Up Next moves keep it; a
  change of setting applies from the next thing played (levelling.ts:18-20 `queued()`; app-rules.sim:2826-2870).

### 1.3 What is queued "as an album" (Phase 1's screens)

| where | as | source |
| --- | --- | --- |
| album page Play, Shuffle, a song row's tap | `'album'` | AlbumPage.tsx:332-336 `play()` -> `queued(tracks, 'album')` (Shuffle too) |
| album page's own ••• Play Next / Play Last | `'album'` | AlbumPage.tsx:368 `as: 'album'`; QueueMenu.tsx:54 |
| a song's ••• Play Next / Play Last | `'songs'` | QueueMenu.tsx:54 (`pick.as ?? 'songs'`) |
| later phases: Search song tap, Requests ▶, artist Play = album; artist Shuffle, playlist, Library Shuffle = songs | | Search.tsx:1691, Requests.tsx:312, ArtistPage.tsx:637, PlaylistPage.tsx:188, ShuffleSongs.tsx:88 |

Resume (lib/resume.ts, another spec's area) saves one char per entry (`'a'` album, `'t'` track, `'-'` none,
:124-125) and re-fits on reading with **`relevel(saved, setting)`** (:191-196): off -> none, song -> track,
album -> album, auto -> saved ?? track. Table in 5.3; pinned resume.sim.cjs:379-380.

### 1.4 Warming (player/levelling.ts:28-33, player/api.ts:603-611)

`warmAlbum(album)`: not under Off; only when some song `isFlac`; then `warmLevels(id)` = `POST
/deadwax/navidrome/level/album/{id}` fire-and-forget, **never twice at once per album** (a `warming` Set cleared on
settle). Called: album page as its songs arrive (AlbumPage.tsx:242-244, once per album id), and right after a play
from Search, Requests, an artist (never before the play). app-rules.sim:2869 pins its exact body.

### 1.5 Info's words (Debug: loudness.ts `describeLevel`; About: aboutSound.ts `aboutLevel`)

`LevelAnswer` (loudness.ts:91-102): `{level, state: 'measured'|'measuring'|'unmeasured'|'plain'|'not_levelled',
gain_db: number|null, wanted_db: number|null, loudness_lufs: number|null, peak_db: number|null, held: boolean,
songs: number, measured_songs: number, why: string|null}`. An answer whose `level` isn't the entry's is treated as
none (aboutSound.ts:122, debugRows.ts:575).

**Debug, `describeLevel(track, format, answer)`** (:130-155), in order (admins only - `infoTabs(admin)`):
1. no level -> `Off`
2. `!levels(track, format ?? 'raw')` -> `Not levelled - ${kindWords(track)}`; kindWords (:117-120):
   `${SUFFIX} songs play as they are` (suffix uppercased) or, with no suffix, `only FLAC songs are levelled`
3. no answer -> `LEVEL_NOT_KNOWN_YET` = `Asked for; deadwax hasn't said yet` (:123)
4. not_levelled -> `Not levelled - ${why ?? "deadwax won't level it"}`
5. measuring -> album: `Measuring its album… (${measured_songs} of ${songs} ${songs === 1 ? 'song' : 'songs'})`; track: `Measuring the song…`
6. plain -> `Played as it is this time - its ${album ? 'album was' : 'loudness was'} still being measured`
7. unmeasured, or gain_db null -> `Not measured yet - it played as it is this time`
8. head = `${album ? 'Album' : 'Song'}, ${signedDb(gain_db)}`; held and wanted_db not null ->
   `${head} · held there by its peak (it wanted ${signedDb(wanted_db) without ' dB'})`; loudness null ->
   `${head} · the ${album|song} is silent`; else `${head} · the ${album|song} at ${lufs(loudness_lufs)}`.
- `signedDb(v)` (:105-108): `fixed = |v|.toFixed(2)`; `(v < 0 && fixed !== '0.00' ? '-' : '+') + fixed + ' dB'`.
- `lufs(v)` (:111-114): `fixed = |v|.toFixed(1)`; `(v < 0 && fixed !== '0.0' ? '-' : '') + fixed + ' LUFS'`.
- `…` is U+2026, `·` is U+00B7 (sim uses `String.fromCharCode(0xb7)`).

**About, the "Sound" group** (`SOUND_TITLE = 'Sound'`, aboutSound.ts:28; rows Format, Gapless, Normalization -
`soundRows` :120-128). `aboutLevel(track, format, answer)` (:84-109), in order:
1. no level -> `Off`
2. `!levels(...)` -> isFlac ? `OFF_WORDS.transcoded` : `OFF_WORDS.kind`
3. no answer -> `LEVEL_CHECKING` = `Checking…` (:31)
4. not_levelled -> `offWords(why)`
5. measuring -> album: `Measuring the album… (${m} of ${n} ${n === 1 ? 'song' : 'songs'})`; track: `Measuring the song…`
6. plain -> `Not this time - the ${album|song} was still being measured`
7. unmeasured or gain_db null -> `Not this time - the ${album|song} hasn't been measured yet`
8. head = `${Album|Song} volume matching`; loudness null -> `${head} - nothing to adjust, the ${album|song} is silent`;
   held && (wanted_db ?? 0) > 0 && |gain_db|.toFixed(1) === '0.0' -> `${head} - kept as it is, it can't go louder
   without distorting`; else change = `${head}, ${volumeChange(gain_db)}`, plus ` - as loud as it can go without
   distorting` when held.
- `volumeChange(g)` (:72-76): `size = |g|.toFixed(1)`; `'0.0'` -> `no change needed`; else `${size} dB ${g < 0 ? 'quieter' : 'louder'}`.
- `OFF_WORDS` (:37-48): server `Off for this song - this server can't adjust volume`; kind `Off for this song - only
  FLAC songs are adjusted`; transcoded `Off for this song - this device can't play FLAC, so it's sent as MP3` (never
  on iOS); large `Off for this song - its file is too large` (never from the new route); file `Off for this song -
  its file can't be measured`.
- `offWords(why)` (:65-69) by `ABOUT_REASONS` (:58-62), first match: `/without numpy|player's cache can't be used/` ->
  server; `/^it isn't a FLAC file/` -> kind; `/MiB a song is held in memory/` -> large; anything else (null included) -> file.
- info.sim.cjs:292-357 pins all of it, reads levels.py's constants, and checks none of About's words matches
  `/\d\.\d\d|LUFS|levelled|numpy|soundfile|MiB|STREAMINFO|Navidrome|hasn't said/`.

**`toFixed` is NOT printf.** JS picks the larger n on an exact tie (it formats |x|, so: away from zero); C/Swift
`%.Nf` picks the even one. Gains are k/100, so exact ties are common: `volumeChange(-0.25)` is `0.3 dB quieter`
(printf: 0.2), `0.75` -> `0.8`, `2.25` -> `2.3`, `signedDb(0.125)` -> `+0.13 dB`, `lufs(-10.25)` -> `-10.3 LUFS`.
Swift must port `jsFixed(a, d)` for a >= 0: if a is an exact tie at d digits (`String(format: "%.{d+25}f", a)` shows
digit d+1 = `5` then only zeros), return `String(format: "%.{d}f", a.nextUp)`, else `String(format: "%.{d}f", a)`.
Vectors in 5.4.

---

## 2. The server's measurement and gain

### 2.1 Constants (src/loudness.py, src/levels.py, src/resample.py, src/album_context.py, src/player_cache.py)

- `REFERENCE_LUFS = -18.0` (loudness.py:59); `FULL_DB = 20*log10((2^23-1)/2^23)` = **-1.0354387945871882e-06**
  (:63, repr from Python here - hard-code this literal in Swift and test it against the formula).
- `ALGORITHM_VERSION = 1` (:56); histogram `BINS 1000`, `BIN_LU 0.1`, `FLOOR_LUFS -70`, `RELATIVE_GATE_LU -10`,
  `OFFSET -0.691` (:66-72); `MEASURED_CHANNELS {1,2}`, `MEASURED_DEPTHS {16,24}` (:76-77).
- `resample.HEADROOM_DB = 3.0` (resample.py:91); `RESAMPLED_TO` {88200,176400,352800 -> 44100; 96000,192000,384000 ->
  48000} (:95); `output_rate(src, cap, bits)` (:170-179): None if cap None, src <= cap, or bits not 16/24.
- levels.py: `LEVEL_WAIT_SECONDS 50` (:64), `LEVEL_WAIT_HIRES_SECONDS 20` (:67), `STALE_WAIT_SECONDS 5` (:70),
  `PLAIN_MARGIN_SECONDS 60` (:72), `MEASURES_AT_ONCE = max(1, min(4, cpu-1))` (:76), `LOOKS_AT_ONCE 8` (:79),
  `BRIEF_REFUSALS (429, 503)` (:82), `LEVELS_KEPT 8192`, `GAINS_KEPT 1024`, `UNMEASURABLE_KEPT 1024` (:86-89),
  `RESAMPLE_CAP 48000` (:104). Reasons: `NOT_FLAC = "it isn't a FLAC file"` (:107), `UNREADABLE = "its file can't be
  read as FLAC by deadwax (20- or 32-bit)"` (:108), `NO_CACHE = "the player's cache can't be used on this server"`
  (:109), `NO_LIBRARIES = "deadwax is running without numpy and soundfile"` (:110).
- `CONTEXT_SECONDS 10` (album_context.py:47); `VERSION_SECONDS 30` (player_cache.py:194) - how long a song's version,
  an album listing and a song's album are believed.

### 2.2 `gain_for(loudness, peak, reserve_db=0.0) -> Gain` (loudness.py:403-422) - the phone ports this exactly

```
wanted  = REFERENCE_LUFS - loudness  if isfinite(loudness) else 0.0        # silence (-inf) asks for nothing
peak_db = 20 * log10(peak)           if peak > 0           else -inf       # peak: largest |sample|, 1.0 = full scale
limit   = FULL_DB - peak_db - reserve_db                                   # +inf when peak is 0
gain    = min(wanted, limit)
rounded = floor(round(gain * 100, 6)) / 100                                # DOWN to 0.01, after snapping 1e-6
if rounded > limit: rounded = floor(gain * 100) / 100                      # the snap never passes the limit
Gain(gain_db=rounded, wanted_db=wanted, loudness=loudness, peak_db=peak_db, held=(limit < wanted))
```

- No cap on a positive gain but the peak. `held` compares the unrounded limit and wanted.
- Python's `round(x, 6)` rounds x's exact binary value to 6 decimals (correctly rounded), which is what C's
  `printf("%.6f")` does: in Swift `Double(String(format: "%.6f", gain * 100))!.rounded(.down) / 100`. **Not**
  `(h * 1e6).rounded() / 1e6`: over 2,000,000 random values near the boundary that shortcut differed 7 times; three
  real inputs where it does are in the vectors (`-25.999999995` must give 7.99, not 8.00).
- `log10` may differ by an ulp between glibc, Apple's libm and Python's; vectors keep >= 1e-10 from any boundary that
  depends on it. Compare `gain_db`, `wanted_db`, `held` exactly; `peak_db` within 1e-12; the Float32 multiplier within 1 ulp.
- Pinned in tests/test_loudness.py: `test_silence_has_no_loudness_and_asks_for_no_gain` (:235), `..._takes_a_song_to_the_reference`
  (:247: -10.6 / -1 dBFS -> -7.4), `..._is_held_under_the_peak` (:253), `test_the_resamples_room_is_reserved_inside_the_limit`
  (:261: 2.0 / 2.0 / 0.99), `test_the_gain_is_rounded_down_to_the_hundredth` (:269, wanted -7.42, -7.425, -7.4299999,
  1.2, 0.0, -0.001, 3.999), `test_no_input_can_take_a_sample_past_24_bits_after_the_rule` (:277). Mirror each in Swift.

### 2.3 What is measured and kept

- A song's `Measurement` (loudness.py:317-331): `peak` (largest |sample| of the song AS IT IS, native rate, 1.0 = full
  scale), `histogram` ((bin, count) ascending, non-empty bins), `blocks`, `seconds`; `.loudness = loudness_of([self])`.
- **An album's loudness is its songs' histograms POOLED** (`pooled` :334-340, `loudness_of` :343-365, libebur128's
  histogram mode, -inf for silence) - not an average of song loudnesses. The phone can't compute it from per-song
  numbers: that is why the route sends the album's.
- Album peak = `max(m.peak for m in pooled)` (levels.py:665, :731).
- Table `loudness` (store.py:424-436): `audio_key TEXT PK` (`s:` + sha256 of the FLAC's 34 STREAMINFO bytes, or `v:` +
  the player cache's Version.key when the MD5 is all zeros - loudness.py:110-123), `algorithm INT`, `peak REAL`,
  `histogram BLOB` (`<HI` pairs), `blocks INT`, `seconds REAL`, `measured_at TEXT`. `loudness_get(keys)` (store.py:3345)
  returns rows of any algorithm, `{}` on failure; `_measurement(row)` (levels.py:164-172) drops another algorithm's.
  Kept in memory too (`Levels._read`, LEVELS_KEPT). A retag/rename/re-file keeps the key. Rows never expire.
- To know a song's key deadwax must read its file's head from Navidrome as the shared account: `cache._version()`
  (4 bytes, `Range: bytes=0-3`, believed 30 s; player_cache.py:1561-1581, `_look` :1583) and `albums.stream_info()`
  (64 KiB windows, kept by version; album_context.py:352-366). This is what every level answer costs.
- Measured: on demand by a levelled stream (song, or its whole album), by `warm()` (POST /level/album), and at filing
  (`measure_filed`, levels.py:822-851, Part B). Nothing else measures; the phone's route never does.

### 2.4 levels.py as the existing routes use it

- `_reason(info)` (:147-155): bits not 16/24 -> UNREADABLE; channels not 1/2 -> `f"it has {n} channels - only mono and
  stereo are levelled"`; no total_samples -> `"its STREAMINFO doesn't say how long it is"`.
- `_song(id)` (:255-260): `cache._version(id)` None -> `cache._why_not[id] or NOT_FLAC` (player_cache's `_look` words:
  `"the file is empty"`, `"Navidrome didn't answer a range of the file"`, `"it isn't a FLAC file"`, `"Navidrome didn't say
  how big the file is"`, `"its first bytes aren't a FLAC file's"`); else `song_of(version)` (:239-253): STREAMINFO not read
  in CONTEXT_SECONDS -> raises CannotPlan; unreadable -> UNREADABLE; `_reason`; else `Song(song_id, version, info, key)`.
- `_album_songs(album_id)` (:262-291): the shared account's `getAlbum` listing (`albums._listing`, album_context.py:336-348,
  `_NoAlbum` when `album.song` isn't a list of dicts), FLAC entries (`_is_flac`) looked at 8 at once: Song kept; a
  NavidromeError `unreachable` re-raised; status in BRIEF_REFUSALS -> None; any other NavidromeError -> `str(e)`
  (left out, lasting); CannotPlan / httpx.TransportError -> None. Returns `(songs, whole)`, **`whole = no look was None`**.
- `_unmeasurable` (in memory, UNMEASURABLE_KEPT): key -> CannotMeasure's words (`"libsndfile can't read it: …"`,
  `"libsndfile reads it as X, not FLAC"`, `"it has N channels; only mono and stereo are measured"`, `"libsndfile couldn't
  decode all of it: …"`) - forgotten at restart, so tried once more after one.
- `warm(album_id)` (:488-504): `"measuring"` if this album's task is live; `"busy"` (dropped, NOT queued) if the one-album
  gate is held or ANY album task is live; else starts `_measure_album` in the background -> `"measuring"`.
- `_album_reserve(songs)` (:749-764): HEADROOM_DB if resample libraries are present and ANY song is hi-res under the
  48 kHz cap (`output_rate(rate, 48000, bits)` not None), else 0 - **the web's album gain keeps 3 dB of room for a hi-res
  album under either Maximum quality; the phone keeps none** (no resample in its path).
- `describe(song_id, level, max_rate)` (:671-737), Info's: default `{"level", "state": "unmeasured", "gain_db": None,
  "wanted_db": None, "loudness_lufs": None, "peak_db": None, "held": False, "songs": 1, "measured_songs": 0, "why":
  None}`; in order: NO_LIBRARIES; NO_CACHE (no cache folder); CannotPlan -> default; not a Song -> not_levelled(words);
  unmeasurable -> not_levelled(its words); copy too big -> not_levelled(player_cache.py:1505-1511 words); `_plain` ->
  `"plain"`; a kept gain -> measured; track: known -> measured (reserve 3 if resampled) else measuring/unmeasured;
  album: listing fails -> default; the song added if unlisted; `counted` = not unmeasurable; `whole and counted and all
  measured` -> pooled gain with `_album_reserve`; else measuring (album task live; measured_songs = max(counted measured,
  progress)) or unmeasured, songs = len(counted). `_measured()` (:771-775) rounds `wanted_db`, `loudness_lufs`,
  `peak_db` to 2 places (`_finite`, None for +-inf/NaN); `gain_db` as is; songs = measured_songs = pooled count.

### 2.5 The two existing routes (src/routes/navidrome.py) - unchanged

- **`GET /deadwax/navidrome/level/{song_id}?level=album|track[&max_rate=48000]`** (:640-662), user. `song_id` 1..256
  (`ID_MAX` :393). `_theirs()` first (one getSong as the asker, kept 300 s - :132-159; 404 if not theirs); cap dropped
  without the resample libraries; answer = `describe()`; NavidromeError -> `_fail(e)` (its status, detail, headers);
  httpx.TransportError -> 503 `"Navidrome broke off saying which file it has"`. Tests: test_normalization.py
  `test_infos_route_says_what_deadwax_would_level_a_song_at` (:655), `..._asks_whether_the_song_is_theirs` (:685),
  `..._says_an_album_is_being_measured` (:694), `test_infos_route_never_pools_part_of_an_album` (:1305).
  **The phone does not use it** (the plan's route table lists it for Info - superseded): its gain is the web copy's,
  reserve included, and Info's words on the phone come from the phone's own decision.
- **`POST /deadwax/navidrome/level/album/{album_id}`** (:665-681), user, **always 202**, body `{"state": s}`:
  `"not_levelled"` when numpy/soundfile are missing or there is no cache folder (checked BEFORE the asker check), else a
  getAlbum AS THE ASKER (NavidromeError -> `_fail`: 404 not theirs, 401...), then `warm()`: `"measuring"` | `"busy"`.
  No body is read (the walk sends none). Tests: `test_an_album_page_measures_its_album_once_and_none_while_another_is`
  (:716 - `measuring`, `measuring`, `busy`), `test_an_album_page_asks_navidrome_for_the_album_as_the_asker_first` (:749 - 404,
  nothing measured), `test_album_pages_opened_one_after_another_measure_only_the_first` (:1220). **The phone uses it.**

---

## 3. The new route: `GET /deadwax/navidrome/loudness/album/{album_id}` (2.1.1)

Permission **user**. Read only: never measures, never makes, never takes the one-album gate. One getAlbum AS THE
ASKER first, as POST /level/album does; then the levels' reads as the shared account. Raw, unrounded numbers: the
phone works the gain out itself (`gain_for`, reserve 0), because it plays the file as it is.

### 3.1 The answer (200, `application/json`)

```json
{
  "reference_lufs": -18.0,
  "state": "measured",
  "why": null,
  "whole": true,
  "album": {"loudness_lufs": -11.437218417201565, "peak": 0.98876953125, "songs": 3},
  "songs": [
    {"id": "a1", "state": "measured", "loudness_lufs": -12.80316, "peak": 0.98876953125, "why": null},
    {"id": "a2", "state": "measured", "loudness_lufs": -10.94121, "peak": 0.9710693359375, "why": null},
    {"id": "a3", "state": "measured", "loudness_lufs": null, "peak": 0.0, "why": null},
    {"id": "a4", "state": "not_levelled", "loudness_lufs": null, "peak": null, "why": "it isn't a FLAC file"}
  ]
}
```
(The phone's album gain here: `gain_for(-11.437218417201565, 0.98876953125, 0)` = **-6.57 dB**. Song a3 is digital
silence. For a hi-res album whose gain is peak-held, e.g. -23.81630525 LUFS / peak 0.50115966796875: phone +5.81 dB,
web +3.00 dB held - the 3 dB reserve the phone doesn't keep.)

**Field by field** (every key always present; `null` only where marked):
- `reference_lufs`: number, `loudness.REFERENCE_LUFS` (-18.0).
- (`algorithm`: int, `loudness.ALGORITHM_VERSION`, now 1 - only if Open question 7 is taken.)
- `state`: string, one of `measured | measuring | unmeasured | not_levelled` (no `plain`: that is about a copy).
- `why`: string or null - section 3.2.
- `whole`: bool - true when every FLAC song of Navidrome's album was looked at (its version and STREAMINFO read, or
  found to be one deadwax can't level for a lasting reason); false when one couldn't be looked at just now (STREAMINFO
  not read within 10 s, Navidrome broke off, or answered 429/503) or the album's listing couldn't be had (then `songs`
  is `[]`). The album is never pooled from part of it.
- `album.loudness_lufs`: number or null - only with `state == "measured"`: `loudness_of(pooled)` of every counted song,
  unrounded; **null there means the album is silent** (-inf). Null in every other state.
- `album.peak`: number or null - only with `measured`: max native sample peak of the counted songs (1.0 = full scale; 0.0 for digital silence).
- `album.songs`: int, always - the songs that count toward the album's level: FLAC, looked at, levellable (16/24-bit,
  1-2 channels, a length), not known unmeasurable. Same as describe()'s `songs` for level=album.
- `songs[]`: one entry per song of Navidrome's album listing **in its order** (disc, then track), every song (MP3s
  too), entries without an id skipped. `id` string (the song id, as the app has it from `/albums/{id}`); `state` one of
  `measured | measuring | unmeasured | not_levelled`; `loudness_lufs` number or null (measured: unrounded, **null =
  silent**; else null); `peak` number or null (measured only); `why` string or null.

### 3.2 States and `why`, decided in this order

Per song (FLAC entries looked at 8 at once, exactly as `_album_songs` looks):
1. not `_is_flac(entry)` -> `not_levelled`, why `NOT_FLAC` (no read from Navidrome).
2. look gave None (brief) -> `unmeasured`, why **`LOOK_LATER = "it couldn't be looked at just now"`** (new constant).
3. look gave words (a lasting NavidromeError's `str(e)`, `_why_not`, UNREADABLE, `_reason`) -> `not_levelled`, why those words.
4. key in `_unmeasurable` -> `not_levelled`, why its CannotMeasure words.
5. key known (memory or database, this algorithm) -> `measured`, loudness and peak.
6. this album's task live, or the song's own measure task live -> `measuring`; else `unmeasured`; why null.

The album (`counted` = the Songs of steps 4-6 not unmeasurable, i.e. steps 5-6):
1. listing failed (`_ASKING` or `_NoAlbum`, incl. an unreachable NavidromeError from a look) -> `unmeasured`, why
   LOOK_LATER, whole false, album `{null, null, 0}`, songs `[]`.
2. whole and counted non-empty and every counted song measured -> **`measured`**, why null.
3. whole and counted empty -> `not_levelled`, why **`NOTHING_TO_LEVEL = "none of its songs can be levelled"`** (new).
4. this album's task live, or any counted song's task live -> `measuring`, why null (or LOOK_LATER when not whole).
5. numpy/soundfile missing -> `not_levelled`, `NO_LIBRARIES`; no cache folder (`await cache._folder() is None`) ->
   `not_levelled`, `NO_CACHE` - nothing more can be measured here.
6. else `unmeasured`, why null when whole, LOOK_LATER when not.

Deliberately unlike describe(): (a) what IS measured is reported even without the libraries or a cache folder - the
phone needs no server processing; (b) no "too big" (no copy is made for the phone); (c) no `_plain`, no kept gains, no
reserve, no rounding.

### 3.3 The code to write

`src/levels.py`:
- Extract `_album_songs`' inner `look` (:278-288) **unchanged** into `async def _look_at(self, song_id) -> Song | str | None`
  and use it from `_album_songs` (a pure extraction - its tests below must stay green).
- New constants beside the reasons (:106-110): `LOOK_LATER`, `NOTHING_TO_LEVEL`.
- `def _number(value: float) -> float | None`: the value, or None when not finite (Starlette's JSONResponse uses
  `allow_nan=False`: an `-inf` would be a 500).
- `def _song_entry(song_id, state, loudness_lufs=None, peak=None, why=None) -> dict` - every entry built by it (the
  contract test reads its keys).
- `async def album_loudness(self, album_id: str) -> dict` - section 3.2; `try: listing = await
  self.cache.albums._listing(album_id); looked = gather(_look_at for FLAC ids under Semaphore(LOOKS_AT_ONCE))
  except (*_ASKING, _NoAlbum): return the LOOK_LATER answer`; then one `await self.known([keys])`; never raises.

`src/routes/navidrome.py`, after `level_album` (:681):
```python
@router.get("/loudness/album/{album_id}")
async def loudness_of_album(request: Request, album_id: str = PathParam(..., min_length=1, max_length=ID_MAX)):
    """(2.1.1) What deadwax has measured of an album, for the iPhone app's Normalization: each song's loudness and
    peak and the album's pooled, unrounded - never measuring or making anything (src/levels.py album_loudness()).
    The album is looked up AS THE ASKER first (Navidrome answers only for an album that user may see), then read as
    the shared account, as every other read the player cache makes. deadwax's own answer, not a relay."""
    try:
        await client_for(request).call("getAlbum", {"id": album_id})
    except NavidromeError as e:
        raise _fail(e)
    return await player_cache.cache.levels.album_loudness(album_id)
```
Update the module docstring's list (navidrome.py:1-13) with the route.

**Cost**: the first call on an N-song FLAC album = 1 getAlbum as the asker + 1 listing + N x (4-byte range + one or two 64
KiB ranges) as the shared account, 8 at a time; then the listing and versions are believed 30 s, STREAMINFO for good
(by version). A call every 5 s re-reads the N 4-byte ranges every 30 s. One SQLite query per call.

### 3.4 Tests that must list it or pin it

- **tests/test_logins.py** ROUTES (:176-178 block): `("GET", "/deadwax/navidrome/loudness/album/{album_id}"): "user",`
  (with a `#? (2.1.1)` comment) - `test_every_route_is_decided`, the 401 walk and `test_every_route_asks_for_exactly_its_permission` follow.
- **tests/test_navidrome.py** `test_there_is_no_general_proxy` (:229): add `"/loudness/album/{album_id}"` after
  `"/level/{song_id}"` in the sorted list, and a docstring paragraph ("joined it in 2.1.1, deliberately: the iPhone
  app's Normalization - deadwax's OWN answer, read only... one getAlbum AS THE ASKER for the id, bounded... see test_normalization.py").
- **tests/test_turntable_disc_art.py** :366-372: the same sorted list.
- **tests/test_navidrome_search.py** `test_every_navidrome_route_asks_through_client_for` (:177): add
  `"/deadwax/navidrome/loudness/album/al-1"` to `paths`; `len({route.path ...}) == 23` -> **24** (:244).
- **tests/test_player_as_you.py**: WALK (:404-429) `"/loudness/album/{album_id}": [("get", "/loudness/album/nd-dummy")]`;
  LEVEL_WAYS (:446) += `"/loudness/album/nd-dummy"`; in `test_every_player_route_asks_navidrome_as_the_signed_in_user`
  assert `made["/loudness/album/nd-dummy"][0] == ("ethan", "getAlbum")`. (The route answers 200 even when the shared
  listing fails, so the walk's status check holds.)
- **tests/test_ios_contract.py**: Routes.swift's `loudness`, `warmLevels` endpoints (the count in
  `test_the_app_names_its_routes_in_the_form_this_test_reads` changes with Phase 1's other routes); a test that the
  answer holds what `AlbumLoudness`, `AlbumLevel`, `SongLoudness` decode - top level and `album` from a real call with
  `client_for` stubbed (its `call` returns `{}`) and `player_cache.cache.albums._listing` raising `_NoAlbum` (the
  LOOK_LATER answer), entries from `levels._song_entry("x", "unmeasured")`. Swift names are camelCase over snake_case
  JSON: give these structs explicit `CodingKeys` and teach `required_fields` to read `case x = "json_name"` (Song's
  JSON is camelCase already, so no global conversion). And `test_the_levels_vectors_are_the_servers`: recompute
  `gain_for` over the committed vectors file (5.1).
- **tests/test_normalization.py**, new (audio libs; skip without them like their neighbours):
  1. `test_the_apps_loudness_route_says_what_is_measured_and_never_measures` - cd_album + an MP3 + a 20-bit FLAC: before
     any play `unmeasured`, whole true, album `{None, None, 3}`, the three FLACs `unmeasured`, the MP3 `not_levelled`
     NOT_FLAC, the 20-bit `not_levelled` UNREADABLE, `measured(monkeypatch) == []`; after `client.get(url("song-2"))`:
     `measured`, each FLAC `measured`, `album.loudness_lufs == loudness_of(pooled)` exactly, `album.peak == max`,
     and **`gain_for(album.loudness_lufs, album.peak, 0.0).gain_db == gain_of(played)`** (a CD album: the web's reserve
     is 0, so phone and web agree).
  2. `..._asks_navidrome_for_the_album_as_the_asker_first` - `al-9`: 404, getAlbum asked once with `al-9`, nothing listed or measured.
  3. `..._says_an_album_is_being_measured` - `run()`: POST warm, then GET -> `measuring` (songs measuring/measured), after -> `measured`.
  4. `..._never_pools_part_of_an_album` - `flaky_looks(monkeypatch, "song-3", 100)` after measuring: whole false, state
     not `measured`, album nulls, song-3 `unmeasured` with LOOK_LATER.
  5. `..._leaves_out_a_song_that_cant_be_measured` - a song in `_unmeasurable`: `not_levelled` with its words, album
     `measured` from the rest, `album.songs == 2`.
  6. `..._sends_silence_as_null_never_infinity` - a silent album: `measured`, `loudness_lufs` null, peak 0.0, body parses
     with `json.loads(..., parse_constant=raise)`.
  7. `..._carries_no_resample_room` - hi_album at a level that is peak-held: the route's numbers through `gain_for(...,
     0.0)` exceed the stream's X-Deadwax-Level (reserve 3) by up to 3 dB.
  8. `..._reports_what_is_measured_without_the_libraries_or_a_folder` - libs or folder missing: measured rows still
     `measured`; an unmeasured album `not_levelled` NO_LIBRARIES / NO_CACHE.
  9. `..._album_with_no_flac` - all MP3: `not_levelled` NOTHING_TO_LEVEL, every song NOT_FLAC, no stream read made.
  10. the exact key sets of the answer, `album` and an entry.
- Run the existing `test_normalization.py` whole (the `_look_at` extraction): especially
  `test_an_album_one_of_whose_songs_couldnt_be_looked_at_just_now_is_never_levelled_in_part` (:974),
  `test_a_song_navidrome_cant_serve_is_left_out_and_its_album_is_levelled` (:1185),
  `test_a_song_navidrome_says_is_busy_is_looked_at_again_not_left_out` (:1209).
- Mutation checks to run once each: `whole` ignored (test 4 fails); `-inf` passed through (6); a reserve applied (1/7);
  the asker's getAlbum dropped (2, the walk); the route left out of ROUTES (test_logins).

### 3.5 Docs, notes, version

- `src/__init__.py` 2.1.0 -> **2.1.1**; commit on **main** (author set explicitly), then `git merge main` into `ios`.
- **README: no change** (nothing a user can notice until the app's Phase 1 ships - say so in the commit message).
- notes/player-normalization.md: a section "The iPhone app's loudness route (2.1.1)" - 3.1-3.3 and the cost; notes/ios.md
  links it. docs/player.md "Normalization" (:1916): one paragraph, written when Phase 1 ships, that the iPhone app levels
  on the phone from the same measurements, without the 3 dB room, and plays a song as it is when its album isn't
  measured yet. docs/ios.md: Phase 1's Normalization (4.x below). CLAUDE.md's test count.

---

## 4. The phone's rule (app 0.2)

The phone plays the original file and applies the gain itself, one Float32 multiply per decoded sample. It uses
the web's setting and rule, and the server's measurements and gain rule with **reserve 0**. It never uses
`GET /level/{song_id}`, and nothing the server measures changes for it.

### 4.1 DeadwaxCore: pure, tested on Linux (new `Levels.swift`, `LevelWords.swift`)

```swift
public enum Normalization: String, CaseIterable, Sendable { case auto, song, album, off
    public static let `default`: Normalization = .auto
    public static let storageKey = "deadwax-player-normalization"           // UserDefaults, per device, like the web
    public static func read(_ stored: String?) -> Normalization            // "song"|"album"|"off" as is; else .auto
}
public enum QueuedAs: Sendable { case album, songs }
public enum Level: String, Codable, Sendable { case album, track }
public func levelFor(_ setting: Normalization, _ queuedAs: QueuedAs) -> Level?   // 1.2's table; .off -> nil
public func relevel(_ saved: Level?, _ setting: Normalization) -> Level?         // resume.ts:191-196
extension Song { public var isFlac: Bool }   // streamWrap.ts:54-57 exactly: suffix "flac" (any case) or contentType
                                             // before ";", trimmed, lowercased, "audio/flac" | "audio/x-flac"
public enum Loudness {
    public static let referenceLUFS = -18.0
    public static let fullDB = -1.0354387945871882e-06      // test: == 20*log10(Double((1<<23)-1)/Double(1<<23))
}
public struct Gain: Equatable, Sendable { public let gainDb, wantedDb, loudness, peakDb: Double; public let held: Bool }
public func gainFor(loudness: Double, peak: Double, reserveDb: Double = 0) -> Gain       // 2.2, line for line
public func gainMultiplier(_ gainDb: Double) -> Float     // Float(pow(10.0, gainDb / 20.0)): Double, rounded to Float once
```

`gainFor` takes `-Double.infinity` for silence; the route's `null` loudness maps to it, and a `null` peak to 0. The
Python rounding step is `Double(String(format: "%.6f", gain * 100))!.rounded(.down) / 100`. The guard is
`if rounded > limit { rounded = (gain * 100).rounded(.down) / 100 }`. `String(format:)` is Foundation, so it works on
Linux.

**Models** (`Models.swift`; snake_case JSON, so each struct gets explicit `CodingKeys`):

```swift
public enum LoudnessState: String, Codable, Sendable { case measured, measuring, unmeasured, notLevelled = "not_levelled" }
//   decode an unknown value as .unmeasured (custom init(from:)): a later server's new state plays as it is, never fails
public struct AlbumLoudness: Codable, Sendable, Equatable {    // GET /loudness/album/{album_id}
    public let referenceLufs: Double            // "reference_lufs"
    public let state: LoudnessState
    public let why: String?
    public let whole: Bool
    public let album: AlbumLevel
    public let songs: [SongLoudness]
}
public struct AlbumLevel: Codable, Sendable, Equatable { public let loudnessLufs: Double?; public let peak: Double?; public let songs: Int }
public struct SongLoudness: Codable, Sendable, Equatable {
    public let id: String; public let state: LoudnessState
    public let loudnessLufs: Double?; public let peak: Double?; public let why: String?
}
public struct WarmAnswer: Codable, Sendable, Equatable { public let state: String }   // "measuring"|"busy"|"not_levelled"
```

The client should **not** check `referenceLufs` against -18; it is there for Info and the downloads' stored copy.

**Routes** (`Routes.swift`, one line each in the contract test's form, both added to `all`):
```swift
public static let loudness = Endpoint(method: "GET", path: "/deadwax/navidrome/loudness/album/{album_id}", query: [])
public static let warmLevels = Endpoint(method: "POST", path: "/deadwax/navidrome/level/album/{album_id}", query: [])
```
The album id goes in as one percent-encoded path segment. `warmLevels` sends no body, and its answer is 202 with
`WarmAnswer`. Both use the client's normal errors: 404 means not theirs, and 401 is the session's.

**The decision** (pure), made once per queue entry:

```swift
public enum AppliedLevel: Equatable, Sendable {
    case off                                   // the entry has no level
    case notFlac                               // levelled entry, not FLAC: plays as it is
    case gain(Gain, Level, songs: Int)         // album: AlbumLevel.songs; track: 1
    case notLevelled(why: String?, Level)
    case plain(Level, songs: Int, measured: Int)    // its album/song was being measured
    case unmeasured(Level, songs: Int)
    case unanswered(Level)                     // no answer in hand when it had to start
    public var multiplier: Float? { if case .gain(let g, _, _) = self, g.gainDb != 0 { gainMultiplier(g.gainDb) } else { nil } }
}
public func decide(level: Level?, song: Song, answer: AlbumLoudness?) -> AppliedLevel
```

`decide` works in this order:
1. `level == nil` -> `.off`.
2. `!song.isFlac` -> `.notFlac`.
3. `answer == nil` -> `.unanswered(level)`.
4. `mine` = the entry of `answer.songs` with `id == song.id`. None (the album changed since) -> `.unmeasured(level,
   album: album.songs, track: 1)`. `mine.state == .notLevelled` -> `.notLevelled(mine.why, level)`: the song before
   its album, as `describe()` does (levels.py:691-695).
5. For `.track`:
   - `mine` measured: `.gain(gainFor(mine.loudnessLufs ?? -inf, mine.peak ?? 0), .track, 1)`.
   - `mine` measuring: `.plain(.track, 1, 0)`.
   - Otherwise: `.unmeasured(.track, 1)`.
6. For `.album`, by `answer.state`:
   - measured: `.gain(gainFor(album.loudnessLufs ?? -inf, album.peak ?? 0), .album, album.songs)`.
   - notLevelled: `.notLevelled(answer.why, .album)`.
   - measuring: `.plain(.album, album.songs, count of answer.songs measured)`.
   - unmeasured: `.unmeasured(.album, album.songs)`.

A `gainDb` of exactly 0 means no multiply. With Off, a non-FLAC song or any state other than `.gain`, the source is
not wrapped at all, so it plays **bit for bit** what the decoder gave.

**Info's answer.** `levelAnswer(_ applied: AppliedLevel) -> LevelAnswer?` builds the web's `LevelAnswer` (1.5),
so the words are the web's own functions, ported:
- `.gain`: `{level, "measured", gain_db: g.gainDb, wanted_db: r2(g.wantedDb), loudness_lufs: finite ? r2(L) : nil,
  peak_db: finite ? r2(peakDb) : nil, held, songs: n, measured_songs: n, why: nil}`. `r2(x)` is
  `Double(String(format: "%.2f", x))!`, which is Python's `round(x, 2)` as `_measured()` applies it (levels.py:767-775).
  **Rounding to 2 places and then `jsFixed(_, 1)` is what the web shows** (e.g. -10.249 -> -10.25 -> "-10.3 LUFS").
- `.plain` -> `"plain"` with songs and measured. `.unmeasured` -> `"unmeasured"`. `.notLevelled(why)` -> `"not_levelled"`, why.
- `.off`, `.notFlac` -> nil. Their words come before any answer is read.
- `.unanswered` -> nil, plus two new lines (Open question 4):
  - Debug: `Played as it is this time - deadwax didn't say in time`
  - About: `Not this time - the ${album|song}'s volume couldn't be checked`

**Words** (`LevelWords.swift`): port `describeLevel` (Debug) and `aboutLevel` / `offWords` / `volumeChange`
(About) verbatim from 1.5, with `format` always `"raw"` (`StreamFormat.format(for:)` never transcodes a FLAC).
Use `jsFixed` for every `toFixed`. Use `SOUND_TITLE` "Sound" and `LEVEL_CHECKING` "Checking…". Info's Sound rows on
the phone are Format, Gapless and Normalization, as soundRows (aboutSound.ts:120-128) has them.

### 4.2 When the app asks: warm and read (app layer, a `LoudnessBook` actor)

- **The book**: album id -> `(AlbumLoudness, fetchedAt)`. A `measured` or `not_levelled` answer is kept **10 minutes**;
  a `measuring` or `unmeasured` one only until the next read. A synchronous, lock-protected `answer(albumId)` serves
  the engine's queue. The book holds no decisions.
- **Nothing at all under Off** (as warmAlbum, levelling.ts:29), and nothing for an album with no `isFlac` song.
- **Wanted**: an album whose page is open, or that holds the entry playing or one of the next **3** entries with a level.
- **On becoming wanted** with no fresh answer: `GET loudness` first. `unmeasured` -> `POST warmLevels`: `measuring` ->
  read every **5 s** (the web's `LEVEL_ASK_AGAIN_MS`, useInfoDetails.ts:134) until it isn't `measuring`; `busy` -> post
  again after 5 s; `not_levelled` -> stop (the next GET says why). A GET answering `measuring` (another device's play,
  a filing) -> read every 5 s. All of it stops when the album stops being wanted.
- **At most one warm in flight per album** (api.ts:603-611 `warming`), none retried more often than every 5 s.
- **GET before warm**, because `warm()` answers `busy` while ANY other album measures, even for one already measured
  (levels.py:500): the phone must read whatever warm says. Reading first also spares the server a measuring task.
- **A failed GET** (network, 5xx) leaves the book as it was; tried again on the next 5 s tick while wanted.
- Resume puts a queue back paused; its albums are wanted like any other queue's.

### 4.3 When the decision is made, and how the gain is applied

- **Once per queue entry, at its first open**, synchronously from the book: `EngineTrack.open` calls
  `decide(level:, song:, answer: book.answer(albumId))`. Kept by the entry's identity (Up Next's entry id, another
  spec's), not its index: a seek, skip back, rebuild or route change reopens it with the **same** decision. A song
  never changes level while it plays, and Info always says what is heard.
- **One decision per album for album-level entries, for the life of the queue**: the first album-level entry decided
  for an album fixes the outcome for every later album-level entry of that album in the queue - the whole album at
  one level, or as it is, so a gapless join never steps (the web steps once the measurement lands: Open question 3).
  A new play (Play, Shuffle, a song row, a resume) is a new queue and new decisions. Track-level entries are each their own.
- **The first song of a play may wait; joins never do** (a join's decision is made from the book when the engine opens
  it, `aheadSeconds` = 2 s before the join). The app wraps the first entry's source in a gate returning
  `PCMRead.waiting` (the engine already retries it, `scheduleRetry`; Now Playing shows `.loading`) **only while the
  answer in hand is `measuring` or none has come yet**, polling the route every 1 s, for at most **20 s**
  (`LEVEL_WAIT_HIRES_SECONDS`, the web's shorter wait); then it decides from what it has. No wait under Off, for a
  non-FLAC song, or for a resume (it comes back paused, and decides when played).
- **The multiply is in the app's source wrapper, not the engine**: `GainedSource: PCMSource` passes `format`, `.waiting`
  and `.end` through and, on `.frames(buffer)`, multiplies each channel in place (`vDSP_vsmul(ch, 1, &m, ch, 1,
  frameLength)`) and returns the same buffer. **PlaybackEngine.swift needs no change**: the gain is applied at the
  file's own rate before the lanes' `conform` and rate converter. One Float32 rounding per sample, no clamp, no limiter
  (`gainFor` keeps `peak * m <= 1.0`; all 41 vectors hold in Float32 - the Swift test checks it). Album gain is one
  multiplier for every song of the album, so joins stay exact.
- **Not FLAC** (MP3, AAC, Opus) plays as it is, as on the web (`levels()`).
- **"Played as it is this time"**: a `.plain`, `.unmeasured` or `.unanswered` entry plays as it is, Info says so in
  the web's words (1.5 items 6-7), and the album's next play picks the gain up.
- **Changing the setting** applies from the next thing played; queued entries keep their level and decision.
- **Navidrome's `replayGain`: not used in Phase 1** (Open question 1). If ever wanted: a fallback for `.unmeasured` and
  `.notFlac` entries only, from OpenSubsonic `song.replayGain {trackGain, albumGain, trackPeak, albumPeak, baseGain}`,
  which `/albums/{id}` already relays (navidrome.py:331-339 returns getAlbum's album as is) - unverified on a real 0.64.

### 4.4 Settings screen (You > Playback)

A section headed `Normalization` holds four choices in order. They use the web's labels and notes verbatim (1.1),
except Off's note on the phone, which has no Maximum quality (Open question 5). The proposed wording is:
`No levelling: every song plays exactly as the file is, bit for bit, unless this iPhone has to change its rate.`
Selecting a choice writes UserDefaults at once.

### 4.5 Swift tests to write (mirroring the sims and pytest)

`DeadwaxCoreTests/LevelsTests.swift` (Linux and macOS):
- **gainFor**: every `python_gain_for` case in the vectors file - `gainDb`, `wantedDb`, `held` exact; `peakDb` within
  1e-12 (-inf where the JSON has null); `gainMultiplier` within 1 Float ulp of `multiplier_f32`; `Float(peak) * it <= 1`.
- **gainFor, ported from test_loudness.py:235-296**: silence, reference, held, reserve, the rounding list, and
  "no input can take a sample past 24 bits". Port the last with its peaks: 3,000 seeded integers in [1, 2^23), plus 1,
  2^23-1 and 2^23, plus 500 values k<<8. The seed is the Swift test's own. Each peak is divided by 2^23 and run at
  LUFS -60, -30, -18 and -5, with reserve 0 and 3. Assert `rint(±value * 2^23 * 10^(g/20))` lies in
  [-2^23, 2^23-1], and also that `abs(Float(value) * gainMultiplier(g)) <= 1`.
- `fullDB` against its formula. `Normalization.read` with nil, junk, "auto", "song", "album" and "off" (persisted.ts).
- `levelFor` (8 cases) and `relevel` (12 cases). `isFlac` (9 cases).
- `jsFixed`: the `signedDb` and `volumeChange` tables, and `lufs(-10.25)` giving "-10.3 LUFS".
- `describeLevel` and `aboutLevel`: all 29 `typescript.words` cases (each has a full `answer`).
- About's words never match `/\d\.\d\d|LUFS|levelled|numpy|soundfile|MiB|STREAMINFO|Navidrome|hasn't said/`
  (info.sim.cjs). The new `.unanswered` lines are checked too.
- `decide`, one test per branch of 4.1, among them: the song's `not_levelled` beating a measured album; silence (null
  loudness, peak 0) giving a 0 dB `.gain` and a nil `multiplier`; a song missing from the answer; `whole` never read.
- `levelAnswer` rounds before the words: an album at L -10.249 gives Debug `… the album at -10.3 LUFS` (unrounded: -10.2).
- Decoding `AlbumLoudness` from the 3.1 example JSON, and an unknown `state` decoding as `.unmeasured`.
- The four settings words, and that Off's note contains "bit for bit".

`DeadwaxAudioTests/EngineRenderTests.swift` (macOS, offline render):
- A `GainedSource` at -6.02 dB over the test songs renders samples equal to the original times `multiplier`
  (bit-exact against vDSP).
- `.off` renders bit for bit the original.
- An album of three songs at one gain keeps its joins sample-exact, as the existing gapless render test does.
- The gate returns `.waiting` until the book answers, then plays.

**The vectors file.** Commit it once as `ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/levels-vectors.json` (a
SwiftPM test resource), copied from this spec's `specs/levels-vectors.json`, with three readers: pytest
`test_ios_contract.py::test_the_levels_vectors_are_the_servers` (recomputes `gain_for` for every case),
`ui/test/loudness.sim.cjs` (`levelFor`, `relevel`, `signedDb`, `volumeChange`, `describeLevel`, `aboutLevel` against the
`typescript` half), and Swift. A rule changed on any side then fails where it was changed.

### 4.6 Phase 2 (downloads) needs from this area

A downloaded song's row keeps its album's `AlbumLoudness` as fetched (with `fetched_at`); offline decisions read that
copy through the same `decide`; it is refreshed when the download's version check runs.

---

## 5. Vectors

These are generated by running the server's `gain_for` (src/loudness.py at 1199330) and the compiled TypeScript
(`ui/src/lib/{loudness,aboutSound}.ts`, `lib/resume.ts`, `player/streamWrap.ts`). They are in
`specs/levels-vectors.json` next to this file: about 34 KB, with keys `python_gain_for` (`REFERENCE_LUFS`, `FULL_DB`,
`FULL_DB_repr`, `HEADROOM_DB`, `cases[]`) and `typescript` (`levelFor`, `relevel`, `isFlac`, `levels`, `signedDb`,
`volumeChange`, `words`).

### 5.1 `gain_for` (also in the JSON: `peak_db`, `multiplier`, `multiplier_f32`)

A selection, numbered as in the JSON's `cases` (all 41 there; the Swift test runs every one). The `loudness_lufs`
value `null` means -inf (silence).
| # | case | loudness_lufs | peak | reserve | gain_db | wanted_db | held |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | typical loud song | -10.6 | 0.8912509381337456 | 0.0 | -7.4 | -7.4 | false |
| 2 | quiet song held by its peak | -24.0 | 0.6683439175686147 | 0.0 | 3.49 | 6.0 | true |
| 4 | held inside the reserve | -20.0 | 0.6309573444801932 | 3.0 | 0.99 | 2.0 | true |
| 5 | same, no reserve (the phone) | -20.0 | 0.6309573444801932 | 0.0 | 2.0 | 2.0 | false |
| 6 | silence: loudness null, peak 0 | null | 0.0 | 0.0 | 0.0 | 0.0 | false |
| 8 | under the gate: loudness null, full-scale peak | null | 1.0 | 0.0 | -0.01 | 0.0 | true |
| 9 | peak 0 (digital zero) but loudness given | -30.0 | 0.0 | 0.0 | 12.0 | 12.0 | false |
| 15 | full-scale peak, wants up | -20.0 | 1.0 | 0.0 | -0.01 | 2.0 | true |
| 17 | 24-bit largest sample | -20.0 | 0.9999998807907104 | 0.0 | 0.0 | 2.0 | true |
| 19 | wanted -7.425 (floors to -7.43) | -10.575 | 0.01 | 0.0 | -7.43 | -7.425000000000001 | false |
| 21 | wanted -7.4200000001 (snaps to -7.42) | -10.5799999999 | 0.01 | 0.0 | -7.42 | -7.4200000001 | false |
| 22 | wanted 2.9999999999 (snaps up to 3.00) | -20.999999999899998 | 0.01 | 0.0 | 3.0 | 2.999999999899998 | false |
| 25 | wanted -0.001 (floors to -0.01) | -17.999 | 0.01 | 0.0 | -0.01 | -0.0010000000000012221 | false |
| 28 | gain -0.25 exactly (JS toFixed(1) tie) | -17.75 | 0.01 | 0.0 | -0.25 | -0.25 | false |
| 32 | held, limit 1e-10 under 3.00 (guard: 2.99) | -40.0 | 0.7079456999985745 | 0.0 | 2.99 | 22.0 | true |
| 34 | held, limit 1e-10 under 0.50 (guard: 0.49) | -30.0 | 0.9440607637559659 | 0.0 | 0.49 | 12.0 | true |
| 35 | wanted 3 - 4e-9: within 5e-7 of 300 hundredths, snaps to 3.00 | -20.999999996 | 0.01 | 0.0 | 3.0 | 2.9999999959999997 | false |
| 36 | wanted 3 - 6e-9: just outside, floors to 2.99 | -20.999999994 | 0.01 | 0.0 | 2.99 | 2.9999999939999995 | false |
| 39 | h=799.9999995: round(h,6) is 799.999999 (7.99); (h*1e6).rounded()/1e6 says 8.00 | -25.999999995 | 0.01 | 0.0 | 7.99 | 7.999999995 | false |

### 5.2 The rule's small tables (TypeScript as it is)

- levelFor: auto+album->album; auto+songs->track; song+album->track; song+songs->track; album+album->album; album+songs->album; off+album->none; off+songs->none
- relevel: auto+album->album; auto+track->track; auto+null->track; song+album->track; song+track->track; song+null->track; album+album->album; album+track->album; album+null->album; off+album->none; off+track->none; off+null->none
- isFlac: ("flac", "audio/flac")->true; ("FLAC", null)->true; (null, "audio/x-flac")->true; (null, "Audio/FLAC; charset=x")->true; ("mp3", "audio/mpeg")->false; ("m4a", "audio/mp4")->false; ("opus", "audio/ogg")->false; (null, null)->false; ("", "audio/flac ")->true
- signedDb: -7.42->"-7.42 dB"; 0.004->"+0.00 dB"; -0.004->"+0.00 dB"; 12->"+12.00 dB"; -0.25->"-0.25 dB"; 0.125->"+0.13 dB"; -0.125->"-0.13 dB"; 0.005->"+0.01 dB"; -0.005->"-0.01 dB"; 1.005->"+1.00 dB"; -1.005->"-1.00 dB"; 2.675->"+2.67 dB"; 0->"+0.00 dB"; 0->"+0.00 dB"
- volumeChange: -7.42->"7.4 dB quieter"; 2.35->"2.4 dB louder"; -0.04->"no change needed"; 0->"no change needed"; -0.25->"0.3 dB quieter"; 0.25->"0.3 dB louder"; 0.75->"0.8 dB louder"; -1.75->"1.8 dB quieter"; 2.25->"2.3 dB louder"; 0.05->"0.1 dB louder"; -0.05->"0.1 dB quieter"; 0.15->"0.1 dB louder"; -3.56->"3.6 dB quieter"; 0.95->"0.9 dB louder"; -0.94->"0.9 dB quieter"

### 5.3 Info's words - `describeLevel` (Debug) and `aboutLevel` (About)

Base answer: `{level: "album", state: "measured", gain_db: -7.42, wanted_db: -7.42, loudness_lufs: -10.6, peak_db: -1, held: false, songs: 3, measured_songs: 3, why: null}`. "entry" is suffix/level/format. Each case's full answer is in the JSON. A selection, numbered as in the JSON's 29.

| # | case | entry / answer (changes to the base) | Debug | About |
| --- | --- | --- | --- | --- |
| 1 | off: no level | flac/none/raw; no answer | Off | Off |
| 2 | mp3 asked album | mp3/album/raw; no answer | Not levelled - MP3 songs play as they are | Off for this song - only FLAC songs are adjusted |
| 5 | flac sent as mp3 | flac/album/mp3; no answer | Not levelled - FLAC songs play as they are | Off for this song - this device can't play FLAC, so it's sent as MP3 |
| 6 | flac, no answer yet | flac/album/raw; no answer | Asked for; deadwax hasn't said yet | Checking… |
| 7 | album measured | flac/album/raw; base | Album, -7.42 dB · the album at -10.6 LUFS | Album volume matching, 7.4 dB quieter |
| 9 | song held | flac/track/raw; level="track", gain_db=1.2, wanted_db=2.35, held=true | Song, +1.20 dB · held there by its peak (it wanted +2.35) | Song volume matching, 1.2 dB louder - as loud as it can go without distorting |
| 10 | album held at -0.01, wanted +4 | flac/album/raw; gain_db=-0.01, wanted_db=4, loudness_lufs=-22, held=true | Album, -0.01 dB · held there by its peak (it wanted +4.00) | Album volume matching - kept as it is, it can't go louder without distorting |
| 13 | album silent | flac/album/raw; gain_db=0, wanted_db=0, loudness_lufs=null | Album, +0.00 dB · the album is silent | Album volume matching - nothing to adjust, the album is silent |
| 14 | gain -0.25 (tie) | flac/album/raw; gain_db=-0.25, wanted_db=-0.25, loudness_lufs=-17.75 | Album, -0.25 dB · the album at -17.8 LUFS | Album volume matching, 0.3 dB quieter |
| 17 | album measuring 1 of 3 | flac/album/raw; state="measuring", gain_db=null, measured_songs=1 | Measuring its album… (1 of 3 songs) | Measuring the album… (1 of 3 songs) |
| 20 | album unmeasured | flac/album/raw; state="unmeasured", gain_db=null | Not measured yet - it played as it is this time | Not this time - the album hasn't been measured yet |
| 22 | album plain | flac/album/raw; state="plain", gain_db=null | Played as it is this time - its album was still being measured | Not this time - the album was still being measured |
| 24 | not levelled: no libraries | flac/album/raw; state="not_levelled", gain_db=null, why="deadwax is running without numpy and soundfile" | Not levelled - deadwax is running without numpy and soundfile | Off for this song - this server can't adjust volume |
| 26 | not levelled: not flac | flac/album/raw; state="not_levelled", gain_db=null, why="it isn't a FLAC file" | Not levelled - it isn't a FLAC file | Off for this song - only FLAC songs are adjusted |
| 29 | not levelled: why null | flac/album/raw; state="not_levelled", gain_db=null | Not levelled - deadwax won't level it | Off for this song - its file can't be measured |

## 6. Open questions

1. **Navidrome's `replayGain` as a fallback** for unmeasured and non-FLAC songs (the plan suggested it)?
   **Recommended: no, not in Phase 1.** The web never reads tags; tag gains come from strangers' tools with mixed
   references (ReplayGain 1's 89 dB, 2.0's -18 LUFS), so an album would play at one ruler's level one time and
   deadwax's the next; Navidrome's real JSON for it is unverified. "Played as it is this time" is honest and what the
   web does. If wanted later: `.unmeasured` and `.notFlac` entries only, Info saying "from the file's tags".
2. **How long the first song of a play waits** while its album is being measured? **Recommended: up to 20 s**
   (`LEVEL_WAIT_HIRES_SECONDS`; the web waits up to 50 s for a CD album). Joins never wait. Most taps come from an
   album page that warmed seconds earlier, so the wait is usually short or none.
3. **One decision per album per queue** (the whole album at one level or as it is), against the web's step to the gain
   once the measurement lands? **Recommended: yes** - on a gapless live album the web's step is audible, and the
   album's next play gets the gain. If James prefers the web's way: redo a `.plain` album decision only at a join
   that isn't gapless (the queue would need to know which are).
4. **Words when no answer could be had** (the route failed, or 20 s passed with none) - the web has no such case, its
   stream carries the level. **Recommended: two new lines**, Debug `Played as it is this time - deadwax didn't say in
   time`, About `Not this time - the album's volume couldn't be checked` (`the song's`), added to the shared vectors
   and to info.sim.cjs's listener-words check.
5. **Off's note on the phone**, which has no Maximum quality but whose engine converts a song whose rate differs from
   the output's? **Recommended:** `No levelling: every song plays exactly as the file is, bit for bit, unless this
   iPhone has to change its rate.` - keeping "bit for bit" (settings.sim pins it on the web); the other three verbatim.
6. **A per-song warm** for track-level songs from albums never opened (later phases' Search, playlists, Library
   Shuffle)? **Recommended: not now** - Phase 1 queues only from album pages, whose warm covers their songs. In Phase 4:
   `POST /deadwax/navidrome/level/song/{song_id}` (user; asker getSong first; one song through `measure()` under the
   same gates), rather than warming whole albums for a shuffle.
7. **An `algorithm` field in the answer**, so Phase 2's stored copies know which ruler measured them? **Recommended:
   add `"algorithm": loudness.ALGORITHM_VERSION` (int, 1) at the top level in 2.1.1** - cheap now, a contract change
   later. Phase 1 ignores it; Phase 2 re-fetches a stored copy whose algorithm isn't the server's.
8. **Should the server send a ready gain instead** (the plan's own open question)? **Recommended: raw values, as
   specified.** The rule is a dozen lines pinned by shared vectors in three languages; the phone's reserve (0 now, a
   "Leave 1 dB of room" setting per plan R10) lives on the phone; a download needs the raw values anyway.
