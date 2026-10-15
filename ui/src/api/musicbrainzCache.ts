import { get, post } from './http'

/**
 * MusicBrainz's saved answers (2.0.0-player.54): every answer MusicBrainz gives, kept on disk by the
 * server for everyone (src/musicbrainz_cache.py), and what the settings show beside its two settings -
 * GET /deadwax/settings/musicbrainz_cache, and its Clear. Both an admin's, as the settings are.
 */
export interface SavedAnswersStats {
  /** Whether answers are being saved: MUSICBRAINZ_CACHE_MB isn't 0. */
  enabled: boolean
  /** The file, as the server sees it. */
  path: string
  /** Its size on disk, in bytes - 0 when there is no such file, or it isn't the saved answers. */
  bytes: number
  /** How many answers it holds. */
  answers: number
  /** MUSICBRAINZ_CACHE_MB as used. */
  limit_mb: number
  /** What is wrong with the file, in words, or null. */
  problem: string | null
}

/** `signal`: lib/latest.ts calls an older read off as a newer one begins. */
export function getSavedAnswers(signal?: AbortSignal): Promise<SavedAnswersStats> {
  return get<SavedAnswersStats>('/settings/musicbrainz_cache', signal)
}

/** Every saved answer gone, on disk and in memory - and the file as it is after. Never called off once
 *  sent: aborting the request wouldn't undo the clearing. */
export function clearSavedAnswers(): Promise<SavedAnswersStats> {
  return post<SavedAnswersStats>('/settings/musicbrainz_cache/clear')
}
