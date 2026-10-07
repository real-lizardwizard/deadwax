# The player: FLAC in an MP4 for Safari, the muxer and the cache

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

#### FLAC in an MP4, for Safari (1.1.0-player.3)

James: "go ahead and build the MP4 repackaging", after his iPhone confirmed FLAC seeks 3 and 8 s
off. Safari (and every iPhone browser) now gets each FLAC song as an MP4 holding the SAME FLAC
frames; Chromium, Arc included, keeps the file as it is. The guide's section is
`docs/player.md#seeking-and-where-safari-lands`.

- **Why an MP4 fixes it.** AVFoundation seeks a FLAC by estimating a byte offset from the bit rate
  it has parsed so far (see "Seeking"); an MP4 has a sample table (`stsz`/`stts`/`stco`) giving
  every frame's size and duration, so a seek is arithmetic. Measured with `avlab2` (AVFoundation,
  pilot-tone read) THROUGH deadwax on 8081 against the seek stub, same song, same targets:
  | file | FLAC as it is (`format=raw`) | FLAC in MP4 (`&wrap=mp4`) |
  | --- | --- | --- |
  | Varied (quiet minute, then loud) | -25.6, -22.9, +39.9, +17.9, +25.3, +38.1, +31.0; 275 s ran off the end | +0.01 on all 8 |
  | Song-like (a song's swing) | -11.8, -14.0, +3.0, -2.5, +1.7, +1.2, +1.9, +4.8 | +0.01 on all 8 |
  In Chromium the wrapped URL, set by hand on an `<audio>` with a Web Audio analyser, read the
  pilot at a constant -0.34 s from the clock on all 8 seeks - the analyser window's half, the
  same figure the raw FLAC gives - so Chromium plays and seeks the MP4 exactly too.
- **The muxer, `src/flac_mp4.py`, pure, no ffmpeg** (the image is python-slim and stays so).
  xiph's isoflac.txt layout: ftyp (`isom`, `iso2`, `mp41`), then `moov` BEFORE `mdat` (a player
  fetching by range seeks without reading to the end), one MP4 sample per FLAC frame, frames
  byte for byte, STREAMINFO in `dfLa` in an `fLaC` sample entry, sample rate as timescale, no
  `stss` (every frame is a sync sample), chunks of about a second. Deterministic (no timestamps),
  so the same file always makes the same bytes. `mp4_layout()` returns the head and where the
  audio is in the input, so the cache writes head + a slice of the FLAC it already holds rather
  than a second copy. Decoded PCM through ffmpeg was byte-identical for six real files; 57 ms for
  a 40 MB CD FLAC as first built, 51 ms since 1.1.0-player.5.
- **Splitting frames safely is the whole risk**, since FLAC has no frame index and the sync code
  turns up inside audio every ~90 KB. A candidate is taken as the next frame only if its header
  is right in every particular: every field agrees with STREAMINFO, reserved bits clear, CRC-8
  right, and exactly the NEXT frame (or sample) number, coded the shortest way - by chance once in
  2^40 bytes at worst, 2^48 past frame 127. And not left to chance: a false header taken for frame
  k leaves the real frame k's header before k+1's, carrying a number already used (and the real
  headers after it too, when several false ones were taken in a row) - so a header carrying ANY
  number already given to a frame is watched for, and the CRC-16 of the frame before that one
  decides which is real; neither or both checking out refuses the file. Only within a frame's
  reach of that frame, since 1.1.0-player.5: one numbered further back can't be real and is
  passed over. Every frame, the last included, must fit that reach - STREAMINFO's largest frame,
  or a frame of verbatim samples when it gives none. The LAST frame is always CRC-16 checked (how
  an ID3v1/APEv2 trailer is left out and a truncated file refused), block sizes must sum to
  STREAMINFO's total, a fixed-block stream's frames must all be one size, past one false sync per
  256 bytes the file is refused, and past 4 MiB of checksumming too (bounded work). Anything off
  raises `CannotRepackage` and the FLAC is sent as it is: a wrong MP4 would be worse than none.
  161 tests (`tests/test_flac_mp4.py`) with a verbatim FLAC encoder, no binary fixtures, planted
  false headers; see "After review (the muxer)" below.
