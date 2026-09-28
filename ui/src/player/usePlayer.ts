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
 * The position changes several times a second, so it is not React state - rendering the whole
 * player four times a second to move one bar would be waste. Whatever shows it subscribes with
 * usePosition() below, and only that re-renders.
 */

import { useEffect, useMemo, useState } from 'preact/hooks'

import {
  EMPTY_QUEUE, LOAD_RETRY_DELAY_MS, MEDIA_ERR_DECODE, NEW_LISTEN, afterFailure, current, listenHeard,
  listenStarted, listenedStep, nextIndex, previousAction, startQueue, type PlayQueue, type QueueTrack,
} from '../lib/playQueue'
import { coverUrl, scrobble, streamUrl } from './api'

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
  /** `start` null with shuffle: no song in particular - see startQueue() */
  playTracks(tracks: QueueTrack[], start: number | null, shuffle?: boolean): void
  toggle(): void
  next(): void
  previous(): void
  seek(seconds: number): void
  showAirPlay(): void
  /** the element's position, and a way to hear about it changing - see usePosition() */
  position(): number
  onPosition(listener: (seconds: number) => void): () => void
}

/** Safari's AirPlay additions to the media element, which the DOM types don't carry. */
interface AirPlayAudio extends HTMLAudioElement {
  webkitShowPlaybackTargetPicker?: () => void
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

