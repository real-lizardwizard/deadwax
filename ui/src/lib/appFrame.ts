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
 * beside the album they edit) - the desktop's alone, with no sheet on a phone: crossing back under
 * 1024px closes it.
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
 *  any puts the others away (App). `edit` is the album page's Edit panel (2.0.0-player.21). */
export type Side = 'none' | 'sources' | 'info' | 'edit'

/** What the side panel shows, from what is open: Info when it is (it is opened over the others -
 *  opening any puts the rest away), then the Edit panel, then Sources; on a phone none is a panel. */
export function sideOf(frame: Frame, open: { sources: boolean; info: boolean; edit: boolean }): Side {
  if (frame === 'phone') return 'none'
  return open.info ? 'info' : open.edit ? 'edit' : open.sources ? 'sources' : 'none'
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
 * Back to the phone: the Info panel - Info is a sheet over Now Playing there, which isn't open - and
 * the Edit panel (2.0.0-player.21), which a phone has no board for, and so no sheet.
 */
export function closesOnCrossing(to: Frame): { nowPlaying: boolean; infoPanel: boolean; editPanel: boolean } {
  return to === 'desktop'
    ? { nowPlaying: true, infoPanel: false, editPanel: false }
    : { nowPlaying: false, infoPanel: true, editPanel: true }
}

/* ===== the sidebar ===== */

/**
 * What the Library shows: Navidrome's albums, artists or songs - and, on a desktop, "Recently added"
 * (the sidebar's first Library view, as the board lists it): the albums, newest first, as a view of
 * its own, so the Albums view keeps the order chosen for it. It is the desktop's alone - a phone has
 * three chips, and shows the albums for it - and isn't kept on the device (state/persisted.ts keeps
 * albums, artists or songs).
 */
export type LibraryPick = 'recent' | 'albums' | 'artists' | 'songs'

/** The sidebar's items - `queue` is Managing's "Needs a look" (2.0.0-player.25), an admin's. */
export type SidebarId = 'home' | 'requests' | LibraryPick | 'queue' | 'you'

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

/** What the Library's title says on a desktop, for each view - the sidebar's own words. */
export const LIBRARY_TITLES: Readonly<Record<LibraryPick, string>> = {
  recent: 'Recently added',
  albums: 'Albums',
  artists: 'Artists',
  songs: 'Songs',
}

/** Managing's own item (2.0.0-player.25): the review queue, above the link to the main page. */
export const SIDEBAR_QUEUE: SidebarItem = { id: 'queue', label: 'Needs a look' }

/** The Library's views the sidebar lists: Songs left out when Navidrome's empty search lists none,
 *  as the phone leaves out its chip (null: not known yet, so it stays). */
export function libraryItems(hasSongs: boolean | null): SidebarItem[] {
  return SIDEBAR_LIBRARY.filter((item) => item.id !== 'songs' || hasSongs !== false)
}

/** The view the Library is showing for a pick: Songs falls back to the albums when Navidrome lists
 *  none; "Recently added" is the desktop's, and a phone shows the albums for it. */
export function shownPick(pick: LibraryPick, hasSongs: boolean | null, frame: Frame): LibraryPick {
  if (pick === 'songs' && hasSongs === false) return 'albums'
  if (pick === 'recent' && frame === 'phone') return 'albums'
  return pick
}

/** The sidebar item for where the app is: its tab - and in the Library, the view showing. Search has
 *  none: its place is the field, which says what it is searching for. Needs a look is its own item
 *  while its page is the one on top (`page`, the tab's top page), whatever tab it was pushed on. */
export function sidebarCurrent(tab: Tab, pick: LibraryPick, hasSongs: boolean | null, page: Page | null = null): SidebarId | null {
  if (page?.kind === 'queue') return 'queue'
  if (tab === 'search') return null
  if (tab === 'library') return shownPick(pick, hasSongs, 'desktop')
  return tab
}

/**
 * What a sidebar item does, from where the app is. Home, Requests and You are their tabs' buttons -
 * the tab as it was left, or back to its root when it is showing (lib/appRoutes.ts's selectTab).
 * So is the Library view that is showing. Another Library view is that view, at the Library's root.
 */
export type SidebarMove =
  | { how: 'tab'; tab: Tab }
  | { how: 'view'; tab: 'library'; pick: LibraryPick }
  /** Needs a look: its page, on You (App's openQueue) */
  | { how: 'queue'; tab: 'you' }

export function sidebarMove(item: SidebarId, pick: LibraryPick, hasSongs: boolean | null): SidebarMove {
  if (item === 'queue') return { how: 'queue', tab: 'you' }
  if (item === 'home' || item === 'requests' || item === 'you') return { how: 'tab', tab: item }
  if (item === shownPick(pick, hasSongs, 'desktop')) return { how: 'tab', tab: 'library' }
  return { how: 'view', tab: 'library', pick: item }
}
