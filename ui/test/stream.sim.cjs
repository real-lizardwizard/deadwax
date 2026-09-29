/**
 * The one-stream engine's decisions (lib/streamPlan.ts): which songs may stream and join a run,
 * where each song sits on the stream's timeline, which song and fragment the playhead is in, what
 * to fetch next from what is buffered, when to fill and when to stop, what an answer from deadwax
 * means, and how listening and the stall are counted across a join.
 *
 * What it pins is heard only on the phone, locked, in a pocket: a join that clicks because a song
 * was placed a rounding error away from where the one before it ended; the playhead read as being
 * in the song before at a join, so the lock screen shows the wrong title; a fragment the playhead
 * needs never fetched because an eviction left a hole the bookkeeping didn't know about; the same
 * bytes fetched over and over after a seek back; a buffer filled past what iOS allows; a partial
 * answer appended at the wrong place; a stream kept going after the file changed under it; or a
 * song counted as heard twice across a join.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/stream.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-stream-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/streamPlan.ts', 'src/lib/fmp4.ts', 'src/lib/playQueue.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const plan = require(path.join(OUT, 'lib/streamPlan.js'))
const {
  formatStreamable, joins, placeSong, songAt, fragmentAt, fragmentSpan, rangesOf, covered, aheadSeconds,
  nextWant, aheadBytes, shouldFill, lowerBudget, classifyAnswer, retryDelay, streamable, splitAcrossJoin, joinStallMs,
  PIECE_MAX_BYTES, PIECE_MAX_SECONDS, REFILL_BELOW_S, FILL_TO_S, MANAGED_AHEAD_BYTES, PLAIN_AHEAD_BYTES,
  RETRY_DELAYS_MS, RETRY_AFTER_MAX_MS, HEADER_TIMEOUT_MS, BODY_STALL_MS, SOURCEOPEN_TIMEOUT_MS, STUCK_MS, ENGINE_OFF_MS,
} = plan
const { LISTEN_SLACK_SECONDS } = require(path.join(OUT, 'lib/playQueue.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
/** Seconds compared to the microsecond, where the arithmetic is floating point on purpose. */
const us = (x) => Math.round(x * 1e6) / 1e6

const CD = { sampleRate: 44100, channels: 2, bitsPerSample: 16 }

/**
 * A head as lib/fmp4.ts would read it: `frags` are [units, bytes] for each fragment, in order,
 * starting after an index ending at byte 1000.
 */
function head(frags, format = CD, timescale = format.sampleRate) {
  let start = 1000, t0 = 0
  const fragments = frags.map(([units, bytes]) => {
    const fragment = { start, end: start + bytes, t0, units }
    start += bytes
    t0 += units
    return fragment
  })
  return { initEnd: 700, indexEnd: 1000, timescale, units: t0, format, fragments }
}
/** A song of `seconds` in 1 s fragments of `bytes` each (the last shorter), at 44.1 kHz. */
function song(seconds, bytes = 200_000, format = CD) {
  const total = Math.round(seconds * format.sampleRate)
  const frags = []
  for (let done = 0; done < total; done += format.sampleRate) frags.push([Math.min(format.sampleRate, total - done), bytes])
  return head(frags, format)
}
/** A run placed from heads, as the engine places it. */
function run(heads, ids = heads.map((_, i) => `s${i}`)) {
  const songs = []
  heads.forEach((h, i) => songs.push(placeSong(songs[i - 1] ?? null, i, ids[i], h)))
  return songs
}

/* ========================================================================== */
console.log('\nwhich formats may stream')

