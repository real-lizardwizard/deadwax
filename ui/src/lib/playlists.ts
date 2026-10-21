/**
 * Playlists (2.0.0-player.58) - the rules, pure: which playlists show where, what their rows say, the albums a
 * playlist's songs are remembered under, Edit's operations, the page scrolling itself under a drag, and the words.
 * Imports only types; no fetch, no page, no player (ui/test/app-rules.sim.cjs holds it so).
 *
 * The playlists are Navidrome's own, as the asker (src/playlists.py says whose is whose): YOURS are yours and
 * editable; SHARED WITH YOU are somebody else's public ones, read-only; FROM FILES are yours and read-only - a smart
 * playlist, or one Navidrome made from an .m3u in the music folders (deadwax's own filing puts those beside a
 * download's songs, so with logins off there may be one per download: they are drawn folded, last).
 */

import type { Playlist, PlaylistEditBody } from '../api/playlists'
import type { AlbumWithSongs, Song } from '../player/api'

/** The longest name and description deadwax writes, and the most songs it edits - held equal to src/playlists.py. */
export const PLAYLIST_NAME_MAX = 200
export const PLAYLIST_COMMENT_MAX = 1000
export const PLAYLIST_SONGS_MAX = 2000

/** How old a list of playlists may be before an ask that isn't `fresh` asks again. */
export const PLAYLISTS_FRESH_MS = 30_000
/** How many playlist pages' answers are kept to draw a page at once as it comes back. */
export const PLAYLISTS_KEPT = 8
/** How many playlists the desktop's sidebar lists by name; the rest are on All playlists. */
export const SIDEBAR_PLAYLISTS_MAX = 20
/** Within this many px of the top or bottom of what shows, a dragged row scrolls the page... */
export const DRAG_EDGE_PX = 56
/** ...by up to this many px a frame. */
export const DRAG_STEP_MAX = 16

/** Who it is: yours (and editable), shared with you, or yours from a file. */
export type PlaylistGroup = 'yours' | 'shared' | 'files'

export function groupOf(playlist: Playlist): PlaylistGroup {
  if (!playlist.mine) return 'shared'
  return playlist.editable ? 'yours' : 'files'
}

/** The Playlists page's three groups, each in Navidrome's own order (by name). */
export function groupPlaylists(list: readonly Playlist[]): Record<PlaylistGroup, Playlist[]> {
  const groups: Record<PlaylistGroup, Playlist[]> = { yours: [], shared: [], files: [] }
  for (const playlist of list) groups[groupOf(playlist)].push(playlist)
  return groups
}

/** The picker's: the ones you can add to, the one changed last first (Navidrome moves `changed` on every add or
 *  removal, so the one you last added to is on top), ties by name. */
export function pickerPlaylists(list: readonly Playlist[]): Playlist[] {
  return list.filter((playlist) => playlist.mine && playlist.editable).sort((a, b) =>
    a.changed < b.changed ? 1 : a.changed > b.changed ? -1 : a.name.localeCompare(b.name))
}

/** The desktop sidebar's: yours, then shared with you, by name - never From files - at most `max`. */
export function sidebarPlaylists(list: readonly Playlist[] | null, max = SIDEBAR_PLAYLISTS_MAX): { id: string; name: string }[] {
  if (!list) return []
  const groups = groupPlaylists(list)
  return [...groups.yours, ...groups.shared].slice(0, max).map(({ id, name }) => ({ id, name }))
}

const count = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

/** "12 songs" */
export function songCount(n: number): string {
  return count(n, 'song', 'songs')
}

