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
 * A path is a stranger's folder name as often as not, so every line breaks anywhere rather than
 * push a phone's screen sideways. A leaf: props only.
 */
export function StoreState({ status, notes }: { status: StoreStatus | null; notes: readonly string[] }) {
  if (!status && !notes.length) return null
  return (
    <div class="app-store">
      {status && (
        <div class={`app-card app-store-box is-${status.kind}`}>
          <p class="app-store-title">{status.title}</p>
          {status.lines.map((line, index) => (
            //? the folders (or the peer) first; the last line is the detail under them
            <p key={index} class={`app-store-line${index && index === status.lines.length - 1 ? ' is-detail' : ''}`}>
              {line}
            </p>
          ))}
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