check('CD: 44.1 kHz, 16-bit, stereo', formatStreamable(CD), true)
check('48 kHz, 24-bit, stereo (the phone lab played it)', formatStreamable({ sampleRate: 48000, channels: 2, bitsPerSample: 24 }), true)
check('mono', formatStreamable({ ...CD, channels: 1 }), true)
check('32 kHz', formatStreamable({ ...CD, sampleRate: 32000 }), true)
//? above 48 kHz the sample entry holds a clamped rate no engine has been seen to play
check('88.2 kHz: no', formatStreamable({ ...CD, sampleRate: 88200 }), false)
check('96 kHz: no', formatStreamable({ ...CD, sampleRate: 96000, bitsPerSample: 24 }), false)
check('48001 Hz: no', formatStreamable({ ...CD, sampleRate: 48001 }), false)
check('6 channels: no', formatStreamable({ ...CD, channels: 6 }), false)
check('3 channels: no', formatStreamable({ ...CD, channels: 3 }), false)
check('no channels: no', formatStreamable({ ...CD, channels: 0 }), false)
check('8-bit: no', formatStreamable({ ...CD, bitsPerSample: 8 }), false)
check('20-bit: no', formatStreamable({ ...CD, bitsPerSample: 20 }), false)
check('32-bit: no', formatStreamable({ ...CD, bitsPerSample: 32 }), false)
check('no rate: no', formatStreamable({ ...CD, sampleRate: 0 }), false)

/* ========================================================================== */
console.log('\nwhich songs join a run')

{
  const [first] = run([song(3)])
  check('a CD song starts a run', joins(null, song(3)), true)
  check('a 96 kHz song can\'t start one', joins(null, song(3, 1000, { sampleRate: 96000, channels: 2, bitsPerSample: 24 })), false)
  check('the same format joins', joins(first, song(4)), true)
  check('another rate ends the run', joins(first, song(4, 1000, { ...CD, sampleRate: 48000 })), false)
  check('another depth ends it', joins(first, song(4, 1000, { ...CD, bitsPerSample: 24 })), false)
  check('mono after stereo ends it', joins(first, song(4, 1000, { ...CD, channels: 1 })), false)
  //? the same format on another clock: the placement would count in two different units
  check('the same format on another timescale ends it', joins(first, head([[1000, 100]], CD, 1000)), false)
  check('a format that can\'t stream ends it even after a streamable run', joins(first, song(4, 1000, { ...CD, channels: 6 })), false)
}

/* ========================================================================== */
console.log('\nwhere each song sits')

{
  const songs = run([song(2.5), song(3.25), song(1)])
  check('the first starts at 0', [songs[0].startUnits, songs[0].start], [0, 0])
  check('its length is its units over the timescale', songs[0].length, Math.round(2.5 * 44100) / 44100)
  check('the second starts where the first ends, in units', songs[1].startUnits, songs[0].head.units)
  check('...and in seconds, exactly', songs[1].start, songs[0].end)
  check('each keeps its queue index and id', songs.map((s) => [s.index, s.id]), [[0, 's0'], [1, 's1'], [2, 's2']])
  check('the run\'s end is every unit over the timescale', songs[2].end, (songs[0].head.units + songs[1].head.units + songs[2].head.units) / 44100)
}
{
  //? twenty songs of odd lengths: summed in seconds they drift a rounding error per song, and at a
  //? join a drift is the playhead said to be in the wrong song - so placement counts in units
  let seed = 7
  const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 }
  const lengths = Array.from({ length: 20 }, () => Math.floor(120 * 44100 + rnd() * 240 * 44100) | 1)
  const songs = run(lengths.map((units) => head([[units, 1_000_000]])))
  let startsExact = true, joinsExact = true, lengthsExact = true, naiveDrift = 0, naive = 0, sum = 0
  songs.forEach((s, i) => {
    if (s.start !== s.startUnits / 44100) startsExact = false
    if (i > 0 && s.start !== songs[i - 1].end) joinsExact = false
    if (s.length !== lengths[i] / 44100) lengthsExact = false
    if (naive !== sum / 44100) naiveDrift++
    naive += lengths[i] / 44100
    sum += lengths[i]
  })
  check('20 odd-length songs: every start is startUnits / timescale, exactly', startsExact, true)
  check('...every song ends exactly where the next begins', joinsExact, true)
  check('...every length is its units / timescale', lengthsExact, true)
  check('...the run ends at all the units / timescale', songs[19].end, sum / 44100)
  check('...where summing seconds would have drifted (so this check means something)', naiveDrift > 0, true)

  //? a playhead read from a naive sum, a hair either side of the true join, is still the right song
  let naiveT = 0, right = true
  songs.forEach((s, i) => {
    if (songAt(songs, naiveT) !== s) right = false
    naiveT += lengths[i] / 44100
  })
  check('songAt at every join reached by summing seconds: the song starting there', right, true)
}

