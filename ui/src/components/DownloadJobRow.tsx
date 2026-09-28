import { readPreferences } from '../state/persisted'

import type { DownloadJob } from '../api/types'
import { JOB_STATUS_CLASS, isActive, jobDetailClass, jobDetailText } from '../lib/jobs'

interface Props {
  job: DownloadJob
  /** Derived rate from the byte deltas, or null when it isn't measurable yet. */
  liveSpeed: number | null
  /**
   * This job's cancel has been asked for and the server hasn't confirmed it yet.
   *
   * Owned by useDownloadJobs rather than by local state here, so one fact drives the row,
   * the toolbar summary and the toggle badge together. As local state it moved the button
   * and nothing else, which is why cancelling used to look like nothing had happened.
   */
  cancelling: boolean
  onCancel: (jobId: number) => Promise<void>
  /**
   * Being started again, until a poll shows it going: on the next peer (v0.9.12), or asking the
   * same one again (v1.0.7). null when neither.
   */
  retrying: 'next' | 'same' | null
  /** Why the last retry didn't start it, or null. */
  retryProblem: string | null
  onRetry: (jobId: number, samePeer?: boolean) => Promise<void>
}

/**
 * One download.
 *
 * Markup and class names match the vanilla renderer exactly - the 2,245 lines of CSS in
 * interface/styles/main.css are unchanged by this migration on purpose, so that a visual
 * difference means a porting mistake rather than a restyle. Restyling is a separate pass.
 *
 * One thing deliberately NOT carried over: the vanilla renderer toggled a `queued` class on
 * this element when the job was organized. Nothing styles `.download-job.queued` - the only
 * rule is `.candidate-box.queued` - so it was dead.
 */
export function DownloadJobRow({ job, liveSpeed, cancelling, onCancel, retrying, retryProblem, onRetry }: Props) {
  const statusClass = JOB_STATUS_CLASS[job.status] ?? ''
  //? a failed or cancelled download with runners-up left can move to the next of them
  //? a failed or cancelled download can always ask its peer again, and move to the next peer
  //? when it has runners-up left
  const stopped = job.status === 'failed' || job.status === 'cancelled'
  const canRetry = stopped && (job.alternatives_left ?? 0) > 0
  const percent = Math.round(job.progress || 0)

  const cancel = async (event: MouseEvent) => {
    event.stopPropagation()

    /*
     * Cancelling is not quite reversible: with SLSKD_INCOMPLETE_PATH configured it also
     * deletes the partial file, and either way you lose your place in that peer's queue,
     * which on Soulseek can be the expensive part. Off by default would be the wrong
     * default, so this asks unless you have turned it off in settings.
     *
     * Read at click time, not at render: the preference can change in another tab while a
     * transfer is running, and the value that matters is the one in force when you click.
     */
    if (readPreferences().confirmCancel) {
      const label = [job.artist, job.album].filter(Boolean).join(' — ') || 'this download'
      if (!confirm(`Cancel ${label}?\n\nYou'll lose your place in this peer's queue.`)) return
    }

    try {
      //? The optimistic state is set inside this call, before the request goes out, so the
      //? row changes on the click rather than on the response. Rollback lives there too.
      await onCancel(job.id)
    } catch (error) {
      console.error(`Cancel error: ${error instanceof Error ? error.message : error}`)
    }
  }

  return (
    <div class={`download-job${cancelling ? ' is-cancelling' : ''}`}>
      <div class="download-job-head">
        <h4 class="text white download-job-title">
          {job.artist || 'unknown'} — {job.album || 'unknown'}
        </h4>

        {/*
          While a cancel is in flight the row says so instead of continuing to report the
          status it is in the middle of leaving. Showing "downloading" for the two round-trips
          a cancel takes is what made the button feel like it did nothing.
        */}
        <span class={`download-job-status ${cancelling || retrying ? 'mid' : statusClass}`}>
          {cancelling ? 'cancelling…' : retrying === 'same' ? 'asking again…'
            : retrying ? 'trying next peer…' : job.status}
        </span>

        {/*
          One group, so the two move together: on a narrow panel they wrap to a line of their own
          at the right rather than squeezing the album's name to nothing.
        */}
        {stopped && !retrying && (
          <span class="download-job-retries">
          <button
            type="button"
            class="download-retry-button"
            title={`Ask ${job.username} for it again. Files that already arrived aren't downloaded twice, `
              + `and slskd can pick a partly downloaded file up where it stopped.`}
            onClick={(event) => { event.stopPropagation(); void onRetry(job.id, true) }}
          >
            ↻ retry
          </button>
          {canRetry && (
            <button
              type="button"
              class="download-retry-button"
              title={`Move this download to the next peer from the list you picked it from - `
                + `${job.alternatives_left} other peer${job.alternatives_left === 1 ? '' : 's'} left`}
              onClick={(event) => { event.stopPropagation(); void onRetry(job.id) }}
            >
              ↻ next peer
            </button>
          )}
          </span>
        )}

        {/* cancelling only means anything while something is still moving */}
        {isActive(job) && (
          <button
            type="button"
            class="download-cancel-button"
            title="Cancel this download"
            disabled={cancelling}
            onClick={cancel}
          >
            ✕
          </button>
        )}
      </div>

      <div class="download-job-meta">
        <span class="text default-secondary download-job-user">{job.username}</span>
        <span class="text default-muted">·</span>
        <span class={`download-job-detail text ${retryProblem ? 'red' : jobDetailClass(job)}`}>
          {retryProblem ?? jobDetailText(job, liveSpeed)}
        </span>
        {(job.attempt ?? 1) > 1 && (
          <span class="text default-muted" title="Moved to another peer after the one before failed">
            · try {job.attempt}
          </span>
        )}
      </div>

      <div class="download-progress-track">
        <div
          class={`download-progress-fill ${statusClass}`}
          style={{ width: `${percent}%` }}
        />
      </div>
    </div>
  )
}
