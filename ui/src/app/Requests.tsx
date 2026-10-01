import type { JSX } from 'preact'
import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { SECTIONS, SECTION_TITLES, changes, type RequestRow, type RequestsView, type Section } from '../lib/requestsView'
import { readPreferences } from '../state/persisted'
import { AttentionCard, DoneRow, DownloadingCard, WaitingCard } from './JobCard'

/**
 * The Requests tab (2.0.0-player.12): the downloads, as the Requests board draws them - Downloading,
 * Waiting, Needs attention and Done, each only when it has something in it - and "Clear done".
 *
 * Everything comes from App, which calls useDownloadJobs ONCE for the whole app (it polls fast only
 * while this tab shows) and works the rows out with lib/requestsView.ts: the headings, the words,
 * which button is the primary one. This lays them out and hands taps back - cancel, next peer, ask
 * again, clear - to the hook's own actions, which put their overlay up in the tap ("cancelling…",
 * "trying next peer…") before anything goes to the server.
 *
 * Until the first answer comes (`answered`), a spinner - never "Nothing requested yet", which would
 * be a claim made before anything was known: a cold open on #requests (iOS reloads a tab it put
 * aside) waits a round trip, and longer while slskd is slow to answer deadwax.
 *
 * Cancelling asks first, IN the card - "Keep it" or "Cancel download" - unless "Confirm before
 * cancelling" is turned off on this device (the main page's preference, read at the tap): a cancel
 * gives up the place in the peer's queue, and with SLSKD_INCOMPLETE_PATH set deletes the
 * part-downloaded file. Never window.confirm(), which would hold the page that plays the music
 * (JobCard.tsx says why). One card asks at a time.
 *
 * For a screen reader, one polite live region says what changed (lib/requestsView.ts's `changes`):
 * a card under another heading, a retry's refusal, a tap's answer starting. A card that moved is
 * drawn afresh in another list, so the control a keyboard had on it is gone; focus goes to the card
 * in its new place instead of falling to the page.
 *
 * Needs no Navidrome - nothing here plays anything - and reads no context.
 */
