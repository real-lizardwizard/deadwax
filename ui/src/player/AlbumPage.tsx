import { Fragment } from 'preact'
import { useEffect, useMemo, useState } from 'preact/hooks'

import { formatDuration, trackTime } from '../lib/format'
import { isAbort, latestOnly } from '../lib/latest'
import { album as fetchAlbum, toQueueTrack, type Album, type AlbumWithSongs, type Song } from './api'
import { ChevronLeftIcon, PlayIcon, PlayingBars, ShuffleIcon } from './icons'
import { Cover } from './Library'
import type { Player } from './usePlayer'

/** The one format every song is in - "FLAC" - or null when they differ or nobody said. */
function sharedFormat(songs: Song[]): string | null {
  const formats = new Set(songs.map((song) => (song.suffix ?? '').toUpperCase()))
  const [only] = formats
  return formats.size === 1 && only ? only : null
}

/**
 * One album: its cover, Play and Shuffle, and its songs.
 *
 * Drawn from the grid's copy of the album straight away, so the cover and title are on screen
 * while the song list is still on its way. Only the newest request counts (lib/latest.ts), and
 * leaving the album calls its request off rather than letting it run on beside the music.
 */
export function AlbumPage({
  id,
  preview,
  player,
  onBack,
}: {
  id: string
  preview: Album | null
  player: Player
  onBack: () => void
}) {
  const [album, setAlbum] = useState<AlbumWithSongs | null>(null)
  const [error, setError] = useState<string | null>(null)
  const requests = useMemo(latestOnly, [])

  useEffect(() => {
    const request = requests.begin()
    setAlbum(null)
    setError(null)
    fetchAlbum(id, request.signal).then(
      (found) => {
        if (request.current()) setAlbum(found)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setError(reason instanceof Error ? reason.message : String(reason))
      },
    )
    return () => requests.supersede()
  }, [id, requests])

  const shown: Album | null = album ?? (preview?.id === id ? preview : null)
  const songs = album?.song ?? []
  const tracks = useMemo(() => (album ? songs.map((song) => toQueueTrack(song, album)) : []), [album])
  const discs = new Set(songs.map((song) => song.discNumber ?? 1)).size
  const format = sharedFormat(songs)
  const total = songs.reduce((sum, song) => sum + (song.duration ?? 0), 0)

  const play = (start: number | null, shuffle = false) => {
    if (tracks.length) player.playTracks(tracks, start, shuffle)
  }

  return (
    <section class="pl-album-page">
      <header class="pl-nav-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          Library
        </button>
      </header>

      <div class="pl-album-hero">
        <Cover id={shown?.coverArt} size={800} class="pl-hero-cover" />
        <h1 class="pl-hero-title">{shown?.name ?? ''}</h1>
        <p class="pl-hero-artist">{shown?.artist ?? ''}</p>
        <p class="pl-hero-meta">
          {[shown?.genre, shown?.year, format].filter(Boolean).join(' · ')}
        </p>

        <div class="pl-hero-actions">
          <button type="button" class="pl-pill" disabled={!tracks.length} onClick={() => play(0)}>
            <PlayIcon class="pl-pill-icon" />
            Play
          </button>
          <button type="button" class="pl-pill" disabled={!tracks.length} onClick={() => play(null, true)}>
            <ShuffleIcon class="pl-pill-icon" />
            Shuffle
          </button>
        </div>
      </div>

      {error && <p class="pl-notice">{error}</p>}
      {!album && !error && <div class="pl-spinner" aria-label="Loading" />}

      <ol class="pl-tracks">
        {songs.map((song, index) => {
          const isCurrent = player.track?.id === song.id
          const disc = song.discNumber ?? 1
          const newDisc = discs > 1 && (index === 0 || (songs[index - 1]?.discNumber ?? 1) !== disc)
          const showArtist = song.artist && song.artist !== shown?.artist
          return (
            <Fragment key={song.id}>
              {newDisc && <li class="pl-disc">Disc {disc}</li>}
              <li>
                <button
                  type="button"
                  class={`pl-track${isCurrent ? ' is-current' : ''}`}
                  onClick={() => play(index)}
                >
                  <span class="pl-track-number">
                    {isCurrent ? <PlayingBars paused={!player.playing} /> : song.track ?? ''}
                  </span>
                  <span class="pl-track-text">
                    <span class="pl-track-title">{song.title}</span>
                    {showArtist && <span class="pl-track-artist">{song.artist}</span>}
                  </span>
                  <span class="pl-track-time">{trackTime(song.duration)}</span>
                </button>
              </li>
            </Fragment>
          )
        })}
      </ol>

      {album && (
        <p class="pl-album-footer">
          {songs.length} {songs.length === 1 ? 'song' : 'songs'}
          {total ? `, ${formatDuration(total)}` : ''}
        </p>
      )}
    </section>
  )
}