/* ========================================================================== */
console.log('\nwhich song the playhead is in')

{
  const songs = run([song(10), song(5), song(7)])
  const [a, b, c] = songs
  check('0: the first', songAt(songs, 0), a)
  check('inside the second', songAt(songs, 12), b)
  check('exactly at a join: the song starting there', songAt(songs, b.start), b)
  check('a nanosecond before a join: still the song starting there', songAt(songs, b.start - 1e-9), b)
  check('a millisecond before it: the song before', songAt(songs, b.start - 1e-3), a)
  check('ten microseconds before it: the song before', songAt(songs, b.start - 1e-5), a)
  check('just before the run ends: the last song', songAt(songs, c.end - 1e-4), c)
  check('at the run\'s end: none (the next song isn\'t placed)', songAt(songs, c.end), null)
  check('past it: none', songAt(songs, c.end + 3), null)
  check('before 0: none', songAt(songs, -0.5), null)
  check('no songs placed: none', songAt([], 0), null)
}

/* ========================================================================== */
console.log('\nfragments, and where they sit')

{
  const songs = run([song(3.5), head([[44100, 100], [22050, 100], [44100, 100], [10000, 100]])])
  const s = songs[1]
  check('0 s into the song: the first fragment', fragmentAt(s, 0), 0)
  check('exactly at the second fragment\'s start', fragmentAt(s, 1), 1)
  check('a nanosecond short of it: already the second', fragmentAt(s, 1 - 1e-9), 1)
  check('a millisecond short: still the first', fragmentAt(s, 0.999), 0)
  check('inside the third', fragmentAt(s, 1.7), 2)
  check('inside the last', fragmentAt(s, 2.6), 3)
  check('before the song: the first', fragmentAt(s, -2), 0)
  check('past the song: the last', fragmentAt(s, 99), 3)

  check('a fragment\'s span on the stream: after the song before it', fragmentSpan(s, 0), [s.start, (s.startUnits + 44100) / 44100])
  check('the third\'s span', fragmentSpan(s, 2), [(s.startUnits + 66150) / 44100, (s.startUnits + 110250) / 44100])
  check('spans follow one another exactly', [0, 1, 2].every((k) => fragmentSpan(s, k)[1] === fragmentSpan(s, k + 1)[0]), true)
  check('the first starts where the song does, the last ends where it does', [fragmentSpan(s, 0)[0], fragmentSpan(s, 3)[1]], [s.start, s.end])
}

/* ========================================================================== */
console.log('\nwhat is buffered')

