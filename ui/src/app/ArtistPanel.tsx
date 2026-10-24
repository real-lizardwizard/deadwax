import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import {
  applyArtistImages, applyArtistRefile, previewArtistImages, previewArtistRefile, searchArtists, type ArtistRefileResults,
} from '../api/library'
import type { ArtistImagesPreview, ArtistMatch } from '../api/types'
import { EDIT_SETTLE_MS } from '../lib/albumEdit'
import { panelIsModal, type PanelStyle } from '../lib/appFrame'
import {
  bestUrls, byKind, canMove, imageNotes, listed, matchLine, moveButton, moveLine, refileAfter, refileOutcome, refileView, savedLine, slotLine, toggleChoice,
  type AppliedName, type NamedPlan,
} from '../lib/artistManage'
import { artistArtUrl } from '../lib/format'
import { isAbort, latestOnly } from '../lib/latest'
import { CheckIcon, CloseIcon } from '../player/icons'
import { useSheet } from './useSheet'
import { sayError } from './sayError'

/** What the artist page's panel is opened for (2.0.0-player.45). */
export type ArtistManageMode = 'images' | 'refile' | 'who'

/**
 * The artist page's request: what it knows of the artist, and what it wants told. Each press makes a
 * new one (`key`), so the panel starts afresh.
 */
export interface ArtistManageRequest {
  key: number
  mode: ArtistManageMode
  /** the artist page's id - the panel is that page's, and closes as it stops being the one on top */
  page: string
  /** the page's name for them */
  name: string
  /** their MusicBrainz id as the page knows it - from their files, Navidrome, or chosen here */
  mbid: string | null
  /** MusicBrainz's name for them now: what Move albums to moves them under */
  currentName: string | null
  /** the names the library files them under that aren't that one: what Move albums to moves */
  moveNames: string[]
  /** the library name whose folder their pictures go into (lib/artistManage.ts imagesFolder) */
  imagesName: string | null
  /** what the pictures already on disk are asked with - a new number after every save */
  version: number
  /** albums moved: `emptied` the names every album of which moved - a page of one of those follows
   *  them under their current name, by their MusicBrainz id; any other stays and is asked again */
  onMoved?: (outcome: { mbid: string; name: string; moved: number; emptied: string[] }) => void
  /** pictures saved: the page asks for its folder again */
  onSaved?: () => void
  /** "Which artist is this?" answered */
  onChosen?: (match: { mbid: string; name: string; disambiguation: string }) => void
}

const TITLES: Readonly<Record<ArtistManageMode, string>> = {
  images: 'Artist images',
  refile: 'Move albums',
  who: 'Which artist is this?',
}

//? (2.0.8, UX batch 5) a failure in words (lib/errorWords.ts) - `failed` its sentence, its own words in brackets for
//? whoever runs deadwax - where it was the error's own words
const message = (error: unknown, failed: string) => sayError(error, '', { failed })

/** Focus fell to the page (or was never taken) - the only time a body moves it. */
const focusLost = (): boolean => {
  if (typeof document === 'undefined') return false
  const active = document.activeElement
  return !active || active === document.body
}

/**
 * The artist page's panel (2.0.0-player.45): the main page's artist dialogs - its images picker
 * (ArtistImagePicker) and its re-filing (ArtistRefileDialog), both in its ArtistDetails.tsx, which went
 * with it in 2.0.0-player.66 - drawn for the app, through the same routes, plus "Which artist is this?" (the
 * picker's MusicBrainz artist search) on its own. By the frame's panel rule (lib/appFrame.ts): a SIDE
 * PANEL on a desktop - a third column from 1280px, a drawer below it, not modal, one at a time (App) -
 * and on a phone a sheet over the whole screen, the page behind inert. useSheet does the rest: focus in
 * to its close button and back to what opened it, Escape (on a desktop only from inside it), its own
 * scroll lock as a sheet.
 *
 * Every write keeps its route's guards, and the routes recompute what they write: Move albums to asks
 * the refile route's preview for each name the library files them under, then its apply for each in
 * turn, and the apply recomputes the plan (src/artist_refile.py, the eighth writer); Save hands the
 * images route the pictures chosen, and it honours only a picture the artist's own sources just offered
 * (src/artist_art.py, the fifth). A write is never called off: closing the panel while one is out only
 * stops what it says being drawn - the page still hears that albums moved, and follows them. Every
 * fetch that draws goes through its own latestOnly().
 */
