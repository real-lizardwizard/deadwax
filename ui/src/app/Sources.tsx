import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import type { Candidate, DownloadRelease } from '../api/types'
import { useCandidateSearch } from '../hooks/useCandidateSearch'
import { useDismiss } from '../hooks/useDismiss'
import { panelIsModal, type PanelStyle } from '../lib/appFrame'
import {
  SIGNAL_LABELS, SORT_LABELS, candidateKey, noSignalMinimums, passesFilters, queriesText, searchedLine, searchingLine, sortCandidates,
  sourcesAnnouncement, storeNotes, storeStatus, type CandidateSort,
} from '../lib/candidates'
import {
  GET_SETTINGS_DEFAULT, NO_SOURCE_FILTERS, PICK_SORT, candidateFilters, floorFilters, pressedCount, signalsSet, sourceChips,
  type SourceFilters,
} from '../lib/getSettings'
import { ChevronDownIcon, CloseIcon } from '../player/icons'
import { SourceCard } from './SourceCard'
import { StoreState } from './StoreState'
import { getSettingsNow, useGetSettings } from './useGetSettings'
import { useSheet } from './useSheet'

/** A Get: what it downloads, and what the sheet's heading says it is for. */
export interface GetRequest {
  /** the release a download files as - lib/releasePayload.ts */
  release: DownloadRelease
  /** "Third · CD · 2008 · GB · Island", or "Third · the album as a whole" */
  subtitle: string
  /** a new number for every Get, so the same album got twice searches twice */
  key: number
  /**
   * The album-you-don't-have page that asked - its group id (2.0.0-player.19). On a desktop the page
   * stays usable beside the Sources panel, and choosing another pressing there searches again for it.
   */
  from?: string
  /** That search again, for another pressing: the chips stay as they are, and nothing is picked for
   *  you - you are choosing, as with a Re-search. */
  again?: boolean
}

//? each Signals chip's list its own id
let signalLists = 0

/**
 * The desktop panel's Signals chip (2.0.0-player.19), as DesktopRequest.dc.html draws it beside the
 * phone's three: the least each of the score's six signals may be, as the main page's candidates
 * panel has them - a slider each, 0 for any, with a count on the chip of how many are set so a
 * minimum is never a filter on out of sight. A tap outside closes it, as does Escape - taken here,
 * so it doesn't close the panel too.
 */
export function SignalsChip({
  minimums,
  onChange,
}: {
  minimums: Readonly<Record<string, number>>
  onChange: (next: Record<string, number>) => void
}) {
  const id = useMemo(() => `app-signals-${++signalLists}`, [])
  const [open, setOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const button = useRef<HTMLButtonElement>(null)
  useDismiss(root, open, () => setOpen(false))
  const set = signalsSet(minimums)

  return (
    <div
      class="app-signals"
      ref={root}
      onKeyDown={(event: KeyboardEvent) => {
        if (!open || event.key !== 'Escape') return
        event.preventDefault()
        setOpen(false)
        button.current?.focus()
      }}
    >
      <button
        ref={button}
        type="button"
        class={`app-chip${set ? ' is-on' : ''}`}
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen((was) => !was)}
      >
        {set ? `Signals · ${set}` : 'Signals'}
      </button>
      <div id={id} class="app-signals-popover" role="group" aria-label="The least each signal may score" hidden={!open}>
        {Object.entries(SIGNAL_LABELS).map(([signal, name]) => {
          const value = minimums[signal] ?? 0
          return (
            <label key={signal} class="app-signals-row">
              <span class="app-signals-name">{name.charAt(0).toUpperCase() + name.slice(1)}</span>
              <input
                class="app-signals-range"
                type="range"
                min={0}
                max={100}
                step={5}
                value={value}
                onInput={(event) => onChange({ ...minimums, [signal]: Number((event.currentTarget as HTMLInputElement).value) })}
              />
              <span class="app-signals-value app-mono">{value ? value : 'any'}</span>
            </label>
          )
        })}
        <button type="button" class="app-signals-reset" disabled={!set} onClick={() => onChange(noSignalMinimums())}>
          Reset
        </button>
      </div>
    </div>
  )
}

