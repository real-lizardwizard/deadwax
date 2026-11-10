/**
 * The Library's shelves (2.0.0-player.59, a better Library) - pure, pinned by ui/test/shelves.sim.cjs: the seven album
 * sorts and the two artist orders, the headers each groups by, the index down the right edge, Find's matching and
 * words, and the blocks the shelf draws in. See "A better Library" in notes/app-library.md.
 *
 * SORTS. One list for your albums and the store's (one choice per device, deadwax-player-order, whose four old values
 * mean what they did), sorted HERE, in the browser, the same way for both scopes - so the store's Artist order is
 * deadwax's, no longer Navidrome's (compilations last, then title). Names compare by lib/owned.ts's foldName (accents,
 * case, a leading "The", "&" folded), with the `#` bucket - a fold key not starting a-z: digits, symbols, non-Latin
 * scripts, nothing at all - after Z, as Apple puts it. Ties keep the order the list came in (Navidrome's).
 *
 * KEYS ONCE. Every album's fold keys are made once per album object (a WeakMap) - about 3,000 foldName calls for a
 * library of 3,000 where folding inside the comparator made about 70,000.
 *
 * WHOSE "RECENTLY ADDED" (2.0.11 - James: "Recently added should be for the user's library, not deadwax's"). The
 * date is a per-list choice, `AddedBy`: the collection's lists (the store's, and everything with logins off) go by
 * `created`, when the COLLECTION got the album; your albums (`you`) by `starred`, when it entered YOUR library -
 * deadwax stars an album as you when it is yours (src/stars.py), and a star you make in Amperfy is the same. Stars
 * made within SAME_MOMENT_MS of each other are one moment - a batch deadwax starred in one go, the first admin's seed
 * above all - and inside one, `created` decides, then the order the list came in. Never `starred` over the
 * collection: a store album carries it only when the asker starred it, so the keys would be mixed.
 */

import type { Album, Artist } from '../player/api'
import type { ArtistOrder } from './artistPage'
import { foldName } from './owned'

export type AlbumSort = 'alphabeticalByArtist' | 'alphabeticalByName' | 'newest' | 'byYearDesc' | 'byYearAsc' | 'recent' | 'frequent'

/** The album sorts, in the select's order: the four that existed keep the Subsonic ids a device saved. */
export const ALBUM_SORTS: readonly { id: AlbumSort; label: string }[] = [
  { id: 'alphabeticalByArtist', label: 'Artist' },
  { id: 'alphabeticalByName', label: 'Title' },
  { id: 'newest', label: 'Recently added' },
  { id: 'byYearDesc', label: 'Year, newest first' },
  { id: 'byYearAsc', label: 'Year, oldest first' },
  { id: 'recent', label: 'Recently played' },
  { id: 'frequent', label: 'Most played' },
]

/** Artist (each artist's albums oldest first): Recently added has its own place now - the root's grid and See all. */
export const DEFAULT_ALBUM_SORT: AlbumSort = 'alphabeticalByArtist'

export function isAlbumSort(value: unknown): value is AlbumSort {
  return ALBUM_SORTS.some((sort) => sort.id === value)
}

/** A sort as a device saved it: one of the seven, anything else (nothing, an old or mistyped value) the default. */
export function albumSortFrom(saved: string | null | undefined): AlbumSort {
  return isAlbumSort(saved) ? saved : DEFAULT_ALBUM_SORT
}

/** An artist order as a device saved it (deadwax-player-artist-order): Name unless Most albums. */
export function artistOrderFrom(saved: string | null | undefined): ArtistOrder {
  return saved === 'albums' ? 'albums' : 'name'
}

/** A list cut into groups: each with its header's words (null for a sort without headers) and its items. */
export interface Group<T> {
  key: string
  label: string | null
  items: T[]
}

/** The `#` group: what no letter heads. */
export const OTHER_INITIAL = '#'

/** A fold key's group: its first letter a-z, as a capital; anything else `#`. */
export function initialOf(foldKey: string): string {
  const first = foldKey.charAt(0)
  return first >= 'a' && first <= 'z' ? first.toUpperCase() : OTHER_INITIAL
}

