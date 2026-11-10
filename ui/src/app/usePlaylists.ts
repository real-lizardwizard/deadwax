import { useEffect, useState } from 'preact/hooks'

import { playlists as fetchPlaylists, type Playlist, type PlaylistWithSongs } from '../api/playlists'
import { isAbort, latestOnly } from '../lib/latest'
import { PLAYLISTS_FRESH_MS, PLAYLISTS_KEPT } from '../lib/playlists'
import { sayError } from './sayError'

/**
 * The app's one list of playlists (2.0.0-player.58) - GET /navidrome/playlists, kept in this module for the page's
 * life, as usePins and useMyLibrary keep theirs: the Playlists page, the picker and the desktop sidebar read it.
 *
 * `askPlaylists({ fresh })`: one read at a time through latestOnly - a newer ask supersedes an older one, and only
 * the newest answer draws; without `fresh`, nothing is asked while an answer under PLAYLISTS_FRESH_MS old is held.
 * Who asks: the Playlists page (fresh, as it shows), the picker (fresh, as it opens), App for the desktop sidebar
 * (as the desktop frame shows and the app comes back to the front - not fresh), and every write made here (fresh,
 * through announcePlaylistChanged). The phone's Library row asks nothing. A failure keeps the last list, and says
 * why beside it. Nothing is written to localStorage; another person signing in reloads the page (signInGate's
 * start-again), so nothing here needs a reset of its own.
 *
 * A playlist PAGE's answer is kept here too (`keptPlaylist` / `keepPlaylist`), the last PLAYLISTS_KEPT by id: App
 * draws only each tab's root and its top page, so going back to a playlist from an album opened from it remounts
 * the page - which draws the kept answer on its first render, before App puts the scroll back, then asks again. A
 * write here without the playlist's new answer (an add, a delete) lets its kept answer go, and the page offers Edit
 * only once its own ask has answered: a kept answer is for drawing, never a base for Done.
 */

export interface PlaylistsState {
  /** the last answer - null until one has come */
  list: Playlist[] | null
  /** the last ask's failure, while it is the newest word - the list is kept */
  problem: string | null
  /** an ask is out */
  asking: boolean
}

let state: PlaylistsState = { list: null, problem: null, asking: false }
let askedAt = 0
const requests = latestOnly()
const listeners = new Set<() => void>()
const changedListeners = new Set<(id: string, now: PlaylistWithSongs | null) => void>()
const kept = new Map<string, PlaylistWithSongs>()

function tell(next: PlaylistsState): void {
  state = next
  for (const listener of [...listeners]) listener()
}

/** Ask deadwax for the playlists: at once with `fresh`, else only when what is held is old or there is none. */
export function askPlaylists({ fresh = false }: { fresh?: boolean } = {}): void {
  if (!fresh && state.list !== null && Date.now() - askedAt < PLAYLISTS_FRESH_MS) return
  const request = requests.begin()
  tell({ ...state, asking: true })
  fetchPlaylists(request.signal).then(
    (answer) => {
      if (!request.current()) return
      askedAt = Date.now()
      tell({ list: answer.playlists, problem: null, asking: false })
    },
    (reason: unknown) => {
      if (!request.current() || isAbort(reason)) return
      //? (2.0.4) in a listener's words (app/ErrorNote.tsx sayError)
      tell({ ...state, problem: sayError(reason), asking: false })
    },
  )
}

/** The playlists as they stand. */
export function playlistsNow(): PlaylistsState {
  return state
}

/** The playlists, re-rendering as they move. */
export function usePlaylists(): PlaylistsState {
  const [, setSeen] = useState(0)
  useEffect(() => {
    const listener = () => setSeen((n) => n + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
  return state
}

/** A write made here changed playlist `id` (or made it, or deleted it): the list asked again, and a page showing it
 *  told. `now` is the playlist as that write answered it (Done, a New playlist) - kept, to draw; without one (an add,
 *  a delete) the answer kept for `id` is let go (review): it is no longer how the playlist stands, and drawn again
 *  later it would play the songs as they were, and start Edit from them - a Done then refused as changed in another
 *  app, for the user's own add. */
export function announcePlaylistChanged(id: string, now: PlaylistWithSongs | null = null): void {
  if (now) keepPlaylist(now)
  else kept.delete(id)
  askPlaylists({ fresh: true })
  for (const listener of [...changedListeners]) listener(id, now)
}

/** Told of every playlist a write here changed, by id, and the playlist as the write answered it if it did - the
 *  playlist page asks again for its own. */
export function onPlaylistChanged(listener: (id: string, now: PlaylistWithSongs | null) => void): () => void {
  changedListeners.add(listener)
  return () => {
    changedListeners.delete(listener)
  }
}

/** The last answer a playlist page had for `id`, or null. */
export function keptPlaylist(id: string): PlaylistWithSongs | null {
  return kept.get(id) ?? null
}

/** A playlist page's answer kept, newest last, the oldest let go past PLAYLISTS_KEPT. */
export function keepPlaylist(answer: PlaylistWithSongs): void {
  const id = answer.playlist.id
  kept.delete(id)
  kept.set(id, answer)
  while (kept.size > PLAYLISTS_KEPT) {
    const [oldest] = kept.keys()
    if (oldest === undefined) break
    kept.delete(oldest)
  }
}

/** A deleted playlist's answer let go. */
export function forgetPlaylist(id: string): void {
  kept.delete(id)
}
