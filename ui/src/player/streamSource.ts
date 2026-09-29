/**
 * One continuous stream of FLAC songs on one audio element: what the gapless switch plays FLAC with
 * where the browser has MediaSource and takes FLAC in an MP4 (ManagedMediaSource on an iPhone or a
 * Mac's Safari, MediaSource in Chromium and Firefox).
 *
 * Why a stream at all: two audio elements handing over from one to the next leave a gap of about
 * 100 ms on an iPhone and 250 ms on a Mac, however early the next song is ready - it is the element
 * starting that costs it. Songs appended back to back into one MediaSource play as one timeline, with
 * nothing to start. The recipe is the one a lab page proved seamless on James's iPhone, in Safari
 * and Arc, locked, fetching over the network while locked too (CLAUDE.md, "One stream for FLAC"):
 *
 *  - each song as fragmented MP4 of its own FLAC frames, made by deadwax (wrap=fmp4, src/flac_mp4.py);
 *  - each song's init segment appended immediately before that song's media - without it WebKit
 *    clicked at the join;
 *  - songs placed with timestampOffset = the run's earlier songs' samples / rate, which WebKit rounds
 *    to the sample timescale (TrackBuffer::roundTowardsTimeScaleWithRoundingMargin), so a join lands on
 *    the exact sample however long the songs are;
 *  - on ManagedMediaSource, disableRemotePlayback set BEFORE attaching, or the source never opens -
 *    no error, just silence (WebKit defers the open until AirPlay can't be asked of the element).
 *
 * What the browser does NOT do for us, each learned from its source (scratchpad reports):
 *
 *  - An iPhone holds only about 5 MiB of audio in a SourceBuffer - under a minute of CD audio - so
 *    nothing is appended whole: pieces of at most PIECE_MAX_BYTES, fed as the playhead needs them,
 *    and a QuotaExceededError is "clear what is behind, then try again" - with the piece split in
 *    two when it is itself too big for the room there is, its fragments' bytes being known - never
 *    lost, and never waiting on a playhead that is itself waiting for data.
 *  - What to append next is worked out from `buffered` every time, never from a cursor: eviction,
 *    a seek or an abort can leave holes anywhere, and a feeder that followed a cursor would stall on
 *    one for good. nextWant() in lib/streamPlan is the rule.
 *  - A seek to time not yet appended is clamped to the MediaSource's duration, which grows only as
 *    data arrives - so the duration is raised to the target song's end first. And Safari 27.0 evicts
 *    relative to where the playhead WAS until the seek lands, which can throw away the piece just
 *    appended for it - so a seek to unbuffered time first removes everything else, appends only the
 *    target's piece, and appends nothing more until 'seeked'.
 *  - endOfStream() is a state, not an event: any append, remove or timestampOffset reopens an ended
 *    source, and one left open stalls at its end instead of ending - which on a locked phone is the
 *    music stopping. So it is called again whenever the run is all in and the source is open.
 *  - abort() throws on an ended source or while a remove runs, and its 'updateend' arrives AFTER
 *    whatever the caller did next - so nothing here trusts an 'updateend' while `updating` is true.
 *
 * The player (usePlayer.ts) owns the queue, the lock screen and the listening; this owns only the
 * stream: which songs are in it and where, fetching, appending, seeking in it, and saying when it
 * can't go on - with the index of the song that couldn't, so the right song is blamed.
 */

import { HEAD_FETCH_BYTES, initBytes, parseHead, piecesInside, type Fmp4Head } from '../lib/fmp4'
import {
  BODY_STALL_MS, FILL_TO_S, HEADER_TIMEOUT_MS, MANAGED_AHEAD_BYTES, PIECE_MAX_BYTES, PIECE_MAX_SECONDS, PLAIN_AHEAD_BYTES,
  RESAMPLE_HEAD_WAIT_MS, SOURCEOPEN_TIMEOUT_MS, STREAM_MAX_RATE, STUCK_MS, aheadBytes, aheadSeconds, classifyAnswer,
  covered, formatStreamable, joins, lowerBudget, nextWant, placeSong, rangesOf, retryDelay, shouldFill, songAt,
  sourceRateOf, type Answer, type Ranges, type RunSong, type Want,
} from '../lib/streamPlan'
import type { QueueTrack } from '../lib/playQueue'
import { resampledFrom, type MaxRate, type Resampled } from '../lib/streamWrap'

/** Why the stream can't go on for a song - the player leaves the stream for it. */
export type StreamFailure =
  /** the browser couldn't decode or parse what was appended for it */
  | 'decode'
  /** its audio couldn't be fetched, after every retry, while the playhead waited on it */
  | 'transport'
  /** deadwax's copy of it changed under the stream (a 200 or 416 to an If-Range ask) */
  | 'changed'
  /** its format isn't one the stream takes (above 48 kHz, more than two channels...) - deadwax can
   *  still wrap it as an MP4 for the URL way; it just never streams */
  | 'format'
  /** deadwax won't repackage it, or its head can't be read */
  | 'refused'
  /** nothing moved for STUCK_MS while it was meant to be playing, and nothing was on its way */
  | 'stuck'
  /** the MediaSource never opened */
  | 'open'
  /** the browser gave the whole stream up over a LATER song's bytes (an append error detaches the
   *  source): this song is fine, and goes on the URL way from where it had got to */
  | 'broken'

export interface StreamEvents {
  /** nothing joins the run after `lastIndex`; known as early as the next song's head says so */
  runEnded(source: StreamSource, lastIndex: number): void
  /** the copy of the song at `index` this stream asked for never streams this page: deadwax won't
   *  repackage it or its head can't be read (`formatOnly` false - that copy isn't asked for the URL
   *  way either), or only its format keeps it out of a stream under this one's setting (`formatOnly`
   *  true - an MP4 of it for the URL way is fine) */
  refused(source: StreamSource, index: number, why: string, formatOnly: boolean): void
  /** the song at `index` can't go on in the stream: play it the URL way */
  failed(source: StreamSource, index: number, kind: StreamFailure, why: string): void
  /** deadwax's cache can't be used at all (503, scope server): stop streaming for a while */
  engineOff(source: StreamSource, why: string): void
  /** the song at `index` has its place in the run - its head is in, and what deadwax did to it known */
  placed(source: StreamSource, index: number): void
}

