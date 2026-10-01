/**
 * Who the page is talking to - `GET /deadwax/me` (src/routes/me.py). With logins off, the one
 * implicit admin, `local`; the app shows or hides its admin-only rows, and Sign out, from this
 * rather than from assumptions, so step 3's logins change what it says and nothing in the page.
 */

import { get } from './http'

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
