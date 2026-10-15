/**
 * Your library as the Library tab draws it (2.0.0-player.52, step 6 of the multi-user plan) - pure, pinned by
 * ui/test/whose.sim.cjs.
 *
 * With logins on your library is your starred albums - Navidrome's getAlbumList2 `starred`, asked AS YOU -
 * which Navidrome lists in its own order only (most recently starred first): Subsonic has no "your starred
 * albums by title". So the Library asks for all of them (a page of 500 at a time, YOURS_MAX at most) and puts
 * them in the order chosen here, the four the store's grid has:
 *
 *  - Recently added: when Navidrome first had the album (`created`), newest first;
 *  - Recently played: the ones you have played (`played`, which Navidrome keeps per user), latest first -
 *    the rest left out, as Navidrome's own "recent" leaves them;
 *  - Artist: by the album artist's name as it should be compared (a leading "The", accents, case folded
 *    away - lib/owned.ts's foldName), then the year, then the title;
 *  - Title: by the title, then the artist.
 *
 * Navidrome's own orders read sort names it doesn't send, so "Artist" and "Title" here can put an album or two
 * where its grid of the store wouldn't; nothing is left out or doubled. Ties keep Navidrome's order.
 *
 * And Your artists: the artists of your albums - Navidrome's own artist (its picture, its MusicBrainz id) for
 * every album artist your albums name, counting YOUR albums of theirs, in Navidrome's order.
 */

import type { Album, AlbumOrder, Artist } from '../player/api'
import { foldName } from './owned'

/** How many of your albums the Library asks for, at most: twenty pages of Navidrome's 500. */
export const YOURS_MAX = 10000
/** One page of them: Navidrome's own ceiling (routes/navidrome.py takes up to 500). */
export const YOURS_PAGE = 500

const time = (value: string | undefined) => {
  const parsed = value ? Date.parse(value) : NaN
  return Number.isNaN(parsed) ? null : parsed
}

const text = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0)

/** Your albums in the order chosen - a new list, Navidrome's left as it is. */
export function sortYourAlbums(albums: readonly Album[], order: AlbumOrder): Album[] {
  const listed = albums.map((album, index) => ({ album, index }))
  const byIndex = (a: { index: number }, b: { index: number }) => a.index - b.index
  if (order === 'recent') {
    return listed
      .filter(({ album }) => time(album.played) !== null)
      .sort((a, b) => time(b.album.played)! - time(a.album.played)! || byIndex(a, b))
      .map(({ album }) => album)
  }
  if (order === 'newest') {
    return listed
      .sort((a, b) => {
        const first = time(a.album.created)
        const second = time(b.album.created)
        if (first === null || second === null) return first === second ? byIndex(a, b) : first === null ? 1 : -1
        return second - first || byIndex(a, b)
      })
      .map(({ album }) => album)
  }
  const artist = (album: Album) => foldName(album.artist)
  const title = (album: Album) => foldName(album.name)
  return listed
    .sort((a, b) =>
      order === 'alphabeticalByArtist'
        ? text(artist(a.album), artist(b.album)) || (a.album.year ?? 9999) - (b.album.year ?? 9999)
          || text(title(a.album), title(b.album)) || byIndex(a, b)
        : text(title(a.album), title(b.album)) || text(artist(a.album), artist(b.album)) || byIndex(a, b))
    .map(({ album }) => album)
}

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
export const EMPTY_LIBRARY_HOW = "Browse the store, or search, and add an album from its page - or Get one deadwax doesn't have."
/** ...in Recently played, with albums of yours but none played. */
export const NOTHING_OF_YOURS_PLAYED = 'Nothing in your library played yet.'

/**
 * What an empty view of your albums says (review): 'empty' - your library empty, whatever the order (the order
 * is one per device, shared with Browse, so Recently played can be the one in use on a first visit) - says so,
 * how to fill it and Browse the store; 'unplayed' only for Recently played over a library that has albums, none
 * played. null while how many albums you have isn't known.
 */
export function yourEmptyNotice(order: AlbumOrder, yoursCount: number | null): 'empty' | 'unplayed' | null {
  if (yoursCount === null) return null
  if (yoursCount === 0) return 'empty'
  return order === 'recent' ? 'unplayed' : null
}
/** ...in Your artists, with nothing in your library. */
export const NO_ARTISTS_OF_YOURS = 'No artists in your library yet.'
