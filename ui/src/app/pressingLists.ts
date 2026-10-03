import type { ReleaseGroupResponse } from '../api/types'

/**
 * The session's pressing lists, by release group (2.0.0-player.13; a module of its own since
 * 2.0.0-player.15, when Search's Get chips began asking for them too): every pressing of an album
 * with its tracklist, as /search_musicbrainz/release_group answered - the album page draws them,
 * and a Get chip picks the usual pressing from them. Kept so Back, a tab switch and a chip on an
 * album already opened ask MusicBrainz nothing again.
 *
 * Only COMPLETE answers are kept, never a failure or a list MusicBrainz broke off part way (a short
 * list would pass for the album's pressings), and the oldest is let go past PRESSINGS_KEPT: a big
 * group's tracklists are a large payload.
 */

/** How many albums' pressing lists the session keeps. */
export const PRESSINGS_KEPT = 20

const pressings = new Map<string, ReleaseGroupResponse>()

/** A group's pressings, if this session already has them complete. */
export function kept(id: string): ReleaseGroupResponse | null {
  return pressings.get(id) ?? null
}

/** Keep a complete answer, as the newest. */
export function keep(id: string, answer: ReleaseGroupResponse): void {
  pressings.delete(id)
  pressings.set(id, answer)
  if (pressings.size > PRESSINGS_KEPT) {
    const [oldest] = pressings.keys()
    if (oldest !== undefined) pressings.delete(oldest)
  }
}
