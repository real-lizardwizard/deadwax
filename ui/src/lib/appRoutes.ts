/**
 * Where the app at /player/ is: a tab, and the pages pushed on it - as pure functions, so the
 * rules are pinned by ui/test/routes.sim.cjs rather than found by tapping.
 *
 * THE ADDRESS IS THE HASH. StaticFiles has no fallback for page routes (`/player/library` is a
 * 404), so the route lives after the `#`:
 *
 *   #/home  #/library  #/search  #/requests  #/you     a tab's root
 *   #/<tab>/album/<id>                                 an album pushed on that tab
 *
 * The player's old `#/album/<id>` links still open: they are the Library's album, and the address
 * is rewritten to `#/library/album/<id>` in place. An empty hash is Home.
 *
 * PER-TAB STACKS, AS IN iOS. Each tab keeps its own pile of pages: an album opened from Home stays
 * under Home while you look at the Library, and coming back to Home finds it where you left it.
 * Tapping the tab you are on pops it to its root; tapping it again at the root scrolls to the top.
 * Back labels name the page below - the tab, or the page under this one.
 *
 * THE BROWSER'S HISTORY. Opening a page pushes a history entry, so the edge swipe and the back
 * button go back; switching tab replaces the entry with that tab's top page. `stepsBack` decides
 * whether going back can be history's own back (the entries below are the pages below, pushed in
 * this session) or has to replace the address, which is what makes a cold deep link work: there
 * is nothing below it to go back to, and back still lands on the tab's root. The browser's own
 * back or forward onto ANOTHER tab's entry is that tab chosen, as it was left (`browserMoved`).
 * lib/appHistory.ts drives all of this against the real history.
 */

export type Tab = 'home' | 'library' | 'search' | 'requests' | 'you'

/** The tab bar's order: You at the right end. */
export const TABS: readonly Tab[] = ['home', 'library', 'search', 'requests', 'you']

export const TAB_LABELS: Readonly<Record<Tab, string>> = {
  home: 'Home',
  library: 'Library',
  search: 'Search',
  requests: 'Requests',
  you: 'You',
}

/** A page pushed on a tab. `label` names it on the back button of a page pushed over it - never
 *  part of the address, and never part of what makes two pages the same one. */
export interface Page {
  kind: 'album'
  id: string
  label?: string
}

export interface Route {
  tab: Tab
  page: Page | null
}

const isTab = (value: string | undefined): value is Tab => TABS.includes(value as Tab)

/** An id out of the address; a stray `%` that isn't an escape is taken as it is, not thrown over. */
function decode(part: string): string {
  try {
    return decodeURIComponent(part)
  } catch {
    return part
  }
}

export function formatRoute(route: Route): string {
  const root = `#/${route.tab}`
  return route.page ? `${root}/${route.page.kind}/${encodeURIComponent(route.page.id)}` : root
}

/**
 * The route an address names, and the address it should read instead: the same string when it is
 * already right, the new home of a legacy `#/album/<id>`, `#/home` for an empty hash, and the
 * nearest sense for anything else (an unknown tab is Home, an unknown page is its tab's root).
 * A caller rewrites the address with replaceState whenever `canonical` differs from what it gave.
 */
