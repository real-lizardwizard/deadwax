/**
 * The one-stream engine's decisions: where each song of a run sits on the stream's timeline, which
 * bytes to fetch and append next, when to stop, what an answer from deadwax means, and how the
 * listening and the gap are counted at a join.
 *
 * With the Gapless switch on, consecutive FLAC songs play as ONE MediaSource stream on one audio
 * element (player/streamSource.ts is the part that touches MediaSource and fetch). deadwax sends each
 * song as fragmented MP4 (`wrap=fmp4`); lib/fmp4.ts reads its head. Each song is placed after the
 * one before it by setting timestampOffset to the run's earlier songs' total samples over the rate -
 * which is exact, because a run holds one timescale - and its init segment is appended just before
 * its media. That is the recipe that played seamlessly on an iPhone, locked, in the lab.
 *
 * The feeder is STATELESS about what is buffered: every decision is read from the SourceBuffer's
 * `buffered` ranges at the moment it is made. The browser evicts what it likes (ManagedMediaSource
 * on iOS does it by itself; any engine does it on a QuotaExceededError), and a seek can land
 * anywhere, so bookkeeping of "what was appended" goes stale in ways that are hard to see and end as
 * a hole the playhead stops at. `buffered` is always the truth.
 *
 * Why the numbers are what they are (see "One stream" in CLAUDE.md and the design notes):
 * - iOS caps an audio SourceBuffer at about 5.26 MiB - some 45 s of CD FLAC - and Chromium at 12 MiB.
 *   So a piece is at most 1 MiB, what is held ahead is budgeted in BYTES as well as seconds, and a
 *   whole song is never appended at once.
 * - Safari doesn't reliably say when it wants more (startstreaming doesn't fire after a seek), so
 *   the page keeps its own watermarks on both engines: refill below 10 s ahead, fill to 30 s.
 *
 * Pure, like the rest of lib/, so ui/test/stream.sim.cjs can hold it to the answers.
 */

import { sameFormat, type FlacFormat, type Fmp4Head } from './fmp4'
import { LISTEN_SLACK_SECONDS } from './playQueue'

/** The most one fetch and one appendBuffer carries, in bytes and in seconds of audio. */
export const PIECE_MAX_BYTES = 1 << 20
export const PIECE_MAX_SECONDS = 5

/** Filling starts when less than this much is ahead of the playhead, in seconds... */
export const REFILL_BELOW_S = 10
/** ...and goes on until this much is, or the byte budget is reached. */
export const FILL_TO_S = 30

/**
 * The most held ahead of the playhead, in bytes. ManagedMediaSource (iOS, Mac Safari) caps the
 * buffer near 5.26 MiB on a phone, behind the playhead included, so 3 MiB leaves it room; plain
 * MediaSource (Chromium, Firefox) allows 12 MiB for audio, 2 MiB on a low-end device - which a
 * QuotaExceededError lowers this to (lowerBudget).
 */
export const MANAGED_AHEAD_BYTES = 3 << 20
export const PLAIN_AHEAD_BYTES = 8 << 20

/** How long to wait before asking again after a transient failure, attempt by attempt. */
export const RETRY_DELAYS_MS = [500, 1000, 2000, 4000]
/** The longest a Retry-After is honoured for: a longer one waits this long and asks again. */
export const RETRY_AFTER_MAX_MS = 30_000

/**
 * How long an answer's HEADERS may take. Long, because the first request for a song deadwax
 * hasn't repackaged yet waits while it downloads the whole file from Navidrome and makes it.
 */
export const HEADER_TIMEOUT_MS = 90_000
/** A body that sends no bytes for this long has stalled: abort it and ask again. */
export const BODY_STALL_MS = 8_000
/** A MediaSource that hasn't opened this long after attaching never will: go the URL way. */
export const SOURCEOPEN_TIMEOUT_MS = 5_000
/** Meant to be playing, the playhead not moving, and nothing in flight or scheduled: stuck. */
export const STUCK_MS = 15_000
/** How long the stream engine stays off after deadwax says its cache can't be used at all. */
export const ENGINE_OFF_MS = 10 * 60_000

/**
 * Whether a song of this format may be streamed at all: what the phone lab proved or what is close
 * to it. Above 48 kHz the sample entry holds a clamped rate (its 16.16 field can't hold 96 kHz) that
 * no engine has been seen to play; more than two channels, or depths other than 16 and 24 bits, are
 * untested. Such a song plays the URL way - the stream ends before it.
 */
