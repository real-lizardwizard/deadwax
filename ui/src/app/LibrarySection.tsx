import type { JSX } from 'preact'
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { libraryTitle, type LibraryPick } from '../lib/appFrame'
import { countText, type ArtistOrder, ARTIST_ORDERS } from '../lib/artistPage'
import { isAbort, latestOnly } from '../lib/latest'
import { newMarks } from '../lib/myLibrary'
import {
  ALBUM_SORTS, albumSortFrom, artistOrderFrom, filterAlbums, filterArtists, filteredCountText, finding, groupAlbums, groupArtists,
  indexEntries, indexKind, noMatchText, showsIndex, sortAlbums, sortArtistsBy, type AlbumSort,
} from '../lib/shelves'
import { EMPTY_LIBRARY, NOTHING_OF_YOURS_PLAYED, NO_ARTISTS_OF_YOURS, yourArtists, yourEmptyNotice } from '../lib/yourLibrary'
import { libraryArtists, type Album, type Artist, type Song } from '../player/api'
import { ChevronDownIcon, ChevronLeftIcon, SearchIcon } from '../player/icons'
import { readPlayerArtistOrder, readPlayerOrder, writePlayerArtistOrder, writePlayerOrder } from '../state/persisted'
import { AlbumTile } from './AlbumTile'
import { albumIndex, keptIndex, refreshIfOld, useIndexGeneration, type AlbumIndex, type Scope } from './albumIndex'
import { usePlayerActions } from './context'
import { ArtistRow, EmptyLibrary, SongsView } from './LibraryViews'
import { Shelf } from './Shelf'
import { ShuffleSongs } from './ShuffleSongs'
import { useMyLibrary } from './useMyLibrary'
import { useYourAlbumsGeneration, yourAlbums } from './useYourAlbums'
import { errorNote } from './ErrorNote'


/** What the Library says above a list it couldn't refresh - the list it has stays drawn. */
/** (2.0.4) over what went wrong asking again - the list below stays as it was */
export const COULDNT_REFRESH = "Couldn't update this list - showing it as it was."
/** ...and above a list cut at the route's cap (src/routes/navidrome.py INDEX_MAX). */
export const TRUNCATED_NOTICE = 'Showing the first 10000 albums - deadwax reads at most that many.'

/* ===== the sorts, one per device, shared by every section that shows them ===== */

let albumSortNow: AlbumSort | null = null
let artistOrderNow: ArtistOrder | null = null
const sortListeners = new Set<() => void>()

function useSorts(): { album: AlbumSort; artist: ArtistOrder; chooseAlbum: (next: AlbumSort) => void; chooseArtist: (next: ArtistOrder) => void } {
  const [, setSeen] = useState(0)
  useEffect(() => {
    const listener = () => setSeen((count) => count + 1)
    sortListeners.add(listener)
    return () => {
      sortListeners.delete(listener)
    }
  }, [])
  if (albumSortNow === null) albumSortNow = albumSortFrom(readPlayerOrder())
  if (artistOrderNow === null) artistOrderNow = artistOrderFrom(readPlayerArtistOrder())
  const tell = () => {
    for (const listener of [...sortListeners]) listener()
  }
  return {
    album: albumSortNow,
    artist: artistOrderNow,
    chooseAlbum: (next) => {
      writePlayerOrder(next)
      albumSortNow = next
      tell()
    },
    chooseArtist: (next) => {
      writePlayerArtistOrder(next)
      artistOrderNow = next
      tell()
    },
  }
}

/* ===== the head: the bar (a page's), the title, Find, the sort and the count ===== */

interface SortChoice {
  label: string
  value: string
  options: readonly { id: string; label: string }[]
  change: (next: string) => void
}

