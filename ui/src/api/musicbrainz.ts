import { ApiError, MusicBrainzUnavailable, get } from './http'
import type {
  ArtistFacts, ArtistSearchResponse, DiscographyResponse, FullySearchResponse, PingResponse, Release, ReleaseGroupResponse, ReleasesResponse,
  SavedSearchResponse, SongSearchResponse,
} from './types'

/**
 * Search release groups, plus the releases of the best match.
 *
 * Two failure modes that must stay distinct:
 *   - resolves to `{}`            the query ran and matched nothing
 *   - throws MusicBrainzUnavailable   MusicBrainz is unreachable; the query never ran
 *
 * Callers that render "no results" for the second case are reintroducing the bug this
 * split exists to fix.
 */
export async function fullySearch(
  query: string,
  limit = 5,
  /**
   * Whether to also fetch the best group's releases.
   *
   * Leave it on when you're about to render them. Turn it OFF if you rank the groups yourself
   * and fetch what you want afterwards — this walks the best group's entire release list with
   * tracklists attached, which for a big album is five requests and 1.4 MB, and MusicBrainz
   * allows roughly one request a second.
   */
  includeReleases = true,
  /** lib/latest.ts aborts a search a newer one has superseded (2.0.0-player.13) */
  signal?: AbortSignal,
  /**
   * Where in MusicBrainz's answers this page starts (2.0.0-player.50, the app's "More from
   * MusicBrainz"): sent only past the first page, so a first page is asked - and cached - as ever. The
   * route refuses past MUSICBRAINZ_OFFSET_MAX (lib/searchResults.ts).
   */
  offset = 0,
  /**
   * The app's Search (2.0.0-player.55): a search's patience on the server (three attempts, not ten), a query
   * MusicBrainz refuses a 422 with words, MusicBrainz shedding a busy 503, and an abandoned search stopped. The
   * metadata editor sends none (as the main page's search sent none). Not sent to MusicBrainz: the server's cache entry is the same.
   */
  quick = false,
): Promise<FullySearchResponse> {
  try {
    return await get<FullySearchResponse>(fullySearchPath(query, limit, includeReleases, offset, quick), signal)
  } catch (error) {
    throw asUnavailable(error)
  }
}

/** The address fullySearch asks - Search's kept answers (app/searchAnswers.ts) are kept by it. */
export function fullySearchPath(query: string, limit = 5, includeReleases = true, offset = 0, quick = false): string {
  const params = new URLSearchParams({ query, limit: String(limit) })
  if (!includeReleases) params.set('releases', 'false')
  if (offset > 0) params.set('offset', String(offset))
  if (quick) params.set('quick', 'true')
  return `/search_musicbrainz/fully_search?${params}`
}

/**
 * Songs on MusicBrainz (2.0.0-player.53): the recordings matching `query` - the box read as the album
 * search reads it (lib/searchQuery.ts songSearchQuery) - each with every release it is on, so the albums
 * a song is on come in the same answer. `limit` recordings a page (lib/songs.ts SONG_SEARCH_LIMIT, the
 * route's); `offset` sent only past the first page, as fullySearch sends it. Resolves to an empty list for
 * nothing found; throws MusicBrainzUnavailable when MusicBrainz is away - never the one for the other.
 */
export async function searchSongs(query: string, limit: number, signal?: AbortSignal, offset = 0): Promise<SongSearchResponse> {
  try {
    return await get<SongSearchResponse>(searchSongsPath(query, limit, offset), signal)
  } catch (error) {
    throw asUnavailable(error)
  }
}

/** The address searchSongs asks. */
export function searchSongsPath(query: string, limit: number, offset = 0): string {
  const params = new URLSearchParams({ query, limit: String(limit) })
  if (offset > 0) params.set('offset', String(offset))
  return `/search_musicbrainz/songs?${params}`
}

/**
 * Artists on MusicBrainz going by a name (2.0.0-player.55, the app's Search): `name` is words, never a query - the
 * server asks `(artist:"…" OR alias:"…")`, so an alias finds the artist ("Kanye West" finds Ye). `limit` a page
 * (lib/searchList.ts ARTIST_SEARCH_LIMIT, the route's); `offset` sent only past the first page. Always a quick search.
 * Resolves to an empty list for nothing found; throws MusicBrainzUnavailable when MusicBrainz is away (`busy` when
 * it said it is shedding), an ApiError 422 with words when MusicBrainz refused the search.
 */
export async function searchArtists(name: string, limit: number, signal?: AbortSignal, offset = 0): Promise<ArtistSearchResponse> {
  try {
    return await get<ArtistSearchResponse>(searchArtistsPath(name, limit, offset), signal)
  } catch (error) {
    throw asUnavailable(error)
  }
}

