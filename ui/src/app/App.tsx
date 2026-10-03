import type { JSX } from 'preact'
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { useDownloadJobs } from '../hooks/useDownloadJobs'
import type { ReleaseGroup } from '../api/types'
import { createRouter, type Router, type StorageLike } from '../lib/appHistory'
import { TAB_LABELS, TABS, backLabel, currentRoute, scrollKey, type Nav, type Page, type Tab } from '../lib/appRoutes'
import { handleDownloadRequests } from '../lib/downloadRequests'
import { arrivingCards, asksAgain, requestsView, stallsOn, watchingOf, type RequestRow } from '../lib/requestsView'
import { MB_PREFIX, artistPageId } from '../lib/artistPage'
import { pinOf, type AlbumPinTarget } from '../lib/pins'
import type { Look } from '../lib/turntable'
import { AlbumPage } from '../player/AlbumPage'
import { navidromeStatus, playedAlbum, sentFormat, type Album, type Artist, type NavidromeStatus } from '../player/api'
import { Library } from '../player/Library'
import { MiniPlayer } from '../player/MiniPlayer'
import { NowPlaying } from '../player/NowPlaying'
import { deckReport, onDeckReport, resumeDeckAudio } from '../player/deck'
import { usePlayer, type Player } from '../player/usePlayer'
import { readPlayerOpensAs, readPlayerWindDown, writePlayerOpensAs, writePlayerWindDown } from '../state/persisted'
import { ActionMenu } from './ActionMenu'
import { ArtistPage, type ArtistPreview } from './ArtistPage'
import { ActionsContext, PlayerContext, pickActions } from './context'
import { Home } from './Home'
import { InfoSheet } from './InfoSheet'
import { NeedsNavidrome } from './NeedsNavidrome'
import { ReleaseGroupPage } from './ReleaseGroupPage'
import { Requests } from './Requests'
import { Search } from './Search'
import { Sources, type GetRequest } from './Sources'
import { TabBar } from './TabBar'
import { useInfoDetails } from './useInfoDetails'
import { PinNotice } from './PinNotice'
import { setPinned, usePins } from './usePins'
import { takeOpener } from './useSheet'
import { You } from './You'

/** How many albums opened this session are kept to draw a page's hero before its songs arrive. */
const PREVIEWS_KEPT = 50

/** sessionStorage, where it can be had (a private window may refuse even the reading of it). */
function sessionStore(): StorageLike | null {
  try {
    return window.sessionStorage
  } catch {
    return null
  }
}

const pageKey = (tab: Tab, page: Page) => `${tab}:${page.kind}:${page.id}`

/** Nothing arriving: one array for every render, so Home's element holds still while it stays so. */
const NOTHING_ARRIVING: readonly RequestRow[] = []

/** Whether the page is showing: false on a locked phone, or with the app in the background. */
function usePageShown(): boolean {
  const [shown, setShown] = useState(() => document.visibilityState !== 'hidden')
  useEffect(() => {
    const onChange = () => setShown(document.visibilityState !== 'hidden')
    document.addEventListener('visibilitychange', onChange)
    return () => document.removeEventListener('visibilitychange', onChange)
  }, [])
  return shown
}

