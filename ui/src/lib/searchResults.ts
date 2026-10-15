/**
 * What the app's Search tab draws from its two answers (2.0.0-player.13) - pure, pinned by
 * ui/test/searchQuery.sim.cjs beside the query rules.
 *
 * The library half is Navidrome's search3; the MusicBrainz half is release groups, less the ones
 * the library already holds - by RELEASE-GROUP id, through lib/owned.ts (the main page's own
 * matching, ported), because the library half already shows those. A name match ("maybe") is NOT
 * dropped: the name can't say it is the same album, so it stays on offer. "More from MusicBrainz"
 * (2.0.0-player.50) appends the next page by the same rule (appendPage, morePages, morePageWords).
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

/**
 * How far into one search's answers "More from MusicBrainz" goes (2.0.0-player.50): the route's own
 * bound, FULLY_SEARCH_OFFSET_MAX in src/routes/search_musicbrainz.py, which refuses a page past it -
 * tests/test_musicbrainz_routes.py holds the two to one number.
 */
export const MUSICBRAINZ_OFFSET_MAX = 1000

/**
 * One more page of the MusicBrainz half, appended below what is there ("More from MusicBrainz",
 * 2.0.0-player.50): the groups not already got - MusicBrainz's paging can hand one back again as its
 * relevance ties shift, and a row twice would be one key twice - and, of those, the ones shown: held
 * albums left out as the first page leaves them (notInLibrary, by the library's answer as the page
 * lands). Nothing already drawn moves or goes; `added` is how many rows the page brought, `held` how
 * many of its NEW groups the library holds - never a repeat, nor anything of an empty page (review: a
 * page of repeats, or none, said its albums were all in your library).
 */
export function appendPage(
  groups: readonly ReleaseGroup[],
  shown: readonly ReleaseGroup[],
  page: readonly ReleaseGroup[],
  index: OwnedIndex | null,
): { groups: ReleaseGroup[]; shown: ReleaseGroup[]; added: number; held: number } {
  const known = new Set(groups.map((group) => group.id))
  const fresh: ReleaseGroup[] = []
  for (const group of page) {
    if (known.has(group.id)) continue
    known.add(group.id)
    fresh.push(group)
  }
  const showing = notInLibrary(fresh, index)
  return { groups: [...groups, ...fresh], shown: [...shown, ...showing], added: showing.length, held: fresh.length - showing.length }
}

/**
 * What a page "More from MusicBrainz" brought, in words (2.0.0-player.50) - `note` drawn under the rows,
 * `said` to VoiceOver: rows added are said only to VoiceOver (they are on the screen); a page whose new
 * albums the library holds every one of says so, by how many there were; a page that brought nothing new
 * - none at all, or only albums already drawn - says that, never that they are in your library (review).
 */
export function morePageWords(added: number, held: number): { note: string | null; said: string } {
  if (added) return { note: null, said: `${added} more ${added === 1 ? 'album' : 'albums'} from MusicBrainz` }
  if (held === 1) return { note: 'The next album MusicBrainz found is in your library already.', said: 'The next album is in your library already' }
  if (held) return { note: `The next ${held} albums MusicBrainz found are all in your library already.`, said: `The next ${held} albums are all in your library already` }
  return { note: 'MusicBrainz sent nothing new.', said: 'MusicBrainz sent nothing new' }
}

/**
 * Whether there is another page to ask MusicBrainz for (2.0.0-player.50): 'more' - "More from
 * MusicBrainz" asks for it; 'end' - every answer is in; 'far' - more match, but past
 * MUSICBRAINZ_OFFSET_MAX, so narrowing the search is the way on. `next` is where the next page starts:
 * every answer got so far, held ones included. `count` is MusicBrainz's own total - or, from a server
 * that doesn't pass it on, unknown, when a full last page is taken to mean there may be more. A page
 * that brought nothing ends it whatever the count says, so a count that runs ahead of the answers can
 * never keep a button that asks for nothing.
 */
export function morePages(next: number, count: number | null | undefined, lastPage: number, limit: number): 'more' | 'end' | 'far' {
  if (lastPage <= 0) return 'end'
  const remaining = typeof count === 'number' ? next < count : lastPage >= limit
  if (!remaining) return 'end'
  return next <= MUSICBRAINZ_OFFSET_MAX ? 'more' : 'far'
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