{
  const timeRanges = (pairs) => ({ length: pairs.length, start: (i) => pairs[i][0], end: (i) => pairs[i][1] })
  check('TimeRanges as pairs', rangesOf(timeRanges([[0, 4.5], [9, 12]])), [[0, 4.5], [9, 12]])
  check('nothing buffered', rangesOf(timeRanges([])), [])

  const buffered = [[0, 10], [20, 30]]
  check('inside one range', covered(buffered, 2, 8), true)
  check('exactly its edges', covered(buffered, 0, 10), true)
  //? a range's reported edge is rounded: WebKit to the frame timescale, Chromium to the microsecond
  check('a range reported 10 ms short at the end still holds a fragment', covered(buffered, 5, 10.01), true)
  check('...or 10 ms late at the start', covered([[5.01, 10]], 5, 8), true)
  check('30 ms short: not held', covered(buffered, 5, 10.03), false)
  check('across a gap: not held', covered(buffered, 8, 22), false)
  check('in the gap: not held', covered(buffered, 12, 14), false)
  check('nothing buffered: not held', covered([], 0, 1), false)
  check('a tolerance of 0: exact', covered(buffered, 5, 10.001, 0), false)

  check('10 s buffered, the playhead at 4: 6 ahead', aheadSeconds(buffered, 4), 6)
  check('at a range\'s end: none ahead', aheadSeconds(buffered, 10), 0)
  check('in a gap: none', aheadSeconds(buffered, 15), 0)
  check('nothing buffered: none', aheadSeconds([], 0), 0)
  //? two ranges that touch at a join (rounding can leave a sliver) are one run ahead
  check('ranges touching within 0.1 s are one run', us(aheadSeconds([[0, 10], [10.05, 20]], 4)), 16)
  check('...a 0.2 s gap is not', aheadSeconds([[0, 10], [10.2, 20]], 4), 6)
  check('...chains of them too', us(aheadSeconds([[0, 5], [5.02, 9], [9.08, 14]], 1)), 13)
  check('the playhead a hair before a range: counts from the playhead', us(aheadSeconds([[20, 30]], 19.95)), 10.05)
  check('...a hair past a range\'s end with the next touching it: the run after', us(aheadSeconds([[0, 10], [10.06, 20]], 10.04)), 9.96)
  check('ranges out of order are read in order', us(aheadSeconds([[10.05, 20], [0, 10]], 4)), 16)
  check('a tolerance given', us(aheadSeconds([[0, 10], [10.3, 20]], 4, 0.5)), 16)
}

/* ========================================================================== */
console.log('\nwhat to fetch next')

{
  //? three 8-second songs in 1 s fragments of 200 kB
  const songs = run([song(8), song(8), song(7.5)])
  const [a, b, c] = songs
  const want = (buffered, t, limits) => {
    const w = nextWant(songs, buffered, t, limits)
    return w && { song: w.song.index, from: w.from, to: w.to, start: w.start, end: w.end }
  }
  const bytesOf = (s, from, to) => ({ start: s.head.fragments[from].start, end: s.head.fragments[to - 1].end })

  check('nothing buffered: the first five seconds of the first song', want([], 0), { song: 0, from: 0, to: 5, ...bytesOf(a, 0, 5) })
  check('the first 3 s buffered: from the fourth fragment', want([[0, 3]], 1), { song: 0, from: 3, to: 8, ...bytesOf(a, 3, 8) })
  check('a piece never runs into the next song, whatever the limits allow', want([[0, 6]], 1).to, 8)
  //? the browser evicted the middle: a hole the playhead will reach, and bookkeeping wouldn't know
  check('an eviction hole ahead: fetched, stopping where data resumes', want([[0, 3], [5, 8]], 1), { song: 0, from: 3, to: 5, ...bytesOf(a, 3, 5) })
  check('a seek back into buffered data: the first gap after it', want([[0, 12]], 2), { song: 1, from: 4, to: 8, ...bytesOf(b, 4, 8) })
  check('the song fully buffered from the playhead on: on into the next', want([[0, 8]], 7.5), { song: 1, from: 0, to: 5, ...bytesOf(b, 0, 5) })
  check('...and past a whole buffered song to the one after', want([[0, 16.02]], 3), { song: 2, from: 0, to: 5, ...bytesOf(c, 0, 5) })
  check('at the last fragment of the run, not buffered: that one alone', want([[0, 23]], 23.2), { song: 2, from: 7, to: 8, ...bytesOf(c, 7, 8) })
  check('everything from the playhead on buffered: nothing', want([[0, c.end]], 10), null)
  check('...buffered from the playhead only (the rest evicted behind): nothing', want([[9.5, c.end]], 10), null)
  check('the playhead past the run: nothing - the next song\'s head comes first', want([], c.end + 1), null)
  check('the playhead before the run: nothing', want([], -1), null)
  check('no songs placed: nothing', nextWant([], [], 0), null)
  //? the fragment the playhead is in, evicted up to just behind the playhead: not fetched again
  check('the playhead\'s fragment evicted only behind the playhead: the next gap instead', want([[4.6, 6]], 4.7).from, 6)
  check('the playhead\'s fragment missing ahead of the playhead: fetched', want([[5.5, 8]], 5.2), { song: 0, from: 5, to: 6, ...bytesOf(a, 5, 6) })
  check('a range reported 10 ms short of a fragment\'s end holds it', want([[0, 2.99]], 0).from, 3)

  check('a seconds limit of 2: two fragments', want([], 0, { maxBytes: PIECE_MAX_BYTES, maxSeconds: 2 }).to, 2)
  check('a seconds limit under one fragment: still one', want([], 0, { maxBytes: PIECE_MAX_BYTES, maxSeconds: 0.5 }).to, 1)
  check('a byte limit of 450 kB: two 200 kB fragments', want([], 0, { maxBytes: 450_000, maxSeconds: 60 }).to, 2)
  check('a byte limit of exactly two fragments: two', want([], 0, { maxBytes: 400_000, maxSeconds: 60 }).to, 2)
  check('a byte limit under one fragment: still one', want([], 0, { maxBytes: 1000, maxSeconds: 60 }).to, 1)
}
{
  //? the default limits: 1 MiB and 5 s - a 24-bit song's fragments are fatter, and bytes stop it first
  const fat = run([song(10, 400_000)])
  check('400 kB fragments under the default limits: two (1 MiB)', nextWant(fat, [], 0).to, 2)
  const huge = run([song(10, 3_000_000)])
  check('a fragment bigger than a whole piece: that fragment alone', nextWant(huge, [], 0).to, 1)
  const thin = run([song(10, 50_000)])
  check('50 kB fragments: five (5 s)', nextWant(thin, [], 0).to, 5)
}