export function formatStreamable(f: FlacFormat): boolean {
  return f.sampleRate > 0 && f.sampleRate <= 48000 && f.channels >= 1 && f.channels <= 2 &&
    (f.bitsPerSample === 16 || f.bitsPerSample === 24)
}

/** A song placed in the run: where it sits on the stream's timeline. */
export interface RunSong {
  /** its position in the queue, and its id there */
  index: number
  id: string
  head: Fmp4Head
  /** time units of the run before it - its timestampOffset, times the timescale */
  startUnits: number
  /** where it starts and ends on the stream's timeline, and how long it is, in seconds */
  start: number
  end: number
  length: number
}

/**
 * Whether a song with this head can join the run after `prev` (null: it would start the run). A run
 * holds ONE format and one timescale: a song that changes either ends the run before it, and plays
 * the URL way. (AVFoundation's handling of a format change mid-stream is untested closed source.)
 */
export function joins(prev: RunSong | null, head: Fmp4Head): boolean {
  if (!formatStreamable(head.format)) return false
  if (!prev) return true
  return prev.head.timescale === head.timescale && sameFormat(prev.head.format, head.format)
}

/**
 * The song placed after `prev` (null: the run's first). Counted in the run's time units, not in
 * seconds: `start` is startUnits over the timescale, and `end` is (startUnits + units) over it - not
 * start + length - so a song's end and the next one's start are the same number, exactly, however
 * many songs come before. Summing seconds would drift by a rounding error per song, and at a join
 * that is enough to say the playhead is in the wrong song.
 */
export function placeSong(prev: RunSong | null, index: number, id: string, head: Fmp4Head): RunSong {
  const startUnits = prev ? prev.startUnits + prev.head.units : 0
  const scale = head.timescale
  return {
    index,
    id,
    head,
    startUnits,
    start: startUnits / scale,
    end: (startUnits + head.units) / scale,
    length: head.units / scale,
  }
}

/** Times this close BEFORE a song's start count as inside it: a float a hair short of a join. */
const AT_START = 1e-6

/**
 * The placed song whose [start, end) holds media time `t`. A time a hair before a song's start
 * (within a microsecond) is that song's - a playhead read as 9.9999999 where the song starts at 10
 * has not gone back to the one before. Null before the run's first song and from the last placed
 * song's end on.
 */
export function songAt(songs: readonly RunSong[], t: number): RunSong | null {
  let found: RunSong | null = null
  for (const song of songs) {
    if (song.start - AT_START <= t) found = song
    else break
  }
  return found && t < found.end ? found : null
}

/** Which of a song's fragments holds `seconds` into the song - the first or the last beyond it. */
export function fragmentAt(song: RunSong, seconds: number): number {
  const units = (seconds + AT_START) * song.head.timescale
  const fragments = song.head.fragments
  let k = 0
  while (k + 1 < fragments.length && fragments[k + 1]!.t0 <= units) k++
  return k
}

/** A fragment's place on the stream's timeline, in seconds: [start, end). */
export function fragmentSpan(song: RunSong, k: number): [number, number] {
  const fragment = song.head.fragments[k]!
  const scale = song.head.timescale
  const at = song.startUnits + fragment.t0
  return [at / scale, (at + fragment.units) / scale]
}

/** Buffered time ranges as plain pairs. */
export type Ranges = ReadonlyArray<readonly [number, number]>

/** A TimeRanges (`sourceBuffer.buffered`, `audio.buffered`) as pairs, in order. */
export function rangesOf(buffered: { length: number; start(i: number): number; end(i: number): number }): Array<[number, number]> {
  const ranges: Array<[number, number]> = []
  for (let i = 0; i < buffered.length; i++) ranges.push([buffered.start(i), buffered.end(i)])
  return ranges
}

/**
 * How far a buffered range's reported edge may be from a fragment's own and still hold it. WebKit
 * rounds times to the frame timescale and Chromium to the microsecond, so an appended fragment's
 * range edges are seldom its exact span. 20 ms is far under one FLAC frame (93 ms at 44.1 kHz).
 */
const EDGE_TOLERANCE_S = 0.02

/** Whether [a, b] lies inside one buffered range, give or take `tol` at each end. */
export function covered(buffered: Ranges, a: number, b: number, tol = EDGE_TOLERANCE_S): boolean {
  return buffered.some(([start, end]) => start <= a + tol && end >= b - tol)
}

