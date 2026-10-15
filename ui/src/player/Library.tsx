import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { ARTIST_ORDERS, ArtistsView, EmptyLibrary, SongsView, countText, type ArtistOrder } from '../app/LibraryViews'
import { chooseLibrary, onLibraryLeaving, setLibrarySongs, useLibraryPick } from '../app/libraryPick'
import { useFrame } from '../app/useFrame'
import { hasLibrary, useMyLibrary } from '../app/useMyLibrary'
import { usePaged } from '../app/usePaged'
import { forgetYourAlbums, useYourAlbumsGeneration, yourAlbums, yourAlbumsPage } from '../app/useYourAlbums'
import { isBrowse, libraryTitle, shownPick, type LibraryPick } from '../lib/appFrame'
import { latestOnly } from '../lib/latest'
import { isNew, newMarks } from '../lib/myLibrary'
import { EMPTY_LIBRARY, NOTHING_OF_YOURS_PLAYED, yourEmptyNotice } from '../lib/yourLibrary'
import { readPlayerOrder, writePlayerOrder } from '../state/persisted'
import { PAGE_SIZE, albumPage, dropPrefetch, librarySongs, prefetchAlbum, type Album, type AlbumOrder, type Artist } from './api'
import { Cover } from './Cover'
import { ChevronDownIcon } from './icons'

const ORDERS: { id: AlbumOrder; label: string }[] = [
  { id: 'newest', label: 'Recently added' },
  { id: 'recent', label: 'Recently played' },
  { id: 'alphabeticalByArtist', label: 'Artist' },
  { id: 'alphabeticalByName', label: 'Title' },
]

const VIEWS: { id: LibraryPick; label: string }[] = [
  { id: 'albums', label: 'Albums' },
  { id: 'artists', label: 'Artists' },
  { id: 'songs', label: 'Songs' },
]

//? (2.0.0-player.52) with a library of your own: yours, and Browse's - the store's
const YOUR_VIEWS: { id: LibraryPick; label: string }[] = [
  { id: 'albums', label: 'Albums' },
  { id: 'artists', label: 'Artists' },
]
const BROWSE_VIEWS: { id: LibraryPick; label: string }[] = [
  { id: 'store', label: 'Albums' },
  { id: 'storeArtists', label: 'Artists' },
  { id: 'songs', label: 'Songs' },
]

function savedOrder(): AlbumOrder {
  const saved = readPlayerOrder()
  return ORDERS.find((order) => order.id === saved)?.id ?? 'newest'
}

/**
 * Every album, a page at a time, in the order chosen (lib's usePaged, the code this file always had):
 * a grid of tiles, each OPENING its album - asking for its songs as the finger lands, so Play is
 * usually ready by the time the page opens; a press that turns into a scroll lets go of the ask.
 */
