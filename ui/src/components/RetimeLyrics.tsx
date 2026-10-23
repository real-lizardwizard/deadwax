import { useEffect, useState } from 'preact/hooks'

import * as libraryApi from '../api/library'
import { latestOnly } from '../lib/latest'
import { describeRetime, type RetimeTotals } from '../lib/lyrics'
import { Loading } from './Loading'

/** A re-time run under way, or how the last one ended. */
interface RetimeRun extends RetimeTotals {
  total: number
  done: number
  running: boolean
  error?: string
}

/*
 * The run is kept in this module, not in the component (2.0.0-player.42), so it outlives what draws
 * it: the app's Server settings page goes whenever another page takes its place - and a run over a whole library takes minutes. Kept
 * here, it goes on and its Stop still works when you come back; one that ENDED while nothing drew it
 * says how it ended when you do.
 *
 * How a run ended is said once, though - not on every later visit: once it has been drawn ended, it is
 * let go as the last thing drawing it goes, so the settings tab left and come back to says the prompt
 * again, as it did when the run was the component's. And it is let go as soon as a new lead is typed:
 * "re-timed 29 tracks." was at the old lead, and still saying it once the new one is saved would read
 * as though the new lead had been applied. A lead typed WHILE it runs lets it go as it ends (`leadMoved`),
 * even once that lead has been saved: the server reads the lead as each album is asked for, so the albums
 * done before the save moved to the old lead and the rest to the new one - its words would say the job
 * was done when part of it was at a lead no longer saved. The prompt says what is true then.
 */
let run: RetimeRun | null = null
let stop = false
//? a new lead typed while the run went on (cleared as one starts): its words are let go as it ends
let leadMoved = false
const runs = latestOnly()
const listeners = new Set<() => void>()

function keep(next: RetimeRun | null): void {
  run = next
  for (const listener of [...listeners]) listener()
}

/** How a run ended - or nothing, when a new lead was typed while it ran (some of it may be at each). */
const ended = (last: RetimeRun): RetimeRun | null => (leadMoved ? null : last)

/** For the sims: forget the run, as a fresh page would. */
export function forgetRetime(): void {
  runs.supersede()
  stop = false
  leadMoved = false
  run = null
}

async function start(): Promise<void> {
  if (run?.running) return
  stop = false
  leadMoved = false
  const ticket = runs.begin()
  const totals = { retimed: 0, unchanged: 0, custom: 0, failed: 0 }
  keep({ ...totals, total: 0, done: 0, running: true })

  let albums
  try {
    //? a REAL scan, not the saved one: writing a .lrc drops that album from the saved scan so
    //? it is read again, so a snapshot taken after an earlier run is missing exactly the albums
    //? that run touched - measured, a second run covered 87 tracks of 104
    albums = (await libraryApi.listAlbums()).albums
      .filter((album) => album.lyrics_count > 0)
  } catch (caught) {
    if (ticket.current()) keep(ended({ ...totals, total: 0, done: 0, running: false, error: `couldn't read the library - ${String(caught)}` }))
    return
  }

  let done = 0
  for (const album of albums) {
    if (stop || !ticket.current()) break
    try {
      const summary = await libraryApi.fetchLyrics(album.path, { retime: true })
      totals.retimed += summary.retimed
      totals.unchanged += summary.unchanged
      totals.custom += summary.custom
      totals.failed += summary.failed
    } catch {
      totals.failed += album.lyrics_count
    }
    done += 1
    if (ticket.current()) keep({ ...totals, total: albums.length, done, running: true })
  }

  if (ticket.current()) keep(ended({ ...totals, total: albums.length, done, running: false }))
}

/**
 * Re-time the lyrics already saved to the lead that is saved now - beside LYRICS_LEAD_MS, on the main
 * page's settings tab and (2.0.0-player.42) on the app's Server settings page, Library.
 *
 * Lives beside LYRICS_LEAD_MS because that is the moment it is wanted: a new lead only applies
 * to lyrics fetched from then on, and the ones already on disk move only when asked. It walks
 * the library one album at a time through the same route the library's Get lyrics uses, so it
 * can be watched and stopped, and the server rewrites only files that are still exactly
 * LRCLIB's lyrics - running it twice, or after changing the lead again, is safe.
 *
 * Refused while the lead has an unsaved edit. It re-times to the SAVED lead, and running it with
 * a different number sitting in the box would do something other than what the screen says.
 */
export function RetimeLyrics({ unsaved }: { unsaved: boolean }) {
  const [, redraw] = useState(0)
  useEffect(() => {
    const listener = () => redraw((count) => count + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
      //? the last thing drawing it gone: an ended run has been said, and the next visit says the prompt
      if (!listeners.size && run && !run.running) run = null
    }
  }, [])
  //? a new lead typed: an ended run was at the old one ("Save the new lead first." stands meanwhile) -
  //? and a running one is let go as it ends, saved or not by then (some of it at each lead)
  useEffect(() => {
    if (!unsaved || !run) return
    if (run.running) leadMoved = true
    else run = null
  })

  return (
    <div class="settings-retime">
      {run?.running ? (
        <button type="button" class="win-button is-running" onClick={() => { stop = true }}>
          <Loading label={run.total ? `re-timing ${run.done}/${run.total} albums · stop` : 'reading the library'} />
        </button>
      ) : (
        <button
          type="button"
          class="win-button"
          disabled={unsaved}
          title={unsaved
            ? 'Save the new lead first - this re-times to the lead that is saved'
            : 'Move the timings of lyrics already saved to the lead above. Only files that are '
              + "still exactly LRCLIB's lyrics are touched."}
          onClick={() => void start()}
        >
          Re-time saved lyrics
        </button>
      )}

      <span class="settings-retime-note">
        {unsaved
          ? 'Save the new lead first.'
          : run?.error
            ? run.error
            : run && !run.running
              ? `${describeRetime(run)}${run.done < run.total ? ` (stopped at ${run.done} of ${run.total} albums)` : '.'}`
              : 'Lyrics saved before the lead changed keep their old timings until re-timed.'}
      </span>
    </div>
  )
}