export interface StreamDeps {
  /** the song's fragmented MP4 - asked once per song, for its head; its pieces come from the same */
  urlOf(track: QueueTrack): string
  /** whether a song may join a stream at all, from what the queue knows (FLAC, raw, switch on...) */
  streamable(track: QueueTrack): boolean
  /** whether its address asks deadwax to resample it - a first head then gets longer to come */
  resamples(track: QueueTrack): boolean
  /** the "Maximum quality" setting the stream started with, for its whole life: under "Original" it
   *  takes a song above 48 kHz as it is (formatStreamable() in lib/streamPlan) */
  maxRate: MaxRate
  /** whether the listener means the music to be playing - the stuck watchdog asks */
  intendsToPlay(): boolean
}

/** Which MediaSource this browser has for FLAC in an MP4, if any, and the type string it takes. */
export interface Engine {
  managed: boolean
  type: string
}

interface MediaSourceLike extends EventTarget {
  readonly readyState: 'closed' | 'open' | 'ended'
  duration: number
  addSourceBuffer(type: string): SourceBuffer
  endOfStream(error?: 'network' | 'decode'): void
}

interface MediaSourceCtor {
  new (): MediaSourceLike
  isTypeSupported(type: string): boolean
}

//? WebKit's ManagedMediaSource takes only the ISO fourcc spelling; Chromium takes both
const FLAC_TYPES = ['audio/mp4; codecs="fLaC"', 'audio/mp4; codecs="flac"']

function constructors(): { managed: MediaSourceCtor | null; plain: MediaSourceCtor | null } {
  const scope = globalThis as unknown as { ManagedMediaSource?: MediaSourceCtor; MediaSource?: MediaSourceCtor }
  return {
    managed: typeof scope.ManagedMediaSource === 'function' ? scope.ManagedMediaSource : null,
    plain: typeof scope.MediaSource === 'function' ? scope.MediaSource : null,
  }
}

/**
 * The browser's MediaSource for FLAC in an MP4, ManagedMediaSource first - it is the only one an
 * iPhone has, and on a Mac it is what Apple asks pages to use. Decided once per page, by the player.
 */
export function mediaSourceEngine(): Engine | null {
  const { managed, plain } = constructors()
  const candidates: [MediaSourceCtor | null, boolean][] = [[managed, true], [plain, false]]
  for (const [ctor, isManaged] of candidates) {
    if (!ctor || typeof ctor.isTypeSupported !== 'function') continue
    for (const type of FLAC_TYPES) {
      try {
        if (ctor.isTypeSupported(type)) return { managed: isManaged, type }
      } catch {
        //? isTypeSupported can throw on an odd string in some engines - try the next spelling
      }
    }
  }
  return null
}

/** A song's head: what parseHead() read, the init segment, and its first bytes while they're useful. */
interface Head {
  head: Fmp4Head
  init: Uint8Array
  /** the first bytes as fetched with the head - the first fragment(s) ride along - until used */
  lead: Uint8Array | null
  etag: string
  /** the address the head came from, which every piece of the song is fetched from too */
  url: string
  /** what deadwax says it resampled the song from and to (X-Deadwax-Resampled), or null */
  resampled: Resampled | null
}

type HeadState =
  | { state: 'pending'; controller: AbortController; attempt: number; timer: ReturnType<typeof setTimeout> | undefined }
  | { state: 'done'; head: Head }
  | { state: 'gone' }

/** A piece fetched and waiting to be appended. */
interface Piece {
  song: RunSong
  from: number
  to: number
  bytes: Uint8Array
  /** a QuotaExceededError has already cleared what was behind for it once */
  cleared: boolean
}

/** A seek being applied, in stages - see seekTo(). */
interface Seek {
  index: number
  seconds: number
  stage: 'wait' | 'clear' | 'place' | 'append' | 'land'
  target: number
}

type Op = { kind: 'init'; song: number } | { kind: 'piece'; piece: Piece } | { kind: 'remove' }

interface Fetched {
  status: number
  headers: Headers | null
  bytes: Uint8Array
  timedOut: boolean
}

export class StreamSource {
  readonly element: HTMLAudioElement
  readonly tracks: QueueTrack[]
  readonly startIndex: number

  private readonly engine: Engine
  private readonly deps: StreamDeps
  private readonly events: StreamEvents
  private readonly ms: MediaSourceLike
  private sb: SourceBuffer | null = null
  private objectUrl: string | null = null
  private closed = false

  /** placed songs, in queue order from startIndex - where each is on the timeline */
  private songs: RunSong[] = []
  private heads = new Map<number, HeadState>()
  /** the run's last song, once known */
  private end: number | null = null
  /** the song whose init segment was appended last - its frames are what the buffer expects next */
  private lastInit: number | null = null
  private op: Op | null = null
  private piece: Piece | null = null
  /** the other halves of a piece split to fit a full buffer, in order - each appended once the one
   *  before it is in (a half split again puts its own second half first) */
  private rest: Piece[] = []
  /** where a later song that can't be had begins: whatever of it is already in goes before the
   *  source is ended, or it would play under the song before's title */
  private cutAt: number | null = null
  /** the largest piece to ask for: PIECE_MAX_BYTES until a full buffer says less fits */
  private pieceMax = PIECE_MAX_BYTES
  private fetching: { controller: AbortController; want: Want } | null = null
  private retry: { timer: ReturnType<typeof setTimeout> } | null = null
  /** how many times in a row the piece at `key` has failed - kept across its retries, cleared when one comes */
  private strikes: { key: string; attempt: number } | null = null
  private seek: Seek | null = null
  private filling = false
  private maxAhead: number
  /** a QuotaExceededError that clearing didn't cure: wait for the playhead to move before trying again */
  private quotaWaitAt: number | null = null
  private lastProgress = { position: -1, at: 0 }
  /** pump() calls so far - how one call can tell that another ran inside it */
  private pumps = 0
  /** when attach() put the stream on the element (performance clock) */
  private attachedAt = 0
  private timers = new Set<ReturnType<typeof setTimeout>>()
  private readonly elementListeners: [string, EventListener][]

