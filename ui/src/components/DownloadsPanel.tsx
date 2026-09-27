import { useEffect, useRef, useState } from 'preact/hooks'

import { bridge } from '../bridge'
import { useDismiss } from '../hooks/useDismiss'
import { useDownloadJobs } from '../hooks/useDownloadJobs'
import type { PendingDownload } from '../lib/downloadOverlay'
import { handleDownloadRequests } from '../lib/downloadRequests'
import { DownloadJobRow } from './DownloadJobRow'

/**
 * The downloads dropdown, in full - toggle, badge, toolbar and list.
 *
 * This owns the whole `#downloads-control` subtree rather than just the list, because split
 * ownership between the vanilla app and this bundle would mean two things toggling the same
 * class. IDs and class names are unchanged so the existing CSS applies untouched.
 *
 * What this replaces: `renderDownloads()` and its 81 lines of `data-job-id` lookup,
 * `insertBefore` and `seen`-set pruning - a hand-written keyed reconciler. `key={job.id}`
 * below is the entire replacement, and it is also what fixes the flicker and lost text
 * selection the manual version was written to avoid in the first place.
 */
export function DownloadsPanel() {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  const {
    jobs,
    trackingEnabled,
    speeds,
    activeCount,
    finishedCount,
    error,
    cancelling,
    pending,
    retrying,
    retryProblems,
    retry,
    refresh,
    enqueue,
    cancel,
    clearFinished,
  } = useDownloadJobs(open)

  // let the vanilla app poke us after it enqueues something
  useEffect(() => {
    const shared = bridge()
    shared.refreshDownloads = refresh

    return () => {
      delete shared.refreshDownloads
    }
  }, [refresh])

  // and take every download request, so the row appears on the click rather than once slskd
  // has connected to the peer (lib/downloadRequests.ts)
  useEffect(() => handleDownloadRequests(enqueue), [enqueue])

  // and shut us when the log opens - only one dropdown at a time, in both directions
  useEffect(() => {
    const shared = bridge()
    shared.closeDownloads = () => setOpen(false)

    return () => {
      delete shared.closeDownloads
    }
  }, [])

  useEffect(() => {
    if (error) console.error(`Downloads refresh error: ${error}`)
  }, [error])

  //? a press that began inside and was released outside doesn't count - see useDismiss
  useDismiss(rootRef, open, () => setOpen(false), { escape: true })

  const toggle = (event: MouseEvent) => {
    // without this the document listener above sees the same click and closes it again
    event.stopPropagation()

    const next = !open
    setOpen(next)

    // only one dropdown open at a time
    if (next) bridge().closeOtherDropdowns?.()

    // no explicit refresh here: `open` is a dependency of the polling effect, so changing it
    // already re-runs the effect and polls immediately
  }

  const onClear = (event: MouseEvent) => {
    event.stopPropagation()
    void clearFinished().catch((caught: unknown) => {
      console.error(`Clear jobs error: ${caught instanceof Error ? caught.message : caught}`)
    })
  }

  return (
    <div id="downloads-control" class={open ? 'open' : undefined} ref={rootRef}>
      <button type="button" id="downloads-toggle-button" onClick={toggle}>
        <span>Downloads ▾</span>
        {/*
          Not rendered at all when idle, rather than rendered with `hidden`. The vanilla
          version set `.hidden = true` and the badge stayed on screen showing "0", because
          `.log-unread-badge` sets `display: flex` and that beats the browser's `[hidden]`
          rule. main.css now forces `[hidden]` to win, but not depending on the attribute in
          the first place is the sturdier answer.
        */}
        {activeCount > 0 && (
          <span id="downloads-active-badge" class="log-unread-badge">
            {activeCount}
          </span>
        )}
      </button>

      <div id="downloads-window">
        <div id="downloads-toolbar">
          <span id="downloads-summary" class="text default-muted">
            {jobs.length ? `${activeCount} active · ${finishedCount} finished` : ''}
          </span>
          <button
            type="button"
            id="downloads-clear-button"
            disabled={finishedCount === 0}
            onClick={onClear}
          >
            Clear finished
          </button>
        </div>

        <div class="scrollable" id="downloads-scrollable">
          <DownloadsList
            jobs={jobs}
            pending={pending}
            retrying={retrying}
            retryProblems={retryProblems}
            onRetry={retry}
            trackingEnabled={trackingEnabled}
            speeds={speeds}
            cancelling={cancelling}
            onCancel={cancel}
          />
        </div>
      </div>
    </div>
  )
}

interface ListProps {
  jobs: ReturnType<typeof useDownloadJobs>['jobs']
  pending: PendingDownload[]
  retrying: ReadonlySet<number>
  retryProblems: ReadonlyMap<number, string>
  onRetry: (jobId: number) => Promise<void>
  trackingEnabled: boolean
  speeds: Map<number, number>
  cancelling: ReadonlySet<number>
  onCancel: (jobId: number) => Promise<void>
}

function DownloadsList(
  { jobs, pending, retrying, retryProblems, onRetry, trackingEnabled, speeds, cancelling, onCancel }: ListProps,
) {
  // an unwritable database is not a broken app - downloads still work, they're just not
  // remembered - so this says which knob to turn rather than reading as a crash
  if (!trackingEnabled) {
    return (
      <h4 class="text red candidates-status">
        job tracking is off — the database path isn't writable, check DB_PATH
      </h4>
    )
  }

  if (!jobs.length && !pending.length) {
    return <h4 class="text default-muted candidates-status">Nothing downloaded yet</h4>
  }

  return (
    <>
      {pending.map((download) => <PendingDownloadRow key={download.key} download={download} />)}
      {jobs.map((job) => (
        <DownloadJobRow
          key={job.id}
          job={job}
          liveSpeed={speeds.get(job.id) ?? null}
          cancelling={cancelling.has(job.id)}
          onCancel={onCancel}
          retrying={retrying.has(job.id)}
          retryProblem={retryProblems.get(job.id) ?? null}
          onRetry={onRetry}
        />
      ))}
    </>
  )
}

/**
 * A download asked for that isn't a job yet - slskd is still connecting to the peer, or said
 * no. Same markup and classes as DownloadJobRow so it sits in the list as one of them; no
 * cancel button, since there is nothing in slskd to cancel until it answers.
 */
function PendingDownloadRow({ download }: { download: PendingDownload }) {
  const refused = download.error !== undefined
  return (
    <div class="download-job is-pending">
      <div class="download-job-head">
        <h4 class="text white download-job-title">
          {download.artist || 'unknown'} — {download.album || 'unknown'}
        </h4>
        <span class={`download-job-status ${refused ? 'bad' : 'mid'}`}>
          {refused ? 'refused' : 'asking slskd…'}
        </span>
      </div>

      <div class="download-job-meta">
        <span class="text default-secondary download-job-user">{download.username}</span>
        <span class="text default-muted">·</span>
        <span class={`download-job-detail text ${refused ? 'red' : 'default-muted'}`}>
          {refused ? download.error : 'connecting to the peer'}
        </span>
      </div>

      <div class={`download-progress-track${refused ? '' : ' is-waiting'}`}>
        <div class="download-progress-fill" style={{ width: '0%' }} />
      </div>
    </div>
  )
}
