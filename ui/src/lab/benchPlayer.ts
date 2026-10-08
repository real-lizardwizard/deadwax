/**
 * The test bench's player (2.0.0-player.36): what the turntable reads of a player (Turntable's
 * TurntablePlayer), backed by ONE <audio> element of the bench's own playing a WAV of the whole song the
 * bench made (a blob: address, which works over plain http) - so play, pause, a seek, a coast's handover
 * back to the song and the element's own start-up latency behave as the app's do. Never the app's player
 * (usePlayer), and nothing of Web Audio touches it: the record's sound is the deck's own, as in the app.
 *
 * Since 2.0.0-player.37 it also plays a SONG FROM THE LIBRARY: its own stream, at the address the app's
 * player asks for it at (lab/library.ts libraryAddress), with the app's own track for it and the device's
 * Maximum quality - so the turntable works out the song's windows as it does in the app.
 */

import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import type { QueueTrack } from '../lib/playQueue'
import type { MaxRate } from '../lib/streamWrap'
import type { TurntablePlayer } from '../player/Turntable'

/** A song as the bench plays it. */
export interface BenchSong {
  id: string
  title: string
  /** seconds - for a library song, Navidrome's */
  seconds: number
  rate: number
  channels: number
  /** the WAV's address - or a library song's stream */
  url: string
  /** a song from the library (2.0.0-player.37): the app's own track for it - what the turntable reads of
   *  it, as it reads the app's - and the Maximum quality it is asked for at. None for a song the bench made */
  library?: { track: QueueTrack; maxRate: MaxRate } | null
}

/**
 * The bench's player is a TurntablePlayer, with what the bench itself reads: what its element can play
 * (the app's question before it chooses an address - asked of the bench's one element, never a new one),
 * and why a song won't load. Its element is only ever played first from a tap (the bench's play button, or
 * the record's): a coast's handover plays it again outside one, which WebKit allows of an element a tap has
 * played - as the app's does.
 */
export type BenchPlayer = TurntablePlayer & {
  canPlayType: (type: string) => string
  /** the song wouldn't load - in words - or null */
  problem: string | null
}

/** Why the element gave up on a song, plainly (its MediaError's code). */
export function loadProblem(code: number | null | undefined): string {
  switch (code) {
    case 1: return 'its loading was stopped'
    case 2: return 'the connection broke off while it loaded'
    case 3: return "it couldn't be decoded"
    case 4: return "deadwax or Navidrome didn't send it, or this browser can't play what they sent"
    default: return 'the browser gave no reason'
  }
}

export function useBenchPlayer(song: BenchSong | null): BenchPlayer {
  const element = useMemo(() => {
    const audio = document.createElement('audio')
    audio.preload = 'auto'
    return audio
  }, [])
  const [playing, setPlaying] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  //? a library song's length as the element has it, once it does - the app's rule (songLength() in
  //? usePlayer: the element's when finite and above 0, else the tags')
  const [elementLength, setElementLength] = useState(0)
  const listeners = useRef(new Set<(seconds: number) => void>())
  //? a seek the element hasn't finished: what the position says until it has, as usePlayer's does
  const pending = useRef<number | null>(null)
  //? the song as last rendered, and the address the element was last given: the turntable's effects run
  //? before this hook's (a child's run first), so for that moment the element still holds the song
  //? before - and its position is no position of the new one's
  const songRef = useRef(song)
  songRef.current = song
  const loaded = useRef<string | null>(null)

  const tell = (seconds: number) => {
    for (const listener of [...listeners.current]) listener(seconds)
  }

  useEffect(() => {
    const onPlay = () => setPlaying(true)
    const onPause = () => setPlaying(false)
    const onTime = () => {
      if (pending.current !== null && !element.seeking) pending.current = null
      if (pending.current === null) tell(element.currentTime)
    }
    element.addEventListener('play', onPlay)
    element.addEventListener('pause', onPause)
    element.addEventListener('ended', onPause)
    //? a load stops the element without a 'pause' (it drops the one queued) - so 'emptied' says it too
    element.addEventListener('emptied', onPause)
    element.addEventListener('timeupdate', onTime)
    element.addEventListener('seeked', onTime)
    //? a song that won't load says so (2.0.0-player.37: a library song's stream can fail; a WAV of the
    //? bench's own never has)
    const onError = () => {
      if (!element.getAttribute('src')) return
      setPlaying(false)
      setProblem(loadProblem(element.error?.code))
    }
    const onLength = () => setElementLength(Number.isFinite(element.duration) && element.duration > 0 ? element.duration : 0)
    element.addEventListener('error', onError)
    element.addEventListener('durationchange', onLength)
    return () => {
      element.removeEventListener('error', onError)
      element.removeEventListener('durationchange', onLength)
      element.removeEventListener('play', onPlay)
      element.removeEventListener('pause', onPause)
      element.removeEventListener('ended', onPause)
      element.removeEventListener('emptied', onPause)
      element.removeEventListener('timeupdate', onTime)
      element.removeEventListener('seeked', onTime)
      element.pause()
      element.removeAttribute('src')
      element.load()
    }
  }, [element])

  //? a new song: the element given its WAV (or a library song its stream), paused at the start - asked for
  //? again when a song that wouldn't load is picked again (a song's id is new each time the bench takes it,
  //? its address not) - and said to be paused here and now:
  //? giving the element a new address runs its load, which drops the 'pause' that pause() queued, so
  //? nothing would say so (review of 2.0.0-player.36: the record spun on over a silent song, and Pause, or
  //? a hand on the record, then played it)
  useEffect(() => {
    element.pause()
    setPlaying(false)
    setProblem(null)
    setElementLength(0)
    pending.current = null
    if (song) element.src = song.url
    else element.removeAttribute('src')
    loaded.current = song?.url ?? null
    tell(0)
  }, [song?.id, song?.url])

  const actions = useMemo(() => ({
    position: () => ((songRef.current?.url ?? null) !== loaded.current ? 0 : pending.current ?? element.currentTime),
    onPosition: (listener: (seconds: number) => void) => {
      listeners.current.add(listener)
      return () => {
        listeners.current.delete(listener)
      }
    },
    seek: (seconds: number) => {
      pending.current = seconds
      element.currentTime = seconds
      tell(seconds)
    },
    toggle: () => {
      if (!element.paused) {
        element.pause()
        return
      }
      element.play().catch(() => setPlaying(false))
    },
    canPlayType: (type: string) => element.canPlayType(type),
  }), [element])

  const library = song?.library ?? null
  return useMemo(() => ({
    track: library
      ? library.track
      : song
        ? {
            id: song.id, title: song.title, artist: 'Test bench', album: '', albumId: null, coverArt: null, duration: song.seconds,
            contentType: 'audio/wav', suffix: 'wav', sampleRate: song.rate, bitDepth: 24, channels: song.channels,
          }
        : null,
    playing,
    //? a WAV of the bench's own is exactly its length; a library song is the element's once it knows
    duration: library && elementLength > 0 ? elementLength : song?.seconds ?? 0,
    maxRate: library ? library.maxRate : ('original' as const),
    problem,
    ...actions,
  }), [song, playing, actions, problem, elementLength])
}