  //? Everything the element's events and the lock screen's handlers read. They are set up once,
  //? so they read these rather than closing over a render's state.
  const engine = useMemo(() => {
    const audio = createAudio()
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
    }

    const canPlay = (type: string) => audio.canPlayType(type) !== ''

    /**
     * The song's length in seconds: the element's once it knows a real one, the tags' until then,
     * 0 when neither does. The element says NaN before it has read the file, and Infinity for a
     * stream sent with no Content-Length - a transcode - which would otherwise ask four minutes
     * of listening of every song before counting it, and leave the lock screen with no scrubber.
     */
    function songLength(): number {
      const own = audio.duration
      if (Number.isFinite(own) && own > 0) return own
      return current(state.queue)?.duration ?? 0
    }

    function updatePositionState() {
      const media = session()
      const length = songLength()
      if (!media?.setPositionState || !(length > 0)) return
      try {
        media.setPositionState({
          duration: length,
          playbackRate: audio.playbackRate || 1,
          position: Math.min(audio.currentTime, length),
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

    function load(next: PlayQueue, autoplay: boolean) {
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
      listeners.forEach((listener) => listener(0))
      showOnLockScreen(track)

      audio.src = streamUrl(track, canPlay)
      if (autoplay) play()
    }

    /** The same song asked for again, on the same element - see onFailure(). */
    function reload() {
      cancelRetry()
      setError(null)
      audio.load()
    }

    function cancelRetry() {
      if (state.retryTimer === undefined) return
      clearTimeout(state.retryTimer)
      state.retryTimer = undefined
      setBuffering(false)
    }

    function play() {
      state.intendsToPlay = true
      //? play pressed on a song that has ended plays it again from the top: a new listen
      if (audio.ended) newListen()
      //? an element whose song failed stays failed until it is loaded again - play() alone is
      //? refused - so pressing play on one is asking for it again
      if (audio.error) reload()
      audio.play().catch((reason: unknown) => {
        const name = reason instanceof DOMException ? reason.name : ''
        //? AbortError is the previous load being replaced by a newer one, which is fine; and
        //? NotSupportedError is the song failing, which the element's 'error' deals with
        if (name === 'AbortError' || name === 'NotSupportedError') return
        setPlaying(false)
        setBuffering(false)
        if (name === 'NotAllowedError') {
          //? refused for want of a tap, so nothing is playing until there is one
          state.intendsToPlay = false
          setError('Tap play to start - this browser only plays audio from a tap')
        }
      })
    }

    function pause() {
      state.intendsToPlay = false
      cancelRetry()
      audio.pause()
      //? already paused, as a failed song leaves it, the element sends no 'pause' to say so
      const media = session()
      if (media) media.playbackState = 'paused'
    }

    function seek(seconds: number) {
      if (!audio.src) return
      const length = Number.isFinite(audio.duration) ? audio.duration : Infinity
      audio.currentTime = Math.max(0, Math.min(seconds, length))
      state.lastPosition = audio.currentTime
      listeners.forEach((listener) => listener(audio.currentTime))
    }

    /** "Previous" early in a song: the song again from the top, heard - and counted - afresh. */
    function restart() {
      newListen()
      state.resumeAt = 0
      seek(0)
      //? no 'playing' follows a seek to a start that is already buffered, so a restart while
      //? playing begins its listen here
      if (!audio.paused) beginListen()
    }

    /** "Skipped ..." in place of the artist's name for a while, unless something replaces it. */
    function showBriefly(message: string) {
      setError(message)
      setTimeout(() => setError((shown) => (shown === message ? null : shown)), SKIP_NOTICE_MS)
    }

    const actions = {
      playTracks(tracks: QueueTrack[], start: number | null, shuffle = false) {
        load(startQueue(tracks, start, shuffle), true)
      },
      toggle() {
        if (!audio.src) return
        //? a failed song shows play whether or not the browser counts the element as paused,
        //? and pressing it asks for the song again
        if (audio.paused || audio.error) play()
        else pause()
      },
      //? next and previous play if the listener meant the music to be playing - which a song
      //? that just failed leaves audio.paused saying it isn't
      next() {
        const index = nextIndex(state.queue)
        if (index !== null) load({ ...state.queue, index }, state.intendsToPlay)
      },
      previous() {
        const action = previousAction(state.queue, audio.currentTime)
        if (action.kind === 'restart') restart()
        else load({ ...state.queue, index: action.index }, state.intendsToPlay)
      },
      seek,
      showAirPlay() {
        audio.webkitShowPlaybackTargetPicker?.()
      },
      position: () => audio.currentTime || 0,
      onPosition(listener: (seconds: number) => void) {
        listeners.add(listener)
        return () => listeners.delete(listener)
      },
    }

    function onTimeUpdate() {
      const position = audio.currentTime
      const at = performance.now()
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
      listeners.forEach((listener) => listener(position))

      const { listen, submit } = listenHeard(state.listen, step, songLength())
      state.listen = listen
      const track = current(state.queue)
      if (track && submit) scrobble(track.id, true, listen.startedAt)
    }

    function onEnded() {
      const index = nextIndex(state.queue)
      if (index === null) {
        state.intendsToPlay = false
        setPlaying(false)
        const media = session()
        if (media) media.playbackState = 'paused'
        return
      }
      //? the moment that matters on a locked phone: same element, new source, straight away
      load({ ...state.queue, index }, true)
    }

    /**
     * The song won't play. What to do about it is afterFailure()'s to say: ask again once for a
     * song that failed to load, then move on to the next as a song ending does - on the same
     * element and straight away, since on a locked phone nothing else will - and stop at the end
     * of the queue, or when nobody meant it to be playing.
     */
    function onFailure() {
      //? an element with no source reports an error too, which is not one worth showing
      if (!audio.src) return
      const failed = current(state.queue)
      const action = afterFailure({
        queue: state.queue,
        code: audio.error?.code ?? 0,
        intendsToPlay: state.intendsToPlay,
        retried: state.retried,
      })
      const media = session()
      setPlaying(false)
      setBuffering(false)

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
      setError(describeMediaError(audio.error))
      if (media) media.playbackState = 'paused'
    }

    const events: [string, EventListener][] = [
      ['play', () => {
        //? the element playing again by itself - iOS carrying on after a call - is wanted too
        if (!audio.paused) state.intendsToPlay = true
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
        if (audio.paused && !audio.ended && !audio.error) state.intendsToPlay = false
        setPlaying(false)
        const media = session()
        if (media && !state.intendsToPlay) media.playbackState = 'paused'
        updatePositionState()
      }],
      ['playing', () => {
        setBuffering(false)
        beginListen()
      }],
      ['loadedmetadata', () => {
        //? a song asked for again after it failed part-way picks up where it stopped
        if (state.resumeAt > 0) {
          const at = state.resumeAt
          state.resumeAt = 0
          seek(at)
        }
      }],
      ['waiting', () => setBuffering(true)],
      ['canplay', () => setBuffering(false)],
      ['timeupdate', onTimeUpdate],
      ['durationchange', () => {
        if (Number.isFinite(audio.duration) && audio.duration > 0) setDuration(audio.duration)
        updatePositionState()
      }],
      //? every seek, whoever asked for it - the scrubber, the lock screen, "previous" restarting -
      //? so the jump it makes is never counted as listening
      ['seeking', () => {
        state.seeked = true
      }],
      ['seeked', updatePositionState],
      ['ended', onEnded],
      ['error', onFailure],
      ['webkitplaybacktargetavailabilitychanged', (event) => {
        setAirplay((event as AvailabilityEvent).availability === 'available')
      }],
    ]

    const handlers: [MediaSessionAction, MediaSessionActionHandler][] = [
      ['play', () => {
        if (audio.src) play()
      }],
      ['pause', () => pause()],
      ['previoustrack', () => actions.previous()],
      ['nexttrack', () => actions.next()],
      ['seekto', (details) => {
        if (details.seekTime != null) seek(details.seekTime)
      }],
      //? NOT seekbackward/seekforward - on iOS they take the place of previous and next
    ]

    return { audio, events, handlers, actions }
  }, [])

  useEffect(() => {
    const { audio, events, handlers } = engine
    events.forEach(([name, handler]) => audio.addEventListener(name, handler))

    const media = session()
    for (const [action, handler] of handlers) {
      try {
        media?.setActionHandler(action, handler)
      } catch {
        //? an action this browser doesn't know - it simply won't be offered
      }
    }

    return () => {
      events.forEach(([name, handler]) => audio.removeEventListener(name, handler))
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
    ...engine.actions,
  }
}

/** The playing position, re-rendering only whatever calls this - several times a second. */
export function usePosition(player: Player): number {
  const [position, setPosition] = useState(() => player.position())
  useEffect(() => player.onPosition(setPosition), [player.onPosition])
  return position
}