const time = (value: unknown): number | null => {
  //? only an ISO string is a date: the dev stand-in's float `created` is "Date unknown", never a guess
  const parsed = typeof value === 'string' ? Date.parse(value) : NaN
  return Number.isNaN(parsed) ? null : parsed
}

/** Whose Recently added a list is (2.0.11): the collection's - when the collection got each album, Navidrome's
 *  `created` - or yours, when each entered your library, its `starred` (see the note at the top). */
export type AddedBy = 'collection' | 'you'

/** Stars this close together are one moment (2.0.11): deadwax stars a batch one album after another - the first
 *  admin's seed is the whole collection, 25 to a pass, a pass after another at once - so no two share an instant,
 *  but the gaps between them are a second or two. A person's own Adds are further apart than this as a rule; two
 *  that aren't land in the collection's order between themselves. */
export const SAME_MOMENT_MS = 30_000

/** What a sort compares an album by, made once per album. */
export interface AlbumKeys {
  artist: string
  title: string
  initial: string
  titleInitial: string
  /** null: no year, or 0 */
  year: number | null
  created: number | null
  /** (2.0.11) when the asker starred it - when it entered their library; null without one */
  starred: number | null
  played: number | null
  plays: number
}

const keyed = new WeakMap<Album, AlbumKeys>()

export function albumKeys(album: Album): AlbumKeys {
  let keys = keyed.get(album)
  if (!keys) {
    const artist = foldName(album.artist)
    const title = foldName(album.name)
    keys = {
      artist,
      title,
      initial: initialOf(artist),
      titleInitial: initialOf(title),
      year: typeof album.year === 'number' && album.year > 0 ? album.year : null,
      created: time(album.created),
      starred: time(album.starred),
      played: time(album.played),
      plays: typeof album.playCount === 'number' && album.playCount > 0 ? album.playCount : 0,
    }
    keyed.set(album, keys)
  }
  return keys
}

const text = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0)
//? letters first, then `#`; then the key itself
const byName = (a: string, aInitial: string, b: string, bInitial: string) =>
  (aInitial === OTHER_INITIAL ? 1 : 0) - (bInitial === OTHER_INITIAL ? 1 : 0) || text(a, b)
//? a value that may be missing: the missing last, whichever way the rest go
const missingLast = (a: number | null, b: number | null, descending: boolean) =>
  a === null || b === null ? (a === b ? 0 : a === null ? 1 : -1) : descending ? b - a : a - b

/** When one of YOUR albums was added: its star (an album without one - never in your library's own list - by
 *  `created`). The collection's lists never ask it: they read `created` alone. */
function addedAt(keys: AlbumKeys): number | null {
  return keys.starred ?? keys.created
}

interface Moment {
  /** the newest star in it - what its month header says */
  at: number | null
  members: { album: Album; index: number; keys: AlbumKeys }[]
}

/**
 * Your albums cut into the moments they were added (2.0.11), newest first: each run of stars no more than
 * SAME_MOMENT_MS apart, one after the next, is one; the albums with no date at all one last moment. Inside each, as
 * the list is to be drawn: `created` newest first (missing last), then the star, then the order handed in.
 */
function moments(albums: readonly Album[]): Moment[] {
  const listed = albums.map((album, index) => ({ album, index, keys: albumKeys(album) }))
  listed.sort((a, b) => missingLast(addedAt(a.keys), addedAt(b.keys), true) || a.index - b.index)
  const cut: Moment[] = []
  let last: number | null = null
  for (const entry of listed) {
    const at = addedAt(entry.keys)
    const current = cut[cut.length - 1]
    if (current && (at === null ? current.at === null : last !== null && last - at <= SAME_MOMENT_MS)) current.members.push(entry)
    else cut.push({ at, members: [entry] })
    last = at
  }
  for (const moment of cut) {
    moment.members.sort((a, b) => missingLast(a.keys.created, b.keys.created, true)
      || missingLast(addedAt(a.keys), addedAt(b.keys), true) || a.index - b.index)
  }
  return cut
}