function AlbumsView({
  order,
  onOpen,
  onCount,
  yours = false,
  onBrowse,
}: {
  order: AlbumOrder
  onOpen: (album: Album) => void
  onCount: (count: number | null) => void
  /** (2.0.0-player.52) your albums - your starred albums, all asked for and put in order here - not the store's */
  yours?: boolean
  /** your library empty: Browse the store */
  onBrowse?: () => void
}) {
  const generation = useYourAlbumsGeneration()
  const albums = usePaged<Album>(
    (offset, signal) => (yours ? yourAlbumsPage(order, offset, PAGE_SIZE) : albumPage(order, offset, signal)),
    PAGE_SIZE,
    yours ? `yours:${order}:${generation}` : order,
  )
  //? (2.0.0-player.51) what is new in your library is marked New until you open it - with logins on only
  const marks = newMarks(useMyLibrary())
  //? (review) your albums drawn empty: how many you have at all - Recently played leaves out the unplayed, and
  //? an empty library says so in any order (yourEmptyNotice), from the one list your albums came from
  const [yoursCount, setYoursCount] = useState<number | null>(null)
  const counting = useMemo(latestOnly, [])
  const emptyOfYours = yours && albums.done && !albums.error && !albums.items.length

  useEffect(() => {
    onCount(albums.done ? albums.items.length : null)
  }, [albums.done, albums.items.length])

  useEffect(() => {
    if (!emptyOfYours) return
    const request = counting.begin()
    yourAlbums().then(
      (every) => {
        if (request.current()) setYoursCount(every.length)
      },
      () => {
        if (request.current()) setYoursCount(null)
      },
    )
    return () => counting.supersede()
  }, [emptyOfYours, generation])
  const notice = emptyOfYours ? yourEmptyNotice(order, yoursCount) : null

  return (
    <>
      <div class="pl-grid">
        {albums.items.map((album) => (
          <button
            key={album.id}
            type="button"
            class="pl-album"
            //? the album's songs asked for as the finger lands, so Play is usually ready by the time
            //? the page opens; a press that turns into a scroll lets go of the ask (api.ts)
            onPointerDown={() => prefetchAlbum(album.id)}
            onPointerCancel={() => dropPrefetch(album.id)}
            onClick={() => onOpen(album)}
          >
            <Cover id={album.coverArt} size={400} class="pl-album-cover" />
            <span class="pl-album-title">{album.name}</span>
            <span class="pl-album-artist">{album.artist}</span>
            {isNew(marks, album) && (
              <span class="pl-album-new">
                New<span class="app-visually-hidden"> in your library</span>
              </span>
            )}
          </button>
        ))}
      </div>

      {albums.error && (
        <div class="pl-notice">
          <p>{albums.error}</p>
          <button type="button" class="pl-text-button" onClick={albums.retry}>
            Try again
          </button>
        </div>
      )}
      {!albums.error && !albums.loading && !albums.items.length && (yours ? (
        //? (2.0.0-player.52) your library empty - Ethan's, at first: what to do about it, in any order; only a
        //? library with albums, none played, says so under Recently played
        notice === 'empty' ? (
          <EmptyLibrary lead={EMPTY_LIBRARY} onBrowse={onBrowse} />
        ) : notice === 'unplayed' ? (
          <p class="pl-notice">{NOTHING_OF_YOURS_PLAYED}</p>
        ) : null
      ) : (
        <p class="pl-notice">{order === 'recent' ? 'Nothing played yet.' : 'No albums in Navidrome yet.'}</p>
      ))}
      {albums.loading && <div class="pl-spinner" aria-label="Loading" />}
      <div ref={albums.sentinel} class="pl-sentinel" />
    </>
  )
}

