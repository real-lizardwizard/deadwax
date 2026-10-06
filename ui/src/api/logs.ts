import { get, url } from './http'

/**
 * The event log (2.0.0-player.33): the lines deadwax kept for the page, and the stream's address.
 * See src/logger.py - the last 500 lines meant for the page since deadwax started, each numbered.
 */

/** One line of the log, as the stream sends it. */
export interface LogLine {
  /** the level: INFO, WARNING, ERROR... */
  event_type: string
  event_content: string
  /** which part of deadwax said it, when it said */
  src?: string
  /** rising by one per line, from 1 each time deadwax starts */
  seq?: number
  /** when the server logged it, seconds since 1970 */
  time?: number
  /** which run of deadwax numbered it */
  boot?: string
}

export interface RecentLog {
  lines: LogLine[]
  last: number
  boot: string
}

export function recentLog(signal?: AbortSignal): Promise<RecentLog> {
  return get<RecentLog>('/interface_logs/recent', signal)
}

/** The stream, sending first the kept lines after `last` of run `boot` (none given: from now only). */
export function logStreamUrl(last: number | null, boot: string | null): string {
  const query = last !== null && boot ? `?after=${last}&boot=${encodeURIComponent(boot)}` : ''
  return url(`/interface_logs/interface_logs${query}`)
}