/** The ranges in order, those touching (within `tol`) merged into one. */
function merged(buffered: Ranges, tol: number): Array<[number, number]> {
  const runs: Array<[number, number]> = []
  for (const [start, end] of [...buffered].sort((x, y) => x[0] - y[0])) {
    const last = runs[runs.length - 1]
    if (last && start <= last[1] + tol) last[1] = Math.max(last[1], end)
    else runs.push([start, end])
  }
  return runs
}

/** The buffered run holding `t` (within `tol`), ranges touching within `tol` merged: its end, or null. */
function runEndAt(buffered: Ranges, t: number, tol: number): number | null {
  const run = merged(buffered, tol).find(([start, end]) => start <= t + tol && t <= end + tol)
  return run ? run[1] : null
}

/**
 * How many seconds are buffered ahead of `t` without a break: the run of ranges starting at or
 * around it, ranges that touch within `tol` counted as one (a join's rounding can leave a sliver).
 */
export function aheadSeconds(buffered: Ranges, t: number, tol = 0.1): number {
  const end = runEndAt(buffered, t, tol)
  return end === null ? 0 : Math.max(0, end - t)
}

/** A piece to fetch and append: fragments [from, to) of one song, the file's bytes [start, end). */
export interface Want {
  song: RunSong
  from: number
  to: number
  start: number
  end: number
}

/**
 * Whether fragment `k` of `song` is still needed with the playhead at `t`: what of it lies ahead of
 * the playhead isn't buffered. Only the part AHEAD counts - the browser evicts behind the playhead
 * frame by frame, and a fragment half gone behind it but whole in front is not fetched again.
 */
function wanted(song: RunSong, k: number, buffered: Ranges, t: number): boolean {
  const [start, end] = fragmentSpan(song, k)
  return !covered(buffered, Math.max(start, t), end)
}

/**
 * The next piece to fetch, with the playhead at `t`: the first fragment at or after it that isn't
 * buffered - in the song holding `t`, then in the placed songs after it - grown over the following
 * fragments of the SAME song that aren't buffered either, as far as the limits allow (one fragment
 * always, whatever its size). One piece never spans two songs, because each song's init segment has
 * to go in just before its media. Null when everything placed from `t` on is buffered, or `t` is in
 * no placed song - past the last one, where the next song's head has to come first.
 */
export function nextWant(
  songs: readonly RunSong[], buffered: Ranges, t: number,
  limits: { maxBytes: number; maxSeconds: number } = { maxBytes: PIECE_MAX_BYTES, maxSeconds: PIECE_MAX_SECONDS },
): Want | null {
  const first = songAt(songs, t)
  if (!first) return null
  for (let s = songs.indexOf(first); s < songs.length; s++) {
    const song = songs[s]!
    const fragments = song.head.fragments
    const scale = song.head.timescale
    for (let k = song === first ? fragmentAt(song, t - song.start) : 0; k < fragments.length; k++) {
      if (!wanted(song, k, buffered, t)) continue
      let to = k + 1
      let bytes = fragments[k]!.end - fragments[k]!.start
      let units = fragments[k]!.units
      while (to < fragments.length && wanted(song, to, buffered, t)) {
        const next = fragments[to]!
        if (bytes + (next.end - next.start) > limits.maxBytes) break
        if ((units + next.units) / scale > limits.maxSeconds) break
        bytes += next.end - next.start
        units += next.units
        to++
      }
      return { song, from: k, to, start: fragments[k]!.start, end: fragments[to - 1]!.end }
    }
  }
  return null
}

/**
 * About how many bytes of the run are buffered ahead of `t`: the sizes of the fragments whose spans
 * fall in the buffered run from `t`. What the byte budget is held to - the SourceBuffer's cap is in
 * bytes, and seconds of 24-bit audio are twice the bytes of 16-bit ones. The fragment the playhead is
 * in counts whole; it is all in the buffer.
 */
export function aheadBytes(songs: readonly RunSong[], buffered: Ranges, t: number): number {
  const runEnd = runEndAt(buffered, t, 0.1)
  if (runEnd === null) return 0
  let bytes = 0
  for (const song of songs) {
    if (song.end <= t || song.start >= runEnd) continue
    song.head.fragments.forEach((fragment, k) => {
      const [start, end] = fragmentSpan(song, k)
      if (end > t + EDGE_TOLERANCE_S && start < runEnd - EDGE_TOLERANCE_S) bytes += fragment.end - fragment.start
    })
  }
  return bytes
}

