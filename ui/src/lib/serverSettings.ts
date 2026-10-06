/**
 * The app's Server settings page (2.0.0-player.33, app/ServerSettings.tsx) - its pure parts, pinned
 * by ui/test/settingslog.sim.cjs. The rules of the settings themselves (which tab a group sits on,
 * the drafts, the note asking for a secret again) are the main page's settings tab's, imported from
 * components/SettingsView.tsx, never copied.
 */

import type { SettingsTab } from '../components/SettingsView'

/** The settings tab's three SERVER tabs (the app's page has no browser preferences) - Library first,
 *  holding the most (paths, organizing, covers, lyrics) and the organizing verdict. The main page
 *  lists them Downloads, Library, Connections, after its Search tab; the app's page has no Search. */
export const SERVER_TABS: readonly { id: SettingsTab; label: string; hint: string }[] = [
  { id: 'library', label: 'Library', hint: 'Paths, organizing, covers and lyrics' },
  { id: 'downloads', label: 'Downloads', hint: 'Choosing and fetching from Soulseek' },
  { id: 'connections', label: 'Connections', hint: 'slskd, MusicBrainz, Navidrome and the picture sources' },
]

/** The tab an arrow key moves to, round from the ends. */
export function serverTabAfter(tab: SettingsTab, step: number): SettingsTab {
  const at = Math.max(0, SERVER_TABS.findIndex((entry) => entry.id === tab))
  return SERVER_TABS[(at + step + SERVER_TABS.length) % SERVER_TABS.length]!.id
}

/**
 * The drafts left once a save of `sent` has been answered. The rows stay editable while a save is on
 * its way (the server stats every path it is sent, which on a NAS takes a moment), so an edit can be
 * made meanwhile: only what was sent, and still as it was sent, goes - a key typed again since, or one
 * the save never carried, stays a draft, to be saved next, rather than wiped unsent under "Saved.".
 */
export function draftsAfterSave(
  current: Readonly<Record<string, string | null>>,
  sent: Readonly<Record<string, string | null>>,
): Record<string, string | null> {
  const left: Record<string, string | null> = {}
  for (const [key, value] of Object.entries(current)) {
    if (!(key in sent) || sent[key] !== value) left[key] = value
  }
  return left
}

/** What the page says on a phone, before its link to the main page. */
export const SETTINGS_PHONE = "Changing deadwax's settings needs a wider screen for now - or"
