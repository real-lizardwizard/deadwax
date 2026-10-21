import type { Song } from '../player/api'
import { get, post } from './http'

/**
 * Navidrome's own playlists, as the asker (2.0.0-player.58) - deadwax's six routes under /navidrome/playlists
 * (src/routes/navidrome.py). Reads take an abort signal (lib/latest.ts calls a superseded one off); writes never
 * do - a write is never called off. Ids are encoded into the path.
 */

/** deadwax's summary of one playlist (src/playlists.py `summary`). */
export interface Playlist {
  id: string
  name: string
  /** the description - Subsonic's `comment`; '' for none */
  comment: string
  /** in the list, Navidrome's stored count (songs not in the library just now included); on one playlist, the songs listed */
  songCount: number
  /** seconds */
  duration: number
  created: string
  /** moved by Navidrome on every add and removal - the picker's order */
  changed: string
  /** the owner's Navidrome user name, as Navidrome has it */
  owner: string
  public: boolean
  /** `pl-<id>_<hash>`, Navidrome's 2x2 mosaic - null for an empty playlist */
  coverArt: string | null
  /** the asker's own */
  mine: boolean
  /** the asker's own, and not a smart playlist or one kept in step with a file */
  editable: boolean
}

/** One playlist with its songs - Navidrome's own, as they are - and how many of them it isn't listing just now. */
export interface PlaylistWithSongs {
  playlist: Playlist
  songs: Song[]
  hidden: number
}

/** What an add came to: written (`done`, with how many were `added`), or - asked to ask - some there `already` and
 *  nothing written (`asked`: how many songs were asked about). */
export interface AddAnswer {
  done: boolean
  already: number
  added?: number
  asked?: number
}

export type Duplicates = 'ask' | 'add' | 'skip'

/** What Edit's Done sends: the songs as drawn when Edit began, the songs now, and only what else changed. */
export interface PlaylistEditBody {
  base: string[]
  song_ids: string[]
  /** (review) the songs a Done that failed sent - Navidrome may have taken them before failing, so the next Done
   *  finding them there is no change made in another app */
  tried?: string[]
  name?: string
  comment?: string
  public?: boolean
}

const one = (id: string) => `/navidrome/playlists/${encodeURIComponent(id)}`

export function playlists(signal?: AbortSignal): Promise<{ playlists: Playlist[] }> {
  return get<{ playlists: Playlist[] }>('/navidrome/playlists', signal)
}

export function playlist(id: string, signal?: AbortSignal): Promise<PlaylistWithSongs> {
  return get<PlaylistWithSongs>(one(id), signal)
}

export function createPlaylist(name: string, songIds: readonly string[]): Promise<PlaylistWithSongs> {
  return post<PlaylistWithSongs>('/navidrome/playlists', { name, song_ids: [...songIds] })
}

export function addToPlaylist(id: string, songIds: readonly string[], duplicates: Duplicates): Promise<AddAnswer> {
  return post<AddAnswer>(`${one(id)}/add`, { song_ids: [...songIds], duplicates })
}

export function editPlaylist(id: string, body: PlaylistEditBody): Promise<PlaylistWithSongs> {
  return post<PlaylistWithSongs>(`${one(id)}/edit`, body)
}

export function deletePlaylist(id: string): Promise<{ deleted: true }> {
  return post<{ deleted: true }>(`${one(id)}/delete`)
}
