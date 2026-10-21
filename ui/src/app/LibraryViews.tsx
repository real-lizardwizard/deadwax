import { useEffect } from 'preact/hooks'

import { albumCountLine } from '../lib/artistPage'
import { IN_THE_STORE } from '../lib/whose'
import { EMPTY_LIBRARY_HOW } from '../lib/yourLibrary'
import { SONGS_PAGE, dropPrefetch, librarySongs, prefetchAlbum, type Album, type Artist, type Song } from '../player/api'
import { Cover } from '../player/Cover'
import { MoreIcon } from '../player/icons'
import { usePaged } from './usePaged'

/**
 * (2.0.0-player.52) Your library empty - Ethan's, at first: `lead` (what is empty), how to fill it, and Browse
 * the store - the one way to the whole store, for Your albums in any order and Your artists alike (review).
 */
export function EmptyLibrary({ lead, onBrowse }: { lead: string; onBrowse?: (() => void) | undefined }) {
  return (
    <div class="pl-notice app-library-empty">
      <p>{lead}</p>
      <p>{EMPTY_LIBRARY_HOW}</p>
      {onBrowse && (
        <button type="button" class="pl-text-button" onClick={onBrowse}>
          Browse the store
        </button>
      )}
    </div>
  )
}

/**
 * One row of Library > Artists (2.0.0-player.17): the artist's round picture, their name and how many albums of
 * theirs - every artist Navidrome has (the album artists, which is what it groups a library on, so an artist who
 * renamed is one row under the name deadwax files them under), opening their page. Since 2.0.0-player.59 drawn on
 * the Library's shelf (app/LibrarySection.tsx), sorted, grouped and found there.
 *
 * (2.0.0-player.52) Your artists count your albums of theirs (lib/yourLibrary.ts yourArtists); `inStore`: Browse's,
 * whose counts are the store's ("2 albums in the store").
 */
export function ArtistRow({ artist, inStore = false, onOpenArtist }: {
  artist: Artist
  inStore?: boolean
  onOpenArtist: (artist: Artist) => void
}) {
  return (
    <button type="button" class="app-result is-artist" onClick={() => onOpenArtist(artist)}>
      <Cover id={artist.coverArt} size={112} class="app-result-cover is-round" />
      <span class="app-result-text">
        <span class="app-result-title">{artist.name}</span>
        {albumCountLine(artist.albumCount, inStore ? IN_THE_STORE : undefined) && (
          <span class="app-result-line">{albumCountLine(artist.albumCount, inStore ? IN_THE_STORE : undefined)}</span>
        )}
      </span>
    </button>
  )
}

/**
 * Library > Songs (2.0.0-player.17): every song, a page at a time - search3 with an empty query,
 * which Navidrome answers with everything. A row OPENS its album, as a tile does (the songs are
 * asked for as the finger lands): Play is pressed there, in the tap, with the songs in hand - a row
 * that fetched and then played would start the music outside the tap (the gesture rule). Navidrome's
 * own order; the Library hides this view altogether when the empty search finds nothing.
 *
 * (2.0.0-player.57) Each row ends with a ••• - `onSongMenu`, App's song menu (Play Next, Play Last), with the
 * song in hand - which names no player action here either.
 */
export function SongsView({ onOpen, onCount, onSongMenu }: {
  onOpen: (album: Album) => void
  onCount: (count: number | null) => void
  onSongMenu?: ((song: Song, event: MouseEvent) => void) | undefined
}) {
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
          <li key={song.id} class={onSongMenu ? 'app-result-row' : undefined}>
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
            {onSongMenu && (
              <button
                type="button"
                class="app-row-more"
                aria-label={`More for ${song.title}`}
                aria-haspopup="dialog"
                onClick={(event) => onSongMenu(song, event as unknown as MouseEvent)}
              >
                <MoreIcon class="app-row-more-icon" />
              </button>
            )}
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
