import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'

import { useLibrary } from '../hooks/useLibrary'
import { BULK_KINDS, bulkSummary, bulkTargets, type BulkKind } from '../lib/bulkTargets'
import {
  BULK_LABELS, BULK_TITLES, CARE_LINE, RESCAN_WORDS, narrowAlbums, planWords, scanAge, scanTotals, scopeLine,
} from '../lib/libraryCare'
import { MANAGING_ADMINS_ONLY } from '../lib/appRoutes'
import { announceAlbumsFiled } from '../lib/libraryEvents'
import { ChevronLeftIcon } from '../player/icons'
import { caughtUp, libraryCareNow, setCareNarrow, startBulk, stopBulk, useLibraryCare } from './useLibraryCare'

/** Focus fell to the page (or was never taken) - the only time this page moves it. */
const focusLost = (): boolean => {
  if (typeof document === 'undefined') return false
  const active = document.activeElement
  return !active || active === document.body
}

/**
 * Library care (2.0.0-player.42): looking after the library in the app (a phone's too since 2.0.0-player.47) - what the main
 * page's Library tab toolbar does beyond the review queue (which is Needs a look). There is no board
 * for it; it is built from STYLE.md and the Managing pages' parts. Pushed on You (`#/you/care/library`),
 * a sibling of Needs a look, Settings and Log (App's openManagingPage).
 *
 *  - RESCAN: the scan that ignores the cache (useLibrary's reload(true), POST /library/rescan), with
 *    what the scan holds and how old it is, said as the main page's status bar says them - and what it
 *    is for: deadwax notices a changed album by its folder's date, which a retag by another program
 *    doesn't move. The library's listeners are told once it has answered (the count, the owned marks,
 *    the Edit panel's and Needs a look's scans).
 *  - THE BULK RUNS: Get covers · N, Get CD art · N, Get lyrics · N - the main page's three, over the
 *    same rules (lib/bulkTargets.ts), driven from the client one album at a time through the routes a
 *    single click uses, each with Stop and the main page's words for what it did (no cover on the
 *    Archive told apart from a request that failed; lyrics in tracks). Over the whole library, or the
 *    albums a few typed words narrow it to (artist, album, edition or folder) - and each says what it
 *    will act on before it starts. Offered only once a REAL scan is in: the saved one can be behind.
 *    The runs are app/useLibraryCare.ts's, kept for the page's life, so a run goes on while another
 *    page shows and each one's result stays on screen until the next of its kind. A run that wrote
 *    something leaves its kind behind the disk: the library is read again at once, and that kind's
 *    button waits for that read - never drawn again over the albums the run just did.
 *
 * The library through the main page's own hook (hooks/useLibrary.ts: the saved scan drawn at once, a
 * real scan underneath), read only once the page first shows - and again, quietly, as it shows again
 * later with nothing under way. A control that goes as a run ends hands focus to what
 * the run says, never to the page.
 *
 * ON A PHONE TOO (2.0.0-player.47): the same page and the same runs, laid out for a phone by app.css.
 * Someone deadwax says isn't its admin gets a short note instead, asking nothing.
 */
