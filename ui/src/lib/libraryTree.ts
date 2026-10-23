import type { LibraryAlbum } from '../api/types'

/**
 * What is left of the main page's library tree (its arrangements, rows and windowing went with the page
 * in 2.0.0-player.66): a disc's title as the scan read it, which the app's track inspector says.
 */

/**
 * A disc's own title, where its files carry one (DISCSUBTITLE) - '' when not, which is most discs.
 * From the scan, so it is there the moment a "Disc N" is drawn.
 */
export const discTitle = (album: LibraryAlbum, disc: number): string =>
  album.disc_titles?.[String(disc)] ?? ''
