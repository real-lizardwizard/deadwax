/**
 * The artist page (2.0.0-player.17), as pure functions - pinned by ui/test/artist.sim.cjs rather than
 * found by tapping.
 *
 * An artist is reached two ways, and the page's id says which (lib/appRoutes.ts): Navidrome's artist
 * id - from Search, Library > Artists, an album you have, Info - or `mb:<mbid>`, an artist known only
 * by MusicBrainz, from the album you don't have. Each side is found from the other here:
 *
 *  - Navidrome's artist -> MusicBrainz id (`artistMbid`): Navidrome's own `musicBrainzId` (the album
 *    artist's id it read from the files), else what /library/owned says the albums Navidrome has of
 *    theirs are by (`albumartist_mbids`) - only when every one that says agrees, and only a SINGLE
 *    artist's id (a collaboration's ids say who else, not who this is). Neither: no discography,
 *    rather than a guess.
 *  - MusicBrainz id -> Navidrome's artist (`libraryArtistFor`): the artist carrying that id; else the
 *    one /library/owned's albums by that id are filed under, by name; else, only for an artist
 *    Navidrome has no id for, the one name MusicBrainz gives - believed only when exactly one artist
 *    answers to it (two bands share a name more often than you'd think; CLAUDE.md's rule for the
 *    main page's artist page too).
 *
 * THE ROWS (`artistRows`): the artist's albums from MusicBrainz's browse - complete, not a search's
 * best matches - with what the library holds of each, and every album Navidrome has of theirs that
 * no row claimed (an untagged rip, an EP, a live album with Studio only on) as a row of its own, so
 * nothing you have is ever left off the page. A group is held by the store's word (/library/owned:
 * folders tagged with its group or release ids) and opened as the Navidrome album holding one of
 * those releases - in idBridge.ts's heldInOrder: its plain edition first, then its oldest; a
 * Navidrome album no folder ties to a group is claimed by a group of its exact title, the only one
 * of that title. In order of year, oldest first, the undated last; then by title.
 *
 * Albums Navidrome has that no MusicBrainz row claims - every one of them while MusicBrainz hasn't
 * answered, or can't - are ONE row per album the library's folders say they are (their release
 * group), keyed as MusicBrainz's row for it would be (`group:<id>`): so its answer landing neither
 * splits Dummy's two pressings into two rows nor changes a row's key under a finger (review), and
 * Play never plays both. "2 editions" counts the releases held, not the folders: a set kept one
 * folder per disc, or a FLAC and an MP3 of one release, is one.
 *
 * Until /library/owned has answered (`index` null), a row only Navidrome claims is "in your library";
 * every other row says neither - no answer must never read as "you hold none of this" (useOwned).
 *
 * PLAY AND SHUFFLE play one copy of each album you have (`playOrder`): a row's album, in the page's
 * order - never both editions of Dummy, which would play every song twice.
 */

import type { ArtistCredit, ArtistFactsLight, ReleaseGroup } from '../api/types'
import { heldInOrder } from './idBridge'
import { foldName, ownedForGroup, type OwnedAlbum, type OwnedIndex } from './owned'
import { groupKind, groupYear } from './searchResults'

/** An artist page's id for one known only by MusicBrainz: `mb:<mbid>`. */
export const MB_PREFIX = 'mb:'

const MBID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** A MusicBrainz id as MusicBrainz writes one, or null. */
export function mbidOf(value: string | null | undefined): string | null {
  const id = (value ?? '').trim().toLowerCase()
  return MBID.test(id) ? id : null
}

export interface ArtistRef {
  /** Navidrome's artist id */
  navidrome: string | null
  /** MusicBrainz's artist id */
  mbid: string | null
}

/** What an artist page's id names: Navidrome's artist, or (`mb:`) MusicBrainz's. */
export function artistRef(id: string): ArtistRef {
  if (id.startsWith(MB_PREFIX)) return { navidrome: null, mbid: mbidOf(id.slice(MB_PREFIX.length)) }
  return { navidrome: id.trim() || null, mbid: null }
}

