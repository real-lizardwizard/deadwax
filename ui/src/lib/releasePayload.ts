/**
 * THE one place a download's release is built (2.0.0-player.15) - what a Find or a Get searches
 * Soulseek for, and what the job files the download as. Pure, pinned by ui/test/payload.sim.cjs
 * against what the main page's two Find buttons sent BEFORE they were moved onto it, captured from
 * the real page against live MusicBrainz (tests/fixtures/payloads/find-buttons.json): eight cases,
 * every body deep-equal, every panel label too.
 *
 * Used by the app's Get (the album you don't have, and the Get chip on a Search row) and - through
 * the bridge (ui/src/main.tsx sets `buildDownloadRelease`) - by interface/scripts/main.js, whose
 * row Find and card Find called buildExpectedFromRelease and buildExpectedFromReleaseGroup until
 * now. Those two are deleted: two builders were two answers waiting to drift apart, and "anything
 * added to a download's payload has to be added in BOTH builders" was a rule kept by hand. Anything
 * added to a download's payload goes HERE, now, and nowhere else.
 *
 * The artist has two roles, and they are not interchangeable (lib/release.ts, credits.mjs):
 *  - `artist` is AS CREDITED on the album - the group's credit - which is what a stranger typed
 *    into their Soulseek folder, so it is what is searched for and what the matcher scores against.
 *  - `album_artist` is who the album is BY in their CURRENT names - the folder it is filed under
 *    and the albumartist tag - from the PRESSING's own credit, so the name and `artist_mbids` (the
 *    same credit's ids) can't disagree. Ye's Donda is searched as "Kanye West" and filed under Ye.
 *
 * Kept exactly as main.js had it, quirks included, because the main page still sends what this
 * builds and the orchestrator diffs its bodies before and after: a credit that names nobody is
 * "N/A" (getArtistNames' word), the country is the raw ISO code ("XE", not the flag's "eu" - the
 * editions code recognises and drops the worldwide ones), a year is four digits or null (never
 * "N/A", or an undated album files as "Album (N/A)"), and the album's own year is the group's
 * first-release-date, so a 2014 vinyl of a 1994 album files under 1994.
 */

import type { ArtistCredit, DownloadRelease, Medium, Release, ReleaseGroup, Track } from '../api/types'
import { creditIds, creditName, currentName, detectEditionTags, isVideoTrack } from './release'
import { representativeRelease, type PressingRelease } from './tracklistDiff'

/** What a pressing's payload takes from its album - main.js's releaseGroupContext, as it built it. */
export interface GroupContext {
  /** the album's credit, as credited: "N/A" when it names nobody */
  artist: string
  /** the same credit in each artist's current name, else the credit */
  albumArtist: string
  artistMbids: string[]
  /** the album's title: "N/A" when MusicBrainz gave none */
  album: string
  /** the first four characters of the group's first-release-date, or null */
  year: string | null
  releaseGroupId: string | null
}

/** A credit as credited, or "N/A" for one that names nobody - getArtistNames() in credits.mjs. */
function credited(credit: ArtistCredit[] | undefined): string {
  return creditName(credit) || 'N/A'
}

/** A year or nothing: `realYear()` in main.js - display says "N/A", a payload never does. */
function realYear(year: string | null | undefined): string | null {
  return /^\d{4}$/.test(year || '') ? (year as string) : null
}

/** An album's context, from its release group as MusicBrainz sent it - createReleaseGroupElement's. */
export function groupContext(group: Pick<ReleaseGroup, 'id' | 'title' | 'first-release-date' | 'artist-credit'>): GroupContext {
  const artist = credited(group['artist-credit'])
  const date = group['first-release-date']
  return {
    artist,
    albumArtist: currentName(group['artist-credit']) || artist,
    artistMbids: creditIds(group['artist-credit']),
    album: group.title || 'N/A',
    year: date ? date.substring(0, 4) : null,
    releaseGroupId: group.id || null,
  }
}

interface RawTrack {
  title?: string
  position?: number
  length?: number | null
  'artist-credit'?: ArtistCredit[]
  recording?: { title?: string; length?: number | null; video?: boolean; 'artist-credit'?: ArtistCredit[] }
}

