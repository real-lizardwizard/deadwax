/**
 * Which frame the app at /player/ is drawn in (2.0.0-player.19) - pure, so the rules are pinned by
 * ui/test/routes.sim.cjs rather than found by resizing a window.
 *
 * ONE APP, TWO FRAMES. James (2026-09-29): desktop is "the same app with a desktop frame, not a
 * second app". Below DESKTOP_MIN (1024px) it is the phone's: five tabs along the bottom, the mini
 * player over them, and Sources and Info as sheets over everything. From 1024px it is the desktop's,
 * as DesktopLibrary.dc.html draws it: a sidebar down the left (Home, Requests with its count, the
 * Library's views, Managing, the search field, You), the page in the main area, and a player bar
 * along the bottom. The same tabs, stacks and addresses underneath - lib/appRoutes.ts - so a link,
 * a reload and the back button mean the same thing in both, and crossing 1024px while music plays
 * changes the chrome around the pages and nothing else (App chooses the frame BELOW itself: the
 * engine is never made again, and the one audio element plays on).
 *
 * THE PANEL RULE. Sources and Info are a sheet on a phone - over everything, the page behind inert.
 * On a desktop they are a side panel that leaves the page usable, since the point of the desktop's
 * Get is the pressings and the sources side by side (DesktopRequest.dc.html: the Sources panel
 * searches again as another pressing is chosen): a third column from COLUMN_MIN (1280px), where the
 * main area makes room for it, and a drawer over the main area's right edge between 1024 and 1279 -
 * at 1024 - 232 - 470 = 322px a third column would leave no room for a tracklist (so what the page
 * needs beside a drawer keeps to the part it leaves in view, `liesOver`). ONE panel at a time: opening
 * Info puts Sources away and the other way round (App; `sideOf` says which shows). Since
 * 2.0.0-player.21 the album page's Edit panel is a third kind (DesktopManage.dc.html: the editors
 * beside the album they edit) - and since 2.0.0-player.47 a sheet over the whole screen on a phone,
 * as the artist page's panel is (2.0.0-player.45): it stays open across 1024px, a panel one side and
 * a sheet the other.
 *
 * The breakpoints are the stylesheets' too (interface/player/app-desktop.css, theme.css's desktop
 * tokens): tests/test_app_desktop_css.py reads these constants and holds every @media there to them.
 */

import type { Page, Tab } from './appRoutes'

/** From this width (CSS px, the viewport's - as a media query reads it) the desktop frame. */
export const DESKTOP_MIN = 1024
/** ...and from this one, a side panel is a third column rather than a drawer over the page. */
export const COLUMN_MIN = 1280

export const DESKTOP_QUERY = `(min-width: ${DESKTOP_MIN}px)`
export const COLUMN_QUERY = `(min-width: ${COLUMN_MIN}px)`

export type Frame = 'phone' | 'desktop'

/** How Sources and Info are drawn: a sheet (phone), a drawer over the main area, or a third column. */
export type PanelStyle = 'sheet' | 'drawer' | 'column'

export interface FrameState {
  frame: Frame
  panel: PanelStyle
}

/** The frame for a viewport `width` px wide. */
export function frameFor(width: number): FrameState {
  if (width < DESKTOP_MIN) return { frame: 'phone', panel: 'sheet' }
  return { frame: 'desktop', panel: width < COLUMN_MIN ? 'drawer' : 'column' }
}

/** The frame from the two media queries' answers, as matchMedia gives them. */
export function frameOf(desktop: boolean, column: boolean): FrameState {
  if (!desktop) return { frame: 'phone', panel: 'sheet' }
  return { frame: 'desktop', panel: column ? 'column' : 'drawer' }
}

/** A sheet is modal: the page behind it inert and still. A desktop panel leaves the page as it is. */
export function panelIsModal(panel: PanelStyle): boolean {
  return panel === 'sheet'
}

/* ===== the desktop's one side panel ===== */

/** What the desktop's side panel shows - one at a time: the column has room for one, and opening
 *  any puts the others away (App). `edit` is the album page's Edit panel (2.0.0-player.21), `artist`
 *  the artist page's (2.0.0-player.45: Artist images…, Move albums to …, Which artist is this?), `upnext`
 *  the queue (2.0.0-player.57, app/UpNext.tsx), opened from the player bar as Info is. */
export type Side = 'none' | 'sources' | 'info' | 'upnext' | 'edit' | 'artist'

