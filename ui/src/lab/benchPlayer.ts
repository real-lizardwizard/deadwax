/**
 * The test bench's player (2.0.0-player.36): what the turntable reads of a player (Turntable's
 * TurntablePlayer), backed by ONE <audio> element of the bench's own playing a WAV of the whole song the
 * bench made (a blob: address, which works over plain http) - so play, pause, a seek, a coast's handover
 * back to the song and the element's own start-up latency behave as the app's do. Never the app's player
 * (usePlayer), and nothing of Web Audio touches it: the record's sound is the deck's own, as in the app.
 */

import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import type { TurntablePlayer } from '../player/Turntable'

/** A song as the bench plays it. */
export interface BenchSong {
  id: string
  title: string
  /** seconds */
  seconds: number
  rate: number
  channels: number
  /** the WAV's address */
  url: string
}

/**
 * The bench's player is a TurntablePlayer and nothing more. Its element is only ever played first from a
 * tap (the bench's play button, or the record's): a coast's handover plays it again outside one, which
 * WebKit allows of an element a tap has played - as the app's does.
 */
export type BenchPlayer = TurntablePlayer

export function useBenchPlayer(song: BenchSong | null): BenchPlayer {
  const element = useMemo(() => {
    const audio = document.createElement('audio')
    audio.preload = 'auto'
    return audio
  }, [])
  const [playing, setPlaying] = useState(false)
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
    return () => {
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

  //? a new song: the element given its WAV, paused at the start - and said to be paused here and now:
  //? giving the element a new address runs its load, which drops the 'pause' that pause() queued, so
  //? nothing would say so (review of 2.0.0-player.36: the record spun on over a silent song, and Pause, or
  //? a hand on the record, then played it)
  useEffect(() => {
    element.pause()
    setPlaying(false)
    pending.current = null
    if (song) element.src = song.url
    else element.removeAttribute('src')
    loaded.current = song?.url ?? null
    tell(0)
  }, [song?.url])

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
  }), [element])

  return useMemo(() => ({
    track: song
      ? {
          id: song.id, title: song.title, artist: 'Test bench', album: '', albumId: null, coverArt: null, duration: song.seconds,
          contentType: 'audio/wav', suffix: 'wav', sampleRate: song.rate, bitDepth: 24, channels: song.channels,
        }
      : null,
    playing,
    duration: song?.seconds ?? 0,
    maxRate: 'original' as const,
    ...actions,
  }), [song, playing, actions])
}
