import type { StoreAlbumResponse } from '../api/types'
import { formatSize } from './format'

/**
 * An album page's Properties (2.0.0-player.44) - pure, pinned by inspector.sim.cjs.
 *
 * What the main page's details pane says of an album that the app's album page didn't (the parity audit's
 * gaps): its year against this pressing's, its size, its release linked to musicbrainz.org, and when
 * deadwax first saw it - and whether deadwax filed it. On both frames, for everyone, from the id bridge
 * the page asks already (GET /store/album by Navidrome's id): its `present` rows carry what the saved scan
 * and the folder's review row say (src/routes/store_album.py, `_facts`). A set kept one folder per disc is
 * one album: its sizes added, the earliest first seen, filed by deadwax when any folder was.
 */

/** One line of Properties: its label, its words, and the release it links to (musicbrainz.org) when it does. */
export interface PropertyRow {
  label: string
  text: string
  /** the release id the words link to, opening beside the app */
  release?: string
  /** a line saying what isn't there - drawn quieter */
  quiet?: boolean
}

/** The release's page on musicbrainz.org. */
export const releaseUrl = (release: string): string => `https://musicbrainz.org/release/${encodeURIComponent(release)}`

/** What the release line says of an album with none to link to. */
export const NO_RELEASE = 'Not tagged with a MusicBrainz release'

/** "1994 (this pressing 2014)" when the album's original year isn't this pressing's - the main page's
 *  "(this press …)" - else the one year; '' for neither. */
export function yearWords(year: string | null | undefined, original: string | null | undefined): string {
  const pressing = String(year ?? '').trim()
  const first = String(original ?? '').trim()
  if (first && pressing && first !== pressing) return `${first} (this pressing ${pressing})`
  return first || pressing
}

/** "14 October 2026, filed by deadwax" - a date in the reader's own words, '' for one that isn't a date. */
export function firstSeenWords(iso: string | null | undefined, imported: boolean, locale?: string): string {
  if (!iso) return ''
  const when = new Date(iso)
  if (Number.isNaN(when.getTime())) return ''
  const date = when.toLocaleDateString(locale, { day: 'numeric', month: 'long', year: 'numeric' })
  return `${date}${imported ? ', filed by deadwax' : ''}`
}

/**
 * The album page's Properties - null until the bridge has answered (or failed), so nothing is drawn that
 * the answer would then change. The release is the bridge's (Navidrome's reading of the files), else the
 * album's own `musicBrainzId`; "not tagged" only when the album's own answer from Navidrome has SAID there
 * is none - its `musicBrainzId` '' (a field Navidrome always sends, notes/app.md; the album page passes ''
 * too for an answer of its own that came without it, `releaseSaid`) - and never from the bridge's null
 * alone (review): that is also its answer when Navidrome couldn't be asked, or has no album by that id
 * (src/routes/store_album.py `navidrome_release` swallows both), and an old address after a rescan drew
 * "not tagged" under "Navidrome has nothing by that id". With no word of its own (undefined: still to come,
 * or failed) nothing is said of the release. The rest comes from the store's folders of it, each line left
 * out when no folder says.
 */
export function albumProperties(
  store: StoreAlbumResponse | null,
  failed: boolean,
  musicBrainzId: string | null | undefined,
  locale?: string,
): PropertyRow[] | null {
  if (!store && !failed) return null
  const present = store?.present ?? []
  const first = present[0]
  const rows: PropertyRow[] = []

  const year = first ? yearWords(first.year, first.original_year) : ''
  if (year) rows.push({ label: 'Year', text: year })

  const sizes = present.map((row) => row.size).filter((size): size is number => typeof size === 'number' && size > 0)
  //? only when every folder said: a set's size from one disc's folder would be half the truth
  if (sizes.length && sizes.length === present.length) rows.push({ label: 'Size', text: formatSize(sizes.reduce((sum, size) => sum + size, 0)) })

  const release = (store?.release_mbid || musicBrainzId || '').trim()
  if (release) rows.push({ label: 'Release', text: release, release })
  else if (musicBrainzId === '') rows.push({ label: 'Release', text: NO_RELEASE, quiet: true })

  const seen = present.map((row) => row.first_seen).filter((when): when is string => !!when).sort()
  const filed = present.some((row) => row.imported)
  const seenWords = seen.length ? firstSeenWords(seen[0], filed, locale) : ''
  if (seenWords) rows.push({ label: 'First seen', text: seenWords })

  return rows
}
