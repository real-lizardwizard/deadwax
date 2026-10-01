/**
 * What the app's Search tab draws from its two answers (2.0.0-player.13) - pure, pinned by
 * ui/test/searchQuery.sim.cjs beside the query rules.
 *
 * The library half is Navidrome's search3; the MusicBrainz half is release groups, less the ones
 * the library already holds - by RELEASE-GROUP id, through lib/owned.ts (the main page's own
 * matching, ported), because the library half already shows those. A name match ("maybe") is NOT
 * dropped: the name can't say it is the same album, so it stays on offer.
 */

import type { ReleaseGroup } from '../api/types'
import { foldName, ownedForGroup, type OwnedIndex } from './owned'
import { creditName } from './release'

/** How many distinct albums of the songs found are asked for as the answer lands, so a tap plays. */
export const SONG_ALBUMS_PREFETCHED = 5

/** The year an album first came out, from MusicBrainz's group; null when it doesn't say. */
export function groupYear(group: Pick<ReleaseGroup, 'first-release-date'>): string | null {
  const year = (group['first-release-date'] ?? '').slice(0, 4)
  return /^\d{4}$/.test(year) ? year : null
}

//? a secondary type says more about what a group IS than its primary one does
const SECONDARY_KIND: Record<string, (primary: string) => string> = {
  live: (primary) => `Live ${primary.toLowerCase()}`,
  compilation: () => 'Compilation',
  soundtrack: () => 'Soundtrack',
  remix: (primary) => `Remix ${primary.toLowerCase()}`,
  demo: () => 'Demo',
  'dj-mix': () => 'DJ mix',
  'mixtape/street': () => 'Mixtape',
  interview: () => 'Interview',
  audiobook: () => 'Audiobook',
  spokenword: () => 'Spoken word',
}

/** What kind of record a group is, in the board's words: "Album", "Live album", "EP", "Compilation". */
export function groupKind(group: Pick<ReleaseGroup, 'primary-type' | 'secondary-types'>): string {
  const primary = group['primary-type'] || ''
  for (const secondary of group['secondary-types'] ?? []) {
    const kind = SECONDARY_KIND[String(secondary).toLowerCase()]
    if (kind) return kind(primary || 'Album')
  }
  return primary || 'Release'
}

/**
 * A MusicBrainz row's second line: "Album · Portishead · 2008" - and "· in your library" on a row
 * the library turned out to hold after the list was drawn (it stays where it is; see notInLibrary).
 */
export function groupLine(group: ReleaseGroup, held = false): string {
  return [groupKind(group), creditName(group['artist-credit']), groupYear(group), held ? 'in your library' : '']
    .filter(Boolean).join(' · ')
}

/** Whether the library holds a group, by its id - false without an answer, which claims nothing. */
export function groupHeld(index: OwnedIndex | null, groupId: string): boolean {
  return !!index && ownedForGroup(index, { groupId }).held.length > 0
}

/**
 * The MusicBrainz half: the groups found, less those the library holds by group id. Kept in
 * MusicBrainz's order (relevance), so its first answer is still first.
 *
 * Worked out ONCE, as the list is drawn (Search waits a moment for the library's answer first),
 * and kept: an answer that lands later never takes a row away - the rows under the finger would
 * move up and the tap open another album (review). A row found to be held then says so instead
 * (groupLine's `held`).
 */
export function notInLibrary(groups: readonly ReleaseGroup[], index: OwnedIndex | null): ReleaseGroup[] {
  if (!index) return [...groups]
  return groups.filter((group) => !groupHeld(index, group.id))
}

/** The library half's top result: an artist whose name IS what was typed. */
export function topArtist<A extends { name?: string }>(artists: readonly A[], text: string): A | null {
  const typed = foldName(text)
  return (typed && artists.find((artist) => foldName(artist.name) === typed)) || null
}

/** The first few distinct albums of the songs found, in order: what is asked for, so a song's tap plays. */
export function albumsToPrefetch(songs: readonly { albumId?: string | null }[], count = SONG_ALBUMS_PREFETCHED): string[] {
  const ids: string[] = []
  for (const song of songs) {
    if (song.albumId && !ids.includes(song.albumId)) ids.push(song.albumId)
    if (ids.length >= count) break
  }
  return ids
}

/** Where a song sits in its album's own answer, by its id; -1 when it isn't there. */
export function songIndex(songs: readonly { id: string }[] | undefined, id: string): number {
  return (songs ?? []).findIndex((song) => song.id === id)
}

/** "Artist · 2 albums in your library". */
export function artistLine(albumCount: number | null | undefined): string {
  const count = albumCount ?? 0
  return count ? `Artist · ${count} ${count === 1 ? 'album' : 'albums'} in your library` : 'Artist'
}
