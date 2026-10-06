import type { JSX } from 'preact'
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { useDownloadJobs } from '../hooks/useDownloadJobs'
import type { ReleaseGroup } from '../api/types'
import { me } from '../api/me'
import { closesOnCrossing, libraryItems, liesOver, makesRoom, sideOf, sidebarCurrent, sidebarMove, type SidebarId } from '../lib/appFrame'
import { createRouter, type Router, type StorageLike } from '../lib/appHistory'
import { QUEUE_ID, QUEUE_PAGE, TAB_LABELS, TABS, backLabel, currentRoute, scrollKey, type Nav, type Page, type Tab } from '../lib/appRoutes'
import { handleDownloadRequests } from '../lib/downloadRequests'
import { movedTo, noteMove, type EditAlbum } from '../lib/albumEdit'
import { announceAlbumsFiled } from '../lib/libraryEvents'
import { latestOnly } from '../lib/latest'
import { arrivingCards, asksAgain, requestsView, stallsOn, watchingOf, type RequestRow } from '../lib/requestsView'
import { MB_PREFIX, artistPageId } from '../lib/artistPage'
import { pinOf, type AlbumPinTarget } from '../lib/pins'
import type { Look } from '../lib/turntable'
import { AlbumPage } from '../player/AlbumPage'
import { navidromeStatus, playedAlbum, sentFormat, type Album, type Artist, type NavidromeStatus } from '../player/api'
import { Library } from '../player/Library'
import { MiniPlayer } from '../player/MiniPlayer'
import { NowPlaying } from '../player/NowPlaying'
import { PlayerBar } from '../player/PlayerBar'
import { Visualizer } from '../player/Visualizer'
import { wakeVisualizerAudio } from '../player/vizAudio'
import { deckRecorded, deckReport, onDeckRecorded, onDeckReport, recordDeckSound, resumeDeckAudio, wakeDeckAudio } from '../player/deck'
import { usePlayer, type Player } from '../player/usePlayer'
import { readPlayerOpensAs, readPlayerWindDown, writePlayerOpensAs, writePlayerWindDown } from '../state/persisted'
import { ActionMenu } from './ActionMenu'
import { ArtistPage, type ArtistPreview } from './ArtistPage'
import { ActionsContext, PlayerContext, pickActions } from './context'
import { EditPanel, isFolderRequest, type AlbumChange, type EditRequest, type FolderRequest } from './EditPanel'
import { Home } from './Home'
import { InfoSheet } from './InfoSheet'
import { chooseLibrary, libraryPick, librarySongs, useLibraryPick } from './libraryPick'
import { NeedsALook } from './NeedsALook'
import { NeedsNavidrome } from './NeedsNavidrome'
import { ReleaseGroupPage } from './ReleaseGroupPage'
import { Requests } from './Requests'
import { Search } from './Search'
import { Sidebar } from './Sidebar'
import { Sources, type GetRequest } from './Sources'
import { TabBar } from './TabBar'
import { useFrame } from './useFrame'
import { useInfoDetails } from './useInfoDetails'
import { PinNotice } from './PinNotice'
import { setPinned, usePins } from './usePins'
import { askQueueSummary, useQueueSummary } from './useQueueSummary'
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
 * THE DESKTOP FRAME (2.0.0-player.19, lib/appFrame.ts): from 1024px wide the same app is drawn in a
 * desktop's frame - a sidebar (Sidebar.tsx) where the tab bar was, the player bar (PlayerBar.tsx)
 * where the mini player was, and Sources and Info as a side panel beside the page rather than sheets
 * over it (a third column from 1280px, a drawer over the page's edge below that). The frame is chosen
 * HERE, below the engine (useFrame, the stylesheets' own media queries): crossing 1024px swaps the
 * chrome around the panes and nothing else - the tab roots and their pages are the same elements in
 * the same places (each pane keyed on its tab), the engine's useMemo never runs again, and the one
 * audio element (two with Gapless) plays on. Into the desktop, Now Playing and what is over it close
 * (it has no Now Playing sheet: the bar is its player, and the turntable is the phone's alone); back
 * to the phone, the Info panel does. A side panel is not modal - nothing behind it goes inert, the
 * page beside it is still the page - and one shows at a time: opening Info puts Sources away and the
 * other way round. The album you don't have follows the pressing chosen with the Sources panel open
 * for it (`sourcesGroup`, and the pressing it searched, `sourcesPressing`), searching again for each.
 * A drawer (1024-1279px) lies over the page's right edge (`.has-drawer`, lib/appFrame.ts liesOver),
 * and the Info drawer goes as you go to an album or artist from the player, so it isn't over the page
 * you asked for. The sidebar's search field is Search's own box (searchBox.ts): typing in it shows
 * Search's results at its root; its Managing shows unless deadwax says this user isn't an admin
 * (`/deadwax/me`, asked as the desktop frame shows, as You asks it for its own row).
 *
 * THE VISUALIZER (2.0.0-player.20, player/Visualizer.tsx): the desktop's full-screen visualizer, opened
 * from the player bar's button and drawn over everything - on a desktop only, closed as the window
 * crosses back to a phone's width. Its audio context is made in that click (openVisualizer: the gesture
 * a browser wants), and it analyses a silent copy of the song, never the player's own element. While
 * it shows, everything behind it is inert - the page, and a desktop's Sources or Info panel left open
 * beside it, or the Edit panel (`covered`) - and nothing behind it counts as watched (the downloads' fast poll stops, as
 * it does behind Now Playing).
 *
 * EDITING AN ALBUM (2.0.0-player.21, DesktopManage.dc.html): on a desktop, for an admin (`/deadwax/me`
 * again), the album page has Edit, which opens the Edit panel (EditPanel.tsx) - a third kind of side
 * panel, by the same rule: one at a time (Edit puts Sources and Info away, and either puts Edit away),
 * not modal, a column or a drawer, and the desktop's alone (drawn only in its frame; crossing to the
 * phone closes it). It is the album page's: it closes as that page stops being the one showing. What
 * it writes comes back as `albumChanged`: the album page asked again (`refreshes`, now and once
 * Navidrome has scanned) and the library's listeners told (announceAlbumsFiled - the owned marks, an
 * album-you-don't-have page's store line); an album an apply gave a new id in Navidrome becomes that
 * page in place (`router.become` - its entry replaced, its scroll and hero kept), and the move is
 * remembered (`moves`), so a page of the old id that comes back on top - back to it, forward to it,
 * another tab showing it - becomes the new one's too; and a deleted album's page is gone back from
 * when nothing of the album is left in Navidrome.
 *
 * NEEDS A LOOK (2.0.0-player.25, NeedsALook.tsx): the review queue's page, pushed on You
 * (`#/you/queue/all`, its facet in the address - pickFacet replaces it), opened from the desktop
 * sidebar's Managing or You's row (openQueue). Its rows open the same Edit panel on a FOLDER
 * (openFolderEdit, a FolderRequest: the queue's place, the page's own listener), by the same rules -
 * one panel at a time, the page's own (it closes as the queue page stops being on top). What the panel
 * writes from there comes back by path (`folder`): the library's listeners told of a write, the count
 * asked again; an album PAGE of the same album elsewhere in the stacks is not followed - nothing keys
 * it on a folder. How many albums need a look is useQueueSummary.ts's store, asked here as the desktop
 * frame shows for an admin and as the app comes back to the front, and after every change the panel
 * reports - never on a timer; the sidebar and You draw it. A phone draws the page as a short note.
 */
