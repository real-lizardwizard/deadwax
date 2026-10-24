/**
 * Looking after the library in the app, on a desktop (2.0.0-player.42) - the Library care page's
 * words and its narrowing, pure, pinned by ui/test/care.sim.cjs. The page is app/LibraryCare.tsx; the
 * runs it starts are app/useLibraryCare.ts's; which albums each run takes, and its words once it has
 * finished, are lib/bulkTargets.ts's (shared with the main page's Library tab until it retired).
 *
 * THE SCAN, said as the main page's status bar said it: its albums (an album held in several
 * pressings once, as the main page counted it), tracks and size; and how old it is - "Saved scan from
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

/** (2.0.8, UX batch 5) The library's read failing, said in place of its raw words (lib/errorWords.ts's `failed`) -
 *  Library care's and Needs a look's. */
export const READ_FAILED = "Couldn't read the library."
export const CHECK_FAILED = "Couldn't check the library just now."
export const REREAD_FAILED = "Couldn't read the library just now."

/** What a run will do, said before it starts: how many album folders it takes, which, and what it
 *  writes. (2.0.8, UX batch 5) In plain words - "matched to a release", "a disc picture from deadwax" - where it
 *  said "with a release", "CD art of deadwax's own" and listed src/disc_art.py's file names. */
export function planWords(kind: BulkKind, count: number, typed: string): string {
  const where = scopeWords(typed)
  if (kind === 'covers') {
    return count
      ? `${foldersWord(count)} matched to a release with no cover${where}. Each cover comes from the Cover Art Archive, `
        + 'for the release the album is matched to, and is saved beside its tracks - nothing else about the album changes.'
      : `No album matched to a release is missing its cover${where}.`
  }
  if (kind === 'disc') {
    return count
      ? `${foldersWord(count)} matched to a release with no disc picture from deadwax yet${where}. A picture of each disc `
        + 'comes from the Cover Art Archive (or fanart.tv, with a key in Server settings) and is saved beside the tracks - '
        + 'nothing else changes.'
      : `Every album matched to a release has a disc picture from deadwax${where}.`
  }
  return count
    ? `${foldersWord(count)} with no lyrics at all${where}. Each track's lyrics come from LRCLIB and are saved beside it - `
      + "nothing else changes. An album with some lyrics is finished from its own Get lyrics, in Edit album."
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

/** What the scan holds, as the main page's status bar counted it: albums (several pressings of one
 *  album once), tracks, and size. */
export function scanTotals(albums: readonly LibraryAlbum[]): string {
  const groups = groupAlbums(albums).length
  const tracks = albums.reduce((sum, album) => sum + album.track_count, 0)
  const size = formatSize(albums.reduce((sum, album) => sum + album.total_size, 0))
  return [`${groups} album${groups === 1 ? '' : 's'}`, `${tracks} track${tracks === 1 ? '' : 's'}`, size].filter(Boolean).join(' · ')
}

/** How old the scan in hand is, as the main page's status bar said it - or what is under way. */
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

/** What the page says it is for - (2.0.8, UX batch 5) what it is FOR, where it said how it works ("through the same
 *  steps as an album's own Get buttons"). A run stops after the album it is on (lib/bulkTargets.ts runBulk). */
export const CARE_LINE = 'Rescan the library after changing tags in another program, and fill in missing covers, CD art '
  + 'and lyrics across many albums at once - one album at a time, and Stop ends a run after the album it\'s on.'

/** (2.0.0-player.65, the 2.0.0 release review) What the page says it is for, naming only the parts it draws for this
 *  person (permissions.ts careParts): the runs alone for Edit albums, Rescan alone for Look after the library. */
export function careLine(parts: { rescan: boolean; bulk: boolean }): string {
  if (parts.rescan && parts.bulk) return CARE_LINE
  if (parts.bulk) {
    return 'Fill in missing covers, CD art and lyrics across many albums at once - one album at a time, and Stop ends a '
      + "run after the album it's on."
  }
  return 'Rescan reads every file of the library again - use it after changing tags in another program.'
}

/** Why Rescan is there - (2.0.8) when to use it first, then why. */
export const RESCAN_WORDS = "Use Rescan after editing tags in another program: deadwax spots a changed album by its "
  + "folder's date, and editing tags in place doesn't change it. Albums added from a download show up without it."