export function ArtistPanel({
  open,
  request,
  opener,
  onClose,
  onSettled,
  panel,
  covered = false,
}: {
  open: boolean
  /** the last request it was opened for, kept as it slides away */
  request: ArtistManageRequest | null
  opener: { current: HTMLElement | null }
  onClose: () => void
  /** albums moved a while ago (EDIT_SETTLE_MS - by when Navidrome has usually scanned the move): the
   *  page they were moved from asks again, under the id it has now (App) - told from here, which is
   *  never unmounted, whether the panel is still open or not */
  onSettled?: (page: string) => void
  panel: PanelStyle
  /** the desktop's visualizer is over it: inert, and not the one Escape closes */
  covered?: boolean
}) {
  const modal = panelIsModal(panel)
  const close = useRef<HTMLButtonElement>(null)
  const box = useRef<HTMLDivElement>(null)
  useSheet({ open, covered, onClose, lockClass: 'app-artist-panel-open', first: close, opener, modal, area: box })

  const title = request ? TITLES[request.mode] : ''
  //? Move albums: the names whose albums move, and where - never the page's own name, which on the
  //? page of their name now would read "Ye → Ye" (review)
  const subtitle = request
    ? (request.mode === 'refile' && request.currentName && request.moveNames.length ? `${listed(request.moveNames)} → ${request.currentName}` : request.name)
    : ''

  return (
    <div class={`app-layer app-artist-panel-layer${open ? ' is-open' : ''}${modal ? '' : ` is-panel is-${panel}`}`} aria-hidden={!open || covered} inert={!open || covered}>
      <div class="app-backdrop" onClick={onClose} />
      {/* a panel's box takes focus from a click on anything in it that can't, so Escape there is still
          from inside it; a sheet's has no tab stop */}
      <div ref={box} class="app-artist-panel" role="dialog" aria-modal={modal ? 'true' : 'false'} aria-labelledby="app-artist-panel-title" tabIndex={modal ? undefined : -1}>
        <header class="app-artist-panel-head">
          <div class="app-artist-panel-heading">
            <h2 id="app-artist-panel-title" class="app-artist-panel-title">{title}</h2>
            {subtitle && <p class="app-artist-panel-subtitle">{subtitle}</p>}
          </div>
          <button ref={close} type="button" class="app-artist-panel-close" aria-label={`Close ${title.toLowerCase() || 'this'}`} onClick={onClose}>
            <CloseIcon class="app-artist-panel-close-icon" />
          </button>
        </header>
        {/* each request a new body (its key), so nothing of the last one's lingers */}
        {request && request.mode === 'refile' && (
          <RefileBody key={request.key} request={request} live={open} onClose={onClose} onSettle={(page) => setTimeout(() => onSettled?.(page), EDIT_SETTLE_MS)} />
        )}
        {request && request.mode === 'images' && <ImagesBody key={request.key} request={request} live={open} />}
        {request && request.mode === 'who' && <WhoBody key={request.key} request={request} live={open} onClose={onClose} />}
      </div>
    </div>
  )
}

/**
 * Move albums to <their current name> - the main page's ArtistRefileDialog, across every name the
 * library files them under (Kanye West's and anything else that isn't Ye): each name's plan asked of
 * the refile route's preview, drawn as one - each move (folder → where it goes, its tracks and how
 * many are retagged), each album that stays and why, and what stops it - then Move, the apply for each
 * name in turn, stopping at the first that fails. What became of it is said in the panel, with Done -
 * every album the preview showed moving that didn't, and why - while the page is told what moved
 * (only when something did), and which names are now empty, so a page of one of those follows them.
 */
