/**
 * Who the page is talking to - `GET /deadwax/me` (src/routes/me.py). With logins off, the one
 * implicit admin, `local`; the app shows or hides its admin-only rows, and Sign out, from this
 * rather than from assumptions, so step 3's logins change what it says and nothing in the page.
 */

import type { GetSettings, GetSettingsAnswer } from '../lib/getSettings'
import type { PinKind, PinsAnswer, PinToggleBody } from '../lib/pins'
import { get, post, put } from './http'

export interface Me {
  user: string
  admin: boolean
  /** 'off' while deadwax has no logins */
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