/** What the side panel shows, from what is open: Info when it is (it is opened over the others -
 *  opening any puts the rest away), then Up Next, then the Edit panel, then the artist's, then Sources;
 *  on a phone none is a panel (the artist's and, since 2.0.0-player.47, the Edit panel are sheets there,
 *  as Sources is; Up Next is a sheet over Now Playing, as Info is). */
export function sideOf(frame: Frame, open: { sources: boolean; info: boolean; edit: boolean; artist?: boolean; upnext?: boolean }): Side {
  if (frame === 'phone') return 'none'
  return open.info ? 'info' : open.upnext ? 'upnext' : open.edit ? 'edit' : open.artist ? 'artist' : open.sources ? 'sources' : 'none'
}

/** Whether the main area makes room for the panel: only a third column does; a drawer lies over it. */
export function makesRoom(panel: PanelStyle, side: Side): boolean {
  return panel === 'column' && side !== 'none'
}

/**
 * Whether the panel lies over the main area's right edge - a drawer, showing (App's `.has-drawer`).
 * What the page needs beside it then keeps to the part left in view: the album you don't have's Get
 * and pressing (app-desktop.css). And a drawer closes as you go to an album or an artist from the
 * player - the bar's "Artist — Album", Info's own cards - since it would lie over the page you asked
 * for; a third column stays beside it.
 */
export function liesOver(panel: PanelStyle, side: Side): boolean {
  return panel === 'drawer' && side !== 'none'
}

/**
 * What crossing into another frame closes. Into the desktop: Now Playing and whatever is over it
 * (its menu, Info as its sheet) - the desktop has no Now Playing sheet (its player bar is the
 * player, and the turntable is the phone's alone); the Sources sheet stays open, becoming the panel.
 * Back to the phone: the Info panel - Info is a sheet over Now Playing there, which isn't open. The
 * artist page's panel (2.0.0-player.45) and the Edit panel (since 2.0.0-player.47 - until then a
 * phone had no editor, and crossing back closed it) stay open either way, a panel on one side and a
 * full-screen sheet on the other, as Sources does. The Up Next panel (2.0.0-player.57) goes back to the
 * phone as the Info panel does: it is a sheet over Now Playing there, which isn't open.
 */
export function closesOnCrossing(to: Frame): { nowPlaying: boolean; infoPanel: boolean; upNextPanel: boolean } {
  return to === 'desktop'
    ? { nowPlaying: true, infoPanel: false, upNextPanel: false }
    : { nowPlaying: false, infoPanel: true, upNextPanel: true }
}

/* ===== the sidebar ===== */

/**
 * What the Library shows: Navidrome's albums, artists or songs - and "Recently added" (the sidebar's
 * first Library view, as the board lists it): the albums, newest first, as a view of its own, so the
 * Albums view keeps the order chosen for it. It isn't kept on the device (state/persisted.ts keeps the
 * rest). (2.0.0-player.59) Each is also a SECTION, a page of its own on a phone (lib/appRoutes.ts
 * SECTION_IDS): the phone's Library root lists them as rows - Recently added as its grid's See all.
 *
 * YOUR LIBRARY AND BROWSE (2.0.0-player.52, step 6 of the multi-user plan): with logins on, for somebody
 * with a library of their own (`personal`), the Library is YOURS - 'albums' your starred albums, 'artists'
 * the artists of them, 'recent' yours newest first - and BROWSE is the store, everything deadwax holds:
 * 'store' every album, 'storeArtists' every artist, 'songs' every song (Navidrome lists songs store-wide,
 * so Songs is Browse's). With logins off - and for the break-glass admin - there is no Browse: the store
 * is the library, and 'store' and 'storeArtists' (kept on a device that had them) show as 'albums' and
 * 'artists' - exactly the Library as it always was.
 */
export type LibraryPick = 'recent' | 'albums' | 'artists' | 'songs' | 'store' | 'storeArtists'

/** Browse's views (2.0.0-player.52): the store's albums, artists and songs. */
export const BROWSE_PICKS: readonly LibraryPick[] = ['store', 'storeArtists', 'songs']

/** Whether a pick is Browse's (the store) - only ever with a library of your own. */
export function isBrowse(pick: LibraryPick, personal: boolean): boolean {
  return personal && BROWSE_PICKS.includes(pick)
}

/** The sidebar's items - `queue` is Managing's "Needs a look" (2.0.0-player.25), `care` its "Library
 *  care" (2.0.0-player.42), `settings` and `log` its "Settings" and "Log" (2.0.0-player.33) - an admin's;
 *  `playlists` (2.0.0-player.58) the Playlists group's "All playlists" (each playlist under it is a button of
 *  its own, by id - Sidebar's `onPlaylist`). */
