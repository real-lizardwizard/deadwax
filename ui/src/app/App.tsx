import type { JSX } from 'preact'
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { createRouter, type Router, type StorageLike } from '../lib/appHistory'
import { TAB_LABELS, TABS, backLabel, currentRoute, formatRoute, type Nav, type Page, type Tab } from '../lib/appRoutes'
import { AlbumPage } from '../player/AlbumPage'
import { navidromeStatus, type Album, type NavidromeStatus } from '../player/api'
import { Library } from '../player/Library'
import { MiniPlayer } from '../player/MiniPlayer'
import { NowPlaying } from '../player/NowPlaying'
import { usePlayer, type Player } from '../player/usePlayer'
import { ActionsContext, PlayerContext, pickActions } from './context'
import { Home } from './Home'
import { NeedsNavidrome } from './NeedsNavidrome'
import { Placeholder } from './Placeholder'
import { TabBar } from './TabBar'
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
 */
export function App() {
  const player = usePlayer()
  //? the engine's actions are made once, in its own useMemo, and never change: taken once here
  const actions = useMemo(() => pickActions(player), [])

  const scrolls = useRef(new Map<string, number>())
  const previews = useRef(new Map<string, Album>())
  const router: Router = useMemo(
    () =>
      createRouter({
        history: window.history,
        hash: () => location.hash,
        storage: sessionStore,
        //? the scroll of the route being left, read before the router moves on from it
        leaving: () => scrolls.current.set(formatRoute(currentRoute(router.nav)), window.scrollY),
        show: (next) => setNav(next),
      }),
    [],
  )
  const [nav, setNav] = useState<Nav>(() => router.nav)

  const [status, setStatus] = useState<NavidromeStatus | null>(null)
  const [sheetOpen, setSheetOpen] = useState(false)
  const [youSeen, setYouSeen] = useState(nav.tab === 'you')

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

  const routeKey = formatRoute(currentRoute(nav))
  useLayoutEffect(() => {
    window.scrollTo(0, scrolls.current.get(routeKey) ?? 0)
  }, [routeKey])

  useEffect(() => {
    if (nav.tab === 'you') setYouSeen(true)
  }, [nav.tab])

  const openAlbum = useCallback((album: Album) => {
    previews.current.delete(album.id)
    previews.current.set(album.id, album)
    if (previews.current.size > PREVIEWS_KEPT) {
      const [oldest] = previews.current.keys()
      if (oldest !== undefined) previews.current.delete(oldest)
    }
    const page: Page = { kind: 'album', id: album.id, label: album.name }
    const address = formatRoute({ tab: router.nav.tab, page })
    //? a page opened afresh starts at its top, even one visited before - not the one showing (a double tap)
    if (address !== formatRoute(currentRoute(router.nav))) scrolls.current.delete(address)
    router.open(page)
  }, [])

  const back = useCallback(() => router.back(), [])

  const chooseTab = useCallback((tab: Tab) => {
    if (router.tab(tab) === 'scroll-to-top') {
      const still = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
      window.scrollTo({ top: 0, behavior: still ? 'auto' : 'smooth' })
    }
  }, [])

  //? Focus goes into Now Playing as it opens (NowPlaying moves it to its close button) and back to
  //? what had it as it closes - the mini player, when a keyboard opened it. Taken at the tap, before
  //? the page behind turns inert and the browser moves focus off an element it can no longer hold.
  const opener = useRef<HTMLElement | null>(null)
  const openSheet = useCallback(() => {
    const active = document.activeElement
    opener.current = active instanceof HTMLElement && active !== document.body ? active : null
    setSheetOpen(true)
  }, [])
  const closeSheet = useCallback(() => setSheetOpen(false), [])
  useLayoutEffect(() => {
    if (sheetOpen || !opener.current) return
    opener.current.focus({ preventScroll: true })
    opener.current = null
  }, [sheetOpen])

  //? The tab roots, memoised: they read no player state, so the music playing leaves them alone.
  //? You reads the player from context, and re-renders with it by itself.
  const roots = useMemo<Record<Tab, JSX.Element>>(
    () => ({
      home: <Home status={status} onRetry={checkNavidrome} onOpen={openAlbum} />,
      library: (
        <NeedsNavidrome status={status} onRetry={checkNavidrome} title={TAB_LABELS.library}>
          <Library onOpen={openAlbum} />
        </NeedsNavidrome>
      ),
      search: (
        <Placeholder
          title={TAB_LABELS.search}
          what="Searching MusicBrainz, choosing a pressing and getting it from Soulseek are on the main page until the app has them."
        />
      ),
      requests: (
        <Placeholder
          title={TAB_LABELS.requests}
          what="Downloads in progress, and how the finished ones ended, are in the main page's Downloads panel until the app has them."
        />
      ),
      you: <You shown={youSeen} />,
    }),
    [status, youSeen],
  )

  const pageView = (tab: Tab, page: Page, player: Player) => (
    <NeedsNavidrome status={status} onRetry={checkNavidrome} title={TAB_LABELS[tab]}>
      <AlbumPage
        id={page.id}
        preview={previews.current.get(page.id) ?? null}
        player={player}
        onBack={back}
        backLabel={backLabel(nav, tab) ?? TAB_LABELS[tab]}
      />
    </NeedsNavidrome>
  )

  return (
    <PlayerContext.Provider value={player}>
      <ActionsContext.Provider value={actions}>
        <div class={`pl-app app-shell${player.track ? ' has-mini' : ''}`}>
          {/* what Now Playing covers: inert while it is open */}
          <div class="app-behind" aria-hidden={sheetOpen} inert={sheetOpen}>
            {TABS.map((tab) => {
              const stack = nav.stacks[tab]
              const top = stack[stack.length - 1] ?? null
              return (
                <div key={tab} class="app-pane" data-tab={tab} hidden={nav.tab !== tab}>
                  <div hidden={top !== null}>{roots[tab]}</div>
                  {top && <div key={pageKey(tab, top)}>{pageView(tab, top, player)}</div>}
                </div>
              )
            })}

            <MiniPlayer player={player} onOpen={openSheet} />
            <TabBar current={nav.tab} onSelect={chooseTab} />
          </div>
          <NowPlaying player={player} open={sheetOpen} onClose={closeSheet} />
        </div>
      </ActionsContext.Provider>
    </PlayerContext.Provider>
  )
}