/**
 * Choose a source (2.0.0-player.15, Sources.dc.html): the sheet a Get opens - "Get the album" on the
 * album you don't have, or a Get chip on a Search row - over everything, under Now Playing's menu and
 * Info (z 25). Soulseek is searched for the release the Get was for (hooks/useCandidateSearch.ts),
 * and each folder found is a card (SourceCard.tsx); a card's Get asks for the download in the tap -
 * the pending row is in Requests from that moment - and `onQueued` closes the sheet and shows
 * Requests.
 *
 *  - THE CHIPS: Lossless (every file lossless: unknown never passes), 24-bit, Free slot, and the
 *    sort. They start as the quality floor (You > Getting albums) - a floor drawn as a chip pressed,
 *    never a filter on out of sight; a 320 kbps floor has its own chip, shown only then.
 *  - THE BEST MATCH - the highest score through the chips - has the purple edge and the one solid
 *    Get wherever the sort puts it: "smallest first" moves it down the list, never onto another
 *    card (review).
 *  - "PICK THE BEST SOURCE FOR ME": on a fresh Get the best match at AUTO_GRAB_MIN_SCORE or more
 *    through the chips is asked for straight away and Requests shows; when nothing qualifies, or the
 *    pressing is held or on its way, the cards show with a line saying why.
 *  - THE STATES: asking (the sweep, and the names being asked for); slskd unable to search (its own
 *    words - "slskd isn't logged in to Soulseek...", the 409 explanation the server builds) with Try
 *    again; nothing found, with the query to edit and Re-search; folders found and none passing the
 *    chips, with Clear filters; and the store's answer - held whole or downloading whole stands where
 *    the cards would be (the server searched nothing), a part held, a part downloading and other
 *    pressings are notes above them. A Get slskd or deadwax refuses (deadwax's 409 "already
 *    downloading from bob", a peer offline) shows on its row in Requests as "refused", in their words.
 *
 * A sheet like the others (useSheet.ts): its own scroll lock, focus in to Cancel and back to the Get
 * that opened it, Escape, a tap on the backdrop above it; inert while closed. Cancel, the backdrop
 * and Escape let the search go IN the gesture (review): left to an effect after the next frame, an
 * answer landing in between could still pick - and queue - a source after Cancel. Its list is the
 * one part that scrolls, and says so itself (`touch-action: pan-y`). It stays mounted, showing the
 * last Get, so it slides away still drawn. A leaf in all but the settings, which it reads from their
 * store (useGetSettings.ts): asked each time it opens, the defaults until the first answer is in - a
 * Get then shows the sources, the safe way round.
 *
 * For VoiceOver (review): one live region, always in the sheet, says each outcome in a line
 * (lib/candidates.ts sourcesAnnouncement) - asking, slskd's refusal, the store's box, nothing found,
 * none passing, how many sources - so someone waiting on Cancel hears the search end. And Try again,
 * Re-search and Clear filters each end the state they sit in, so before they do, focus goes to the
 * list (a tab stop of -1): never to the page, outside the dialog.
 *
 * ON A DESKTOP (2.0.0-player.19) it is the side panel, as DesktopRequest.dc.html draws it - a third
 * column from 1280px, a drawer over the page's edge below that (lib/appFrame.ts's panel rule) - and
 * NOT modal: the page beside it stays usable, which is the point - the pressings and their sources
 * side by side. So no scroll lock and no backdrop, and Escape closes it only from inside it (its box
 * takes focus from a click on anything in it that can't, so a click on its heading still counts). Its
 * head is the board's: "Sources", what they are for under it, and a close button; its chips gain
 * Signals (SignalsChip, above), whose minimums filter only while it is a panel. The cards are the SAME
 * cards - James chose cards over a comparison table on a desktop too. The album page asks it to search
 * again as another pressing is chosen (`again`): the chips you set stay set, and nothing is picked for
 * you.
 */