/** The albums in `sort` - a new list, the one handed in left as it is. Recently played and Most played leave out
 *  what hasn't been played (as Navidrome's own `recent` does). Recently added goes by `by` (2.0.11): the collection's
 *  `created` unless the list is yours. */
export function sortAlbums(albums: readonly Album[], sort: AlbumSort, by: AddedBy = 'collection'): Album[] {
  if (sort === 'newest' && by === 'you') return moments(albums).flatMap((moment) => moment.members.map((entry) => entry.album))
  const listed = albums.map((album, index) => ({ album, index, keys: albumKeys(album) }))
  type Entry = (typeof listed)[number]
  const compare: (a: Entry, b: Entry) => number =
    sort === 'alphabeticalByArtist'
      ? (a, b) => byName(a.keys.artist, a.keys.initial, b.keys.artist, b.keys.initial) || missingLast(a.keys.year, b.keys.year, false)
        || text(a.keys.title, b.keys.title) || a.index - b.index
      : sort === 'alphabeticalByName'
        ? (a, b) => byName(a.keys.title, a.keys.titleInitial, b.keys.title, b.keys.titleInitial) || text(a.keys.artist, b.keys.artist) || a.index - b.index
        : sort === 'newest'
          ? (a, b) => missingLast(a.keys.created, b.keys.created, true) || a.index - b.index
          : sort === 'byYearDesc' || sort === 'byYearAsc'
            ? (a, b) => missingLast(a.keys.year, b.keys.year, sort === 'byYearDesc')
              || byName(a.keys.artist, a.keys.initial, b.keys.artist, b.keys.initial) || text(a.keys.title, b.keys.title) || a.index - b.index
            : sort === 'recent'
              ? (a, b) => b.keys.played! - a.keys.played! || a.index - b.index
              : (a, b) => b.keys.plays - a.keys.plays || missingLast(a.keys.played, b.keys.played, true) || a.index - b.index
  const kept = sort === 'recent' ? listed.filter((entry) => entry.keys.played !== null)
    : sort === 'frequent' ? listed.filter((entry) => entry.keys.plays > 0)
      : listed
  return kept.sort(compare).map((entry) => entry.album)
}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
export const DATE_UNKNOWN = 'Date unknown'
export const NO_YEAR = 'No year'

function monthOf(at: number | null): string {
  if (at === null) return DATE_UNKNOWN
  const date = new Date(at)
  return `${MONTHS[date.getUTCMonth()]} ${date.getUTCFullYear()}`
}

/** The month an album was added, in English from a fixed table (never toLocaleString): "October 2026". */
export function monthLabel(created: unknown): string {
  return monthOf(time(created))
}

/** Consecutive runs of the same key, each a group. */
function runs<T>(items: readonly T[], key: (item: T) => string, label: (item: T) => string | null): Group<T>[] {
  const groups: Group<T>[] = []
  for (const item of items) {
    const at = key(item)
    const last = groups[groups.length - 1]
    if (last && last.key === at) last.items.push(item)
    else groups.push({ key: at, label: label(item), items: [item] })
  }
  return groups
}

/** Whether a sort draws headers: the letters, the years and the months; the played sorts are one running list. */
export function albumSortHeads(sort: AlbumSort): boolean {
  return sort !== 'recent' && sort !== 'frequent'
}

//? each whole list of yours -> the month of the moment each album in it was added, made once per list
const addedMonths = new WeakMap<readonly Album[], Map<Album, string>>()

function addedMonthsOf(whole: readonly Album[]): Map<Album, string> {
  let month = addedMonths.get(whole)
  if (!month) {
    month = new Map()
    for (const moment of moments(whole)) for (const entry of moment.members) month.set(entry.album, monthOf(moment.at))
    addedMonths.set(whole, month)
  }
  return month
}

/** Sorted albums cut into their headers' groups: the artist's or the title's first letter, the year ("No year"
 *  last), the month added ("Date unknown" last) - or one unlabelled group for Recently played and Most played.
 *  The month added follows `by`, as the sort did (2.0.11): yours the month of the moment it entered your library
 *  (its moment's newest star, so one moment is never split between two months), the collection's its `created`.
 *  `whole` is the sorted list before Find narrowed it to `sorted`: your moments are cut from it, never from what
 *  Find left - taking albums out of a run of stars only widens its gaps, and a moment cut again would split over a
 *  month's end into headers out of order. */
