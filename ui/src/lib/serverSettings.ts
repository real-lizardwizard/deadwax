/**
 * The app's Server settings page (2.0.0-player.33, app/ServerSettings.tsx) - its pure parts, pinned
 * by ui/test/settingslog.sim.cjs. The rules of the settings themselves (which tab a group sits on,
 * the tabs' marks, the drafts, the note asking for a secret again) were the main page's settings tab's
 * (it retired in 2.0.0-player.66), and lived in components/SettingsView.tsx until 2.1.33, when they
 * moved here word for word: the iPhone app's exporter (ios/scripts/export-server-vectors.cjs, on the
 * ios branch) runs pure files as they are, and the phone's Server settings follows these.
 */

import type { ServerSetting, ServerSettings } from '../api/settings'
import { SAVED_ANSWERS_GROUP } from './musicbrainzAnswers'

/** Server settings' three tabs (SERVER_TABS, below, lists them). */
export type SettingsTab = 'downloads' | 'library' | 'connections'

/** The settings tab's three SERVER tabs (the app's page has no browser preferences) - Library first,
 *  holding the most (paths, organizing, covers, lyrics) and the organizing verdict. The main page
 *  listed them Downloads, Library, Connections, after its Search tab; the app's page has no Search. */
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

/* ===== tabs (v0.9.15) - moved from components/SettingsView.tsx in 2.1.33 ===== */

/**
 * Which tab a server group belongs on. The server names its groups; a group this doesn't know
 * yet goes under Library rather than nowhere, so a setting added later is never unreachable.
 */
export function tabForGroup(groupId: string): SettingsTab {
  //? (2.0.0-player.48) logins - read-only, the environment's - sit with Navidrome, whose accounts they are;
  //? (2.0.0-player.54) MusicBrainz's saved answers, a group the server sends straight after Connections
  if (groupId === 'connections' || groupId === 'logins' || groupId === SAVED_ANSWERS_GROUP) return 'connections'
  if (groupId === 'downloads' || groupId === 'soulseek') return 'downloads'
  return 'library'
}

/**
 * A mark per tab: 'attention' when a server setting on it needs it (or, for Library, when
 * organizing is blocked), else 'unsaved' when it holds an edit, else nothing.
 */
export function tabMarks(
  server: ServerSettings | null,
  draftEnv: Record<string, unknown>,
): Partial<Record<SettingsTab, 'attention' | 'unsaved'>> {
  const marks: Partial<Record<SettingsTab, 'attention' | 'unsaved'>> = {}
  const groupOf = new Map<string, string>()
  for (const group of server?.groups ?? []) {
    for (const setting of group.settings) {
      groupOf.set(setting.key, group.id)
      if (setting.status === 'error') marks[tabForGroup(group.id)] = 'attention'
    }
  }
  if (server && !server.organizing.enabled && server.organizing.blockers.length) marks.library = 'attention'

  const unsaved = (tab: SettingsTab) => { if (!marks[tab]) marks[tab] = 'unsaved' }
  for (const key of Object.keys(draftEnv)) unsaved(tabForGroup(groupOf.get(key) ?? ''))
  return marks
}

/**
 * A secret that is sent to an address with every request, and what its row says while that
 * address has an unsaved new value and the secret hasn't been typed to go with it. The server
 * refuses that save - the saved secret is never sent somewhere it wasn't typed for - and saying so
 * beside the field beats a refusal in the save bar. The rule itself is the server's:
 * SECRET_FOR_ADDRESS and _moved_without_secret in src/routes/settings.py. Navidrome since v1.0.3,
 * slskd since v1.0.5. And since 2.0.0-player.65 the other half: the secret reverted (to the
 * environment's) while the address after the save isn't the environment's - said as `reverted`.
 */
const RETYPE_WITH_ADDRESS: Record<string, { address: string; note: string; reverted: string }> = {
  NAVIDROME_PASSWORD: {
    address: 'NAVIDROME_URL',
    note: "Type the password again to go with the new address - deadwax won't send the saved one to an address it wasn't entered for.",
    reverted:
      "Reverting brings back the environment's password, which was given for the environment's address - type the password again, or revert NAVIDROME_URL in the same save.",
  },
  SLSKD_APIKEY: {
    address: 'SLSKD_URL',
    note: "Type the API key again to go with the new address - deadwax won't send the saved one to an address it wasn't entered for.",
    reverted:
      "Reverting brings back the environment's API key, which was given for the environment's address - type the key again, or revert SLSKD_URL in the same save.",
  },
}

export function retypeSecretNote(
  key: string,
  server: ServerSettings | null,
  draftEnv: Record<string, string | null>,
): string | null {
  const rule = RETYPE_WITH_ADDRESS[key]
  if (!rule) return null

  const settings = (server?.groups ?? []).flatMap((group) => group.settings)
  const current = settings.find((setting) => setting.key === rule.address)?.value ?? ''
  const secret = settings.find((setting) => setting.key === key)
  const url = draftEnv[rule.address]

  //? (2.0.0-player.65) the other half, over two saves: the secret reverted while the address in force after the save
  //? - saved before, or typed now - isn't the environment's. Reverting brings back the environment's secret, which
  //? the server won't send to another address (ENVIRONMENTS_SECRET_ELSEWHERE in src/routes/settings.py)
  if (draftEnv[key] === null) {
    const row = settings.find((setting) => setting.key === rule.address)
    if (!secret?.env_set || url === null) return null
    const environments = (row?.overridden ? row.env_value : row?.value) ?? ''
    const after = typeof url === 'string' ? url.trim() : current.trim()
    return after && after !== environments.trim() ? rule.reverted : null
  }

  if (typeof url !== 'string' || !url.trim() || url.trim() === current.trim()) return null
  if (!secret?.value) return null
  if ((draftEnv[key] ?? '').trim()) return null
  return rule.note
}

/**
 * The server drafts after an edit of one setting (exported for the app's Server settings page,
 * 2.0.0-player.33, which keeps the same drafts): setting a value back to the one already saved is
 * no change and leaves the draft - except a secret's, which has no readable value, so any typing is
 * a change by definition.
 */
export function editedEnvDraft(
  current: Record<string, string | null>,
  key: string,
  value: string,
  committed: ServerSetting | undefined,
): Record<string, string | null> {
  const next = { ...current, [key]: value }
  if (committed && !committed.secret && (committed.value ?? '') === value) delete next[key]
  return next
}