- **The route: `wrap=mp4` on the EXISTING stream route**, honoured only with `format=raw` - no new
  route, `test_there_is_no_general_proxy` still pins the list. `player_cache.Mp4Cache.answer()`:
  1. **Which version** (`_version`): a `bytes=0-3` range of the file from Navidrome. Its type must
     be `audio/flac` or `audio/x-flac` (Navidrome's mime_types.yaml says `audio/flac`) AND its
     first bytes `fLaC` or `ID3`; the Content-Range gives the size, and Last-Modified plus any
     ETag the stamp. Remembered `VERSION_SECONDS` (30), since Safari asks two bytes, then the rest,
     then a range per seek. A 416 (an empty file) is a "no", not Safari's 416. Four bytes that
     Navidrome breaks off are NOT remembered: that request gets the FLAC, the next looks again.
  2. **The key is `sha256([FORMAT_VERSION, id, size, stamp])`**, and the file is named by it, never
     by the id (caller input). Navidrome's Last-Modified for a raw stream is its database's
     `UpdatedAt` (core/stream/media_streamer.go: `ModTime()` is `mf.UpdatedAt`), which moves once
     its scan has seen a change; the size is ServeContent's real one. **The MP4 carries no tags**
     - only STREAMINFO and the frames - so a retag makes the same MP4 again: a wasted repackage,
     never a wrong one. What the key must catch is a file whose AUDIO was replaced, and a
     same-size replacement is caught by the stamp (pinned). Bump `FORMAT_VERSION` whenever the
     muxer's output changes.
  3. **Miss**: the whole file (no Range) streamed to a `.part` file in 1 MiB writes, its bytes
     counted against the version's size (a length that disagrees, or too many or too few bytes,
     means it changed or broke: this request gets the FLAC, the next looks again - NOT remembered
     as a refusal, which would keep a good song out for good), then `_repackage` in a worker
     thread: read, `mp4_layout`, write `<key>.<token>.tmp`, `os.replace` into place, so a
     half-written MP4 is never served. The input is held once in memory (`WRAP_MAX_BYTES`, 512 MiB;
     bigger is refused from the probe's size, logged at info, nothing fetched).
  4. **Single flight**: one task per key in `_working`, awaited through `asyncio.shield` so a
     phone hanging up can't cancel what another request waits on; and one repackage at a time
     altogether (`_gate`, an asyncio.Lock made per event loop - TestClient runs each request on its
     own loop), which bounds memory; inside it the file is checked for again. **Verified**: ten
     requests at once on a cold song, one abandoned after 20 ms, made one MP4 and every range
     matched. (Since 1.1.0-player.4 the gate covers the repackage only, and a make nobody waits
     for any more is stopped - see "After review (the cache)".)
  5. **Refusals** (`CannotRepackage`, too big) are remembered per key (`REFUSALS_KEPT`, 256) and
     logged ONCE: `player: song X is sent to Safari as FLAC, not in an MP4 - <reason>`. Transient
     failures (Navidrome dropping the download, the disk) are logged each time and not remembered.
     ~~Every failure answers None and the route relays the FLAC~~ - not a request carrying on from
     an MP4, which the review found spliced two files; see "After review (the cache)".
- **Served by `ranged_file`, not Starlette's FileResponse**, which was read (0.50) and fails three
  ways: its 416 says `Content-Range: */N` without the unit, it refuses a suffix range longer than
  the file (RFC 9110 says the whole file, as a 206), and it stats the file only as it sends, so an
  eviction in between is a 500. `ranged_file` opens the file FIRST (an open file outlives its
  name; FileNotFoundError reaches the caller while it can still send the FLAC), answers one range
  (several, another unit or a malformed one get the whole file with a 200, which the RFC allows),
  and honours If-Range strongly against the ETag (the key) or exactly against Last-Modified (the
  MP4 file's own mtime - which is why LRU recency is kept in memory, `_used`, and never by
  touching the file: that would change the validator under a seek). `audio/mp4`,
  `Cache-Control: no-cache`, Accept-Ranges, exact Content-Length; GuardMedia and the gzip
  exemption apply by path already (`/deadwax/navidrome/stream/`), and a test checks both.
- **The cache: `tempfile.gettempdir()/deadwax-player`, 1 GiB, least recently served first**, never
  the file just made. Temp space, not /config: it is rebuilt on demand, the config volume is what
  gets backed up, and a new image starts it empty. Leftover `.part`/`.tmp` files older than 10
  minutes are cleared on first use. ~~No setting, decided~~ **Two settings since 1.1.0-player.4,
  asked for** (`PLAYER_CACHE_PATH`, so it can live on an SSD, and `PLAYER_CACHE_MB`) - see "After
  review (the cache)". Still never /config by default.
- **The page** (`lib/streamWrap.ts`, pinned by `wrap.sim.cjs`): `wrapsFlac()` once per page -
  WebKit that isn't Chromium (any iPhone/iPad UA, CriOS and FxiOS included; a "Macintosh" UA with
  touch points is an iPad in desktop mode, even one claiming Chrome; otherwise `AppleWebKit/`
  without `Chrome/`, which HeadlessChrome, Edge, Opera, Samsung and Arc all carry) AND
  `canPlayType('audio/mp4; codecs="flac"') !== ''`. Per song, `asksForMp4()`: a FLAC by suffix or
  type, and `format=raw` (a transcode has no FLAC in it). `streamUrl(track, canPlay, pageWraps)`;
  usePlayer's `addressOf()` is used for the element, the reload, the gapless download and the
  unfinished handover alike, so all four ask for the same URL and the server's cache serves them
  all. `memoryPlan` already took any `audio/*`, so the gapless download holds the MP4 unchanged.
