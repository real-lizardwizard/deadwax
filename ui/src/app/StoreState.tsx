import { useRef, useState } from 'preact/hooks'

import type { StoreStatus } from '../lib/candidates'

/**
 * What the library and the downloads already have of a pressing (step 2's store, 2.0.0-player.7),
 * in the app's look (2.0.0-player.15): the main page's candidates panel draws these as
 * `.candidates-store` and `.candidates-notes`, and the app draws the same words - lib/candidates.ts
 * storeStatus and storeNotes, pinned by candidates.sim.cjs - as a card and a list of notes.
 *
 *  - On the album you don't have, under "Get the album" (where its answer, landing late, moves
 *    nothing a finger is reaching for): from POST /download/store_state, which searches nothing.
 *  - In the Sources sheet: a pressing held complete, or downloading whole, stands where the sources
 *    would (the server searched nothing); a part held, a part downloading, and other pressings held
 *    are notes above them.
 *
 * JOIN (2.0.0-player.49, downloads per person): a download somebody else asked for (lib/perPerson.ts
 * storeStatusFor's `joinJobId`) has "Join this download" under its words (JoinDownload, below), when
 * the page gives an `onJoin`. What a join leads to is the page's: the Sources sheet hands over to
 * Requests, as a Get does; the album page asks the store again, and the line becomes yours.
 *
 * A path is a stranger's folder name as often as not, so every line breaks anywhere rather than
 * push a phone's screen sideways. A leaf: props only.
 */
export function StoreState({
  status,
  notes,
  onJoin,
}: {
  status: StoreStatus | null
  notes: readonly string[]
  /** join the download this status is about; resolves once deadwax has it, rejects with its words */
  onJoin?: (jobId: number) => Promise<unknown>
}) {
  if (!status && !notes.length) return null
  return (
    <div class="app-store">
      {status && (
        //? a focus target (tabIndex -1): Join hands its focus here as it gives way (JoinDownload)
        <div class={`app-card app-store-box is-${status.kind}`} tabIndex={-1}>
          <p class="app-store-title">{status.title}</p>
          {status.lines.map((line, index) => (
            //? the folders (or the peer) first; the last line is the detail under them
            <p key={index} class={`app-store-line${index && index === status.lines.length - 1 ? ' is-detail' : ''}`}>
              {line}
            </p>
          ))}
          {status.joinJobId !== undefined && onJoin && <JoinDownload key={status.joinJobId} jobId={status.joinJobId} onJoin={onJoin} />}
        </div>
      )}
      {notes.length > 0 && (
        <ul class="app-store-notes">
          {notes.map((note, index) => (
            <li key={index} class="app-store-note">
              {note}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/**
 * Where the focus a Join button had goes as the button gives way: the store box around it, which a
 * page keeps drawn through its next look (the album page's line becoming yours) - never the page
 * itself, where a keyboard or VoiceOver would start again from the top. Only when the button has it,
 * or nothing does. Shared with the main page's box (components/StoreStatusBox.tsx).
 */
export function keepJoinFocus(button: HTMLElement | null, box: string): void {
  if (typeof document === 'undefined' || !button) return
  const active = document.activeElement
  if (active && active !== document.body && active !== button) return
  button.closest<HTMLElement>(box)?.focus({ preventScroll: true })
}

/**
 * "Join this download" (2.0.0-player.49), under a download somebody else asked for - its own component,
 * keyed on the download, so StoreState stays a leaf and another download's Join starts afresh. The tap
 * asks deadwax at once; while it is out the button waits (aria-disabled, so the focus on it stays);
 * once deadwax has it the button gives way to "Joined - it's in your Requests." (until the page's next
 * look says it's yours), handing its focus to the box (keepJoinFocus); a refusal is said under it, in
 * an alert, and the button is there to try again.
 */
export function JoinDownload({ jobId, onJoin }: { jobId: number; onJoin: (jobId: number) => Promise<unknown> }) {
  const [state, setState] = useState<'idle' | 'joining' | 'joined'>('idle')
  const [refused, setRefused] = useState<string | null>(null)
  const button = useRef<HTMLButtonElement | null>(null)

  const join = () => {
    if (state !== 'idle') return
    setState('joining')
    setRefused(null)
    onJoin(jobId).then(
      () => {
        keepJoinFocus(button.current, '.app-store-box')
        setState('joined')
      },
      (caught: unknown) => {
        setState('idle')
        setRefused(caught instanceof Error ? caught.message : String(caught))
      },
    )
  }

  if (state === 'joined') return <p class="app-store-line" role="status">Joined - it's in your Requests.</p>
  return (
    <>
      <button ref={button} type="button" class="app-button app-store-join" aria-disabled={state === 'joining'} onClick={join}>
        {state === 'joining' ? 'Joining…' : 'Join this download'}
      </button>
      {refused && (
        <p class="app-store-line is-refused" role="alert">
          {refused}
        </p>
      )}
    </>
  )
}
