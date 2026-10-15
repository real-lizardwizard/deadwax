/**
 * MusicBrainz's saved answers beside their settings (2.0.0-player.54, components/MusicBrainzAnswers.tsx) -
 * its pure parts, pinned by ui/test/mbanswers.sim.cjs: the words under Clear, and when the line is
 * read again.
 */

import type { SavedAnswersStats } from '../api/musicbrainzCache'
import type { SettingGroup } from '../api/settings'

/** The server's settings group the two settings are in, and Clear is drawn under (src/routes/settings.py). */
export const SAVED_ANSWERS_GROUP = 'musicbrainz-cache'

/** The setting that names the file: Clear empties the file that is SAVED, so a draft of it holds Clear back. */
export const SAVED_ANSWERS_PATH = 'MUSICBRAINZ_CACHE_PATH'

/** A size as people say it: bytes, KB, then MB to one place (1024s, as the settings' MB are). */
export function describeBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} bytes`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

const answersCount = (count: number) => `${count.toLocaleString('en')} answer${count === 1 ? '' : 's'}`

/** The line under Clear: what the file holds, and whether anything is being saved at all. */
export function describeSavedAnswers(stats: SavedAnswersStats, cleared: boolean): string {
  if (stats.problem) return `Nothing is being saved: ${stats.problem}.`
  const held = `${answersCount(stats.answers)} in ${describeBytes(stats.bytes)}`
  if (!stats.enabled) {
    return stats.answers
      ? `Saving is off (MUSICBRAINZ_CACHE_MB is 0), and the file still holds ${held}.`
      : 'Saving is off (MUSICBRAINZ_CACHE_MB is 0): answers are kept in memory only, for an hour.'
  }
  if (!stats.answers) {
    return cleared ? 'Cleared. The next answers are asked of MusicBrainz again.' : 'Nothing saved yet.'
  }
  return `${held} saved, of ${stats.limit_mb} MB.`
}

/** What the line is read again on: the group's settings as saved. A save that moves the file or changes its
 *  size draws Clear afresh, which reads the file the settings now name. */
export function savedAnswersKey(group: SettingGroup): string {
  return group.settings.map((setting) => `${setting.key}=${setting.value ?? ''}`).join('|')
}
