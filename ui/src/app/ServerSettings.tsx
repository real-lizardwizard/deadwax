import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { getServerSettings, saveServerSettings, type ServerSetting, type ServerSettings as Settings, type SettingUpdate } from '../api/settings'
import { OrganizeModes, OrganizingVerdict, ServerGroup, editedEnvDraft, tabForGroup, tabMarks, type SettingsTab } from '../components/SettingsView'
import { SERVER_TABS, SETTINGS_PHONE, draftsAfterSave, serverTabAfter } from '../lib/serverSettings'
import { isAbort, latestOnly } from '../lib/latest'
import { ChevronLeftIcon } from '../player/icons'

/** What the page holds beyond its own life: the settings as last answered, the drafts made against
 *  them, the tab, a save on its way and how the last ended - one page's worth, shared by every copy of
 *  the page mounted (an address can put it on another tab too). Kept until a reload, never stored. */
interface PageState {
  server: Settings | null
  drafts: Record<string, string | null>
  tab: SettingsTab
  saving: boolean
  saveError: string | null
  justSaved: boolean
}

const freshPage = (): PageState => ({ server: null, drafts: {}, tab: 'library', saving: false, saveError: null, justSaved: false })
let kept: PageState = freshPage()
const listeners = new Set<() => void>()
//? one read at a time for the page, wherever it is drawn (only the copy that shows ever reads)
const reads = latestOnly()

function keep(change: Partial<PageState> | ((state: PageState) => Partial<PageState>)): void {
  kept = { ...kept, ...(typeof change === 'function' ? change(kept) : change) }
  for (const listener of [...listeners]) listener()
}

/** For the sims: forget the page, as a fresh page would. */
export function forgetServerSettingsPage(): void {
  reads.supersede()
  kept = freshPage()
}

/**
 * The server's settings in the app, on a desktop (2.0.0-player.33) - the SERVER half of the main
 * page's settings tab (components/SettingsView.tsx), drawn from that tab's own parts: every group
 * GET /deadwax/settings returns, each row with its value and where it came from, its status, a
 * secret masked, choices as a dropdown, what can't be edited said, the organizing verdict, revert
 * deleting the override, the note asking for a secret again beside an address change. Pushed on You
 * (`#/you/settings/server`). There is no board for it; the desktop sidebar's Managing names it.
 *
 * Its groups sit under the settings tab's own three server tabs - Library, Downloads, Connections
 * (tabForGroup: a group it doesn't know goes under Library, so nothing is unreachable) - drawn as
 * the Edit panel's underline tabs. EVERY EDIT IS A DRAFT until Save, kept across the tabs (a tab
 * holding one is marked, as on the main page), and ONE save bar saves them all at once: the server
 * takes the whole batch or none of it, and a refusal is said in the bar with every draft still there.
 * Save is the screen's one solid purple button.
 *
 * NOT here, on purpose: the main page's browser preferences (search, candidates, auto-grab, the
 * interface) - they are that page's, kept in that browser - and Re-time lyrics, a bulk run. One line
 * says so, with the main page beside the app.
 *
 * Read the first time the page shows, and again each time it comes back into view WITH NO UNSAVED
 * DRAFT - a volume just fixed shows as fixed, and a draft is never read over; never at start-up. Each
 * read through latestOnly(), and a save calls any read still out off, so an older answer never lands
 * over what the save answered. The rows stay editable while a save is on its way: an edit made then
 * stays a draft (draftsAfterSave), never wiped unsent under "Saved.".
 *
 * Save and Discard go with the drafts; focus on either, as they go, is given to what the bar says -
 * never dropped to the page, where a keyboard or VoiceOver would start again from the top.
 *
 * WHAT IT HOLDS OUTLIVES IT (`kept`, below - review): App draws only the page on top of each tab, so
 * the page goes whenever another takes its place - the sidebar's Log or Needs a look (its siblings,
 * which replace it), Back, Go to album from the player bar. Its drafts are unsaved work the bar has
 * counted ("2 unsaved changes"), so they are kept in this module, with the refusal, the tab and the
 * settings they were made against, until Save or Discard - as the main page keeps its own for the
 * page's life. Coming back with a draft reads nothing over it; with none, it reads again.
 *
 * On a PHONE it is a short note, asking nothing.
 */