/** The page id for an artist: Navidrome's id when there is one, else `mb:<mbid>`; null for neither. */
export function artistPageId(ref: { navidrome?: string | null; mbid?: string | null }): string | null {
  if (ref.navidrome) return ref.navidrome
  const mbid = mbidOf(ref.mbid)
  return mbid ? `${MB_PREFIX}${mbid}` : null
}

/** An artist as Navidrome answers - only what these read. */
export interface LibraryArtistFields {
  id: string
  name?: string
  musicBrainzId?: string
}

/** An album Navidrome has - only what these read. */
export interface HeldAlbumFields {
  id: string
  name?: string
  year?: number
  coverArt?: string
  musicBrainzId?: string
}

/** Every album /library/owned listed, once each, whichever way the index holds it. */
function everyOwned(index: OwnedIndex | null): OwnedAlbum[] {
  if (!index) return []
  const seen = new Map<string, OwnedAlbum>()
  for (const map of [index.byRelease, index.byGroup, index.byName]) {
    for (const albums of map.values()) for (const album of albums) seen.set(album.path, album)
  }
  return [...seen.values()]
}

/** The one artist an album is by, as MusicBrainz ids say - null for none, or a collaboration. */
function soleArtist(album: OwnedAlbum): string | null {
  const ids = (album.albumartist_mbids ?? []).map(mbidOf).filter((id): id is string => !!id)
  return ids.length === 1 ? ids[0]! : null
}

/**
 * Navidrome's artist's MusicBrainz id: their own `musicBrainzId`, else what the library's folders of
 * the albums Navidrome has of theirs say they are by (by release id, else by the artist's name on
 * an untagged folder) - only when every folder that says agrees. Null otherwise.
 */
export function artistMbid(artist: LibraryArtistFields | null, held: readonly HeldAlbumFields[], index: OwnedIndex | null): string | null {
  const own = mbidOf(artist?.musicBrainzId)
  if (own || !artist) return own
  const releases = new Set(held.map((album) => mbidOf(album.musicBrainzId)).filter((id): id is string => !!id))
  const name = foldName(artist.name)
  const says = new Set<string>()
  for (const album of everyOwned(index)) {
    const byRelease = !!album.release_mbid && releases.has(album.release_mbid.toLowerCase())
    const byName = !releases.size && !!name && foldName(album.artist) === name
    if (!byRelease && !byName) continue
    const id = soleArtist(album)
    if (id) says.add(id)
  }
  return says.size === 1 ? [...says][0]! : null
}

/**
 * Navidrome's artist for a MusicBrainz id: the one carrying it; else the one the library's albums by
 * that id are filed under (their folders' artist name); else - only an artist Navidrome has no id
 * for - the one answering to `name`, MusicBrainz's name for them. Each believed only when exactly one
 * artist answers. Null otherwise.
 */
export function libraryArtistFor<A extends LibraryArtistFields>(
  artists: readonly A[], mbid: string | null, index: OwnedIndex | null, name?: string | null,
): A | null {
  const id = mbidOf(mbid)
  if (!id) return null
  const carrying = artists.filter((artist) => mbidOf(artist.musicBrainzId) === id)
  if (carrying.length) return carrying.length === 1 ? carrying[0]! : null

  const one = (names: Set<string>): A | null => {
    if (!names.size) return null
    const found = artists.filter((artist) => names.has(foldName(artist.name)) && !mbidOf(artist.musicBrainzId))
    return found.length === 1 ? found[0]! : null
  }
  const filedUnder = new Set(everyOwned(index).filter((album) => soleArtist(album) === id).map((album) => foldName(album.artist)).filter(Boolean))
  if (filedUnder.size) return one(filedUnder)
  const named = foldName(name)
  return named ? one(new Set([named])) : null
}