/** Coarse, as an album's: "48 min", "1h 5m"; '' for nothing. */
export function lengthText(seconds: number): string {
  if (!seconds) return ''
  const minutes = Math.round(seconds / 60)
  if (minutes < 60) return `${minutes} min`
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`
}

/** A playlist page's count and length, as an album's foot says them: "12 songs, 48 min". */
export function songsLine(n: number, seconds: number): string {
  const length = lengthText(seconds)
  return length ? `${songCount(n)}, ${length}` : songCount(n)
}

/** What a row on the Playlists page says under its name. */
export function rowLine(playlist: Playlist): string {
  const group = groupOf(playlist)
  const length = lengthText(playlist.duration)
  const songs = [songCount(playlist.songCount), ...(length ? [length] : [])]
  if (group === 'files') return `From a file · ${songCount(playlist.songCount)}`
  if (group === 'shared') return [playlist.owner || 'Somebody', ...songs].join(' · ')
  return [...songs, ...(playlist.public ? ['Shared'] : [])].join(' · ')
}

/** Whose it is, under a playlist page's title. */
export function ownerLine(playlist: Playlist): string {
  const group = groupOf(playlist)
  if (group === 'files') return 'From a file in the music folders'
  if (group === 'shared') return `${playlist.owner || 'Somebody'}'s · Shared with you`
  return playlist.public ? 'Yours · Shared with everyone' : 'Yours'
}

/** Why a playlist page has no Edit - null when it has one. */
export function readOnlyWords(playlist: Playlist, songs: number): string | null {
  const group = groupOf(playlist)
  if (group === 'shared') return `Only ${playlist.owner || 'its owner'} can change this playlist.`
  if (group === 'files') return "Navidrome made this playlist from a file in the music folders - a smart playlist, or an .m3u - so it can't be changed here."
  if (songs > PLAYLIST_SONGS_MAX) return 'deadwax edits playlists of up to 2,000 songs - edit this one in Amperfy or Navidrome.'
  return null
}

/** Whether a playlist page offers Edit. */
export function canEdit(playlist: Playlist, songs: number): boolean {
  return readOnlyWords(playlist, songs) === null
}

/** "2 songs in this playlist aren't in the library just now - deleted, or being moved." - '' for none. */
export function hiddenWords(hidden: number): string {
  if (hidden <= 0) return ''
  return `${count(hidden, 'song', 'songs')} in this playlist ${hidden === 1 ? "isn't" : "aren't"} in the library just now - deleted, or being moved.`
}

/** Edit's note of the same: what Done does to them if the songs change. */
export function hiddenEditWords(hidden: number): string {
  if (hidden <= 0) return ''
  return `${count(hidden, 'song', 'songs')} that ${hidden === 1 ? "isn't" : "aren't"} in the library just now will be dropped if you change the songs.`
}

export const PLAYLISTS_EMPTY = 'No playlists yet.'
export const PLAYLISTS_EMPTY_HOW = "Make one here, or start one from a song's or an album's ••• menu, or from Now Playing: Add to a playlist."
export const PLAYLIST_EMPTY = "Nothing in this playlist yet. Add songs from a song's or an album's ••• menu - Add to a playlist - or from Now Playing's ••• while a song plays."
export const PLAYLIST_GONE = "This playlist isn't on Navidrome any more - deleted in another app, maybe."
export const PLAYLIST_CHANGED = "This playlist changed in another app while you were editing it - here it is now. Your changes weren't saved."
export const SHARED_NOTE = 'Everyone with an account on this Navidrome can find it and play it - in deadwax, Navidrome and their other apps. Only you can change it.'
export const NEEDS_A_NAME = 'A playlist needs a name.'
export const DISCARD_QUESTION = 'Discard your changes?'

/** Delete's question, in place. */
export function deleteQuestion(name: string): string {
  return `Delete "${name}"? It goes from Navidrome for good - from Amperfy and every other app too, and for everyone it's shared with. The songs stay in the library.`
}

/** "Couldn't list your playlists: <why>" */
export function listFailed(why: string): string {
  return `Couldn't list your playlists: ${why}`
}

/* ===== playing one ===== */

/**
 * The albums a playlist's songs are remembered under (player/api.ts rememberQueue - for Info, the turntable's disc
 * art and Go to album's preview): one stub per album, in the order its first song appears, holding its songs in
 * playlist order, and `partial` - its songs only the playlist's, so Info counts none of the album's from it (no
 * "Track 1 of 1", no "1 song"). NO `musicBrainzId` key at all - an empty one would make the ••• menu's pin
 * unpinnable (App's menuPinNow); left out, the pin falls back to Navidrome's id, from which deadwax reads the
 * release. A song with no album id gets none.
 */
