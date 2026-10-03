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
 * The plays are Navidrome's, for the account deadwax signs in with - the shared one while logins are
 * off (step 6 signs as the user, and then they are each person's own). `recent` stops at its first
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
