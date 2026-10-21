import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { LibraryHome } from '../app/LibraryHome'
import { LibrarySection } from '../app/LibrarySection'
import { chooseLibrary, onLibraryLeaving, setLibrarySongs, useLibraryPick } from '../app/libraryPick'
import { useFrame } from '../app/useFrame'
import { hasLibrary, useMyLibrary } from '../app/useMyLibrary'
import { forgetYourAlbums } from '../app/useYourAlbums'
import { shownPick, type LibraryPick } from '../lib/appFrame'
import { latestOnly } from '../lib/latest'
import { librarySongs, type Album, type Artist, type Song } from './api'

/**
 * The Library tab (2.0.0-player.17; laid out as Apple's since 2.0.0-player.59 - see "A better Library" in
 * notes/app-library.md).
 *
 * ON A PHONE the root is a short list (app/LibraryHome.tsx): the Library's Shuffle, Playlists (its page,
 * 2.0.0-player.58), Albums, Artists - and Songs, with logins off - then, with a library of your own, Browse's group
 * (the store's Albums, Artists and Songs), and Recently added's 12 newest with See all. Each row opens its SECTION as
 * a page on this tab (`onOpenSection`, App's openSection: `#/library/section/<id>`), drawn by app/LibrarySection.tsx -
 * its title, Find, the sort and the count, and the shelf in blocks under its headers with the index down the edge.
 *
 * ON A DESKTOP (2.0.0-player.19) the views are the sidebar's (app/Sidebar.tsx, app/libraryPick.ts - the store both
 * choose from), and the root draws the section for the pick INLINE: no back bar, its title the view's name, Find, the
 * sort and the count on the title's row. Each view is drawn once first chosen and kept, hidden, after - so coming back
 * to one finds it where it was left, scrolled where it was (the scroll kept as another is chosen, put back as it is
 * chosen again).
 *
 * Here on both frames: whether Navidrome's empty search lists songs - asked once, as the tab is first drawn, for a
 * single song - since a Navidrome that won't list songs that way would show an empty list for a library full of them
 * (the Songs row and the sidebar's item are left out then); and (2.0.0-player.52) your library's count moving - the
 * starring worker done, a star read back from Amperfy - asking your albums again (app/useYourAlbums.ts).
 *
 * YOUR LIBRARY AND BROWSE (2.0.0-player.52, step 6 of the multi-user plan): with logins on, for somebody with a
 * library of their own (useMyLibrary's hasLibrary - not the break-glass admin), the Library is YOURS - your starred
 * albums in Navidrome, asked as you, and Your artists, the artists of them - and BROWSE is the store, every album,
 * artist and song deadwax holds. With logins off - and for the break-glass admin - there is no Browse: the store is
 * the library, exactly as before. An empty library says so, and what to do about it - Browse the store (a button,
 * whose focus is handed on to the store's title).
 *
 * NEW (2.0.0-player.51, personal libraries): with logins on, an album new in your library carries a New mark on its
 * tile (app/AlbumTile.tsx), gone once you open it.
 *
 * Tiles and rows navigate; nothing here plays (see "The one app" in CLAUDE.md). A song row's ••• opens App's song
 * menu (`onSongMenu`), and the Shuffles are app/ShuffleSongs.tsx's.
 */
export function Library({ onOpen, onOpenArtist, onOpenPlaylists, onOpenSection, onSongMenu, shown = true }: {
  onOpen: (album: Album) => void
  onOpenArtist: (artist: Artist) => void
  /** (2.0.0-player.58) the Playlists page */
  onOpenPlaylists: () => void
  /** (2.0.0-player.59) a section of the Library, as a page on this tab (a phone's) */
  onOpenSection: (id: LibraryPick) => void
  onSongMenu?: ((song: Song, event: MouseEvent) => void) | undefined
  shown?: boolean
}) {
  //? what shows is the store's (app/libraryPick.ts): chosen by the desktop sidebar - and so is whether Navidrome's
  //? empty search lists songs, which both frames leave Songs out without
  const { pick, hasSongs } = useLibraryPick()
  const desktop = useFrame().frame === 'desktop'
  //? (2.0.0-player.52) a library of your own - logins on, signed in through Navidrome: yours, and Browse
  const personal = hasLibrary()
  const probes = useMemo(latestOnly, [])
  //? where each view was scrolled to, as another was chosen
  const scrolled = useRef(new Map<LibraryPick, number>())
  const page = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const request = probes.begin()
    librarySongs(0, 1, request.signal).then(
      (songs) => {
        if (request.current()) setLibrarySongs(songs.length > 0)
      },
      () => {
        //? a failed ask says nothing: the row stays, and the section says what went wrong if opened
        if (request.current()) setLibrarySongs(true)
      },
    )
    return () => probes.supersede()
  }, [])

  //? what a desktop draws: the view picked - Songs falling back to the albums where Navidrome lists none, Browse's
  //? two the albums and the artists with logins off (lib/appFrame.ts's shownPick)
  const drawn: LibraryPick = shownPick(pick, hasSongs, 'desktop', personal)

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
  //? a desktop's views drawn once first chosen, and kept
  const [visited, setVisited] = useState<readonly LibraryPick[]>(() => [drawn])
  useEffect(() => {
    if (desktop) setVisited((before) => (before.includes(drawn) ? before : [...before, drawn]))
  }, [drawn, desktop])

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

  //? Browse the store, from your library's empty notice on a desktop - which the store's view then hides, and the
  //? focus with it: handed on (review) to the store's title, never left to fall to the page, where a keyboard or
  //? VoiceOver would start again from the top. A phone's opens the store's section, whose page takes the focus.
  const handOn = useRef(false)
  const browse = useMemo(() => () => {
    handOn.current = true
    chooseLibrary('store')
  }, [])
  useLayoutEffect(() => {
    if (!handOn.current || drawn !== 'store') return
    handOn.current = false
    const active = document.activeElement as HTMLElement | null
    if (active && active !== document.body && !active.closest('[hidden]')) return
    page.current?.querySelector<HTMLElement>('[data-section="store"] .pl-large-title')?.focus({ preventScroll: true })
  })

  if (!desktop) {
    return (
      <div class="app-library-root" ref={page}>
        <LibraryHome personal={personal} hasSongs={hasSongs} shown={shown} onOpen={onOpen} onOpenSection={onOpenSection} onOpenPlaylists={onOpenPlaylists} />
      </div>
    )
  }

  return (
    <div class="app-library-root" ref={page}>
      {(visited.includes(drawn) ? visited : [...visited, drawn]).map((view) => (
        <div key={view} hidden={view !== drawn}>
          <LibrarySection
            id={view}
            personal={personal}
            shown={shown && view === drawn}
            onOpen={onOpen}
            onOpenArtist={onOpenArtist}
            onSongMenu={onSongMenu}
            onBrowse={browse}
          />
        </div>
      ))}
    </div>
  )
}