/**
 * Every track of every disc, with both numberings: `position` running across the whole release
 * (what the matcher keys its file mapping on, and files are named after), `disc` and
 * `disc_position` MusicBrainz's own (what a multi-disc release is TAGGED with). Each track keeps
 * its OWN credit, the disc's title (DISCSUBTITLE), and whether it is video (never an audio file).
 */
function tracksOf(release: Release): Track[] {
  const tracks: Track[] = []
  let position = 0
  ;(release.media ?? []).forEach((medium: Medium, discIndex) => {
    //? the disc's own title ('' from MusicBrainz when it has none)
    const discTitle = (medium.title || '').trim() || null
    ;((medium.tracks ?? []) as RawTrack[]).forEach((track, trackIndex) => {
      position += 1
      const credit = track['artist-credit'] || track.recording?.['artist-credit']
      tracks.push({
        position,
        title: track.recording?.title || track.title || '',
        length_ms: track.recording?.length ?? track.length ?? null,
        disc: medium.position ?? discIndex + 1,
        disc_position: track.position ?? trackIndex + 1,
        //? an empty credit is still a credit to main.js: "N/A", not null
        artist: credit ? credited(credit) : null,
        artist_mbids: creditIds(credit),
        disc_title: discTitle,
        video: isVideoTrack(medium, track),
      })
    })
  })
  return tracks
}

/** One real pressing of the album, as a download - the row Find's payload, and the card's. */
export function releasePayload(release: Release, context: GroupContext): DownloadRelease {
  const rawDate = release['release-events']?.[0]?.date || release.date || ''
  const catalogNumbers = (release['label-info'] ?? [])
    .map((entry) => entry['catalog-number'])
    .filter((number): number is string => Boolean(number))

  return {
    artist: context.artist,
    album_artist: currentName(release['artist-credit']) || context.albumArtist,
    artist_mbids: creditIds(release['artist-credit']),
    album: release.title || context.album,
    year: rawDate ? rawDate.substring(0, 4) : realYear(context.year),
    original_year: realYear(context.year),
    release_mbid: release.id,
    edition_tags: detectEditionTags(release),
    tracks: tracksOf(release),
    release_group_mbid: context.releaseGroupId || null,
    disambiguation: release.disambiguation || null,
    media_format: (release.media ?? []).map((medium) => medium.format).filter(Boolean).join(' + ') || null,
    //? the raw ISO code (`||`, as main.js: an empty one falls through to the release's country)
    country: release['release-events']?.[0]?.area?.['iso-3166-1-codes']?.[0] || release.country || null,
    catalog_number: catalogNumbers.join(', ') || null,
  }
}

/**
 * The album as a whole, no pressing - for when MusicBrainz can't say which pressings it has. No
 * tracklist to match against (the matcher drops the signals that need one), no release id (so
 * nothing is checked as held or downloading), filed under the album's current artist.
 */
export function groupFallback(context: GroupContext): DownloadRelease {
  return {
    artist: context.artist,
    album_artist: context.albumArtist,
    artist_mbids: context.artistMbids,
    album: context.album,
    year: realYear(context.year),
    original_year: realYear(context.year),
    release_mbid: null,
    release_group_mbid: context.releaseGroupId || null,
    edition_tags: [],
    tracks: [],
  }
}

/** "Portishead - Dummy", "Kanye West - Donda [DELUXE]" - what the main page's candidates panel heads itself with. */
export function downloadLabel(release: DownloadRelease): string {
  const tags = release.edition_tags.length ? ` [${release.edition_tags.join(', ')}]` : ''
  return `${release.artist} - ${release.album}${tags}`
}

/**
 * A download of `release` - a pressing of `group` - or, with no pressing, of the album as a whole;
 * with the label a panel heads it with. What the main page's two Find buttons call (the bridge's
 * `buildDownloadRelease`): the row passes its own pressing, the card representativeRelease()'s.
 */
export function buildDownloadRelease(
  group: Pick<ReleaseGroup, 'id' | 'title' | 'first-release-date' | 'artist-credit'>,
  release: Release | null,
): { release: DownloadRelease; label: string } {
  const context = groupContext(group)
  const payload = release ? releasePayload(release, context) : groupFallback(context)
  return { release: payload, label: downloadLabel(payload) }
}

/** The pressing a card's Find - and a Search row's Get chip - downloads: the usual one (lib/tracklistDiff.ts). */
export function usualPressing<R extends PressingRelease>(pressings: readonly R[]): R | null {
  return representativeRelease(pressings)
}
