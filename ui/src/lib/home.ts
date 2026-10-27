/**
 * Home's "Not played in a while" (2.0.0-player.18): which albums the shelf shows - pure, pinned by
 * ui/test/home.sim.cjs. James liked it as a section; slices.md's S7 is the rule.
 *
 * Navidrome has no list of albums by how long ago they were played, so it is made from the one it
 * has: getAlbumList2 `recent` - albums played, the most recent first - asked for at RECENT_LISTED, and
 * each album's OpenSubsonic `played` (when it was last played: Navidrome sends it on an album list
 * and on getAlbum, set only once the album has been played). The albums last played more than
 * NOT_PLAYED_DAYS ago, the longest ago first, up to NOT_PLAYED_SHOWN. Fewer than NOT_PLAYED_FEWEST,
 * and there is no shelf at all - nor when no album carries `played`: a Navidrome that doesn't send it
 * would otherwise have every album "not played in a while", or none, on no evidence.
 *
 * The plays are Navidrome's, for the account the player asks as - the shared one while logins are off
 * (and for the break-glass admin); with logins on (2.0.0-player.52) each signed-in person's own, asked with
 * their own login. `recent` stops at its first
 * RECENT_LISTED albums, so in a library with more played albums than that, the very oldest plays
 * past it are not looked at.
 */

/** How many of the albums played, most recent first, the shelf is made from - the route's most. */
export const RECENT_LISTED = 500

/** An album last played longer ago than this is "not played in a while". */
export const NOT_PLAYED_DAYS = 30

/** How many the shelf shows, the longest unplayed first. */
export const NOT_PLAYED_SHOWN = 20

/** Fewer than this, and there is no shelf. */
export const NOT_PLAYED_FEWEST = 4

const DAY_MS = 86_400_000

/** What this reads of an album: its id, and when it was last played (OpenSubsonic `played`). */
export interface PlayedAlbumFields {
  id: string
  played?: string | null
}

/** When an album was last played, in ms - null when Navidrome didn't say, or said nothing readable. */
export function playedAt(album: PlayedAlbumFields): number | null {
  const played = typeof album.played === 'string' ? album.played.trim() : ''
  if (!played) return null
  const at = Date.parse(played)
  return Number.isFinite(at) ? at : null
}

/**
 * The albums the shelf shows: last played more than NOT_PLAYED_DAYS before `now`, the longest ago
 * first (an album listed twice, once), up to NOT_PLAYED_SHOWN - or none at all, with fewer than
 * NOT_PLAYED_FEWEST or with no album carrying `played`.
 */
export function notPlayedInAWhile<A extends PlayedAlbumFields>(albums: readonly A[], now: number): A[] {
  //? an album with no played is left out - so with none carrying it (a Navidrome that doesn't send
  //? it) there are none at all, fewer than NOT_PLAYED_FEWEST, and no shelf
  const dated = albums.map((album) => ({ album, at: playedAt(album) }))
  const before = now - NOT_PLAYED_DAYS * DAY_MS
  const seen = new Set<string>()
  const old = dated
    .filter((entry): entry is { album: A; at: number } => entry.at !== null && entry.at < before)
    .sort((a, b) => a.at - b.at || (a.album.id < b.album.id ? -1 : a.album.id > b.album.id ? 1 : 0))
    .filter((entry) => !seen.has(entry.album.id) && !!seen.add(entry.album.id))
    .map((entry) => entry.album)
  return old.length < NOT_PLAYED_FEWEST ? [] : old.slice(0, NOT_PLAYED_SHOWN)
}

/*
 * Home's "Recently played" (2.0.15 - James: "Can we also add recently played to the homepage"): the albums you
 * played, the most recently played first, from getAlbumList2 `recent` at Home's RECENT_COUNT (20) - asked as you with logins on,
 * so the plays are your own (the shared account's with logins off, and for break-glass), as Not played in a while's
 * are. An album of All music you played that isn't in your library is in it: what you played is what you played.
 *
 * Home's rule is that nothing lands above a shelf and moves it under a finger, and this shelf sits above Recently
 * added - so what it draws is a small state, kept here, pure (ui/test/home.sim.cjs pins it):
 *
 *  - 'asking': no answer yet. Home waits for one as it does for the pins (Shelves' `ready`); drawn before it comes,
 *    it holds the shelf's own height, its heading over an empty row the tiles' height.
 *  - 'tiles': the albums, drawn.
 *  - 'none': no shelf - nothing played, or a failure, KNOWN before the shelf was ever on screen.
 *  - 'nothing' / 'failed': what an empty answer or a failure says once the held row is on screen - one line inside
 *    that same height, so Recently added under it never moves - until Home is next out of view (`later`), when the
 *    shelf goes ('none'). Coming back, Home draws without it from the start.
 *
 * A shelf that wasn't there (none) finding albums while Home is on screen waits too (`later`), and appears while Home
 * is out of view - never above Recently added under a finger. And a shelf there keeps its ROWS, not just its place:
 * the phone's shelf is one sideways row whatever it holds, but the desktop's is a grid that wraps (six across, fewer
 * beside a third column), so on screen an answer that needs more rows than are drawn fills only the rows drawn - the
 * held row's one, the first row's tiles - and one that needs fewer leaves the drawn tiles; either way the whole
 * answer waits for Home to be out of view (`later`). An answer that changes nothing (the same albums, in the
 * same order) leaves the state as it was, the very object, so the shelf's memo holds and its tiles aren't redrawn; a
 * failed ask again with tiles drawn leaves them.
 */

