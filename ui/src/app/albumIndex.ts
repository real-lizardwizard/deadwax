import { useEffect, useState } from 'preact/hooks'

import { albumIndexOf, type Album } from '../player/api'

/**
 * The Library's album lists (2.0.0-player.59, a better Library): one per scope - `yours`, your starred albums asked
 * as you, and `store`, every album deadwax holds - each in ONE request (src/routes/navidrome.py /album_index, which
 * reads Navidrome's pages of 500 on deadwax's side: one round trip over WireGuard where your albums took six), shared
 * by every reader. A module, as useYourAlbums and useMyLibrary are: one ask per scope for the whole app.
 *
 * Each scope has a GENERATION: a list asked for belongs to the generation it was asked on, and a reader keyed on the
 * generation asks again as it moves. `forgetIndex` moves it (useYourAlbums.ts does for an Add, a Remove and your
 * library's count moving - never for a filing); `refreshIfOld` moves it only when the list in hand is older than
 * INDEX_FRESH_MS, and is called as a section mounts, as the Library tab comes into view and as a desktop's pick
 * changes - so Recently played and Most played are at most a minute behind when you look.
 *
 * While a new list is on its way every view keeps drawing the one it has (`keptIndex`, the last that landed for the
 * scope this session, whatever generation), so the page never empties and the scroll stays put; the new one is
 * swapped in as it lands. A failed ask isn't kept: the next look asks again. Nothing here is asked with logins off but
 * the store's (the Library is the store's then).
 */

export type Scope = 'yours' | 'store'

export interface AlbumIndex {
  albums: Album[]
  truncated: boolean
  /** Date.now() when it landed */
  at: number
}

/** How long a list in hand is fresh enough not to be asked again by refreshIfOld. */
export const INDEX_FRESH_MS = 60_000

interface Held {
  generation: number
  held: { generation: number; list: Promise<AlbumIndex>; pending: boolean } | null
  kept: AlbumIndex | null
  listeners: Set<() => void>
}

const scopes: Record<Scope, Held> = {
  yours: { generation: 0, held: null, kept: null, listeners: new Set() },
  store: { generation: 0, held: null, kept: null, listeners: new Set() },
}

function tell(scope: Scope): void {
  for (const listener of [...scopes[scope].listeners]) listener()
}

/** The scope's list for the generation it is on - one ask shared by every reader; a failed ask isn't kept. */
export function albumIndex(scope: Scope): Promise<AlbumIndex> {
  const state = scopes[scope]
  if (!state.held || state.held.generation !== state.generation) {
    const asked = {
      generation: state.generation,
      pending: true,
      list: albumIndexOf(scope).then((answer) => ({ albums: answer.albums ?? [], truncated: !!answer.truncated, at: Date.now() })),
    }
    asked.list.then(
      (list) => {
        asked.pending = false
        //? the newest generation's list is the one kept to draw from; an older one landing late keeps nothing
        if (asked.generation === state.generation || !state.kept) state.kept = list
      },
      () => {
        asked.pending = false
        if (state.held === asked) state.held = null
      },
    )
    state.held = asked
  }
  return state.held.list
}

/** The last list that landed for the scope this session, whatever generation - for a first draw, synchronously. */
export function keptIndex(scope: Scope): AlbumIndex | null {
  return scopes[scope].kept
}

/** Asked again at the next look (generation + 1); the kept list stays to draw meanwhile. */
export function forgetIndex(scope: Scope): void {
  const state = scopes[scope]
  state.generation += 1
  state.held = null
  tell(scope)
}

/** Forgotten only if the kept list is older than INDEX_FRESH_MS - and nothing is on its way for this generation. */
export function refreshIfOld(scope: Scope): void {
  const state = scopes[scope]
  if (!state.kept) return
  if (state.held && state.held.generation === state.generation && state.held.pending) return
  if (Date.now() - state.kept.at > INDEX_FRESH_MS) forgetIndex(scope)
}

/** The generation the scope is on - what a reader keys its list on - re-rendering the caller as it moves. */
export function useIndexGeneration(scope: Scope): number {
  const [, setSeen] = useState(0)
  useEffect(() => {
    const listener = () => setSeen((count) => count + 1)
    scopes[scope].listeners.add(listener)
    return () => {
      scopes[scope].listeners.delete(listener)
    }
  }, [scope])
  return scopes[scope].generation
}
