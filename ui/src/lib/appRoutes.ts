/**
 * Where the app at /player/ is: a tab, and the pages pushed on it - as pure functions, so the
 * rules are pinned by ui/test/routes.sim.cjs rather than found by tapping.
 *
 * THE ADDRESS IS THE HASH. StaticFiles has no fallback for page routes (`/player/library` is a
 * 404), so the route lives after the `#`:
 *
 *   #/home  #/library  #/search  #/requests  #/you     a tab's root
 *   #/<tab>/album/<id>                                 an album pushed on that tab
 *   #/<tab>/group/<rgid>?release=<mbid>                an album you don't have (2.0.0-player.13):
 *                                                      a MusicBrainz release group, and the pressing
 *                                                      shown when it isn't the default
 *   #/<tab>/group/<rgid>?song=<mbid>,<mbid>            ...opened from a song Search found (2.0.0-player.53):
 *                                                      its recordings, so the page opens on a pressing
 *                                                      with the song and marks it - `release` too once
 *                                                      one is chosen
 *   #/<tab>/artist/<id>                                an artist (2.0.0-player.17): Navidrome's
 *                                                      artist id, or `mb:<mbid>` for one known only
 *                                                      by MusicBrainz (lib/artistPage.ts reads it)
 *   #/<tab>/queue/all?facet=<id>                       Needs a look (2.0.0-player.25), the review
 *                                                      queue - pushed on You. One page whatever
 *                                                      the facet: `facet` is in the address, as a
 *                                                      group page's pressing is, not its identity
 *   #/<tab>/settings/server                            the server's settings (2.0.0-player.33), and
 *   #/<tab>/log/all                                    the event log - pushed on You, one page each,
 *                                                      as the queue page is
 *   #/<tab>/care/library                               Library care (2.0.0-player.42): Rescan and the
 *                                                      bulk runs - pushed on You, one page, as they are
 *   #/<tab>/people/all                                 People (2.0.0-player.61): Navidrome's accounts -
 *                                                      pushed on You, one page, as they are
 *   #/<tab>/playlists/all                              the Playlists page (2.0.0-player.58) - pushed on the
 *                                                      Library, one page whatever id the address gives
 *   #/<tab>/playlist/<id>                              one playlist, by Navidrome's playlist id
 *   #/library/section/<id>                             a section of the Library (2.0.0-player.59) - a phone's
 *                                                      page from the Library's root: recent, albums, artists,
 *                                                      songs, store or storeArtists (SECTION_IDS); on any other
 *                                                      tab, or with another id, the tab's root
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
 * Within the tab showing, going back finds the page in the stack, and going FORWARD puts the pages
 * passed back on top - never a search, since one page can be in a stack twice (`forwardTo`).
 * lib/appHistory.ts drives all of this against the real history.
 */

import type { LibraryPick } from './appFrame'
import { NO_PERMISSION } from './permissions'

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

/** What a page can be: an album in the library (Navidrome's id), a MusicBrainz release group -
 *  the album you don't have (2.0.0-player.13) - an artist (2.0.0-player.17), Needs a look, the
 *  review queue (2.0.0-player.25), the server's settings or the event log (2.0.0-player.33),
 *  Library care (2.0.0-player.42), (2.0.0-player.58) the Playlists page and one playlist - page kinds
 *  of their own, never one of the Library's views - or (2.0.0-player.59) a section of the Library, one of its
 *  views as a page of its own: a phone's way to Albums, Artists and the rest from the Library's root. */
export type PageKind = 'album' | 'group' | 'artist' | 'queue' | 'settings' | 'log' | 'care' | 'people' | 'playlists' | 'playlist' | 'section'

const PAGE_KINDS: readonly PageKind[] = ['album', 'group', 'artist', 'queue', 'settings', 'log', 'care', 'people', 'playlists', 'playlist', 'section']

/** (2.0.0-player.59) A section's ids: exactly the Library's views (lib/appFrame.ts LibraryPick - routes.sim holds
 *  the two equal). The Playlists page and a playlist's stay page kinds of their own. */
export const SECTION_IDS: readonly LibraryPick[] = ['recent', 'albums', 'artists', 'songs', 'store', 'storeArtists']

