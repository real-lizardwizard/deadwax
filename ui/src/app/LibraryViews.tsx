import { useEffect, useMemo, useState } from 'preact/hooks'

import { albumCountLine, sortArtists, type ArtistOrder } from '../lib/artistPage'
import { isAbort, latestOnly } from '../lib/latest'
import {
  SONGS_PAGE, dropPrefetch, libraryArtists, librarySongs, prefetchAlbum, type Album, type Artist, type Song,
} from '../player/api'
import { Cover } from '../player/Cover'
import { usePaged } from './usePaged'

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

export { ARTIST_ORDERS, countText, type ArtistOrder } from '../lib/artistPage'

/**
 * Library > Artists (2.0.0-player.17): every artist Navidrome has - the album artists, which is what
 * it groups a library on, so an artist who renamed is one row under the name deadwax files them
 * under (Ye, with Donda and BULLY) - a row each, opening their page. getArtists, asked as the view
 * is first shown and once more each time it is chosen again.
 */
export function ArtistsView({
  order,
  shown,
  onOpenArtist,
  onCount,
}: {
  order: ArtistOrder
  shown: boolean
  onOpenArtist: (artist: Artist) => void
  onCount: (count: number | null) => void
}) {
  const [artists, setArtists] = useState<Artist[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const requests = useMemo(latestOnly, [])

  function load() {
    const request = requests.begin()
    setError(null)
    libraryArtists(true).then(
      (found) => {
        if (!request.current()) return
        setArtists(found)
        onCount(found.length)
      },
      (reason: unknown) => {
        if (request.current() && !isAbort(reason)) setError(message(reason))
      },
    )
  }

  useEffect(() => {
    if (shown) load()
  }, [shown])

  useEffect(() => () => requests.supersede(), [])

  const listed = useMemo(() => (artists ? sortArtists(artists, order) : []), [artists, order])

  if (error) {
    return (
      <div class="pl-notice">
        <p>{error}</p>
        <button type="button" class="pl-text-button" onClick={load}>
          Try again
        </button>
      </div>
    )
  }
  if (!artists) return <div class="pl-spinner" aria-label="Loading" />
  if (!artists.length) return <p class="pl-notice">No artists in Navidrome yet.</p>
  return (
    <ul class="app-results app-library-list">
      {listed.map((artist) => (
        <li key={artist.id}>
          <button type="button" class="app-result is-artist" onClick={() => onOpenArtist(artist)}>
            <Cover id={artist.coverArt} size={112} class="app-result-cover is-round" />
            <span class="app-result-text">
              <span class="app-result-title">{artist.name}</span>
              {albumCountLine(artist.albumCount) && <span class="app-result-line">{albumCountLine(artist.albumCount)}</span>}
            </span>
          </button>
        </li>
      ))}
    </ul>
  )
}

/**
 * Library > Songs (2.0.0-player.17): every song, a page at a time - search3 with an empty query,
 * which Navidrome answers with everything. A row OPENS its album, as a tile does (the songs are
 * asked for as the finger lands): Play is pressed there, in the tap, with the songs in hand - a row
 * that fetched and then played would start the music outside the tap (the gesture rule). Navidrome's
 * own order; the Library hides this view altogether when the empty search finds nothing.
 */
export function SongsView({ onOpen, onCount }: { onOpen: (album: Album) => void; onCount: (count: number | null) => void }) {
  const songs = usePaged<Song>((offset, signal) => librarySongs(offset, SONGS_PAGE, signal), SONGS_PAGE, 'songs')

  useEffect(() => {
    onCount(songs.done ? songs.items.length : null)
  }, [songs.done, songs.items.length])

  const open = (song: Song) => {
    if (!song.albumId) return
    onOpen({
      id: song.albumId,
      name: song.album ?? '',
      ...(song.artist ? { artist: song.artist } : {}),
      ...(song.coverArt ? { coverArt: song.coverArt } : {}),
    })
  }

  return (
    <>
      <ul class="app-results app-library-list">
        {songs.items.map((song) => (
          <li key={song.id}>
            <button
              type="button"
              class="app-result"
              onPointerDown={() => {
                if (song.albumId) void prefetchAlbum(song.albumId)
              }}
              onPointerCancel={() => {
                if (song.albumId) dropPrefetch(song.albumId)
              }}
              onClick={() => open(song)}
            >
              <Cover id={song.coverArt} size={96} class="app-result-cover" />
              <span class="app-result-text">
                <span class="app-result-title">{song.title}</span>
                <span class="app-result-line">{[song.artist, song.album].filter(Boolean).join(' · ')}</span>
              </span>
              <span class="app-visually-hidden">, opens its album</span>
            </button>
          </li>
        ))}
      </ul>
      {songs.error && (
        <div class="pl-notice">
          <p>{songs.error}</p>
          <button type="button" class="pl-text-button" onClick={songs.retry}>
            Try again
          </button>
        </div>
      )}
      {!songs.error && !songs.loading && !songs.items.length && <p class="pl-notice">No songs in Navidrome yet.</p>}
      {songs.loading && <div class="pl-spinner" aria-label="Loading" />}
      <div ref={songs.sentinel} class="pl-sentinel" />
    </>
  )
}