  constructor(element: HTMLAudioElement, tracks: QueueTrack[], startIndex: number, engine: Engine, deps: StreamDeps, events: StreamEvents) {
    this.element = element
    this.tracks = tracks
    this.startIndex = startIndex
    this.engine = engine
    this.deps = deps
    this.events = events
    this.maxAhead = engine.managed ? MANAGED_AHEAD_BYTES : PLAIN_AHEAD_BYTES
    const { managed, plain } = constructors()
    const Ctor = (engine.managed ? managed : plain) as MediaSourceCtor
    this.ms = new Ctor()
    this.elementListeners = [
      ['seeked', () => this.pump()],
      ['waiting', () => this.pump()],
      ['playing', () => this.pump()],
    ]
  }

  /**
   * Put the stream on the element - synchronously, so the player can call play() in the same turn of
   * the tap that asked for it. `startAt` is where in the first song to begin (a seek made before the
   * stream existed); it applies once that song's head is in.
   */
  attach(startAt = 0): void {
    const element = this.element
    this.attachedAt = performance.now()
    this.ms.addEventListener('sourceopen', () => this.opened())
    if (this.engine.managed) {
      //? before attaching: without it WebKit never opens a ManagedMediaSource at all
      element.disableRemotePlayback = true
      try {
        element.srcObject = this.ms as unknown as MediaSource
      } catch {
        this.objectUrl = URL.createObjectURL(this.ms as unknown as MediaSource)
        element.src = this.objectUrl
      }
    } else {
      //? Chromium won't take a MediaSource as srcObject (a TypeError) - a blob: address is the way in
      this.objectUrl = URL.createObjectURL(this.ms as unknown as MediaSource)
      element.src = this.objectUrl
    }
    this.elementListeners.forEach(([name, listener]) => element.addEventListener(name, listener))
    if (startAt > 0) this.seek = { index: this.startIndex, seconds: startAt, stage: 'wait', target: 0 }
    this.later(SOURCEOPEN_TIMEOUT_MS, () => {
      if (!this.sb && !this.closed) this.fail(this.startIndex, 'open', 'the stream never opened')
    })
    //? straight away, beside the open: on a cold cache deadwax downloads and repackages the whole
    //? song before the first byte, and that is most of the wait
    this.fetchHead(this.startIndex)
    this.later(5000, () => this.watch())
  }

  /** The placed song at `index`, or null - what the player measures a song's length and place by. */
  song(index: number): RunSong | null {
    return this.songs.find((song) => song.index === index) ?? null
  }

  songAt(t: number): RunSong | null {
    return songAt(this.songs, t)
  }

  /** The run's last song, once known. */
  runEnd(): number | null {
    return this.end
  }

  /** The "Maximum quality" setting the stream started with, which it keeps - see StreamDeps. */
  get maxRate(): MaxRate {
    return this.deps.maxRate
  }

  /** What deadwax resampled the song at `index` from and to, once its head is in - for the readout. */
  resampled(index: number): Resampled | null {
    const entry = this.heads.get(index)
    return entry?.state === 'done' ? entry.head.resampled : null
  }

  /** The rate of the song at `index` when it streams above 48 kHz as it is ("Original"), once its
   *  head is in - for the readout, which shows the rate was kept. */
  hiRes(index: number): number | null {
    const entry = this.heads.get(index)
    if (entry?.state !== 'done' || entry.head.resampled) return null
    const rate = entry.head.head.format.sampleRate
    return rate > STREAM_MAX_RATE ? rate : null
  }

  /** Whether song-relative `seconds` of the placed song at `index` is buffered now. */
  isBuffered(index: number, seconds: number): boolean {
    const song = this.song(index)
    if (!song || !this.sb) return false
    const t = song.start + Math.max(0, seconds)
    return covered(this.buffered(), t, t + 0.05)
  }

  /**
   * Go to song-relative `seconds` of the song at `index`. False when this stream can't get there -
   * a song before the run, past its known end, or not placed yet beyond the first - and the player
   * loads it another way. The first song may be asked for before its head is in: the seek applies
   * once it is.
   */
  seekTo(index: number, seconds: number): boolean {
    if (this.closed || index < this.startIndex) return false
    if (this.end !== null && index > this.end) return false
    const placed = this.song(index)
    if (!placed && !(index === this.startIndex && this.songs.length === 0)) return false
    this.seek = { index, seconds, stage: 'wait', target: 0 }
    this.pump()
    return true
  }

  /** From the player's timeupdate and play: keep feeding. */
  tick(): void {
    this.progressed()
    this.pump()
  }

  close(): void {
    if (this.closed) return
    this.closed = true
    this.fetching?.controller.abort()
    this.fetching = null
    for (const entry of this.heads.values()) {
      if (entry.state === 'pending') {
        entry.controller.abort()
        if (entry.timer !== undefined) clearTimeout(entry.timer)
      }
    }
    if (this.retry) clearTimeout(this.retry.timer)
    this.retry = null
    this.timers.forEach((timer) => clearTimeout(timer))
    this.timers.clear()
    const element = this.element
    this.elementListeners.forEach(([name, listener]) => element.removeEventListener(name, listener))
    //? srcObject beats the src attribute, so it has to go before anything else can play here - and
    //? only this stream's own attachment is undone: an element already given something else keeps it
    let detached = false
    if (element.srcObject === (this.ms as unknown as MediaSource)) {
      element.srcObject = null
      detached = true
    }
    if (this.objectUrl) {
      if (element.getAttribute('src') === this.objectUrl) {
        element.removeAttribute('src')
        detached = true
      }
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
    }
    if (detached) element.load()
    if (this.engine.managed) element.disableRemotePlayback = false
  }