/** There is one queue page: its id is always this. */
export const QUEUE_ID = 'all'

/** Needs a look, as App opens it (from the sidebar, or You's row) - All, no facet. */
export const QUEUE_PAGE: Page = { kind: 'queue', id: QUEUE_ID, label: 'Needs a look' }

/** The server's settings (2.0.0-player.33): one page, whatever id an address gives it. */
export const SETTINGS_ID = 'server'
export const SETTINGS_PAGE: Page = { kind: 'settings', id: SETTINGS_ID, label: 'Server settings' }

/** The event log (2.0.0-player.33): one page, whatever id an address gives it. */
export const LOG_ID = 'all'
export const LOG_PAGE: Page = { kind: 'log', id: LOG_ID, label: 'Event log' }

/** Library care (2.0.0-player.42): Rescan and the bulk runs - one page, whatever id an address gives it. */
export const CARE_ID = 'library'
export const CARE_PAGE: Page = { kind: 'care', id: CARE_ID, label: 'Library care' }

/** People (2.0.0-player.61): Navidrome's accounts - one page, whatever id an address gives it. */
export const PEOPLE_ID = 'all'
export const PEOPLE_PAGE: Page = { kind: 'people', id: PEOPLE_ID, label: 'People' }

/** The Playlists page (2.0.0-player.58): one page, whatever id an address gives it. A playlist's own page is
 *  `{ kind: 'playlist', id: <Navidrome's id>, label: <its name> }`, so a page pushed over it says the name. */
export const PLAYLISTS_ID = 'all'
export const PLAYLISTS_PAGE: Page = { kind: 'playlists', id: PLAYLISTS_ID, label: 'Playlists' }

/** What a Managing page says, in place of itself, to someone without its permission (2.0.0-player.47: the pages
 *  are on both frames - until then a phone's note stood here, pointing at the main page; 2.0.0-player.61: per
 *  page, by its permission - lib/permissions.ts). With logins off everyone is the admin, so nobody sees it. */
export const MANAGING_ADMINS_ONLY = NO_PERMISSION

/** The Managing pages that are one page each, by kind: an address's id is made this one. */
const ONE_PAGE: Partial<Record<PageKind, string>> = { settings: SETTINGS_ID, log: LOG_ID, care: CARE_ID, people: PEOPLE_ID, playlists: PLAYLISTS_ID }

/** A page pushed on a tab. `label` names it on the back button of a page pushed over it - never
 *  part of the address, and never part of what makes two pages the same one. `release` is a group
 *  page's pressing - in the address (`?release=`), so a reload or a link shows the same one, but
 *  NOT part of what makes two pages the same: choosing another pressing is the same page, its
 *  address replaced (`replaceTop`), never a page pushed over it. */
export interface Page {
  kind: PageKind
  id: string
  label?: string
  release?: string
  /** the queue page's facet (2.0.0-player.25): in the address (`?facet=`), never its identity */
  facet?: string
  /** a group page opened from a song Search found (2.0.0-player.53): the song's recordings, comma-separated
   *  (lib/songs.ts songIds) - in the address (`?song=`), never its identity, and kept as a pressing is chosen */
  song?: string
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
  if (!route.page) return root
  const path = `${root}/${route.page.kind}/${encodeURIComponent(route.page.id)}`
  if (route.page.kind === 'queue' && route.page.facet) return `${path}?facet=${encodeURIComponent(route.page.facet)}`
  if (route.page.kind !== 'group') return path
  const query = [
    ...(route.page.release ? [`release=${encodeURIComponent(route.page.release)}`] : []),
    //? its commas left as they are: `song=<id>,<id>` reads as what it is
    ...(route.page.song ? [`song=${encodeURIComponent(route.page.song).replace(/%2C/gi, ',')}`] : []),
  ]
  return query.length ? `${path}?${query.join('&')}` : path
}

/** What a page's scroll is kept under: its address without the pressing - choosing another
 *  pressing is the same page, and must not jump it back to the top - nor the queue's facet, nor the song
 *  a group page was opened from. */
export function scrollKey(route: Route): string {
  if (!route.page) return formatRoute(route)
  const { release: _release, facet: _facet, song: _song, ...page } = route.page
  return formatRoute({ tab: route.tab, page })
}

