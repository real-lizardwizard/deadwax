import type { LibraryAlbum, LibraryTrack } from '../api/types'
import type { AlbumGroup } from './groupAlbums'

/**
 * The library as a tree, arranged one of four ways.
 *
 * By ARTIST it is a real tree: artists, their albums, an album's editions when you hold more
 * than one, then tracks. The other three - album name, release date, date added - list albums
 * directly under group headings, the way Windows 7's music library did "Arrange by": sorting
 * artist folders by an album's release date means nothing, so those sorts drop the artist level
 * rather than pretend.
 *
 * Pure, so the rules about what is visible and in what order live in one testable place rather
 * than in a component's render (see ui/test/tree.sim.cjs). The component draws `visibleRows()`
 * as a flat list with an indent per level - a flat list is what keyboard navigation walks anyway.
 */

export interface ArtistNode {
  id: string
  artist: string
  groups: AlbumGroup[]
  /** Albums under this artist with outstanding issues. */
  needsAttention: number
  hasNew: boolean
}

export type TreeSort = 'artist' | 'album' | 'released' | 'added'
export type SortDirection = 'asc' | 'desc'

export const TREE_SORTS: readonly TreeSort[] = ['artist', 'album', 'released', 'added']

/**
 * Where each sort starts. Names read A-Z. A release date reads oldest first, the same
 * chronological default as the search tab - an artist's output in the order they made it.
 * Date added reads newest first, because the question is almost always "what just arrived".
 */
export const DEFAULT_DIRECTION: Record<TreeSort, SortDirection> = {
  artist: 'asc', album: 'asc', released: 'asc', added: 'desc',
}

/*
 * Node ids. Prefixed by kind so a group key and a path can never collide, and built in one
 * place so the tree, the details pane and the reveal logic all agree on them. NEVER rebuild
 * one by hand: a group key carries a NUL (see groupAlbums), which is not what it looks like.
 */
export const artistNodeId = (artist: string) => `artist:${artist}`
export const groupNodeId = (group: AlbumGroup) => `group:${group.key}`
export const editionNodeId = (album: LibraryAlbum) => `edition:${album.path}`
export const trackNodeId = (album: LibraryAlbum, track: LibraryTrack) =>
  `track:${album.path}\u0000${track.filename}`

/**
 * When an album arrived, in unix seconds, or 0 when nothing says.
 *
 * The EARLIER of two imperfect clocks. `first_seen` is when deadwax first recorded the album:
 * exact for anything filed or found since install, but every album that was already there on
 * the first scan shares that one moment. The folder's mtime is when its contents last changed:
 * usually when it was ripped or downloaded, though a cover added later moves it. The earlier of
 * the two gives an existing library its real spread and a new import its real arrival.
 */
export function albumAddedAt(album: LibraryAlbum): number {
  const seen = album.first_seen ? Date.parse(album.first_seen) / 1000 : NaN
  const clocks = [seen, album.modified_at].filter((t) => Number.isFinite(t) && t > 0)
  return clocks.length ? Math.min(...clocks) : 0
}

/** An album's newest edition decides - a deluxe press that arrived today is news. */
export function groupAddedAt(group: AlbumGroup): number {
  return Math.max(0, ...group.editions.map(albumAddedAt))
}

const byName = (a: string, b: string) => a.localeCompare(b, undefined, { sensitivity: 'base' })
const albumThenArtist = (a: AlbumGroup, b: AlbumGroup) =>
  byName(a.album, b.album) || byName(a.artist, b.artist)

/**
 * Fold album groups under their artists, A-Z (or Z-A). Each artist's albums run by year,
 * whichever way the artists do - a discography reads in the order it was made.
 */
export function groupArtists(
  groups: readonly AlbumGroup[],
  isNew: (album: LibraryAlbum) => boolean,
  direction: SortDirection = 'asc',
): ArtistNode[] {
  const byArtist = new Map<string, ArtistNode>()

  for (const group of groups) {
    let node = byArtist.get(group.artist)
    if (!node) {
      node = { id: artistNodeId(group.artist), artist: group.artist, groups: [], needsAttention: 0, hasNew: false }
      byArtist.set(group.artist, node)
    }

    node.groups.push(group)
    if (group.needsAttention) node.needsAttention += 1
    node.hasNew ||= group.editions.some(isNew)
  }

  const nodes = [...byArtist.values()]

  for (const node of nodes) {
    //? undated albums sink rather than leading as year 0 - the same rule as the search sort
    node.groups.sort((a, b) => (a.year || '9999').localeCompare(b.year || '9999') || byName(a.album, b.album))
  }

  const flip = direction === 'desc' ? -1 : 1
  return nodes.sort((a, b) => flip * byName(a.artist, b.artist))
}