export function RefileBody({ request, live, onClose, onSettle }: {
  request: ArtistManageRequest
  live: boolean
  onClose: () => void
  /** albums moved: wait for Navidrome's scan, then have the page they were moved from ask again (ArtistPanel's) */
  onSettle?: (page: string) => void
}) {
  const [plans, setPlans] = useState<NamedPlan[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [applying, setApplying] = useState(false)
  const [outcome, setOutcome] = useState<{ text: string; failures: string[] } | null>(null)
  const previews = useMemo(latestOnly, [])
  //? a move's answer: drawn only while this body is still the one showing it
  const applies = useMemo(latestOnly, [])
  const done = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    const ticket = previews.begin()
    Promise.all(request.moveNames.map((name) =>
      previewArtistRefile(name, request.mbid, ticket.signal).then((plan) => ({ name, plan })))).then(
      (found) => {
        if (ticket.current()) setPlans(found)
      },
      (caught: unknown) => {
        if (ticket.current() && !isAbort(caught)) setError(message(caught, "Couldn't work out the moves."))
      },
    )
    return () => previews.supersede()
  }, [])

  //? closed: a move still out goes on, but what it says isn't drawn into a panel nobody sees
  useEffect(() => {
    if (!live) applies.supersede()
  }, [live])

  //? Move gone and Done come: focus goes to Done, only when it fell to the page
  useLayoutEffect(() => {
    if (outcome && focusLost()) done.current?.focus({ preventScroll: true })
  }, [outcome])

  const view = refileView(plans ?? [])

  const apply = async () => {
    if (!plans || !canMove(view) || applying) return
    const ticket = applies.begin()
    setApplying(true)
    setError(null)
    const applied: AppliedName[] = []
    let problem: string | null = null
    //? one name at a time - each apply recomputes its own plan on the server - and none after one fails:
    //? what the preview said is no longer what is on disk
    const moving = new Set(view!.moves.map((move) => move.path))
    for (const { name, plan } of plans) {
      if (!plan.moves.some((move) => moving.has(move.path))) continue
      try {
        applied.push({ name, ...(await applyArtistRefile(name, request.mbid)) })
      } catch (caught) {
        problem = message(caught, "The move didn't work.")
        break
      }
    }
    const results: ArtistRefileResults[] = applied.map((one) => one.results)
    const told = refileOutcome(results, view!.toFolder)
    const after = refileAfter(plans, applied, view!)
    //? the page told only when something moved - closed or not, the library has changed - and asked
    //? again once Navidrome has had time to scan it
    if (told.moved && request.mbid) {
      request.onMoved?.({ mbid: request.mbid, name: view!.currentName, moved: told.moved, emptied: after.emptied })
      onSettle?.(request.page)
    }
    if (!ticket.current()) return
    setApplying(false)
    setOutcome({ text: told.text, failures: [...told.failures, ...after.stayed, ...(problem ? [problem] : [])] })
  }

  return (
    <>
      <div class="app-artist-panel-body" tabIndex={-1}>
        {outcome ? (
          <div class="app-artist-panel-outcome" role="status">
            <p class="app-artist-panel-note">{outcome.text}</p>
            {outcome.failures.map((failure) => <p key={failure} class="app-artist-panel-note is-warning">{failure}</p>)}
          </div>
        ) : !plans && !error ? (
          <div class="app-asking" role="status">
            <span class="app-sweep" aria-hidden="true" />
            <span class="app-asking-text">Working out the moves…</span>
          </div>
        ) : view ? (
          <>
            <p class="app-artist-panel-note">
              Each album moves into <strong>{view.toFolder}/</strong> keeping its own folder name, and its album artist
              tag becomes {view.currentName} - where a download filed today would put it. Each track's own artist is
              what the sleeve credited, and stays.
            </p>
            {view.problems.map((problem) => <p key={problem} class="app-artist-panel-note is-warning">{problem}</p>)}
            {view.moves.length > 0 && (
              <ul class="app-artist-moves" aria-label="Albums that move">
                {view.moves.map((move) => (
                  <li key={move.path} class="app-artist-move">
                    <span class="app-artist-move-path">{move.path}</span>
                    <span class="app-artist-move-to">→ {move.target_path}</span>
                    <span class="app-artist-move-line">{moveLine(move)}</span>
                  </li>
                ))}
              </ul>
            )}
            {view.refused.length > 0 && (
              <ul class="app-artist-moves is-refused" aria-label="Albums that stay">
                {view.refused.map((refused) => (
                  <li key={refused.path} class="app-artist-move">
                    <span class="app-artist-move-path">{refused.path}</span>
                    <span class="app-artist-move-line is-warning">stays - {refused.reason}</span>
                  </li>
                ))}
              </ul>
            )}
            {/* nothing to move: every album already under the name - or every one staying, said beside it */}
            {view.empty && !view.problems.length && (
              <p class="app-artist-panel-note">
                {view.refused.length
                  ? 'Nothing can move - every album stays where it is, for the reason beside it.'
                  : `Nothing to move - every album is already filed under ${view.currentName}.`}
              </p>
            )}
          </>
        ) : null}
        {error && <p class="app-artist-panel-note is-warning" role="alert">{error}</p>}
      </div>
      <footer class="app-artist-panel-foot">
        {outcome ? (
          <button ref={done} type="button" class="pl-pill is-primary app-artist-panel-primary" onClick={onClose}>
            Done
          </button>
        ) : (
          <>
            <button
              type="button"
              class={`pl-pill is-primary app-artist-panel-primary${applying ? ' is-busy' : ''}`}
              disabled={!canMove(view)}
              aria-disabled={applying ? 'true' : undefined}
              aria-busy={applying}
              onClick={() => void apply()}
            >
              {applying ? 'Moving…' : moveButton(view?.moves.length ?? 0)}
            </button>
            <button type="button" class="pl-pill" onClick={onClose}>
              Cancel
            </button>
          </>
        )}
      </footer>
    </>
  )
}