/** A page of a kind, from the parts of an address after its tab. */
function pageFrom(parts: readonly string[], query: string): Page | null {
  const kind = parts[0] as PageKind
  if (!PAGE_KINDS.includes(kind) || !parts[1]) return null
  const id = decode(parts.slice(1).join('/'))
  //? the server's settings and the log: one page each, whatever the address said, with nothing more
  const only = ONE_PAGE[kind]
  if (only) return { kind, id: only }
  //? a section is one of the Library's views, by its id - another id is no page, so the address is the tab's root
  if (kind === 'section') return SECTION_IDS.includes(id as LibraryPick) ? { kind, id } : null
  if (kind === 'queue') {
    //? one queue page: whatever id the address gave, it is that one
    const facet = new URLSearchParams(query).get('facet')?.trim()
    return facet ? { kind, id: QUEUE_ID, facet } : { kind, id: QUEUE_ID }
  }
  if (kind !== 'group') return { kind, id }
  const params = new URLSearchParams(query)
  const release = params.get('release')?.trim()
  //? the song's recordings as lib/songs.ts reads them - kept as written here, read (and checked) by the page
  const song = params.get('song')?.trim()
  return { kind, id, ...(release ? { release } : {}), ...(song ? { song } : {}) }
}

/**
 * The route an address names, and the address it should read instead: the same string when it is
 * already right, the new home of a legacy `#/album/<id>`, `#/home` for an empty hash, and the
 * nearest sense for anything else (an unknown tab is Home, an unknown page is its tab's root).
 * A caller rewrites the address with replaceState whenever `canonical` differs from what it gave.
 */