/** One row of the artist page's albums. */
export interface ArtistRow {
  /** stable: the group's id, or the Navidrome album's */
  key: string
  title: string
  year: string | null
  /** the album you have, by Navidrome's id - what the row opens; null for one held only by the
   *  store's word (Navidrome hasn't found it, or holds it under ids nobody matched) */
  albumId: string | null
  coverArt: string | null
  /** the MusicBrainz album, when the row is one - what a row not held opens, and Get gets */
  group: ReleaseGroup | null
  /** in the library; null while the library hasn't said (/library/owned not answered) */
  held: boolean | null
  /** how many releases of it the library holds: "2 editions" past one */
  editions: number
  /** the releases the library holds of it - what the id bridge asks Navidrome about when the row
   *  has no album id */
  releases: string[]
  /** what MusicBrainz calls it, when it isn't a plain album: "Live album", "Compilation" */
  kind: string | null
}

const yearOf = (year: number | undefined): string | null => (year && year > 0 ? String(year) : null)

/** Whether the library's folders of a release say which group it is - false for no release id. */
function knownGroup(index: OwnedIndex | null, release: string | null | undefined): boolean {
  return !!groupOfRelease(index, release)
}

/** The release group the library's folders of a release say it is, or null. */
function groupOfRelease(index: OwnedIndex | null, release: string | null | undefined): string | null {
  const id = mbidOf(release)
  if (!id || !index) return null
  return (index.byRelease.get(id) ?? []).find((album) => !!album.release_group_mbid)?.release_group_mbid ?? null
}

/** How many releases these copies are: each release once, each folder or album saying none once. */
function editionsOf(folders: readonly OwnedAlbum[], albums: readonly HeldAlbumFields[]): number {
  const seen = new Set<string>()
  for (const folder of folders) seen.add(mbidOf(folder.release_mbid) ? `r:${mbidOf(folder.release_mbid)}` : `f:${folder.path}`)
  for (const album of albums) seen.add(mbidOf(album.musicBrainzId) ? `r:${mbidOf(album.musicBrainzId)}` : `a:${album.id}`)
  return seen.size
}

/**
 * The artist page's rows - see the module's note. `groups` null: MusicBrainz hasn't answered (or
 * can't, or doesn't know who this is), and the albums Navidrome has are the whole list. `index`
 * null: /library/owned hasn't answered, and only Navidrome's albums say what you hold.
 */
