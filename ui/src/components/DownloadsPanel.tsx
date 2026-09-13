import { useEffect, useRef, useState } from 'preact/hooks'

import { bridge } from '../bridge'
import { useDownloadJobs } from '../hooks/useDownloadJobs'
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
    refresh,
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

  useEffect(() => {
    if (!open) return

    /*
      Where the press BEGAN, not just where it ended. A press inside the panel released outside
      it - a drag on the toolbar, a text selection run off the edge - fires its click on what
      the two have in common, which is outside, and used to close the panel. It never came up
      while the panel could be dragged, because the panel travelled with the pointer; now that
      it stays anchored, the pointer leaves it. Cleared on every click so a keyboard click,
      which has no press, is judged by its target alone.
    */
    let pressedInside = false

    const onPointerDown = (event: PointerEvent) => {
      pressedInside = rootRef.current?.contains(event.target as Node) ?? false
    }

    const onDocumentClick = (event: MouseEvent) => {
      const root = rootRef.current
      if (root && !pressedInside && !root.contains(event.target as Node)) setOpen(false)
      pressedInside = false
    }

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false)
    }

    document.addEventListener('pointerdown', onPointerDown, true)
    document.addEventListener('click', onDocumentClick)
    document.addEventListener('keydown', onKeyDown)

    return () => {
      document.removeEventListener('pointerdown', onPointerDown, true)
      document.removeEventListener('click', onDocumentClick)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [open])

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
  trackingEnabled: boolean
  speeds: Map<number, number>
  cancelling: ReadonlySet<number>
  onCancel: (jobId: number) => Promise<void>
}

function DownloadsList({ jobs, trackingEnabled, speeds, cancelling, onCancel }: ListProps) {
  // an unwritable database is not a broken app - downloads still work, they're just not
  // remembered - so this says which knob to turn rather than reading as a crash
  if (!trackingEnabled) {
    return (
      <h4 class="text red candidates-status">
        job tracking is off — the database path isn't writable, check DB_PATH
      </h4>
    )
  }

  if (!jobs.length) {
    return <h4 class="text default-muted candidates-status">Nothing downloaded yet</h4>
  }

  return (
    <>
      {jobs.map((job) => (
        <DownloadJobRow
          key={job.id}
          job={job}
          liveSpeed={speeds.get(job.id) ?? null}
          cancelling={cancelling.has(job.id)}
          onCancel={onCancel}
        />
      ))}
    </>
  )
}