/* ========================================================================== */
console.log('\nhow much is held ahead, in bytes')

{
  const songs = run([song(4), song(4)])
  check('3 s buffered from 0: three 200 kB fragments', aheadBytes(songs, [[0, 3]], 0), 600_000)
  check('from 1.5 s: the fragment it is in (whole) and the next', aheadBytes(songs, [[0, 3]], 1.5), 400_000)
  check('a fragment ending at the playhead doesn\'t count', aheadBytes(songs, [[0, 3]], 2), 200_000)
  check('across a join, ranges touching: both songs\' fragments', aheadBytes(songs, [[0, 4], [4.01, 6]], 3), 3 * 200_000)
  check('a run ending half-way through a fragment counts it whole (the budget errs short)', aheadBytes(songs, [[0, 2.5]], 0), 600_000)
  check('nothing around the playhead: nothing', aheadBytes(songs, [[5, 7]], 1), 0)
  check('nothing buffered: nothing', aheadBytes(songs, [], 0), 0)
  check('a run past the placed songs counts only what is placed', aheadBytes(songs, [[0, 20]], 6.5), 2 * 200_000)
}

/* ========================================================================== */
console.log('\nwhen to fill')

{
  const fill = (ahead, filling, bytes = 0, max = MANAGED_AHEAD_BYTES) => shouldFill({ ahead, aheadBytes: bytes, maxBytes: max, filling })
  check('not filling, 12 s ahead: wait', fill(12, false), false)
  check('not filling, 9 s ahead: start', fill(9, false), true)
  check(`not filling, exactly ${REFILL_BELOW_S} s: wait`, fill(REFILL_BELOW_S, false), false)
  check('filling, 20 s ahead: go on', fill(20, true), true)
  check('filling, 29.9 s: go on', fill(29.9, true), true)
  check(`filling, ${FILL_TO_S} s: stop`, fill(FILL_TO_S, true), false)
  check('filling, at the byte budget: stop, whatever the seconds', fill(5, true, MANAGED_AHEAD_BYTES), false)
  //? starting past the budget would fetch a piece, stop, start again: a piece at a time through the cap
  check('not filling, under 10 s but at the budget: don\'t start', fill(5, false, MANAGED_AHEAD_BYTES), false)
  check('just under the budget: fill', fill(5, false, MANAGED_AHEAD_BYTES - 1), true)
  check('plain MediaSource\'s larger budget', fill(20, true, 5 << 20, PLAIN_AHEAD_BYTES), true)

  //? a walk: playing at 1 s a second, each piece bringing 5 s, starting from nothing
  let ahead = 0, filling = false
  const trace = []
  for (let second = 0; second < 40; second++) {
    filling = fill(ahead, filling)
    if (filling) ahead += 5
    trace.push(filling ? 'F' : '.')
    ahead = Math.max(0, ahead - 1)
  }
  //? 0 -> past 30 s in eight pieces, quiet for 23 s until under 10 remain, then six pieces back past 30
  check('a walk: bursts of fetching, then quiet until 10 s ahead remain', trace.join(''), 'FFFFFFFF.......................FFFFFF...')
}

