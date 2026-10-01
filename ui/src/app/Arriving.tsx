import type { RequestRow } from '../lib/requestsView'
import { ArrivingCard } from './JobCard'

/**
 * Home's Arriving (2.0.0-player.12): up to three downloads on their way, with "See all" going to
 * the Requests tab - and NOTHING AT ALL when nothing is (James: "is it possible to hide arriving
 * when there isn't anything arriving? ... I don't know that I want it to be persistent all the
 * time"). Not an empty section, not a heading with "nothing yet" under it: no section.
 *
 * What counts as arriving is what the Requests tab's badge counts (lib/requestsView.ts): queued,
 * downloading, being filed, being retried, or still asking slskd. App hands the cards in, already
 * cut to three (arrivingCards); a leaf, it reads no context.
 *
 * `trouble`: deadwax didn't answer the last look. The cards are the last answer, and say so - a bar
 * that has stopped must not pass for one still moving - while App keeps asking (stallsOn).
 */
export function Arriving({
  rows,
  onSeeAll,
  trouble = false,
}: {
  rows: readonly RequestRow[]
  onSeeAll: () => void
  trouble?: boolean
}) {
  if (!rows.length) return null

  return (
    <section class="app-section app-arriving" aria-labelledby="app-arriving-title">
      <div class="app-section-head app-arriving-head">
        <h2 id="app-arriving-title" class="app-section-title">
          Arriving
        </h2>
        <button type="button" class="app-text-button app-see-all" onClick={onSeeAll}>
          See all
        </button>
      </div>
      {trouble && (
        <p class="app-arriving-note">Can't reach deadwax just now: this is its last answer, and it keeps asking.</p>
      )}
      <ul class="app-jobs">
        {rows.map((row) => (
          <li key={row.key}>
            <ArrivingCard row={row} onOpen={onSeeAll} />
          </li>
        ))}
      </ul>
    </section>
  )
}
