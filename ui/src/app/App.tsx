import type { JSX } from 'preact'
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { createRouter, type Router, type StorageLike } from '../lib/appHistory'
import { TAB_LABELS, TABS, backLabel, currentRoute, formatRoute, type Nav, type Page, type Tab } from '../lib/appRoutes'
import type { Look } from '../lib/turntable'
import { AlbumPage } from '../player/AlbumPage'
import { navidromeStatus, playedAlbum, sentFormat, type Album, type NavidromeStatus } from '../player/api'
import { Library } from '../player/Library'
import { MiniPlayer } from '../player/MiniPlayer'
import { NowPlaying } from '../player/NowPlaying'
import { usePlayer, type Player } from '../player/usePlayer'
import { readPlayerOpensAs, writePlayerOpensAs } from '../state/persisted'
import { ActionMenu } from './ActionMenu'
import { ActionsContext, PlayerContext, pickActions } from './context'
import { Home } from './Home'
import { InfoSheet } from './InfoSheet'
import { NeedsNavidrome } from './NeedsNavidrome'
import { Placeholder } from './Placeholder'
import { TabBar } from './TabBar'
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
  //? what is over Now Playing: its ••• menu, or Info - never both
  const [over, setOver] = useState<'none' | 'menu' | 'info'>('none')
  const [youSeen, setYouSeen] = useState(nav.tab === 'you')
  //? "Now Playing opens as", kept on this device
  const [opensAs, setOpensAs] = useState<Look>(readPlayerOpensAs)
  const chooseOpensAs = useCallback((look: Look) => {
    writePlayerOpensAs(look)
    setOpensAs(look)
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

  //? What each sheet gives focus back to as it closes, taken in the tap that opened it: the button
  //? focuses itself first (WebKit doesn't focus a tapped button), before the page behind turns
  //? inert. The sheets do the rest themselves (useSheet.ts).
  const sheetOpener = useRef<HTMLElement | null>(null)
  const moreOpener = useRef<HTMLElement | null>(null)
  const openSheet = useCallback((event: MouseEvent) => {
    sheetOpener.current = takeOpener(event)
    setSheetOpen(true)
  }, [])
  const closeSheet = useCallback(() => {
    setOver('none')
    setSheetOpen(false)
  }, [])
  const openMenu = useCallback((event: MouseEvent) => {
    moreOpener.current = takeOpener(event)
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
      you: <You shown={youSeen} opensAs={opensAs} onOpensAs={chooseOpensAs} />,
    }),
    [status, youSeen, opensAs],
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

  const playing = player.track
  const toAlbum = playing?.albumId ? () => goToAlbum(playing) : null

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
          <NowPlaying
            player={player}
            open={sheetOpen}
            covered={over !== 'none'}
            opener={sheetOpener}
            onClose={closeSheet}
            onMore={openMenu}
            onAlbum={toAlbum ?? closeSheet}
            openAs={opensAs}
          />
          {/* over Now Playing: its menu, then Info - the menu first, so where one closes as the
              other opens, focus ends in the one that opened */}
          <ActionMenu
            open={sheetOpen && over === 'menu'}
            opener={over === 'info' ? undefined : moreOpener}
            onClose={closeOver}
            onInfo={openInfo}
            onAlbum={toAlbum}
          />
          <InfoSheet
            open={sheetOpen && over === 'info'}
            opener={moreOpener}
            onClose={closeOver}
            onAlbum={toAlbum}
            player={player}
            album={playing ? playedAlbum(playing.albumId) : null}
            sentFormat={sentFormat}
          />
        </div>
      </ActionsContext.Provider>
    </PlayerContext.Provider>
  )
}