/**
 * The Library tab: Albums, Artists or Songs (2.0.0-player.17, as Library.dc.html draws them), and a
 * sort under them.
 *
 *  - ALBUMS: the grid, in one of four orders - Recently added, Recently played, Artist, Title - a
 *    page at a time.
 *  - ARTISTS: every artist Navidrome has (getArtists), by name or by how many albums of theirs you
 *    have, each opening their page.
 *  - SONGS: every song (search3 with an empty query, a page at a time), each opening its album. The
 *    chip is left out when Navidrome's empty search finds nothing - asked once, as the tab is first
 *    drawn, for a single song - since a Navidrome that won't list songs that way would show an
 *    empty list for a library full of them.
 *
 * The sort is a link-coloured line holding the platform's own picker (iOS's wheel), as the board's
 * "Recently added ▾" draws it, and the count beside it is said once the whole list is in. What is
 * shown, and the albums' order, are kept on this device. Each view is drawn once first chosen and
 * kept, hidden, after - so coming back to one finds it where it was left, scrolled where it was.
 *
 * ON A DESKTOP (2.0.0-player.19) the views are the sidebar's (app/Sidebar.tsx) - so the chips aren't
 * drawn and the title is the view's name, as DesktopLibrary.dc.html has "Albums" - and the sidebar
 * has one more, "Recently added": the albums, newest first, a view of its own beside Albums, so the
 * Albums view keeps the order chosen for it. Which view shows is app/libraryPick.ts's, a store both
 * choose from; a phone shows the albums for "Recently added". A view's scroll is kept as another is
 * chosen, by the chips or the sidebar, and put back as it is chosen again.
 *
 * NEW (2.0.0-player.51, personal libraries): with logins on, an album new in your library - added since
 * you last opened it - carries a New mark on its tile (app/useMyLibrary.ts), gone once you open it.
 *
 * YOUR LIBRARY AND BROWSE (2.0.0-player.52, step 6 of the multi-user plan): with logins on, for somebody with
 * a library of their own (useMyLibrary's hasLibrary - not the break-glass admin), the Library is YOURS - your
 * starred albums in Navidrome, asked as you (app/useYourAlbums.ts), in the four orders (lib/yourLibrary.ts),
 * and Your artists, the artists of them - and BROWSE is the store, every album, artist and song deadwax holds,
 * the views the tab always had. A phone opens on your albums, with a second row of two chips over the views -
 * "Your library" and "Browse" - as the one way to the whole store; a desktop's sidebar lists both, Browse as a
 * group of its own (lib/appFrame.ts). Songs is Browse's: Navidrome lists songs store-wide. An empty library
 * says so, and what to do about it - browse the store (a button, which hands its focus on to Browse), or search
 * - in any order and in Your artists too (review), and an album is added from its page. With logins off - and for the break-glass admin - there is no Browse and no second row: the store is
 * the library, exactly as before.
 *
 * Tiles and rows navigate; nothing here plays (see "The one app" in CLAUDE.md).
 */
