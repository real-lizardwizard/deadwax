/**
 * Looking after the library in the app, on a desktop (2.0.0-player.42) - the Library care page's
 * words and its narrowing, pure, pinned by ui/test/care.sim.cjs. The page is app/LibraryCare.tsx; the
 * runs it starts are app/useLibraryCare.ts's; which albums each run takes, and its words once it has
 * finished, are lib/bulkTargets.ts's (shared with the main page's Library tab).
 *
 * THE SCAN, said as the main page's status bar says it: its albums (an album held in several
 * pressings once, as the main page counts it), tracks and size; and how old it is - "Saved scan from
 * 3 h ago" while the saved scan is what's in hand, "Scanned 2 min ago in 4s" once the disk has been
 * read. Rescan reads every file again: deadwax notices a changed album by its folder's date, which a
 * tag edited in place by another program doesn't move.
 *
 * THE RUNS act on the whole library, or on the albums a few typed words narrow it to (`narrowAlbums`:
 * every word somewhere in the folder's artist, album, edition or path, accents and case aside) - and
 * say so before they start (`planWords`): how many album FOLDERS, which, and what will be written. A
 * run takes folders, and an album held in two pressings is two of them - counted as albums beside the
 * scan's grouped count, a library of 7 albums would have "8 albums with no lyrics".
 */

import type { LibraryAlbum } from '../api/types'
import type { BulkKind } from './bulkTargets'
import { formatAge, formatSize } from './format'
import { groupAlbums } from './groupAlbums'
import { matchesTyped } from './typedMatch'

/** What the narrowing reads of an album in the scan. */
export interface NarrowAlbum {
  path: string
  artist: string
  album: string
  edition: string
}

/** The albums a run acts on: all of them, or those whose artist, album, edition or folder holds
 *  every word typed. */
export function narrowAlbums<T extends NarrowAlbum>(albums: readonly T[], typed: string): T[] {
  if (!typed.trim()) return [...albums]
  return albums.filter((album) => matchesTyped(`${album.artist} ${album.album} ${album.edition} ${album.path}`, typed))
}

/** Where a run acts, in words: " in the whole library", or " among the folders matching “x”". */
export function scopeWords(typed: string): string {
  const text = typed.trim()
  return text ? ` among the folders matching “${text}”` : ' in the whole library'
}

const foldersWord = (count: number) => `${count} album folder${count === 1 ? '' : 's'}`

/** What the runs act on, said under the narrowing: the whole library, or how many folders match. */
export function scopeLine(inScope: number, all: number, typed: string): string {
  const text = typed.trim()
  if (!text) return `The runs act on the whole library: ${foldersWord(all)}.`
  return inScope ? `The runs act on ${inScope} of ${foldersWord(all)}: those matching “${text}”.` : `No album folder matches “${text}”.`
}

/** What a run will do, said before it starts: how many album folders it takes, which, and what it
 *  writes - CD art by the names src/disc_art.py's disc_art_filename gives (disc.<ext>, or disc<N>.<ext>
 *  per disc of a set; the extension the picture's own). */
export function planWords(kind: BulkKind, count: number, typed: string): string {
  const where = scopeWords(typed)
  if (kind === 'covers') {
    return count
      ? `${foldersWord(count)} with a release and no cover${where}. Each cover comes from the Cover Art Archive, `
        + "by the release the album's tags name, and is saved beside its tracks - nothing else about the album changes."
      : `No album with a release is missing its cover${where}.`
  }
  if (kind === 'disc') {
    return count
      ? `${foldersWord(count)} with a release and no CD art of deadwax's own${where}. A picture of each disc, from `
        + 'the Cover Art Archive (or fanart.tv, with a key), is saved beside the tracks as disc.jpg (disc1.jpg, '
        + "disc2.jpg… for a set with a picture per disc; .png when that's what the source has) - nothing else changes."
      : `Every album with a release has CD art of deadwax's own${where}.`
  }
  return count
    ? `${foldersWord(count)} with no lyrics at all${where}. Each track is looked up on LRCLIB and saved as a .lrc `
      + "beside it - nothing else changes. An album with some lyrics is finished from its own Get lyrics, in its Edit panel."
    : `Every album has some lyrics${where}.`
}

/** The button that starts a run: the main page's words, with how many albums it takes. */
export const BULK_LABELS: Readonly<Record<BulkKind, string>> = {
  covers: 'Get covers',
  disc: 'Get CD art',
  lyrics: 'Get lyrics',
}

/** Each run's heading on the page. */
export const BULK_TITLES: Readonly<Record<BulkKind, string>> = {
  covers: 'Covers',
  disc: 'CD art',
  lyrics: 'Lyrics',
}

/** What the scan holds, as the main page's status bar counts it: albums (several pressings of one
 *  album once), tracks, and size. */
export function scanTotals(albums: readonly LibraryAlbum[]): string {
  const groups = groupAlbums(albums).length
  const tracks = albums.reduce((sum, album) => sum + album.track_count, 0)
  const size = formatSize(albums.reduce((sum, album) => sum + album.total_size, 0))
  return [`${groups} album${groups === 1 ? '' : 's'}`, `${tracks} track${tracks === 1 ? '' : 's'}`, size].filter(Boolean).join(' · ')
}

/** How old the scan in hand is, as the main page's status bar says it - or what is under way. */
export function scanAge(
  scan: { loaded: boolean; stale: boolean; loading: boolean; scannedAt: number | null; scanSeconds: number },
  rescanning: boolean,
  now = Date.now(),
): string {
  if (!scan.loaded) return 'Reading the library…'
  if (rescanning) return 'Rescanning - reading every file again…'
  const age = formatAge(scan.scannedAt, now)
  if (scan.stale) return `Saved scan from ${age || 'an earlier visit'}${scan.loading ? ' · checking for changes' : ''}`
  return scan.scannedAt ? `Scanned ${age}${scan.scanSeconds ? ` in ${scan.scanSeconds}s` : ''}` : ''
}

/** What the page says it is for. */
export const CARE_LINE = 'Rescan, and the runs that fetch covers, CD art and lyrics for the albums missing them - '
  + "one album at a time, through the same steps as an album's own Get buttons, each with Stop."

/** Why Rescan is there. */
export const RESCAN_WORDS = "deadwax notices a changed album by its folder's date, and a tag edited in place by another "
  + "program doesn't change it - so after a retag elsewhere, Rescan reads every file again. Albums filed from a "
  + 'download appear without it.'

/** On a phone, the page is a note. */
export const CARE_PHONE = 'Looking after the library needs a wider screen for now - or'