export type TreeLayout =
  | { by: 'artist'; artists: ArtistNode[] }
  | {
      by: 'album' | 'released' | 'added'
      groups: AlbumGroup[]
      /** The heading this album sits under: its initial, its year, or the month it arrived. */
      heading: (group: AlbumGroup) => string
    }

/** A title's initial for a heading, accents folded so "Élan" files under E and not its own. */
function initial(title: string): string {
  const first = title.trim().normalize('NFD').charAt(0).toLocaleUpperCase()
  return /\p{L}/u.test(first) ? first : '#'
}

function monthOf(seconds: number): string {
  if (!seconds) return 'Unknown date'
  return new Date(seconds * 1000).toLocaleDateString(undefined, { month: 'long', year: 'numeric' })
}

/**
 * Arrange the library for display.
 *
 * Whichever way a date sort runs, albums with no date SINK - reading a missing date as zero
 * puts everything MusicBrainz knows least about at the top of "oldest first", the trap the
 * search view's sort already fell into once.
 */
export function arrange(
  groups: readonly AlbumGroup[],
  sort: TreeSort,
  direction: SortDirection,
  isNew: (album: LibraryAlbum) => boolean,
): TreeLayout {
  if (sort === 'artist') return { by: 'artist', artists: groupArtists(groups, isNew, direction) }

  const flip = direction === 'desc' ? -1 : 1

  if (sort === 'album') {
    return {
      by: 'album',
      groups: [...groups].sort((a, b) => flip * albumThenArtist(a, b)),
      heading: (group) => initial(group.album),
    }
  }

  if (sort === 'released') {
    return {
      by: 'released',
      groups: [...groups].sort((a, b) =>
        Number(!a.year) - Number(!b.year)
        || flip * a.year.localeCompare(b.year)
        || albumThenArtist(a, b)),
      heading: (group) => group.year || 'Undated',
    }
  }

  return {
    by: 'added',
    groups: [...groups].sort((a, b) => {
      const at = groupAddedAt(a)
      const bt = groupAddedAt(b)
      return Number(!at) - Number(!bt) || flip * (at - bt) || albumThenArtist(a, b)
    }),
    heading: (group) => monthOf(groupAddedAt(group)),
  }
}

export type TreeRow =
  | { kind: 'artist'; id: string; level: 1; parent: null; open: boolean; node: ArtistNode }
  /** `withArtist` when the artist level is gone and the row has to say whose album it is. */
  | { kind: 'group'; id: string; level: number; parent: string | null; open: boolean; group: AlbumGroup; withArtist: boolean }
  | { kind: 'edition'; id: string; level: number; parent: string; open: boolean; album: LibraryAlbum; group: AlbumGroup }
  /** "1979", "September 2026", "T" - a group header. Not a node: nothing to select. */
  | { kind: 'heading'; id: null; level: 1; parent: null; label: string }
  /** A "Disc 2" divider. Not a node either: keyboard navigation skips both. */
  | { kind: 'disc'; id: null; level: number; parent: string; disc: number }
  | { kind: 'track'; id: string; level: number; parent: string; album: LibraryAlbum; track: LibraryTrack; match: boolean }

export interface TreeOpenState {
  /** Nodes opened by hand. */
  expanded: ReadonlySet<string>
  /**
   * While filtering, every artist with a match starts OPEN - a filter that found three albums
   * and showed you three closed artists would make you open each one to see what it found.
   * This is the set of those you have closed again, and it is reset whenever the filter changes.
   */
  closedWhileFiltering: ReadonlySet<string>
  filtering: boolean
  /** Tracks whose title matched the text filter. Their albums open to show just those tracks. */
  trackMatches: ReadonlySet<string>
}

function isOpen(id: string, state: TreeOpenState, autoOpen: boolean): boolean {
  if (state.expanded.has(id)) return true
  return autoOpen && !state.closedWhileFiltering.has(id)
}

function pushTracks(
  rows: TreeRow[], album: LibraryAlbum, parent: string, level: number,
  state: TreeOpenState, onlyMatches: boolean,
): void {
  //? only an album the files TAG as multi-disc is split - an untagged one is one run of tracks
  const split = album.disc_count > 1
  let disc: number | null = null

  for (const track of album.tracks) {
    const id = trackNodeId(album, track)
    const match = state.trackMatches.has(id)
    if (onlyMatches && !match) continue

    const trackDisc = track.disc ?? 1
    if (split && trackDisc !== disc) {
      disc = trackDisc
      rows.push({ kind: 'disc', id: null, level, parent, disc })
    }

    rows.push({ kind: 'track', id, level, parent, album, track, match })
  }
}

const matchesIn = (album: LibraryAlbum, state: TreeOpenState) =>
  album.tracks.some((track) => state.trackMatches.has(trackNodeId(album, track)))

