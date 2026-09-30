/**
 * The connection checks the app's You tab runs as it first shows - the same pings the main page's
 * pills make (interface/scripts/init.js), and the player's Navidrome status.
 *
 * A ping answers 200 with `{status: 'ok'}` or `{status: 'failed', code, error}`: a failure is in
 * the body, not the status. The code is a short name ("NOT_LOGGED_IN", 401) and the error slskd's
 * or deadwax's own sentence - both text from the server, shown as text.
 */

import { get } from './http'

export interface PingAnswer {
  status: string
  code?: string | number
  error?: string
}

export function pingMusicBrainz(signal?: AbortSignal): Promise<PingAnswer> {
  return get<PingAnswer>('/search_musicbrainz/ping', signal)
}

export function pingSlskd(signal?: AbortSignal): Promise<PingAnswer> {
  return get<PingAnswer>('/monitor_slskd/ping', signal)
}