  /* ===== opening ===== */

  private opened() {
    if (this.closed) return
    //? a reopened source (an append after endOfStream) fires this again: one SourceBuffer, ever
    if (!this.sb) {
      const types = [this.engine.type, ...FLAC_TYPES.filter((type) => type !== this.engine.type)]
      for (const type of types) {
        try {
          this.sb = this.ms.addSourceBuffer(type)
          break
        } catch (error) {
          if (!(error instanceof DOMException && error.name === 'NotSupportedError')) break
        }
      }
      if (!this.sb) {
        this.fail(this.startIndex, 'open', "the browser wouldn't take FLAC in an MP4 after all")
        return
      }
      this.sb.addEventListener('updateend', () => this.updated())
      this.sb.addEventListener('error', () => this.appendFailed())
    }
    this.pump()
  }

  /* ===== heads: where each song goes ===== */

  /** Ask for a song's head (and its first fragments) - once, with retries for a song not yet needed. */
  private fetchHead(index: number) {
    if (this.closed || this.heads.has(index)) return
    const track = this.tracks[index]
    if (!track) return
    const controller = new AbortController()
    const entry: HeadState = { state: 'pending', controller, attempt: 0, timer: undefined }
    this.heads.set(index, entry)
    void this.loadHead(index, track, entry)
  }

  private async loadHead(index: number, track: QueueTrack, entry: Extract<HeadState, { state: 'pending' }>) {
    const url = this.deps.urlOf(track)
    const got = await this.get(url, 0, HEAD_FETCH_BYTES - 1, null, entry.controller)
    if (this.closed || this.heads.get(index) !== entry) return
    const answer = got ? this.judge(got, 0, HEAD_FETCH_BYTES - 1, false) : null
    if (!got || !answer) return
    const first = index === this.startIndex && this.songs.length === 0
    if (answer.kind === 'ok') {
      const total = totalOf(got.headers?.get('Content-Range') ?? null) ?? got.bytes.length
      const parsed = parseHead(got.bytes, total)
      const etag = got.headers?.get('ETag') ?? null
      if (parsed.kind === 'bad' || !etag) {
        this.headRefused(index, parsed.kind === 'bad' ? `its stream can't be read: ${parsed.why}` : 'deadwax sent no ETag')
        return
      }
      const head = parsed.head
      const resampled = resampledFrom(got.headers?.get('X-Deadwax-Resampled') ?? null)
      this.heads.set(index, { state: 'done', head: { head, init: initBytes(head, got.bytes).slice(), lead: got.bytes, etag, url, resampled } })
      this.place()
      this.pump()
      return
    }
    if (answer.kind === 'refused') {
      this.headRefused(index, 'deadwax would not repackage it')
      return
    }
    if (answer.kind === 'engine-off') {
      this.heads.set(index, { state: 'gone' })
      this.events.engineOff(this, "deadwax's cache for the player can't be used")
      if (first) this.fail(index, 'transport', "deadwax's cache for the player can't be used")
      else this.endAt(index - 1)
      return
    }
    //? the run's first song has somebody waiting on it: straight to the URL way rather than retrying
    if (first || answer.kind !== 'retry') {
      this.heads.set(index, { state: 'gone' })
      if (first) this.fail(index, answer.kind === 'changed' ? 'changed' : 'transport', whyOf(answer))
      else this.endAt(index - 1)
      return
    }
    const delay = retryDelay(entry.attempt, answer.afterMs)
    if (delay === null) {
      //? a later song: the run simply ends before it, and it plays the URL way at its turn
      this.heads.set(index, { state: 'gone' })
      this.endAt(index - 1)
      return
    }
    entry.attempt += 1
    entry.timer = setTimeout(() => {
      entry.timer = undefined
      if (this.closed || this.heads.get(index) !== entry) return
      entry.controller = new AbortController()
      void this.loadHead(index, track, entry)
    }, delay)
  }

  /** A head that won't do: the song never streams this page; the run ends before it (or, first, fails). */
  private headRefused(index: number, why: string) {
    this.heads.set(index, { state: 'gone' })
    this.events.refused(this, index, why, false)
    if (index === this.startIndex && this.songs.length === 0) this.fail(index, 'refused', why)
    else this.endAt(index - 1)
  }

  /** Place every song whose head is in, in order; the first that doesn't join ends the run. */
  private place() {
    for (;;) {
      const index = this.startIndex + this.songs.length
      if (this.end !== null && index > this.end) return
      const entry = this.heads.get(index)
      if (!entry || entry.state !== 'done') return
      const prev = this.songs[this.songs.length - 1] ?? null
      const { head } = entry.head
      if (!joins(prev, head, this.deps.maxRate)) {
        const track = this.tracks[index]
        //? a format this engine doesn't stream never will (in a stream started under this setting); a
        //? song that merely differs from the run's (44.1 then 48 kHz) can start its own run another time
        const why = `${head.format.sampleRate} Hz / ${head.format.bitsPerSample}-bit / ${head.format.channels} channels isn't streamed`
        const never = !formatStreamable(head.format, this.deps.maxRate)
        if (never) {
          this.heads.set(index, { state: 'gone' })
          this.events.refused(this, index, why, true)
        }
        if (prev) this.endAt(index - 1)
        else this.fail(index, never ? 'format' : 'refused', `${track?.title ?? 'the song'}: ${why}`)
        return
      }
      //? The same format out isn't enough when deadwax resampled one of them: a 96 kHz song and a
      //? 192 kHz one both come out 48 kHz, and so does a 48 kHz song beside a resampled 96 kHz one -
      //? and deadwax gives neither side of a change of rate the other's samples, so the join would
      //? click in music that runs on. Only the same SOURCE rate joins; the run ends before the other,
      //? which starts a run of its own another time, like 44.1 then 48 kHz.
      const prevEntry = prev ? this.heads.get(prev.index) : undefined
      if (prev && prevEntry?.state === 'done' &&
          sourceRateOf(prev.head, prevEntry.head.resampled?.from ?? null) !== sourceRateOf(head, entry.head.resampled?.from ?? null)) {
        this.endAt(index - 1)
        return
      }
      const song = placeSong(prev, index, this.tracks[index]!.id, head)
      this.songs.push(song)
      this.events.placed(this, index)
      if (this.seek?.stage === 'wait' && this.seek.index === index) this.pump()
    }
  }

