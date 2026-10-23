import { useEffect, useState } from 'preact/hooks'

import { ApiError } from '../api/http'
import * as libraryApi from '../api/library'
import type { LibraryAlbum } from '../api/types'
import { runBulk, type BulkKind, type BulkOutcome, type BulkRun } from '../lib/bulkTargets'
import { latestOnly } from '../lib/latest'
import { announceAlbumsFiled } from '../lib/libraryEvents'

/**
 * The bulk runs of the app's Library care page (2.0.0-player.42), kept in this module for the page's
 * life - as the server settings' drafts and the log's lines are (app/ServerSettings.tsx, EventLog.tsx):
 * App draws only the page on top of each tab, so Library care goes whenever another page takes its
 * place - the sidebar's Log or Settings, Back, Go to album - and a run of a whole library takes
 * minutes. Kept here, a run goes on while you look at the Log, its Stop still works when you come
 * back, and each run's result stays on screen until the next of its kind, as the main page kept it.
 * The words typed to narrow the runs are kept with them.
 *
 * Each run is lib/bulkTargets.ts's runBulk over the albums the page hands it, one at a time, through
 * the route a single click uses (Get cover, Get CD art, Get lyrics - the same calls the Edit panel's
 * buttons make, as the main page's runs did): never a loop on the server. Each kind runs on its own, as
 * on the main page; one of a kind at a time (asked again while running, it does nothing), each through a
 * latestOnly() of its own so nothing from an older run is ever drawn over a newer one's. Once a run has
 * written anything the library's listeners are told (announceAlbumsFiled - the page's own scan, the
 * Edit panel's, Needs a look's and its count, the owned marks), once, at its end, as the main page
 * reloaded once at its end - and its kind is `behind`: the scan the page holds still lists what the run
 * just did as missing, so the page holds that kind's button back until a read of the library begun
 * after the run ended has landed (app/LibraryCare.tsx), rather than offer the same albums again.
 */

export interface CareState {
  /** each run under way, or the last one's result (null: none yet) */
  runs: Readonly<Record<BulkKind, BulkRun | null>>
  /** Stop pressed on a run still fetching its album */
  stopping: Readonly<Record<BulkKind, boolean>>
  /** the words typed to narrow the runs */
  narrow: string
  /** a run of that kind wrote something as it ended, and the library hasn't been read since */
  behind: Readonly<Record<BulkKind, boolean>>
}

const NONE: Readonly<Record<BulkKind, boolean>> = { covers: false, disc: false, lyrics: false }
const fresh = (): CareState => ({ runs: { covers: null, disc: null, lyrics: null }, stopping: NONE, narrow: '', behind: NONE })
let kept: CareState = fresh()
const tickets: Record<BulkKind, ReturnType<typeof latestOnly>> = { covers: latestOnly(), disc: latestOnly(), lyrics: latestOnly() }
const listeners = new Set<() => void>()

function keep(change: Partial<CareState>): void {
  kept = { ...kept, ...change }
  for (const listener of [...listeners]) listener()
}

/** A cover or CD art: written, none to find (a 404 - a fact about the release), or failed (worth
 *  another go) - told apart as the main page told them. */
const pictureStep = (route: (path: string) => Promise<unknown>) => async (album: LibraryAlbum): Promise<BulkOutcome> => {
  try {
    await route(album.path)
    return { written: 1 }
  } catch (caught) {
    return caught instanceof ApiError && caught.status === 404 ? { missing: 1 } : { failed: 1 }
  }
}

/** Each album's step: the route a single click uses. Lyrics are counted in TRACKS - a lookup that
 *  failed outright counts every track of the album failed (runBulk's `failedAs`). */
const STEPS: Readonly<Record<BulkKind, (album: LibraryAlbum) => Promise<BulkOutcome>>> = {
  covers: pictureStep((path) => libraryApi.fetchCoverArt(path)),
  disc: pictureStep((path) => libraryApi.fetchDiscArt(path)),
  lyrics: async (album) => {
    const summary = await libraryApi.fetchLyrics(album.path)
    return { written: summary.written + summary.replaced, missing: summary.missing + summary.instrumental, failed: summary.failed }
  },
}

/** The runs and the narrowing, as they stand. */
export function libraryCareNow(): CareState {
  return kept
}

/** Start a run of `kind` over `targets` (the albums it takes, worked out by the page as it is
 *  pressed). Nothing while one of that kind is running. */
export async function startBulk(kind: BulkKind, targets: readonly LibraryAlbum[]): Promise<void> {
  if (kept.runs[kind]?.running || !targets.length) return
  const ticket = tickets[kind].begin()
  keep({ stopping: { ...kept.stopping, [kind]: false } })
  const run = await runBulk(
    targets,
    STEPS[kind],
    (now) => {
      if (!ticket.current()) return
      if (now.running) keep({ runs: { ...kept.runs, [kind]: now } })
      //? as it ends, in the same telling: Stop let go, and - had it written anything - its kind behind
      //? the disk, so the page never draws its button over the albums it just did
      else {
        keep({
          runs: { ...kept.runs, [kind]: now },
          stopping: { ...kept.stopping, [kind]: false },
          behind: now.written > 0 ? { ...kept.behind, [kind]: true } : kept.behind,
        })
      }
    },
    () => kept.stopping[kind] || !ticket.current(),
    kind === 'lyrics' ? (album) => album.track_count : undefined,
  )
  //? one telling at the end rather than per album: each write already dropped its folder from the
  //? server's scan cache, so one scan picks up every change
  if (run.written > 0) announceAlbumsFiled()
}

/** The library read again since those kinds' runs ended (the page says so): their buttons back, over
 *  albums that know what the runs did. */
export function caughtUp(kinds: readonly BulkKind[]): void {
  if (!kinds.some((kind) => kept.behind[kind])) return
  const behind = { ...kept.behind }
  for (const kind of kinds) behind[kind] = false
  keep({ behind })
}

/** Stop the run of `kind` after the album being fetched. */
export function stopBulk(kind: BulkKind): void {
  if (kept.runs[kind]?.running && !kept.stopping[kind]) keep({ stopping: { ...kept.stopping, [kind]: true } })
}

/** The words that narrow the runs. */
export function setCareNarrow(narrow: string): void {
  if (narrow !== kept.narrow) keep({ narrow })
}

/** For the sims: forget it all, as a fresh page would. */
export function forgetLibraryCare(): void {
  for (const kind of Object.keys(tickets) as BulkKind[]) tickets[kind].supersede()
  kept = fresh()
}

/** The runs and the narrowing, re-rendering as they move. */
export function useLibraryCare(): CareState {
  const [, redraw] = useState(0)
  useEffect(() => {
    const listener = () => redraw((count) => count + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
  return kept
}