/**
 * Artist images… - as ArtistImagePicker had it on the old page: every picture of them its sources have, slot by
 * slot (square, banner, background, logo, wide, clear art) with where each is from; the file already
 * on disk, or that nothing was found; a tap to choose one, again to leave that slot as it is; "Use
 * another picture" putting any picture found in any slot; the notes on the keys not set; and Save,
 * with "Replace pictures that are already there". Who they are can be changed here too (the search),
 * for the pictures alone - as it could there. While another artist's pictures are being looked for,
 * or the look failed, Save can't be pressed: what it would write is the last artist's, rejected or no
 * longer on screen (review) - and Try again looks again for the artist last asked about.
 */
export function ImagesBody({ request, live }: { request: ArtistManageRequest; live: boolean }) {
  const [preview, setPreview] = useState<ArtistImagesPreview | null>(null)
  const [problem, setProblem] = useState<string | null>(null)
  const [chosen, setChosen] = useState<Record<string, string>>({})
  const [expanded, setExpanded] = useState<Readonly<Record<string, boolean>>>({})
  const [replace, setReplace] = useState(false)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState<string | null>(null)
  const [version, setVersion] = useState(request.version)
  //? the search: open when MusicBrainz couldn't say who this is, or asked for ("Not them?")
  const [searchOpen, setSearchOpen] = useState(false)
  const [query, setQuery] = useState(request.name)
  const [matches, setMatches] = useState<ArtistMatch[]>([])
  const [searchNote, setSearchNote] = useState<string | null>(null)
  //? whose pictures are being looked for (null: none) - and a search for an artist, apart from it
  const [loading, setLoading] = useState<string | null>(request.name)
  const [searching, setSearching] = useState(false)
  //? the pictures asked for, and a search - each replacing what it shows, only the newest of each (lib/latest.ts)
  const asks = useMemo(latestOnly, [])
  const searches = useMemo(latestOnly, [])
  const saves = useMemo(latestOnly, [])
  //? the artist last asked about - what Try again asks for again
  const lastAsked = useRef<{ mbid: string | null; name: string }>({ mbid: request.mbid, name: request.name })

  const queryBox = useRef<HTMLInputElement>(null)

  const load = (mbid: string | null, name: string) => {
    lastAsked.current = { mbid, name }
    if (!request.imagesName) {
      setLoading(null)
      setProblem("There's no one folder for their pictures.")
      return
    }
    const ticket = asks.begin()
    setLoading(name)
    setProblem(null)
    previewArtistImages(request.imagesName, { artistMbid: mbid }, ticket.signal).then(
      (found) => {
        if (!ticket.current()) return
        setLoading(null)
        setPreview(found)
        setChosen(bestUrls(found))
        setExpanded({})
        setSaved(null)
        if (!found.mbid) {
          setSearchOpen(true)
          setMatches(found.matches)
        } else {
          setMatches([])
        }
      },
      (caught: unknown) => {
        if (!ticket.current() || isAbort(caught)) return
        setLoading(null)
        setProblem(message(caught, "Couldn't look for pictures just now."))
      },
    )
  }

  useEffect(() => {
    load(request.mbid, request.name)
    return () => {
      asks.supersede()
      searches.supersede()
    }
  }, [])

  useEffect(() => {
    if (!live) saves.supersede()
  }, [live])

  //? "Not them?" gone and the search come: focus to its box, only when it fell to the page
  useLayoutEffect(() => {
    if (searchOpen && focusLost()) queryBox.current?.focus({ preventScroll: true })
  }, [searchOpen])

  const search = () => {
    const wanted = query.trim()
    if (!wanted) return
    const ticket = searches.begin()
    setSearching(true)
    setSearchNote(null)
    searchArtists(wanted, ticket.signal).then(
      (found) => {
        if (!ticket.current()) return
        setSearching(false)
        setMatches(found.matches)
        if (!found.matches.length) setSearchNote(`Nothing in MusicBrainz goes by "${wanted}".`)
      },
      (caught: unknown) => {
        if (!ticket.current() || isAbort(caught)) return
        setSearching(false)
        setSearchNote(message(caught, "MusicBrainz couldn't be reached."))
      },
    )
  }

  //? what Save would write is what shows: never while another artist's pictures are coming, or after
  //? that look failed and took them off the screen
  const canSave = !!preview?.mbid && !!Object.keys(chosen).length && loading === null && !problem

  const save = async () => {
    if (!preview || !request.imagesName || saving || !canSave) return
    const ticket = saves.begin()
    setSaving(true)
    setSaved(null)
    try {
      const result = await applyArtistImages(request.imagesName, chosen, { artistMbid: preview.mbid, replace })
      //? the page's folder asked again, whatever shows now - the pictures are on disk
      request.onSaved?.()
      if (!ticket.current()) return
      setPreview((was) => (was ? { ...was, art: result.art } : was))
      setVersion((was) => was + 1)
      setSaved(savedLine(result.results))
    } catch (caught) {
      if (ticket.current()) setSaved(message(caught, "That couldn't be saved."))
    } finally {
      if (ticket.current()) setSaving(false)
    }
  }

  const grouped = useMemo(() => byKind(preview?.candidates ?? []), [preview])
  const notes = preview ? imageNotes(preview) : []
  const who = preview?.facts?.name || request.name

  return (
    <>
      <div class="app-artist-panel-body" tabIndex={-1} aria-busy={loading !== null || searching}>
        {preview?.mbid && loading === null && (
          <p class="app-artist-panel-who">
            Showing {who}{preview.facts?.disambiguation ? ` (${preview.facts.disambiguation})` : ''}
            {!searchOpen && (
              <>
                {' '}
                <button type="button" class="app-text-button app-artist-panel-inline" aria-expanded={false} onClick={() => setSearchOpen(true)}>
                  Not them?
                </button>
              </>
            )}
          </p>
        )}

        {searchOpen && (
          <form class="app-artist-search" role="search" onSubmit={(event) => { event.preventDefault(); search() }}>
            <label class="app-artist-search-label" for="app-artist-images-query">Search MusicBrainz for an artist</label>
            <div class="app-artist-search-row">
              <input
                ref={queryBox}
                id="app-artist-images-query"
                class="app-artist-search-input"
                type="search"
                value={query}
                autoComplete="off"
                onInput={(event) => setQuery((event.currentTarget as HTMLInputElement).value)}
              />
              <button type="submit" class={`pl-pill${searching ? ' is-busy' : ''}`} aria-busy={searching} disabled={!query.trim()}>Search</button>
            </div>
          </form>
        )}
        {searchNote && <p class="app-artist-panel-note">{searchNote}</p>}
        {searchOpen && matches.length > 0 && (
          <MatchList matches={matches} label="Which artist the pictures are of" onPick={(match) => load(match.mbid, match.name)} />
        )}

        {loading !== null ? (
          <div class="app-asking" role="status">
            <span class="app-sweep" aria-hidden="true" />
            <span class="app-asking-text">Looking for pictures of {loading}…</span>
          </div>
        ) : problem ? (
          <div class="app-artist-panel-outcome">
            <p class="app-artist-panel-note is-warning" role="alert">{problem}</p>
            <button type="button" class="app-button" onClick={() => load(lastAsked.current.mbid, lastAsked.current.name)}>Try again</button>
          </div>
        ) : preview ? (
          <>
            {!preview.mbid && preview.problems.map((said) => <p key={said} class="app-artist-panel-note is-warning">{said}</p>)}
            {notes.map((note) => <p key={note} class="app-artist-panel-note">{note}</p>)}
            {preview.mbid && preview.problems.map((said) => <p key={said} class="app-artist-panel-note">{said}</p>)}
            {preview.mbid && preview.kinds.map(({ kind, label }) => {
              const options = grouped[kind] ?? []
              //? every other picture found, so one source's "thumb" can be this slot's background
              const others = preview.candidates.filter((candidate) => candidate.kind !== kind)
              const existing = preview.art?.[kind]
              const more = !!expanded[kind]
              const line = slotLine(existing, options.length)
              //? each picture in a box of the slot's shape - square for the square, wide for the rest - with
              //? the picture fitted inside, so one arriving moves nothing beside it (review)
              const box = `app-artist-option-image${kind === 'thumb' ? ' is-square' : ''}`
              return (
                <section key={kind} class="app-artist-slot" aria-labelledby={`app-artist-slot-${kind}`}>
                  <div class="app-artist-slot-head">
                    <h3 id={`app-artist-slot-${kind}`} class="app-artist-slot-title">{label}</h3>
                    {line && <span class="app-artist-slot-line">{line}</span>}
                    {others.length > 0 && (
                      <button
                        type="button"
                        class="app-text-button app-artist-slot-more"
                        aria-expanded={more}
                        onClick={() => setExpanded((was) => ({ ...was, [kind]: !was[kind] }))}
                      >
                        {more ? 'Fewer' : `Use another picture (${others.length})`}
                      </button>
                    )}
                  </div>
                  <div class="app-artist-options" role="group" aria-labelledby={`app-artist-slot-${kind}`}>
                    {[...options, ...(more ? others : [])].map((candidate) => {
                      const on = chosen[kind] === candidate.url
                      return (
                        <button
                          key={`${kind}:${candidate.url}`}
                          type="button"
                          class={`app-artist-option${on ? ' is-chosen' : ''}`}
                          aria-pressed={on}
                          aria-label={`${candidate.label}, from ${candidate.source}`}
                          title={`${candidate.label} - ${candidate.source}`}
                          onClick={() => setChosen((was) => toggleChoice(was, kind, candidate.url))}
                        >
                          <img class={box} src={candidate.preview} alt="" loading="lazy" decoding="async" />
                          <span class="app-artist-option-source">
                            {on && <CheckIcon class="app-artist-option-tick" />}
                            {candidate.source}
                          </span>
                        </button>
                      )
                    })}
                    {options.length === 0 && !more && existing && preview.path && (
                      <img class={`${box} is-existing`} src={artistArtUrl(preview.path, kind, version)} alt={`${label} on disk`} />
                    )}
                  </div>
                </section>
              )
            })}
          </>
        ) : null}
      </div>
      <footer class="app-artist-panel-foot">
        <label class="app-artist-replace">
          <input
            type="checkbox"
            class="app-artist-replace-box"
            checked={replace}
            onChange={(event) => setReplace((event.currentTarget as HTMLInputElement).checked)}
          />
          <span>Replace pictures that are already there</span>
        </label>
        <p class="app-artist-panel-said" role="status" aria-live="polite">{saved ?? ''}</p>
        <button
          type="button"
          class={`pl-pill is-primary app-artist-panel-primary${saving ? ' is-busy' : ''}`}
          disabled={!canSave}
          aria-disabled={saving ? 'true' : undefined}
          aria-busy={saving}
          onClick={() => void save()}
        >
          {saving ? 'Saving…' : 'Save'}
        </button>
      </footer>
    </>
  )
}

