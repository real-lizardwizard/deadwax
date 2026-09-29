/**
 * Playing: one audio element, the queue, and the lock screen.
 *
 * Three things here are specific to iPhones and each is load-bearing:
 *
 *  - ONE audio element for the life of the page, never replaced. iOS lets a page play audio only
 *    from a tap, and it is the ELEMENT a tap unlocks - so moving to the next song while the phone
 *    is locked works by giving the same element a new source. A fresh element for each song would
 *    have been started by nobody, and could be refused.
 *  - play() is called in the same turn as the tap that asked for it, never after an await. A
 *    promise in between loses the tap.
 *  - The lock screen's controls come from the Media Session API, and iOS shows EITHER track
 *    buttons or 10-second skip buttons: setting a seekforward/seekbackward handler replaces
 *    previous and next. So those two are deliberately never set.
 *
 * And one that matters most there: a song that won't play must not stop the queue. A failure is
 * tried once more and then passed over for the next song (afterFailure() in lib/playQueue), on
 * the same element, so a dropped connection or a missing file doesn't end the music in a pocket.
 *
 * The gapless switch (off by default, lib/gapless) is the one exception to the first rule, and it
 * keeps to the reason for it: a SECOND element, put through load() in the same tap that first
 * plays so that iOS unlocks it too, holds the next song muted and ready, and a song ending starts
 * it from the 'ended' handler. The two then swap roles, so there are only ever two elements, both
 * unlocked by a tap. Every rule above goes by whichever element is playing - `live()` - and events
 * from the other one are dropped (routeEvent()). When the standby can't take the song, the song
 * goes on the element that was playing, exactly as with the switch off; and with it off there is
 * one element, as there always was.
 *
 * With the switch on, FLAC songs play differently again: one continuous MediaSource stream on the
 * element playing (player/streamSource.ts), songs appended back to back, so a song change is the
 * timeline running on rather than anything starting. Everything here then goes by where the current
 * song sits in the stream - songStart(), songPosition(), songLength() - and a song change is seen in
 * 'timeupdate' when the clock crosses into the next song (crossInto()). A stream starts only from a
 * tap or a lock-screen command; whatever it can't play (a song that isn't FLAC, a failure, AirPlay)
 * goes the ways above, and the stream is left for it at the position it had reached (leaveStream()).
 *
 * The position changes several times a second, so it is not React state - rendering the whole
 * player four times a second to move one bar would be waste. Whatever shows it subscribes with
 * usePosition() below, and only that re-renders. From a seek until the element says it has landed,
 * what it hears is the seek's target (reportedPosition() in lib/scrub), so the bar never goes back
 * to where the song was while the seek is on its way. ui/test/player.sim.cjs drives this file
 * through a fake DOM - the seek wiring, the readout across song changes, a gapless handover.
 */

import { useEffect, useMemo, useState } from 'preact/hooks'

import {
  PRELOAD_DELAY_MS, activeAfter, afterPlaybackFailure, clockStep, handoverDecision, memoryPlan, overMemoryMax,
  airplayShown, routeEvent, standbyPlan, startChange, streamReading, withReading, type Change, type ClockUpdate,
  type ElementSlot, type GapReading, type HandoverDecision, type Standby,
} from '../lib/gapless'
import {
  EMPTY_QUEUE, LOAD_RETRY_DELAY_MS, MEDIA_ERR_DECODE, NEW_LISTEN, current, listenHeard, listenStarted,
  listenedStep, nextIndex, previousAction, startQueue, type PlayQueue, type QueueTrack,
} from '../lib/playQueue'
import { reportedPosition, seekStep, type PendingSeek, type SeekEvent, type SeekReading } from '../lib/scrub'
import { ENGINE_OFF_MS, joinStallMs, splitAcrossJoin, streamable as mayStream, type RunSong } from '../lib/streamPlan'
import { asksForMp4, isFlac, wrappedAs, wrapsFlac, type Wrapped } from '../lib/streamWrap'
import { readPlayerGapless, writePlayerGapless } from '../state/persisted'
import { coverUrl, fragmentedUrl, scrobble, streamFormat, streamUrl } from './api'
import { StreamSource, mediaSourceEngine, type StreamEvents, type StreamFailure } from './streamSource'

export interface Player {
  queue: PlayQueue
  track: QueueTrack | null
  playing: boolean
  buffering: boolean
  /** seconds; the element's own once it knows it, the tags' until then */
  duration: number
  error: string | null
  /** whether an AirPlay device is on the network - the button shows only then */
  airplay: boolean
  /** whether the gapless switch is on - see lib/gapless */
  gapless: boolean
  /** the last few song changes, timed from one song's end to the next one's clock running, newest first */
  gaps: GapReading[]
  /** the last seek the listener made, and where its song's end says it landed - see SeekReading */
  lastSeek: SeekReading | null
  /** how the song playing came when it was asked for as FLAC in an MP4, for the readout; null when
   *  it wasn't (every song, outside Safari) - see lib/streamWrap */
  wrapped: Wrapped | null
  /** `start` null with shuffle: no song in particular - see startQueue() */
  playTracks(tracks: QueueTrack[], start: number | null, shuffle?: boolean): void
  toggle(): void
  next(): void
  previous(): void
  seek(seconds: number): void
  showAirPlay(): void
  /** the switch - a tap, which is also what unlocks the second element */
  setGapless(on: boolean): void
  /** the element's position, and a way to hear about it changing - see usePosition() */
  position(): number
  onPosition(listener: (seconds: number) => void): () => void
}

/** Safari's AirPlay additions to the media element, which the DOM types don't carry. */
interface AirPlayAudio extends HTMLAudioElement {
  webkitShowPlaybackTargetPicker?: () => void
  webkitCurrentPlaybackTargetIsWireless?: boolean
}

interface AvailabilityEvent extends Event {
  availability?: string
}

function describeMediaError(error: MediaError | null): string {
  switch (error?.code) {
    case 2: // MEDIA_ERR_NETWORK
      return 'The connection dropped while this song was loading'
    case 3: // MEDIA_ERR_DECODE
      return "This song's file couldn't be decoded"
    case 4: // MEDIA_ERR_SRC_NOT_SUPPORTED - also what a failed request looks like from here
      return "Couldn't play this song - Navidrome didn't send audio this device can play"
    default:
      return "Couldn't play this song"
  }
}

/** How long "Skipped ..." stands where the artist's name goes before the next song's own returns. */
const SKIP_NOTICE_MS = 5000

/** HTMLMediaElement.HAVE_METADATA: the element knows the song's length, and a seek moves it. */
const HAVE_METADATA = 1

/** Why the song before this one was passed over, named - the line is shown under the NEXT song. */
function skipNotice(title: string, error: MediaError | null): string {
  return error?.code === MEDIA_ERR_DECODE
    ? `Skipped "${title}" - its file couldn't be decoded`
    : `Skipped "${title}" - it wouldn't play`
}

function createAudio(): AirPlayAudio {
  const audio: AirPlayAudio = document.createElement('audio')
  audio.preload = 'auto'
  //? what offers this element to AirPlay speakers at all
  audio.setAttribute('x-webkit-airplay', 'allow')
  document.body.appendChild(audio)
  return audio
}

const session = (): MediaSession | null => ('mediaSession' in navigator ? navigator.mediaSession : null)

