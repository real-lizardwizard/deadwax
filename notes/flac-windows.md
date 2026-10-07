# Windows cut straight from the FLAC (2.0.0-player.23)

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Windows cut straight from the FLAC (2.0.0-player.23)

James, on the visualizer's one documented cost (above, "The desktop visualizer"): "yes, cut the windows
straight from the FLAC". The spec is the session scratchpad's `uplan/slice-flacwindows.md`. (Numbered
.23: the merge of main's 1.1.8 took .22 while this was being built.)

- **The problem.** A window (the scrub route, `answer_window()`) was always cut from an MP4 the player's
  cache keeps. A desktop playing the FLAC as it is - Chrome, Firefox or Edge with Gapless off, a song
  not resampled - never has one made, so the visualizer's first window of each song had `_window_source`
  make the plain MP4: the whole song downloaded from Navidrome again and kept against PLAYER_CACHE_MB,
  clearing an iPhone's songs.
- **The change.** For the song AS IT IS (no `max_rate`; a cap with no plan for this song; or the
  resampled copy refused) with NO finished MP4 of it in the cache (Safari's plain one or the gapless
  player's fragmented one - the lookup `_window_source` always made), the window is cut straight from
  the FLAC on Navidrome (`_from_flac`): byte ranges of `stream` with `format=raw`, exactly as `_look`
  asks for its four bytes, through the cache's own client like every other read of the cache. Nothing is
  made, written or cached on disk, and `_used`, the cap and the eviction never hear of it. A cached MP4
  is still preferred (it costs Navidrome the version check alone); the resampled path is untouched.
- **Why nothing heard can change**: deadwax's MP4s carry the FLAC's frames untouched and a window
  renumbers its frames under a STREAMINFO of its own (flac_window.renumber, flac_of_frames), so the
  window cut from the FLAC is BYTE FOR BYTE the one cut from the plain MP4 for the same `at`/`seconds` -
  the main test (`test_flac_ranges.py`, and through the route in `test_scrub_window.py`).
- **`src/flac_ranges.py`, pure, like flac_window.py**: every step is a generator that YIELDS the
  (offset, length) it needs and is sent the bytes; `run()` drives one over bytes in memory (the tests),
  `Mp4Cache._by_ranges` with ranged reads, each move between reads in a worker thread (`advance()` -
  StopIteration can't cross into an asyncio future). It reuses flac_mp4's frame rules rather than a
  second frame finder: `_frame_header` (sync, reserved bits, CRC-8, fields against STREAMINFO),
  `_split_frames` (the next number, the duplicate-number CRC-16 rule, the last frame's checksum, the
  trailer tags), `_crc16`, `_reach`, and flac_window's `flac_of_frames`, `CannotCut`, `PastTheEnd`.
- **`_split_frames` grew three parameters, defaulting to what it always did**: `first_number` (a stretch
  starting at a frame other than 0), `to_the_end` (False: the stretch stops short of the file) and
  `tail` (below). Short of the end it answers only the frames whose end is CERTAIN (`_certain`): each
  followed by the next header with a frame's reach and HEADER_MAX (16) of the stretch after its start -
  so a false header taken for the next frame would have met the real one inside the stretch and been
  found out as in a whole file (pinned: a copy of frame 6's header in frame 5, with STREAMINFO's largest
  frame well above the real ones, is never where frame 5 ends). STREAMINFO's total is checked only from
  frame 0 (`first_number == 0`). `tail` is the file's last bytes and where they begin, for a stretch that
  runs to where the audio can end but not through the tags after it: `_audio_ends` finds the very ends
  the whole file has from those bytes, and `_last_frame_end` refuses a stretch that stops before the
  furthest of them within the reach rather than sum short. Every test in test_flac_mp4.py passes unchanged.
- **The head** (`read_head`): one HEAD_CHUNK (64 KiB) read at 0 for an ordinary file - ID3v2 tags
  skipped, 'fLaC', STREAMINFO (first and 34 bytes, or CannotCut), a SEEKTABLE up to SEEKTABLE_MAX
  (64 KiB) read, anything else skipped by its length - a cover of megabytes by a read starting past it,
  never downloaded (pinned with 3-6 MB pictures) - type 127 and blocks past the end refused, the first
  frame's header read (number 0; its sync says fixed or variable; its block size is every frame's but
  the last in a fixed stream). Then the file's last TRAILER_MAX (387) bytes, one small read: what tags
  follow the audio, by flac_mp4's own `_audio_ends` over them, and so `Head.end` - the latest place the
  audio can end within a frame's reach of the earliest - where every window's reads stop: the end of the
  file, or before an APEv2 tag longer than a frame (a cover kept in the tag), which is never read. A
  STREAMINFO length of 0 is found there too: the last frames' worth read with the tail, the last frame
  checked as a whole file's. At most HEAD_READS (32) reads - each picture past the read before it costs
  one - or CannotCut. Seek points with a sample past the song (every placeholder's is all ones) or not
  running forward are left out. Kept per VERSION in `_heads` (HEADS_KEPT 16, the song asked longest ago
  dropped), so a retag reads it again.
- **Finding the window** (`cut`, `_locate`): `low` (a frame at or before the window's first sample) and
  `high` (a place past it) start from the first frame and `Head.end`, narrowed by the seek points and by
  frames earlier windows of the version found (kept with the head, `keep_points`, POINTS_KEPT 1024 - with
  them a later window usually needs no probe). Probes - reads of 2 x reach + 16 + 4 KiB, each syncing to
  the first REAL frame in it (`_first_frame`: a right header, a number inside the song, in a fixed stream
  the stream's block size unless it ends the song, frames `_split_frames` can follow, and its own CRC-16
  summing to zero) - close in until the samples' guess is within the lead (`_lead`: an eighth of the
  window at the song's average rate, or 8 x reach) of `low`, at most PROBES (10). After the same end moves
  twice running the next probe goes halfway instead: plain interpolation (and the Illinois rule, tried
  first) closed in from one side on a song half silence, half noise. Then the READ: from a frame's reach
  and a header before `low` (bar the song's first frame), so the frame before it is in the read too; the
  frames are split from the first real frame in those bytes (`_first_frame(before=...)`), and `low` has to
  be one `_split_frames` found AFTER it, at the sample they make it - or CannotCut ("isn't a frame of
  this stream at the sample said": a seek point off a frame, or naming another sample, earlier or
  later), judged on the read's first frames before a window is looked for in them. So a window's
  frames are never taken on one header and its CRC-16 alone. More reads when the first fell short, each
  sized by `_pace`: what the frames read took, or what the later half of them by bytes took when that is
  more. The window is then picked by exactly cut_window's rule (the frame `at` falls in, then frames
  before `at + seconds` within the budget); a fixed stream's block sizes and, at the audio's end, the
  song's length are checked. WINDOW_READS (14) reads a window at most, and `read_limit()` bytes.
- **The answers are today's**: audio/flac, `X-Deadwax-Window`, WINDOW_CACHE; PastTheEnd the 416 in the
  same words; a TransportError or a short body (Navidrome breaking off) a 503 for the song; a range
  whose Content-Range names another size, or a 416 (the file changed under the reads), a 503 for the
  song with the version forgotten; any other NavidromeError raised as for the song (the route's
  `_fail`). FALLING BACK to today's path (the plain MP4 made as before), logged once a version
  (`_uncut`, bounded like `_refused`): a range answered with anything but that range (`_Whole`: a 200,
  another range, more bytes) - closed at once, never read on - and a head CannotCut, both for good for
  that version; a window's own CannotCut (a damaged end, a lying seek point) for that window only, the
  next tried from the FLAC again. A SLIP in reading the file - anything a flac_ranges step raises but
  CannotCut and PastTheEnd - is CannotCut too (`_moved`, "reading it went wrong (ValueError: ...)"),
  for good in the head and for the window in a cut, so a bug of this path is a fallback and a log line,
  never a 500. With no usable cache folder a window is still cut from the FLAC
  (nothing resampled or wrapped can be played then), and only its fallback is the 503 for the server -
  the log line then ends "its windows can't be had", and says the MP4 is used once there is a folder.
  A proxy that ignores ranges ALTOGETHER never gets this far: the version check's four bytes come back
  whole, and every FLAC is refused with "Navidrome didn't answer a range of the file" (the visualizer
  says so; Safari gets FLAC; the gapless stream plays songs the ordinary way) - troubleshooting.md says so.
- **Behaviour that moved, deliberately**: a song too big to hold (WRAP_MAX_BYTES) has its windows cut
  from the FLAC now - the 415 only where the FLAC path falls back; a song whose MP4 the muxer refused
  has its middle windows cut from the FLAC, while one reaching a damaged end falls back to that refusal's
  415. Five tests that asserted the old behaviour were changed, each saying so: `test_a_window_through_
  the_app` (whole fetch 1 -> 0, nothing in the folder), `test_the_mp4_made_for_the_first_window_is_cut_
  from_again` (now `test_a_songs_second_window_reuses_its_head`), `test_a_song_too_big_to_hold_is_a_415_
  and_never_fetched` (now cut from the FLAC, and the 415 where ranges come back whole),
  `test_without_the_cap_the_song_as_it_is_is_cut_from` (no make, the MP4 path's bytes) and
  `test_a_resampled_copy_refused_as_it_is_made_...` (`asked` [PLAN, None] -> [PLAN]).
- **After review** (fifteen findings, three of them pairs - all fixed; the reviewers' own files in the
  session scratchpad's `review-flac/` and `fixer/`, swept window by window against the MP4 path before
  and after):
  - **A hidden track fell back** (major): a window starting in silence seconds before the music read on
    at the pace its silent frames took, each read reaching less far than the one before, until the
    seven ran out - and the whole song was made into an MP4 and kept. `_pace` sizes a read on by the
    later half of the frames too. Before/after on libFLAC files: 8 min silence + 30 s, 43 of 180 windows
    fell back -> 0; 6 min + 1 min, 26 of 161 (seek table) and 41 (none) -> 0, at most 2 reads with a seek
    table.
  - **A cover in an APEv2 tag at the end** (two findings): probes landed in the tag ("no frame where one
    has to begin") and an end window read on into it a probe's length at a time until the reads ran out
    - 47 of the 160 windows from a song's last 40 s fell back. The tail read and `Head.end` above: 0, the
    tag never read, every window the MP4 path's.
  - **Four probes didn't close in on long uneven songs with no seek table** (two findings): 45 minutes of
    quiet and loud, 38 of 300 random fresh windows fell back, 35 of them past `read_limit`; a 30-minute
    song with 20 minutes of silence in the middle read 5-8x the window in its last five minutes. PROBES 10
    (each a few tens of KB): none fell back, those windows 1.25x. WINDOW_READS is PROBES + 4.
  - **Six pictures sent every window of an album to the MP4** (HEAD_READS 6, a read a picture): 32.
  - **A copy of a frame's header planted in the audio, two bytes set so the CRC-16 comes out** (a crafted
    file), reached by a probe or a seek point, was taken for that frame and served as a window that
    doesn't decode, where the MP4 path refuses the file. The read from before `low` above: the copy is
    found out exactly as in a whole file, or isn't one of the frames - refused. Measured on the
    reviewer's layouts, a copy in the frame before and one in its own frame, reached by probes, earlier
    windows' frames and a seek point: 8 wrong windows in 1,000 -> 0 (the rest refused, as the MP4 path
    refuses the file). The frame a read is split from is never kept as a place for the next window.
    **Residual, stated in `cut()`'s docstring**: copies of SEVERAL headers in a row in front of the frame
    read from, the first taken for the frame before; a whole file read from frame 0 finds those out too,
    and a stretch can't - like the MP4 path's own residuals, it takes a file made to do it.
  - **A seek point naming another sample at a frame's right place** was only refused by `% block`, and
    untested: now by the sample the frames make it, and pinned.
  - **The no-folder log line** said an MP4 was used over a 503 (`_not_cut(kept=...)`); **the
    troubleshooting entry** blamed a range-ignoring proxy for a line such a proxy never causes (it is
    caught at the version check) - now says what such a proxy does show.
  - **Rules no test pinned**: `_certain`'s margin, `_range`'s other-range and more-bytes answers,
    HEADS_KEPT and its order, `_uncut`'s bound, cut()'s `read_limit`, the frames kept across windows -
    each now has a test that fails with it broken. And a test docstring credited the Illinois rule,
    which the code rejected.
- **After a second review** (two findings, each confirmed by three skeptics - both fixed; the
  reviewers' files in the session scratchpad's `verify/`, `verify-stale-seek/` and `recheck-*/`, mine
  in `fixer2/`):
  - **A stale seek table answered a 500** (minor): a point on a real frame but claiming a sample
    EARLIER than the frame's put the frame the read is split from past the window's start, and the
    window was looked for from there before the point was judged - a ValueError out of `_pace` (`lo`
    -1) for a long window from the point: a 500 every ten seconds, no MP4 made and nothing logged,
    where the MP4 path (which reads no seek table) cut the window. The reviewer's randomised stale
    tables over a libFLAC file: 35 of 1,452 windows. The point is judged on the read's first frames
    now, before anything else is made of them (after which `lo` can't be below 0), and refused like
    any other lying point: 1,242 CannotCut and the same 210 answered, every one the MP4 path's, none
    raising; and refused in the read made from it, where the old order sometimes read on first. Plus
    `_moved`, above: any slip of the pure step falls back rather than answering a 500. Pinned pure
    (`stale()`: four minutes of the test encoder's song, points claiming a second early - a
    ValueError without the fix, a read past the point's without judging it first) and through the
    route (the MP4 path's window, the MP4 made, said once; a step made to slip - an IndexError on the
    head's first move, a ValueError in a cut after a read - falls back, for good or for that window;
    and a 416 makes no MP4, which a PastTheEnd taken for a slip would). PastTheEnd is a CannotCut, and
    CannotCut a ValueError, so `_moved` re-raises CannotCut BEFORE its catch-all.
  - **The turntable's window bullet** still gave the old 415s ("too big to hold, judged before
    anything is fetched"; "whose MP4 was refused") as the song's answer: now only a window that falls
    back from the FLAC path, judged before the song is fetched whole.
- **Measured** (libFLAC files, a 40 s window from 3.3 s): CD with a seek point every second, 1 read,
  1.01x the window; CD with no seek table, 1 read, 1.12x (the lead); 24/96, 2 reads, 1.07x. Over the
  reviewers' 39 files (CD, hi-res to 24/192, 8 channels, every block size, variable blocks, ffmpeg's,
  totals of 0, hidden tracks, APEv2 and ID3 tags, 45 minutes): 5,562 windows, swept or at random, 1,168
  of them checked byte for byte against the MP4 path - none fell back, all equal, at most 11 reads (a
  long song with no seek table) and 3 with one. The head is two reads (its start and its last 387 bytes)
  for an ordinary file. About 10 ms of CPU a 40 s CD window (6 ms from an MP4, side by side), in a
  worker thread. The client is untouched (vizAudio.ts's header comment only); `player/api.ts`'s
  scrubWindow comment still says "cut by deadwax from its own MP4" - the rules forbid client edits
  beyond that one comment.
- **Verified**: 2334 Python tests (2208 passed and 126 skipped here, without numpy, soxr and soundfile;
  106 new: `test_flac_ranges.py` 76, 30 in `test_scrub_window.py` (106 now) - and the libFLAC
  equality tests skip where `flac` isn't installed, as in CI, the encoder's always run), pyflakes, tsc,
  all 40 sims, the engine guard empty. The builder's 45 mutations re-run on the fixed code (adapted to its
  changed lines, `fixer/mut/builder_mut.py`), each restored byte for byte (checked by hash): 43 caught;
  the other two no longer pin a rule - HEAD_READS's VALUE (the tests follow the constant; a fixed head
  of sixty pictures pins the bound instead) and cut()'s own CRC-16 check of the frame it reads from,
  made redundant by the read from before `low` and removed (pinned: a first frame whose CRC-16 is wrong
  is taken as the whole file takes it, the MP4 path's window). The review's fixes: 25 more, one per
  rule (`fixer/mut/mutate.py`): all caught - two, the tail guard and the frame read from never kept,
  only once they had tests of their own. The second review's: 11 (`fixer2/mutate.py` - `low` judged
  after the loop as before, or after it with a `lo` < 0 guard, or not at all; its index, place or
  sample unchecked; `_moved` turning no slip, only ValueErrors, or a CannotCut into one; either of
  `_by_ranges`' moves past it): all caught - the first move's and a slip on a step's first move only
  once the test slipped there; a "PastTheEnd wrapped" mutation was no mutation (PastTheEnd is a
  CannotCut) and the redundant name went from the except. The earlier two sets re-run on this code
  (`fixer2/builder_mut.py`, `fixer2/fixer_mut.py`): 44 of the builder's caught, the 45th's line gone
  as above, and all 25 of the first review's - every file restored byte for byte (checked by hash).
  The repo's `.venv` was copied byte for byte out of iCloud storage for these runs (its every import
  stalled four minutes here).
- **Verified in the real page** (the app on :8081 against the stub Navidrome, which logged every stream
  request's range and bytes): three songs - a 24/96 FLAC with a seek table and a 2.85 MB picture before
  its audio, a CD one with a seek table (both made by libFLAC), and an ffmpeg-made one with none - each
  asked for windows at 0, a third in, the last 1.5 s and past the end, 40 s and 1 s, with the cache
  empty: no file appeared in the cache; every read was a range (11-14 reads for 8 windows, 1.05-1.3x the
  windows' own bytes - 18.8 MB for 17.8 MB of hi-res windows from a 36.8 MB song); past the end a 416;
  every window decoded by `flac -t`; then, the plain MP4 made by the stream route, every window asked
  again came from it and was BYTE-FOR-BYTE the FLAC path's, header included - 60 checks. The desktop
  visualizer's 42 real-page checks passed with the cache emptied first, and no MP4 appeared (11 stream
  reads, none without a range); the phone turntable's 53 passed (its MP4s were the page's own playback,
  `wrap=mp4`, its window then cut from that). Checked against 2.0.0-player.21 first, the same script
  caught the old way: the first window made an MP4, reading the whole 8.7 MB song without a range.
- **NOT verified here**: a real Navidrome's ranges on James's server (Go's ServeContent answers them as
  the fake does - the version check already depends on it); a real library's VBR and seek tables at
  scale.