  /**
   * One song of look-ahead: the song after the last placed one gets its head asked for once the
   * feeding is within FILL_TO_S of that last song's end - about a minute before the join, early
   * enough for deadwax to make it and for the run's end to be known, but late enough that its first
   * pieces follow its head within deadwax's IN_USE_SECONDS. Asked a whole song earlier, the head was
   * all deadwax had served of it by the time the song after it was made, and a small cache cleared
   * it as idle just before it was needed. A song that can't join is known at once, with no asking.
   */
  private lookAhead(frontier: RunSong | null, want: Want | null) {
    const last = this.songs[this.songs.length - 1]
    if (!last || this.end !== null) return
    if (frontier && frontier.index < last.index) return
    const next = last.index + 1
    const track = this.tracks[next]
    if (!track || !this.deps.streamable(track)) {
      this.endAt(last.index)
      return
    }
    if (this.heads.has(next)) return
    //? how far into the last song the feeding has got - all of it, when nothing of it is wanted
    const fed = want && want.song.index === last.index ? want.song.head.fragments[want.from]!.t0 / want.song.head.timescale : last.length
    if (last.length - fed > FILL_TO_S) return
    this.fetchHead(next)
  }

  /** Nothing joins after `lastIndex`: said as early as it is known, and again whenever it comes
   *  earlier (a later song that couldn't be had); anything of later songs goes. */
  private endAt(lastIndex: number) {
    if (this.end !== null && this.end <= lastIndex) return
    this.end = lastIndex
    for (const [index, entry] of this.heads) {
      if (index > lastIndex && entry.state === 'pending') {
        entry.controller.abort()
        if (entry.timer !== undefined) clearTimeout(entry.timer)
        this.heads.delete(index)
      }
    }
    this.songs = this.songs.filter((song) => song.index <= lastIndex)
    if (this.fetching && this.fetching.want.song.index > lastIndex) {
      this.fetching.controller.abort()
      this.fetching = null
    }
    if (this.piece && this.piece.song.index > lastIndex) this.piece = null
    this.rest = this.rest.filter((piece) => piece.song.index <= lastIndex)
    if (lastIndex >= this.startIndex) this.events.runEnded(this, lastIndex)
    this.pump()
  }

  /* ===== feeding ===== */

  private buffered(): Ranges {
    const sb = this.sb
    if (!sb) return []
    try {
      return rangesOf(sb.buffered)
    } catch {
      //? a SourceBuffer removed from its source (the element loaded something else) throws
      return []
    }
  }

  private busy(): boolean {
    return this.closed || !this.sb || this.op !== null || this.sb.updating || this.ms.readyState === 'closed'
  }

  /** Do the next thing, if nothing is in flight. Called by every event that might have freed it. */
  private pump() {
    if (this.busy()) return
    const pass = ++this.pumps
    if (this.cutAt !== null) {
      const from = this.cutAt
      this.cutAt = null
      if (this.buffered().some(([, b]) => b > from + 0.001)) {
        this.remove(from, Infinity)
        return
      }
    }
    if (this.seek && this.seeking()) return
    //? a full buffer that clearing and splitting didn't cure: nothing goes in until the playhead has
    //? moved on - unless it is waiting for data itself, when waiting on it would wait for ever
    if (this.quotaWaitAt !== null) {
      const moved = Math.abs(this.element.currentTime - this.quotaWaitAt) >= 0.5
      if (!moved && aheadSeconds(this.buffered(), this.element.currentTime) >= 1) return
      this.quotaWaitAt = null
    }
    if (this.piece) {
      this.append(this.piece)
      return
    }
    const t = this.element.currentTime
    const ranges = this.buffered()
    const want = nextWant(this.songs, ranges, t, { maxBytes: this.pieceMax, maxSeconds: PIECE_MAX_SECONDS })
    this.lookAhead(want?.song ?? songAt(this.songs, t), want)
    //? lookAhead can end the run, and endAt pumps: that pump has done this one's work already, with
    //? what it found - carrying on here would act on `want` as it was before, and fetch again the
    //? fragments that came with the last song's head (every album's last song did)
    if (this.pumps !== pass) return
    if (!want) {
      this.maybeEnd(t, ranges)
      return
    }
    const ahead = aheadSeconds(ranges, t)
    this.filling = shouldFill({ ahead, aheadBytes: aheadBytes(this.songs, ranges, t), maxBytes: this.maxAhead, filling: this.filling })
    if (!this.filling) return
    this.feed(want)
  }

  /** Everything placed is in: at the run's known end, the source is ended - again, after any reopen. */
  private maybeEnd(t: number, ranges: Ranges) {
    const last = this.songs[this.songs.length - 1]
    if (this.end === null || !last || last.index !== this.end) return
    if (nextWant(this.songs, ranges, t) !== null) return
    if (this.ms.readyState !== 'open' || this.sb?.updating) return
    try {
      this.ms.endOfStream()
    } catch {
      //? an append or remove began in between - the next updateend tries again
    }
  }