export function usePlayer(): Player {
  const [queue, setQueue] = useState<PlayQueue>(EMPTY_QUEUE)
  const [playing, setPlaying] = useState(false)
  const [buffering, setBuffering] = useState(false)
  const [duration, setDuration] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [airplay, setAirplay] = useState(false)
  const [gapless, setGaplessShown] = useState(readPlayerGapless)
  const [gaps, setGaps] = useState<GapReading[]>([])
  const [lastSeek, setLastSeek] = useState<SeekReading | null>(null)
  const [wrapped, setWrapped] = useState<Wrapped | null>(null)

  //? Everything the element's events and the lock screen's handlers read. They are set up once,
  //? so they read these rather than closing over a render's state.
  const engine = useMemo(() => {
    //? the page's element, and - once the gapless switch has been on - the second one
    const elements: AirPlayAudio[] = [createAudio()]
    const listeners = new Set<(seconds: number) => void>()
    const state = {
      queue: EMPTY_QUEUE as PlayQueue,
      //? Whether the listener means the music to be playing: set by anything that plays, cleared
      //? by a pause - asked for, or one nobody asked for, like a call coming in - and by the end
      //? of the queue. NOT audio.paused: a song that fails leaves the element paused while the
      //? listener still means it to play, and what follows - trying it again, moving on, and
      //? whether "next" plays - goes by what they meant, not by what the element is doing.
      intendsToPlay: false,
      //? this hearing of the song, for counting it as played - see Listen in lib/playQueue
      listen: NEW_LISTEN,
      //? for measuring what was heard: the last position seen and when (performance clock, ms),
      //? and whether the element sought since - see listenedStep()
      lastPosition: 0,
      lastAt: 0,
      seeked: false,
      //? a song that failed: whether it has been asked for again since it was loaded, the ask
      //? waiting to go, and where to pick up once it has loaded (0 for the top)
      retried: false,
      retryTimer: undefined as ReturnType<typeof setTimeout> | undefined,
      resumeAt: 0,
      //? which of `elements` is playing - always 0 with the switch never on
      active: 0 as ElementSlot,
      gapless: readPlayerGapless(),
      //? whether the second element has been through load() in a tap - iOS unlocks for good
      spareUnlocked: false,
      //? what the standby element holds or is getting, the wait before it starts getting it, and
      //? the download into memory under way
      standby: null as Standby | null,
      preloadTimer: undefined as ReturnType<typeof setTimeout> | undefined,
      download: null as AbortController | null,
      //? checkWrapped()'s two bytes, let go of at the next song: deadwax stops making an MP4 once
      //? nobody is waiting for it, and this would otherwise wait for every song skipped past
      wrapCheck: null as AbortController | null,
      //? the blob: address each element holds a song in memory by, handed back when it lets go
      memory: new Map<HTMLAudioElement, string>(),
      //? The song change being timed, from 'ended' until the next song's clock runs (clockStep()).
      //? Only a change that goes straight from one to the other is timed, so everything that
      //? means the music stopped - a pause, asked for or not, a refused play(), a failure that
      //? stops the queue - and anything the listener does, drops it.
      change: null as Change | null,
      //? a seek on its way: what the bar is told until the element says it has landed
      pendingSeek: null as PendingSeek | null,
      //? the last seek the listener made, for the readout - see seekStep() in lib/scrub
      seekReading: null as SeekReading | null,
      //? the one-stream engine's streams, by element - at most one each, only ever on the element playing
      streams: new Map<HTMLAudioElement, StreamSource>(),
      //? songs deadwax won't repackage (or whose stream failed to decode): never streamed again this
      //? page, and asked for as the file as it is, not in an MP4
      refused: new Set<string>(),
      //? songs only their format keeps out of a stream (hi-res, surround): never streamed, but still
      //? asked for in an MP4 by Safari - its seeks land there
      noStream: new Set<string>(),
      //? streaming is off until then (performance clock): deadwax's cache can't be used, or three
      //? streams in a row failed
      engineOffUntil: 0,
      failedStreams: 0,
      //? a pause between two 'timeupdate's: the wall clock across them is no measure of a join
      pausedSinceUpdate: false,
      //? when a 'waiting' on the stream began (performance clock), and the reading of a join still
      //? being decided - see crossInto()
      waitingAt: null as number | null,
      join: null as { stall: number; waitingAt: number | null } | null,
    }

    /** The element playing - or paused, or about to play. Everything the player does goes to it. */
    const live = (): AirPlayAudio => elements[state.active]!
    /** The other element, when there is one: the gapless switch's standby. */
    const other = (): AirPlayAudio | null => elements[state.active === 0 ? 1 : 0] ?? null

    /** The stream on the element playing, if it holds one. */
    const liveStream = (): StreamSource | null => state.streams.get(live()) ?? null
    /** Whether an element has anything to play: a src attribute, or a MediaSource as srcObject. */
    const hasSource = (element: HTMLAudioElement) => element.getAttribute('src') !== null || element.srcObject != null

    const canPlay = (type: string) => live().canPlayType(type) !== ''
    const isWireless = () => live().webkitCurrentPlaybackTargetIsWireless === true
    //? Safari, and every browser on an iPhone: FLAC songs are asked for inside an MP4, which is how
    //? its engine lands a seek where it was asked to - see lib/streamWrap. Decided once, for the page.
    const pageWraps = wrapsFlac({
      userAgent: typeof navigator !== 'undefined' ? navigator.userAgent ?? '' : '',
      maxTouchPoints: typeof navigator !== 'undefined' ? navigator.maxTouchPoints ?? 0 : 0,
      canPlayType: (type) => elements[0]!.canPlayType(type),
    })
    /** Where a song's audio is, for this page - see streamUrl(). A song deadwax won't repackage is
     *  asked for as it is: asking for an MP4 of it would only have deadwax try again and give up. */
    const addressOf = (track: QueueTrack) => streamUrl(track, canPlay, pageWraps && !state.refused.has(track.id))
    //? MediaSource with FLAC in an MP4, if the browser has it - decided once, for the page
    const engine = mediaSourceEngine()

    /** Whether a song can go in a stream now - see streamable() in lib/streamPlan. */
    function streamable(track: QueueTrack): boolean {
      return mayStream({
        gapless: state.gapless,
        engine: engine !== null,
        isFlac: isFlac(track),
        raw: streamFormat(track, canPlay) === 'raw',
        wireless: isWireless(),
        refused: state.refused.has(track.id) || state.noStream.has(track.id),
        engineOff: performance.now() < state.engineOffUntil,
      })
    }

    /** Where the current song starts in the live stream - 0 without one. Always the QUEUE's song, never
     *  the one under the playhead: between a join and the 'timeupdate' that sees it, positions run on
     *  past the song's end rather than jumping to 0 under the old title. */
    function songStart(): number {
      return liveStream()?.song(state.queue.index)?.start ?? 0
    }

    /** Seconds into the current song, stream or not. */
    function songPosition(): number {
      return Math.max(0, (live().currentTime || 0) - songStart())
    }

    /**
     * The song's length in seconds: the element's once it knows a real one, the tags' until then,
     * 0 when neither does. The element says NaN before it has read the file, and Infinity for a
     * stream sent with no Content-Length - a transcode - which would otherwise ask four minutes
     * of listening of every song before counting it, and leave the lock screen with no scrubber.
     */
    function songLength(): number {
      //? a stream's duration is everything appended so far, never the song: its own samples say
      const stream = liveStream()
      if (stream) return stream.song(state.queue.index)?.length ?? current(state.queue)?.duration ?? 0
      const own = live().duration
      if (Number.isFinite(own) && own > 0) return own
      return current(state.queue)?.duration ?? 0
    }

    function updatePositionState() {
      const audio = live()
      const media = session()
      const length = songLength()
      if (!media?.setPositionState || !(length > 0)) return
      try {
        media.setPositionState({
          duration: length,
          playbackRate: audio.playbackRate || 1,
          position: Math.min(songPosition(), length),
        })
      } catch {
        //? a position a moment past the end during a change of song - the next update fixes it
      }
    }

    function showOnLockScreen(track: QueueTrack) {
      const media = session()
      if (!media || typeof MediaMetadata === 'undefined') return
      const art = coverUrl(track.coverArt, 512)
      media.metadata = new MediaMetadata({
        title: track.title,
        artist: track.artist,
        album: track.album,
        artwork: art ? [{ src: new URL(art, location.href).href, sizes: '512x512' }] : [],
      })
    }

    /**
     * Whether the song now playing came inside an MP4, for the readout: an audio element never says
     * what type it was sent, and deadwax sends the FLAC as it is when it won't repackage a file. So
     * it is asked with two bytes, as Safari itself asks first - deadwax makes the MP4 once for both.
     *
     * The ask before is let go of first. deadwax keeps making an MP4 only while a request waits for
     * it, so skipping through songs stops the ones skipped past - but only if their asks go too.
     */
    function checkWrapped(track: QueueTrack) {
      state.wrapCheck?.abort()
      state.wrapCheck = null
      if (!asksForMp4(track, streamFormat(track, canPlay), pageWraps)) {
        setWrapped(null)
        return
      }
      const id = track.id
      const controller = new AbortController()
      state.wrapCheck = controller
      setWrapped({ id, got: null })
      fetch(addressOf(track), { headers: { Range: 'bytes=0-1' }, signal: controller.signal })
        .then((response) => {
          response.body?.cancel().catch(() => {})
          if (!response.ok) return
          const got = wrappedAs(response.headers.get('Content-Type'))
          setWrapped((shown) => (shown?.id === id ? { id, got } : shown))
        })
        .catch(() => {
          //? let go of (the song changed), or failed - the readout goes on saying it was asked
          //? for; the song itself is the element's business
        })
        .finally(() => {
          if (state.wrapCheck === controller) state.wrapCheck = null
        })
    }

    /** Tell whatever shows the position where the song is - or where a seek on its way is going. */
    function report(position: number) {
      const shown = reportedPosition(state.pendingSeek, position, performance.now())
      listeners.forEach((listener) => listener(shown))
    }

    /** The last seek's reading after `event`, and the readout told when it changed. */
    function readSeek(event: SeekEvent) {
      const next = seekStep(state.seekReading, event)
      if (next === state.seekReading) return
      state.seekReading = next
      setLastSeek(next)
    }

    /** A new hearing of the song: from a load, or a restart of the song already loaded. */
    function newListen() {
      state.listen = NEW_LISTEN
      state.lastPosition = 0
      state.lastAt = performance.now()
      state.seeked = false
    }

    /**
     * The song has begun playing - the first time in a listen is when it started, which is what
     * the play is reported as having happened at, and when Navidrome hears what's playing.
     */
    function beginListen() {
      const { listen, nowPlaying } = listenStarted(state.listen, Date.now())
      state.listen = listen
      const track = current(state.queue)
      if (track && nowPlaying) scrobble(track.id, false)
    }

    /** The ONE place a stream is taken off an element: whatever it is given next, or nothing. */
    function detach(element: HTMLAudioElement) {
      const stream = state.streams.get(element)
      if (!stream) return
      state.streams.delete(element)
      stream.close()
    }

    /** Give an element a source, handing back a blob: address it held a song in memory by. */
    function setSource(element: AirPlayAudio, src: string) {
      //? a MediaSource as srcObject beats the src attribute: it goes first, or this would be ignored
      detach(element)
      const held = state.memory.get(element)
      element.src = src
      if (held !== undefined && held !== src) {
        URL.revokeObjectURL(held)
        state.memory.delete(element)
      }
    }

    /** An element lets go of its song entirely - what it held in memory too. */
    function empty(element: AirPlayAudio) {
      detach(element)
      element.removeAttribute('src')
      element.load()
      const held = state.memory.get(element)
      if (held !== undefined) {
        URL.revokeObjectURL(held)
        state.memory.delete(element)
      }
    }

    /**
     * A new song on the element playing - the one-element way, and the only way with the switch off.
     * `gesture`: this comes from a tap or a lock-screen command, which is the only time a new stream
     * may start. Outside one - a song ending, a skip after a failure - a new MediaSource on the element
     * would have to open, fetch and append before iOS suspends a page that isn't playing, so those go
     * the URL way and the stream waits for the next tap.
     */
    function load(next: PlayQueue, autoplay: boolean, gesture = false) {
      const track = current(next)
      if (!track) return

      cancelRetry()
      state.queue = next
      state.retried = false
      state.resumeAt = 0
      newListen()

      setQueue(next)
      setDuration(track.duration)
      setError(null)
      state.pendingSeek = null
      readSeek({ kind: 'song change' })
      report(0)
      showOnLockScreen(track)

      state.join = null
      if (gesture && startStream(next)) {
        if (autoplay) play()
        state.wrapCheck?.abort()
        state.wrapCheck = null
        setWrapped({ id: track.id, got: 'stream' })
        fitStandby()
        return
      }
      setSource(live(), addressOf(track))
      if (autoplay) play()
      //? after the element's own request is on its way - the song comes first, the readout second
      checkWrapped(track)
      fitStandby()
    }

    /* ===== the one stream - see player/streamSource.ts ===== */

    /** Events from a stream, dropped unless it is still the stream on the element playing. */
    const streamEvents: StreamEvents = {
      runEnded(source) {
        if (state.streams.get(live()) !== source) return
        fitStandby()
        //? the song after the run needs every second it can get, if the queue is already at the end
        //? (after PRELOAD_DELAY_MS, like any other: the stream's own pieces have the connection first)
        const end = source.runEnd()
        if (end !== null && state.queue.index >= end) preloadSoon()
      },
      refused(source, index, _why, formatOnly) {
        const track = source.tracks[index]
        if (track) (formatOnly ? state.noStream : state.refused).add(track.id)
        if (state.streams.get(live()) === source) fitStandby()
      },
      failed(source, index, kind, why) {
        if (state.streams.get(live()) !== source) return
        streamFailed(source, index, kind, why)
      },
      engineOff() {
        state.engineOffUntil = performance.now() + ENGINE_OFF_MS
        state.failedStreams = 0
      },
    }

    /**
     * A new stream on the element playing, starting at the queue's song. False when this song can't
     * stream; the caller plays it the URL way. (A seek made before its first song's head is in is the
     * stream's to apply - see StreamSource.seekTo().)
     */
    function startStream(next: PlayQueue): boolean {
      const track = current(next)
      if (!engine || !track || !streamable(track)) return false
      const element = live()
      //? whatever the element held goes first - a stream, a song by address, a song in memory
      detach(element)
      const held = state.memory.get(element)
      if (held !== undefined) {
        URL.revokeObjectURL(held)
        state.memory.delete(element)
      }
      element.removeAttribute('src')
      element.muted = false
      const stream = new StreamSource(element, next.tracks, next.index, engine, {
        urlOf: fragmentedUrl,
        streamable,
        intendsToPlay: () => state.intendsToPlay,
      }, streamEvents)
      state.streams.set(element, stream)
      stream.attach()
      return true
    }

    /**
     * Next or previous to a song already placed in the live stream: a seek in it, no new source. The
     * same state as a song change, but a seek on its way until the element says it has landed.
     */
    function moveInStream(next: PlayQueue, autoplay: boolean): boolean {
      const stream = liveStream()
      const song = stream?.song(next.index)
      const track = current(next)
      if (!stream || !song || !track || !state.gapless || stream.tracks !== next.tracks) return false
      if (!stream.seekTo(next.index, 0)) return false
      cancelRetry()
      state.queue = next
      state.retried = false
      state.resumeAt = 0
      newListen()
      state.join = null
      setQueue(next)
      setDuration(song.length)
      setError(null)
      state.pendingSeek = { target: 0, since: performance.now() }
      readSeek({ kind: 'song change' })
      report(0)
      showOnLockScreen(track)
      setWrapped({ id: track.id, got: 'stream' })
      updatePositionState()
      const audio = live()
      //? no 'playing' comes for a seek into data already there while playing: the listen begins here
      if (!audio.paused && stream.isBuffered(next.index, 0)) beginListen()
      if (autoplay && audio.paused) play()
      fitStandby()
      //? into the run's last song: the song after the run is got ready, as a crossing into it would
      const end = stream.runEnd()
      if (end !== null && next.index >= end) preloadSoon()
      return true
    }

    /**
     * The stream can't go on for the song playing (a failure, AirPlay, the switch going off): that song
     * the URL way from where it had got to, on the same element. As the file as it is, never an MP4 of
     * it - deadwax relays that at once, where an MP4 might mean downloading and repackaging the whole
     * song first; the cost is only Safari's seek precision, for this one song. The listen carries on.
     * `usual`: the song's usual address instead (an MP4 for Safari) - for a song only its format kept
     * out of the stream, which has played nothing yet and whose seeks should land.
     */
    function leaveStream(position: number, usual = false) {
      const track = current(state.queue)
      if (!track) return
      const element = live()
      detach(element)
      state.join = null
      state.resumeAt = position
      state.wrapCheck?.abort()
      state.wrapCheck = null
      if (usual) {
        setSource(element, addressOf(track))
        checkWrapped(track)
      } else {
        setSource(element, streamUrl(track, canPlay, false))
        setWrapped(pageWraps && streamFormat(track, canPlay) === 'raw' && isFlac(track) ? { id: track.id, got: 'flac' } : null)
      }
      if (state.intendsToPlay) play()
      fitStandby()
    }

    /**
     * A stream that can't go on for the song at `index`. A song of its own that failed to decode or was
     * refused never streams again. A song AFTER the one playing moves the queue on to it, the URL way,
     * as a song change - but only with the playhead at the join, waiting on it; otherwise (the stream
     * says so for a later song only when it has to: a decode error, or nothing to go on with) the song
     * playing leaves the stream from where it had got to and plays on. Three failures without a join
     * played between them, and streaming stops for a while.
     */
    function streamFailed(source: StreamSource, index: number, kind: StreamFailure, why: string) {
      const failedTrack = source.tracks[index]
      if (failedTrack && (kind === 'decode' || kind === 'refused')) state.refused.add(failedTrack.id)
      if (failedTrack && kind === 'format') state.noStream.add(failedTrack.id)
      if (kind !== 'format') state.failedStreams += 1
      if (state.failedStreams >= 3) {
        state.engineOffUntil = performance.now() + ENGINE_OFF_MS
        state.failedStreams = 0
      }
      console.warn(`deadwax player: left the gapless stream at song ${index + 1} (${kind}): ${why}`)
      const atJoin = songPosition() >= songLength() - 0.5
      if (index > state.queue.index && source.tracks === state.queue.tracks && atJoin && kind !== 'decode') {
        load({ ...state.queue, index }, state.intendsToPlay)
        return
      }
      leaveStream(songPosition(), kind === 'format' && index === state.queue.index)
    }

    /**
     * The same song asked for again, on the same element - see onFailure(). A song held in memory
     * is asked for from Navidrome instead: if asking again is needed, the copy is what to doubt.
     */
    function reload() {
      //? load() on an element holding a MediaSource detaches it for good: leave the stream instead
      if (liveStream()) {
        leaveStream(songPosition())
        return
      }
      cancelRetry()
      setError(null)
      const audio = live()
      const track = current(state.queue)
      if (state.memory.has(audio) && track) setSource(audio, addressOf(track))
      else audio.load()
    }

    function cancelRetry() {
      if (state.retryTimer === undefined) return
      clearTimeout(state.retryTimer)
      state.retryTimer = undefined
      setBuffering(false)
    }

    /**
     * `refused`, for a handover: what to do if iOS won't start the standby - see handOver(). Any
     * other refusal of a play() is the element's, as it always was.
     */
    function play(refused?: () => void) {
      const audio = live()
      state.intendsToPlay = true
      //? play pressed on a song that has ended plays it again from the top: a new listen - and in a
      //? stream, "the top" is the song's start, not the stream's (which would be the run's first song)
      if (audio.ended) {
        newListen()
        liveStream()?.seekTo(state.queue.index, 0)
      }
      //? an element whose song failed stays failed until it is loaded again - play() alone is
      //? refused - so pressing play on one is asking for it again
      if (audio.error) reload()
      //? a stream paused for a while restarts its stuck clock now, while the element is still paused -
      //? a locked phone's timers may not have run since
      liveStream()?.tick()
      audio.play().catch((reason: unknown) => {
        const name = reason instanceof DOMException ? reason.name : ''
        //? AbortError is the previous load being replaced by a newer one, which is fine; and
        //? NotSupportedError is the song failing, which the element's 'error' deals with
        if (name === 'AbortError' || name === 'NotSupportedError') return
        //? the standby wouldn't start - and it is still the one playing, so nothing has moved on
        if (refused && audio === live()) {
          refused()
          return
        }
        setPlaying(false)
        setBuffering(false)
        if (name === 'NotAllowedError') {
          //? refused for want of a tap, so nothing is playing until there is one - and a song
          //? change it stopped is no gap to time
          state.intendsToPlay = false
          state.change = null
          setError('Tap play to start - this browser only plays audio from a tap')
        }
      })
    }

    function pause() {
      state.intendsToPlay = false
      //? a song change paused before it began playing isn't a gap worth timing
      state.change = null
      cancelRetry()
      live().pause()
      //? already paused, as a failed song leaves it, the element sends no 'pause' to say so
      const media = session()
      if (media) media.playbackState = 'paused'
    }

    /**
     * The element playing to `seconds`, clamped to the song; null with nothing loaded. Says what it
     * went to, and whether a 'seeked' will answer.
     *
     * Until it says it has landed, the bar is told the target (see reportedPosition()) - but only
     * for a seek that MOVES the element, which one still loading can't: before it has the song's
     * start (HAVE_NOTHING) the time is only kept as where to begin, and once it has, both engines
     * seek there only if it is past 0 (WebKit's setReadyState, and Chromium's). "Previous", or a
     * tap at the far left, on a song still loading would otherwise hold the bar at 0:00 for
     * PENDING_MAX_MS while the song played. A seek to where it already is moves nothing either.
     */
    function seek(seconds: number): { target: number; answered: boolean } | null {
      const audio = live()
      if (!hasSource(audio)) return null
      const stream = liveStream()
      if (stream) {
        //? in the stream: song-relative, clamped to the song's own length; the stream does the rest
        //? (fetching again what it no longer holds) and the element answers with 'seeked' once there
        const song = stream.song(state.queue.index)
        const target = Math.max(0, Math.min(seconds, song ? song.length : seconds))
        const loaded = audio.readyState >= HAVE_METADATA && song !== null
        const moves = loaded && target !== songPosition()
        if (!stream.seekTo(state.queue.index, target)) return null
        state.lastPosition = target
        state.pendingSeek = moves || (!loaded && target > 0) ? { target, since: performance.now() } : null
        report(target)
        return { target, answered: loaded || target > 0 }
      }
      const length = Number.isFinite(audio.duration) ? audio.duration : Infinity
      const target = Math.max(0, Math.min(seconds, length))
      const loaded = audio.readyState >= HAVE_METADATA
      const moves = loaded && target !== audio.currentTime
      audio.currentTime = target
      state.lastPosition = audio.currentTime
      state.pendingSeek = moves ? { target, since: performance.now() } : null
      report(target)
      //? a loaded element answers every seek with 'seeked', even to where it is; one still loading
      //? answers only a start past 0, when it gets there
      return { target, answered: loaded || target > 0 }
    }

    /** "Previous" early in a song: the song again from the top, heard - and counted - afresh. */
    function restart() {
      newListen()
      state.resumeAt = 0
      readSeek({ kind: 'other seek' })
      seek(0)
      //? no 'playing' follows a seek to a start that is already buffered, so a restart while
      //? playing begins its listen here
      if (!live().paused) beginListen()
    }

    /** "Skipped ..." in place of the artist's name for a while, unless something replaces it. */
    function showBriefly(message: string) {
      setError(message)
      setTimeout(() => setError((shown) => (shown === message ? null : shown)), SKIP_NOTICE_MS)
    }

    /* ===== the gapless switch's second element - see lib/gapless ===== */

    /** The second element, made the first time the switch is on and kept for the page's life. */
    function ensureSpare() {
      if (elements[1]) return
      const spare = createAudio()
      //? A muted element is never the lock screen's Now Playing (canShowControlsManager in
      //? WebKit), so the standby can't take the lock screen from the song playing.
      spare.muted = true
      elements.push(spare)
      attach(spare)
    }

    /**
     * iOS unlocks audio per element, from a tap, and for good: load() in a tap does it. So the
     * second element goes through load() in the first tap that plays - before the playing element
     * is started, so that one stays the element last touched - and in the tap that turns the
     * switch on. One that already holds a song needs none, and load() would only start it over.
     */
    function unlockSpare() {
      const spare = elements[1]
      if (!state.gapless || !spare || state.spareUnlocked) return
      state.spareUnlocked = true
      //? never load() an element holding something - on a MediaSource that detaches it for good
      if (!hasSource(spare)) spare.load()
    }

    function cancelPreload() {
      if (state.preloadTimer !== undefined) clearTimeout(state.preloadTimer)
      state.preloadTimer = undefined
      state.download?.abort()
      state.download = null
    }

    /** The standby lets go of whatever it holds or is getting. */
    function dropStandby() {
      cancelPreload()
      const standby = other()
      if (standby && hasSource(standby)) empty(standby)
      state.standby = null
    }

    /** What standbyPlan() needs to know of a live stream: where its run ends (null while unknown). */
    function liveRun(): { runEnd: number | null } | null {
      const stream = liveStream()
      return stream ? { runEnd: stream.runEnd() } : null
    }

    /**
     * The queue moved on: a standby holding any song but the one after the new one lets go of it,
     * and a wait to get one ready starts again from the new song's 'playing'.
     */
    function fitStandby() {
      if (state.preloadTimer !== undefined) clearTimeout(state.preloadTimer)
      state.preloadTimer = undefined
      const plan = standbyPlan(state.queue, state.gapless, state.standby, isWireless(), liveRun())
      if (plan.kind === 'clear' || (plan.kind === 'load' && state.standby)) dropStandby()
    }

    /**
     * A song has started playing: the one after it is got ready a moment from now. Never while
     * AirPlaying - standbyPlan() answers nothing to get ready then, as a handover can't happen.
     */
    function preloadSoon() {
      if (!state.gapless || state.preloadTimer !== undefined || isWireless()) return
      if (standbyPlan(state.queue, state.gapless, state.standby, false, liveRun()).kind !== 'load') return
      state.preloadTimer = setTimeout(() => {
        state.preloadTimer = undefined
        preloadNow()
      }, PRELOAD_DELAY_MS)
    }

    function preloadNow() {
      //? AirPlay may have begun during the wait
      const plan = standbyPlan(state.queue, state.gapless, state.standby, isWireless(), liveRun())
      if (plan.kind !== 'load') return
      dropStandby()
      ensureSpare()
      const element = other()
      if (!element) return
      element.muted = true
      const standby: Standby = { index: plan.index, id: plan.track.id, stage: 'fetching', failed: false }
      state.standby = standby
      void download(standby, element, plan.track)
    }

    /**
     * The next song, downloaded whole into memory and handed to the standby as a blob: address -
     * where it fits (memoryPlan()). An element left holding only an ADDRESS may have its buffer
     * thrown away on a locked phone, since a paused element in a hidden page is marked purgeable
     * in WebKit; a copy in memory is there whatever iOS does, and costs no trip to the server when
     * its turn comes. Anything that doesn't go into memory - too big, a download that failed -
     * hands the standby the address instead, to buffer as iOS allows; a transcode goes straight to
     * the address, never fetched. AirPlay beginning while it downloads lets the standby go
     * altogether (standbyPlan()).
     */
    async function download(standby: Standby, element: AirPlayAudio, track: QueueTrack) {
      const address = addressOf(track)
      const raw = streamFormat(track, canPlay) === 'raw'
      const controller = new AbortController()
      state.download = controller
      //? after every wait: still the standby's song, and nothing got ready for AirPlay
      const wanted = (): boolean => {
        if (state.standby !== standby) return false
        if (!isWireless()) return true
        dropStandby()
        return false
      }
      const byAddress = () => {
        if (!wanted()) return
        if (state.download === controller) state.download = null
        standby.stage = 'stream'
        setSource(element, address)
        element.load()
      }
      if (!wanted()) return
      //? A transcode never goes into memory (memoryPlan()), and that is known before asking: fetched
      //? only to be abandoned, it would start a transcode on Navidrome and throw it away, and the
      //? standby's own request would start a second.
      if (!raw) {
        byAddress()
        return
      }
      try {
        const response = await fetch(address, { signal: controller.signal })
        if (!wanted()) return
        const declared = response.headers.get('Content-Length')
        const contentLength = declared !== null && Number.isFinite(Number(declared)) ? Number(declared) : null
        const plan = memoryPlan({
          ok: response.ok,
          contentType: response.headers.get('Content-Type'),
          contentLength,
          raw,
        })
        if (plan === 'stream') {
          controller.abort()
          byAddress()
          return
        }
        const blob = contentLength !== null ? await response.blob() : await readCounted(response, controller)
        if (!wanted()) return
        if (!blob) {
          byAddress()
          return
        }
        state.download = null
        const kept = URL.createObjectURL(blob)
        setSource(element, kept)
        state.memory.set(element, kept)
        element.load()
        standby.stage = 'memory'
      } catch {
        //? let go of (the standby moved on, and this was aborted), or the download failed - then
        //? the element can have a go itself, and says so with an error if it can't
        byAddress()
      }
    }

    /** A download that didn't say its size, read to the end - or null, abandoned, past the limit. */
    async function readCounted(response: Response, controller: AbortController): Promise<Blob | null> {
      const type = response.headers.get('Content-Type') ?? ''
      if (!response.body) return response.blob()
      const reader = response.body.getReader()
      const parts: BlobPart[] = []
      let received = 0
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        received += value.byteLength
        if (overMemoryMax(received)) {
          controller.abort()
          return null
        }
        parts.push(value as BlobPart)
      }
      return new Blob(parts, { type })
    }

    /**
     * Move to `next` by starting the standby, if it holds exactly that song - handoverDecision()
     * says. The swap happens in this turn, and play() on the standby is called in it: from 'ended'
     * that is inside the second WebKit allows after a song ends, and the standby was unlocked by a
     * tap anyway. Anything else is left to the caller, which loads the song the one-element way.
     *
     * Also says, for timing the change, the incoming element's readyState (for a handover of what
     * it held) and where its clock starts from.
     */
    function handOver(next: PlayQueue, autoplay: boolean): { decision: HandoverDecision; readyState: number | null; from: number } {
      const incoming = other()
      const decision = handoverDecision({
        enabled: state.gapless, standby: state.standby, queue: next, index: next.index, autoplay, wireless: isWireless(),
      })
      const track = current(next)
      if (decision.kind !== 'handover' || !incoming || !track) return { decision, readyState: null, from: 0 }

      const outgoing = live()
      cancelRetry()
      //? aborts a download still under way - 'unfinished' plays the song from its address instead
      cancelPreload()
      if (decision.source === 'unfinished') setSource(incoming, addressOf(track))
      //? what it held, when it held something: whether iOS kept it - see describeHow()
      const readyState = decision.source === 'unfinished' ? null : incoming.readyState
      const from = incoming.currentTime || 0
      state.standby = null
      state.active = activeAfter(state.active, 'handover')
      //? muted before anything else touches it, so the lock screen never takes the element that
      //? has finished for the song playing
      outgoing.muted = true
      incoming.muted = false

      state.queue = next
      state.retried = false
      state.resumeAt = 0
      newListen()
      setQueue(next)
      setDuration(songLength())
      setError(null)
      state.pendingSeek = null
      readSeek({ kind: 'song change' })
      report(0)
      showOnLockScreen(track)

      play(() => refusedHandover(next))
      checkWrapped(track)
      //? the element that finished lets go of its song, and becomes the next song's standby
      empty(outgoing)
      return { decision, readyState, from }
    }

    /**
     * iOS wouldn't start the standby. The song goes on the element that was playing, which a tap
     * unlocked long ago - the one-element way, straight away, so the music doesn't stop over it.
     */
    function refusedHandover(at: PlayQueue) {
      if (state.queue !== at) return
      const refused = live()
      state.active = activeAfter(state.active, 'refused')
      refused.muted = true
      live().muted = false
      empty(refused)
      if (state.change) {
        state.change = { ...state.change, how: { kind: 'same element', reason: 'refused' }, readyState: null, from: 0 }
      }
      load(at, true)
    }

    /**
     * A 'timeupdate' from the element playing, while a song change is timed: the change ends when
     * the incoming song's clock is seen running - see clockStep() - and the readout gets it.
     */
    function timeChange(update: ClockUpdate) {
      if (!state.change) return
      const step = clockStep(state.change, update)
      if (step.kind === 'wait') {
        state.change = step.change
        return
      }
      state.change = null
      if (step.kind === 'reading') {
        const { reading } = step
        setGaps((shown) => withReading(shown, reading))
      }
    }

    const actions = {
      playTracks(tracks: QueueTrack[], start: number | null, shuffle = false) {
        state.change = null
        //? before load() starts the song: the tap unlocks the second element as well
        unlockSpare()
        load(startQueue(tracks, start, shuffle), true, true)
      },
      toggle() {
        const audio = live()
        if (!hasSource(audio)) return
        //? a failed song shows play whether or not the browser counts the element as paused,
        //? and pressing it asks for the song again
        if (audio.paused || audio.error) {
          //? the music had stopped, so whatever started it again is this tap, not a song change
          state.change = null
          unlockSpare()
          play()
        } else pause()
      },
      //? next and previous play if the listener meant the music to be playing - which a song
      //? that just failed leaves audio.paused saying it isn't
      next() {
        const index = nextIndex(state.queue)
        if (index === null) return
        state.change = null
        unlockSpare()
        const next = { ...state.queue, index }
        //? a song already in the stream is a seek in it; otherwise as ever - and, being a tap or a
        //? lock-screen command, free to start a stream
        if (moveInStream(next, state.intendsToPlay)) return
        if (handOver(next, state.intendsToPlay).decision.kind === 'handover') return
        load(next, state.intendsToPlay, true)
      },
      previous() {
        const action = previousAction(state.queue, songPosition())
        state.change = null
        unlockSpare()
        if (action.kind === 'restart') {
          restart()
          return
        }
        const previous = { ...state.queue, index: action.index }
        if (moveInStream(previous, state.intendsToPlay)) return
        load(previous, state.intendsToPlay, true)
      },
      //? the scrubber and the lock screen's: a seek the listener made, during a song change, ends
      //? its timing - the position it jumps to isn't the clock running - and is the one the readout
      //? follows to its song's end, to say where it really landed. One no 'seeked' will answer - to
      //? the top of a song still loading, where it starts anyway - is nothing to follow, but it does
      //? take the place of any seek before it.
      seek(seconds: number) {
        state.change = null
        state.join = null
        const sought = seek(seconds)
        const track = current(state.queue)
        if (!sought || !track) return
        if (sought.answered) readSeek({ kind: 'asked', asked: sought.target, length: songLength(), track: track.id })
        else readSeek({ kind: 'other seek' })
      },
      showAirPlay() {
        //? A stream can't go to AirPlay (a ManagedMediaSource only opens with remote playback turned
        //? off), so the song playing leaves it first, in this same tap - the picker needs one. On a Mac
        //? the picker also wants the song loaded, so there it takes a second tap.
        if (liveStream()) leaveStream(songPosition())
        live().webkitShowPlaybackTargetPicker?.()
      },
      setGapless(on: boolean) {
        if (on === state.gapless) return
        state.gapless = on
        writePlayerGapless(on)
        setGaplessShown(on)
        if (on) {
          ensureSpare()
          //? this tap unlocks it, if no tap has yet
          unlockSpare()
          if (!live().paused) preloadSoon()
          return
        }
        //? the stream is the switch's: the song playing leaves it where it is, on the listener's own tap
        if (liveStream()) leaveStream(songPosition())
        //? one element from here on - whichever is playing now - and the other lets go
        state.active = activeAfter(state.active, 'switch off')
        dropStandby()
      },
      position: () => songPosition(),
      onPosition(listener: (seconds: number) => void) {
        listeners.add(listener)
        return () => listeners.delete(listener)
      },
    }

    function onTimeUpdate() {
      const audio = live()
      const at = performance.now()
      const stream = liveStream()
      stream?.tick()
      //? the clock ran into the next song of the stream: a song change, seen here - never while a seek
      //? is on its way, when the clock may still say where the element was
      if (stream && !audio.seeking && !state.pendingSeek && !state.seeked) {
        const song = stream.songAt(audio.currentTime)
        if (song && song.index > state.queue.index) {
          crossInto(stream, song, at)
          return
        }
      }
      if (state.join && state.join.waitingAt === null) {
        //? an update after the join with no stall between: the join played through
        const reading = streamReading(state.join.stall)
        setGaps((shown) => withReading(shown, reading))
        state.join = null
      }
      const position = stream ? songPosition() : audio.currentTime
      state.pausedSinceUpdate = false
      timeChange({ position: audio.currentTime, at, playbackRate: audio.playbackRate, seeked: state.seeked })
      const step = listenedStep({
        previous: state.lastPosition,
        now: position,
        elapsed: (at - state.lastAt) / 1000,
        rate: audio.playbackRate,
        seeked: state.seeked,
      })
      state.lastPosition = position
      state.lastAt = at
      state.seeked = false
      report(position)
      readSeek({ kind: 'clock', position, at })

      const { listen, submit } = listenHeard(state.listen, step, songLength())
      state.listen = listen
      const track = current(state.queue)
      if (track && submit) scrobble(track.id, true, listen.startedAt)
    }

    /**
     * The stream's clock has run into `song`: a song change with nothing starting. The song before
     * is finished first - the last of its listening counted and, if that makes it a play, told to
     * Navidrome under ITS id - then the new one begins, with what was already heard of it counted
     * once. A song passed wholly between two updates is never current and gets no "now playing".
     * The join is read for the readout: 0 ms when it played through (the lab's wall-against-media
     * estimate as a floor), or the stall, when the playhead waited at it for data.
     */
    function crossInto(stream: StreamSource, song: RunSong, at: number) {
      const audio = live()
      const old = stream.song(state.queue.index)
      const oldTrack = current(state.queue)
      const now = Math.max(0, audio.currentTime - song.start)
      const rate = audio.playbackRate
      const split = splitAcrossJoin({
        previous: state.lastPosition,
        oldLength: old?.length ?? 0,
        now,
        elapsed: (at - state.lastAt) / 1000,
        rate,
        seeked: state.seeked,
      })
      if (old && oldTrack) {
        const { listen, submit } = listenHeard(state.listen, split.before, old.length)
        state.listen = listen
        if (submit) scrobble(oldTrack.id, true, listen.startedAt)
      }
      const media = (old ? Math.max(0, old.length - state.lastPosition) : 0) + now
      const stall = state.pausedSinceUpdate || state.seeked ? 0 : joinStallMs({ elapsedMs: at - state.lastAt, media, rate })
      state.join = { stall, waitingAt: state.waitingAt }

      const next = { ...state.queue, index: song.index }
      const track = current(next)!
      cancelRetry()
      state.queue = next
      state.retried = false
      state.resumeAt = 0
      state.listen = listenHeard(NEW_LISTEN, split.after, song.length).listen
      state.lastPosition = now
      state.lastAt = at
      state.seeked = false
      state.pausedSinceUpdate = false
      //? a join played: the stream works, whatever went wrong before
      state.failedStreams = 0
      setQueue(next)
      setDuration(song.length)
      setError(null)
      state.pendingSeek = null
      readSeek({ kind: 'song change' })
      report(now)
      showOnLockScreen(track)
      updatePositionState()
      setWrapped({ id: track.id, got: 'stream' })
      beginListen()
      fitStandby()
      const end = stream.runEnd()
      if (end !== null && song.index >= end) preloadNow()
    }

    function onEnded() {
      //? a stream ends only at its run's end: a last song too short for any update to have seen it
      //? become current is made current first, or the song after it would be the one played again
      const stream = liveStream()
      const end = stream?.runEnd() ?? null
      if (stream && end !== null && state.queue.index < end) {
        const last = stream.song(end)
        if (last) crossInto(stream, last, performance.now())
      }
      //? before anything moves on: where the clock was when the audio ran out judges the last seek
      const ended = live()
      readSeek({ kind: 'ended', position: songPosition(), at: performance.now(), rate: ended.playbackRate })
      const index = nextIndex(state.queue)
      if (index === null) {
        state.change = null
        state.intendsToPlay = false
        setPlaying(false)
        const media = session()
        if (media) media.playbackState = 'paused'
        return
      }
      //? timed from here to the next song's clock running, with the switch on or off - the readout
      const endedAt = performance.now()
      const next = { ...state.queue, index }
      //? The moment that matters on a locked phone, straight away either way: the standby
      //? started, or the same element given the next song's source. (A handover iOS refuses
      //? says so later, from play()'s promise - see refusedHandover().)
      const moved = handOver(next, true)
      //? a new source starts its clock at 0, so `from` is 0 the one-element way
      state.change = startChange(endedAt, moved.decision, moved.readyState, moved.from)
      if (moved.decision.kind === 'handover') return
      load(next, true)
    }

    /**
     * The song won't play. What to do about it is afterFailure()'s to say: ask again once for a
     * song that failed to load, then move on to the next as a song ending does - on the same
     * element and straight away, since on a locked phone nothing else will - and stop at the end
     * of the queue, or when nobody meant it to be playing. A song playing from memory is asked
     * for from Navidrome at once instead (afterPlaybackFailure()).
     */
    function onFailure() {
      const audio = live()
      //? an element with no source reports an error too, which is not one worth showing - nor does an
      //? error event whose error a newer load has already cleared
      if (!hasSource(audio) || !audio.error) return
      //? a stream's failure: the stream usually said first, naming the song it was appending; if not,
      //? the song playing is the one to take out of it
      const stream = liveStream()
      if (stream) {
        streamFailed(stream, state.queue.index, 'decode', describeMediaError(audio.error))
        return
      }
      const failed = current(state.queue)
      //? a seek on its way never lands in a song that failed under it
      state.pendingSeek = null
      readSeek({ kind: 'failed' })
      const action = afterPlaybackFailure({
        queue: state.queue,
        code: audio.error?.code ?? 0,
        intendsToPlay: state.intendsToPlay,
        retried: state.retried,
        fromMemory: state.memory.has(audio),
      })
      const media = session()
      setPlaying(false)
      setBuffering(false)
      //? the song the change went to failed before its clock moved: whatever the time comes to,
      //? it includes getting over that, and the readout says so
      if (state.change) state.change = { ...state.change, failed: true }

      if (action.kind === 'stream') {
        //? the copy in memory is what failed: the same song from Navidrome, where it stopped
        state.resumeAt = audio.currentTime || 0
        reload()
        play()
        return
      }

      if (action.kind === 'retry') {
        state.retried = true
        //? a song that stopped part-way picks up where it stopped - see 'loadedmetadata'
        state.resumeAt = audio.currentTime || 0
        setError(describeMediaError(audio.error))
        //? still meant to be playing, and about to be again: the lock screen keeps saying so
        setBuffering(true)
        if (media) media.playbackState = 'playing'
        state.retryTimer = setTimeout(() => {
          state.retryTimer = undefined
          if (state.intendsToPlay) play()
        }, LOAD_RETRY_DELAY_MS)
        return
      }

      if (action.kind === 'skip') {
        //? named before load() replaces the source, and with it the element's error
        const notice = skipNotice(failed?.title ?? 'a song', audio.error)
        load({ ...state.queue, index: action.index }, true)
        showBriefly(notice)
        return
      }

      state.intendsToPlay = false
      //? the music has stopped: a tap starting it again later is no song change
      state.change = null
      setError(describeMediaError(audio.error))
      if (media) media.playbackState = 'paused'
    }

    /** The standby's song won't load: when its turn comes, it goes the one-element way. */
    function onStandbyError(element: AirPlayAudio) {
      //? an element with no source reports an error too - the standby being emptied
      if (!hasSource(element) || !state.standby) return
      state.standby.failed = true
    }

    const events: [string, EventListener][] = [
      ['play', () => {
        //? the element playing again by itself - iOS carrying on after a call - is wanted too
        if (!live().paused) state.intendsToPlay = true
        setPlaying(true)
        const media = session()
        if (media) media.playbackState = 'playing'
        updatePositionState()
      }],
      ['pause', () => {
        //? A pause nobody here asked for - a call coming in, headphones coming out - means the
        //? listener has stopped listening, so a song failing now must not start the music
        //? again. One that comes with the song ending or failing (Chromium sends a 'pause' after
        //? the 'error', with the error already set) is the player's to deal with, and doesn't.
        const audio = live()
        if (audio.paused && !audio.ended && !audio.error) {
          state.intendsToPlay = false
          //? and a song change it interrupted - a call arriving at the change - isn't a gap
          state.change = null
        }
        //? any pause but the song's end (which sends one before 'ended') stops the wall clock
        //? being a measure of how long the song played on past its clock
        if (!audio.ended) readSeek({ kind: 'paused' })
        state.pausedSinceUpdate = true
        state.join = null
        setPlaying(false)
        const media = session()
        if (media && !state.intendsToPlay) media.playbackState = 'paused'
        updatePositionState()
      }],
      ['playing', () => {
        setBuffering(false)
        //? a join the stream stalled at: its reading is the stall, now it is over
        if (state.join?.waitingAt != null) {
          const reading = streamReading(Math.max(0, Math.round(performance.now() - state.join.waitingAt)))
          setGaps((shown) => withReading(shown, reading))
          state.join = null
        }
        state.waitingAt = null
        const stream = liveStream()
        //? a stream playing works: failures before it weren't "in a row"
        if (stream) state.failedStreams = 0
        stream?.tick()
        //? with no seek in flight, none is on its way - the second guard, as at 'loadedmetadata'
        if (!live().seeking) state.pendingSeek = null
        beginListen()
        //? NOT the end of a timed song change: WebKit sends 'playing' from inside play() for an
        //? element with data, before any sound - the change ends on the clock (timeChange())
        preloadSoon()
      }],
      ['loadedmetadata', () => {
        //? A second guard: with no seek in flight, none is on its way. seek() only waits on a seek
        //? the element can answer and a failure lets go of it, so nothing should be left by now -
        //? but one left over a new load would never land, and would hold the bar for PENDING_MAX_MS.
        if (!live().seeking) state.pendingSeek = null
        //? a song asked for again after it failed part-way picks up where it stopped
        if (state.resumeAt > 0) {
          const at = state.resumeAt
          state.resumeAt = 0
          readSeek({ kind: 'other seek' })
          seek(at)
        }
      }],
      ['waiting', () => {
        setBuffering(true)
        if (!liveStream()) return
        const at = performance.now()
        state.waitingAt = at
        //? a stall right at a join - WebKit's 'timeupdate' comes just before the 'waiting', so the join
        //? is usually seen first - belongs to the join's reading
        if (state.join && state.join.waitingAt === null && songPosition() < 0.3) state.join.waitingAt = at
      }],
      ['canplay', () => setBuffering(false)],
      ['timeupdate', onTimeUpdate],
      ['durationchange', () => {
        const audio = live()
        //? a stream's duration grows with every append and is never the song's
        if (liveStream()) setDuration(songLength())
        else if (Number.isFinite(audio.duration) && audio.duration > 0) setDuration(audio.duration)
        updatePositionState()
      }],
      //? every seek, whoever asked for it - the scrubber, the lock screen, "previous" restarting -
      //? so the jump it makes is never counted as listening
      ['seeking', () => {
        state.seeked = true
        state.join = null
      }],
      //? Landed. The bar goes back to the element's own clock - unless another seek has gone out
      //? since, which is still on its way. That clock is what the readout calls "the player said":
      //? Safari's says the time asked for even when it lands elsewhere (see lib/scrub).
      ['seeked', () => {
        const audio = live()
        if (audio.seeking) return
        state.pendingSeek = null
        readSeek({ kind: 'seeked', position: songPosition() })
        report(songPosition())
        updatePositionState()
      }],
      ['ended', onEnded],
      ['error', onFailure],
      //? from either element, each keeping its own answer - see routeEvent() and airplayShown()
      ['webkitplaybacktargetavailabilitychanged', () => {}],
      //? AirPlay starting or stopping: a standby is let go of while it plays there, and the next
      //? song got ready again once it stops - see standbyPlan()
      ['webkitcurrentplaybacktargetiswirelesschanged', () => {
        fitStandby()
        if (!live().paused) preloadSoon()
      }],
    ]

    //? each element's listeners, each asking routeEvent() whether its event counts
    const attached = new Map<AirPlayAudio, [string, EventListener][]>()
    //? each element's last word on whether an AirPlay device is there
    const airplayAnswers = new Map<AirPlayAudio, boolean>()
    let mounted = false

    function attach(element: AirPlayAudio) {
      if (!mounted || attached.has(element)) return
      const routed: [string, EventListener][] = events.map(([name, handler]) => [name, (event: Event) => {
        const route = routeEvent(name, element === live())
        if (route === 'player') handler(event)
        else if (route === 'standby') onStandbyError(element)
        else if (route === 'availability') {
          //? With remote playback off (a stream) WebKit stops watching for devices on the element and
          //? sends one last 'not-available' - about itself, not the network. Its answer from before stands.
          if (element.disableRemotePlayback) return
          airplayAnswers.set(element, (event as AvailabilityEvent).availability === 'available')
          setAirplay(airplayShown(airplayAnswers.values()))
        }
      }])
      routed.forEach(([name, listener]) => element.addEventListener(name, listener))
      attached.set(element, routed)
    }

    function mount(): () => void {
      mounted = true
      elements.forEach(attach)
      return () => {
        attached.forEach((routed, element) => routed.forEach(([name, listener]) => element.removeEventListener(name, listener)))
        attached.clear()
        state.streams.forEach((stream) => stream.close())
        state.streams.clear()
        state.wrapCheck?.abort()
        state.wrapCheck = null
        mounted = false
      }
    }

    //? a switch left on from before: the second element exists from the start, unlocked by the first tap
    if (state.gapless) ensureSpare()

    const handlers: [MediaSessionAction, MediaSessionActionHandler][] = [
      ['play', () => {
        if (!hasSource(live())) return
        //? the lock screen's play, as toggle(): the listener starting the music, not a song change
        state.change = null
        play()
      }],
      ['pause', () => pause()],
      ['previoustrack', () => actions.previous()],
      ['nexttrack', () => actions.next()],
      ['seekto', (details) => {
        if (details.seekTime != null) actions.seek(details.seekTime)
      }],
      //? NOT seekbackward/seekforward - on iOS they take the place of previous and next
    ]

    return { mount, handlers, actions }
  }, [])

  useEffect(() => {
    const { mount, handlers } = engine
    const unmount = mount()

    const media = session()
    for (const [action, handler] of handlers) {
      try {
        media?.setActionHandler(action, handler)
      } catch {
        //? an action this browser doesn't know - it simply won't be offered
      }
    }

    return () => {
      unmount()
      for (const [action] of handlers) {
        try {
          media?.setActionHandler(action, null)
        } catch {
          // as above
        }
      }
    }
  }, [engine])

  return {
    queue,
    track: current(queue),
    playing,
    buffering,
    duration,
    error,
    airplay,
    gapless,
    gaps,
    lastSeek,
    wrapped,
    ...engine.actions,
  }
}

/** The playing position, re-rendering only whatever calls this - several times a second. */
export function usePosition(player: Player): number {
  const [position, setPosition] = useState(() => player.position())
  useEffect(() => player.onPosition(setPosition), [player.onPosition])
  return position
}
