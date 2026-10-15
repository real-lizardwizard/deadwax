/**
 * Who the page is talking to - `GET /deadwax/me` (src/routes/me.py). With logins off, the one
 * implicit admin, `local`; with them on (2.0.0-player.48), the signed-in user - or a 401, which brings
 * the sign-in screen (app/signInGate.tsx). The app shows or hides its admin-only rows, and Sign out,
 * from this rather than from assumptions.
 */

import type { GetSettings, GetSettingsAnswer } from '../lib/getSettings'
import type { PinKind, PinsAnswer, PinToggleBody } from '../lib/pins'
import { get, post, put } from './http'
import type { AddedToLibrary, FindCandidatesRequest, MyLibrary } from './types'

export interface Me {
  user: string
  admin: boolean
  /** 'off' while deadwax has no logins; 'on' with AUTH_MODE on (2.0.0-player.48) */
  auth: 'off' | 'on'
  /** src/__init__.py's __version__ - "2.0.0-player.12" */
  version: string
}

export function me(signal?: AbortSignal): Promise<Me> {
  return get<Me>('/me', signal)
}

/**
 * What the user chose in You > Getting albums (2.0.0-player.15) - kept per user on the server
 * (src/routes/me.py): "When I tap Get" and the quality floor, which of them they set, and whether
 * deadwax can keep them.
 */
export function getPreferences(signal?: AbortSignal): Promise<GetSettingsAnswer> {
  return get<GetSettingsAnswer>('/me/preferences', signal)
}

/** Set any of them; the rest stay. Answers with all of them, as getPreferences does. */
export function putPreferences(values: Partial<GetSettings>): Promise<GetSettingsAnswer> {
  return put<GetSettingsAnswer>('/me/preferences', values)
}

/**
 * What the user pinned to Home (2.0.0-player.18) - kept per user on the server (src/routes/pins.py),
 * deadwax's own and never Navidrome's stars: every pin as it is now, its state and what it opens.
 */
export function getPins(signal?: AbortSignal): Promise<PinsAnswer> {
  return get<PinsAnswer>('/me/pins', signal)
}

/**
 * Home's Edit: the whole ordered list - the pins it names, in its order; the rest are unpinned - and
 * `known`, the list it was made from: a pin stored since that it doesn't hold keeps its place.
 */
export function putPins(body: { pins: { kind: PinKind; ref: string }[]; known?: { kind: PinKind; ref: string }[] }): Promise<PinsAnswer> {
  return put<PinsAnswer>('/me/pins', body)
}

/** Pin or unpin one album or artist, by what it is (lib/pins.ts toggleBody). Answers with every pin. */
export function togglePin(body: PinToggleBody): Promise<PinsAnswer> {
  return post<PinsAnswer>('/me/pins/toggle', body)
}

/**
 * Your library (2.0.0-player.51, personal libraries) - your starred albums in Navidrome, as deadwax keeps
 * them (src/routes/my_library.py): how many, what still waits to be starred and why, what is new in it,
 * and what the admin deleted. `{ on: false }` with logins off.
 */
export function myLibrary(signal?: AbortSignal): Promise<MyLibrary> {
  return get<MyLibrary>('/me/library', signal)
}

/** Add to my library: a pressing the store holds - the release a Get would download - into yours. */
export function addToMyLibrary(release: FindCandidatesRequest): Promise<AddedToLibrary> {
  return post<AddedToLibrary>('/me/library/add', release)
}

/** You opened it: the "new in your library" marker goes from it - by release id, or by the store's ids. */
export function markLibrarySeen(by: { release_mbid?: string; album_ids?: number[] }): Promise<{ cleared: number }> {
  return post<{ cleared: number }>('/me/library/seen', by)
}

/** Put away an album the admin deleted ("removed by the admin"). */
export function dismissRemoved(albumId: number): Promise<{ dismissed: boolean }> {
  return post<{ dismissed: boolean }>('/me/library/dismiss', { album_id: albumId })
}