export function Requests({
  view,
  answered = true,
  trackingEnabled,
  error,
  onCancel,
  onRetry,
  onClear,
}: {
  view: RequestsView
  /** deadwax has answered once (or failed to): until then nothing is known, empty or not */
  answered?: boolean
  /** false when deadwax can't write its database: downloads still work, but none is kept track of */
  trackingEnabled: boolean
  /** why the last look at the downloads failed; the rows stay as they were meanwhile */
  error: string | null
  onCancel: (jobId: number) => Promise<void>
  onRetry: (jobId: number, samePeer?: boolean) => Promise<void>
  onClear: () => Promise<void>
}) {
  //? the card asking "cancel it?", by its row's key - one at a time
  const [asking, setAsking] = useState<string | null>(null)

  //? what the live region says, worked out once per new view (a view is a new object per change)
  const seen = useRef<{ view: RequestsView | null; said: string; moved: string[] }>({ view: null, said: '', moved: [] })
  if (seen.current.view !== view) {
    const { said, moved } = changes(seen.current.view, view)
    seen.current = { view, said: said || seen.current.said, moved }
  }

  //? the card a keyboard was in, so focus can follow it to another heading
  const page = useRef<HTMLElement | null>(null)
  const focusedRow = useRef<string | null>(null)
  const onFocusIn = (event: FocusEvent) => {
    const card = (event.target as HTMLElement | null)?.closest?.('[data-row]') as HTMLElement | null
    focusedRow.current = card?.dataset.row ?? null
  }
  const onFocusOut = (event: FocusEvent) => {
    //? a removed card's focus goes nowhere (no relatedTarget): kept, so it can be put back
    const next = event.relatedTarget as Node | null
    if (next && !page.current?.contains(next)) focusedRow.current = null
  }
  useLayoutEffect(() => {
    const key = focusedRow.current
    if (!key || !seen.current.moved.includes(key)) return
    const active = document.activeElement
    if (active && active !== document.body) return
    const card = page.current?.querySelector<HTMLElement>(`[data-row="${CSS.escape(key)}"]`)
    card?.focus()
  })

  const cancelNow = (row: RequestRow) => {
    setAsking(null)
    if (row.jobId === null || row.cancel !== 'ready') return
    void onCancel(row.jobId).catch((caught: unknown) => console.error(`Cancel error: ${message(caught)}`))
  }

  //? the ✕: cancel, or ask first; a second tap on the ✕ asking closes the question
  const cancel = (row: RequestRow) => {
    if (row.jobId === null || row.cancel !== 'ready') return
    if (asking === row.key) setAsking(null)
    else if (readPreferences().confirmCancel) setAsking(row.key)
    else cancelNow(row)
  }

  const keep = () => setAsking(null)

  const retry = (row: RequestRow, samePeer: boolean) => {
    //? the hook keeps its own refusal for the row (retryProblems); nothing to catch here
    if (row.jobId !== null) void onRetry(row.jobId, samePeer)
  }

  const clear = () => {
    void onClear().catch((caught: unknown) => console.error(`Clear jobs error: ${message(caught)}`))
  }

  const card = (section: Section, row: RequestRow): JSX.Element => {
    const cancelling = { onCancel: cancel, asking: asking === row.key, onKeep: keep, onConfirm: cancelNow }
    if (section === 'downloading') return <DownloadingCard row={row} {...cancelling} />
    if (section === 'waiting') return <WaitingCard row={row} {...cancelling} />
    if (section === 'attention') return <AttentionCard row={row} onRetry={retry} />
    return <DoneRow row={row} />
  }

  return (
    <section class="app-requests" ref={page} onFocusIn={onFocusIn} onFocusOut={onFocusOut}>
      <header class="pl-large-header">
        <h1 class="pl-large-title">Requests</h1>
        <button type="button" class="app-text-button app-clear-done" disabled={!view.clearable} onClick={clear}>
          Clear done
        </button>
      </header>

      <p class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">
        {seen.current.said}
      </p>

      {error && (
        <div class="app-card app-placeholder-body" role="status">
          <p class="app-placeholder-lead">Can't get your requests from deadwax</p>
          <p class="app-placeholder-text app-error">{error}</p>
          <p class="app-placeholder-text">
            {view.empty
              ? 'It keeps asking while this tab is open.'
              : "It keeps asking while this tab is open; what's below is from the last answer."}
          </p>
        </div>
      )}

      {!trackingEnabled ? (
        <div class="app-card app-placeholder-body">
          <p class="app-placeholder-lead">Downloads aren't being kept track of</p>
          <p class="app-placeholder-text">
            deadwax can't write its database. Downloads still arrive in slskd's folder, but they can't be
            listed here or filed into your library. Check <span class="app-mono">DB_PATH</span>.
          </p>
        </div>
      ) : view.empty ? (
        !answered ? (
          <div class="pl-spinner" aria-label="Loading" />
        ) : (
          !error && (
            <div class="app-card app-placeholder-body">
              <p class="app-placeholder-lead">Nothing requested yet</p>
              <p class="app-placeholder-text">
                Albums you get show here while they download, and once they've arrived. Finding and getting
                albums is on the main page for now.
              </p>
            </div>
          )
        )
      ) : (
        SECTIONS.map((section) => {
          const rows = view.sections[section]
          if (!rows.length) return null
          return (
            <section key={section} class="app-requests-section" aria-labelledby={`app-requests-${section}`}>
              <h2 id={`app-requests-${section}`} class="app-section-title">
                {SECTION_TITLES[section]}
              </h2>
              <ul class={section === 'done' ? 'app-done-list' : 'app-jobs'}>
                {rows.map((row) => (
                  <li key={row.key} data-row={row.key} tabIndex={-1}>
                    {card(section, row)}
                  </li>
                ))}
              </ul>
            </section>
          )
        })
      )}
    </section>
  )
}

const message = (caught: unknown) => (caught instanceof Error ? caught.message : String(caught))