/**
 * Whether to go on fetching, with hysteresis: start when less than REFILL_BELOW_S is ahead, and
 * once started go on until FILL_TO_S is, so the network is used in bursts rather than a piece every
 * few seconds. The byte budget is a hard stop either way - starting past it would fetch a piece,
 * stop, and start again at once, a piece at a time, straight through the cap.
 */
export function shouldFill(q: { ahead: number; aheadBytes: number; maxBytes: number; filling: boolean }): boolean {
  if (q.aheadBytes >= q.maxBytes) return false
  return q.ahead < (q.filling ? FILL_TO_S : REFILL_BELOW_S)
}

/** The byte budget after a QuotaExceededError: a quarter less, never below one piece. */
export function lowerBudget(maxBytes: number, pieceBytes: number): number {
  return Math.max(pieceBytes, Math.floor(maxBytes * 0.75))
}

/**
 * What an answer from deadwax means for the stream.
 * - ok: append it.
 * - refused: deadwax won't repackage this song, ever, as it is - never stream it on this page.
 * - retry: transient; ask again after `afterMs` (Retry-After) or the next of RETRY_DELAYS_MS.
 * - engine-off: deadwax's cache can't be used at all - stop streaming for ENGINE_OFF_MS.
 * - changed: the file isn't the one the head came from (If-Range failed) - leave the stream for it.
 * - fatal: not an answer the stream can use.
 */
export type Answer =
  | { kind: 'ok' }
  | { kind: 'refused' }
  | { kind: 'retry'; afterMs: number | null }
  | { kind: 'engine-off' }
  | { kind: 'changed' }
  | { kind: 'fatal'; why: string }

export interface AnswerQuestion {
  /** the HTTP status; 0 for a network error, a timeout or an abort before any answer */
  status: number
  contentType: string | null
  contentRange: string | null
  retryAfter: string | null
  /** the JSON body's "scope" on a 503: 'song' or 'server' */
  scope: string | null
  /** the Range asked for, first and LAST byte - inclusive, as in the header; null: the whole file.
   *  (An open-ended "bytes=N-" asks with askedEnd null.) */
  askedStart: number | null
  askedEnd: number | null
  /** whether it was asked with If-Range */
  ifRange: boolean
}

/** Retry-After in ms, when it gives seconds (a date isn't worth the clock arithmetic), capped. */
function retryAfterMs(value: string | null): number | null {
  if (value === null || !/^\s*\d+\s*$/.test(value)) return null
  return Math.min(Number(value.trim()) * 1000, RETRY_AFTER_MAX_MS)
}

function isMp4(contentType: string | null): boolean {
  return (contentType ?? '').split(';')[0]!.trim().toLowerCase() === 'audio/mp4'
}

/**
 * What an answer means. A partial answer is only ok when it is exactly the bytes asked for - its
 * Content-Range starting where asked and ending where asked, or at the file's last byte when the ask
 * ran past it (a song smaller than the head fetch). Anything else would be appended at the wrong
 * place in the song, which is worse than not streaming it. A whole-file 200 is ok only when the
 * whole file was asked for; to an If-Range ask a 200 (or a 416) says the file is no longer the one
 * the head came from.
 */
