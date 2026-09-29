import type { LibraryAlbum } from '../api/types'
import { outstandingIssues } from './metadataQueue'

/**
 * One album, with every edition of it you hold.
 *
 * Mirrors how the search view is organised - there a release *group* is the album and the
 * releases under it are its editions, and the same shape belongs here. Listing every edition
 * as a peer meant three separate "The Slow Rush" rows, which reads as three albums rather
 * than one album you happen to have three pressings of.
 */
/**
 * What an album's folders are, in words: "3 editions", or - when some are the discs of one
 * release stored one folder per disc (v0.9.13) - "2 disc folders" / "2 editions · 1 split".
 * The count of editions comes from the scan, which counts a split release once.
 */
export function folderSummary(editions: readonly { split_discs?: boolean; edition_count: number }[]): {
  label: string
  title: string
} {
  const folders = editions.length
  const split = editions.filter((e) => e.split_discs).length
  const releases = editions[0]?.edition_count ?? folders
  if (!split) {
    return { label: `${folders} editions`, title: `${folders} versions of this album are in your library` }
  }
  const title = `${split} of these folders hold different discs of one release - the metadata `
    + 'editor merges them when you apply that release to each'
  return releases <= 1
    ? { label: `${folders} disc folders`, title }
    : { label: `${releases} editions · split discs`, title }
}

/**
 * What one folder is called among its album's others: its edition, or - for a disc of a release
 * stored one folder per disc - which discs it holds (v0.9.13), after the edition when it has one.
 * A folder of ONE disc that has a title says it too (v1.1.0): "Disc 4 · Live at Wembley 1974" -
 * such a folder has no disc headings of its own, so this is the only place it would show.
 */
export function editionName(album: {
  edition: string
  disc_label?: string | null
  discs?: number[]
  disc_titles?: Record<string, string>
}): string {
  if (album.disc_label) {
    const [only, ...rest] = album.discs ?? []
    const title = only !== undefined && !rest.length ? album.disc_titles?.[String(only)] : ''
    const label = title ? `${album.disc_label} · ${title}` : album.disc_label
    return album.edition ? `${album.edition} · ${label}` : label
  }
  return album.edition || 'Standard'
}

export interface AlbumGroup {
  key: string
  artist: string
  album: string
  /** Earliest year across the editions - the album's year, not any one pressing's. */
  year: string
  /** Set when editions disagree, e.g. an original and a much later reissue. */
  yearRange: string
  editions: LibraryAlbum[]
  /**
   * Which edition's cover represents the album.
   *
   * Art is shown once, on the album, rather than repeated down the editions - the editions
   * differ by tracklist and pressing, and a column of near-identical thumbnails added noise
   * without adding information. Since there's only one cover, it's worth picking the edition
   * that actually has one rather than whichever sorted first.
   */
  artFrom: LibraryAlbum | undefined
  /** Totals across every edition, so the collapsed row can say something useful. */
  trackCount: number
  totalSize: number
  duration: number
  formats: string[]
  hasMixedTags: boolean
  /**
   * How many editions under this album have outstanding metadata issues.
   *
   * Counted rather than a boolean because a collapsed row has to say something useful about
   * editions you can't see yet: "1 of 3 needs attention" is a reason to expand, and a bare
   * warning triangle on an album whose deluxe press is the only problem is misleading.
   */
  needsAttention: number
  /** Every outstanding issue across the editions, worst first, deduplicated. */
  issues: string[]
}

/**
 * Fold the flat album list into one entry per (artist, album).
 *
 * Grouped case-insensitively on purpose: the same album tagged "The Slow Rush" in one folder
 * and "the slow rush" in another is still one album, and splitting it would recreate exactly
 * the problem this grouping exists to solve.
 */
export function groupAlbums(albums: readonly LibraryAlbum[]): AlbumGroup[] {
  const groups = new Map<string, AlbumGroup>()

  for (const album of albums) {
    const key = `${album.artist.toLowerCase()}\u0000${album.album.toLowerCase()}`
    let group = groups.get(key)

    if (!group) {
      group = {
        key,
        //? the first-seen spelling wins for display - albums arrive sorted, so this is stable
        artist: album.artist,
        album: album.album,
        year: album.year,
        yearRange: '',
        artFrom: undefined,
        editions: [],
        trackCount: 0,
        totalSize: 0,
        duration: 0,
        formats: [],
        hasMixedTags: false,
        needsAttention: 0,
        issues: [],
      }
      groups.set(key, group)
    }

    group.editions.push(album)
    group.trackCount += album.track_count
    group.totalSize += album.total_size
    group.duration += album.duration
    group.hasMixedTags ||= album.mixed_tags

    if (album.needs_attention) group.needsAttention += 1
  }

  for (const group of groups.values()) {
    const years = [...new Set(group.editions.map((e) => e.year).filter(Boolean))].sort()
    const first = years[0]
    const last = years[years.length - 1]

    group.year = first ?? ''
    //? a 1998 album reissued in 2012 should say so rather than silently picking one
    group.yearRange = first && last && first !== last ? `${first}–${last}` : ''

    group.formats = [...new Set(group.editions.flatMap((e) => e.formats))].sort()

    //? The worst-affected edition contributes first, and each edition's own list already
    //? arrives worst first, so the union opens with the most serious thing wrong anywhere under
    //? this album - which is what the row shows when it only has room for two or three chips.
    group.issues = [...new Set(
      [...group.editions].sort((a, b) => b.severity - a.severity).flatMap(outstandingIssues),
    )]

    //? most-complete first: when you hold several pressings, the one with the most tracks is
    //? almost always the one you actually want to look at
    group.editions.sort((a, b) => b.track_count - a.track_count || a.edition.localeCompare(b.edition))

    //? art on disk beats art that needs fetching, and either beats a placeholder - so an
    //? album whose deluxe press carries the only cover still shows it
    group.artFrom =
      group.editions.find((e) => e.art) ??
      group.editions.find((e) => e.release_mbid) ??
      group.editions[0]
  }

  return [...groups.values()]
}