export function LibraryCare({
  admin,
  live,
  onBack,
  backLabel,
}: {
  /** deadwax's admin is the one looking (everyone, with logins off) - on either frame since 2.0.0-player.47 */
  admin: boolean
  /** this page is what shows - its tab current, the app in front, nothing over it */
  live: boolean
  onBack: () => void
  backLabel: string
}) {
  //? read only once it shows - for anyone but the admin, nothing is asked at all
  const library = useLibrary(admin && live)
  const care = useLibraryCare()
  const [rescanning, setRescanning] = useState(false)
  //? the run whose button has focus: should the button go (the run ended with nothing left to fetch),
  //? focus goes to what the run says - never to the page
  const focusedRun = useRef<BulkKind | null>(null)
  const runButtons = useRef<Partial<Record<BulkKind, HTMLButtonElement | null>>>({})
  const runWords = useRef<Partial<Record<BulkKind, HTMLParagraphElement | null>>>({})

  //? shown again after the first time, with nothing under way: the library read again underneath
  const wasLive = useRef(live)
  useEffect(() => {
    if (admin && live && !wasLive.current && library.loaded && !library.loading) void library.reload(false)
    wasLive.current = live
  }, [live])

  //? a run that wrote something leaves its kind behind the disk (the store says so as it ends): the
  //? scan in hand still lists what it just did as missing, and pressing its button again would ask for
  //? all of it again. So the library is read again at once, as the main page reads it after a run, and
  //? that kind's button is held back until a read begun after the run ended has landed - each write
  //? dropped its folder from the server's cache, so that read lists the albums as they are now. A page
  //? drawn fresh begins every read after a run that ended while it was away: nothing is behind for it.
  useEffect(() => {
    caughtUp(BULK_KINDS)
  }, [])
  const catchUp = useRef<{ kinds: BulkKind[]; answered: boolean } | null>(null)
  const [, caughtUpDrawn] = useState(0)
  useEffect(() => {
    if (!admin || !live || !library.loaded || library.problem) return
    const pending = catchUp.current
    if (pending) {
      //? answered, and no newer read still out (useLibrary draws only the newest): what is in hand was
      //? read after the run ended
      if (pending.answered && !library.loading) {
        catchUp.current = null
        caughtUp(pending.kinds)
      }
      return
    }
    const kinds = BULK_KINDS.filter((kind) => libraryCareNow().behind[kind])
    if (!kinds.length) return
    const mine = { kinds, answered: false }
    catchUp.current = mine
    void library.reload(false).then(() => {
      mine.answered = true
      caughtUpDrawn((count) => count + 1)
    })
  })

  //? a run's button gone with focus on it (the run ended, nothing left to fetch): focus to its words
  useLayoutEffect(() => {
    const kind = focusedRun.current
    if (!kind || runButtons.current[kind]?.isConnected || !focusLost()) return
    focusedRun.current = null
    runWords.current[kind]?.focus({ preventScroll: true })
  })
  //? focus moved on from a run's button that is still there: nothing to hand on. Asked once this turn is
  //? over: Chromium blurs a focused button AS it is removed, while it is still in the page - that is the
  //? button going, which the layout effect above (run in the same commit) hands on, not focus moving on
  const leftRun = (kind: BulkKind) => (event: FocusEvent) => {
    const button = event.currentTarget as HTMLElement
    void Promise.resolve().then(() => {
      if (focusedRun.current === kind && button.isConnected) focusedRun.current = null
    })
  }

  const header = (
    <>
      <header class="pl-nav-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
      </header>
      <header class="pl-large-header">
        <h1 class="pl-large-title">Library care</h1>
      </header>
    </>
  )

  if (!admin) {
    return (
      <section class="app-care is-refused app-needs">
        {header}
        <div class="app-card app-placeholder-body">
          <p class="app-placeholder-text">{MANAGING_ADMINS_ONLY}</p>
        </div>
      </section>
    )
  }

  const real = library.loaded && !library.stale
  //? Rescan refused while ours is out, or a plain read over a real scan is - and offered while the saved
  //? scan is on screen with the first real one under way, as the main page offers it (useLibrary draws
  //? only the newest answer, so the rescan simply wins)
  const scanBusy = rescanning || (library.loading && !library.stale)
  const rescan = () => {
    if (scanBusy || library.problem) return
    setRescanning(true)
    void library.reload(true).then((albums) => {
      setRescanning(false)
      //? what another program changed may move the count, the owned marks, an open editor's album
      if (albums.length) announceAlbumsFiled()
    })
  }
  const retry = () => {
    if (!library.loading) void library.reload(false)
  }

  const inScope = narrowAlbums(library.albums, care.narrow)

  return (
    <section class="app-care">
      {header}
      <div class="app-care-body">
        <p class="app-care-line">{CARE_LINE}</p>

        {library.problem ? (
          <p class="app-care-state">{library.problem}</p>
        ) : !library.loaded ? (
          <div class="pl-spinner" aria-label="Reading the library" />
        ) : library.error && !library.albums.length ? (
          <div class="app-care-state">
            <p>deadwax couldn't read the library: {library.error}</p>
            <button type="button" class="app-button" aria-disabled={library.loading ? 'true' : undefined} onClick={retry}>
              Try again
            </button>
          </div>
        ) : (
          <>
            <section class="app-care-section" aria-labelledby="app-care-rescan">
              <div class="app-care-head">
                <h2 id="app-care-rescan" class="app-care-title">Rescan</h2>
                <button
                  type="button"
                  class="app-button app-care-button"
                  aria-disabled={scanBusy ? 'true' : undefined}
                  title="Re-read every file, ignoring the cache - for when something changed that deadwax couldn't see, like a retag by another program"
                  onClick={rescan}
                >
                  {rescanning ? 'Rescanning…' : 'Rescan'}
                </button>
              </div>
              <p class="app-care-facts" role="status">
                {[scanTotals(library.albums), scanAge(library, rescanning)].filter(Boolean).join(' · ')}
              </p>
              {library.error && (
                <p class="app-care-problem">
                  Couldn't read the library just now: {library.error}{' '}
                  <button type="button" class="app-text-button" aria-disabled={library.loading ? 'true' : undefined} onClick={retry}>
                    Try again
                  </button>
                </p>
              )}
              <p class="app-care-note">{RESCAN_WORDS}</p>
            </section>

            <section class="app-care-section" aria-labelledby="app-care-runs">
              <h2 id="app-care-runs" class="app-care-title">Covers, CD art and lyrics</h2>
              <label class="app-care-narrow">
                <span class="app-care-label">Narrow to</span>
                <input
                  class="app-care-input"
                  type="search"
                  value={care.narrow}
                  placeholder="Artist, album or folder"
                  spellcheck={false}
                  autoComplete="off"
                  onInput={(event) => setCareNarrow((event.currentTarget as HTMLInputElement).value)}
                />
              </label>
              <p class="app-care-note">
                {real ? scopeLine(inScope.length, library.albums.length, care.narrow) : 'Checking the library…'}
              </p>

              {BULK_KINDS.map((kind) => {
                const run = care.runs[kind]
                const stopping = care.stopping[kind]
                //? only from a real scan (the saved one can be behind what is on disk), and not while a run of
                //? this kind that wrote is newer than the scan in hand
                const targets = real && !care.behind[kind] ? bulkTargets(kind, inScope) : null
                return (
                  <section key={kind} class="app-care-run" aria-labelledby={`app-care-${kind}`}>
                    <div class="app-care-head">
                      <h3 id={`app-care-${kind}`} class="app-care-heading">{BULK_TITLES[kind]}</h3>
                      {run?.running ? (
                        <button
                          type="button"
                          class="app-button app-care-button is-running"
                          aria-disabled={stopping ? 'true' : undefined}
                          title="Stop after the album being fetched"
                          ref={(element) => { runButtons.current[kind] = element }}
                          onFocus={() => { focusedRun.current = kind }}
                          onBlur={leftRun(kind)}
                          onClick={() => stopBulk(kind)}
                        >
                          <span class="app-care-spin" aria-hidden="true" />
                          {stopping ? `Stopping after ${run.done + 1} of ${run.total}` : `Stop · ${run.done} of ${run.total}`}
                        </button>
                      ) : targets && targets.length > 0 ? (
                        <button
                          type="button"
                          class="app-button app-care-button"
                          ref={(element) => { runButtons.current[kind] = element }}
                          onFocus={() => { focusedRun.current = kind }}
                          onBlur={leftRun(kind)}
                          onClick={() => void startBulk(kind, targets)}
                        >
                          {BULK_LABELS[kind]} · {targets.length}
                        </button>
                      ) : null}
                    </div>
                    <p class="app-care-note">{targets ? planWords(kind, targets.length, care.narrow) : 'Checking the library…'}</p>
                    {/* always there: what the last run did, said as it ends and kept until the next */}
                    <p
                      ref={(element) => { runWords.current[kind] = element }}
                      class="app-care-result"
                      role="status"
                      tabIndex={-1}
                    >
                      {run && !run.running ? bulkSummary(kind, run) : ''}
                    </p>
                  </section>
                )
              })}
            </section>
          </>
        )}
      </div>
    </section>
  )
}