check('after a QuotaExceededError the budget drops a quarter', lowerBudget(3 << 20, 1 << 20), Math.floor((3 << 20) * 0.75))
check('...and again', lowerBudget(lowerBudget(3 << 20, 1 << 20), 1 << 20), Math.floor(Math.floor((3 << 20) * 0.75) * 0.75))
{
  let budget = MANAGED_AHEAD_BYTES
  for (let i = 0; i < 20; i++) budget = lowerBudget(budget, 1 << 20)
  check('...never below one piece, however often', budget, 1 << 20)
}
check('a piece bigger than three quarters: the piece', lowerBudget(1_000_000, 900_000), 900_000)

/* ========================================================================== */
console.log('\nwhat an answer means')

{
  const ask = (fields) => classifyAnswer({
    status: 206, contentType: 'audio/mp4', contentRange: 'bytes 0-262143/9000000', retryAfter: null, scope: null,
    askedStart: 0, askedEnd: 262143, ifRange: false, ...fields,
  })
  const kind = (fields) => ask(fields).kind
  check('206, audio/mp4, the range asked: ok', ask({}), { kind: 'ok' })
  check('...with parameters on the type, in capitals', kind({ contentType: 'Audio/MP4; foo=bar' }), 'ok')
  //? a song smaller than the head fetch: the answer stops at the file's last byte
  check('the ask ran past a small file: ok, ending at its last byte', kind({ contentRange: 'bytes 0-99999/100000' }), 'ok')
  check('a piece asked with If-Range, answered 206: ok', kind({ contentRange: 'bytes 5000-9999/9000000', askedStart: 5000, askedEnd: 9999, ifRange: true }), 'ok')
  check('a total of * still ok when the range is exact', kind({ contentRange: 'bytes 0-262143/*' }), 'ok')
  check('an open-ended ask answered to the file\'s end: ok', kind({ contentRange: 'bytes 1000-4999/5000', askedStart: 1000, askedEnd: null }), 'ok')
  check('...answered short of it: fatal', kind({ contentRange: 'bytes 1000-2000/5000', askedStart: 1000, askedEnd: null }), 'fatal')
  check('another start than asked: fatal', ask({ contentRange: 'bytes 1-262143/9000000' }), { kind: 'fatal', why: 'bytes from 1 came back, not from 0' })
  check('short of the end asked, not at the file\'s end: fatal', ask({ contentRange: 'bytes 0-1000/9000000' }), { kind: 'fatal', why: 'bytes to 1000 came back, not to 262143' })
  check('past the end asked: fatal', kind({ contentRange: 'bytes 0-300000/9000000' }), 'fatal')
  check('an unreadable Content-Range: fatal', kind({ contentRange: 'bytes=0-262143' }), 'fatal')
  check('no Content-Range: fatal', ask({ contentRange: null }), { kind: 'fatal', why: "the answer's Content-Range (none) can't be read" })
  check('an impossible range (end before start): fatal', kind({ contentRange: 'bytes 10-5/100', askedStart: 10, askedEnd: 5 }), 'fatal')
  check('an impossible range (past the file): fatal', kind({ contentRange: 'bytes 0-100/100', askedEnd: 100 }), 'fatal')
  check('a partial answer to a whole-file ask: fatal', kind({ askedStart: null, askedEnd: null }), 'fatal')
  check('the FLAC as it is instead of an MP4: fatal', ask({ contentType: 'audio/flac' }), { kind: 'fatal', why: 'the answer is audio/flac, not audio/mp4' })
  check('an HTML page: fatal', kind({ contentType: 'text/html' }), 'fatal')
  check('no type: fatal', kind({ contentType: null }), 'fatal')

  check('200 to a whole-file ask: ok', kind({ status: 200, contentRange: null, askedStart: null, askedEnd: null }), 'ok')
  check('200 the FLAC to a whole-file ask: fatal', kind({ status: 200, contentType: 'audio/flac', contentRange: null, askedStart: null, askedEnd: null }), 'fatal')
  check('200 to a ranged ask (the server ignored the range): fatal', ask({ status: 200, contentRange: null }), { kind: 'fatal', why: 'the whole file came back when a range was asked for' })
  //? If-Range failed: the file isn't the one the head came from - appending it would splice two songs
  check('200 to an If-Range ask: changed', ask({ status: 200, ifRange: true }), { kind: 'changed' })
  check('416 to an If-Range ask: changed', ask({ status: 416, ifRange: true }), { kind: 'changed' })
  check('416 otherwise: fatal', ask({ status: 416 }), { kind: 'fatal', why: 'the range asked for is past the end of the file' })

  check('415: refused (this song can\'t be repackaged)', ask({ status: 415 }), { kind: 'refused' })
  check('404: refused', kind({ status: 404 }), 'refused')
  check('410: refused', kind({ status: 410 }), 'refused')
  check('415 to an If-Range ask: still refused', kind({ status: 415, ifRange: true }), 'refused')

  check('503 for the whole server: the engine goes off', ask({ status: 503, scope: 'server', retryAfter: '30' }), { kind: 'engine-off' })
  check('503 for this song, Retry-After 2: retry in 2 s', ask({ status: 503, scope: 'song', retryAfter: '2' }), { kind: 'retry', afterMs: 2000 })
  check('503 with no scope and no Retry-After: retry, no wait given', ask({ status: 503 }), { kind: 'retry', afterMs: null })
  check('429 asking for 2 minutes: capped', ask({ status: 429, retryAfter: '120' }), { kind: 'retry', afterMs: RETRY_AFTER_MAX_MS })
  check('a Retry-After with spaces', ask({ status: 503, retryAfter: ' 5 ' }), { kind: 'retry', afterMs: 5000 })
  check('a Retry-After as a date: no wait given', ask({ status: 503, retryAfter: 'Wed, 21 Oct 2026 07:28:00 GMT' }), { kind: 'retry', afterMs: null })
  check('a Retry-After of nonsense: no wait given', ask({ status: 503, retryAfter: '-3' }), { kind: 'retry', afterMs: null })
  for (const status of [500, 502, 504]) check(`${status}: retry`, kind({ status }), 'retry')
  check('a network error, a timeout (status 0): retry', ask({ status: 0, contentType: null, contentRange: null }), { kind: 'retry', afterMs: null })
  for (const status of [400, 401, 403, 301, 302, 204, 501]) check(`${status}: fatal`, ask({ status }), { kind: 'fatal', why: `an unexpected answer (${status})` })
}