export function classifyAnswer(q: AnswerQuestion): Answer {
  const { status } = q
  if (status === 0) return { kind: 'retry', afterMs: null }
  if (q.ifRange && (status === 200 || status === 416)) return { kind: 'changed' }
  if (status === 415 || status === 404 || status === 410) return { kind: 'refused' }
  if (status === 503 && q.scope === 'server') return { kind: 'engine-off' }
  if ([429, 500, 502, 503, 504].includes(status)) return { kind: 'retry', afterMs: retryAfterMs(q.retryAfter) }

  if (status === 200 || status === 206) {
    if (!isMp4(q.contentType)) return { kind: 'fatal', why: `the answer is ${q.contentType ?? 'untyped'}, not audio/mp4` }
    if (status === 200) {
      return q.askedStart === null ? { kind: 'ok' } : { kind: 'fatal', why: 'the whole file came back when a range was asked for' }
    }
    if (q.askedStart === null) return { kind: 'fatal', why: 'part of the file came back when the whole was asked for' }
    const range = /^\s*bytes\s+(\d+)-(\d+)\/(\d+|\*)\s*$/i.exec(q.contentRange ?? '')
    if (!range) return { kind: 'fatal', why: `the answer's Content-Range (${q.contentRange ?? 'none'}) can't be read` }
    const first = Number(range[1])
    const last = Number(range[2])
    const size = range[3] === '*' ? null : Number(range[3])
    if (last < first || (size !== null && last >= size)) {
      return { kind: 'fatal', why: `the answer's Content-Range (${q.contentRange}) is impossible` }
    }
    if (first !== q.askedStart) return { kind: 'fatal', why: `bytes from ${first} came back, not from ${q.askedStart}` }
    //? the ask may run past the file's end - the head fetch of a small song - and then ends at its last byte
    const endsAtFile = size !== null && last === size - 1
    const fits = q.askedEnd === null ? endsAtFile || size === null : last === q.askedEnd || (endsAtFile && last < q.askedEnd)
    if (!fits) return { kind: 'fatal', why: `bytes to ${last} came back, not to ${q.askedEnd ?? 'the end'}` }
    return { kind: 'ok' }
  }
  if (status === 416) return { kind: 'fatal', why: 'the range asked for is past the end of the file' }
  return { kind: 'fatal', why: `an unexpected answer (${status})` }
}

/**
 * How long to wait before attempt `attempt` (0 for the first retry) asks again: the server's own
 * Retry-After when it gave one (capped), else the next of RETRY_DELAYS_MS. Null once they are used
 * up - the caller gives up there.
 */
export function retryDelay(attempt: number, retryAfterMs: number | null): number | null {
  if (!(attempt >= 0 && attempt < RETRY_DELAYS_MS.length)) return null
  if (retryAfterMs !== null) return Math.min(Math.max(0, retryAfterMs), RETRY_AFTER_MAX_MS)
  return RETRY_DELAYS_MS[Math.floor(attempt)] ?? null
}

export interface StreamableQuestion {
  /** the Gapless switch */
  gapless: boolean
  /** the page has a MediaSource that plays FLAC in MP4 */
  engine: boolean
  isFlac: boolean
  /** asked for as it is (format=raw), not transcoded - a transcode has no FLAC in it */
  raw: boolean
  /** the sound goes to AirPlay: a speaker is handed a URL, never a MediaSource */
  wireless: boolean
  /** deadwax refused to repackage this song on this page (415), or it failed decoding in a stream */
  refused: boolean
  /** deadwax said its cache can't be used, less than ENGINE_OFF_MS ago */
  engineOff: boolean
}

/** Whether a song may go into a stream. Every no plays it the URL way, as with the switch off. */
export function streamable(q: StreamableQuestion): boolean {
  return q.gapless && q.engine && q.isFlac && q.raw && !q.wireless && !q.refused && !q.engineOff
}

/** The listening one update across a join adds: to the song that ended, and to the one after. */
export interface JoinListen {
  before: number
  after: number
}

/**
 * How the listening between two updates is shared when a join falls between them: the rest of the
 * OLD song from where it was (`previous`, song-relative, to `oldLength`), and the NEW song up to
 * where it is now (`now`, song-relative). The same rules as listenedStep(): nothing across a seek, and
 * the two together no more than the wall clock allows at this rate, plus a little slack - taken off
 * the new song first, since the old song's rest is the part known to have played.
 */
export function splitAcrossJoin(q: { previous: number; oldLength: number; now: number; elapsed: number; rate: number; seeked: boolean }): JoinListen {
  if (q.seeked) return { before: 0, after: 0 }
  const pace = q.rate > 0 ? q.rate : 1
  const allowed = Math.max(0, q.elapsed) * pace + LISTEN_SLACK_SECONDS
  let before = Math.max(0, q.oldLength - q.previous)
  let after = Math.max(0, q.now)
  if (before + after > allowed) {
    after = Math.max(0, allowed - before)
    before = Math.min(before, allowed)
  }
  return { before, after }
}

/**
 * The stall across a join, in ms, estimated from the two updates spanning it: the wall time between
 * them less the media time the clock moved (at this rate). A join that played through reads 0.
 */
export function joinStallMs(q: { elapsedMs: number; media: number; rate: number }): number {
  const pace = q.rate > 0 ? q.rate : 1
  return Math.max(0, Math.round(q.elapsedMs - (q.media / pace) * 1000))
}
