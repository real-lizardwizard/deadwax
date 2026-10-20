import type { ReleaseGroup, ReleaseGroupResponse } from '../api/types'
import { getGroup, pressingLabel, type PageRelease } from '../lib/pressings'
import { buildDownloadRelease, usualPressing } from '../lib/releasePayload'
import { songPressing } from '../lib/songs'
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

/**
 * What Get on a MusicBrainz SONG gets (2.0.0-player.55, Search's song rows and Top results: the mock's "Machine Gun -
 * Third (Get)"): the album it names, on a pressing that has the song - songPressing over its pressings (the album's
 * usual pressing when that has it, else the most usual with one of its recordings, else with a track of its title) -
 * and the group taken from the pressings (getGroup), since a recording search's group carries no year or credit to
 * file a download under. Null when there are no pressings to choose from: the album page opens instead, the song
 * marked, and its Get takes over - a download is never filed without a year.
 */
export function songGet(album: { id: string; title: string }, recordings: readonly string[], pressings: ReleaseGroupResponse | null): Omit<GetRequest, 'key'> | null {
  const releases = (pressings?.releases ?? []) as PageRelease[]
  if (!pressings || pressings.problem || !releases.length) return null
  const chosenId = songPressing(releases, recordings) ?? usualPressing(releases)?.id ?? null
  const chosen = releases.find((release) => release.id === chosenId) ?? null
  if (!chosen) return null
  const group = getGroup(album.id, null, releases, chosen)
  const pressing = pressings.releases.find((release) => release.id === chosen.id) ?? null
  const built = buildDownloadRelease(group, pressing)
  return { release: built.release, subtitle: [group.title || album.title, pressingLabel(chosen)].filter(Boolean).join(' · ') }
}