/* ========================================================================== */
console.log('\nwaiting before asking again')

check('the delays', RETRY_DELAYS_MS, [500, 1000, 2000, 4000])
check('attempt by attempt', [0, 1, 2, 3].map((n) => retryDelay(n, null)), [500, 1000, 2000, 4000])
check('then none: give up', retryDelay(4, null), null)
check('an attempt below 0: none', retryDelay(-1, null), null)
check('a Retry-After is honoured', retryDelay(0, 2000), 2000)
check('...capped', retryDelay(1, 90_000), RETRY_AFTER_MAX_MS)
check('...of 0: at once', retryDelay(2, 0), 0)
check('...but not past the last attempt', retryDelay(4, 2000), null)

/* ========================================================================== */
console.log('\nwhich songs may go into a stream')

{
  const yes = { gapless: true, engine: true, isFlac: true, raw: true, wireless: false, refused: false, engineOff: false }
  check('the switch on, an engine, a FLAC as it is, no AirPlay, never refused, the engine on', streamable(yes), true)
  const noes = { gapless: false, engine: false, isFlac: false, raw: false, wireless: true, refused: true, engineOff: true }
  for (const key of Object.keys(noes)) check(`...except ${key} ${noes[key]}`, streamable({ ...yes, [key]: noes[key] }), false)
}