/** The address searchArtists asks. */
export function searchArtistsPath(name: string, limit: number, offset = 0): string {
  const params = new URLSearchParams({ name, limit: String(limit) })
  if (offset > 0) params.set('offset', String(offset))
  return `/search_musicbrainz/artists?${params}`
}

/**
 * Search what's saved (2.0.0-player.56): the artists, albums and songs MusicBrainz's answers saved on disk hold that
 * match the words typed - every word, the last as a prefix, accents folded - in milliseconds, MusicBrainz asked
 * nothing. Each kind in its own route's shape, so its rows are MusicBrainz's rows. Not a MusicBrainz search: it never
 * says MusicBrainz is away - `available: false` is "nothing saved to search".
 */
export async function searchSaved(words: string, signal?: AbortSignal): Promise<SavedSearchResponse> {
  return await get<SavedSearchResponse>(searchSavedPath(words), signal)
}

/** The address searchSaved asks. */
export function searchSavedPath(words: string): string {
  return `/search_musicbrainz/saved?${new URLSearchParams({ words })}`
}

/**
 * Every release in a group.
 *
 * `withTracks` defaults to true because the download flow matches Soulseek folders against a
 * release's real tracklist. Pass false when you only need to tell pressings APART — format,
 * country, catalogue number and `media[].track-count` all survive, and it is the difference
 * between one request and five. Pair it with `getRelease` for whichever one gets chosen.
 */
export async function getReleases(
  releaseGroupMbid: string,
  withTracks = true,
  signal?: AbortSignal,
): Promise<ReleasesResponse> {
  const params = new URLSearchParams({ release_group_mbid: releaseGroupMbid })
  if (!withTracks) params.set('tracks', 'false')

  try {
    return await get<ReleasesResponse>(`/search_musicbrainz/releases?${params}`, signal)
  } catch (error) {
    throw asUnavailable(error)
  }
}

/** One release, with its tracklist. The other half of `getReleases(id, false)`. */
export async function getRelease(releaseMbid: string, signal?: AbortSignal): Promise<Release> {
  const params = new URLSearchParams({ release_mbid: releaseMbid })

  try {
    return await get<Release>(`/search_musicbrainz/release?${params}`, signal)
  } catch (error) {
    throw asUnavailable(error)
  }
}

/**
 * Every pressing of one album WITH its tracklist (2.0.0-player.13), for the app's album-you-don't-
 * have page - every one is needed to find the most common tracklist and show what each changes.
 * Cached on the server like every MusicBrainz answer. `problem` set means MusicBrainz failed (part
 * way, or before the first page): the list is not the album's pressings, and the page says so.
 */
export async function getReleaseGroup(releaseGroupMbid: string, signal?: AbortSignal): Promise<ReleaseGroupResponse> {
  const params = new URLSearchParams({ release_group_mbid: releaseGroupMbid })

  try {
    return await get<ReleaseGroupResponse>(`/search_musicbrainz/release_group?${params}`, signal)
  } catch (error) {
    throw asUnavailable(error)
  }
}

/**
 * Every ALBUM credited to an artist (2.0.0-player.17's artist page): MusicBrainz's browse of their
 * release groups of primary type album, complete - not a search's best matches. `studioOnly` leaves
 * out live albums, compilations and the rest, AFTER the browse (the server's rule: filtering a
 * complete set throws nothing away). The browse's pages are cached on the server, so the other
 * choice of Studio only costs nothing more of MusicBrainz. A `problem` in the answer means it broke
 * off: the list is not the artist's whole discography.
 */
export async function getDiscography(artistMbid: string, studioOnly: boolean, signal?: AbortSignal): Promise<DiscographyResponse> {
  const params = new URLSearchParams({ artist_mbid: artistMbid, types: 'album' })
  if (studioOnly) params.set('studio_only', 'true')

  try {
    return await get<DiscographyResponse>(`/search_musicbrainz/discography?${params}`, signal)
  } catch (error) {
    throw asUnavailable(error)
  }
}

/** Who an artist is (2.0.0-player.17): MusicBrainz's facts - in full since 2.0.0-player.45, their links and
 *  line-up too, from the same one request - cached on the server. */
export async function getArtistFacts(artistMbid: string, signal?: AbortSignal): Promise<ArtistFacts> {
  const params = new URLSearchParams({ mbid: artistMbid })

  try {
    return await get<ArtistFacts>(`/search_musicbrainz/artist?${params}`, signal)
  } catch (error) {
    throw asUnavailable(error)
  }
}

export function ping(): Promise<PingResponse> {
  return get<PingResponse>('/search_musicbrainz/ping')
}

function asUnavailable(error: unknown): unknown {
  if (error instanceof ApiError && error.status === 503) {
    return new MusicBrainzUnavailable(error.detail, error.busy)
  }
  return error
}