export function groupAlbums(sorted: readonly Album[], sort: AlbumSort, by: AddedBy = 'collection', whole: readonly Album[] = sorted): Group<Album>[] {
  if (!sorted.length) return []
  if (!albumSortHeads(sort)) return [{ key: 'all', label: null, items: [...sorted] }]
  if (sort === 'alphabeticalByArtist') return runs(sorted, (album) => albumKeys(album).initial, (album) => albumKeys(album).initial)
  if (sort === 'alphabeticalByName') return runs(sorted, (album) => albumKeys(album).titleInitial, (album) => albumKeys(album).titleInitial)
  if (sort === 'newest' && by === 'you') {
    const month = addedMonthsOf(whole)
    return runs(sorted, (album) => month.get(album) ?? DATE_UNKNOWN, (album) => month.get(album) ?? DATE_UNKNOWN)
  }
  if (sort === 'newest') {
    return runs(sorted, (album) => monthLabel(album.created), (album) => monthLabel(album.created))
  }
  const year = (album: Album) => albumKeys(album).year
  return runs(sorted, (album) => String(year(album) ?? 'none'), (album) => (year(album) === null ? NO_YEAR : String(year(album))))
}

/* ===== artists ===== */

/** What an artist list holds: a name, and how many albums (Navidrome's Artist, and lib/artistPage.ts's callers). */
export type ArtistLike = Pick<Artist, 'name' | 'albumCount'>

const artistKeyed = new WeakMap<ArtistLike, { name: string; initial: string }>()

function artistKeys(artist: ArtistLike): { name: string; initial: string } {
  let keys = artistKeyed.get(artist)
  if (!keys) {
    const name = foldName(artist.name)
    keys = { name, initial: initialOf(name) }
    artistKeyed.set(artist, keys)
  }
  return keys
}

/** Artists in an order: Name by deadwax's own folding, `#` last (Navidrome strips articles foldName doesn't - "La
 *  Dispute" is under D there, under L here - so the letter headers need deadwax's order); Most albums most first, a
 *  tie in the order handed in. */
export function sortArtistsBy<A extends ArtistLike>(artists: readonly A[], order: ArtistOrder): A[] {
  const listed = artists.map((artist, index) => ({ artist, index }))
  return order === 'name'
    ? listed.sort((a, b) => {
        const first = artistKeys(a.artist)
        const second = artistKeys(b.artist)
        return byName(first.name, first.initial, second.name, second.initial) || a.index - b.index
      }).map(({ artist }) => artist)
    : listed.sort((a, b) => (b.artist.albumCount ?? 0) - (a.artist.albumCount ?? 0) || a.index - b.index).map(({ artist }) => artist)
}

/** Sorted artists in their groups: by Name's first letter, or one unlabelled group for Most albums. */
export function groupArtists<A extends ArtistLike>(sorted: readonly A[], order: ArtistOrder): Group<A>[] {
  if (!sorted.length) return []
  if (order !== 'name') return [{ key: 'all', label: null, items: [...sorted] }]
  return runs(sorted, (artist) => artistKeys(artist).initial, (artist) => artistKeys(artist).initial)
}

/* ===== Find ===== */

/**
 * What Find matches against: foldName's folding (accents, case, "&", punctuation) but keeping what foldName drops for
 * COMPARING - a bracketed aside ("(Deluxe Edition)") and a leading "The" - since those are words a person types to
 * find an album. Made once per album, the first time Find runs.
 */