export function parseHash(hash: string): { route: Route; canonical: string } {
  const path = hash.replace(/^#/, '').replace(/\?.*$/, '')
  const parts = path.split('/').filter((part, index) => index > 0 || part !== '')
  let route: Route

  if (parts[0] === 'album' && parts[1]) {
    route = { tab: 'library', page: { kind: 'album', id: decode(parts.slice(1).join('/')) } }
  } else if (isTab(parts[0])) {
    const tab = parts[0]
    route = parts[1] === 'album' && parts[2]
      ? { tab, page: { kind: 'album', id: decode(parts.slice(2).join('/')) } }
      : { tab, page: null }
  } else {
    route = { tab: 'home', page: null }
  }

  return { route, canonical: formatRoute(route) }
}

export const samePage = (a: Page | null | undefined, b: Page | null | undefined): boolean =>
  !!a && !!b && a.kind === b.kind && a.id === b.id

/* ===== the stacks ===== */

export interface Nav {
  tab: Tab
  /** each tab's pages above its root, bottom first; empty at the root */
  stacks: Readonly<Record<Tab, readonly Page[]>>
}

const emptyStacks = (): Record<Tab, readonly Page[]> => ({ home: [], library: [], search: [], requests: [], you: [] })

/** Where a page load starts: the address's tab, with its page (a cold deep link) on the root. */
export function startNav(route: Route): Nav {
  const stacks = emptyStacks()
  if (route.page) stacks[route.tab] = [route.page]
  return { tab: route.tab, stacks }
}

function top(nav: Nav, tab: Tab = nav.tab): Page | null {
  const stack = nav.stacks[tab]
  return stack[stack.length - 1] ?? null
}

export function currentRoute(nav: Nav): Route {
  return { tab: nav.tab, page: top(nav) }
}

function withStack(nav: Nav, tab: Tab, stack: readonly Page[]): Nav {
  return { tab, stacks: { ...nav.stacks, [tab]: stack } }
}

/** A page opened from the tab showing. Opening the page already on top changes nothing - a double
 *  tap on a tile is one page, not two. */
export function openPage(nav: Nav, page: Page): Nav {
  if (samePage(top(nav), page)) return nav
  return withStack(nav, nav.tab, [...nav.stacks[nav.tab], page])
}

/** The page on top taken off; the same nav at the root. */
export function popPage(nav: Nav): Nav {
  const stack = nav.stacks[nav.tab]
  return stack.length ? withStack(nav, nav.tab, stack.slice(0, -1)) : nav
}

export type TabAction = 'switch' | 'pop-to-root' | 'scroll-to-top'

/**
 * A tap on a tab. Another tab: show it as it was left. The tab showing, with pages on it: back to
 * its root. The tab showing, at its root: nothing moves, and the caller scrolls to the top.
 */
export function selectTab(nav: Nav, tab: Tab): { nav: Nav; action: TabAction } {
  if (tab !== nav.tab) return { nav: { ...nav, tab }, action: 'switch' }
  if (nav.stacks[tab].length) return { nav: withStack(nav, tab, []), action: 'pop-to-root' }
  return { nav, action: 'scroll-to-top' }
}

/**
 * The browser moved to `route` in the tab it names - back, forward, or an address typed in. Its tab
 * shows, and that tab's stack is brought to agree: back to the page if it is in the stack (going
 * back), the root if it is the root, and otherwise the page put on top (going forward to it).
 * A back or forward onto ANOTHER tab's entry doesn't come here - see `browserMoved`.
 */
export function followRoute(nav: Nav, route: Route): Nav {
  const stack = nav.stacks[route.tab]
  if (!route.page) return withStack(nav, route.tab, [])
  for (let index = stack.length - 1; index >= 0; index--) {
    if (samePage(stack[index], route.page)) return withStack(nav, route.tab, stack.slice(0, index + 1))
  }
  return withStack(nav, route.tab, [...stack, route.page])
}

/** What the back button on the top page of `tab` says: the page below's label, or the tab's name
 *  when the page below is the root (or has no label - a page reached by a cold link). Null at the
 *  root, which has no back button. */
export function backLabel(nav: Nav, tab: Tab = nav.tab): string | null {
  const stack = nav.stacks[tab]
  if (!stack.length) return null
  const below = stack[stack.length - 2]
  return below?.label || TAB_LABELS[tab]
}

/** The addresses below the top page of the tab showing, nearest first, down to its root - what
 *  going back one page (the first) or popping to the root (all of them) would pass through. */
export function addressesBelow(nav: Nav): string[] {
  const stack = nav.stacks[nav.tab]
  const below: string[] = []
  for (let index = stack.length - 2; index >= -1; index--) {
    below.push(formatRoute({ tab: nav.tab, page: stack[index] ?? null }))
  }
  return stack.length ? below : []
}

/* ===== the browser's history ===== */

/**
 * The history entries this page has made or seen, by their place in the browser's list. The
 * browser won't say what an entry holds, so the page keeps its own note: each entry it makes
 * carries its place (`{n}` in history.state), and `entries[n]` is the address it was given.
 */
export interface HistoryNote {
  index: number
  entries: readonly (string | undefined)[]
}

/**
 * A page load: the entry it is on, which after a reload may already carry a place of its own - and
 * then `saved`, the entries this page's earlier load noted (lib/appHistory.ts keeps them for the
 * tab), may say what is below it. Without them the entries below are unknown, going back replaces
 * the address, and the entry below is left behind as a copy of the one replaced - a swipe that
 * shows nothing new. With them, going back after a reload is history's own back, as before it.
 */
export function startHistory(
  place: number | null,
  address: string,
  saved?: readonly (string | null | undefined)[] | null,
): HistoryNote {
  const index = place ?? 0
  const entries: (string | undefined)[] =
    place !== null && saved ? saved.map((entry) => (typeof entry === 'string' ? entry : undefined)) : []
  entries[index] = address
  return { index, entries }
}

export function pushed(note: HistoryNote, address: string): HistoryNote {
  return { index: note.index + 1, entries: [...note.entries.slice(0, note.index + 1), address] }
}

export function replaced(note: HistoryNote, address: string): HistoryNote {
  const entries = [...note.entries]
  entries[note.index] = address
  return { index: note.index, entries }
}

/** The browser moved to `place` (null: an entry this page never made, like an address typed in,
 *  which the browser adds after the current one). */
export function moved(note: HistoryNote, place: number | null, address: string): HistoryNote {
  if (place === null) return pushed(note, address)
  const entries = [...note.entries]
  entries[place] = address
  return { index: place, entries }
}

/**
 * How many steps of history's own back reach `below` (addresses nearest first): all of them when
 * the entries under this one are exactly those, made in this session; otherwise 0, and the caller
 * replaces the address instead. So a page opened here goes back as the browser would, and a cold
 * deep link - with nothing of this app's under it - still goes back to its tab's root.
 */
export function stepsBack(note: HistoryNote, below: readonly string[]): number {
  if (!below.length || note.index < below.length) return 0
  for (let step = 1; step <= below.length; step++) {
    if (note.entries[note.index - step] !== below[step - 1]) return 0
  }
  return below.length
}

/** What the browser's own move comes to: where the app is, the note, and the address the entry
 *  must read - `rewrite` when that isn't what the browser has there. */
export interface Moved {
  nav: Nav
  note: HistoryNote
  address: string
  rewrite: boolean
}

/**
 * The browser moved by itself and landed on `hash`, at `place` in its list (null: an entry this page
 * never made - an address typed in, which the browser adds after this one).
 *
 * Going back or forward onto ANOTHER tab's entry is that tab chosen, as it was left - its pages
 * kept - and the entry is rewritten to that tab's top page. Switching tab replaces the entry, so the
 * entries below one tab's root are whichever tab showed when they were made: going back from the
 * Library's root lands on an entry Home wrote. Taken at its word it emptied Home's stack (the entry
 * names Home's root) and dropped the album opened there, which a tab never does. A web page can't
 * stop that back from leaving the tab; it can stop it losing the tab it lands on.
 *
 * Within the tab showing, and for an address typed in (which says where to go), `followRoute`.
 */
export function browserMoved(nav: Nav, note: HistoryNote, place: number | null, hash: string): Moved {
  const { route, canonical } = parseHash(hash)
  let noted = moved(note, place, canonical)
  const next = place !== null && route.tab !== nav.tab ? { ...nav, tab: route.tab } : followRoute(nav, route)
  const address = formatRoute(currentRoute(next))
  if (address !== canonical) noted = replaced(noted, address)
  return { nav: next, note: noted, address, rewrite: place === null || address !== hash }
}
