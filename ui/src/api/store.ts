import { get } from './http'
import type { StoreAlbumResponse } from './types'

/**
 * The id bridge (2.0.0-player.17): one album across its three ids - the store index's rows of the
 * release (its folder, edition, formats), the album's other pressings, and Navidrome's album id for
 * each, which the server looks up itself (src/routes/store_album.py). Asked by the release
 * (a Requests row, an album you hold seen from MusicBrainz) or by Navidrome's album id (the album
 * page, Info). `navidrome_id` is null when Navidrome doesn't have the album (yet) or can't be asked.
 */
export function storeAlbum(
  by: { release_mbid: string } | { navidrome_id: string },
  signal?: AbortSignal,
): Promise<StoreAlbumResponse> {
  const params = new URLSearchParams(by)
  return get<StoreAlbumResponse>(`/store/album?${params}`, signal)
}

/**
 * Navidrome's album for the first of `releases` Navidrome has - the album you have, opened from
 * MusicBrainz's side (an artist page's row, a Search row found held, a Requests row): each release
 * asked of the id bridge in turn, the first with an id wins. Null when Navidrome has none of them
 * (yet) or can't be asked.
 */
export async function navidromeAlbumFor(releases: readonly string[], signal?: AbortSignal): Promise<string | null> {
  for (const release of releases) {
    const answer = await storeAlbum({ release_mbid: release }, signal)
    if (answer.navidrome_id) return answer.navidrome_id
  }
  return null
}