- **The readout says how the song came**, since an element never shows what type it was sent and
  deadwax may have sent the FLAC: `checkWrapped()` asks the same URL for `bytes=0-1` at every song
  (`load` and `handOver`), reads the Content-Type, and drops an answer for a song no longer
  playing. The "Last seek" line ends ` · FLAC in MP4`, ` · sent as FLAC, not in an MP4`, or
  ` · asked for FLAC in MP4` until the answer lands; nothing in Chromium. It describes the song
  PLAYING, so after a song change it sits beside a seek judged on the song before. (Since
  2.0.0-player.10 it is Info > Debug's **Sent as** row, off the now-playing sheet: built on the same
  `describeWrap`, less "sent as" and its rate, with the depth and rate it was sent at on the end -
  `FLAC in MP4, 24-bit, 48 kHz` - and the resampling on a **Resampled** row of its own.)
- **First-request delay** (a cold `bytes=0-1` through deadwax on this Mac, the stub on
  localhost): 131-225 ms for a 4-minute CD-quality FLAC (29 MB, ~970 kbps; the repackage itself
  77-87 ms of it, the rest fetching from the Python stub), 91 ms for Varied (19 MB); a cached
  answer 1.2 ms, against 2.3 ms for the raw FLAC relayed. A NAS will be slower; a real Navidrome
  serves the file faster than the stub.
- **Verified in the real page** (Chromium, 8081, the seek stub): the page as it is - element on
  `format=raw`, the gapless download `?format=raw`, a handover "from memory" at 226 ms, the seek
  line with no suffix. Then with `navigator.userAgent`/`maxTouchPoints` overridden to an iPhone's
  and the player module re-imported: the element on `&wrap=mp4`, the next song downloaded as
  `&wrap=mp4` and played from its `blob:` after a handover "from memory", the line reading "No
  seek yet · FLAC in MP4" and, after a real tap at 50%, "Last seek: asked 2:30, the player said
  2:30 · FLAC in MP4", then "... the song ended on time ..." at the end; at 375x667 the line wraps
  above the title with nothing clipped. Every served byte and range (0-1, 1000-, a suffix, a
  middle, past the end, If-Range stale and current) compared equal to `flac_to_mp4()` of the file
  for Varied, the ID3-fronted Varied and the CD file.
- **Tests**: 32 through the real app in `tests/test_navidrome.py` (a fake Navidrome serving a
  FLAC from the muxer tests' encoder), and `wrap.sim.cjs` plus a Safari/Chromium section in
  `player.sim.cjs`. Mutations: 14 of the cache's (If-Range ignored, the suffix clamp, refusal
  memory, the stamp in the key, the LRU touch, LRU order, the cap, version memory, the bytes check,
  the size cap, the byte count, the 416's unit, the part file left, a weak ETag taken) and 8 of the
  page's (the answer-for-this-song guard, the download's URL, the handover's check, the iOS and
  iPad rules, the Chrome exclusion, the raw-only rule, the canPlayType ask) all caught - after
  the stamp, the byte count and the two iOS rules first went uncaught and tests were added.