/**
 * The app at /player/: five tabs - Home, Library, Search, Requests and You - with the player
 * inside them, the mini player docked above the tab bar and Now Playing a sheet over everything.
 *
 * THE ROOT, and the ONE place usePlayer() is called (ui/test/app-rules.sim.cjs holds that). The
 * engine makes one audio element for the page's life, and iOS unlocks audio per element from a
 * tap: this component never unmounts, so neither does the music, whichever tab shows.
 *
 * Every tab's root stays mounted, hidden while another shows, so a tab comes back as it was left -
 * pages loaded, scrolled where it was. The DOCUMENT is the scroller (iOS's tap on the status bar
 * scrolls only the document to the top), so each route's scroll is saved by hand as it is left
 * and put back after the next one draws. The top page of each tab's stack stays mounted too. The
 * roots are memoised elements, so a change of `playing` or `buffering` re-renders the player's own
 * parts and not the grids behind them.
 *
 * The address is the hash (lib/appRoutes.ts has the rules, lib/appHistory.ts drives them): opening
 * a page pushes a history entry, so the edge swipe goes back; switching tab replaces it. Sheets are
 * state, not addresses. While Now Playing is open, everything behind it is inert - the tab bar and
 * the mini player included - so neither a keyboard nor VoiceOver can reach a control it covers.
 *
 * Three sheets, stacked (2.0.0-player.10): Now Playing, and over it either its ••• menu or Info.
 * Each is its own sheet (useSheet.ts) - its own scroll lock, focus in and back, Escape - and the
 * one underneath is inert while another is over it. The menu and Info are never open together:
 * choosing Info closes the menu as it opens, and Info gives focus back to the ••• button.
 *
 * "Now Playing opens as" (2.0.0-player.11) is kept here - You sets it, Now Playing opens in it -
 * and only the SETTING: which look is showing is Now Playing's own, so switching it never
 * re-renders this component, let alone the engine.
 *
 * The downloads (2.0.0-player.12) are watched HERE, once, for the whole app: useDownloadJobs is
 * called in this component and nowhere else in it, so the Requests tab, Home's Arriving and the
 * tab's badge are one poll and one set of overlays, and this page's downloads go through it
 * (handleDownloadRequests, for a later slice's Get). It polls fast only while the Requests tab's
 * root shows (its `open`; lib/requestsView.ts's watchingOf), keeps going slowly by itself while
 * something is on its way, and otherwise stops - and is asked once more as Home comes into view
 * and as the app comes back from the background (asksAgain), so a download started on another
 * device shows without a poll left running. A look that FAILED while something was on its way
 * keeps it asking (stallsOn): the hook would otherwise stop there for good, and Home's Arriving
 * and the badge would freeze on the last answer. The badge counts Home's own list
 * (view.arriving), so the two can never count different things. Each tab's top page is memoised on
 * what an album page reads (the playing song and whether it plays), so a poll re-renders Requests
 * and Home's Arriving and not an album page.
 *
 * Search (2.0.0-player.13) opens two kinds of page: an album you have (openAlbum, as a tile does)
 * and an album you don't (openGroup: a MusicBrainz release group, drawn outside the Navidrome gate,
 * since nothing on it is Navidrome's). A pressing chosen there replaces the page's own address
 * (pickPressing, router.update), so scroll is kept by scrollKey, which leaves the pressing out.
 *
 * Get (2.0.0-player.15) - the album page's "Get the album", or a Get chip on a Search row - opens
 * the Sources sheet over everything (openSources; z 25, under Now Playing's menu and Info), and the
 * page behind is inert while it shows, as it is behind Now Playing. It is never open with Now
 * Playing: each covers what would open the other, and a chip's lookup that lands late can't stack
 * them either - Search is told when its root stops being what shows (`searchActive`: another tab,
 * a page over it, Now Playing, the sheet) and calls the lookup off, and openSources refuses while
 * Now Playing is open, the backstop (review). A source's Get - or a pick made for you - asks for the
 * download in the tap through the one downloads hook here (its pending row is up from that call),
 * and `gotten` closes the sheet with no focus given back and shows Requests at its root. The album
 * page is told whether it is what shows (its tab current, the sheet closed, the app in front), so
 * what it says is already here of a pressing is asked again as you come back to it - after a Get,
 * or a download cancelled in Requests.
 *
 * Artists (2.0.0-player.17): an artist's page (openArtist) is pushed on the tab showing, from Search's
 * artist rows and top result, Library > Artists, the artist on both album pages, and Info's artist
 * card - by Navidrome's id for them, or `mb:<mbid>` for one known only by MusicBrainz (the album you
 * don't have). One Navidrome knows is drawn inside the gate, like an album you have; one MusicBrainz
 * knows outside it, its albums-you-have half asked only while Navidrome answers. Requests is told
 * when its root is what shows (`requestsActive`: watching it, no sheet over it), and only then looks
 * for its Done rows' albums, so their ▶ plays - looking again until Navidrome has scanned what was
 * filed - and calls a tap's look off when it stops being so; it is told why Navidrome can't be asked
 * (`navidromeProblem`), for a row that can't open. Info asks for what fills its About in as it opens
 * (useInfoDetails).
 *
 * Pins (2.0.0-player.18) are the app's one store (usePins.ts), read where they show: Home is told when
 * it is what shows (`homeShown`), and asks its pins afresh then; the album and artist pages read
 * theirs themselves. The ••• menu's pin is App's: the playing song's album, by the answer it was
 * played from, taken as the menu OPENS (so no row comes or goes, nor changes album, while it is up) -
 * its tap closes the menu, saves behind it and says what became of it in the app's one notice
 * (PinNotice, drawn here once), and plays nothing.
 */