export function parseHash(hash: string): { route: Route; canonical: string } {
  const address = hash.replace(/^#/, '')
  const mark = address.indexOf('?')
  const path = mark === -1 ? address : address.slice(0, mark)
  const query = mark === -1 ? '' : address.slice(mark + 1)
  const parts = path.split('/').filter((part, index) => index > 0 || part !== '')
  let route: Route

  if (parts[0] === 'album' && parts[1]) {
    route = { tab: 'library', page: { kind: 'album', id: decode(parts.slice(1).join('/')) } }
  } else if (isTab(parts[0])) {
    const page = pageFrom(parts.slice(1), query)
    //? a section is the Library's: on any other tab the address is that tab's root
    route = { tab: parts[0], page: page?.kind === 'section' && parts[0] !== 'library' ? null : page }
  } else {
    route = { tab: 'home', page: null }
  }

  return { route, canonical: formatRoute(route) }
}

export const samePage = (a: Page | null | undefined, b: Page | null | undefined): boolean =>
  !!a && !!b && a.kind === b.kind && a.id === b.id

/**
 * (2.0.0-player.58) How the Playlists page or a playlist's is opened on the Library's stack (App's
 * openPlaylistsPage, from the sidebar or the phone Library's row): `stay` when that very page is on top; `back` when
 * a playlists or playlist page is on top and that very page is just under it (All playlists from a playlist opened
 * from the Playlists page - review: replacing the top made two Playlists pages, one over the other); `become` - the
 * top replaced - for another playlists or playlist page on top (the sidebar's picks are siblings, never a pile);
 * else `open`, pushed.
 */
export function playlistsMove(stack: readonly Page[], page: Page): 'stay' | 'back' | 'become' | 'open' {
  const top = stack[stack.length - 1] ?? null
  if (samePage(top, page)) return 'stay'
  const playlistOnTop = !!top && (top.kind === 'playlists' || top.kind === 'playlist')
  if (playlistOnTop && samePage(stack[stack.length - 2], page)) return 'back'
  return playlistOnTop ? 'become' : 'open'
}

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

/**
 * The page on top of the tab showing, made `page` - the same page (kind and id) in another state:
 * a group page showing another pressing, the queue page another facet. The same nav when the top is
 * another page, or nothing changed. Pushed nothing, so back still leaves the page, as it does after
 * a pick in a list.
 */
export function replaceTop(nav: Nav, page: Page): Nav {
  const stack = nav.stacks[nav.tab]
  const top = stack[stack.length - 1]
  if (!samePage(top, page)) return nav
  //? the song a group page was opened from stays as a pressing is chosen (a pick names none); an address
  //? that names one says which
  const song = page.song ?? top!.song ?? null
  if ((top!.release ?? null) === (page.release ?? null) && (top!.facet ?? null) === (page.facet ?? null) && (top!.song ?? null) === song) return nav
  const { release: _release, facet: _facet, song: _song, ...kept } = top!
  return withStack(nav, nav.tab, [...stack.slice(0, -1), {
    ...kept,
    ...(page.release ? { release: page.release } : {}),
    ...(page.facet ? { facet: page.facet } : {}),
    ...(song ? { song } : {}),
  }])
}

/**
 * The page on top of the tab showing become ANOTHER page (2.0.0-player.21): an album an edit gave a
 * new identity - applying another release gives it a new id in Navidrome - shown as it is now, not
 * left on an id Navidrome no longer has. Its entry is replaced, never a page pushed over it, so back
 * still leaves it. The same nav unless `from` is on top and `to` is another page; a copy of `from`
 * lower in the stack (Go to album can put one there) is left as it is.
 */
export function becomeTop(nav: Nav, from: Page, to: Page): Nav {
  const stack = nav.stacks[nav.tab]
  if (!samePage(top(nav), from) || samePage(from, to)) return nav
  return withStack(nav, nav.tab, [...stack.slice(0, -1), to])
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
 * The browser moved to `route` in the tab it names - back, or an address typed in. Its tab shows,
 * and that tab's stack is brought to agree: back to the page if it is in the stack (the nearest the
 * top, so with a page in it twice, the copy just under where it was), the root if it is the root,
 * and otherwise the page put on top. A move onto ANOTHER tab's entry, and a move forward within the
 * tab showing, don't come here - see `browserMoved`.
 */
export function followRoute(nav: Nav, route: Route): Nav {
  const stack = nav.stacks[route.tab]
  if (!route.page) return withStack(nav, route.tab, [])
  for (let index = stack.length - 1; index >= 0; index--) {
    if (samePage(stack[index], route.page)) {
      //? the page as the stack had it (its label), showing the pressing the address names
      const kept = withStack(nav, route.tab, stack.slice(0, index + 1))
      return replaceTop({ ...kept, tab: route.tab }, route.page)
    }
  }
  return withStack(nav, route.tab, [...stack, route.page])
}

/**
 * The browser went FORWARD, in the tab showing, to `route` at `place`: the pages it passes - the
 * note's entries between, those of this tab - are put back on top in the order they were opened,
 * and the one it lands on last. Never a search down the stack, as `followRoute` does going back:
 * a page can be in a stack twice (Go to album, from Now Playing, opens the song's album over
 * whatever is showing - which can be the same album, lower down), and the lower copy taken for
 * the one gone forward to cut every page above it, the stack and the history then disagreeing.
 */
export function forwardTo(nav: Nav, note: HistoryNote, place: number, route: Route): Nav {
  let next = nav
  const step = (page: Page | null) => {
    next = page ? replaceTop(openPage(next, page), page) : withStack(next, route.tab, [])
  }
  for (let at = note.index + 1; at < place; at++) {
    const entry = note.entries[at]
    if (entry === undefined) continue
    const passed = parseHash(entry).route
    if (passed.tab === route.tab) step(passed.page)
  }
  step(route.page)
  return next
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
 * Within the tab showing: forward puts the pages passed back on top (`forwardTo`); back, and an
 * address typed in (which says where to go), `followRoute`.
 */
export function browserMoved(nav: Nav, note: HistoryNote, place: number | null, hash: string): Moved {
  const { route, canonical } = parseHash(hash)
  let noted = moved(note, place, canonical)
  const next =
    place !== null && route.tab !== nav.tab
      ? { ...nav, tab: route.tab }
      : place !== null && place > note.index
        ? forwardTo(nav, note, place, route)
        : followRoute(nav, route)
  const address = formatRoute(currentRoute(next))
  if (address !== canonical) noted = replaced(noted, address)
  return { nav: next, note: noted, address, rewrite: place === null || address !== hash }
}