- **NOT verified - the phone's to answer**: that the iPhone's AVFoundation lands in the MP4 as the
  Mac's does (the readout's end-of-song line is how James sees it); how long a first play waits
  over WireGuard from the NAS; that the gapless `blob:` of an MP4 plays on the phone (it plays in
  Chromium); memory on the NAS with hi-res files; and Safari's own request pattern against the
  cache (only curl, AVPlayer and Chromium have asked it).

#### After review (the muxer, 1.1.0-player.4)

An adversarial review confirmed three findings in `src/flac_mp4.py`, all fixed together:

- **Anything appended that checksums to zero went into the last MP4 sample.** FLAC's CRC-16
  starts at zero with nothing XORed at the end, so once a frame sums to zero, appended zero
  bytes keep it there, and so does a run of whole frames, each summing to zero. The end check
  took the end of the file on that alone: 16 zeros after a 60 s `flac -8` file made the last
  sample 1302 bytes instead of 1286, and AVPlayer (`avend`, from 50 s) posted
  FailedToPlayToEndTime at 57.7 s (-11800 / OSStatus -50) on a song it plays to 60.0 as FLAC -
  the same with 64 to 4096 zeros. `_last_frame_end` now refuses (the FLAC is served) when:
  the last frame checks out at more than one candidate end (a tag whose own CRC-16 is zero, 1
  in 65,536 - the longer was taken, tag and all); the sum, carried in the same pass to every
  sync code in the last frame, is zero at one (a frame's end with another after it); or three
  or more zero bytes come before the chosen end. **Don't strip zeros instead**: a real
  frame's CRC-16 ends in a zero byte in one file of 256 and that can't be told from one
  appended zero; a real frame ends in three only when its CRC-16 is 0x0000 and the byte
  before it is zero too. One or two appended zeros stay in the last sample, and AVPlayer
  played those MP4s to the end (measured). ~~Still let in: any other trailer whose CRC-16
  happens to be zero, 1 in 65,536~~ - not so: a whole frame of the OTHER blocking strategy got
  in every time, and anything built to sum to zero still can; see the second review below.
- **Each header repeating the number just used cost a whole-frame checksum, uncharged.**
  review4's `m/dup_dos.py` (a valid 397 KB FLAC, frame 1 full of copies of its own header):
  200 copies 1.8 s, 1,000 copies 8.8 s, packed with 21,800 copies 196 s - and through the app
  every other Safari song waited behind it on the cache's one gate (`m/gate_demo.py`: an
  ordinary song's first byte at 8.8 s). Now every such header is charged to
  FALSE_SYNC_BUDGET; `_Checksums` carries one running CRC-16 per origin and remembers every
  answer, so a frame is summed once, not once a copy; and CHECKSUM_BUDGET (1 MiB plus twice
  the file) bounds all checksumming, refusing past it. After: 0.01 s, 0.01 s, and refused in
  0.02 s; gate_demo's songs answer at once. A real file sums its last frame and any tag and
  nothing else - a test pins it with the budget set to exactly that. ~~The worst case is now
  linear, about twice the file at ~15 MB/s of pure-Python CRC~~ - and linear was the problem:
  one file with a long tail still held the gate for seconds. The budget is 4 MiB whatever the
  file since the second review, below.
- **A repeated number where BOTH readings check out kept the first**, splitting a valid FLAC
  in the wrong place with no error (`m/wrongsplit.py`: a start at 18580 where frame 2 really
  is at 32965; AVAssetReader failed on the MP4 with -50). Both checking out is refused now,
  as neither always was: in a real file it takes a false header (2^-40) AND a 1-in-65,536
  checksum. That held for one planted copy only: two in a row got past it (see the second
  review).
- **Measured**: the 40 MB CD FLAC maps in 55.2 ms against 55.0 before (median of 15). 112 of
  121 FLACs to hand (the review battery, the seek and gapless libraries, the big and hi-res
  files) give byte-identical MP4s; the nine that changed are six zero trailers, the two
  crafted wrong splits and the packed-copies file, all now refused. Through the real app
  s60 + 16 zeros answers `audio/flac`, and s60 itself `audio/mp4`, playing to 60.0 s in
  AVPlayer.
- **Tests**: 19 new in `tests/test_flac_mp4.py` (103 now); 14 fail on the old muxer, and the
  other 5 pin what must still be accepted (one or two appended zeros, a last frame whose own
  CRC-16 ends in one or two zeros). All 8 mutations of the new rules tried were caught.
- **`FORMAT_VERSION` is 2** (player_cache.py), bumped at integration. The muxer's output didn't
  change for any file it still wraps, but a cache kept since 1.1.0-player.3 holds MP4s of the
  files it now refuses, which AVFoundation stops in before the end; the new key means they are
  never served again, at the cost of one re-make of each song cached.

A second review, of those fixes, confirmed three more crafted files that got through, all fixed
in 1.1.0-player.5. Each was reproduced with its script in the scratchpad's `verify5` before the
fix and after it.

- **Two header copies in a row still split a valid FLAC in the wrong place.** Only a header
  repeating the number JUST used was watched for. So copies of frame 2's and frame 3's headers
  inside frame 1 were both taken, and the real frame 2's header, carrying a number no longer
  looked for, was passed over as a false sync. `verify5/twoplant.py` built two such files: A
  split at [.., 16571, 18580, 20580, 65753] and B at [.., 16571, 18580, 49359], where the real
  starts are [.., 16571, 32965, 49359, 65753]. `flac -t` passes both, and AVAssetReader failed on
  both MP4s (-11800 / -50).
  - `_frame_header` now reads the number, whatever it is, and the split watches for a header
    carrying ANY number already given to a frame. The rule is the old one at any slot: the frame
    before that one checks out either where the next was taken to begin or at this header, and
    everything taken in between was inside it.
  - A now wraps, split where it should be: AVAssetReader and ffmpeg both decode its MP4 to
    libFLAC's PCM exactly. (ffmpeg's own FLAC demuxer misreads the FLAC itself.)
  - B, where frame 1 checks out at the first copy as well, is refused as two readings. The old
    test of two copies in a row ("refused rather than guessed") now wraps correctly, for the same
    reason as A.
  - **Only within a frame's reach.** A real file carries a valid header with SOME earlier number
    far more often than one with the next number: past frame 127 its number byte has 128 chances
    instead of one. On random bytes for a CD stream 3,000 frames in, that was once in 2^33.6
    bytes (one per 13 GiB), roughly one 40 MB track in 300. Refusing those would cost real
    songs, and so would summing back to their frame (the whole file, for number 3 turning up in
    frame 3,000). So a header further from the start of that frame than any frame can reach is
    passed over unsummed: the frame couldn't be that long. The last number given is checked
    whatever the distance, as before.