export function App() {
  const player = usePlayer()
  //? the engine's actions are made once, in its own useMemo, and never change: taken once here
  const actions = useMemo(() => pickActions(player), [])

  const scrolls = useRef(new Map<string, number>())
  const previews = useRef(new Map<string, Album>())
  //? the albums you don't have, as Search showed them: a group page's header before its pressings
  const groupPreviews = useRef(new Map<string, ReleaseGroup>())
  //? the artists opened this session, as the row that opened them knew them: a page's hero at once
  const artistPreviews = useRef(new Map<string, ArtistPreview>())
  const router: Router = useMemo(
    () =>
      createRouter({
        history: window.history,
        hash: () => location.hash,
        storage: sessionStore,
        //? the scroll of the route being left, read before the router moves on from it - kept by
        //? scrollKey, which leaves a group page's pressing out: choosing one is the same page
        leaving: () => scrolls.current.set(scrollKey(currentRoute(router.nav)), window.scrollY),
        show: (next) => setNav(next),
      }),
    [],
  )
  const [nav, setNav] = useState<Nav>(() => router.nav)

  const [status, setStatus] = useState<NavidromeStatus | null>(null)
  const [sheetOpen, setSheetOpen] = useState(false)
  //? Now Playing open, for a callback made once: set in the tap that opens it, and every render
  const nowPlayingOpen = useRef(false)
  nowPlayingOpen.current = sheetOpen
  //? the Sources sheet: whether it shows, and the last Get it was opened for (kept as it slides away)
  const [sourcesOpen, setSourcesOpen] = useState(false)
  const [getting, setGetting] = useState<GetRequest | null>(null)
  //? what is over Now Playing: its ••• menu, or Info - never both
  const [over, setOver] = useState<'none' | 'menu' | 'info'>('none')
  const [youSeen, setYouSeen] = useState(nav.tab === 'you')
  const [searchSeen, setSearchSeen] = useState(nav.tab === 'search')
  //? "Now Playing opens as", kept on this device
  const [opensAs, setOpensAs] = useState<Look>(readPlayerOpensAs)
  const chooseOpensAs = useCallback((look: Look) => {
    writePlayerOpensAs(look)
    setOpensAs(look)
  }, [])
  //? "Pause winds the record down", kept on this device - the turntable's pause (2.0.0-player.14)
  const [windDown, setWindDown] = useState<boolean>(readPlayerWindDown)
  const chooseWindDown = useCallback((on: boolean) => {
    writePlayerWindDown(on)
    setWindDown(on)
  }, [])
  //? the turntable's sound, for Info > Debug: told when it changes - a window in, a context started -
  //? never a frame at a time
  const [turntableSound, setTurntableSound] = useState(deckReport)
  useEffect(() => onDeckReport(setTurntableSound), [])

  const checkNavidrome = useCallback(() => {
    setStatus(null)
    navidromeStatus()
      .then(setStatus)
      .catch((reason: unknown) =>
        setStatus({ configured: true, ok: false, server: null, problem: String(reason) }),
      )
  }, [])

  useEffect(checkNavidrome, [checkNavidrome])

  useLayoutEffect(() => {
    history.scrollRestoration = 'manual'
    router.start()
  }, [])

  //? the browser moved by itself: back, forward, an address typed in
  useEffect(() => {
    const onMove = () => router.moved()
    window.addEventListener('popstate', onMove)
    window.addEventListener('hashchange', onMove)
    return () => {
      window.removeEventListener('popstate', onMove)
      window.removeEventListener('hashchange', onMove)
    }
  }, [])

  const routeKey = scrollKey(currentRoute(nav))
  useLayoutEffect(() => {
    window.scrollTo(0, scrolls.current.get(routeKey) ?? 0)
  }, [routeKey])

  useEffect(() => {
    if (nav.tab === 'you') setYouSeen(true)
    if (nav.tab === 'search') setSearchSeen(true)
  }, [nav.tab])

  //? What's showing, as far as the downloads go: a tab's ROOT, with Now Playing not over it
  const pageShown = usePageShown()
  const watching = watchingOf({ shown: pageShown, tab: nav.tab, depth: nav.stacks[nav.tab].length, sheetOpen })
  //? a failed look while something was on its way: keep asking until deadwax answers (stallsOn)
  const [stalled, setStalled] = useState(false)
  const downloads = useDownloadJobs(watching === 'requests' || stalled)
  const { jobs, pending, speeds, cancelling, retrying, retryingSame, retryProblems } = downloads
  const { refresh, enqueue, cancel, retry, clearFinished, trackingEnabled, error: downloadsError } = downloads

  //? Whether deadwax has answered yet, or failed to: until then Requests knows nothing, empty or
  //? not. The hook's jobs are one array until its first answer replaces them.
  const firstJobs = useRef(jobs)
  const answered = useRef(false)
  if (!answered.current && (jobs !== firstJobs.current || downloadsError !== null || !trackingEnabled)) answered.current = true

  //? every download asked for on this page goes through the one hook, so its row is up from the tap
  useEffect(() => handleDownloadRequests(enqueue), [enqueue])

  //? Home coming into view, or the app back from the background, asks again (Requests asks by itself)
  const watched = useRef(watching)
  useEffect(() => {
    const before = watched.current
    watched.current = watching
    if (asksAgain(before, watching)) refresh()
  }, [watching])

  const view = useMemo(
    () => requestsView({ jobs, pending, speeds, cancelling, retrying, retryingSame, retryProblems }, Date.now()),
    [jobs, pending, speeds, cancelling, retrying, retryingSame, retryProblems],
  )
  const arriving = view.arriving.length ? arrivingCards(view) : NOTHING_ARRIVING

  const stalls = stallsOn(watching, downloadsError, view.arriving.length)
  useEffect(() => setStalled(stalls), [stalls])

  const openAlbum = useCallback((album: Album) => {
    previews.current.delete(album.id)
    previews.current.set(album.id, album)
    if (previews.current.size > PREVIEWS_KEPT) {
      const [oldest] = previews.current.keys()
      if (oldest !== undefined) previews.current.delete(oldest)
    }
    const page: Page = { kind: 'album', id: album.id, label: album.name }
    const address = scrollKey({ tab: router.nav.tab, page })
    //? a page opened afresh starts at its top, even one visited before - not the one showing (a double tap)
    if (address !== scrollKey(currentRoute(router.nav))) scrolls.current.delete(address)
    router.open(page)
  }, [])

  /** An album you don't have (2.0.0-player.13), from Search: its group page, on the tab showing. */
  const openGroup = useCallback((group: ReleaseGroup) => {
    groupPreviews.current.delete(group.id)
    groupPreviews.current.set(group.id, group)
    if (groupPreviews.current.size > PREVIEWS_KEPT) {
      const [oldest] = groupPreviews.current.keys()
      if (oldest !== undefined) groupPreviews.current.delete(oldest)
    }
    const page: Page = { kind: 'group', id: group.id, ...(group.title ? { label: group.title } : {}) }
    const address = scrollKey({ tab: router.nav.tab, page })
    if (address !== scrollKey(currentRoute(router.nav))) scrolls.current.delete(address)
    router.open(page)
  }, [])

  /**
   * An artist's page (2.0.0-player.17), on the tab showing: by Navidrome's id for them, or - known only
   * by MusicBrainz - `mb:<mbid>`. Drawn at once from what the row that opened it knew.
   */
  const openArtist = useCallback((artist: { navidrome?: string | null; mbid?: string | null; name?: string; coverArt?: string | null }) => {
    const id = artistPageId(artist)
    if (!id) return
    artistPreviews.current.delete(id)
    artistPreviews.current.set(id, { ...(artist.name ? { name: artist.name } : {}), ...(artist.coverArt ? { coverArt: artist.coverArt } : {}) })
    if (artistPreviews.current.size > PREVIEWS_KEPT) {
      const [oldest] = artistPreviews.current.keys()
      if (oldest !== undefined) artistPreviews.current.delete(oldest)
    }
    const page: Page = { kind: 'artist', id, ...(artist.name ? { label: artist.name } : {}) }
    const address = scrollKey({ tab: router.nav.tab, page })
    if (address !== scrollKey(currentRoute(router.nav))) scrolls.current.delete(address)
    router.open(page)
  }, [])
  //? an artist from Navidrome's answers - Search's rows, Library > Artists
  const openLibraryArtist = useCallback((artist: Artist) => openArtist({ navidrome: artist.id, name: artist.name, coverArt: artist.coverArt ?? null }), [])
  //? from an album page: Navidrome's album artist, or MusicBrainz's sole credited artist
  const openAlbumArtist = useCallback((artist: { id: string; name: string }) => openArtist({ navidrome: artist.id, name: artist.name }), [])
  const openCreditedArtist = useCallback((artist: { mbid: string; name: string }) => openArtist({ mbid: artist.mbid, name: artist.name }), [])

  /** A pressing chosen on a group page: the page's address replaced - the default takes it out. */
  const pickPressing = useCallback((groupId: string, release: string | null) => {
    router.update({ kind: 'group', id: groupId, ...(release ? { release } : {}) })
  }, [])

  const back = useCallback(() => router.back(), [])

  const chooseTab = useCallback((tab: Tab) => {
    if (router.tab(tab) === 'scroll-to-top') {
      const still = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
      window.scrollTo({ top: 0, behavior: still ? 'auto' : 'smooth' })
    }
  }, [])

  //? Arriving's "See all", and a tap on one of its cards: the list of downloads, at Requests' root
  const seeRequests = useCallback(() => router.root('requests'), [])

  //? Get: the Sources sheet for the release it was for - a new key every time, so a second Get of
  //? the same album searches again - with focus given back to the Get as it closes. Never over Now
  //? Playing: a Get is tapped with nothing over the page, so one arriving while Now Playing is open
  //? is a lookup that landed late, and opens nothing
  const sourcesOpener = useRef<HTMLElement | null>(null)
  const gets = useRef(0)
  const openSources = useCallback((request: Omit<GetRequest, 'key'>, opener: HTMLElement | null) => {
    if (nowPlayingOpen.current) return
    sourcesOpener.current = opener
    gets.current += 1
    setGetting({ ...request, key: gets.current })
    setSourcesOpen(true)
  }, [])
  const closeSources = useCallback(() => setSourcesOpen(false), [])
  //? a download asked for from the sheet: it goes - focus going nowhere it would land - and Requests shows
  const gotten = useCallback(() => {
    sourcesOpener.current = null
    setSourcesOpen(false)
    router.root('requests')
  }, [])

  //? What each sheet gives focus back to as it closes, taken in the tap that opened it: the button
  //? focuses itself first (WebKit doesn't focus a tapped button), before the page behind turns
  //? inert. The sheets do the rest themselves (useSheet.ts).
  const sheetOpener = useRef<HTMLElement | null>(null)
  const moreOpener = useRef<HTMLElement | null>(null)
  const openSheet = useCallback((event: MouseEvent) => {
    sheetOpener.current = takeOpener(event)
    setSheetOpen(true)
    nowPlayingOpen.current = true
    //? the mini player's tap is a gesture: a turntable left showing gets its sound back from it
    //? (never made here - resumed, when there is one)
    resumeDeckAudio()
  }, [])
  const closeSheet = useCallback(() => {
    setOver('none')
    setSheetOpen(false)
  }, [])
  //? the album the ••• menu's pin is for, taken as the menu opens (2.0.0-player.18): what can be pinned
  //? NOW is menuPinNow, kept in step below; the menu acts on what it opened with
  const menuPinNow = useRef<AlbumPinTarget | null>(null)
  const [menuPin, setMenuPin] = useState<AlbumPinTarget | null>(null)
  const openMenu = useCallback((event: MouseEvent) => {
    moreOpener.current = takeOpener(event)
    setMenuPin(menuPinNow.current)
    setOver('menu')
  }, [])
  const openInfo = useCallback(() => setOver('info'), [])
  const closeOver = useCallback(() => setOver('none'), [])

  /**
   * "Go to album" - the menu's row, Now Playing's "Artist — Album" line, Info's album card: every
   * sheet closes and the song's album opens on the tab showing, as a tile there would open it.
   * Drawn from the answer it was played from when that is in hand, so the page has its cover and
   * artist at once. The ••• button is in a sheet that is closing, so focus isn't sent back to it.
   */
  /** Info's artist card: every sheet closes and the artist's page opens on the tab showing. */
  const toArtist = (artist: { id: string; name: string }) => {
    moreOpener.current = null
    closeSheet()
    openArtist({ navidrome: artist.id, name: artist.name })
  }

  const goToAlbum = (track: NonNullable<Player['track']>) => {
    if (!track.albumId) return
    moreOpener.current = null
    closeSheet()
    openAlbum(
      playedAlbum(track.albumId) ?? {
        id: track.albumId,
        name: track.album,
        ...(track.coverArt ? { coverArt: track.coverArt } : {}),
      },
    )
  }

  //? The tab roots, memoised: they read no player state, so the music playing leaves them alone.
  //? You reads the player from context, and re-renders with it by itself. Each is memoised apiece,
  //? on what it is handed - Home and Requests on the downloads they draw, so a poll re-renders only
  //? them; Search on whether its root is what shows, so that changing re-renders only Search.
  const arrivingTrouble = downloadsError !== null
  //? Search's root is what shows, with nothing over it: a Get chip's lookup still out when it stops
  //? being so is called off, so its late answer opens no sheet over what you went to instead
  const searchActive = nav.tab === 'search' && nav.stacks.search.length === 0 && !sheetOpen && !sourcesOpen
  //? You's tab is the one showing: its Getting albums are asked again each time it is opened
  const youCurrent = nav.tab === 'you'
  //? Requests' root is what shows, with nothing over it: its Done rows' albums are looked for only
  //? then, and a tap's look still out when it stops being so opens nothing
  const requestsActive = watching === 'requests' && !sourcesOpen
  //? why Navidrome can't be asked for an album just now, for a Done row that can't open: unknown
  //? (null) until its status is in
  const navidromeProblem = !status ? null
    : !status.configured ? "Navidrome isn't set up, so deadwax can't open the album here"
    : !status.ok ? "Navidrome isn't answering just now, so deadwax can't open the album here"
    : null
  //? Home is what shows: its pins are asked again as it comes into view (2.0.0-player.18)
  const homeShown = watching === 'home'
  const home = useMemo(
    () => (
      <Home
        status={status}
        onRetry={checkNavidrome}
        onOpen={openAlbum}
        onOpenArtist={openArtist}
        arriving={arriving}
        onSeeAll={seeRequests}
        arrivingTrouble={arrivingTrouble}
        shown={homeShown}
      />
    ),
    [status, arriving, arrivingTrouble, homeShown],
  )
  const requests = useMemo(
    () => (
      <Requests
        view={view}
        answered={answered.current}
        trackingEnabled={trackingEnabled}
        error={downloadsError}
        active={requestsActive}
        navidromeProblem={navidromeProblem}
        onCancel={cancel}
        onRetry={retry}
        onClear={clearFinished}
        onOpenAlbum={openAlbum}
      />
    ),
    [view, answered.current, trackingEnabled, downloadsError, cancel, retry, clearFinished, requestsActive, navidromeProblem],
  )
  const library = useMemo(
    () => (
      <NeedsNavidrome status={status} onRetry={checkNavidrome} title={TAB_LABELS.library}>
        <Library onOpen={openAlbum} onOpenArtist={openLibraryArtist} />
      </NeedsNavidrome>
    ),
    [status],
  )
  const search = useMemo(
    () => <Search shown={searchSeen} active={searchActive} status={status} onRetry={checkNavidrome} onOpenAlbum={openAlbum} onOpenGroup={openGroup} onOpenArtist={openLibraryArtist} onGet={openSources} />,
    [status, searchSeen, searchActive],
  )
  const you = useMemo(
    () => <You shown={youSeen} current={youCurrent} opensAs={opensAs} onOpensAs={chooseOpensAs} windDown={windDown} onWindDown={chooseWindDown} />,
    [youSeen, youCurrent, opensAs, windDown],
  )
  const roots: Record<Tab, JSX.Element> = { library, search, you, home, requests }

  //? an album you don't have needs no Navidrome, so it is drawn outside the gate. It is told whether
  //? it is what shows - its tab current, no Sources sheet over it, the app in front - and asks the
  //? store again as it comes back to that
  //? an artist: one Navidrome knows inside the gate, one MusicBrainz knows outside it
  const artistView = (tab: Tab, page: Page) => {
    const artist = (
      <ArtistPage
        id={page.id}
        preview={artistPreviews.current.get(page.id) ?? null}
        navidromeOk={!!status?.ok}
        shown={pageShown && nav.tab === tab && !sourcesOpen}
        onBack={back}
        backLabel={backLabel(nav, tab) ?? TAB_LABELS[tab]}
        onOpenAlbum={openAlbum}
        onOpenGroup={openGroup}
        onGet={openSources}
      />
    )
    return page.id.startsWith(MB_PREFIX) ? artist : (
      <NeedsNavidrome status={status} onRetry={checkNavidrome} title={TAB_LABELS[tab]}>
        {artist}
      </NeedsNavidrome>
    )
  }

  const pageView = (tab: Tab, page: Page, player: Player) =>
    page.kind === 'artist' ? artistView(tab, page) : page.kind === 'group' ? (
      <ReleaseGroupPage
        id={page.id}
        release={page.release ?? null}
        preview={groupPreviews.current.get(page.id) ?? null}
        shown={pageShown && nav.tab === tab && !sourcesOpen}
        onBack={back}
        backLabel={backLabel(nav, tab) ?? TAB_LABELS[tab]}
        onPick={pickPressing}
        onGet={openSources}
        onArtist={openCreditedArtist}
      />
    ) : (
      <NeedsNavidrome status={status} onRetry={checkNavidrome} title={TAB_LABELS[tab]}>
        <AlbumPage
          id={page.id}
          preview={previews.current.get(page.id) ?? null}
          player={player}
          onBack={back}
          backLabel={backLabel(nav, tab) ?? TAB_LABELS[tab]}
          onArtist={openAlbumArtist}
          onOpenAlbum={openAlbum}
        />
      </NeedsNavidrome>
    )

  //? Each tab's top page, memoised on what it reads, so a poll of the downloads never re-renders
  //? one. `player` is a new object on every render of this component, so it can't be what the
  //? memo is keyed on: an album page reads only the playing song's id, whether it plays, and
  //? playTracks (one function for the page's life) - app-rules.sim.cjs holds AlbumPage to those,
  //? so reading more of the player there fails until it is added here too. The group page's
  //? `shown` reads the Sources sheet and whether the app is in front, so those key it too.
  const playingId = player.track?.id ?? null
  const pages = useMemo(
    () =>
      Object.fromEntries(
        TABS.map((tab) => {
          const stack = nav.stacks[tab]
          const top = stack[stack.length - 1] ?? null
          return [tab, top ? pageView(tab, top, player) : null]
        }),
      ) as Record<Tab, JSX.Element | null>,
    [nav, status, playingId, player.playing, sourcesOpen, pageShown],
  )

  const playing = player.track
  const toAlbum = playing?.albumId ? () => goToAlbum(playing) : null
  const playedFrom = playing ? playedAlbum(playing.albumId) : null
  //? what fills Info > About in, asked as it opens (2.0.0-player.17)
  const infoDetails = useInfoDetails(sheetOpen && over === 'info', playing, playedFrom)
  //? what is behind a sheet - Now Playing, or the Sources sheet - is inert while it shows
  const covered = sheetOpen || sourcesOpen

  //? The ••• menu's pin (2.0.0-player.18): the playing song's album, by its release where the answer
  //? it was played from says it (none at all, "", and it can't be pinned), else by Navidrome's id,
  //? from which deadwax reads the release. The pins are asked as Now Playing opens, so the menu
  //? knows by the time it does. Whether the menu has the row, and for which album, is decided as it
  //? opens (menuPin, from menuPinNow): a pins answer or the next song landing while it is up moves no
  //? row - a row deadwax can no longer keep pins for stays, inactive. Its tap closes the menu, saves
  //? behind it and says what became of it (PinNotice) - it plays nothing.
  const pins = usePins(sheetOpen)
  const playingRelease = playedFrom?.musicBrainzId?.trim()
  menuPinNow.current = playing?.albumId && playingRelease !== '' && pins.canSave ? {
    kind: 'album', release_mbid: playingRelease ?? null, navidrome_id: playing.albumId, label: playedFrom?.name ?? playing.album,
    sub: playedFrom?.artist ?? playing.artist ?? '', cover: playedFrom?.coverArt ?? playing.coverArt ?? null,
  } : null
  const menuPinned = menuPin && pins.pins && pins.canSave ? pinOf(pins.pins, menuPin) !== null : null
  const pinPlaying = menuPin ? () => {
    closeOver()
    void setPinned(menuPin, !menuPinned, true)
  } : null

  return (
    <PlayerContext.Provider value={player}>
      <ActionsContext.Provider value={actions}>
        <div class={`pl-app app-shell${player.track ? ' has-mini' : ''}`}>
          {/* what Now Playing covers: inert while it is open */}
          <div class="app-behind" aria-hidden={covered} inert={covered}>
            {TABS.map((tab) => {
              const stack = nav.stacks[tab]
              const top = stack[stack.length - 1] ?? null
              return (
                <div key={tab} class="app-pane" data-tab={tab} hidden={nav.tab !== tab}>
                  <div hidden={top !== null}>{roots[tab]}</div>
                  {top && <div key={pageKey(tab, top)}>{pages[tab]}</div>}
                </div>
              )
            })}

            <MiniPlayer player={player} onOpen={openSheet} />
            <TabBar current={nav.tab} onSelect={chooseTab} arriving={view.arriving.length} />
          </div>
          {/* a Get's sources (2.0.0-player.15): over the page, under Now Playing's menu and Info */}
          <Sources open={sourcesOpen} request={getting} opener={sourcesOpener} onClose={closeSources} onQueued={gotten} />
          <NowPlaying
            player={player}
            open={sheetOpen}
            covered={over !== 'none'}
            opener={sheetOpener}
            onClose={closeSheet}
            onMore={openMenu}
            onAlbum={toAlbum ?? closeSheet}
            openAs={opensAs}
            windDown={windDown}
            pinnable={menuPinNow.current !== null}
          />
          {/* over Now Playing: its menu, then Info - the menu first, so where one closes as the
              other opens, focus ends in the one that opened */}
          <ActionMenu
            open={sheetOpen && over === 'menu'}
            opener={over === 'info' ? undefined : moreOpener}
            onClose={closeOver}
            onInfo={openInfo}
            onAlbum={toAlbum}
            pinned={menuPinned}
            onPin={pinPlaying}
          />
          <InfoSheet
            open={sheetOpen && over === 'info'}
            opener={moreOpener}
            onClose={closeOver}
            onAlbum={toAlbum}
            player={player}
            album={playedFrom}
            sentFormat={sentFormat}
            turntable={turntableSound}
            details={infoDetails}
            onArtist={toArtist}
          />
          {/* what became of a pin, said over everything (2.0.0-player.18) */}
          <PinNotice />
        </div>
      </ActionsContext.Provider>
    </PlayerContext.Provider>
  )
}
