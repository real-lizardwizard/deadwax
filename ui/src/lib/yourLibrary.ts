/**
 * Your library as the Library tab draws it (2.0.0-player.52, step 6 of the multi-user plan) - pure, pinned by
 * ui/test/whose.sim.cjs.
 *
 * With logins on your library is your starred albums - Navidrome's getAlbumList2 `starred`, asked AS YOU - which
 * Navidrome lists in its own order only (most recently starred first): Subsonic has no "your starred albums by
 * title". So the Library asks for all of them - since 2.0.0-player.59 in one request (app/albumIndex.ts, the route's
 * cap 10,000) - and puts them in the order chosen with lib/shelves.ts, the store's too.
 *
 * And Your artists: the artists of your albums - Navidrome's own artist (its picture, its MusicBrainz id) for
 * every album artist your albums name, counting YOUR albums of theirs, in Navidrome's order.
 */

import type { Album, Artist } from '../player/api'
import type { AlbumSort } from './shelves'

/** Your artists: Navidrome's artists that your albums name as their album artist, each counting your albums
 *  of theirs, in Navidrome's order. */
export function yourArtists(artists: readonly Artist[], albums: readonly Album[]): Artist[] {
  const counts = new Map<string, number>()
  for (const album of albums) {
    if (album.artistId) counts.set(album.artistId, (counts.get(album.artistId) ?? 0) + 1)
  }
  return artists.filter((artist) => counts.has(artist.id)).map((artist) => ({ ...artist, albumCount: counts.get(artist.id) ?? 0 }))
}

/** What the Library says with nothing in your library: your library is empty, and the two ways to fill it. */
export const EMPTY_LIBRARY = 'Nothing in your library yet.'
export const EMPTY_LIBRARY_HOW = "Look through All music and add the albums you like, or find new ones in Search and Get them."
/** ...in Recently played, with albums of yours but none played. */
export const NOTHING_OF_YOURS_PLAYED = "You haven't played anything from your library yet."

/** (2.0.5, UX batch 2) The empty states with logins off (the library IS the collection), and of All music - never
 *  "in Navidrome": the music server is the reader's only through what it shows. */
export const NO_ALBUMS = 'No albums yet.'
export const NO_ARTISTS = 'No artists yet.'
export const NO_SONGS = 'No songs yet.'

/**
 * What an empty view of your albums says (review): 'empty' - your library empty, whatever the order (the order
 * is one per device, shared with Browse, so Recently played can be the one in use on a first visit) - says so,
 * how to fill it and Browse the store; 'unplayed' only for the played sorts - Recently played and (2.0.0-player.59)
 * Most played, which leave out the unplayed - over a library that has albums, none played. null while how many
 * albums you have isn't known.
 */
export function yourEmptyNotice(order: AlbumSort, yoursCount: number | null): 'empty' | 'unplayed' | null {
  if (yoursCount === null) return null
  if (yoursCount === 0) return 'empty'
  return order === 'recent' || order === 'frequent' ? 'unplayed' : null
}
/** ...in Your artists, with nothing in your library. */
export const NO_ARTISTS_OF_YOURS = 'No artists in your library yet.'