export function Library({ onOpen, onOpenArtist }: { onOpen: (album: Album) => void; onOpenArtist: (artist: Artist) => void }) {
  //? what shows is the store's (app/libraryPick.ts): chosen by the chips here, or the desktop sidebar -
  //? and so is whether Navidrome's empty search lists songs, which both leave Songs out without
  const { pick, hasSongs } = useLibraryPick()
  const desktop = useFrame().frame === 'desktop'
  //? (2.0.0-player.52) a library of your own - logins on, signed in through Navidrome: yours, and Browse
  const personal = hasLibrary()
  const [order, setOrder] = useState<AlbumOrder>(savedOrder)
  const [artistOrder, setArtistOrder] = useState<ArtistOrder>('name')
  const [counts, setCounts] = useState<Record<LibraryPick, number | null>>({
    recent: null, albums: null, artists: null, songs: null, store: null, storeArtists: null,
  })
  const probes = useMemo(latestOnly, [])
  //? where each view was scrolled to, as another was chosen
  const scrolled = useRef(new Map<LibraryPick, number>())
  const page = useRef<HTMLElement>(null)

  useEffect(() => {
    const request = probes.begin()
    librarySongs(0, 1, request.signal).then(
      (songs) => {
        if (request.current()) setLibrarySongs(songs.length > 0)
      },
      () => {
        //? a failed ask says nothing: the chip stays, and the view says what went wrong if chosen
        if (request.current()) setLibrarySongs(true)
      },
    )
    return () => probes.supersede()
  }, [])

  //? the phone's chips: the albums for "Recently added", which is the desktop sidebar's - and the
  //? songs view chosen on this device, Navidrome turning out to list none: the albums (the store's, with a
  //? library of your own - Songs is Browse's then)
  const showing: LibraryPick = shownPick(pick, hasSongs, 'phone', personal)
  //? (2.0.0-player.52) whose views the chips are: yours, or Browse's - the store
  const browsing = isBrowse(showing, personal)
  const views = (personal ? (browsing ? BROWSE_VIEWS : YOUR_VIEWS) : VIEWS).filter((entry) => entry.id !== 'songs' || hasSongs !== false)
  //? what is drawn: the view showing - or on a desktop "Recently added" (lib/appFrame.ts's shownPick)
  const drawn: LibraryPick = shownPick(pick, hasSongs, desktop ? 'desktop' : 'phone', personal)

  //? your library's count moving - the starring worker done, a star read back from Amperfy - asks for your
  //? albums again (app/useYourAlbums.ts): the Library asks your library as it shows (App)
  const mine = useMyLibrary()
  const starredCount = mine && mine.on && mine.kept ? mine.starred ?? null : null
  const seenCount = useRef<number | null>(null)
  useEffect(() => {
    if (starredCount === null) return
    if (seenCount.current !== null && seenCount.current !== starredCount) forgetYourAlbums()
    seenCount.current = starredCount
  }, [starredCount])
  const [visited, setVisited] = useState<ReadonlySet<LibraryPick>>(() => new Set([drawn]))
  useEffect(() => {
    setVisited((before) => (before.has(drawn) ? before : new Set(before).add(drawn)))
  }, [drawn])

  //? Only while this tab is the one showing: the sidebar can choose a view from another tab, whose
  //? page the document's scroll belongs to then (App opens the Library at that view's top).
  const onScreen = () => !!page.current && page.current.getClientRects().length > 0
  const drawnNow = useRef(drawn)
  drawnNow.current = drawn
  useEffect(
    () =>
      onLibraryLeaving(() => {
        if (onScreen()) scrolled.current.set(drawnNow.current, window.scrollY)
      }),
    [],
  )
  useLayoutEffect(() => {
    if (onScreen() && scrolled.current.has(drawn)) window.scrollTo(0, scrolled.current.get(drawn)!)
  }, [drawn])

  const choose = (next: LibraryPick) => {
    if (next !== showing) chooseLibrary(next)
  }

  const counted = (which: LibraryPick) => (count: number | null) => setCounts((before) => (before[which] === count ? before : { ...before, [which]: count }))
  const onAlbumsCount = useMemo(() => counted('albums'), [])
  const onRecentCount = useMemo(() => counted('recent'), [])
  const onArtistsCount = useMemo(() => counted('artists'), [])
  const onSongsCount = useMemo(() => counted('songs'), [])
  const onStoreCount = useMemo(() => counted('store'), [])
  const onStoreArtistsCount = useMemo(() => counted('storeArtists'), [])
  //? Browse the store, from your library's empty notice - which the store's view then hides, and the focus
  //? with it: handed on (review) to Browse's chip where it is drawn (a phone's scope row), else to the title
  //? (a desktop's: "Albums in the store") - never left to fall to the page, where a keyboard or VoiceOver
  //? would start again from the top
  const handOn = useRef(false)
  const browseChip = useRef<HTMLButtonElement>(null)
  const title = useRef<HTMLHeadingElement>(null)
  const browse = useMemo(() => () => {
    handOn.current = true
    chooseLibrary('store')
  }, [])
  useLayoutEffect(() => {
    if (!handOn.current || drawn !== 'store') return
    handOn.current = false
    const active = document.activeElement as HTMLElement | null
    if (active && active !== document.body && !active.closest('[hidden]')) return
    const chip = browseChip.current
    ;(chip && chip.getClientRects().length > 0 ? chip : title.current)?.focus({ preventScroll: true })
  }, [drawn])

  const sorts =
    drawn === 'albums' || drawn === 'store'
      ? { label: 'Album order', value: order, options: ORDERS, change: (next: string) => {
          writePlayerOrder(next)
          setOrder(next as AlbumOrder)
        } }
      : drawn === 'artists' || drawn === 'storeArtists'
        ? { label: 'Artist order', value: artistOrder, options: ARTIST_ORDERS, change: (next: string) => setArtistOrder(next as ArtistOrder) }
        : null
  const count =
    drawn === 'albums' || drawn === 'recent' || drawn === 'store' ? countText(counts[drawn], 'album', 'albums')
      : drawn === 'artists' || drawn === 'storeArtists' ? countText(counts[drawn], 'artist', 'artists')
        : countText(counts.songs, 'song', 'songs')

  return (
    <section class="pl-library" ref={page}>
      <header class="pl-large-header">
        <h1 class="pl-large-title" ref={title} tabIndex={-1}>{desktop ? libraryTitle(drawn, personal) : 'Library'}</h1>
      </header>

      {/* (2.0.0-player.52) with a library of your own: yours, or the store - the one way to the whole store */}
      {personal && (
        <div class="app-library-views app-library-scope" role="group" aria-label="Your library or the store">
          <button
            type="button"
            class={`app-chip app-library-view${browsing ? '' : ' is-on'}`}
            aria-pressed={!browsing}
            onClick={() => {
              if (browsing) choose('albums')
            }}
          >
            Your library
          </button>
          <button
            ref={browseChip}
            type="button"
            class={`app-chip app-library-view${browsing ? ' is-on' : ''}`}
            aria-pressed={browsing}
            onClick={() => {
              if (!browsing) choose('store')
            }}
          >
            Browse
          </button>
        </div>
      )}

      <div class="app-library-views" role="group" aria-label="Show">
        {views.map((entry) => (
          <button
            key={entry.id}
            type="button"
            class={`app-chip app-library-view${entry.id === showing ? ' is-on' : ''}`}
            aria-pressed={entry.id === showing}
            onClick={() => choose(entry.id)}
          >
            {entry.label}
          </button>
        ))}
      </div>

      <div class="app-library-bar">
        {sorts ? (
          <label class="app-sort">
            <span class="app-sort-value">{sorts.options.find((option) => option.id === sorts.value)?.label}</span>
            <ChevronDownIcon class="app-sort-icon" />
            <select
              class="app-sort-select"
              aria-label={sorts.label}
              value={sorts.value}
              onChange={(event) => sorts.change((event.currentTarget as HTMLSelectElement).value)}
            >
              {sorts.options.map((option) => (
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

      {(visited.has('albums') || drawn === 'albums') && (
        <div hidden={drawn !== 'albums'}>
          <AlbumsView order={order} onOpen={onOpen} onCount={onAlbumsCount} yours={personal} onBrowse={browse} />
        </div>
      )}
      {/* the desktop sidebar's "Recently added": the albums newest first, beside the Albums view */}
      {(visited.has('recent') || drawn === 'recent') && (
        <div hidden={drawn !== 'recent'}>
          <AlbumsView order="newest" onOpen={onOpen} onCount={onRecentCount} yours={personal} onBrowse={browse} />
        </div>
      )}
      {(visited.has('artists') || drawn === 'artists') && (
        <div hidden={drawn !== 'artists'}>
          <ArtistsView order={artistOrder} shown={drawn === 'artists'} onOpenArtist={onOpenArtist} onCount={onArtistsCount} yours={personal} onBrowse={browse} />
        </div>
      )}
      {/* (2.0.0-player.52) Browse - the store's albums and artists, with a library of your own */}
      {personal && (visited.has('store') || drawn === 'store') && (
        <div hidden={drawn !== 'store'}>
          <AlbumsView order={order} onOpen={onOpen} onCount={onStoreCount} />
        </div>
      )}
      {personal && (visited.has('storeArtists') || drawn === 'storeArtists') && (
        <div hidden={drawn !== 'storeArtists'}>
          <ArtistsView order={artistOrder} shown={drawn === 'storeArtists'} onOpenArtist={onOpenArtist} onCount={onStoreArtistsCount} inStore />
        </div>
      )}
      {(visited.has('songs') || drawn === 'songs') && hasSongs !== false && (
        <div hidden={drawn !== 'songs'}>
          <SongsView onOpen={onOpen} onCount={onSongsCount} />
        </div>
      )}
    </section>
  )
}
