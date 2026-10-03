/**
 * The Search tab's box, shared with the desktop sidebar's field (2.0.0-player.19). On a desktop the
 * search is a field in the sidebar, not a place - DesktopRequest.dc.html draws it there, still saying
 * what was searched for while an album found by it is open - and the Search tab's own box isn't
 * drawn. The search itself stays the Search tab's (app/Search.tsx: its pacing, its two halves, its
 * guards): the sidebar's field only types into it, and asks it now on Enter. A module, as useOwned.ts
 * is: every root renders from one bundle.
 *
 *  - The text: Search tells the store what its box says (`shareSearchText`), and the sidebar's field
 *    draws that; the sidebar's typing reaches Search through `typeSearch`, as if typed in its box.
 *  - Enter in the sidebar's field: `submitSearch`, which Search answers as its own form's submit -
 *    both halves asked at once.
 */

let text = ''
const shown = new Set<(text: string) => void>()
const typed = new Set<(text: string) => void>()
const submitted = new Set<() => void>()

/** What the box says now. */
export function searchText(): string {
  return text
}

/** Search's box changed: the sidebar's field shows it. */
export function shareSearchText(next: string): void {
  if (next === text) return
  text = next
  for (const listener of [...shown]) listener(next)
}

/** The sidebar's field typed into: Search takes it as typing in its own box. */
export function typeSearch(next: string): void {
  for (const listener of [...typed]) listener(next)
}

/** Enter in the sidebar's field: Search asks both halves now. */
export function submitSearch(): void {
  for (const listener of [...submitted]) listener()
}

const subscribe = <T>(set: Set<T>, listener: T) => {
  set.add(listener)
  return () => {
    set.delete(listener)
  }
}

/** The text as Search shares it (the sidebar's field). */
export const onSearchText = (listener: (text: string) => void) => subscribe(shown, listener)
/** Typing from the sidebar's field (Search). */
export const onSearchTyped = (listener: (text: string) => void) => subscribe(typed, listener)
/** Enter in the sidebar's field (Search). */
export const onSearchSubmitted = (listener: () => void) => subscribe(submitted, listener)