  /** Get `want` - from the head's bytes when it rode along, else with a ranged ask. */
  private feed(want: Want) {
    if (this.fetching || this.retry) return
    const entry = this.heads.get(want.song.index)
    if (!entry || entry.state !== 'done') return
    const { lead, etag, url } = entry.head
    if (lead) {
      //? the fragments that rode along with the head are appended from it: a first piece of a CD song
      //? runs past the 256 KiB, and asking for all of it again would fetch those bytes twice
      const inLead = piecesInside(entry.head.head, lead.length)
      if (want.from < inLead) {
        const to = Math.min(want.to, inLead)
        const fragments = want.song.head.fragments
        const bytes = lead.subarray(fragments[want.from]!.start, fragments[to - 1]!.end)
        this.piece = { song: want.song, from: want.from, to, bytes, cleared: false }
        //? past its first fragments the lead is no use: let it go rather than hold 256 KiB per song
        if (to >= inLead) entry.head.lead = null
        this.pump()
        return
      }
      entry.head.lead = null
    }
    const controller = new AbortController()
    this.fetching = { controller, want }
    //? from the address its head came from: what the run was started with, whatever is asked now
    void this.get(url, want.start, want.end - 1, etag, controller).then((got) => {
      if (this.closed || this.fetching?.controller !== controller) return
      this.fetching = null
      if (!got) return
      const answer = this.judge(got, want.start, want.end - 1, true)
      if (answer.kind === 'ok' && got.bytes.length === want.end - want.start) {
        this.strikes = null
        this.piece = { song: want.song, from: want.from, to: want.to, bytes: got.bytes, cleared: false }
        this.pump()
        return
      }
      this.pieceFailed(want, answer.kind === 'ok' ? { kind: 'retry', afterMs: null } : answer)
    })
  }

  /** A piece that didn't come. Retried while nothing waits on it; given up on when the playhead does. */
  private pieceFailed(want: Want, answer: Answer) {
    const index = want.song.index
    if (answer.kind === 'changed' || answer.kind === 'refused' || answer.kind === 'fatal' || answer.kind === 'engine-off') {
      if (answer.kind === 'engine-off') this.events.engineOff(this, "deadwax's cache for the player can't be used")
      //? a refusal is said as one first, whichever song it is - the player keeps it by the copy asked for
      if (answer.kind === 'refused') this.events.refused(this, index, whyOf(answer), false)
      //? a LATER song that can't be had, while the song playing still has music: the run ends before
      //? it, and it plays the URL way at its turn - the song playing is never cut short for it
      const playing = songAt(this.songs, this.element.currentTime)
      if (playing && index > playing.index && !this.waitingOn(want)) {
        this.cutAt = want.song.start
        this.endAt(index - 1)
        return
      }
      this.fail(index, answer.kind === 'changed' ? 'changed' : answer.kind === 'refused' ? 'refused' : 'transport', whyOf(answer))
      return
    }
    const key = `${index}:${want.from}`
    const attempt = this.strikes?.key === key ? this.strikes.attempt : 0
    this.strikes = { key, attempt: attempt + 1 }
    const delay = retryDelay(attempt, answer.kind === 'retry' ? answer.afterMs : null)
    const waiting = this.waitingOn(want)
    if (delay === null && waiting) {
      this.retry = null
      this.strikes = null
      this.fail(index, 'transport', whyOf(answer))
      return
    }
    //? nothing is waiting on it yet: keep trying at the last delay - the playhead may never need it
    //? before the connection comes back
    const wait = delay ?? retryDelay(3, null) ?? 4000
    const timer = setTimeout(() => {
      if (this.retry?.timer === timer) this.retry = null
      this.pump()
    }, wait)
    this.retry = { timer }
  }

  /** Whether the playhead has run out of data at this piece. */
  private waitingOn(want: Want): boolean {
    const t = this.element.currentTime
    const start = want.song.start + want.song.head.fragments[want.from]!.t0 / want.song.head.timescale
    return aheadSeconds(this.buffered(), t) < 0.5 && t >= start - 1
  }

  /** Append a piece - its song's init first, whenever the buffer last had another song's. */
  private append(piece: Piece) {
    const sb = this.sb!
    if (this.lastInit !== piece.song.index) {
      const entry = this.heads.get(piece.song.index)
      if (!entry || entry.state !== 'done') {
        this.piece = null
        return
      }
      try {
        sb.timestampOffset = piece.song.start
        this.op = { kind: 'init', song: piece.song.index }
        sb.appendBuffer(entry.head.init as BufferSource)
        this.lastInit = piece.song.index
      } catch {
        this.op = null
        this.later(200, () => this.pump())
      }
      return
    }
    try {
      this.op = { kind: 'piece', piece }
      sb.appendBuffer(piece.bytes as BufferSource)
    } catch (error) {
      this.op = null
      if (error instanceof DOMException && error.name === 'QuotaExceededError') this.quota(piece)
      else this.later(200, () => this.pump())
    }
  }

  /**
   * The buffer is full. First clear what is behind the playhead (keeping a second of it, so nothing
   * about to be decoded goes) and anything held apart from the run the playhead is in. If that isn't
   * enough and the piece is more than one fragment, split it - its fragments' bytes are known, so
   * nothing is fetched again - and ask for smaller pieces from now on. One fragment that still
   * doesn't fit: hold less ahead, and wait for the playhead to free some room.
   */
  private quota(piece: Piece) {
    const t = this.element.currentTime
    const ranges = this.buffered()
    const first = ranges[0]
    if (!piece.cleared) {
      piece.cleared = true
      if (first && first[0] < t - 1.05) {
        this.remove(first[0], t - 1)
        return
      }
      const apart = ranges.find(([a, b]) => !(a <= t + 0.1 && t < b))
      if (apart) {
        this.remove(apart[0], apart[1])
        return
      }
    }
    if (piece.to - piece.from > 1) {
      const [head, tail] = split(piece)
      this.pieceMax = Math.max(1, Math.floor(piece.bytes.length / 2))
      this.piece = head
      this.rest.unshift(tail)
      this.pump()
      return
    }
    //? once per wait: the budget comes down a step, not to the floor in one run of retries
    if (this.quotaWaitAt === null) this.maxAhead = lowerBudget(this.maxAhead, piece.bytes.length)
    piece.cleared = false
    this.quotaWaitAt = t
  }