export function artistRows(
  held: readonly HeldAlbumFields[], groups: readonly ReleaseGroup[] | null, index: OwnedIndex | null,
): ArtistRow[] {
  const byRelease = new Map<string, HeldAlbumFields>()
  for (const album of held) {
    const release = mbidOf(album.musicBrainzId)
    if (release && !byRelease.has(release)) byRelease.set(release, album)
  }
  const claimed = new Set<string>()
  const rows: ArtistRow[] = []

  //? what the library holds of a group: its folders in the order a copy is opened, the releases
  //? they are, and the Navidrome albums of those releases nobody claimed yet
  const holdingOf = (groupId: string) => {
    const holding = heldInOrder(ownedForGroup(index, { groupId }).held)
    const releases = [...new Set(holding.map((album) => mbidOf(album.release_mbid)).filter((id): id is string => !!id))]
    const albums = releases.map((release) => byRelease.get(release)).filter((album): album is HeldAlbumFields => !!album && !claimed.has(album.id))
    return { holding, releases, albums }
  }

  //? the titles more than one group shares: a name can't say which of them an untagged album is
  const titles = new Map<string, number>()
  for (const group of groups ?? []) titles.set(foldName(group.title), (titles.get(foldName(group.title)) ?? 0) + 1)

  const seen = new Set<string>()
  for (const group of groups ?? []) {
    if (!group.id || seen.has(group.id)) continue
    seen.add(group.id)
    const { holding, releases, albums } = holdingOf(group.id)
    //? an album Navidrome has that no folder ties to a group - no release id at all, or one whose
    //? folder carries no group id (an .m4a deadwax filed: Easy MP4 has no key for it) - claimed by
    //? the one group of its exact title
    const title = foldName(group.title)
    if (title && titles.get(title) === 1) {
      const named = held.filter((album) =>
        !claimed.has(album.id) && !albums.includes(album) && foldName(album.name) === title && !knownGroup(index, album.musicBrainzId))
      //? oldest first, as the library's copies are: before /library/owned answers, Navidrome's CD of
      //? Dummy is the row's album as it is after
      albums.push(...named.sort((a, b) => (a.year || 9999) - (b.year || 9999) || a.id.localeCompare(b.id)))
    }
    for (const album of albums) claimed.add(album.id)
    const kind = groupKind(group)
    const mine = holding.length > 0 || albums.length > 0
    rows.push({
      key: `group:${group.id}`,
      title: group.title ?? '',
      year: groupYear(group),
      albumId: albums[0]?.id ?? null,
      coverArt: albums[0]?.coverArt ?? null,
      group,
      held: mine ? true : index ? false : null,
      editions: editionsOf(holding, albums),
      releases,
      kind: kind === 'Album' ? null : kind,
    })
  }

  //? the albums no MusicBrainz row claimed: one row per group the library's folders say they are -
  //? keyed as MusicBrainz's row for it would be - else one each
  for (const album of held) {
    if (claimed.has(album.id)) continue
    const groupId = groupOfRelease(index, album.musicBrainzId)
    if (groupId && !seen.has(groupId)) {
      seen.add(groupId)
      const { holding, releases, albums } = holdingOf(groupId)
      if (!albums.includes(album)) albums.push(album)
      for (const each of albums) claimed.add(each.id)
      const years = albums.map((each) => each.year ?? 0).filter((year) => year > 0)
      rows.push({
        key: `group:${groupId}`,
        title: albums[0]!.name ?? '',
        year: yearOf(years.length ? Math.min(...years) : undefined),
        albumId: albums[0]!.id,
        coverArt: albums[0]!.coverArt ?? null,
        group: null,
        held: true,
        editions: editionsOf(holding, albums),
        releases,
        kind: null,
      })
      continue
    }
    claimed.add(album.id)
    rows.push({
      key: `album:${album.id}`,
      title: album.name ?? '',
      year: yearOf(album.year),
      albumId: album.id,
      coverArt: album.coverArt ?? null,
      group: null,
      held: true,
      editions: 1,
      releases: mbidOf(album.musicBrainzId) ? [mbidOf(album.musicBrainzId)!] : [],
      kind: null,
    })
  }

  return rows.sort((a, b) =>
    (a.year === null ? 1 : 0) - (b.year === null ? 1 : 0)
    || (a.year ?? '').localeCompare(b.year ?? '')
    || foldName(a.title).localeCompare(foldName(b.title))
    || a.key.localeCompare(b.key))
}

/** A row's second line, the board's: "1994 · in your library · 2 editions", "2008 · not in your
 *  library", "1998 · Live album · not in your library" - and neither while the library hasn't said. */
export function rowLine(row: Pick<ArtistRow, 'year' | 'held' | 'editions' | 'kind'>): string {
  return [
    row.year,
    row.kind,
    row.held === null ? null : row.held ? 'in your library' : 'not in your library',
    row.held && row.editions > 1 ? `${row.editions} editions` : null,
  ].filter(Boolean).join(' · ')
}

/** What Play and Shuffle play: one album of each row you have, in the page's order. */
export function playOrder(rows: readonly Pick<ArtistRow, 'albumId'>[]): string[] {
  return [...new Set(rows.map((row) => row.albumId).filter((id): id is string => !!id))]
}

/**
 * Under Play and Shuffle: "Plays the 2 albums you have" - or, with some not answered, how many. With
 * nothing to play, what Navidrome said (`library`): still asking, or none of theirs - the line is
 * drawn from the first frame wherever albums could be had, so its answer moves nothing (review).
 */