export type SidebarId = 'home' | 'requests' | LibraryPick | 'playlists' | 'queue' | 'care' | 'settings' | 'log' | 'you'

export interface SidebarItem {
  id: SidebarId
  label: string
}

/** Home and Requests, at the top, as the board has them. */
export const SIDEBAR_TOP: readonly SidebarItem[] = [
  { id: 'home', label: 'Home' },
  { id: 'requests', label: 'Requests' },
]

/** The Library's views, under their group label. */
export const SIDEBAR_LIBRARY: readonly SidebarItem[] = [
  { id: 'recent', label: 'Recently added' },
  { id: 'albums', label: 'Albums' },
  { id: 'artists', label: 'Artists' },
  { id: 'songs', label: 'Songs' },
]

/** Browse's views under their own group label (2.0.0-player.52) - the store's. */
export const SIDEBAR_BROWSE: readonly SidebarItem[] = [
  { id: 'store', label: 'Albums' },
  { id: 'storeArtists', label: 'Artists' },
  { id: 'songs', label: 'Songs' },
]

/** What the Library's title says on a desktop, for each view - the sidebar's own words. */
export const LIBRARY_TITLES: Readonly<Record<LibraryPick, string>> = {
  recent: 'Recently added',
  albums: 'Albums',
  artists: 'Artists',
  songs: 'Songs',
  //? never shown with logins off (shownPick turns them into albums and artists) - as the sidebar would say
  store: 'Albums',
  storeArtists: 'Artists',
}

/** ...and with a library of your own (2.0.0-player.52): yours, and the store's. */
export const PERSONAL_TITLES: Readonly<Record<LibraryPick, string>> = {
  recent: 'Recently added',
  albums: 'Your albums',
  artists: 'Your artists',
  songs: 'Songs in the store',
  store: 'Albums in the store',
  storeArtists: 'Artists in the store',
}

/** The desktop Library's title for a view. */
export function libraryTitle(pick: LibraryPick, personal = false): string {
  return (personal ? PERSONAL_TITLES : LIBRARY_TITLES)[pick]
}

/** The Playlists group's first item (2.0.0-player.58): the Playlists page - the playlists listed under it are buttons
 *  of their own (Sidebar), up to lib/playlists.ts SIDEBAR_PLAYLISTS_MAX. */
export const SIDEBAR_PLAYLISTS: SidebarItem = { id: 'playlists', label: 'All playlists' }

/** Managing's own item (2.0.0-player.25): the review queue, above the link to the main page. */
export const SIDEBAR_QUEUE: SidebarItem = { id: 'queue', label: 'Needs a look' }

/** Managing's Library care (2.0.0-player.42), after Needs a look: Rescan and the bulk runs. */
export const SIDEBAR_CARE: SidebarItem = { id: 'care', label: 'Library care' }

/** Managing's server settings and event log (2.0.0-player.33), after Library care. */
export const SIDEBAR_SETTINGS: SidebarItem = { id: 'settings', label: 'Settings' }
export const SIDEBAR_LOG: SidebarItem = { id: 'log', label: 'Log' }

/** The Library's views the sidebar lists: Songs left out when Navidrome's empty search lists none,
 *  as the phone's root leaves out its row (null: not known yet, so it stays) - the phone's root lists these
 *  too, Recently added aside (2.0.0-player.59). With a library of your own (2.0.0-player.52) the Library's
 *  are yours - Recently added, Albums, Artists - and Songs is Browse's. */
export function libraryItems(hasSongs: boolean | null, personal = false): SidebarItem[] {
  if (personal) return SIDEBAR_LIBRARY.filter((item) => item.id !== 'songs')
  return SIDEBAR_LIBRARY.filter((item) => item.id !== 'songs' || hasSongs !== false)
}

/** Browse's views the sidebar lists (2.0.0-player.52): none with logins off; with a library of your own the
 *  store's albums, artists and songs - Songs left out as above. */
export function browseItems(hasSongs: boolean | null, personal = false): SidebarItem[] {
  if (!personal) return []
  return SIDEBAR_BROWSE.filter((item) => item.id !== 'songs' || hasSongs !== false)
}

/** The view the Library is showing for a pick: Songs falls back to the albums when Navidrome lists
 *  none - the store's, Browse's own, with a library of your own; "Recently added" is the desktop's, and a
 *  phone shows the albums for it. With logins off Browse's two (kept on a device) are the albums and the
 *  artists - the store is the library then. */
