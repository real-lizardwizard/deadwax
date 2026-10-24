import { useRef, useState } from 'preact/hooks'

import type { StoreStatus } from '../lib/candidates'
import { ADDED_WORDS } from '../lib/myLibrary'
import { withoutJoin } from '../lib/perPerson'
import { errorNote } from './ErrorNote'

/**
 * What the library and the downloads already have of a pressing (step 2's store, 2.0.0-player.7),
 * in the app's look (2.0.0-player.15): the main page's candidates panel drew these as
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
 * ADD (2.0.0-player.51, personal libraries): a pressing the store holds that isn't in your library
 * (storeStatusFor's `add`) has "Add to my library" under its words (AddToLibrary, below), when the page
 * gives an `onAdd` - which asks the store again afterwards, and the line becomes "Already in your library".
 *
 * A path is a stranger's folder name as often as not, so every line breaks anywhere rather than
 * push a phone's screen sideways. A leaf: props only.
 */
export function StoreState({
  status,
  notes,
  onJoin,
  onAdd,
}: {
  status: StoreStatus | null
  notes: readonly string[]
  /** join the download this status is about; resolves once deadwax has it, rejects with its words */
  onJoin?: (jobId: number) => Promise<unknown>
  /** add the pressing this status is about to your library (2.0.0-player.51); resolves once deadwax has it */
  onAdd?: () => Promise<unknown>
}) {
  if (!status && !notes.length) return null
  //? (2.0.0-player.65) no Join to draw - someone without Get albums: no "Join it" either (withoutJoin)
  if (status && !onJoin) status = withoutJoin(status)
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
          {status.add && onAdd && <AddToLibrary key={status.lines[0] ?? ''} onAdd={onAdd} />}
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
 * or nothing does. (Shared with the main page's box until it retired in 2.0.0-player.66.)
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
  const [refused, setRefused] = useState<unknown>(null)
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
        setRefused(caught)
      },
    )
  }

  if (state === 'joined') return <p class="app-store-line" role="status">Joined - it's in your Requests.</p>
  return (
    <>
      <button ref={button} type="button" class="app-button app-store-join" aria-disabled={state === 'joining'} onClick={join}>
        {state === 'joining' ? 'Joining…' : 'Join this download'}
      </button>
      {refused ? (
        <p class="app-store-line is-refused" role="alert">
          {errorNote(refused, { as: 'span' })}
        </p>
      ) : null}
    </>
  )
}

/**
 * "Add to my library" (2.0.0-player.51), under a pressing the store holds that isn't yours - as Join is:
 * the tap asks deadwax at once, the button waits (aria-disabled, so the focus on it stays), and gives way
 * to the added words, handing its focus to the box; a refusal is said under it, in an alert.
 */
export function AddToLibrary({ onAdd }: { onAdd: () => Promise<unknown> }) {
  const [state, setState] = useState<'idle' | 'adding' | 'added'>('idle')
  const [refused, setRefused] = useState<unknown>(null)
  const button = useRef<HTMLButtonElement | null>(null)

  const add = () => {
    if (state !== 'idle') return
    setState('adding')
    setRefused(null)
    onAdd().then(
      () => {
        keepJoinFocus(button.current, '.app-store-box')
        setState('added')
      },
      (caught: unknown) => {
        setState('idle')
        setRefused(caught)
      },
    )
  }

  if (state === 'added') return <p class="app-store-line" role="status">{ADDED_WORDS}</p>
  return (
    <>
      <button ref={button} type="button" class="app-button app-store-join" aria-disabled={state === 'adding'} onClick={add}>
        {state === 'adding' ? 'Adding…' : 'Add to my library'}
      </button>
      {refused ? (
        <p class="app-store-line is-refused" role="alert">
          {errorNote(refused, { as: 'span' })}
        </p>
      ) : null}
    </>
  )
}