  private remove(start: number, end: number) {
    try {
      this.op = { kind: 'remove' }
      this.sb!.remove(start, end)
    } catch {
      this.op = null
    }
  }

  /** An append, remove or init finished - or an aborted one's late 'updateend' arrived. */
  private updated() {
    //? the 'updateend' that follows an abort() comes after whatever was started next: while that is
    //? still running, this one says nothing
    if (!this.sb || this.sb.updating) return
    const op = this.op
    this.op = null
    if (op?.kind === 'piece' && this.piece === op.piece) this.piece = this.rest.shift() ?? null
    this.pump()
  }

  /** The browser couldn't parse or decode an append: whose was it, so the right song is blamed. */
  private appendFailed() {
    const op = this.op
    const index = op?.kind === 'piece' ? op.piece.song.index : op?.kind === 'init' ? op.song : (this.lastInit ?? this.startIndex)
    //? A later song's bytes that won't parse: that song never streams, but the browser has given the
    //? whole source up with it (WebKit detaches it on an append error; Chromium ends it with a decode
    //? error) - so the song playing, which is fine, goes on the URL way from where it had got to
    const playing = songAt(this.songs, this.element.currentTime)
    if (playing && index > playing.index) {
      this.events.refused(this, index, "the browser couldn't play what deadwax sent for it", false)
      this.fail(playing.index, 'broken', "the browser gave the stream up over a later song's audio")
      return
    }
    this.fail(index, 'decode', "the browser couldn't play what deadwax sent for it")
  }

  /* ===== seeking ===== */

  /** Apply the seek in stages; true while it still holds up ordinary feeding. */
  private seeking(): boolean {
    const seek = this.seek!
    if (seek.stage === 'wait') {
      const song = this.song(seek.index)
      if (!song) return true
      seek.target = song.start + Math.min(Math.max(0, seek.seconds), Math.max(0, song.length - 0.001))
      //? up to the song's end at most: nothing may be placed after the last song, and a seek to its
      //? final moments must not wait on data that can never come
      if (covered(this.buffered(), seek.target, Math.min(seek.target + 0.05, song.end))) {
        this.element.currentTime = seek.target
        this.seek = null
        return false
      }
      //? stop what was on its way for somewhere else
      this.fetching?.controller.abort()
      this.fetching = null
      this.piece = null
      this.rest = []
      if (this.retry) clearTimeout(this.retry.timer)
      this.retry = null
      seek.stage = 'clear'
    }
    if (seek.stage === 'clear') {
      //? everything else goes, so nothing is evicted relative to where the playhead was (Safari 27.0)
      const other = this.buffered().find(([a, b]) => !(a <= seek.target && seek.target < b))
      if (other) {
        this.remove(other[0], other[1])
        return true
      }
      seek.stage = 'place'
    }
    if (seek.stage === 'place') {
      const song = this.song(seek.index)!
      //? A seek is clamped to what is seekable: [0, duration] for a finite duration, which grows only
      //? as data comes (WebKit's starts at nothing, the init saying 0), and only [0, the buffered end]
      //? for Chromium's infinite one. So a finite duration past the target song's end, first. It can't
      //? be set below what is buffered, hence the max.
      const duration = this.ms.duration
      if (this.ms.readyState === 'open' && !(Number.isFinite(duration) && seek.target < duration)) {
        try {
          const ranges = this.buffered()
          const bufferedEnd = ranges.length ? ranges[ranges.length - 1]![1] : 0
          this.ms.duration = Math.max(song.end, bufferedEnd)
        } catch {
          //? something was updating after all - the next pump tries again
          return true
        }
      }
      this.element.currentTime = seek.target
      seek.stage = 'append'
    }
    if (seek.stage === 'append') {
      const ranges = this.buffered()
      if (covered(ranges, seek.target, Math.min(seek.target + 0.05, this.song(seek.index)!.end))) {
        seek.stage = 'land'
      } else {
        if (this.piece) {
          this.append(this.piece)
          return true
        }
        const want = nextWant(this.songs, ranges, seek.target, { maxBytes: this.pieceMax, maxSeconds: PIECE_MAX_SECONDS })
        if (want) this.feed(want)
        return true
      }
    }
    //? 'land': nothing more until the element says it has got there
    if (this.element.seeking) return true
    this.seek = null
    return false
  }

  /* ===== watching ===== */

  /** The playhead moved - or is paused, which is not being stuck: the clock starts again from play. */
  private progressed() {
    const position = this.element.currentTime
    if (position !== this.lastProgress.position || this.element.paused) this.lastProgress = { position, at: performance.now() }
  }

  /** Every few seconds, even while nothing happens: a stream that has stopped moving for no reason fails. */
  private watch() {
    if (this.closed) return
    this.progressed()
    const idle = !this.fetching && !this.retry && this.op === null && !this.piece && this.rest.length === 0
    const stuck = this.deps.intendsToPlay() && !this.element.paused && performance.now() - this.lastProgress.at > STUCK_MS
    if (stuck && idle && !this.resampling()) {
      //? at the very end of the last placed song, it is that song that can't go on
      const t = this.element.currentTime
      const last = this.songs[this.songs.length - 1]
      const song = songAt(this.songs, t) ?? (last && t >= last.end - 0.05 ? last : null) ?? this.song(this.startIndex)
      this.fail(song?.index ?? this.startIndex, 'stuck', 'the stream stopped moving')
      return
    }
    this.pump()
    this.later(5000, () => this.watch())
  }