- **A frame's reach** (`_reach`) is what makes that sound, and bounds everything below.
  - It is STREAMINFO's max_framesize when the encoder wrote one (libFLAC and ffmpeg write the
    true figure). Otherwise it is a frame of the largest block stored verbatim, the sum in
    ffmpeg's `ff_flac_get_max_frame_size`, which no encoder goes past.
  - No frame is taken that makes the one before it larger than that, and no last frame may be.
    A frame past it means the reach is wrong for this file, and so is everything it decided.
  - Of the 217 FLACs to hand (1.37 GB, 1.9 million frames), none has a frame past its reach.
    Two, in review4's battery, leave max_framesize 0.
  - **Residual**: the reach is only as honest as the file. A crafted file with a frame larger
    than its own STREAMINFO allows can still be split wrong. With no max_framesize given, the
    same goes for a frame larger than verbatim (legal FLAC that no encoder writes). Either needs
    two or more planted copies with checksum bytes solved as well, and costs one song in Safari.
    Middle frames are still never checksummed, so a whole frame slipped in between two others is
    caught only when its number was given within a frame's reach of it, or it makes a frame
    larger than the reach.
- **A whole frame of the OTHER blocking strategy after the last went into the last sample
  every time.** The last frame was searched for the stream's own sync code only, and such a
  frame sums to zero on its own. `verify5/s60_plus_fff9.flac` is a 60 s `flac -8` file plus its
  own frame 0 re-coded with 0xFFF9: its last sample was 2575 bytes where STREAMINFO says 1298,
  and AVPlayer stopped at 57.8 s (-11800 / -50) on a song it plays to the end as FLAC.
  - Both sync codes are looked for now.
  - A last sample larger than the reach is refused before anything is summed, which alone
    refuses this file: "the last frame would be 2575 bytes, larger than any frame of this stream
    can be (1298)".
  - One or two appended zero bytes still fit s60's reach and stay in. Sixteen don't.
  - **Still let in**: something appended that sums to zero and starts with no sync code, while
    the last sample stays within the reach. That happens one time in 65,536 by chance, and every
    time if built so. With no max_framesize the room is the verbatim bound's slack over the last
    frame.