/**
 * Which artist is this? - the picker's MusicBrainz artist search on its own, for a page that says
 * MusicBrainz doesn't know who this is (the eight acts called Nirvana; files tagged by something
 * else): every artist going by the name - or one an alias of theirs matches ("as Kanye West") - with
 * what tells them apart. Choosing one gives the page their id, for this visit: their albums, who they
 * are, their pictures.
 */
export function WhoBody({ request, live, onClose }: { request: ArtistManageRequest; live: boolean; onClose: () => void }) {
  const [query, setQuery] = useState(request.name)
  const [matches, setMatches] = useState<ArtistMatch[] | null>(null)
  const [note, setNote] = useState<string | null>(null)
  const [searching, setSearching] = useState(false)
  const asks = useMemo(latestOnly, [])

  const search = (wanted: string) => {
    const text = wanted.trim()
    if (!text) return
    const ticket = asks.begin()
    setSearching(true)
    setNote(null)
    searchArtists(text, ticket.signal).then(
      (found) => {
        if (!ticket.current()) return
        setSearching(false)
        setMatches(found.matches)
        if (!found.matches.length) setNote(`Nothing in MusicBrainz goes by "${text}".`)
      },
      (caught: unknown) => {
        if (!ticket.current() || isAbort(caught)) return
        setSearching(false)
        setNote(message(caught, "MusicBrainz couldn't be reached."))
      },
    )
  }

  //? asked as it opens, for the page's own name - the question it is there to answer
  useEffect(() => {
    search(request.name)
    return () => asks.supersede()
  }, [])

  useEffect(() => {
    if (!live) asks.supersede()
  }, [live])

  const pick = (match: ArtistMatch) => {
    request.onChosen?.({ mbid: match.mbid, name: match.name, disambiguation: match.disambiguation })
    onClose()
  }

  return (
    <div class="app-artist-panel-body" tabIndex={-1} aria-busy={searching}>
      <p class="app-artist-panel-note">
        MusicBrainz knows several artists by names like this, or none from your files. Choose who {request.name} is,
        and the page shows their albums and who they are - for this visit. The release editor writes who an album is
        by into its files.
      </p>
      <form class="app-artist-search" role="search" onSubmit={(event) => { event.preventDefault(); search(query) }}>
        <label class="app-artist-search-label" for="app-artist-who-query">Search MusicBrainz for an artist</label>
        <div class="app-artist-search-row">
          <input
            id="app-artist-who-query"
            class="app-artist-search-input"
            type="search"
            value={query}
            autoComplete="off"
            onInput={(event) => setQuery((event.currentTarget as HTMLInputElement).value)}
          />
          <button type="submit" class={`pl-pill${searching ? ' is-busy' : ''}`} aria-busy={searching} disabled={!query.trim()}>Search</button>
        </div>
      </form>
      {searching && matches === null ? (
        <div class="app-asking" role="status">
          <span class="app-sweep" aria-hidden="true" />
          <span class="app-asking-text">Searching MusicBrainz…</span>
        </div>
      ) : null}
      {note && <p class="app-artist-panel-note">{note}</p>}
      {matches && matches.length > 0 && <MatchList matches={matches} label="Artists going by this name" onPick={pick} />}
    </div>
  )
}

/** MusicBrainz's artists for a name, one row each: who they are, a tap to take them. */
export function MatchList({ matches, label, onPick }: { matches: readonly ArtistMatch[]; label: string; onPick: (match: ArtistMatch) => void }) {
  return (
    <ul class="app-group app-artist-matches" aria-label={label}>
      {matches.map((match) => {
        const line = matchLine(match)
        return (
          <li key={match.mbid}>
            <button type="button" class="app-row app-link-row app-artist-match" onClick={() => onPick(match)}>
              <span class="app-artist-match-name" dir="auto">{match.name}</span>
              {line && <span class="app-artist-match-line">{line}</span>}
            </button>
          </li>
        )
      })}
    </ul>
  )
}