export function playlistAlbums(songs: readonly Song[]): AlbumWithSongs[] {
  const albums = new Map<string, AlbumWithSongs & { song: Song[] }>()
  for (const song of songs) {
    if (!song.albumId) continue
    let stub = albums.get(song.albumId)
    if (!stub) {
      const artist = song.displayAlbumArtist || song.artist
      stub = {
        id: song.albumId,
        name: song.album ?? '',
        ...(artist ? { artist } : {}),
        ...(song.coverArt ? { coverArt: song.coverArt } : {}),
        ...(song.year ? { year: song.year } : {}),
        song: [],
        partial: true,
      }
      albums.set(song.albumId, stub)
    }
    stub.song.push(song)
  }
  return [...albums.values()]
}

/**
 * (review) What is remembered for a playlist's albums at the tap: the album's OWN answer where one is held already
 * (`held`: player/api.ts playedAlbum - an album page's, every song, its disc titles and label) - a stub never put
 * over it, or the album already playing loses its disc's art and Info its facts; else the stub, with the songs of
 * an earlier playlist's stub of it kept beside the new ones (a song of it playing from that one still found).
 */
export function withHeld(stubs: readonly AlbumWithSongs[], held: (id: string) => AlbumWithSongs | null): AlbumWithSongs[] {
  return stubs.map((stub) => {
    const have = held(stub.id)
    if (!have) return stub
    if (!have.partial) return have
    const fresh = new Set((stub.song ?? []).map((song) => song.id))
    return { ...stub, song: [...(have.song ?? []).filter((song) => !fresh.has(song.id)), ...(stub.song ?? [])] }
  })
}

/** The stub toQueueTrack fills a song's gaps from: its own album, by id and name - every playlist entry carries its
 *  own cover and format, so nothing else is wanted. */
export function stubFor(song: Song): AlbumWithSongs {
  return { id: song.albumId ?? '', name: song.album ?? '' }
}

/* ===== editing ===== */

/** A row of Edit's list: keyed by the place its song had when Edit began, so a song in twice is two rows. */
export interface EditRow {
  key: string
  id: string
  title: string
  artist: string
}

/** What Edit holds: the rows, and the name, description and sharing as typed. */
export interface EditState {
  rows: EditRow[]
  name: string
  comment: string
  public: boolean
}

export function startEdit(songs: readonly Song[], playlist: Playlist): EditState {
  return {
    rows: songs.map((song, index) => ({ key: `${index}:${song.id}`, id: song.id, title: song.title, artist: song.artist ?? '' })),
    name: playlist.name,
    comment: playlist.comment,
    public: playlist.public,
  }
}

/** The row at `from` moved to `to` (clamped); the same rows when it doesn't move. */
export function moveRow(rows: readonly EditRow[], from: number, to: number): EditRow[] {
  const target = Math.max(0, Math.min(rows.length - 1, to))
  if (from < 0 || from >= rows.length || target === from) return rows.slice()
  const next = rows.slice()
  const [row] = next.splice(from, 1)
  next.splice(target, 0, row!)
  return next
}

export function removeRow(rows: readonly EditRow[], index: number): EditRow[] {
  return rows.filter((_, at) => at !== index)
}

const ids = (rows: readonly EditRow[]) => rows.map((row) => row.id)

/** Whether Edit has changed anything since it began. */
export function editChanged(start: EditState, now: EditState): boolean {
  return editBody(start, now) !== null
}

/** What Done sends: `base` (the songs as drawn when Edit began), the songs now, and only the metadata that changed
 *  - '' for a description cleared. Null when nothing changed. */
export function editBody(start: EditState, now: EditState): PlaylistEditBody | null {
  const base = ids(start.rows)
  const songIds = ids(now.rows)
  const songsChanged = now.rows.length !== start.rows.length || now.rows.some((row, at) => row.key !== start.rows[at]?.key)
  const name = now.name.trim()
  const comment = now.comment.trim()
  const body: PlaylistEditBody = {
    base,
    song_ids: songIds,
    ...(name !== start.name.trim() ? { name } : {}),
    ...(comment !== start.comment.trim() ? { comment } : {}),
    ...(now.public !== start.public ? { public: now.public } : {}),
  }
  return songsChanged || 'name' in body || 'comment' in body || 'public' in body ? body : null
}