- **The checksumming was still about twice the file.** `verify5/bigtail.py` (a valid FLAC and 64
  MiB appended with no sync code in it) took 9.2 s to refuse, 134 MB summed. Through the app an
  ordinary song asked for 0.5 s later got its first byte at 9.3 s, behind the cache's one gate.
  At WRAP_MAX_BYTES that is over a minute here.
  - An end further from the last frame's start than a frame can reach is ruled out before
    anything is summed. Tails of 16, 64 and 512 MiB are refused with nothing summed, in 0.0,
    0.0 and 0.3 s (the last is the search for sync codes through 512 MB).
  - `CHECKSUM_BUDGET` is 4 MiB whatever the file, about a quarter of a second here. Only a
    stream claiming frames megabytes long can reach it, since the reach bounds every sum.
  - Through the app (verify6's copy of gate_demo, 64 MiB tail) the ordinary song answers at
    0.5 s, when it is asked.
  - A real file's tag gets the same treatment: a 1 MiB APEv2 tag (a cover) after the audio used
    to be summed and now isn't.
- **Measured**: all 217 FLACs to hand (the seek, step1 and review4 libraries and the big files)
  against 1.1.0-player.4's muxer. 209 give byte-identical MP4s. The other 8, the review's zero
  and junk trailers, are refused by both, 6 of them now by the reach before anything is summed.
  The 40 MB CD file maps in 50.8 ms against 55.1 (median of 15, twice over).
- **Tests**: `tests/test_flac_mp4.py` has 161 now, 58 more, with the header and appended-frame
  tests rewritten. They cover:
  - chained copies resolved, and refused where both readings check out;
  - old numbers within and beyond reach;
  - frames larger than STREAMINFO allows, at the second, a middle and the last frame, and one
    with a copy halfway;
  - the other strategy's frame both ways, with the largest frame known and unknown, and
    `flac -8`'s own file with its frame 0 appended re-coded;
  - 16 MiB appended refused with nothing summed, a stream claiming 16 MiB frames stopped at the
    budget, a big tag left out unsummed, and verbatim frames of every shape within reach when
    STREAMINFO gives none.

  Sixteen mutations, each undoing one rule, are all caught. The first pass missed three. The
  reach on tag candidates and carrying a sum on from an earlier frame got tests. The third,
  checking every frame taken since the slot rather than only the one before it, turned out to
  add nothing, and was dropped.
- **`FORMAT_VERSION` is not bumped** here (it is player_cache.py's). Every real file's MP4 is
  unchanged. A 1.1.0-player.4 cache can hold a wrong MP4 only of a crafted file (twoplant A or
  B, a frame of the other strategy appended), and serves it until it is evicted. Bumping would
  clear those at the cost of re-making every cached song.

#### After review (the cache, 1.1.0-player.4)

The same review confirmed five findings in `src/player_cache.py` and the page, and one in the
docs; fixed together with two settings James asked for so the cache can live on an SSD. Each was
reproduced with review4's script before the fix and after it, and again after integration.

- **Skipping songs in Safari made the song landed on wait for every one skipped (major).** Each
  make was a shielded task nothing cancelled, one lock covered the download from Navidrome as
  well as the repackage, and `checkWrapped()`'s `bytes=0-1` was never aborted - so four Nexts on
  uncached songs downloaded and repackaged all four, in turn, before the fifth started.
  - `_Make` counts the requests waiting on a make, and the last to leave cancels it, its
    Navidrome download closed with it. A later request for that song starts afresh.
  - The route wraps `answer()` in `unless_abandoned()`, since uvicorn never cancels a handler
    whose phone has gone; a hang-up answers 204 into the closed connection.
  - `_gate` covers `_repackage` only, so downloads no longer queue behind each other.
    `_to_the_end` keeps it held until the worker thread finishes even when the make is cancelled:
    a thread can't be stopped, and a second song mustn't be held in memory beside it.
  - `checkWrapped()` has an AbortController, aborted at the next song and on unmount.
  - `review4/skip.py` at 100 MB/s, song 5's first byte: 2880-2897 ms before, 531-559 ms after
    (one song alone 546-630 ms), MP4s made 6 before and 2 after; uncapped 316-473 ms before,
    171-286 after. Live under uvicorn, the stub at 5 MB/s, four skips 150 ms apart: song 5 in
    5539 ms against 5513 ms for one song alone, four "was stopped" lines, and the stub saw each
    skipped download hang up part-way.
- **One URL could be answered as FLAC and then as MP4** (`test_splice.py`: a cut first download
  gave `bytes 0-1/200917` as FLAC, then `bytes 2-100/201415` from the MP4; the other way round
  after an eviction). The element splices the two into a decode error.
  - `_answered` remembers what each SONG was last answered as, and `continues()` tells a fresh
    start (Safari's `bytes=0-1` probe, or no Range) from a continuation (anything else).
  - A continuation of a FLAC answer stays FLAC, however long after. A fresh start stays FLAC for
    `VERSION_SECONDS` after one, so the readout's probe and the element are told the same.
  - A continuation of an MP4 answer re-makes the MP4 and waits for it, also when the file
    vanishes between being found and opened. If it still can't be had, it is a **503** with
    `Retry-After: 2` and `Cache-Control: no-store`, never FLAC bytes. The page's retry then
    starts afresh, and a fresh probe may get FLAC.
  - After: (a) both FLAC, the second body `FLAC[2:101]`; (b) MP4, then 503.
  - Costs, stated: a transient failure keeps that song on FLAC for its play; the memory is per
    song, not per phone (deadwax can't tell clients apart), so two clients on one song around a
    failure can still see a flip; and whether Safari always starts a song with exactly
    `bytes=0-1` is unverified on a phone - if it didn't, a retry after a failure would get a 503
    rather than the FLAC.
- **A disk short of space filled up and was never given back** (`enospc.py`: songs 3-6 sent as
  FLAC, 76 MiB held for good). `_make_room()` runs BEFORE the download now: the MP4s played
  longest ago are cleared until the new song fits under the cap, counting the songs being made
  (`_reserved`), and the disk has `MAKE_ROOM_FACTOR` (2) copies of it plus `DISK_SPARE_BYTES`
  (128 MiB) free. Short even then is FLAC, with nothing fetched. ENOSPC anyway (something else
  writing) clears twice the song and tries once more. After: all six wrapped.
  - The cap bounds the finished MP4s. The folder's peak is the cap plus one `.part` per song
    being made, and a song bigger than the whole cap is still made - kept on its own, the one way
    past the cap. The docs say both.
  - **Found at integration**: `_make_room()`'s loop variable was `size`, rebinding the song's own
    size that `fits()` reads, so the room was judged by whichever song was about to be cleared. A
    big song after small ones cleared nothing: a 50 MB song beside ten 9 MB ones under a 100 MB
    cap went 40 MB past it until `_evict` trimmed it after the make.
    `test_room_is_made_for_the_song_coming_not_the_size_of_the_songs_cleared` fails without the
    fix.
- **A read-only root filesystem stopped deadwax starting** (`ro_import.py`, `ro_app.py`): the
  cache folder was `tempfile.gettempdir()` at import, which raises when nothing is writable.
  Nothing is resolved at import now, and no usable folder means FLAC, logged once per distinct
  problem (`_said`).
- **The cache folder wasn't checked to be deadwax's own** (`plant.py` served a planted link's
  target as `206 audio/mp4 b'PRIVATE KEY MATERIAL'`). `_judge()` lstats `deadwax-player` before
  anything in it is listed, deleted or served: a real folder, not a link, owned by
  `os.getuid()`, with no group or other permission bits. Anything else is refused - FLAC, and one
  log line naming what to remove. **Only the permission bits count** (verification pass): the
  first cut demanded the mode be exactly 0700, and OpenMediaVault sets setgid on every shared
  folder (sharemgmt ORs in 02000), which Linux's mkdir passes on - so `deadwax-player` came out
  02700 on James's platform and was refused on every song, with advice ("remove it") that could
  only recreate it. macOS's mkdir doesn't inherit setgid, which is how the Mac tests missed it.
  Now `_judge` refuses `mode & 0o077`, and `_own` chmods a folder it has JUST made to 0700
  (never one it found). Made, chmodded and still open means a disk that keeps no permissions
  (CIFS, NTFS, exFAT), which gets its own message pointing at a Linux-formatted disk. Clean-up and eviction never follow links, and cached files are opened with
  `O_NOFOLLOW`. Residual: if the folder `PLAYER_CACHE_PATH` names can be written by another
  user and isn't sticky, they could swap `deadwax-player` between the check and the file
  operations.
- **The settings.**
  - `PLAYER_CACHE_PATH` (the Paths group, Settings → Library). Empty is
    `gettempdir()/deadwax-player`. Set, deadwax makes its OWN `<path>/deadwax-player` (0700),
    never chmods or chowns the folder named, and touches nothing else there - so it can name a
    shared folder. Read on every request (`Mp4Cache.directory`, `_folder()`), so a change needs
    no restart; a new folder clears `_used`. Not validated on save, like the other paths: the
    row adds `folder_problem()` (the same `_judge`, making nothing) to `_describe_path`'s
    exists-and-writable check.
  - `PLAYER_CACHE_MB` (after `DB_PATH`). Default 1024. `parse_player_cache_mb()` takes ASCII
    digits only, 64 to 1048576, and a trailing "MB"; anything else is refused on save. Read at
    every use (`player_cache_bytes()`). An unreadable environment value is an error row saying
    1024 is used.
  - Both are commented into `docker-compose.example.yml` (with a `/cache` volume line) and
    `.env.example`, and documented under Paths in docs/configuration.md.
  - **Verified in the real page** (Chromium with an iPhone user agent, the seek stub, 8081): the
    element played `&wrap=mp4` and the readout said "FLAC in MP4"; three real taps landed (the
    pilot read 210.51, 60.32 and 271.07 against clocks of 210.79, 60.79 and 271.56, the
    analyser's usual lag); the MP4s went into the configured folder's `deadwax-player` (mode
    700, "256 MB at most" logged); changing `PLAYER_CACHE_PATH` in the tab moved the next MP4 to
    the new folder with no restart.
- **The docs' MP3 claim was wrong.** player.md and troubleshooting.md said an MP3 is sent as it
  is because "Safari seeks those properly already", which holds for a CONSTANT-bit-rate MP3
  only. avlab2 on review4's `varied-vbr.mp3` (LAME V2 with a Xing header) landed -0.29, -2.29,
  +41.31, +8.31, -0.19 and +33.31 s off at 90, 250, 30, 150, 200 and 60 s, where the CBR
  `varied-320.mp3` landed +0.01 on every seek. WebKit's `createAVAssetForURL` doesn't set
  `AVURLAssetPreferPreciseDurationAndTimingKey`, so avlab stands for Safari. The docs now say a
  VBR MP3 can land seconds off in Safari and isn't repackaged, and that AAC and ALAC in `.m4a`
  are MP4s already. The test song swings its bit rate far more than music does, so how far off
  a real V0 album lands is unknown. Repackaging MP3 is not built.
- **Tests**: `tests/test_player_cache.py` is new (32 functions, 48 cases); three tests in
  test_navidrome.py changed, because they pinned the flip (the request after a cut download
  stays FLAC now, and wraps once `VERSION_SECONDS` have passed); `player.sim.cjs` checks that
  Next lets go of song 1's probe. Fifteen mutations, each undoing one fix, were all caught, and
  so is the make-room one.