export function playsLine(albums: number, inHand: number, settled: boolean, library: 'asking' | 'done' | 'failed' = 'done'): string {
  if (!albums) return library === 'asking' ? 'Looking for their albums in your library…' : library === 'done' ? 'Navidrome has none of their albums to play' : ''
  const all = albums === 1 ? 'Plays the album you have' : `Plays the ${albums} albums you have`
  if (!settled) return `Getting the songs of the ${albums === 1 ? 'album' : `${albums} albums`} you have…`
  if (inHand >= albums) return all
  if (!inHand) return "Navidrome didn't send the songs"
  return `Plays ${inHand} of the ${albums} albums you have - Navidrome didn't send the rest`
}

/** Who they are, in a line: "Group · Bristol · since 1991", "Group · London · 1965 to 2014". */
export function factsLine(facts: Pick<ArtistFactsLight, 'type' | 'area' | 'begin_area' | 'country' | 'began' | 'ended' | 'ended_on' | 'disambiguation'> | null): string {
  if (!facts) return ''
  const began = (facts.began ?? '').slice(0, 4)
  const ended = (facts.ended_on ?? '').slice(0, 4)
  const span = began && ended ? `${began} to ${ended}` : began ? (facts.ended ? `${began}, ended` : `since ${began}`) : ended ? `until ${ended}` : ''
  return [facts.type, facts.begin_area || facts.area || facts.country, span].filter(Boolean).join(' · ')
}

/**
 * Start each of `items` in turn, at most `limit` at a time, the next as each settles - in their order,
 * and only while `going()` (a newer set superseding this one stops it). An artist page asks for
 * every album Play plays this way (review): a hundred compilations of Various Artists asked for at
 * once queued the page's own covers behind them, on the browser's few connections to deadwax.
 */
export function inTurns<T>(items: readonly T[], limit: number, start: (item: T) => Promise<unknown>, going: () => boolean = () => true): void {
  let next = 0
  const more = () => {
    if (next >= items.length || !going()) return
    const item = items[next++]!
    start(item).then(more, more)
  }
  for (let count = 0; count < Math.max(1, limit); count++) more()
}

/** "2 albums in your library" - '' for none, or an artist Navidrome didn't count. */
export function albumCountLine(count: number | null | undefined): string {
  const albums = count ?? 0
  return albums > 0 ? `${albums} ${albums === 1 ? 'album' : 'albums'} in your library` : ''
}

/**
 * The one artist an album is credited to, by MusicBrainz id - what the album you don't have links to
 * (2.0.0-player.17). Null for a collaboration (whose page would it be?) or a credit with no id.
 */
export function soleCredit(credits: readonly ArtistCredit[] | null | undefined): { mbid: string; name: string } | null {
  if (!credits || credits.length !== 1) return null
  const mbid = mbidOf(credits[0]!.artist?.id)
  const name = (credits[0]!.name || credits[0]!.artist?.name || '').trim()
  return mbid && name ? { mbid, name } : null
}

/** Library > Artists' orders (2.0.0-player.17). */
export type ArtistOrder = 'name' | 'albums'

export const ARTIST_ORDERS: readonly { id: ArtistOrder; label: string }[] = [
  { id: 'name', label: 'Name' },
  { id: 'albums', label: 'Most albums' },
]

/**
 * Library > Artists in an order: Navidrome's own by name (a leading "The" set aside, as its index
 * files them), or by how many albums of theirs the library holds, most first - a tie in Navidrome's
 * order.
 */
export function sortArtists<A extends { albumCount?: number }>(artists: readonly A[], order: ArtistOrder): A[] {
  if (order === 'name') return [...artists]
  return artists
    .map((artist, index) => ({ artist, index }))
    .sort((a, b) => (b.artist.albumCount ?? 0) - (a.artist.albumCount ?? 0) || a.index - b.index)
    .map(({ artist }) => artist)
}

/** "114 albums", "1 artist" - the Library's count beside the sort, once the whole list is in. */
export function countText(count: number | null, one: string, many: string): string {
  return count === null ? '' : `${count} ${count === 1 ? one : many}`
}