export function ServerSettings({
  desktop,
  live,
  onBack,
  backLabel,
}: {
  desktop: boolean
  /** this page is what shows - its tab current, the app in front, nothing over it */
  live: boolean
  onBack: () => void
  backLabel: string
}) {
  //? the page's state is the module's (`kept`): this copy draws it, and is drawn again as it changes
  const [, redraw] = useState(0)
  useEffect(() => {
    const listener = () => redraw((n) => n + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
  const { server, drafts: draftEnv, tab, saving, saveError, justSaved } = kept
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const tablist = useRef<HTMLDivElement>(null)
  const barText = useRef<HTMLSpanElement>(null)
  //? whether the last render drew Save and Discard
  const hadButtons = useRef(false)

  const read = () => {
    const ticket = reads.begin()
    setLoading(true)
    getServerSettings(ticket.signal).then(
      (answer) => {
        if (!ticket.current()) return
        keep({ server: answer })
        setError(null)
        setLoading(false)
      },
      (reason: unknown) => {
        if (!ticket.current() || isAbort(reason)) return
        setError(reason instanceof Error ? reason.message : 'Could not read settings')
        setLoading(false)
      },
    )
  }

  useEffect(() => {
    //? a draft is never read over - one kept from before the page was last left included
    if (!desktop || !live || Object.keys(kept.drafts).length) return
    read()
    return () => reads.supersede()
  }, [desktop, live])

  const settingsByKey = useMemo(() => {
    const map = new Map<string, ServerSetting>()
    for (const group of server?.groups ?? []) for (const setting of group.settings) map.set(setting.key, setting)
    return map
  }, [server])

  const edit = (key: string, value: string) => {
    keep((state) => ({ justSaved: false, drafts: editedEnvDraft(state.drafts, key, value, settingsByKey.get(key)) }))
  }
  const revert = (key: string) => {
    keep((state) => ({ justSaved: false, drafts: { ...state.drafts, [key]: null } }))
  }
  const discard = () => keep({ drafts: {}, saveError: null })
  const setTab = (next: SettingsTab) => keep({ tab: next })
  const dirty = Object.keys(draftEnv).length

  //? Save and Discard are drawn only with a draft: the save or discard that takes the last one takes
  //? them away, and focus on either would fall to the page. It goes to what the bar says instead -
  //? only when it fell (a click elsewhere meanwhile is left where it went)
  useLayoutEffect(() => {
    const had = hadButtons.current
    hadButtons.current = dirty > 0
    if (!had || dirty > 0 || typeof document === 'undefined') return
    const active = document.activeElement
    if (!active || active === document.body) barText.current?.focus()
  })

  //? the save's answer lands in the module whether or not the page is still drawn: left mid-save, the
  //? page comes back to what it answered
  const save = async () => {
    if (kept.saving || !Object.keys(kept.drafts).length) return
    //? a read still out would land over what the save answers
    reads.supersede()
    setLoading(false)
    //? what this save carries: an edit made while it is on its way is not in it, and stays a draft
    const sent = kept.drafts
    keep({ saving: true, saveError: null })
    try {
      const updates: SettingUpdate[] = Object.entries(sent).map(([key, value]) => ({ key, value }))
      const answer = await saveServerSettings(updates)
      //? the settings were just answered: a failed read's line would say something untrue beside them
      setError(null)
      keep((state) => {
        const left = draftsAfterSave(state.drafts, sent)
        return { server: answer, drafts: left, justSaved: !Object.keys(left).length, saving: false }
      })
    } catch (caught: unknown) {
      //? the server took none of the batch: every draft stays, and the bar says why
      keep({ saveError: caught instanceof Error ? caught.message : 'Could not save', saving: false })
    }
  }

  const header = (
    <>
      <header class="pl-nav-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
      </header>
      <header class="pl-large-header">
        <h1 class="pl-large-title">Server settings</h1>
      </header>
    </>
  )

  if (!desktop) {
    return (
      <section class="app-settings is-phone app-needs">
        {header}
        <div class="app-card app-placeholder-body">
          <p class="app-placeholder-text app-settings-phone">
            {SETTINGS_PHONE}{' '}
            <a class="app-queue-link" href="/" target="_blank" rel="noopener">
              the main page
            </a>
            .
          </p>
        </div>
      </section>
    )
  }

  const marks = tabMarks(server, draftEnv, {}, {})
  const groups = (server?.groups ?? []).filter((group) => tabForGroup(group.id) === tab)
  const onTabKey = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const next = serverTabAfter(tab, step)
    setTab(next)
    tablist.current?.querySelector<HTMLElement>(`[data-tab="${next}"]`)?.focus()
  }

  return (
    <section class="app-settings">
      {header}
      <div class="app-settings-body">
        <p class="app-settings-line">
          What deadwax itself runs with, from your compose file or <code>.env</code>. Changing one here stores an override
          that wins over the environment and applies without a restart. This browser's preferences and re-timing saved
          lyrics are on{' '}
          <a class="app-queue-link" href="/" target="_blank" rel="noopener">
            the main page
          </a>
          .
        </p>

        {!server && error ? (
          <div class="app-settings-state">
            <p>deadwax couldn't read its settings: {error}</p>
            <button type="button" class="app-button" aria-disabled={loading ? 'true' : undefined} onClick={() => !loading && read()}>
              Try again
            </button>
          </div>
        ) : !server ? (
          <div class="pl-spinner" aria-label="Reading the settings" />
        ) : (
          <>
            <div ref={tablist} class="app-edit-tabs app-settings-tabs" role="tablist" aria-label="Server settings" onKeyDown={onTabKey}>
              {SERVER_TABS.map((entry) => {
                const chosen = entry.id === tab
                return (
                  <button
                    key={entry.id}
                    type="button"
                    role="tab"
                    id={`app-settings-tab-${entry.id}`}
                    class={`app-edit-tab app-settings-tab${chosen ? ' is-on' : ''}`}
                    data-tab={entry.id}
                    aria-selected={chosen}
                    aria-controls="app-settings-panel"
                    tabIndex={chosen ? 0 : -1}
                    title={entry.hint}
                    onClick={() => setTab(entry.id)}
                  >
                    {entry.label}
                    {marks[entry.id] === 'attention' && <span class="app-settings-mark is-attention" title="A setting here needs attention" />}
                    {marks[entry.id] === 'unsaved' && <span class="app-settings-mark" title="Unsaved changes here" />}
                  </button>
                )
              })}
            </div>
            {error && <p class="app-settings-problem">Couldn't read the settings again just now: {error}</p>}

            <div id="app-settings-panel" class="app-settings-panel" role="tabpanel" aria-labelledby={`app-settings-tab-${tab}`}>
              {tab === 'library' && <OrganizingVerdict organizing={server.organizing} />}
              {groups.map((group) => (
                <ServerGroup key={group.id} group={group} server={server} draftEnv={draftEnv} onEdit={edit} onRevert={revert} />
              ))}
              {tab === 'library' && <OrganizeModes modes={server.organize_modes} />}
            </div>
          </>
        )}
      </div>

      {/* always there, at the foot of the page above the player bar: says nothing until there is something to save */}
      {/* the region is its words alone (review): around Discard and Save too, a screen reader read their
          names with every change - "1 unsaved change, Discard, Save changes" */}
      <div class={`app-settings-savebar${saveError ? ' has-error' : ''}${dirty || saveError || justSaved ? ' is-said' : ''}`}>
        <span ref={barText} class="app-settings-savebar-text" role="status" tabIndex={-1}>
          {saveError ? `Not saved: ${saveError}` : justSaved && !dirty ? 'Saved.' : dirty ? `${dirty} unsaved change${dirty === 1 ? '' : 's'}` : ''}
        </span>
        {dirty > 0 && (
          <>
            <button type="button" class="app-button app-settings-discard" aria-disabled={saving ? 'true' : undefined} onClick={() => !saving && discard()}>
              Discard
            </button>
            <button type="button" class="app-button is-primary app-settings-save" aria-disabled={saving ? 'true' : undefined} onClick={() => void save()}>
              {saving ? 'Saving…' : 'Save changes'}
            </button>
          </>
        )}
      </div>
    </section>
  )
}
