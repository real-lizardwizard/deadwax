import { useRef, useState } from 'preact/hooks'

import { addToMyLibrary } from '../api/me'
import type { FindCandidatesRequest } from '../api/types'
import { keepJoinFocus } from '../app/StoreState'
import type { StoreStatus } from '../lib/candidates'
import { joinDownload } from '../lib/downloadRequests'
import { ADDED_WORDS } from '../lib/myLibrary'
import { addedStatus } from '../lib/perPerson'

/**
 * What stands where the main page's candidates would, when Find didn't search (step 2): the pressing
 * is in your library complete, or downloading already. No Download - Downloads is where a download in
 * flight is cancelled, and a better copy replacing a held one is not built yet.
 *
 * Join (2.0.0-player.49), for a download somebody else asked for (`joinJobId` - lib/perPerson.ts
 * storeStatusFor): the tap asks deadwax at once (lib/downloadRequests.ts joinDownload, after which the
 * downloads panel asks again); while it is out the button waits, aria-disabled rather than disabled so
 * the focus on it stays; once deadwax has it the button gives way to "Joined - it's in Downloads.",
 * handing its focus to the box (keepJoinFocus); a refusal is said under it in an alert, with the button
 * back to try again. Its own file (it was CandidatesPanel's) so ui/test/sources.sim.cjs draws it.
 *
 * Add to my library (2.0.0-player.51), for a pressing the store holds whole that isn't in your library
 * (`add` - logins on): the same way, given the `release` the Find was for - "Added - it's in your
 * library, and deadwax stars it for you in Navidrome." The main page doesn't ask the store again, so once
 * added the box draws addedStatus - "Already in your library", the add note gone - as the Sources panel
 * does (review: it said "not in your library" above "Added").
 */
export function StoreStatusBox({ status: found, release }: { status: StoreStatus; release?: FindCandidatesRequest }) {
  const [join, setJoin] = useState<{ jobId: number; state: 'joining' | 'joined' | 'refused'; reason?: string } | null>(null)
  //? (2.0.0-player.51) Add to my library, for a pressing the store holds that isn't yours (status.add)
  const [adding, setAdding] = useState<{ state: 'adding' | 'added' | 'refused'; reason?: string } | null>(null)
  const addButton = useRef<HTMLButtonElement | null>(null)
  const status = adding?.state === 'added' ? addedStatus(found) : found
  const add = () => {
    if (!release || adding?.state === 'adding') return
    setAdding({ state: 'adding' })
    addToMyLibrary(release).then(
      () => {
        keepJoinFocus(addButton.current, '.candidates-store')
        setAdding({ state: 'added' })
      },
      (caught: unknown) => setAdding({ state: 'refused', reason: caught instanceof Error ? caught.message : String(caught) }),
    )
  }
  const button = useRef<HTMLButtonElement | null>(null)
  const jobId = status.joinJobId
  const mine = jobId !== undefined && join?.jobId === jobId ? join : null
  const ask = (id: number) => {
    if (mine?.state === 'joining') return
    setJoin({ jobId: id, state: 'joining' })
    joinDownload(id).then(
      () => {
        keepJoinFocus(button.current, '.candidates-store')
        setJoin({ jobId: id, state: 'joined' })
      },
      (caught: unknown) => setJoin({ jobId: id, state: 'refused', reason: caught instanceof Error ? caught.message : String(caught) }),
    )
  }
  return (
    //? a focus target (tabIndex -1): Join hands its focus here as it gives way
    <div class={`candidates-store is-${status.kind}`} tabIndex={-1}>
      <h4 class="text white candidates-store-title">{status.title}</h4>
      {status.lines.map((line, index) => (
        //? the folders (or the peer) first; the last line is the detail under them
        <p key={index} class={`text ${index && index === status.lines.length - 1 ? 'default-muted' : 'default-secondary'} candidates-store-line`}>
          {line}
        </p>
      ))}
      {jobId !== undefined && (mine?.state === 'joined' ? (
        <p class="text default-secondary candidates-store-line" role="status">Joined - it's in Downloads.</p>
      ) : (
        <button
          ref={button}
          type="button"
          class="candidate-download-button candidates-store-join"
          aria-disabled={mine?.state === 'joining'}
          onClick={() => ask(jobId)}
        >
          {mine?.state === 'joining' ? 'Joining…' : 'Join this download'}
        </button>
      ))}
      {mine?.state === 'refused' && <p class="text red candidates-store-line" role="alert">{mine.reason}</p>}
      {status.add && release && (adding?.state === 'added' ? (
        <p class="text default-secondary candidates-store-line" role="status">{ADDED_WORDS}</p>
      ) : (
        <button
          ref={addButton}
          type="button"
          class="candidate-download-button candidates-store-join"
          aria-disabled={adding?.state === 'adding'}
          onClick={add}
        >
          {adding?.state === 'adding' ? 'Adding…' : 'Add to my library'}
        </button>
      ))}
      {adding?.state === 'refused' && <p class="text red candidates-store-line" role="alert">{adding.reason}</p>}
    </div>
  )
}