export function shownPick(pick: LibraryPick, hasSongs: boolean | null, frame: Frame, personal = false): LibraryPick {
  if (!personal && pick === 'store') return 'albums'
  if (!personal && pick === 'storeArtists') return 'artists'
  if (pick === 'songs' && hasSongs === false) return personal ? 'store' : 'albums'
  if (pick === 'recent' && frame === 'phone') return 'albums'
  return pick
}

/** The sidebar item for where the app is: its tab - and in the Library, the view showing. Search has
 *  none: its place is the field, which says what it is searching for. Needs a look is its own item
 *  while its page is the one on top (`page`, the tab's top page), whatever tab it was pushed on.
 *  (2.0.0-player.59) `base`: the Library stack's first page - a section page there (pushed on a phone, then the
 *  window widened, or reached by its address) names its own view, whatever is pushed over it, until it goes. */
export function sidebarCurrent(
  tab: Tab, pick: LibraryPick, hasSongs: boolean | null, page: Page | null = null, personal = false, base: Page | null = null,
): SidebarId | null {
  //? (2.0.0-player.58) the Playlists page and a playlist's - before the Library tab's own branch: App draws a listed
  //? playlist's own row current in place of All playlists
  if (page?.kind === 'playlists' || page?.kind === 'playlist') return 'playlists'
  //? (2.0.0-player.59) a section page at the Library stack's foot - after the playlists, so one over it names them
  if (tab === 'library' && base?.kind === 'section') return shownPick(base.id as LibraryPick, hasSongs, 'desktop', personal)
  if (page?.kind === 'queue') return 'queue'
  //? Library care (2.0.0-player.42), the same way
  if (page?.kind === 'care') return 'care'
  //? the server's settings and the log, the same way (2.0.0-player.33)
  if (page?.kind === 'settings') return 'settings'
  if (page?.kind === 'log') return 'log'
  if (tab === 'search') return null
  if (tab === 'library') return shownPick(pick, hasSongs, 'desktop', personal)
  return tab
}

/** The Managing pages but Needs a look, which opens through its own move: Library care
 *  (2.0.0-player.42), the server's settings and the log (2.0.0-player.33). */
export type ManagingKind = 'care' | 'settings' | 'log'

/**
 * What a sidebar item does, from where the app is. Home, Requests and You are their tabs' buttons -
 * the tab as it was left, or back to its root when it is showing (lib/appRoutes.ts's selectTab).
 * So is the Library view that is showing. Another Library view is that view, at the Library's root.
 */
export type SidebarMove =
  /** `pick` (2.0.0-player.59): the Library root's view to set first - the section page's own, so popping to the root
   *  draws the view the item named rather than the pick it was left on */
  | { how: 'tab'; tab: Tab; pick?: LibraryPick }
  | { how: 'view'; tab: 'library'; pick: LibraryPick }
  /** Needs a look: its page, on You (App's openQueue) */
  | { how: 'queue'; tab: 'you' }
  /** Library care, the server's settings, or the log: its page, on You (App's openManaging) */
  | { how: 'managing'; tab: 'you'; kind: ManagingKind }
  /** (2.0.0-player.58) All playlists: the Playlists page, on the Library (App's openPlaylistsPage) */
  | { how: 'playlists' }

export function sidebarMove(
  item: SidebarId, pick: LibraryPick, hasSongs: boolean | null, personal = false, base: Page | null = null,
): SidebarMove {
  if (item === 'playlists') return { how: 'playlists' }
  if (item === 'queue') return { how: 'queue', tab: 'you' }
  if (item === 'care' || item === 'settings' || item === 'log') return { how: 'managing', tab: 'you', kind: item }
  if (item === 'home' || item === 'requests' || item === 'you') return { how: 'tab', tab: item }
  //? (2.0.0-player.59) a section page at the Library stack's foot is the view the tab shows as it was left - so the
  //? item it names is "the tab", and any other, the pick's own included, is that view at the Library's root. The
  //? tab's button pops to the root when it is showing, so the root is given the section's view first (review of .59:
  //? Artists clicked over Artists' section dropped to a root drawing Albums)
  if (base?.kind === 'section') {
    const section = shownPick(base.id as LibraryPick, hasSongs, 'desktop', personal)
    if (item === section) return { how: 'tab', tab: 'library', pick: section }
    return { how: 'view', tab: 'library', pick: item }
  }
  if (item === shownPick(pick, hasSongs, 'desktop', personal)) return { how: 'tab', tab: 'library' }
  return { how: 'view', tab: 'library', pick: item }
}
