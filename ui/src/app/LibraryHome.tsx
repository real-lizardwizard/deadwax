import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { ALL_MUSIC, browseItems, libraryItems, type LibraryPick, type SidebarItem } from '../lib/appFrame'
import { isAbort, latestOnly } from '../lib/latest'
import { newMarks } from '../lib/myLibrary'
import { sortAlbums } from '../lib/shelves'
import { EMPTY_LIBRARY, NO_ALBUMS } from '../lib/yourLibrary'
import { albumPage, type Album } from '../player/api'
import { AlbumIcon, ArtistIcon, ChevronRightIcon, PlaylistIcon, SongIcon } from '../player/icons'
import { AlbumTile } from './AlbumTile'
import { albumIndex, INDEX_FRESH_MS } from './albumIndex'
import { usePlayerActions } from './context'
import { EmptyLibrary } from './LibraryViews'
import { ShuffleSongs } from './ShuffleSongs'
import { useMyLibrary } from './useMyLibrary'
import { useYourAlbumsGeneration } from './useYourAlbums'
import { errorNote } from './ErrorNote'

/** How many albums the root's Recently added shows - See all opens the rest. */
export const RECENT_ON_ROOT = 12


/**
 * The Library tab's root on a phone (2.0.0-player.59, a better Library) - Apple's list of categories with Recently
 * added under it, in place of the rows of chips:
 *
 *  - the Library's Shuffle (2.0.0-player.57, Part B: your whole library once each, in deadwax's order) at the head of
 *    the first group;
 *  - the first group: .58's Playlists row (its page - never a section), then libraryItems' views - Albums, Artists,
 *    and Songs without a library of your own while Navidrome's empty search lists songs - the desktop sidebar's
 *    Library group, one list in one order (Recently added is the grid below);
 *  - with a library of your own (hasLibrary), a second group under "Browse": browseItems - the store's Albums,
 *    Artists and Songs, the sidebar's Browse group - in place of the "Your library | Browse" chips;
 *  - Recently added: the newest 12 - yours by `created` from app/albumIndex.ts's list, or with logins off (and for
 *    the break-glass admin) ONE getAlbumList2 newest of 12 (the store's whole list is asked for only as a store
 *    section opens) - with See all opening the `recent` section; your library empty, EmptyLibrary. Kept up to date
 *    as the sections are: yours follows the `yours` generation (App's refreshIfOld as the tab shows moves it); the
 *    logins-off 12, which no generation covers, are asked again as the root comes into view (`shown`) once the last
 *    answer is over INDEX_FRESH_MS old - the grid it has kept drawn meanwhile (the review of .59).
 *
 * A row opens its section as a page on the Library tab (`onOpenSection`, App's openSection - pushed, so the edge
 * swipe and Back come back here); a tile opens its album. Nothing here plays: the Shuffle is ShuffleSongs', handed
 * the ActionsContext object as one.
 */