/** One album and, if it is open, what is under it. */
function pushGroup(
  rows: TreeRow[], group: AlbumGroup, level: number, parent: string | null,
  state: TreeOpenState, withArtist: boolean,
): void {
  const id = groupNodeId(group)
  const matched = group.editions.some((album) => matchesIn(album, state))
  const byHand = state.expanded.has(id)
  const open = isOpen(id, state, matched)

  rows.push({ kind: 'group', id, level, parent, open, group, withArtist })
  if (!open) return

  if (group.editions.length === 1) {
    const only = group.editions[0]
    if (only) pushTracks(rows, only, id, level + 1, state, matched && !byHand)
    return
  }

  for (const album of group.editions) {
    const editionId = editionNodeId(album)
    const editionMatched = matchesIn(album, state)
    const editionOpen = isOpen(editionId, state, editionMatched)

    rows.push({ kind: 'edition', id: editionId, level: level + 1, parent: id, open: editionOpen, album, group })
    if (editionOpen) {
      pushTracks(rows, album, editionId, level + 2, state, editionMatched && !state.expanded.has(editionId))
    }
  }
}

/**
 * Every row currently on screen, in order.
 *
 * Track lists are only ever produced for an album that is open, which is the whole performance
 * story of this view: a library's worth of track rows is the 711ms freeze from the search view
 * waiting to happen, so nothing below an album exists until that album is opened. An album
 * opened only because the text filter matched some of its tracks shows just those tracks.
 */
export function visibleRows(layout: TreeLayout, state: TreeOpenState): TreeRow[] {
  const rows: TreeRow[] = []

  if (layout.by === 'artist') {
    for (const node of layout.artists) {
      const open = isOpen(node.id, state, state.filtering)
      rows.push({ kind: 'artist', id: node.id, level: 1, parent: null, open, node })
      if (open) {
        for (const group of node.groups) pushGroup(rows, group, 2, node.id, state, false)
      }
    }
    return rows
  }

  let heading: string | null = null
  for (const group of layout.groups) {
    const label = layout.heading(group)
    if (label !== heading) {
      heading = label
      rows.push({ kind: 'heading', id: null, level: 1, parent: null, label })
    }
    pushGroup(rows, group, 1, null, state, true)
  }

  return rows
}

/** What a selected node IS, resolved, for the details pane. */
export type Selected =
  | { kind: 'none' }
  | { kind: 'artist'; node: ArtistNode }
  /** An album you hold several pressings of, as a whole. Each pressing is its own 'album'. */
  | { kind: 'group'; group: AlbumGroup }
  | { kind: 'album'; album: LibraryAlbum; group: AlbumGroup }
  | { kind: 'track'; album: LibraryAlbum; group: AlbumGroup; track: LibraryTrack }

/**
 * Node id -> what it is, for every node in the library, filtered or not.
 *
 * Built over the WHOLE library rather than what the tree is showing, so a selection survives
 * being filtered out of view - the details pane keeps showing what you picked while you narrow
 * the tree, instead of going blank the moment the filter stops matching it. It is the same
 * whichever way the tree is arranged: an id means one thing however it is sorted.
 */
export function indexTree(artists: readonly ArtistNode[]): Map<string, Selected> {
  const index = new Map<string, Selected>()

  for (const node of artists) {
    index.set(node.id, { kind: 'artist', node })

    for (const group of node.groups) {
      const multiple = group.editions.length > 1
      const only = group.editions[0]

      //? a single-edition album IS its one release, so selecting it selects that release
      index.set(
        groupNodeId(group),
        multiple || !only ? { kind: 'group', group } : { kind: 'album', album: only, group },
      )

      for (const album of group.editions) {
        if (multiple) index.set(editionNodeId(album), { kind: 'album', album, group })
        for (const track of album.tracks) {
          index.set(trackNodeId(album, track), { kind: 'track', album, group, track })
        }
      }
    }
  }

  return index
}

/** The tree node that stands for this album: its group, or its edition row when it has siblings. */
export function nodeIdForAlbum(album: LibraryAlbum, group: AlbumGroup): string {
  return group.editions.length > 1 ? editionNodeId(album) : groupNodeId(group)
}

/** The ids that must be open for `id` to be on screen in this layout, outermost first. */
export function ancestorsOf(id: string, layout: TreeLayout): string[] {
  const placed: [string | null, AlbumGroup][] = layout.by === 'artist'
    ? layout.artists.flatMap((node) => node.groups.map((group): [string, AlbumGroup] => [node.id, group]))
    : layout.groups.map((group): [null, AlbumGroup] => [null, group])

  for (const [artistId, group] of placed) {
    const lead = artistId ? [artistId] : []
    const gid = groupNodeId(group)
    if (gid === id) return lead

    const multiple = group.editions.length > 1

    for (const album of group.editions) {
      const eid = editionNodeId(album)
      if (multiple && eid === id) return [...lead, gid]

      if (album.tracks.some((track) => trackNodeId(album, track) === id)) {
        return multiple ? [...lead, gid, eid] : [...lead, gid]
      }
    }
  }

  return []
}
