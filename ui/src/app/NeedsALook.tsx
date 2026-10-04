import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import * as libraryApi from '../api/library'
import type { LibraryAlbum } from '../api/types'
import { useLibrary } from '../hooks/useLibrary'
import { albumArtUrl } from '../lib/format'
import { isNewImport, issueLabel, outstandingIssues } from '../lib/metadataQueue'
import {
  MARK_WORDS, NEEDS_LOOK_LINE, NEEDS_LOOK_PHONE, facetAlbums, facetShown, facets, leavingAtEnd, rowChanged, startSession,
  stepTarget, summaryTotal,
  type Facet, type FolderChange, type LookSession, type RowMark,
} from '../lib/needsLook'
import { ChevronLeftIcon } from '../player/icons'
import type { FolderRequest } from './EditPanel'
import { askQueueSummary, setPageQueueCount } from './useQueueSummary'
import { takeOpener } from './useSheet'

/** A row as drawn: the album, the key it keeps for the session, what became of it. */
interface DrawnRow {
  key: string
  album: LibraryAlbum
  mark: RowMark | null
}

const asRows = (albums: readonly LibraryAlbum[]): DrawnRow[] => albums.map((album) => ({ key: album.path, album, mark: null }))
const sessionRows = (session: LookSession): DrawnRow[] => session.rows.map((row) => ({ key: row.listed.path, album: row.album, mark: row.mark }))

/** A session just ended: its rows and chips held on screen until a fresh scan has landed (`read`: the
 *  ending's own read has answered - the list is worked out again once no read is still out). */
interface Ending {
  rows: DrawnRow[]
  chips: Facet[]
  /** the facet its rows were narrowed by: the chip drawn pressed while they are held */
  facet: string | null
  read: boolean
}

/** Focus fell to the page (or was never taken) - the only time this page moves it. */
const focusLost = (): boolean => {
  if (typeof document === 'undefined') return false
  const active = document.activeElement
  return !active || active === document.body
}

/**
 * Needs a look (2.0.0-player.25): the review queue in the app, on a desktop - the main page's queue
 * (components/LibraryView.tsx's review, which is left as it is) with the app's Edit panel for its
 * editor. There is no board for this screen; it is built from STYLE.md and the desktop frame's parts.
 *
 * THE LIST is the main page's: lib/metadataQueue.ts's queueAlbums over the main page's own hook
 * (hooks/useLibrary.ts - the saved scan drawn at once, a real scan underneath), read only once this
 * page first shows (and again, quietly, as it shows again later), never at start-up. Facet chips
 * narrow it - All, Newly added, one per kind of issue (lib/needsLook.ts) - the facet in the address,
 * replaced as it is chosen, never a page of its own.
 *
 * A ROW opens the Edit panel on its FOLDER (App's openFolderEdit, the same side panel the album
 * page's Edit opens, by the frame's one-panel rule), with where the album sits in the queue - which
 * the release editor already knows how to show ("3 of 17", Previous, Next, Apply becoming Next). The
 * SESSION is the list as shown when the row was clicked, fixed (lib/needsLook.ts): nothing moves
 * while it lasts - an album fixed, ignored or deleted stays in its row saying which, followed by its
 * path through a rename - and stepping away from an album (Next, Previous, another row, the panel
 * closing, the page left) marks it reviewed, which is what clears a new import, and asks the count
 * again. An album gone when stepped to ends the session, as the main page's does. When the session
 * ends - the panel closes (App closes it as this page stops being on top), the facet changes, the
 * page goes - its rows stay until a fresh scan has landed, and the list is worked out again from it.
 *
 * Its count: while it shows with a REAL scan in hand, and no session, its All count stands in for the
 * server's (useQueueSummary.ts's setPageQueueCount) - one function over the same albums.
 *
 * On a PHONE it is a short note, asking nothing: no editor has a board there yet.
 */
