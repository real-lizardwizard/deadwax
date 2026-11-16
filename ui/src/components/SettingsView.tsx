/**
 * The server settings' parts: the rows, groups and verdict the app's Server settings page
 * (app/ServerSettings.tsx, 2.0.0-player.33) is drawn from. This file held the main page's whole settings
 * tab (v0.5.1, tabs since v0.9.15) until the main page retired in 2.0.0-player.66; the name is kept, so
 * the imports and sims that name it hold, and what is left is what the app draws. The rules beside them -
 * which tab a group sits on, the tabs' marks, the drafts, the note asking for a secret again - moved to
 * lib/serverSettings.ts in 2.1.33, word for word, so the iPhone app's exporter can run them as they are.
 */

import type { ComponentChildren } from 'preact'

import type { ServerSetting, ServerSettings, SettingGroup as ServerSettingsGroup } from '../api/settings'
import { retypeSecretNote } from '../lib/serverSettings'

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
          ? 'Organizing is active — finished downloads will be moved into the library, tagged and filed.'
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
    //? lists them - COVER_ART_SIZE and FETCH_LYRICS, say. A text box would take anything and then
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