export function LibraryHome({ personal, hasSongs, shown, onOpen, onOpenSection, onOpenPlaylists }: {
  personal: boolean
  hasSongs: boolean | null
  shown: boolean
  onOpen: (album: Album) => void
  onOpenSection: (id: LibraryPick) => void
  onOpenPlaylists: () => void
}) {
  const actions = usePlayerActions()
  const yours = libraryItems(hasSongs, personal).filter((item) => item.id !== 'recent')
  const browse = browseItems(hasSongs, personal)
  const [recent, setRecent] = useState<{ albums: Album[]; empty: boolean } | null>(null)
  const [problem, setProblem] = useState<unknown>(null)
  const asks = useMemo(latestOnly, [])
  const generation = useYourAlbumsGeneration()
  const mine = useMyLibrary()
  const marks = useMemo(() => newMarks(mine), [mine])
  //? when the logins-off 12 last landed
  const landedAt = useRef(0)

  const load = () => {
    const request = asks.begin()
    setProblem(null)
    const asking = personal
      ? albumIndex('yours').then((index) => ({ albums: sortAlbums(index.albums, 'newest').slice(0, RECENT_ON_ROOT), empty: !index.albums.length }))
      : albumPage('newest', 0, request.signal, RECENT_ON_ROOT).then((albums) => ({ albums, empty: !albums.length }))
    asking.then(
      (found) => {
        if (!request.current()) return
        landedAt.current = Date.now()
        setRecent(found)
      },
      (reason: unknown) => {
        if (request.current() && !isAbort(reason)) setProblem(reason)
      },
    )
  }
  useEffect(load, [personal, personal ? generation : 0])
  //? logins off: the 12 asked again as the root shows, once they are over a minute old - as the store's sections are
  useEffect(() => {
    if (shown && !personal && landedAt.current && Date.now() - landedAt.current > INDEX_FRESH_MS) load()
  }, [shown])
  useEffect(() => () => asks.supersede(), [])

  //? the sidebar's own items (lib/appFrame.ts), each a Library view - (2.0.10) with its glyph beside Playlists': a record
  //? for albums, a head and shoulders for artists, a note for songs
  const RowIcon = (pick: string) => (pick === 'artists' || pick === 'storeArtists' ? ArtistIcon : pick === 'songs' ? SongIcon : AlbumIcon)
  const row = (item: SidebarItem) => {
    const Icon = RowIcon(item.id)
    return (
      <button key={item.id} type="button" class="app-row app-link-row app-library-row" onClick={() => onOpenSection(item.id as LibraryPick)}>
        <Icon class="app-library-row-icon" />
        <span class="app-row-label">{item.label}</span>
        <ChevronRightIcon class="app-chevron" />
      </button>
    )
  }

  return (
    <section class="pl-library app-library-home">
      <header class="pl-large-header">
        <h1 class="pl-large-title" tabIndex={-1}>Library</h1>
      </header>

      {/* (2.0.0-player.57, Part B) the whole library, shuffled - at the head of the first group */}
      <ShuffleSongs scope="yours" shown={shown} actions={actions} />
      <div class="app-group app-library-group">
        {/* (2.0.0-player.58) the playlists - their page, not a section; it navigates, and asks nothing */}
        <button type="button" class="app-row app-link-row app-library-row app-library-playlists" onClick={onOpenPlaylists}>
          <PlaylistIcon class="app-library-playlists-icon" />
          <span class="app-row-label">Playlists</span>
          <ChevronRightIcon class="app-chevron" />
        </button>
        {yours.map(row)}
      </div>

      {/* (2.0.0-player.52) with a library of your own: the collection, All music (2.0.5: it was "Browse", over the
          same "Albums, Artists" as yours) - the one way to all of it */}
      {browse.length > 0 && (
        <section class="app-library-browse" aria-labelledby="app-library-browse-title">
          <h2 id="app-library-browse-title" class="app-section-title">
            {ALL_MUSIC}
          </h2>
          <div class="app-group app-library-group">{browse.map(row)}</div>
        </section>
      )}

      <section class="app-library-recent" aria-labelledby="app-library-recent-title">
        <div class="app-section-head app-library-recent-head">
          <h2 id="app-library-recent-title" class="app-section-title">
            Recently added
          </h2>
          <button type="button" class="app-text-button app-see-all" onClick={() => onOpenSection('recent')}>
            See all
          </button>
        </div>
        {!recent ? (
          problem ? (
            <div class="pl-notice">
              {errorNote(problem, { retry: true })}
              <button type="button" class="pl-text-button" onClick={load}>
                Try again
              </button>
            </div>
          ) : <div class="pl-spinner" aria-label="Loading" />
        ) : recent.empty ? (
          personal ? <EmptyLibrary lead={EMPTY_LIBRARY} onBrowse={() => onOpenSection('store')} /> : <p class="pl-notice">{NO_ALBUMS}</p>
        ) : (
          <div class="pl-grid">
            {recent.albums.map((album) => <AlbumTile key={album.id} album={album} marks={marks} onOpen={onOpen} />)}
          </div>
        )}
      </section>
    </section>
  )
}
