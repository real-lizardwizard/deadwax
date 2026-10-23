/**
 * The server settings' parts: the rows, groups, verdict, drafts and tab marks the app's Server settings
 * page (app/ServerSettings.tsx, 2.0.0-player.33) is drawn from, with the rules beside them - which tab a
 * group sits on, the drafts, the note asking for a secret again. This file held the main page's whole
 * settings tab (v0.5.1, tabs since v0.9.15) until the main page retired in 2.0.0-player.66; the name is
 * kept, so the imports and sims that name it hold, and what is left is what the app draws.
 */

import type { ComponentChildren } from 'preact'

import type { ServerSetting, ServerSettings, SettingGroup as ServerSettingsGroup } from '../api/settings'
import { SAVED_ANSWERS_GROUP } from '../lib/musicbrainzAnswers'

/* ===== tabs (v0.9.15) ===== */

/** Server settings' three tabs (lib/serverSettings.ts's SERVER_TABS lists them). */
export type SettingsTab = 'downloads' | 'library' | 'connections'

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

/* ============================================================================
 * Small shared pieces
 * ==========================================================================*/

export function Section({
  title,
  note,
  children,
}: {
  title: string
  note?: ComponentChildren
  children: ComponentChildren
}) {
  return (
    <section class="settings-section">
      <h3 class="settings-section-title">{title}</h3>
      {note ? <p class="settings-section-note">{note}</p> : null}
      <div class="settings-section-body">{children}</div>
    </section>
  )
}

/* ============================================================================
 * Server configuration - editable (v0.5.1)
 *
 * SERVER SETTINGS ARE EDITABLE, with two exceptions that are shown and explained rather than
 * hidden - DB_PATH is the database the overrides live in, and PUID/PGID are consumed by the
 * entrypoint before Python starts. Saving one stores an OVERRIDE that wins over the
 * environment, applies live without a restart, and is announced as an override with a revert
 * control. See the long note at the top of src/routes/settings.py for why the override has to
 * win rather than the environment.
 * ==========================================================================*/

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

/**
 * A server group's rows (exported for the app's Server settings page, 2.0.0-player.33): every
 * setting, its draft, and the note another row's edit asks of it. `children` follow the rows inside
 * the group - Re-time saved lyrics, under the lyrics group (components/RetimeLyrics.tsx, since
 * 2.0.0-player.42), and since 2.0.0-player.54 Clear MusicBrainz's saved answers under theirs
 * (components/MusicBrainzAnswers.tsx).
 */
export function ServerGroup({
  group,
  server,
  draftEnv,
  onEdit,
  onRevert,
  children,
}: {
  group: ServerSettingsGroup
  server: ServerSettings | null
  draftEnv: Record<string, string | null>
  onEdit: (key: string, value: string) => void
  onRevert: (key: string) => void
  children?: ComponentChildren
}) {
  return (
    <Section title={group.label} note={group.note}>
      <div class="settings-env-list">
        {group.settings.map((setting) => (
          <SettingRow
            key={setting.key}
            setting={setting}
            draft={draftEnv[setting.key]}
            onEdit={onEdit}
            onRevert={onRevert}
            note={retypeSecretNote(setting.key, server, draftEnv)}
          />
        ))}
      </div>
      {children}
    </Section>
  )
}

/** Whether organizing can happen, and every reason it can't - said once, at the top of Library. */
export function OrganizingVerdict({ organizing }: { organizing: ServerSettings['organizing'] }) {
  return (
    <div class={`settings-verdict${organizing.enabled ? ' ok' : ''}`} role="status">
      <span class="settings-verdict-title">
        {organizing.enabled
          ? 'Organizing is active — finished downloads will be tagged and filed.'
          : 'Organizing will not file anything right now.'}
      </span>

      {organizing.blockers.length ? (
        <ul class="settings-verdict-list">
          {organizing.blockers.map((blocker) => (
            <li key={blocker}>{blocker}</li>
          ))}
        </ul>
      ) : null}
    </div>
  )
}

