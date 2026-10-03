import { useEffect, useState } from 'preact/hooks'

import type { LibraryPick } from '../lib/appFrame'
import { readPlayerLibraryView, writePlayerLibraryView } from '../state/persisted'

/**
 * What the Library tab shows - Albums, Artists, Songs, or on a desktop "Recently added" - as a small
 * store (2.0.0-player.19), since two places choose it: the Library's own chips on a phone, and the
 * desktop sidebar's Library views (app/Sidebar.tsx), which also says which one shows. And whether
 * Navidrome's empty search lists songs at all - the Library asks once - since both leave out Songs
 * when it lists none. A module, as useOwned.ts is: every root renders from one bundle.
 *
 * Albums, Artists and Songs are kept on the device (deadwax-player-library-view), as the chips'
 * choice always was; "Recently added" is the desktop sidebar's, never kept, so a phone opened later
 * finds the view it had.
 */

let pick: LibraryPick | null = null
let songs: boolean | null = null
const listeners = new Set<() => void>()
//? told just before the view changes, while the old one is still on screen: the Library keeps
//? where it was scrolled to (player/Library.tsx is the one listener of this kind)
const leaving = new Set<() => void>()

function tell() {
  for (const listener of [...listeners]) listener()
}

/** The view chosen: the device's, until something is chosen this session. */
export function libraryPick(): LibraryPick {
  if (pick === null) pick = readPlayerLibraryView()
  return pick
}

/** Whether Navidrome's empty search lists songs: null until the Library has asked. */
export function librarySongs(): boolean | null {
  return songs
}

/** Another view chosen - by a chip or the sidebar. */
export function chooseLibrary(next: LibraryPick): void {
  if (next === libraryPick()) return
  for (const listener of [...leaving]) listener()
  pick = next
  if (next !== 'recent') writePlayerLibraryView(next)
  tell()
}

/** What Navidrome's one-song empty search said (the Library asks it as it is first drawn). */
export function setLibrarySongs(has: boolean): void {
  if (songs === has) return
  songs = has
  tell()
}

/** Told just before the view changes, while the one being left is still drawn. */
export function onLibraryLeaving(listener: () => void): () => void {
  leaving.add(listener)
  return () => {
    leaving.delete(listener)
  }
}

/** The view chosen and whether there are songs, re-rendering the caller as either changes. */
export function useLibraryPick(): { pick: LibraryPick; hasSongs: boolean | null } {
  const [, setSeen] = useState(0)
  useEffect(() => {
    const listener = () => setSeen((count) => count + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
  return { pick: libraryPick(), hasSongs: songs }
}