export function NeedsALook({
  desktop,
  shown,
  facet,
  onFacet,
  onBack,
  backLabel,
  editing,
  onEdit,
  onCloseEdit,
}: {
  desktop: boolean
  /** its tab is the one showing, and the app is in front */
  shown: boolean
  /** the facet the address names (null: All) */
  facet: string | null
  onFacet: (facet: string | null) => void
  onBack: () => void
  backLabel: string
  /** the folder the Edit panel has open for this page, null while it is closed */
  editing: string | null
  /** open the Edit panel on a folder; `opener` the row it gives focus back to (undefined: as it was) */
  onEdit: (request: Omit<FolderRequest, 'key'>, opener: HTMLElement | null | undefined) => void
  onCloseEdit: () => void
}) {
  //? read only once it shows on a desktop - a phone asks nothing at all
  const library = useLibrary(desktop && shown)
  const real = library.loaded && !library.stale && !library.error

  const [session, setSession] = useState<LookSession | null>(null)
  //? read by the callbacks the panel's request carries, which outlive the render that made them
  const sessionNow = useRef(session)
  sessionNow.current = session
  const libraryNow = useRef(library)
  libraryNow.current = library
  //? the chips as the session began: nothing above the list moves while it lasts, either
  const [heldChips, setHeldChips] = useState<Facet[] | null>(null)
  //? read by end(), which the panel's callbacks reach from the render that began the session
  const heldNow = useRef(heldChips)
  heldNow.current = heldChips
  //? the session's rows, kept on screen while the fresh scan that ends it lands
  const [ending, setEnding] = useState<Ending | null>(null)
  //? the row a session ended on: focus goes back near it should the recompute take it away
  const endedAt = useRef<number | null>(null)
  //? a Try again pressed: focus kept in the page should the state it sat in go
  const retrying = useRef(false)
  const body = useRef<HTMLDivElement>(null)
  //? the panel has opened for this session: its closing after that ends it
  const opened = useRef(false)
  const [failedArt, setFailedArt] = useState<ReadonlySet<string>>(() => new Set())
  const list = useRef<HTMLUListElement>(null)

  const liveChips = useMemo(() => facets(library.albums, library.issueTypes), [library.albums, library.issueTypes])
  const libraryChips = useRef(liveChips)
  libraryChips.current = liveChips
  //? while a session lasts, and while its rows are held, the chips as it began
  const chips = session ? heldChips ?? liveChips : ending ? ending.chips : liveChips
  //? a facet that has emptied shows All
  const showing = session ? session.facet : facetShown(liveChips, facet)
  const albums = useMemo(() => facetAlbums(library.albums, showing), [library.albums, showing])

  /** Note that the album has been looked at - what clears a new import - and ask the count again.
   *  Settles (never rejects) once the note has been written, or has failed. */
  const review = (path: string | null): Promise<void> =>
    path ? libraryApi.markReviewed(path).then(() => askQueueSummary(), () => undefined) : Promise.resolve()

  /** The session over: the album left marked reviewed (unless already - `marked` is that note, from
   *  go()), its rows held until a fresh scan lands, and the list worked out again from it. The scan
   *  is asked for only once the note is written, or it could still count the album just left
   *  (2.0.0-player.25 review). */
  const end = (reviewLeaving: boolean, marked: Promise<void> = Promise.resolve()) => {
    const was = sessionNow.current
    if (!was) return
    const noted = reviewLeaving ? review(leavingAtEnd(was)) : marked
    sessionNow.current = null
    opened.current = false
    endedAt.current = was.index
    setSession(null)
    setEnding({ rows: sessionRows(was), chips: heldNow.current ?? libraryChips.current, facet: was.facet, read: false })
    void noted
      .then(() => libraryNow.current.reload(false))
      .then(() => setEnding((held) => (held ? { ...held, read: true } : held)))
  }

  /** The row element at `index`, for the panel to give focus back to. */
  const rowElement = (index: number): HTMLElement | null =>
    (list.current?.children[index]?.querySelector('button') as HTMLElement | null | undefined) ?? null

  /** What the panel says became of an album of this session: its row brought up to date, in place. */
  const heard = (change: FolderChange) => {
    const was = sessionNow.current
    if (!was) return
    const next = rowChanged(was, change)
    sessionNow.current = next
    setSession(next)
  }

  /** The panel's request for the session's current album. */
  const requestFor = (at: LookSession, reread: boolean): Omit<FolderRequest, 'key'> => ({
    folder: at.rows[at.index]!.path,
    reread,
    queue: {
      position: at.index + 1,
      total: at.rows.length,
      onNext: () => go((sessionNow.current?.index ?? 0) + 1),
      onPrevious: () => go((sessionNow.current?.index ?? 0) - 1),
    },
    onChange: heard,
  })

  /** From the current album to row `index` - Next, Previous, or another row clicked. */
  const go = (index: number, opener?: HTMLElement | null) => {
    const was = sessionNow.current
    if (!was) return
    const paths = new Set(libraryNow.current.albums.map((album) => album.path))
    const target = stepTarget(was, index, (path) => paths.has(path))
    if (target.kind === 'stay') return
    const marked = review(target.leaving)
    if (target.kind === 'end') {
      end(false, marked)
      onCloseEdit()
      return
    }
    sessionNow.current = target.session
    setSession(target.session)
    onEdit(requestFor(target.session, false), opener ?? rowElement(target.session.index))
  }

  /** A row clicked: the session begun on it - or, in one, that album stepped to (its own row again
   *  closes the panel, as Edit pressed again does). */
  const choose = (event: MouseEvent, index: number, path: string) => {
    const was = sessionNow.current
    if (was) {
      if (index === was.index) onCloseEdit()
      else go(index, takeOpener(event))
      return
    }
    if (ending) return
    const begun = startSession(albums, path, showing)
    if (!begun) return
    opened.current = false
    sessionNow.current = begun
    heldNow.current = liveChips
    setHeldChips(liveChips)
    setSession(begun)
    onEdit(requestFor(begun, true), takeOpener(event))
  }

  /** A facet chosen: a session ends with it (and the panel closes), and the address says the facet. */
  const chooseFacet = (id: string | null) => {
    if (sessionNow.current) {
      end(true)
      onCloseEdit()
    }
    onFacet(id)
  }

  //? the panel closed - Close, Escape, another panel, the page left: the session ends
  useEffect(() => {
    if (!session) return
    if (editing !== null) {
      opened.current = true
      return
    }
    if (opened.current) end(true)
  }, [editing, session])

  //? the ending's read answered, and no read still out (a scan gathered after a write may have
  //? superseded it - its albums never written): the list worked out again from what is in now
  useEffect(() => {
    if (ending?.read && !library.loading) {
      setEnding(null)
      setHeldChips(null)
    }
  }, [ending, library.loading])

  //? focus kept in the page: a Try again that worked takes its state away, and a row the session
  //? ended on can leave the list (fixed, ignored, renamed) - only when focus fell to the page
  useLayoutEffect(() => {
    if (retrying.current && !library.loading) {
      retrying.current = false
      if (focusLost()) body.current?.focus({ preventScroll: true })
    }
    if (endedAt.current !== null && !session && !ending) {
      const at = endedAt.current
      endedAt.current = null
      if (focusLost()) {
        const buttons = list.current?.querySelectorAll<HTMLElement>('.app-queue-row')
        const target = buttons && buttons.length ? buttons[Math.min(at, buttons.length - 1)] : body.current
        target?.focus({ preventScroll: true })
      }
    }
  })

  //? gone with a session still on (back): the album left marked reviewed, and the count the server's
  useEffect(() => () => {
    const was = sessionNow.current
    if (was) {
      const path = leavingAtEnd(was)
      if (path) review(path)
    }
    setPageQueueCount(null)
  }, [])

  //? shown again after the first time, with nothing under way: the library read again underneath
  const wasShown = useRef(shown)
  useEffect(() => {
    if (desktop && shown && !wasShown.current && library.loaded && !sessionNow.current && !ending) void library.reload(false)
    wasShown.current = shown
  }, [shown])

  //? while it shows with a real scan and no session, its count is the badge's
  useEffect(() => {
    setPageQueueCount(desktop && shown && real && !session && !ending ? summaryTotal(library.albums) : null)
  }, [desktop, shown, real, session, ending, library.albums])

  //? a facet the address names that has emptied: the address says All again - only while this page
  //? is the one showing, since the router rewrites the top of the tab that shows (a read landing
  //? while another tab shows would rewrite nothing, and the address would keep the old facet)
  useEffect(() => {
    if (desktop && shown && real && !session && !ending && facet !== null && showing === null) onFacet(null)
  }, [desktop, shown, real, session, ending, facet, showing])

  const header = (
    <>
      <header class="pl-nav-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
      </header>
      <header class="pl-large-header">
        <h1 class="pl-large-title">Needs a look</h1>
      </header>
    </>
  )

  if (!desktop) {
    return (
      <section class="app-queue is-phone app-needs">
        {header}
        {/* the app's own card for a page with nothing to show - no style of this page's own on a phone */}
        <div class="app-card app-placeholder-body">
          <p class="app-placeholder-text app-queue-phone">
            {NEEDS_LOOK_PHONE}{' '}
            <a class="app-queue-link" href="/" target="_blank" rel="noopener">
              the main page
            </a>
            .
          </p>
        </div>
      </section>
    )
  }

  const rows: DrawnRow[] = session ? sessionRows(session) : ending?.rows ?? asRows(albums)
  //? a Try again: refused while a read is out (aria-disabled, so focus stays on it)
  const retry = () => {
    if (library.loading) return
    retrying.current = true
    void library.reload(false)
  }
  const checking = library.loaded && (library.stale || library.loading)
  const pressed = session ? session.facet : ending ? ending.facet : showing

  return (
    <section class="app-queue">
      {header}
      <div ref={body} class="app-queue-body" tabIndex={-1}>
        <p class="app-queue-line">{NEEDS_LOOK_LINE}</p>

        {library.problem ? (
          <p class="app-queue-state">{library.problem}</p>
        ) : !library.loaded ? (
          <div class="pl-spinner" aria-label="Reading the library" />
        ) : library.error && !library.albums.length ? (
          <div class="app-queue-state">
            <p>deadwax couldn't read the library: {library.error}</p>
            <button type="button" class="app-button" aria-disabled={library.loading ? 'true' : undefined} onClick={retry}>
              Try again
            </button>
          </div>
        ) : (
          <>
            <div class="app-library-views app-queue-facets" role="group" aria-label="Show">
              {chips.filter((chip) => chip.id === null || chip.count > 0).map((chip) => (
                <button
                  key={chip.id ?? 'all'}
                  type="button"
                  class={`app-chip app-library-view app-queue-facet${chip.id === pressed ? ' is-on' : ''}`}
                  aria-pressed={chip.id === pressed}
                  {...(chip.hint ? { title: chip.hint } : {})}
                  onClick={() => chooseFacet(chip.id)}
                >
                  {chip.label} <span class="app-queue-count app-mono">{chip.count}</span>
                </button>
              ))}
            </div>

            {/* always there, one line tall: its coming and going moves no row */}
            <p class="app-queue-checking" role="status">
              {library.error ? (
                <>
                  Couldn't check the library just now: {library.error}{' '}
                  <button type="button" class="app-text-button" aria-disabled={library.loading ? 'true' : undefined} onClick={retry}>
                    Try again
                  </button>
                </>
              ) : checking ? (
                'Checking the library…'
              ) : null}
            </p>

            {!rows.length ? (
              <p class="app-queue-state">Nothing needs a look.</p>
            ) : (
              <ul ref={list} class="app-queue-list" aria-label="Albums that need a look">
                {rows.map((row, index) => {
                  const { album, mark } = row
                  const current = !!session && session.index === index
                  const art = album.art ? albumArtUrl(album) : null
                  const edition = album.disc_label || album.edition
                  return (
                    <li key={row.key}>
                      <button
                        type="button"
                        class={`app-queue-row${current ? ' is-current' : ''}${mark ? ' is-done' : ''}`}
                        {...(current ? { 'aria-current': 'true' as const } : {})}
                        {...(ending ? { 'aria-disabled': 'true' as const } : {})}
                        onClick={(event) => choose(event, index, album.path)}
                      >
                        {art && !failedArt.has(art) ? (
                          <img
                            class="app-queue-cover"
                            src={art}
                            alt=""
                            loading="lazy"
                            onError={() => setFailedArt((was) => new Set(was).add(art))}
                          />
                        ) : (
                          <span class="app-queue-cover is-empty" aria-hidden="true" />
                        )}
                        <span class="app-queue-text">
                          <span class="app-queue-album">{album.album || album.path}</span>
                          <span class="app-queue-artist">{[album.artist, edition].filter(Boolean).join(' · ')}</span>
                        </span>
                        <span class="app-queue-chips">
                          {mark ? (
                            <span class="app-queue-mark">{MARK_WORDS[mark]}</span>
                          ) : (
                            <>
                              {isNewImport(album) && <span class="app-queue-chip is-new">New</span>}
                              {outstandingIssues(album).map((code) => (
                                <span
                                  key={code}
                                  class="app-queue-chip"
                                  {...(library.issueTypes[code]?.hint ? { title: library.issueTypes[code]!.hint } : {})}
                                >
                                  {issueLabel(code, library.issueTypes)}
                                </span>
                              ))}
                            </>
                          )}
                        </span>
                      </button>
                    </li>
                  )
                })}
              </ul>
            )}
          </>
        )}
      </div>
    </section>
  )
}
