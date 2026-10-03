import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { ARTIST_ORDERS, ArtistsView, SongsView, countText, type ArtistOrder } from '../app/LibraryViews'
import { chooseLibrary, onLibraryLeaving, setLibrarySongs, useLibraryPick } from '../app/libraryPick'
import { useFrame } from '../app/useFrame'
import { usePaged } from '../app/usePaged'
import { LIBRARY_TITLES, shownPick, type LibraryPick } from '../lib/appFrame'
import { latestOnly } from '../lib/latest'
import { readPlayerOrder, writePlayerOrder, type LibraryView } from '../state/persisted'
import { PAGE_SIZE, albumPage, dropPrefetch, librarySongs, prefetchAlbum, type Album, type AlbumOrder, type Artist } from './api'
import { Cover } from './Cover'
import { ChevronDownIcon } from './icons'

const ORDERS: { id: AlbumOrder; label: string }[] = [
  { id: 'newest', label: 'Recently added' },
  { id: 'recent', label: 'Recently played' },
  { id: 'alphabeticalByArtist', label: 'Artist' },
  { id: 'alphabeticalByName', label: 'Title' },
]

const VIEWS: { id: LibraryView; label: string }[] = [
  { id: 'albums', label: 'Albums' },
  { id: 'artists', label: 'Artists' },
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
function AlbumsView({ order, onOpen, onCount }: { order: AlbumOrder; onOpen: (album: Album) => void; onCount: (count: number | null) => void }) {
  const albums = usePaged<Album>((offset, signal) => albumPage(order, offset, signal), PAGE_SIZE, order)

  useEffect(() => {
    onCount(albums.done ? albums.items.length : null)
  }, [albums.done, albums.items.length])

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
      {!albums.error && !albums.loading && !albums.items.length && (
        <p class="pl-notice">{order === 'recent' ? 'Nothing played yet.' : 'No albums in Navidrome yet.'}</p>
      )}
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
 * Tiles and rows navigate; nothing here plays (see "The one app" in CLAUDE.md).
 */
export function Library({ onOpen, onOpenArtist }: { onOpen: (album: Album) => void; onOpenArtist: (artist: Artist) => void }) {
  //? what shows is the store's (app/libraryPick.ts): chosen by the chips here, or the desktop sidebar -
  //? and so is whether Navidrome's empty search lists songs, which both leave Songs out without
  const { pick, hasSongs } = useLibraryPick()
  const desktop = useFrame().frame === 'desktop'
  const [order, setOrder] = useState<AlbumOrder>(savedOrder)
  const [artistOrder, setArtistOrder] = useState<ArtistOrder>('name')
  const [counts, setCounts] = useState<Record<LibraryPick, number | null>>({ recent: null, albums: null, artists: null, songs: null })
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
  //? songs view chosen on this device, Navidrome turning out to list none: the albums
  const view: LibraryView = pick === 'recent' ? 'albums' : pick
  const showing: LibraryView = view === 'songs' && hasSongs === false ? 'albums' : view
  const views = VIEWS.filter((entry) => entry.id !== 'songs' || hasSongs !== false)
  //? what is drawn: the view showing - or on a desktop "Recently added" (lib/appFrame.ts's shownPick)
  const drawn: LibraryPick = shownPick(pick, hasSongs, desktop ? 'desktop' : 'phone')
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

  const choose = (next: LibraryView) => {
    if (next !== showing) chooseLibrary(next)
  }

  const counted = (which: LibraryPick) => (count: number | null) => setCounts((before) => (before[which] === count ? before : { ...before, [which]: count }))
  const onAlbumsCount = useMemo(() => counted('albums'), [])
  const onRecentCount = useMemo(() => counted('recent'), [])
  const onArtistsCount = useMemo(() => counted('artists'), [])
  const onSongsCount = useMemo(() => counted('songs'), [])

  const sorts =
    drawn === 'albums'
      ? { label: 'Album order', value: order, options: ORDERS, change: (next: string) => {
          writePlayerOrder(next)
          setOrder(next as AlbumOrder)
        } }
      : drawn === 'artists'
        ? { label: 'Artist order', value: artistOrder, options: ARTIST_ORDERS, change: (next: string) => setArtistOrder(next as ArtistOrder) }
        : null
  const count =
    drawn === 'albums' || drawn === 'recent' ? countText(counts[drawn], 'album', 'albums')
      : drawn === 'artists' ? countText(counts.artists, 'artist', 'artists')
        : countText(counts.songs, 'song', 'songs')

  return (
    <section class="pl-library" ref={page}>
      <header class="pl-large-header">
        <h1 class="pl-large-title">{desktop ? LIBRARY_TITLES[drawn] : 'Library'}</h1>
      </header>

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
          <AlbumsView order={order} onOpen={onOpen} onCount={onAlbumsCount} />
        </div>
      )}
      {/* the desktop sidebar's "Recently added": the albums newest first, beside the Albums view */}
      {(visited.has('recent') || drawn === 'recent') && (
        <div hidden={drawn !== 'recent'}>
          <AlbumsView order="newest" onOpen={onOpen} onCount={onRecentCount} />
        </div>
      )}
      {(visited.has('artists') || drawn === 'artists') && (
        <div hidden={drawn !== 'artists'}>
          <ArtistsView order={artistOrder} shown={drawn === 'artists'} onOpenArtist={onOpenArtist} onCount={onArtistsCount} />
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