export function Sources({
  open,
  request,
  opener,
  onClose: closeSheet,
  onQueued,
  panel = 'sheet',
  covered = false,
}: {
  open: boolean
  request: GetRequest | null
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  /** a download was asked for: the sheet goes, and Requests shows */
  onQueued: () => void
  /** how it is drawn: a sheet (a phone), or a desktop's side panel - a drawer or a third column */
  panel?: PanelStyle
  /** something over the whole screen - the desktop's visualizer (2.0.0-player.20): a panel left open
   *  under it is inert, and out of what a screen reader can reach, until it goes */
  covered?: boolean
}) {
  const modal = panelIsModal(panel)
  const cancel = useRef<HTMLButtonElement>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const box = useRef<HTMLDivElement>(null)
  const { settings } = useGetSettings(open)

  const floor = (settings ?? GET_SETTINGS_DEFAULT).quality_floor
  const [filters, setFilters] = useState<SourceFilters>(() => floorFilters(floor))
  //? the desktop's Signals chip: the least each signal may be (none on a phone, where none is drawn)
  const [signals, setSignals] = useState<Record<string, number>>(noSignalMinimums)
  const [sort, setSort] = useState<CandidateSort>('score')
  //? the chips were tapped since this Get began: the settings landing late don't re-seed them then
  const touched = useRef(false)

  //? The Signals chip's minimums apply only where the chip is drawn - the desktop's panel. Carried into
  //? a phone's sheet (a window narrowed under 1024px, an iPad turned upright, the panel open) they are
  //? kept for the panel again but filter nothing: a minimum is never a filter on out of sight.
  const minimums = modal ? undefined : signals
  const filtersNow = useRef(filters)
  filtersNow.current = filters
  const minimumsNow = useRef(minimums)
  minimumsNow.current = minimums

  const state = useCandidateSearch({
    //? read as the answer lands: the settings as they are then, and the chips
    picking: () => ({
      pick: getSettingsNow().get_mode === 'pick',
      filters: candidateFilters(filtersNow.current, minimumsNow.current),
      sort: PICK_SORT,
    }),
    onPicked: onQueued,
  })

  //? Cancel, the backdrop and Escape: the search let go in the gesture, then the sheet closes
  const onClose = () => {
    state.stop()
    closeSheet()
  }
  useSheet({ open, covered, onClose, lockClass: 'app-sources-open', first: cancel, opener, modal, area: box })

  //? every Get searches afresh, its chips the quality floor again - but the desktop panel following
  //? the page to another pressing (`again`) searches for that one with the chips as you left them,
  //? and picks nothing
  useEffect(() => {
    if (!open || !request) return
    if (scroller.current) scroller.current.scrollTop = 0
    if (request.again) {
      state.start(request.release, false)
      return
    }
    touched.current = false
    setFilters(floorFilters(getSettingsNow().quality_floor))
    setSignals(noSignalMinimums())
    setSort('score')
    state.start(request.release)
  }, [open, request?.key])

  //? the backstop: however the sheet closed (a Get handing over, App), the search goes with it
  useEffect(() => {
    if (!open) state.stop()
  }, [open])

  //? the settings arriving after the sheet opened: the chips become the floor, unless already tapped
  useEffect(() => {
    if (open && settings && !touched.current) setFilters(floorFilters(settings.quality_floor))
  }, [settings?.quality_floor])

  const search = state.search
  const result = search?.result ?? null
  const chosen = useMemo(() => candidateFilters(filters, minimums), [filters, minimums])
  const passing = useMemo(() => (result?.candidates ?? []).filter((candidate) => passesFilters(candidate, chosen)), [result, chosen])
  const shown = useMemo(() => sortCandidates(passing, sort), [passing, sort])
  //? the best match through the chips - the top of the list by score, as a pick goes - wherever the
  //? sort puts it
  const best = useMemo(() => {
    const top = sortCandidates(passing, 'score')[0]
    return top ? candidateKey(top) : null
  }, [passing])

  //? a button that ends the state it sits in hands focus to the list first, never to the page
  const keepFocus = () => scroller.current?.focus({ preventScroll: true })

  const toggle = (key: keyof SourceFilters) => {
    touched.current = true
    setFilters((now) => ({ ...now, [key]: !now[key] }))
  }

  const get = (candidate: Candidate) => {
    if (state.download(candidate, shown)) onQueued()
  }

  const status = result ? storeStatus(result, 'Requests') : null
  const notes = result ? storeNotes(result) : []
  const announcement = search
    ? sourcesAnnouncement({ pending: search.pending, release: search.release, error: search.error, status, result, shown: shown.length, notPicked: state.notPicked })
    : ''

  return (
    <div class={`app-layer app-sources-layer${open ? ' is-open' : ''}${modal ? '' : ` is-panel is-${panel}`}`} aria-hidden={!open || covered} inert={!open || covered}>
      <div class="app-backdrop" onClick={onClose} />
      {/* a panel's box takes focus from a click anywhere in it that lands on nothing focusable (its
          heading, the chips' row - and in Safari a chip, which it never focuses), so Escape there is
          still from inside it */}
      <div ref={box} class="app-sources" role="dialog" aria-modal={modal ? 'true' : 'false'} aria-labelledby="app-sources-title" tabIndex={modal ? undefined : -1}>
        {modal ? (
          //? the subtitle has the sheet's whole width, and wraps: the part that tells pressings apart
          //? comes last, and is the part an ellipsis would take
          <header class="app-sources-head">
            <button ref={cancel} type="button" class="app-sources-cancel" onClick={onClose}>
              Cancel
            </button>
            <h2 id="app-sources-title" class="app-sources-title">Choose a source</h2>
            {request && <p class="app-sources-subtitle">{request.subtitle}</p>}
          </header>
        ) : (
          //? the desktop panel's head, as its board has it: what they are for under the heading, and
          //? the close button at the right
          <header class="app-sources-head is-panel">
            <div class="app-sources-heading">
              <h2 id="app-sources-title" class="app-sources-title">Sources</h2>
              {request && <p class="app-sources-subtitle">for {request.subtitle}</p>}
            </div>
            <button ref={cancel} type="button" class="app-sources-close" onClick={onClose} aria-label="Close the sources">
              <CloseIcon class="app-sources-close-icon" />
            </button>
          </header>
        )}
        <p class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">{announcement}</p>

        <div class="app-sources-chips" role="group" aria-label="Filter the sources">
          {sourceChips(floor, filters).map((chip) => (
            <button
              key={chip.key}
              type="button"
              class={`app-chip${chip.on ? ' is-on' : ''}`}
              aria-pressed={chip.on}
              onClick={() => toggle(chip.key)}
            >
              {chip.label}
            </button>
          ))}
          {/* a desktop's Signals chip, before the sort as its board has it */}
          {!modal && (
            <SignalsChip
              minimums={signals}
              onChange={(next) => {
                touched.current = true
                setSignals(next)
              }}
            />
          )}
          <label class="app-chip app-sources-sort">
            <span class="app-visually-hidden">Sort the sources</span>
            <span aria-hidden="true">{SORT_LABELS[sort]}</span>
            <select
              class="app-sources-sort-select"
              value={sort}
              onChange={(event) => setSort((event.currentTarget as HTMLSelectElement).value as CandidateSort)}
            >
              {Object.entries(SORT_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
            <ChevronDownIcon class="app-sources-sort-icon" />
          </label>
        </div>

        <div ref={scroller} class="app-sources-scroll" tabIndex={-1} aria-busy={!!search?.pending}>
          {!search ? null : search.pending ? (
            <div class="app-sources-state">
              <span class="app-sweep app-sources-sweep" aria-hidden="true" />
              <p class="app-sources-state-text">{searchingLine(search.release)}</p>
              <p class="app-sources-state-note">slskd listens for answers for a few seconds.</p>
            </div>
          ) : search.error ? (
            <div class="app-sources-state">
              <p class="app-sources-state-text is-warning">{search.error}</p>
              <button
                type="button"
                class="app-button"
                onClick={() => {
                  keepFocus()
                  state.start(search.release)
                }}
              >
                Try again
              </button>
            </div>
          ) : status ? (
            <StoreState status={status} notes={notes} />
          ) : (
            <>
              <StoreState status={null} notes={notes} />
              {state.notPicked && <p class="app-sources-not-picked">{state.notPicked}</p>}
              {!result!.candidates.length ? (
                <form
                  class="app-sources-state"
                  onSubmit={(event) => {
                    event.preventDefault()
                    keepFocus()
                    state.requery()
                  }}
                >
                  <p class="app-sources-state-text">Soulseek found nothing for {queriesText(result!)}.</p>
                  <label class="app-sources-query">
                    <span class="app-sources-query-label">Search Soulseek for</span>
                    <input
                      class="app-sources-query-input"
                      type="search"
                      value={state.query}
                      onInput={(event) => state.setQuery((event.currentTarget as HTMLInputElement).value)}
                      enterKeyHint="search"
                      autoComplete="off"
                      autoCapitalize="none"
                      spellcheck={false}
                    />
                  </label>
                  <button type="submit" class="app-button">
                    Re-search
                  </button>
                </form>
              ) : !shown.length ? (
                <div class="app-sources-state">
                  <p class="app-sources-state-text">
                    {result!.candidates.length} {result!.candidates.length === 1 ? 'folder' : 'folders'} on Soulseek, none pass your filters
                  </p>
                  {pressedCount(filters, minimums) > 0 && (
                    <button
                      type="button"
                      class="app-button"
                      onClick={() => {
                        keepFocus()
                        touched.current = true
                        setFilters(NO_SOURCE_FILTERS)
                        setSignals(noSignalMinimums())
                      }}
                    >
                      Clear filters
                    </button>
                  )}
                </div>
              ) : (
                <>
                  <ul class="app-sources-list">
                    {shown.map((candidate) => (
                      <SourceCard key={candidateKey(candidate)} candidate={candidate} best={candidateKey(candidate) === best} onGet={get} />
                    ))}
                  </ul>
                  <p class="app-sources-footer">{searchedLine(result!, shown.length)}</p>
                </>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}
