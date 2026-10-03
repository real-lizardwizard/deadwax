import type { ReleaseGroup, ReleaseGroupResponse } from '../api/types'
import { pressingLabel, type PageRelease } from '../lib/pressings'
import { buildDownloadRelease, usualPressing } from '../lib/releasePayload'
import type { GetRequest } from './Sources'

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

/**
 * What a Get chip gets (2.0.0-player.15's Search rows; since 2.0.0-player.17 the artist page's too):
 * the album's USUAL pressing (representativeRelease over every pressing - the one its page opens
 * on, and a main-page card's Find downloads), built by the one payload builder - or, with no
 * pressings to pick from (MusicBrainz failed, or broke the list off), the album as a whole, and the
 * sheet's subtitle says so.
 */
export function usualGet(group: ReleaseGroup, pressings: ReleaseGroupResponse | null): Omit<GetRequest, 'key'> {
  const usual = pressings ? usualPressing(pressings.releases as PageRelease[]) : null
  const pressing = usual ? pressings!.releases.find((release) => release.id === usual.id) ?? null : null
  const built = buildDownloadRelease(group, pressing)
  return {
    release: built.release,
    subtitle: [group.title, usual ? pressingLabel(usual) : 'the album as a whole'].filter(Boolean).join(' · '),
  }
}
