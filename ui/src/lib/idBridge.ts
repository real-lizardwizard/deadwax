/**
 * The id bridge's answers, as the app draws them (2.0.0-player.17) - pure, pinned by
 * ui/test/artist.sim.cjs.
 *
 * GET /deadwax/store/album answers for one release: the store's folders of it (`present`), the
 * album's other pressings the store holds, and Navidrome's album id for each (src/routes/
 * store_album.py). From that:
 *
 *  - the album page's "Also: <edition> ›" chips (`alsoChips`): another pressing you hold, that
 *    Navidrome has - a chip for one it hasn't found would open nothing;
 *  - its "Other pressings ›" chip (`otherPressingsGroup`, 2.0.0-player.41): the album's MusicBrainz
 *    release group, as its folders carry it - the album-you-don't-have page lists every pressing,
 *    the ones you hold marked, and gets any of them;
 *  - Info's "This pressing: …" - only when it adds to the album's line (`pressingAdds`, 2.0.7) - and its folder
 *    (`pressingLine`, `folderLine`);
 *  - which releases of a MusicBrainz album you hold (`heldReleases`), for opening the album you
 *    have from MusicBrainz's side - in the order every screen opens and plays one of several copies
 *    (`heldInOrder`): the plain edition first, then the oldest, then by folder. Search's row and the
 *    artist page's open the same pressing of Dummy (review: Search took the scan's order, and the
 *    scan sorts "20th Anniversary..." before the "Standard" it names the plain one beside it).
 */

import type { StoreAlbumResponse, StoreRow } from '../api/types'
import { ownedForGroup, type OwnedAlbum, type OwnedIndex } from './owned'

/** How many "Also" chips the album page draws, at most. */
export const ALSO_SHOWN = 3

/** A chip's words: the pressing's edition, else its year - "Also: 20th Anniversary Reissue 180gram". */
export function alsoLabel(row: Pick<StoreRow, 'edition' | 'year'>): string {
  const edition = (row.edition ?? '').trim()
  const year = String(row.year ?? '').trim().slice(0, 4)
  return `Also: ${edition || (/^\d{4}$/.test(year) ? `the ${year} pressing` : 'another pressing')}`
}

/** The other pressings you hold that Navidrome has, each once, never the album showing. */
export function alsoChips(answer: StoreAlbumResponse | null, showing: string): { navidromeId: string; label: string }[] {
  const chips: { navidromeId: string; label: string }[] = []
  for (const row of answer?.other_pressings ?? []) {
    const id = row.navidrome_id
    if (!id || id === showing || chips.some((chip) => chip.navidromeId === id)) continue
    chips.push({ navidromeId: id, label: alsoLabel(row) })
    if (chips.length >= ALSO_SHOWN) break
  }
  return chips
}

//? a MusicBrainz id as MusicBrainz writes one (lib/pressings.ts groupMbid's pattern)
const MBID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/**
 * The release group the album page's "Other pressings" chip opens - the bridge's word, from the
 * album's own folders (a folder tagged with a release id alone, an .m4a deadwax filed, carries none) -
 * or null, and no chip: lowercased, and only an id as MusicBrainz writes one.
 */
export function otherPressingsGroup(answer: Pick<StoreAlbumResponse, 'release_group_mbid'> | null): string | null {
  const id = (answer?.release_group_mbid ?? '').trim().toLowerCase()
  return MBID.test(id) ? id : null
}

/** "This pressing: 20th Anniversary Reissue 180gram · 2014 · FLAC" - null when the store holds none. */
export function pressingLine(present: readonly Pick<StoreRow, 'edition' | 'year' | 'formats'>[]): string | null {
  if (!present.length) return null
  const first = present[0]!
  const formats = [...new Set(present.flatMap((row) => row.formats ?? []))].map((format) => format.toUpperCase())
  const year = String(first.year ?? '').slice(0, 4)
  const parts = [(first.edition ?? '').trim(), /^\d{4}$/.test(year) ? year : '', formats.join('/')].filter(Boolean)
  return parts.length ? `This pressing: ${parts.join(' · ')}` : null
}

/**
 * (2.0.7) Whether Info's "This pressing: …" says anything the album's own line doesn't (the review's M6: it
 * repeated "1994 · FLAC" under "1994 · FLAC · 2 songs"): an edition, a year that isn't the album's, or formats
 * that aren't the album's one format - a reissue's year, a deluxe, the FLAC of an album Navidrome lists as
 * mixed. `album` is what the album line says: its year ('' unknown) and its one format ('' when it has none).
 */
export function pressingAdds(present: readonly Pick<StoreRow, 'edition' | 'year' | 'formats'>[], album: { year: string; format: string }): boolean {
  if (!present.length) return false
  const first = present[0]!
  if ((first.edition ?? '').trim()) return true
  const year = String(first.year ?? '').slice(0, 4)
  if (/^\d{4}$/.test(year) && year !== album.year) return true
  const formats = [...new Set(present.flatMap((row) => row.formats ?? []))].map((format) => format.toUpperCase()).join('/')
  return !!formats && formats !== album.format.toUpperCase()
}

/** Where it is on disk: the folder (each folder of a set kept one per disc), or null. */
export function folderLine(present: readonly Pick<StoreRow, 'path'>[]): string | null {
  const paths = present.map((row) => row.path).filter(Boolean)
  return paths.length ? paths.join('\n') : null
}

/** A folder's edition says it is the plain one: none at all, or the "Standard" the library's scan
 *  names the plain one when another edition sits beside it (src/library.py). */
export function plainEdition(edition: string | null | undefined): boolean {
  const label = (edition ?? '').trim().toLowerCase()
  return !label || label === 'standard'
}

const yearOf = (year: OwnedAlbum['year']): string => {
  const found = String(year ?? '').trim().slice(0, 4)
  return /^\d{4}$/.test(found) ? found : ''
}

/**
 * The copies of an album the library holds, in the order every screen opens and plays one: the
 * plain edition first, then the oldest (a year nobody wrote last), then by folder - the steady tie.
 */
export function heldInOrder<A extends Pick<OwnedAlbum, 'path' | 'edition' | 'year'>>(albums: readonly A[]): A[] {
  return [...albums].sort((a, b) => {
    const plain = (plainEdition(a.edition) ? 0 : 1) - (plainEdition(b.edition) ? 0 : 1)
    const [ya, yb] = [yearOf(a.year), yearOf(b.year)]
    return plain || (ya ? 0 : 1) - (yb ? 0 : 1) || ya.localeCompare(yb) || a.path.localeCompare(b.path)
  })
}

/** The releases of a MusicBrainz album the library holds, by its group id - what the bridge asks
 *  about, in heldInOrder's order, so the first Navidrome has is the copy the artist page opens too. */
export function heldReleases(index: OwnedIndex | null, groupId: string | null | undefined): string[] {
  if (!groupId) return []
  const ids = heldInOrder(ownedForGroup(index, { groupId }).held).map((album) => (album.release_mbid ?? '').trim().toLowerCase())
  return [...new Set(ids.filter(Boolean))]
}