function SectionHead({ page, title, titleRef, find, sort, count }: {
  page: { onBack: () => void; backLabel: string } | null
  title: string
  titleRef: { current: HTMLHeadingElement | null }
  find: { value: string; placeholder: string; change: (next: string) => void } | null
  sort: SortChoice | null
  count: string
}) {
  return (
    <>
      {page && (
        <header class="pl-nav-bar">
          <button type="button" class="pl-back" onClick={page.onBack}>
            <ChevronLeftIcon class="pl-back-icon" />
            <span class="pl-back-label">{page.backLabel}</span>
          </button>
        </header>
      )}
      <header class="pl-large-header">
        <h1 class="pl-large-title" ref={titleRef} tabIndex={-1}>{title}</h1>
      </header>
      <div class="app-library-bar">
        {find && (
          <label class="app-search-field app-library-find">
            <SearchIcon class="app-search-icon" />
            <input
              type="search"
              class="app-search-input"
              placeholder={find.placeholder}
              aria-label={find.placeholder}
              value={find.value}
              enterKeyHint="search"
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="none"
              spellcheck={false}
              onInput={(event) => find.change((event.currentTarget as HTMLInputElement).value)}
              onKeyDown={(event) => {
                if (event.key === 'Escape' && find.value) {
                  event.preventDefault()
                  find.change('')
                }
              }}
            />
          </label>
        )}
        {sort ? (
          <label class="app-sort">
            <span class="app-sort-value">{sort.options.find((option) => option.id === sort.value)?.label}</span>
            <ChevronDownIcon class="app-sort-icon" />
            <select
              class="app-sort-select"
              aria-label={sort.label}
              value={sort.value}
              onChange={(event) => sort.change((event.currentTarget as HTMLSelectElement).value)}
            >
              {sort.options.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
        ) : (
          <span />
        )}
        <span class="app-library-count app-mono">{count}</span>
      </div>
    </>
  )
}

/** Find typed into, or another order chosen: the section brought back to its top, so what is found - or the list's
 *  start - is what shows. */
function backToTop(section: HTMLElement | null): void {
  if (section && section.getClientRects().length > 0 && window.scrollY > 0) window.scrollTo(0, 0)
}

export interface SectionProps {
  /** the view drawn - already through lib/appFrame.ts shownPick */
  id: LibraryPick
  /** a library of your own (useMyLibrary's hasLibrary) */
  personal: boolean
  /** the section is what shows: its page on top of the tab showing, or a desktop's view drawn - with the app in front */
  shown: boolean
  onOpen: (album: Album) => void
  onOpenArtist: (artist: Artist) => void
  onSongMenu?: ((song: Song, event: MouseEvent) => void) | undefined
  /** your library empty: Browse the store */
  onBrowse: () => void
  /** drawn as a page (a phone's, or one reached by its address): its back bar - null at a desktop's Library root */
  page?: { onBack: () => void; backLabel: string } | null
}

/**
 * A section of the Library (2.0.0-player.59, a better Library) - Your albums, Recently added, Albums in the store,
 * Your artists, Artists in the store, Songs - one component for every one, drawn as a PAGE on a phone (pushed from
 * the Library's root, `#/library/section/<id>`) and INLINE at a desktop's Library root for the sidebar's pick. Top to
 * bottom: a page's back bar, the title (libraryTitle's words), Find (albums and artists), the sort (where there is
 * more than one order) and the count on one bar, and the shelf - the grid or the list, in blocks under their headers,
 * with the index down the right edge when the sort has one (app/Shelf.tsx, lib/shelves.ts).
 *
 * The albums are ONE list per scope (app/albumIndex.ts: yours, or the store's), in hand whole and sorted here, so
 * the count is known at once and Find filters in place; a list asked again (an Add, a Remove, older than a minute as
 * the section shows) swaps in where the old one was - never emptied, the scroll kept. A page takes focus as it
 * mounts, but only when focus has fallen to the page or into the hidden root. Tiles and rows navigate; a song row's
 * ••• opens Up Next's song menu; the Shuffles are app/ShuffleSongs.tsx's, handed the ActionsContext object as one.
 * Nothing here names a playback action.
 */
export function LibrarySection(props: SectionProps) {
  const title = useRef<HTMLHeadingElement>(null)
  const page = props.page ?? null
  useLayoutEffect(() => {
    if (!page) return
    const active = document.activeElement as HTMLElement | null
    if (active && active !== document.body && !active.closest('[hidden]')) return
    title.current?.focus({ preventScroll: true })
  }, [])
  const id = props.id
  return id === 'songs' ? <SongSection {...props} titleRef={title} />
    : id === 'artists' || id === 'storeArtists' ? <ArtistSection {...props} titleRef={title} />
      : <AlbumSection {...props} titleRef={title} />
}

type Inner = SectionProps & { titleRef: { current: HTMLHeadingElement | null } }

/* ===== albums: Your albums, Recently added, Albums in the store ===== */

function AlbumSection({ id, personal, shown, onOpen, onBrowse, page, titleRef }: Inner) {
  const actions = usePlayerActions()
  const section = useRef<HTMLElement>(null)
  //? yours with a library of your own - Your albums and your Recently added; the store's otherwise
  const scope: Scope = id === 'store' || !personal ? 'store' : 'yours'
  const yoursGeneration = useYourAlbumsGeneration()
  const storeGeneration = useIndexGeneration('store')
  const generation = scope === 'yours' ? yoursGeneration : storeGeneration
  const [index, setIndex] = useState<AlbumIndex | null>(() => keptIndex(scope))
  const [problem, setProblem] = useState<unknown>(null)
  const asks = useMemo(latestOnly, [])
  const sorts = useSorts()
  //? Recently added has its own order, and no choice of another
  const sort: AlbumSort = id === 'recent' ? 'newest' : sorts.album
  const [typed, setTyped] = useState('')
  const mine = useMyLibrary()
  const marks = useMemo(() => newMarks(mine), [mine])

  const load = () => {
    const request = asks.begin()
    setProblem(null)
    albumIndex(scope).then(
      (list) => {
        if (request.current()) setIndex(list)
      },
      (reason: unknown) => {
        if (request.current() && !isAbort(reason)) setProblem(reason)
      },
    )
  }
  //? as it shows (mounting shown, a desktop's pick coming back to it, Back to it): asked again if over a minute old
  useEffect(() => {
    if (shown) refreshIfOld(scope)
  }, [shown])
  useEffect(load, [scope, generation])
  useEffect(() => () => asks.supersede(), [])

  const albums = index?.albums ?? null
  const sorted = useMemo(() => (albums ? sortAlbums(albums, sort) : []), [albums, sort])
  const found = useMemo(() => (finding(typed) ? filterAlbums(sorted, typed) : sorted), [sorted, typed])
  const groups = useMemo(() => groupAlbums(found, sort), [found, sort])
  const entries = useMemo(() => (showsIndex(sort, sorted.length, typed) ? indexEntries(groups, sort) : null), [groups, sort, sorted.length, typed])
  const item = useCallback((album: Album) => <AlbumTile key={album.id} album={album} marks={marks} onOpen={onOpen} />, [marks, onOpen])
  const itemKey = useCallback((album: Album) => album.id, [])

  const count = !albums ? '' : finding(typed) ? filteredCountText(found.length, sorted.length, 'album', 'albums') : countText(sorted.length, 'album', 'albums')
  const notice = scope === 'yours' && albums && !sorted.length ? yourEmptyNotice(sort, albums.length) : null

  let body: JSX.Element
  if (!albums) {
    body = problem ? (
      <div class="pl-notice">
        {errorNote(problem, { retry: true })}
        <button type="button" class="pl-text-button" onClick={load}>
          Try again
        </button>
      </div>
    ) : <div class="pl-spinner" aria-label="Loading" />
  } else if (!sorted.length) {
    //? (2.0.0-player.52) your library empty - Ethan's, at first: what to do about it, in any order; a library with
    //? albums, none played, says so under the played sorts
    body = scope === 'yours' ? (
      notice === 'empty' ? <EmptyLibrary lead={EMPTY_LIBRARY} onBrowse={onBrowse} />
        : notice === 'unplayed' ? <p class="pl-notice">{NOTHING_OF_YOURS_PLAYED}</p>
          : <span />
    ) : (
      <p class="pl-notice">{albums.length && (sort === 'recent' || sort === 'frequent') ? 'Nothing played yet.' : 'No albums in Navidrome yet.'}</p>
    )
  } else if (!found.length) {
    body = <p class="pl-notice">{noMatchText('albums', typed)}</p>
  } else {
    body = <Shelf kind="grid" groups={groups} index={entries} years={indexKind(sort) === 'decades'} item={item} itemKey={itemKey} />
  }

  return (
    <section class="pl-library app-library-section" data-section={id} ref={section}>
      <SectionHead
        page={page ?? null}
        title={libraryTitle(id, personal)}
        titleRef={titleRef}
        find={{
          value: typed,
          placeholder: 'Find in albums',
          change: (next) => {
            setTyped(next)
            backToTop(section.current)
          },
        }}
        sort={id === 'recent' ? null : {
          label: 'Album order',
          value: sort,
          options: ALBUM_SORTS,
          //? another order is another list: from its top, as Find's is
          change: (next) => {
            sorts.chooseAlbum(albumSortFrom(next))
            backToTop(section.current)
          },
        }}
        count={count}
      />
      {/* (2.0.0-player.57, Part B) your whole library, shuffled - at the top of your albums */}
      {personal && id === 'albums' && <ShuffleSongs scope="yours" shown={shown} actions={actions} count />}
      {albums && problem && (
        <div class="pl-notice app-library-problem">
          <p>{COULDNT_REFRESH}</p>
          {errorNote(problem, { retry: true })}
          <button type="button" class="pl-text-button" onClick={load}>
            Try again
          </button>
        </div>
      )}
      {index?.truncated && <p class="pl-notice">{TRUNCATED_NOTICE}</p>}
      {body}
    </section>
  )
}

/* ===== artists: Your artists, Artists in the store ===== */

function ArtistSection({ id, personal, shown, onOpenArtist, onBrowse, page, titleRef }: Inner) {
  const section = useRef<HTMLElement>(null)
  //? (2.0.0-player.52) Your artists - the artists of your albums, counting yours - or Browse's, counted "in the store"
  const yours = personal && id === 'artists'
  const inStore = personal && id === 'storeArtists'
  const [artists, setArtists] = useState<Artist[] | null>(null)
  const [problem, setProblem] = useState<unknown>(null)
  const asks = useMemo(latestOnly, [])
  const generation = useYourAlbumsGeneration()
  const sorts = useSorts()
  const order = sorts.artist
  const [typed, setTyped] = useState('')

  const load = () => {
    const request = asks.begin()
    setProblem(null)
    const asking = yours
      ? Promise.all([libraryArtists(true), yourAlbums()]).then(([every, albums]) => yourArtists(every, albums))
      : libraryArtists(true)
    asking.then(
      (list) => {
        if (request.current()) setArtists(list)
      },
      (reason: unknown) => {
        if (request.current() && !isAbort(reason)) setProblem(reason)
      },
    )
  }
  //? getArtists asked as it shows, and once more each time it shows again (as Library > Artists always was) - and
  //? Your artists again as your albums change
  useEffect(() => {
    if (!shown) return
    if (yours) refreshIfOld('yours')
    load()
  }, [shown, yours ? generation : 0])
  useEffect(() => () => asks.supersede(), [])

  const sorted = useMemo(() => (artists ? sortArtistsBy(artists, order) : []), [artists, order])
  const found = useMemo(() => (finding(typed) ? filterArtists(sorted, typed) : sorted), [sorted, typed])
  const groups = useMemo(() => groupArtists(found, order), [found, order])
  const entries = useMemo(() => (showsIndex(order, sorted.length, typed) ? indexEntries(groups, order) : null), [groups, order, sorted.length, typed])
  const item = useCallback((artist: Artist) => <ArtistRow artist={artist} inStore={inStore} onOpenArtist={onOpenArtist} />, [inStore, onOpenArtist])
  const itemKey = useCallback((artist: Artist) => artist.id, [])

  const count = !artists ? '' : finding(typed) ? filteredCountText(found.length, sorted.length, 'artist', 'artists') : countText(sorted.length, 'artist', 'artists')

  let body: JSX.Element
  if (!artists) {
    body = problem ? (
      <div class="pl-notice">
        {errorNote(problem, { retry: true })}
        <button type="button" class="pl-text-button" onClick={load}>
          Try again
        </button>
      </div>
    ) : <div class="pl-spinner" aria-label="Loading" />
  } else if (!sorted.length) {
    body = yours ? <EmptyLibrary lead={NO_ARTISTS_OF_YOURS} onBrowse={onBrowse} /> : <p class="pl-notice">No artists in Navidrome yet.</p>
  } else if (!found.length) {
    body = <p class="pl-notice">{noMatchText('artists', typed)}</p>
  } else {
    body = <Shelf kind="list" groups={groups} index={entries} item={item} itemKey={itemKey} />
  }

  return (
    <section class="pl-library app-library-section" data-section={id} ref={section}>
      <SectionHead
        page={page ?? null}
        title={libraryTitle(id, personal)}
        titleRef={titleRef}
        find={{
          value: typed,
          placeholder: 'Find in artists',
          change: (next) => {
            setTyped(next)
            backToTop(section.current)
          },
        }}
        sort={{
          label: 'Artist order',
          value: order,
          options: ARTIST_ORDERS,
          change: (next) => {
            sorts.chooseArtist(artistOrderFrom(next))
            backToTop(section.current)
          },
        }}
        count={count}
      />
      {artists && problem && (
        <div class="pl-notice app-library-problem">
          <p>{COULDNT_REFRESH}</p>
          {errorNote(problem, { retry: true })}
          <button type="button" class="pl-text-button" onClick={load}>
            Try again
          </button>
        </div>
      )}
      {body}
    </section>
  )
}

/* ===== songs: the store's, in Navidrome's order ===== */

function SongSection({ id, personal, shown, onOpen, onSongMenu, page, titleRef }: Inner) {
  const actions = usePlayerActions()
  const [songs, setSongs] = useState<number | null>(null)
  return (
    <section class="pl-library app-library-section" data-section={id}>
      <SectionHead page={page ?? null} title={libraryTitle(id, personal)} titleRef={titleRef} find={null} sort={null} count={countText(songs, 'song', 'songs')} />
      {/* (2.0.0-player.57, Part B) every song, shuffled - the store's (Browse) with a library of your own, else the
          library's, which is the store */}
      <ShuffleSongs scope={personal ? 'store' : 'yours'} shown={shown} actions={actions} />
      <SongsView onOpen={onOpen} onCount={setSongs} onSongMenu={onSongMenu} />
    </section>
  )
}