/** What ORGANIZE_MODE can be set to, least to most destructive. */
export function OrganizeModes({ modes }: { modes: ServerSettings['organize_modes'] }) {
  return (
    <Section
      title="Organize modes"
      note="What each ORGANIZE_MODE does with a finished download, from the safest to the one that moves files."
    >
      <div class="settings-env-list">
        {Object.entries(modes).map(([mode, description]) => (
          <div key={mode} class="settings-mode">
            <code class="settings-mode-name">{mode}</code>
            <span class="settings-mode-note">{description}</span>
          </div>
        ))}
      </div>
    </Section>
  )
}

export function SettingRow({
  setting,
  draft,
  onEdit,
  onRevert,
  note,
}: {
  setting: ServerSetting
  /** The pending edit: a string, `null` for "revert", or undefined when untouched. */
  draft: string | null | undefined
  onEdit: (key: string, value: string) => void
  onRevert: (key: string) => void
  /** Something another row's edit asks of this one, said before the save refuses it. */
  note?: string | null
}) {
  const edited = draft !== undefined
  const reverting = draft === null

  /*
   * A secret is never sent to the browser, so there is no current value to put in the field.
   * The placeholder carries whether one exists, and typing replaces it wholesale - which is
   * the only thing you can do with a value you cannot read.
   */
  const value = typeof draft === 'string' ? draft : setting.secret ? '' : (setting.value ?? '')

  const control = !setting.editable ? (
    <span class="settings-env-locked" title={setting.locked_reason ?? undefined}>Locked</span>
  ) : setting.choices ? (
    //? A setting that only takes certain values is offered only those values, as the server
    //? lists them - ORGANIZE_MODE and COVER_ART_SIZE. A text box would take anything and then
    //? refuse it on save.
    <select
      class="settings-env-input"
      value={value}
      onChange={(e) => onEdit(setting.key, (e.currentTarget as HTMLSelectElement).value)}
    >
      {Object.entries(setting.choices).map(([choice, label]) => (
        <option key={choice} value={choice}>{label}</option>
      ))}
    </select>
  ) : (
    <input
      class="settings-env-input"
      type={setting.secret ? 'password' : 'text'}
      value={value}
      spellcheck={false}
      autocomplete="off"
      placeholder={setting.secret ? (setting.value ? '•••••••• (set)' : 'not set') : 'not set'}
      onInput={(e) => onEdit(setting.key, (e.currentTarget as HTMLInputElement).value)}
    />
  )

  return (
    <div
      class={`settings-env settings-env-${setting.status}${edited ? ' is-edited' : ''}`}
    >
      <div class="settings-env-head">
        <code class="settings-env-key">{setting.key}</code>

        {setting.overridden && !edited ? (
          <span class="settings-env-source is-override" title="Set here, overriding the environment">
            Set here
          </span>
        ) : setting.source ? (
          <span class="settings-env-source" title="Which file supplied this value">
            From {setting.source}
          </span>
        ) : null}

        {edited ? <span class="settings-env-badge is-edited">Unsaved</span> : null}
        {setting.status === 'error' && !edited ? (
          <span class="settings-env-badge">Needs attention</span>
        ) : null}
      </div>

      <div class="settings-env-control">{control}</div>

      <div class="settings-env-effect">{setting.effect}</div>

      {/*
        A locked setting explains itself. A disabled control with no reason attached reads as
        a bug rather than as a decision, and this one has a good reason.
      */}
      {!setting.editable && setting.locked_reason ? (
        <div class="settings-env-effect">{setting.locked_reason}</div>
      ) : null}

      {/*
        An override that cannot be undone becomes state nobody remembers setting. Reverting
        deletes the stored row rather than writing the environment's value back, so the
        setting follows the compose file again from then on.
      */}
      {/* (2.0.0-player.65) only where it can be saved: a locked row's revert is refused by the save */}
      {setting.overridden && setting.editable && !reverting ? (
        <button type="button" class="settings-env-revert" onClick={() => onRevert(setting.key)}>
          Revert to the environment{setting.env_value ? ` (${setting.env_value})` : ''}
        </button>
      ) : null}

      {reverting ? <div class="settings-env-effect">Will revert to the environment on save.</div> : null}

      {note ? <div class="settings-env-detail">{note}</div> : null}

      {setting.detail && !edited ? <div class="settings-env-detail">{setting.detail}</div> : null}
    </div>
  )
}
