/**
 * The app's side of the browser's history (2.0.0-player.9): lib/appRoutes.ts's rules, driven
 * against a real `history` - or the fake one in ui/test/routes.sim.cjs, which is why nothing here
 * touches `window` itself. App hands it the history, the address and sessionStorage, and hears back
 * through `show` whenever the route on screen changes.
 *
 * Each entry the app makes carries `{n, load}` in history.state: its place in the browser's list,
 * and which page load's note it belongs to. The note - what address each place was given - is kept
 * in sessionStorage under that load, so a reload (iOS reloads a tab it put aside, and a reload
 * keeps the back/forward list) knows the entries below it and goes back through them as it did
 * before, rather than replacing the address and leaving a copy of the entry below behind. The load
 * is in the key because the n's are only this load's own: a tab that opened /player/ twice has two
 * sets of entries each counting from 0, and a note must never be read for the other's.
 */

import {
  addressesBelow, browserMoved, currentRoute, formatRoute, openPage, parseHash, popPage, pushed,
  replaced, selectTab, startHistory, startNav, stepsBack,
  type HistoryNote, type Nav, type Page, type Tab, type TabAction,
} from './appRoutes'

/** The parts of `window.history` used. */
export interface HistoryLike {
  readonly state: unknown
  pushState(state: unknown, unused: string, url: string): void
  replaceState(state: unknown, unused: string, url: string): void
  go(delta: number): void
}

/** The parts of sessionStorage used. */
export interface StorageLike {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

/** What history.state holds for an entry the app made. */
export interface EntryState {
  n: number
  load: string
}

const NOTE_KEY = 'deadwax-player-history:'

/** The place history.state says an entry is, when this app made it. */
export function placeOf(state: unknown): number | null {
  const n = (state as { n?: unknown } | null)?.n
  return typeof n === 'number' && Number.isInteger(n) && n >= 0 ? n : null
}

/** Which page load made the entry - null for one made before loads were recorded, or by nobody. */
export function loadOf(state: unknown): string | null {
  const load = (state as { load?: unknown } | null)?.load
  return typeof load === 'string' && load ? load : null
}

export function entryState(note: HistoryNote, load: string): EntryState {
  return { n: note.index, load }
}

/** A name for a page load. Not crypto.randomUUID: that needs a secure context, and deadwax is
 *  usually reached over plain http on the home network. */
export function newLoad(): string {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`
}

/** The entries a load noted, or null - none kept, another load's, or storage refused. */
export function readNote(storage: StorageLike | null, load: string): (string | null)[] | null {
  try {
    const raw = storage?.getItem(NOTE_KEY + load)
    const entries: unknown = raw ? JSON.parse(raw) : null
    return Array.isArray(entries) ? entries.map((entry) => (typeof entry === 'string' ? entry : null)) : null
  } catch {
    return null
  }
}

export function saveNote(storage: StorageLike | null, load: string, note: HistoryNote): void {
  try {
    storage?.setItem(NOTE_KEY + load, JSON.stringify(note.entries))
  } catch {
    //? full, or refused (a private window): after a reload, back replaces the address, as it did
  }
}

export interface RouterHost {
  history: HistoryLike
  /** location.hash, read fresh */
  hash(): string
  /** sessionStorage, or null where it can't be had */
  storage(): StorageLike | null
  /** the route on screen is about to change: App saves the scroll of the one being left */
  leaving(): void
  /** the route on screen changed */
  show(nav: Nav): void
  /** a name for a load that made none of the entries it is on (tests give their own) */
  newLoad?(): string
}

export interface Router {
  readonly nav: Nav
  /** the first address: a legacy `#/album/<id>` or an empty hash rewritten in place */
  start(): void
  /** a page opened from the tab showing; false when it was already on top (a double tap) */
  open(page: Page): boolean
  /** the in-app back button */
  back(): void
  /** a tap on a tab; 'scroll-to-top' is the caller's to do */
  tab(tab: Tab): TabAction
  /**
   * A link to a tab's ROOT from another tab (Home's Arriving: "See all" and its cards go to the
   * list of downloads), whatever page was left on top of it - Go to album can leave an album on
   * the Requests tab. Two taps on the tab, as one: the switch, then back to its root, so the
   * history is what tapping it twice would make.
   */
  root(tab: Tab): void
  /** the browser moved by itself - popstate and hashchange both call this; one move is taken once */
  moved(): void
}

export function createRouter(host: RouterHost): Router {
  let nav = startNav(parseHash(host.hash()).route)
  let note: HistoryNote = startHistory(null, formatRoute(currentRoute(nav)))
  let load = ''
  //? the address last written or followed - a popstate and a hashchange for the same move are one
  let shown = ''

  const keep = (next: HistoryNote) => {
    note = next
    saveNote(host.storage(), load, next)
  }

  const change = (next: Nav, address: string) => {
    shown = address
    nav = next
    host.show(next)
  }

  /** `next` written into the address, as a new entry or in place of this one. */
  function commit(next: Nav, how: 'push' | 'replace') {
    host.leaving()
    const address = formatRoute(currentRoute(next))
    keep(how === 'push' ? pushed(note, address) : replaced(note, address))
    if (how === 'push') host.history.pushState(entryState(note, load), '', address)
    else host.history.replaceState(entryState(note, load), '', address)
    change(next, address)
  }

  /** Down to `next` (a page off the top, or the tab's root): history's own back when the entries
   *  below are those pages, made here; otherwise the address is replaced. */
  function goDown(next: Nav, below: string[]) {
    host.leaving()
    const steps = stepsBack(note, below)
    const address = formatRoute(currentRoute(next))
    if (steps) {
      keep({ ...note, index: note.index - steps })
      host.history.go(-steps)
    } else {
      keep(replaced(note, address))
      host.history.replaceState(entryState(note, load), '', address)
    }
    change(next, address)
  }

  /** A tap on a tab: show it as it was left, or back to its root when it is showing. */
  function choose(tab: Tab): TabAction {
    const { nav: next, action } = selectTab(nav, tab)
    if (action === 'switch') commit(next, 'replace')
    else if (action === 'pop-to-root') goDown(next, addressesBelow(nav))
    return action
  }

  return {
    get nav() {
      return nav
    },

    start() {
      const { canonical } = parseHash(host.hash())
      const state = host.history.state
      const place = placeOf(state)
      const earlier = place === null ? null : loadOf(state)
      load = earlier ?? (host.newLoad ?? newLoad)()
      keep(startHistory(place, canonical, earlier ? readNote(host.storage(), earlier) : null))
      host.history.replaceState(entryState(note, load), '', canonical)
      shown = canonical
    },

    open(page) {
      const next = openPage(nav, page)
      if (next === nav) return false
      commit(next, 'push')
      return true
    },

    back() {
      const next = popPage(nav)
      if (next !== nav) goDown(next, addressesBelow(nav).slice(0, 1))
    },

    tab(tab) {
      return choose(tab)
    },

    root(tab) {
      if (choose(tab) === 'switch' && nav.stacks[tab].length) choose(tab)
    },

    moved() {
      const result = browserMoved(nav, note, placeOf(host.history.state), host.hash())
      keep(result.note)
      if (result.rewrite) host.history.replaceState(entryState(note, load), '', result.address)
      if (result.address === shown) return
      host.leaving()
      change(result.nav, result.address)
    },
  }
}