export function App() {
  const player = usePlayer()
  //? the engine's actions are made once, in its own useMemo, and never change: taken once here
  const actions = useMemo(() => pickActions(player), [])
  //? the phone's frame or the desktop's (2.0.0-player.19) - chosen here, below the engine
  const { frame, panel } = useFrame()
  const desktop = frame === 'desktop'
  //? what the Library shows, for the desktop sidebar (libraryPick.ts: the Library and the sidebar choose it)
  const { pick: libraryView, hasSongs } = useLibraryPick()
  //? the sidebar's Managing shows unless deadwax says this user isn't an admin - with logins off, everyone
  //? is (You's row asks the same). Asked as the desktop frame shows (a phone has no sidebar); a failed ask
  //? leaves it as it was
  const [admin, setAdmin] = useState(true)
  const meRequests = useMemo(latestOnly, [])
  useEffect(() => {
    if (!desktop) return
    const request = meRequests.begin()
    me(request.signal).then(
      (who) => {
        if (request.current()) setAdmin(who.admin)
      },
      () => {},
    )
    return () => meRequests.supersede()
  }, [desktop])

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
  //? the desktop's Edit panel (2.0.0-player.21): whether it shows, and the last album it was opened for
  //? (kept as it slides away) - and what it gives focus back to, the album page's Edit
  const [editOpen, setEditOpen] = useState(false)
  const editOpenNow = useRef(false)
  editOpenNow.current = editOpen
  //? (2.0.0-player.25: or an album opened by its folder from Needs a look - FolderRequest)
  const [edit, setEdit] = useState<EditRequest | FolderRequest | null>(null)
  const editNow = useRef<EditRequest | FolderRequest | null>(null)
  editNow.current = edit
  const editOpener = useRef<HTMLElement | null>(null)
  const editKeys = useRef(0)
  //? album pages asked again after an edit: each album's count, a new number each time (AlbumPage's
  //? `refresh`) - one per album, so asking one again never changes what another was handed
  const [refreshes, setRefreshes] = useState<ReadonlyMap<string, number>>(() => new Map())
  //? the albums an apply gave a new id in Navidrome this session, old id to new (lib/albumEdit.ts
  //? noteMove): a page of the old id coming back on top is the new one's
  const moves = useRef(new Map<string, string>())
  //? a desktop's Info: the side panel, opened from the player bar (2.0.0-player.19)
  const [infoPanel, setInfoPanel] = useState(false)
  const infoPanelOpen = useRef(false)
  infoPanelOpen.current = infoPanel
  //? what the Info panel gives focus back to as it closes: the player bar's Info, taken in its click
  const infoOpener = useRef<HTMLElement | null>(null)
  const [youSeen, setYouSeen] = useState(nav.tab === 'you')
  const [searchSeen, setSearchSeen] = useState(nav.tab === 'search')
  //? the Library asks Navidrome for nothing - its albums, their covers, whether songs can be listed -
  //? until its tab has been shown once: mounted hidden from the start, it fetched all of that at every
  //? launch, beside what Home was waiting for. (A desktop's sidebar shows Songs until it is known.)
  const [librarySeen, setLibrarySeen] = useState(nav.tab === 'library')
  //? "Now Playing opens as", kept on this device
  const [opensAs, setOpensAs] = useState<Look>(readPlayerOpensAs)
  //? as the mini player's tap reads it (openSheet is made once)
  const opensAsNow = useRef(opensAs)
  opensAsNow.current = opensAs
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
  //? a recording of it (2.0.0-player.32): running, or made and waiting to be saved - started from Debug's
  //? button, a tap, since it may make the context
  const [turntableRecording, setTurntableRecording] = useState(deckRecorded)
  useEffect(() => onDeckRecorded(setTurntableRecording), [])
  const recordTurntable = useCallback(() => {
    const problem = recordDeckSound(20)
    if (problem) console.warn(`turntable recording: ${problem}`)
  }, [])

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
    if (nav.tab === 'library') setLibrarySeen(true)
  }, [nav.tab])

  //? the desktop's visualizer showing (2.0.0-player.20) - see openVisualizer below
  const [visualizing, setVisualizing] = useState(false)

  //? What's showing, as far as the downloads go: a tab's ROOT, with Now Playing not over it - nor the
  //? desktop's visualizer, which covers the whole screen as Now Playing does a phone's
  const pageShown = usePageShown()
  const watching = watchingOf({ shown: pageShown, tab: nav.tab, depth: nav.stacks[nav.tab].length, sheetOpen: sheetOpen || (desktop && visualizing) })
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

  //? How many albums need a look (2.0.0-player.25, useQueueSummary.ts): the desktop sidebar's count
  //? and You's - an admin's. Asked as the desktop frame first shows for one, and as the page comes back
  //? from hidden; after that, the Edit panel's changes and the queue page's reviews ask again (and a
  //? filed album, by itself). Never at start-up on a phone, and no timer
  const needsLook = useQueueSummary()
  useEffect(() => {
    if (desktop && admin && pageShown) askQueueSummary()
  }, [desktop, admin, pageShown])

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
    //? one side panel at a time on a desktop: Sources puts Info and Edit away, giving focus back to
    //? nothing (Sources takes it)
    infoOpener.current = null
    setInfoPanel(false)
    editOpener.current = null
    setEditOpen(false)
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
    //? the mini player's tap is a gesture: a Now Playing that opens as the turntable gets its sound made
    //? and started from it (2.0.0-player.30: made only by a tap on the turntable itself until then, so a
    //? turntable opened this way had no sound until a first scrub had come and gone); one that opens as
    //? the cover only gets a sound back that a turntable left showing already had
    if (opensAsNow.current === 'turntable') wakeDeckAudio()
    else resumeDeckAudio()
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

  //? A desktop's Info (2.0.0-player.19): the player bar's button opens it as the side panel, and
  //? closes it again. One panel at a time - it puts Sources away, the search going with it (Sources'
  //? backstop) and focus given to Info, not back to the Get.
  const toggleInfo = useCallback((event: MouseEvent) => {
    if (infoPanelOpen.current) {
      setInfoPanel(false)
      return
    }
    infoOpener.current = takeOpener(event)
    sourcesOpener.current = null
    setSourcesOpen(false)
    editOpener.current = null
    setEditOpen(false)
    setInfoPanel(true)
  }, [])
  const closeInfoPanel = useCallback(() => setInfoPanel(false), [])

  //? The desktop's visualizer (2.0.0-player.20): the player bar's button opens it - its audio context
  //? made in this click, the gesture a browser lets it run from - and focus goes back to that button
  //? as it closes
  const visualizerOpener = useRef<HTMLElement | null>(null)
  const openVisualizer = useCallback((event: MouseEvent) => {
    visualizerOpener.current = takeOpener(event)
    wakeVisualizerAudio()
    setVisualizing(true)
  }, [])
  const closeVisualizer = useCallback(() => setVisualizing(false), [])

  //? The album page's Edit (2.0.0-player.21): the Edit panel for the album - a new request each press,
  //? so it starts afresh - and pressed again on the album it shows, closed. One panel at a time: it
  //? puts Sources (and its search, by Sources' backstop) and Info away, focus going to the panel.
  const toggleEdit = useCallback((event: MouseEvent, album: EditAlbum) => {
    if (editOpenNow.current && editNow.current?.album?.id === album.id) {
      setEditOpen(false)
      return
    }
    editOpener.current = takeOpener(event)
    editKeys.current += 1
    setEdit({ album, key: editKeys.current })
    setEditOpen(true)
    sourcesOpener.current = null
    setSourcesOpen(false)
    infoOpener.current = null
    setInfoPanel(false)
  }, [])
  const closeEdit = useCallback(() => setEditOpen(false), [])

  //? Needs a look's rows (2.0.0-player.25): the Edit panel on a FOLDER, by the same one-panel rule -
  //? a new request each album, a step through the queue included; `opener` the row it gives focus
  //? back to (undefined: kept as it was)
  const openFolderEdit = useCallback((request: Omit<FolderRequest, 'key'>, opener: HTMLElement | null | undefined) => {
    if (opener !== undefined) editOpener.current = opener
    editKeys.current += 1
    setEdit({ ...request, key: editKeys.current })
    setEditOpen(true)
    sourcesOpener.current = null
    setSourcesOpen(false)
    infoOpener.current = null
    setInfoPanel(false)
  }, [])

  //? Needs a look (2.0.0-player.25), from the sidebar or You's row: its page, on You - the tab shown
  //? as it was left and the page pushed over it, or nothing when it is already the page on top there
  const openQueue = useCallback(() => {
    const stack = router.nav.stacks.you
    const onTop = stack[stack.length - 1]?.kind === 'queue'
    if (router.nav.tab !== 'you') router.tab('you')
    if (!onTop) {
      scrolls.current.delete(scrollKey({ tab: 'you', page: QUEUE_PAGE }))
      router.open(QUEUE_PAGE)
    }
  }, [])
  //? a facet chosen there: the page's address replaced, as a pressing chosen on a group page
  const pickFacet = useCallback((facet: string | null) => {
    router.update({ kind: 'queue', id: QUEUE_ID, ...(facet ? { facet } : {}) })
  }, [])

  //? Crossing into the other frame (lib/appFrame.ts closesOnCrossing): into the desktop, Now Playing
  //? and what is over it close - the desktop's player is its bar; back to the phone, the Info panel.
  //? The Sources sheet stays open across, a panel on one side and a sheet on the other.
  const lastFrame = useRef(frame)
  useEffect(() => {
    if (lastFrame.current === frame) return
    lastFrame.current = frame
    const closes = closesOnCrossing(frame)
    if (closes.nowPlaying) {
      sheetOpener.current = null
      moreOpener.current = null
      setOver('none')
      setSheetOpen(false)
    }
    if (closes.infoPanel) {
      infoOpener.current = null
      setInfoPanel(false)
      //? the visualizer is a desktop's: a phone's width closes it, and it doesn't come back by itself
      setVisualizing(false)
    }
    if (closes.editPanel) {
      editOpener.current = null
      setEditOpen(false)
    }
  }, [frame])

  //? The Edit panel is the album page's: as that page stops being the one showing - another page, a
  //? tab, the sidebar - it closes, focus given back to nothing (the Edit it came from is gone). Opened
  //? from Needs a look, it is that page's, by the same rule
  const topNow = nav.stacks[nav.tab][nav.stacks[nav.tab].length - 1] ?? null
  const editShown = edit !== null && (isFolderRequest(edit) ? topNow?.kind === 'queue' : topNow?.kind === 'album' && topNow.id === edit.album.id)
  useEffect(() => {
    if (!editOpen || editShown) return
    editOpener.current = null
    setEditOpen(false)
  }, [editOpen, editShown])

  /**
   * What the Edit panel wrote (2.0.0-player.21), for the album it names. A write: the library's
   * listeners told (announceAlbumsFiled - the owned marks, an album-you-don't-have page's store line)
   * and the album page asked again; Navidrome having scanned: the page asked once more. A new id in
   * Navidrome after another release was applied: the page showing the album becomes that album's -
   * its entry replaced, its hero and scroll kept - and the panel follows it. Deleted: the panel goes,
   * and the page is gone back from when that was the album's only folder.
   */
  const albumChanged = useCallback((change: AlbumChange) => {
    //? every change the panel reports may move how many albums need a look
    askQueueSummary()
    //? an album opened from Needs a look: the library's listeners told of a write - the page that
    //? opened it hears the rest itself (FolderRequest's onChange)
    if (change.kind === 'folder') {
      if (change.wrote) announceAlbumsFiled()
      return
    }
    //? the album asked again under the id it has now - a write's `settled` can land after its move
    const ask = (id: string) => {
      const now = movedTo(moves.current, id) ?? id
      setRefreshes((was) => new Map(was).set(now, (was.get(now) ?? 0) + 1))
    }
    const top = currentRoute(router.nav).page
    const showing = top?.kind === 'album' && top.id === change.id
    if (change.kind === 'written' || change.kind === 'settled') {
      if (change.kind === 'written') announceAlbumsFiled()
      ask(change.id)
      return
    }
    if (change.kind === 'moved') {
      noteMove(moves.current, change.id, change.to)
      const at = editNow.current
      if (at && !isFolderRequest(at) && at.album.id === change.id) setEdit({ ...at, album: { ...at.album, id: change.to } })
      const preview = previews.current.get(change.id)
      if (preview) previews.current.set(change.to, { ...preview, id: change.to })
      //? not showing (the page left during the rename's wait): the page becomes it when it is back on top
      if (!showing) return
      scrolls.current.set(scrollKey({ tab: router.nav.tab, page: { kind: 'album', id: change.to } }), window.scrollY)
      router.become({ kind: 'album', id: change.id }, { kind: 'album', id: change.to, ...(top.label ? { label: top.label } : {}) })
      return
    }
    //? deleted: the panel closes - focus back to Edit while its page stays, to nothing when it goes
    announceAlbumsFiled()
    if (editNow.current?.album?.id === change.id) {
      if (change.last) editOpener.current = null
      setEditOpen(false)
    }
    if (!change.last) ask(change.id)
    else if (showing) router.back()
  }, [])

  //? A page of an album an apply moved, back on top - back to it, forward to it, its tab chosen: it
  //? becomes the album's page as it is now, its entry replaced (as the move itself does to the page
  //? showing), never left on an id Navidrome no longer has
  useEffect(() => {
    if (topNow?.kind !== 'album') return
    const to = movedTo(moves.current, topNow.id)
    if (!to) return
    const preview = previews.current.get(topNow.id)
    if (preview && !previews.current.has(to)) previews.current.set(to, { ...preview, id: to })
    router.become(topNow, { kind: 'album', id: to, ...(topNow.label ? { label: topNow.label } : {}) })
  }, [nav])

  //? The Edit focus goes back to, once a move has put the page under the album's new id: that page's
  //? own Edit (the one it was opened from went with the old page), on the tab showing
  useEffect(() => {
    const was = editOpener.current
    if (!editOpen || !was || was.isConnected) return
    editOpener.current = document.querySelector<HTMLElement>(`.app-pane[data-tab="${nav.tab}"] .app-edit-toggle[aria-pressed="true"]`)
  })

  //? The desktop sidebar (2.0.0-player.19): Home, Requests and You are their tabs' buttons, and so is
  //? the Library view showing; another Library view is that view at the Library's root - from another
  //? tab, or a page on the Library's, opened at its top (lib/appFrame.ts sidebarMove).
  const chooseFromSidebar = useCallback((item: SidebarId) => {
    const move = sidebarMove(item, libraryPick(), librarySongs())
    if (move.how === 'tab') {
      chooseTab(move.tab)
      return
    }
    if (move.how === 'queue') {
      openQueue()
      return
    }
    const away = router.nav.tab !== 'library' || router.nav.stacks.library.length > 0
    chooseLibrary(move.pick)
    if (!away) return
    scrolls.current.delete(scrollKey({ tab: 'library', page: null }))
    router.root('library')
  }, [])
  //? the sidebar's search field typed into: Search's results, at its root
  const showSearch = useCallback(() => {
    if (router.nav.tab === 'search' && !router.nav.stacks.search.length) return
    router.root('search')
  }, [])

  /**
   * "Go to album" - the menu's row, Now Playing's "Artist — Album" line, Info's album card: every
   * sheet closes and the song's album opens on the tab showing, as a tile there would open it.
   * Drawn from the answer it was played from when that is in hand, so the page has its cover and
   * artist at once. The ••• button is in a sheet that is closing, so focus isn't sent back to it.
   */
  //? A desktop's Info as a drawer (1024-1279px) lies over the page these open, so it goes too - focus
  //? given back to nothing, the page opening takes it; as a third column it stays beside the page
  const leaveInfoDrawer = () => {
    if (!liesOver(panel, infoPanel ? 'info' : 'none')) return
    infoOpener.current = null
    setInfoPanel(false)
  }

  /** Info's artist card: every sheet closes and the artist's page opens on the tab showing. */
  const toArtist = (artist: { id: string; name: string }) => {
    leaveInfoDrawer()
    moreOpener.current = null
    closeSheet()
    openArtist({ navidrome: artist.id, name: artist.name })
  }

  const goToAlbum = (track: NonNullable<Player['track']>) => {
    if (!track.albumId) return
    leaveInfoDrawer()
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
  //? the Sources sheet over the page: a phone's - a desktop's panel leaves the page beside it showing
  const sourcesOver = sourcesOpen && !desktop
  //? the album-you-don't-have a desktop's Sources panel is showing a Get of, and the pressing it searched:
  //? its page shows Get pressed only for that pressing, and follows another chosen (2.0.0-player.19)
  const sourcesGroup = desktop && sourcesOpen ? getting?.from ?? null : null
  const sourcesPressing = sourcesGroup ? getting?.release.release_mbid ?? null : null
  //? Search's root is what shows, with nothing over it: a Get chip's lookup still out when it stops
  //? being so is called off, so its late answer opens no sheet over what you went to instead
  const searchActive = nav.tab === 'search' && nav.stacks.search.length === 0 && !sheetOpen && !sourcesOver
  //? You's tab is the one showing: its Getting albums are asked again each time it is opened
  const youCurrent = nav.tab === 'you'
  //? Requests' root is what shows, with nothing over it: its Done rows' albums are looked for only
  //? then, and a tap's look still out when it stops being so opens nothing
  const requestsActive = watching === 'requests' && !sourcesOver
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
        {librarySeen && <Library onOpen={openAlbum} onOpenArtist={openLibraryArtist} />}
      </NeedsNavidrome>
    ),
    [status, librarySeen],
  )
  const search = useMemo(
    () => <Search shown={searchSeen} active={searchActive} status={status} onRetry={checkNavidrome} onOpenAlbum={openAlbum} onOpenGroup={openGroup} onOpenArtist={openLibraryArtist} onGet={openSources} />,
    [status, searchSeen, searchActive],
  )
  const you = useMemo(
    () => (
      <You
        shown={youSeen}
        current={youCurrent}
        opensAs={opensAs}
        onOpensAs={chooseOpensAs}
        windDown={windDown}
        onWindDown={chooseWindDown}
        desktop={desktop}
        needsLook={needsLook}
        onNeedsLook={openQueue}
      />
    ),
    [youSeen, youCurrent, opensAs, windDown, desktop, needsLook],
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
        shown={pageShown && nav.tab === tab && !sourcesOver}
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

  //? Needs a look (2.0.0-player.25): the review queue, a desktop's - on a phone a short note, asking
  //? nothing. Its rows open the Edit panel on their folder; it is told which folder the panel has open
  //? for it (`editing`), and whether it is what shows
  const queueView = (tab: Tab, page: Page) => (
    <NeedsALook
      desktop={desktop}
      shown={pageShown && nav.tab === tab}
      facet={page.facet ?? null}
      onFacet={pickFacet}
      onBack={back}
      backLabel={backLabel(nav, tab) ?? TAB_LABELS[tab]}
      editing={editOpen && isFolderRequest(edit) ? edit.folder : null}
      onEdit={openFolderEdit}
      onCloseEdit={closeEdit}
    />
  )

  const pageView = (tab: Tab, page: Page, player: Player) =>
    page.kind === 'queue' ? queueView(tab, page) : page.kind === 'artist' ? artistView(tab, page) : page.kind === 'group' ? (
      <ReleaseGroupPage
        id={page.id}
        release={page.release ?? null}
        preview={groupPreviews.current.get(page.id) ?? null}
        shown={pageShown && nav.tab === tab && !sourcesOver}
        onBack={back}
        backLabel={backLabel(nav, tab) ?? TAB_LABELS[tab]}
        onPick={pickPressing}
        onGet={openSources}
        onArtist={openCreditedArtist}
        desktop={desktop}
        sourcesPressing={sourcesGroup === page.id ? sourcesPressing : null}
        onCloseSources={closeSources}
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
          onEdit={desktop && admin ? toggleEdit : undefined}
          editing={editOpen && edit?.album?.id === page.id}
          refresh={refreshes.get(page.id) ?? 0}
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
    [nav, status, playingId, player.playing, sourcesOpen, pageShown, desktop, sourcesGroup, sourcesPressing, admin, editOpen, edit, refreshes],
  )

  const playing = player.track
  const toAlbum = playing?.albumId ? () => goToAlbum(playing) : null
  const playedFrom = playing ? playedAlbum(playing.albumId) : null
  //? Info: a sheet over Now Playing on a phone; on a desktop the side panel the player bar opens
  const infoOpen = desktop ? infoPanel : sheetOpen && over === 'info'
  //? what fills Info > About in, asked as it opens (2.0.0-player.17)
  const infoDetails = useInfoDetails(infoOpen, playing, playedFrom)
  //? what is behind a sheet - Now Playing, or the Sources sheet - is inert while it shows; a desktop's
  //? side panel leaves the page beside it as it is
  //? (2.0.0-player.20: and behind the desktop's visualizer, which covers the whole screen)
  const visualizerShown = desktop && visualizing
  const covered = (!desktop && (sheetOpen || sourcesOpen)) || visualizerShown
  //? the main area makes room for a desktop's panel only as a third column; a drawer lies over its edge
  //? (lib/appFrame.ts)
  const side = sideOf(frame, { sources: sourcesOpen, info: infoPanel, edit: editOpen })

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
        <div class={`pl-app app-shell${player.track && !desktop ? ' has-mini' : ''}${desktop ? ' app-desk' : ''}${makesRoom(panel, side) ? ' has-side' : ''}${liesOver(panel, side) ? ' has-drawer' : ''}`}>
          {/* what Now Playing covers: inert while it is open */}
          <div class="app-behind" aria-hidden={covered} inert={covered}>
            {/* a desktop's sidebar, in the tab bar's place (2.0.0-player.19) - first, as it is on screen */}
            {desktop && (
              <Sidebar
                current={sidebarCurrent(nav.tab, libraryView, hasSongs, topNow)}
                library={libraryItems(hasSongs)}
                arriving={view.arriving.length}
                admin={admin}
                needsLook={needsLook}
                onSelect={chooseFromSidebar}
                onSearch={showSearch}
              />
            )}
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

            {/* the player: the mini player over the tab bar, or a desktop's player bar */}
            {desktop ? (
              <PlayerBar player={player} onAlbum={toAlbum} onInfo={toggleInfo} infoOpen={infoPanel} onVisualizer={openVisualizer} />
            ) : (
              <MiniPlayer player={player} onOpen={openSheet} />
            )}
            {!desktop && <TabBar current={nav.tab} onSelect={chooseTab} arriving={view.arriving.length} />}
          </div>
          {/* a Get's sources (2.0.0-player.15): over the page, under Now Playing's menu and Info - a desktop's side panel */}
          <Sources open={sourcesOpen} request={getting} opener={sourcesOpener} onClose={closeSources} onQueued={gotten} panel={panel} covered={visualizerShown} />
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
            open={infoOpen}
            opener={desktop ? infoOpener : moreOpener}
            onClose={desktop ? closeInfoPanel : closeOver}
            onAlbum={toAlbum}
            player={player}
            album={playedFrom}
            sentFormat={sentFormat}
            turntable={turntableSound}
            recording={turntableRecording}
            onRecord={recordTurntable}
            details={infoDetails}
            onArtist={toArtist}
            panel={panel}
            covered={visualizerShown}
          />
          {/* the album page's Edit panel (2.0.0-player.21) - the desktop's alone, in its frame only */}
          {desktop && <EditPanel open={editOpen} request={edit} opener={editOpener} onClose={closeEdit} onChanged={albumChanged} panel={panel} covered={visualizerShown} />}
          {/* what became of a pin, said over everything (2.0.0-player.18) */}
          <PinNotice />
          {/* the desktop's full-screen visualizer, over everything (2.0.0-player.20) */}
          <Visualizer open={visualizerShown} player={player} opener={visualizerOpener} onClose={closeVisualizer} />
        </div>
      </ActionsContext.Provider>
    </PlayerContext.Provider>
  )
}