  /**
   * The run's first head still on its way for a song deadwax was asked to resample, within
   * RESAMPLE_HEAD_WAIT_MS of the start: nothing moves while deadwax makes it, and that is not stuck.
   * Past it, the song goes the URL way - as the file as it is, relayed at once - like any other.
   */
  private resampling(): boolean {
    if (this.songs.length > 0 || this.heads.get(this.startIndex)?.state !== 'pending') return false
    const track = this.tracks[this.startIndex]
    return !!track && this.deps.resamples(track) && performance.now() - this.attachedAt < RESAMPLE_HEAD_WAIT_MS
  }

  private fail(index: number, kind: StreamFailure, why: string) {
    if (this.closed) return
    this.events.failed(this, index, kind, why)
  }

  private later(ms: number, fn: () => void) {
    const timer = setTimeout(() => {
      this.timers.delete(timer)
      if (!this.closed) fn()
    }, ms)
    this.timers.add(timer)
  }

  /* ===== HTTP ===== */

  /**
   * GET bytes [start, end] of `url`. No timeout on the answer's headers shorter than HEADER_TIMEOUT_MS
   * - deadwax downloads and repackages the whole song before the first byte of a cold one - but a body
   * that stops arriving for BODY_STALL_MS is given up (a tunnel that roamed never says so). Null when
   * this stream let go of it; `timedOut` when the clock did.
   */
  private async get(url: string, start: number, end: number, ifRange: string | null, controller: AbortController): Promise<Fetched | null> {
    let timedOut = false
    const expire = () => {
      timedOut = true
      controller.abort()
    }
    let timer = setTimeout(expire, HEADER_TIMEOUT_MS)
    const headers: Record<string, string> = { Range: `bytes=${start}-${end}` }
    if (ifRange) headers['If-Range'] = ifRange
    try {
      const response = await fetch(url, { headers, signal: controller.signal, cache: 'no-store' })
      clearTimeout(timer)
      //? The status first: only a 206 carries bytes to append, and only a 503's body says anything
      //? (its scope). Anything else - above all the whole file as a 200, deadwax's answer to an
      //? If-Range ask whose file changed - is let go of unread, and a 206 is read no further than asked.
      const limit = response.status === 206 ? end - start + 1 : response.status === 503 ? 4096 : 0
      const reader = response.body?.getReader()
      const found = { status: response.status, headers: response.headers, timedOut: false }
      if (limit === 0) {
        void reader?.cancel().catch(() => {})
        return { ...found, bytes: new Uint8Array(0) }
      }
      timer = setTimeout(expire, BODY_STALL_MS)
      const parts: Uint8Array[] = []
      let size = 0
      if (reader) {
        while (size < limit) {
          const { done, value } = await reader.read()
          if (done) break
          parts.push(value)
          size += value.byteLength
          clearTimeout(timer)
          timer = setTimeout(expire, BODY_STALL_MS)
        }
        if (size >= limit) void reader.cancel().catch(() => {})
      } else {
        const whole = new Uint8Array(await response.arrayBuffer())
        parts.push(whole)
        size = whole.byteLength
      }
      clearTimeout(timer)
      const bytes = new Uint8Array(Math.min(size, limit))
      let at = 0
      for (const part of parts) {
        if (at >= bytes.length) break
        const take = Math.min(part.byteLength, bytes.length - at)
        bytes.set(take === part.byteLength ? part : part.subarray(0, take), at)
        at += take
      }
      return { ...found, bytes }
    } catch {
      clearTimeout(timer)
      if (!timedOut && controller.signal.aborted) return null
      //? a network error or a stall: status 0, which classifyAnswer() takes for "try again"
      return { status: 0, headers: null, bytes: new Uint8Array(0), timedOut }
    }
  }

  private judge(got: Fetched, askedStart: number, askedEnd: number, ifRange: boolean): Answer {
    const headers = got.headers
    return classifyAnswer({
      status: got.status,
      contentType: headers?.get('Content-Type') ?? null,
      contentRange: headers?.get('Content-Range') ?? null,
      retryAfter: headers?.get('Retry-After') ?? null,
      scope: got.status === 503 ? scopeOf(got.bytes) : null,
      askedStart,
      askedEnd,
      ifRange,
    })
  }
}

/** A piece in two, at a fragment boundary - the first half's bytes end where its fragments do. */
function split(piece: Piece): [Piece, Piece] {
  const fragments = piece.song.head.fragments
  const mid = piece.from + Math.floor((piece.to - piece.from) / 2)
  const cut = fragments[mid]!.start - fragments[piece.from]!.start
  return [
    { song: piece.song, from: piece.from, to: mid, bytes: piece.bytes.subarray(0, cut), cleared: false },
    { song: piece.song, from: mid, to: piece.to, bytes: piece.bytes.subarray(cut), cleared: false },
  ]
}

/** The whole size from a Content-Range answer ("bytes 0-262143/31457280"). */
function totalOf(contentRange: string | null): number | null {
  const match = /\/(\d+)\s*$/.exec(contentRange ?? '')
  return match ? Number(match[1]) : null
}

/** The "scope" of a 503's JSON body - "server" when deadwax's cache can't be used at all. */
function scopeOf(bytes: Uint8Array): string | null {
  try {
    const body = JSON.parse(new TextDecoder().decode(bytes)) as { scope?: unknown }
    return typeof body.scope === 'string' ? body.scope : null
  } catch {
    return null
  }
}

function whyOf(answer: Answer): string {
  switch (answer.kind) {
    case 'refused':
      return 'deadwax would not repackage it'
    case 'changed':
      return "the song's file changed while it played"
    case 'engine-off':
      return "deadwax's cache for the player can't be used"
    case 'fatal':
      return answer.why
    case 'retry':
      return "its audio couldn't be fetched"
    default:
      return 'it stopped'
  }
}