/** What Recently played says once its row is on screen and the answer is that nothing was played. */
export const NOTHING_PLAYED = "You haven't played anything yet."

/** What Recently played reads of an album: what a tile draws. */
export interface PlayedTileFields {
  id: string
  name?: string
  artist?: string
  coverArt?: string | null
}

export type PlayedShelf<A> =
  | { kind: 'asking' }
  | { kind: 'none' }
  | { kind: 'tiles'; albums: readonly A[] }
  | { kind: 'nothing' }
  | { kind: 'failed'; error: unknown }

export interface PlayedState<A> {
  /** what the shelf draws now */
  shelf: PlayedShelf<A>
  /** what it draws once Home is next out of view - a change that would move what is under a finger */
  later: PlayedShelf<A> | null
}

const NO_SHELF = { kind: 'none' } as const

/** Before any answer. */
export const PLAYED_ASKING: PlayedState<never> = { shelf: { kind: 'asking' }, later: null }

/** The albums the shelf shows: `recent`'s order, an album once, up to `count` (Home's RECENT_COUNT). */
export function recentlyPlayed<A extends { id: string }>(albums: readonly A[], count: number): A[] {
  const seen = new Set<string>()
  return albums.filter((album) => !seen.has(album.id) && !!seen.add(album.id)).slice(0, count)
}

/** Whether two lists draw the same tiles: the same albums, in the same order, each drawn the same. */
export function samePlayed<A extends PlayedTileFields>(a: readonly A[], b: readonly A[]): boolean {
  return a.length === b.length && a.every((album, at) => {
    const other = b[at]
    return !!other && album.id === other.id && album.name === other.name && album.artist === other.artist && (album.coverArt ?? null) === (other.coverArt ?? null)
  })
}

/** How many rows a shelf takes, `perRow` tiles to a row: the held row (asking, nothing, failed) one, no shelf none. */
export function playedRows<A>(shelf: PlayedShelf<A>, perRow: number): number {
  if (shelf.kind === 'none') return 0
  if (shelf.kind !== 'tiles') return 1
  const across = perRow >= 1 ? perRow : Infinity
  return shelf.albums.length <= across ? 1 : Math.ceil(shelf.albums.length / across)
}

/**
 * What the shelf draws once an answer lands - `albums` (`recent`'s page) or `error` - with `onScreen` whether Home's
 * shelves are drawn and showing (ready, and Home in view) right now, `count` how many it shows, and `perRow` how many
 * tiles a row of the shelf holds right now: Infinity for the phone's one sideways row (the default), the grid's
 * columns on the desktop - what tells an answer that would change the shelf's height from one that wouldn't.
 */
export function playedLanded<A extends PlayedTileFields>(
  state: PlayedState<A>, answer: { albums: readonly A[] } | { error: unknown }, onScreen: boolean, count: number,
  perRow: number = Infinity,
): PlayedState<A> {
  const { shelf } = state
  if ('error' in answer) {
    //? a failure is no news: what is drawn stays - only a shelf still asking hears it
    if (shelf.kind !== 'asking') return state
    return onScreen ? { shelf: { kind: 'failed', error: answer.error }, later: NO_SHELF } : { shelf: NO_SHELF, later: null }
  }
  const albums = recentlyPlayed(answer.albums, count)
  if (shelf.kind === 'tiles' && samePlayed(shelf.albums, albums)) return state.later === null ? state : { shelf, later: null }
  const target: PlayedShelf<A> = albums.length ? { kind: 'tiles', albums } : NO_SHELF
  if (!onScreen) return { shelf: target, later: null }
  //? on screen: no shelf there stays none until Home is out of view, whatever it found
  if (shelf.kind === 'none') return target.kind === 'none' ? { shelf, later: null } : { shelf, later: target }
  //? ...and a shelf there keeps its rows: the tiles in the rows drawn, or one line in the held row
  const rows = playedRows(shelf, perRow)
  if (target.kind === 'none') return rows === 1 ? { shelf: { kind: 'nothing' }, later: NO_SHELF } : { shelf, later: NO_SHELF }
  const needs = playedRows(target, perRow)
  if (needs === rows) return { shelf: target, later: null }
  if (needs < rows) return { shelf, later: target }
  //? more rows than are drawn (the desktop's grid): as many as the rows drawn hold now, all of them out of view
  const fits = albums.slice(0, rows * perRow)
  const now = shelf.kind === 'tiles' && samePlayed(shelf.albums, fits) ? shelf : { kind: 'tiles' as const, albums: fits }
  return { shelf: now, later: target }
}

/** Home out of view: what was waiting for it is drawn. */
export function playedOutOfView<A>(state: PlayedState<A>): PlayedState<A> {
  return state.later === null ? state : { shelf: state.later, later: null }
}