export function findText(name: string | null | undefined): string {
  return String(name || '')
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[’‘`´]/g, "'")
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

const findWords = (typed: string) => findText(typed).split(' ').filter(Boolean)
const albumFound = new WeakMap<Album, string>()
const artistFound = new WeakMap<ArtistLike, string>()

/** The albums Find keeps: every word typed, in any order, inside the album's title and artist, folded. */
export function filterAlbums(albums: readonly Album[], typed: string): Album[] {
  const words = findWords(typed)
  if (!words.length) return [...albums]
  return albums.filter((album) => {
    let found = albumFound.get(album)
    if (found === undefined) {
      found = `${findText(album.name)} ${findText(album.artist)}`
      albumFound.set(album, found)
    }
    return words.every((word) => found!.includes(word))
  })
}

/** The artists Find keeps, by name. */
export function filterArtists<A extends ArtistLike>(artists: readonly A[], typed: string): A[] {
  const words = findWords(typed)
  if (!words.length) return [...artists]
  return artists.filter((artist) => {
    let found = artistFound.get(artist)
    if (found === undefined) {
      found = findText(artist.name)
      artistFound.set(artist, found)
    }
    return words.every((word) => found!.includes(word))
  })
}

/** Whether anything is typed into Find (spaces alone are nothing). */
export function finding(typed: string): boolean {
  return findWords(typed).length > 0
}

/** "12 of 3012 albums" - the count while Find narrows the list. */
export function filteredCountText(shown: number, total: number, one: string, many: string): string {
  return `${shown} of ${total} ${total === 1 ? one : many}`
}

/** "No albums match “dumy”." */
export function noMatchText(kind: 'albums' | 'artists', typed: string): string {
  return `No ${kind} match “${typed.trim()}”.`
}

/* ===== the index down the right edge ===== */

/** An index needs a list this long, at least; a shorter one is a scroll away. */
export const INDEX_MIN = 50

export interface IndexEntry {
  label: string
  aria: string
  /** the group it jumps to, by its place in the groups */
  group: number
}

const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')

/** What index a sort draws: the 27 letters for the name sorts, the decades present for the year sorts, else none. */
export function indexKind(sort: AlbumSort | ArtistOrder): 'letters' | 'decades' | null {
  if (sort === 'alphabeticalByArtist' || sort === 'alphabeticalByName' || sort === 'name') return 'letters'
  if (sort === 'byYearDesc' || sort === 'byYearAsc') return 'decades'
  return null
}

/** Whether the index is drawn: a sort that has one, nothing typed into Find, and at least INDEX_MIN items. */
export function showsIndex(sort: AlbumSort | ArtistOrder, count: number, typed: string): boolean {
  return indexKind(sort) !== null && !finding(typed) && count >= INDEX_MIN
}

/**
 * The index's entries. Letters: all 27, A-Z then #, each jumping to its own group - or, with none, the next group
 * after it, or the last group when there is none after. Decades: one per decade present, in the sort's direction,
 * labelled with its first year, jumping to its first group; "No year" gets none.
 */
export function indexEntries<T>(groups: readonly Group<T>[], sort: AlbumSort | ArtistOrder): IndexEntry[] {
  const kind = indexKind(sort)
  if (!kind || !groups.length) return []
  if (kind === 'letters') {
    const rank = (label: string | null) => (label === OTHER_INITIAL ? LETTERS.length : LETTERS.indexOf(label ?? ''))
    return [...LETTERS, OTHER_INITIAL].map((label, at) => {
      const found = groups.findIndex((group) => rank(group.label) >= at)
      return {
        label,
        aria: label === OTHER_INITIAL ? 'Jump to numbers and symbols' : `Jump to ${label}`,
        group: found === -1 ? groups.length - 1 : found,
      }
    })
  }
  const entries: IndexEntry[] = []
  groups.forEach((group, at) => {
    const year = Number(group.label)
    if (!Number.isInteger(year) || group.label === NO_YEAR) return
    const decade = String(Math.floor(year / 10) * 10)
    if (entries[entries.length - 1]?.label === decade) return
    entries.push({ label: decade, aria: `Jump to the ${decade}s`, group: at })
  })
  return entries
}

/** One place on the drawn strip: an entry, or a dot standing for those left out between two. */
export type IndexSlot = { kind: 'entry'; entry: IndexEntry; at: number } | { kind: 'dot' }

/**
 * The entries as `slots` places can draw them: all, when they fit; else as many as fit with a dot between each two
 * (aria-hidden, inert - Apple's "A • D • G"), the first and last always kept, the rest spread evenly. Which entry a
 * finger is over is taken from the slot under it (entryAt): an entry's own, or - over a dot - one of the letters it
 * stands for, so a letter left out is still reached by dragging.
 */
export function fitIndex(entries: readonly IndexEntry[], slots: number): IndexSlot[] {
  const all = entries.map((entry, at): IndexSlot => ({ kind: 'entry', entry, at }))
  if (entries.length <= Math.max(1, slots)) return all
  const kept = Math.max(2, Math.floor((slots + 1) / 2))
  const drawn: IndexSlot[] = []
  let before = -1
  for (let n = 0; n < kept; n++) {
    const at = Math.round((n * (entries.length - 1)) / (kept - 1))
    if (at === before) continue
    if (before !== -1 && at - before > 1) drawn.push({ kind: 'dot' })
    drawn.push({ kind: 'entry', entry: entries[at]!, at })
    before = at
  }
  return drawn
}

/**
 * The entry under a finger at `y`, the drawn slots spread evenly from `top` over `height` (every slot, dots too, is
 * one height). The SLOT under the finger first: an entry's slot gives that entry, so a drawn letter always jumps to
 * itself however the strip is thinned; a dot's slot spreads the entries it stands for over its own height, so a drag
 * across it reaches each in turn. (Review of .59: taking the place over the full list instead agreed with fitIndex's
 * spread only mid-strip - at 13 slots A went to B and # to Z.)
 */
export function entryAt(drawn: readonly IndexSlot[], y: number, top: number, height: number): number | null {
  if (!drawn.length || height <= 0) return null
  const place = ((y - top) / height) * drawn.length
  const index = Math.min(drawn.length - 1, Math.max(0, Math.floor(place)))
  const slot = drawn[index]!
  if (slot.kind === 'entry') return slot.at
  const before = drawn[index - 1]
  const after = drawn[index + 1]
  if (before?.kind !== 'entry' || after?.kind !== 'entry') {
    //? fitIndex never draws a dot at an end or beside another dot; a hand-made list falls back to a neighbour
    return before?.kind === 'entry' ? before.at : after?.kind === 'entry' ? after.at : null
  }
  const between = after.at - before.at - 1
  if (between <= 0) return before.at
  const within = Math.min(1, Math.max(0, place - index))
  return before.at + 1 + Math.min(between - 1, Math.floor(within * between))
}

/* ===== blocks: what the shelf draws ===== */

/** The most items in one block: 60 divides by 2, 3, 4, 5 and 6 columns, so a block never ends in a part row at the
 *  widths the app draws (2 on a phone, 6 on a desktop, 3-5 beside a panel). */
export const BLOCK_SIZE = 60

export interface Block<T> {
  key: string
  /** the group's header, on its first block only */
  head: string | null
  group: number
  items: T[]
}

/** Each group cut into blocks of at most `size` items, its header on the first. */
export function blocks<T>(groups: readonly Group<T>[], size: number = BLOCK_SIZE): Block<T>[] {
  const cut: Block<T>[] = []
  groups.forEach((group, at) => {
    for (let start = 0; start < group.items.length; start += size) {
      cut.push({ key: `${group.key}:${start / size}`, head: start === 0 ? group.label : null, group: at, items: group.items.slice(start, start + size) })
    }
  })
  return cut
}

/**
 * Which blocks lie between `from` and `to` (px from the shelf's top), by their heights - the blocks the shelf draws
 * before the page has said what is near the view (a new list, a new sort, Find typed into): `[start, end)`, at least
 * one block when there are any. A block whose top is at `to` or below, or whose bottom is at `from` or above, is out.
 */
export function blocksNear(heights: readonly number[], from: number, to: number): [number, number] {
  if (!heights.length) return [0, 0]
  let top = 0
  let start = -1
  let end = 0
  heights.forEach((height, at) => {
    const bottom = top + height
    if (bottom > from && top < to) {
      if (start === -1) start = at
      end = at + 1
    }
    top = bottom
  })
  if (start === -1) {
    //? all of them above the window (scrolled past the end): the last; below it (the shelf not reached yet): the first
    return from >= top ? [heights.length - 1, heights.length] : [0, 1]
  }
  return [start, end]
}