/* ========================================================================== */
console.log('\nlistening across a join')

{
  const split = (fields) => {
    const r = splitAcrossJoin({ previous: 198.7, oldLength: 200, now: 0.3, elapsed: 1.6, rate: 1, seeked: false, ...fields })
    return { before: us(r.before), after: us(r.after) }
  }
  check('the rest of the old song and the start of the new', split({}), { before: 1.3, after: 0.3 })
  check('across a seek: nothing to either', split({ seeked: true }), { before: 0, after: 0 })
  //? an update that missed a long stretch can't count more than the wall clock allows
  check('more than the clock allows: the old song\'s rest first, the new song gets what is left', split({ previous: 199, now: 2, elapsed: 1 }), { before: 1, after: 0.5 })
  check('...the old song\'s rest alone over the cap: capped, nothing to the new', split({ previous: 190, now: 5, elapsed: 1 }), { before: 1.5, after: 0 })
  check('the cap is the wall clock times the rate, plus the slack', split({ previous: 199, now: 3, elapsed: 1, rate: 2 }), { before: 1, after: 1 + LISTEN_SLACK_SECONDS })
  check('a rate of 0 counts as 1', split({ previous: 199, now: 2, elapsed: 1, rate: 0 }), { before: 1, after: 0.5 })
  check('a clock that went backwards: only the slack', split({ previous: 199, now: 2, elapsed: -3 }), { before: 0.5, after: 0 })
  check('the old song\'s position already at its end: nothing more of it', split({ previous: 200.2, now: 0.4, elapsed: 0.5 }), { before: 0, after: 0.4 })
  check('a new position below 0: nothing of the new', split({ now: -0.1 }), { before: 1.3, after: 0 })
}

check('the stall at a join that played through: 0', joinStallMs({ elapsedMs: 250, media: 0.25, rate: 1 }), 0)
check('a second of silence at the join', joinStallMs({ elapsedMs: 1250, media: 0.25, rate: 1 }), 1000)
check('at twice the speed', joinStallMs({ elapsedMs: 250, media: 0.5, rate: 2 }), 0)
check('the media clock ahead of the wall (read a moment apart): 0, not negative', joinStallMs({ elapsedMs: 240, media: 0.25, rate: 1 }), 0)
check('whole milliseconds', joinStallMs({ elapsedMs: 250.6, media: 0.25, rate: 1 }), 1)
check('a rate of 0 counts as 1', joinStallMs({ elapsedMs: 500, media: 0.25, rate: 0 }), 250)

/* ========================================================================== */
console.log('\nthe numbers')

check('a piece: 1 MiB, 5 s', [PIECE_MAX_BYTES, PIECE_MAX_SECONDS], [1 << 20, 5])
check('fill below 10 s ahead, to 30 s', [REFILL_BELOW_S, FILL_TO_S], [10, 30])
check('ahead: 3 MiB managed, 8 MiB plain', [MANAGED_AHEAD_BYTES, PLAIN_AHEAD_BYTES], [3 << 20, 8 << 20])
//? iOS caps an audio SourceBuffer near 5.26 MiB, behind the playhead included: the budget leaves room
check('the managed budget and a piece stay under iOS\'s 5.26 MiB cap', MANAGED_AHEAD_BYTES + PIECE_MAX_BYTES < 5.26 * (1 << 20), true)
check('timers: a 90 s header wait, an 8 s stalled body, 5 s to open, 15 s stuck, 10 min off',
  [HEADER_TIMEOUT_MS, BODY_STALL_MS, SOURCEOPEN_TIMEOUT_MS, STUCK_MS, ENGINE_OFF_MS], [90_000, 8_000, 5_000, 15_000, 600_000])
check('Retry-After honoured up to 30 s', RETRY_AFTER_MAX_MS, 30_000)

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