/** Whether `next` only removes and reorders `base`'s songs - src/playlists.py's rule, mirrored. */
export function isRearrangement(base: readonly string[], next: readonly string[]): boolean {
  const have = new Map<string, number>()
  for (const id of base) have.set(id, (have.get(id) ?? 0) + 1)
  for (const id of next) {
    const left = have.get(id) ?? 0
    if (left <= 0) return false
    have.set(id, left - 1)
  }
  return true
}

/**
 * How far the page scrolls this frame with a dragged row at `y` (the pointer's clientY), between `top` (the bar's
 * bottom) and `bottom` (the window's, less the player): 0 away from both; within `edge` px of one, toward it - more
 * the nearer, at most `step` - negative upward.
 */
export function edgeScroll(y: number, top: number, bottom: number, edge = DRAG_EDGE_PX, step = DRAG_STEP_MAX): number {
  if (!(bottom > top) || !(edge > 0)) return 0
  const into = (distance: number) => Math.min(step, Math.ceil(step * Math.min(1, (edge - distance) / edge)))
  if (y < top + edge) return -into(Math.max(0, y - top))
  if (y > bottom - edge) return into(Math.max(0, bottom - y))
  return 0
}

/** A dragged row's distance from where it started: the pointer's, and the page's own scroll since. */
export function dragDistance(clientY: number, startY: number, scrollY: number, startScrollY: number): number {
  return clientY - startY + scrollY - startScrollY
}

/* ===== adding ===== */

/** What the picker was opened with: one song or an album's (or a playlist's) songs, in hand. */
export interface PlaylistPick {
  key: number
  label: string
  songs: { id: string; title: string; artist?: string }[]
}

/** The picker's line of what it is adding: "Roads · Portishead", or "Dummy · 11 songs". */
export function pickLine(pick: Omit<PlaylistPick, 'key'>): string {
  const [first] = pick.songs
  if (pick.songs.length === 1 && first) return first.artist ? `${first.title} · ${first.artist}` : first.title
  return `${pick.label} · ${songCount(pick.songs.length)}`
}

/** What the songs are called in a sentence: the one song's title, or "11 songs". */
function what(pick: Omit<PlaylistPick, 'key'>, n = pick.songs.length): string {
  return pick.songs.length === 1 && n === 1 ? pick.songs[0]!.title : songCount(n)
}

/** What became of an add, in the app's notice. */
export function addedWords(answer: { added: number; already: number }, mode: 'ask' | 'add' | 'skip', pick: Omit<PlaylistPick, 'key'>, name: string): string {
  if (answer.added <= 0) {
    return pick.songs.length === 1 ? `Nothing added - ${pick.songs[0]!.title} is in ${name} already` : `Nothing added - they're all in ${name} already`
  }
  if (mode === 'skip' && answer.already > 0) {
    return `Added ${what(pick, answer.added)} to ${name} - ${answer.already} ${answer.already === 1 ? 'was' : 'were'} in it already`
  }
  return `Added ${what(pick, answer.added)} to ${name}`
}

/** What a playlist made from the picker says: "Made Late night with Roads". */
export function madeWords(name: string, pick: Omit<PlaylistPick, 'key'>): string {
  return `Made ${name} with ${what(pick)}`
}

/** The question when some of the songs are in the playlist already - its words, and its two buttons: what each
 *  sends (`null`: back to the list, nothing sent). */
export function duplicateQuestion(already: number, asked: number, pick: Omit<PlaylistPick, 'key'>, name: string): {
  text: string
  yes: { label: string; mode: 'add' }
  no: { label: string; mode: 'skip' | null }
} {
  if (asked === 1) return { text: `${pick.songs[0]?.title ?? 'That song'} is in ${name} already.`, yes: { label: 'Add it again', mode: 'add' }, no: { label: 'Cancel', mode: null } }
  if (already >= asked) return { text: `These ${asked} songs are all in ${name} already.`, yes: { label: 'Add them again', mode: 'add' }, no: { label: 'Cancel', mode: null } }
  return {
    text: `${already} of these ${asked} songs ${already === 1 ? 'is' : 'are'} in ${name} already.`,
    yes: { label: 'Add them all', mode: 'add' },
    no: { label: already === 1 ? 'Skip that one' : `Skip those ${already}`, mode: 'skip' },
  }
}
