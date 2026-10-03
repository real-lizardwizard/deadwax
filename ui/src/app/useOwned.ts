import { useEffect, useState } from 'preact/hooks'

import { owned } from '../api/library'
import { onAlbumsFiled } from '../lib/libraryEvents'
import { buildOwnedIndex, type OwnedIndex } from '../lib/owned'

/**
 * What the library holds, for the app's Search and the album-you-don't-have page (2.0.0-player.13):
 * `/library/owned` through lib/owned.ts, kept for the page's life in this module, so every screen
 * reading it shares one answer and one request.
 *
 * ONE request in flight, and one more after it when asked meanwhile ("ask again", the main page's
 * refreshOwned rule): the asks are sequential, so the answer that lands last is always the newest
 * question's - the reason latestOnly() exists, met here by never having two out at once. Asked
 * when a screen that reads it first SHOWS (`ask`: the Search tab, an album page), beside each
 * MusicBrainz search (cheap: an unchanged library is a 304), and when the downloads say an album
 * was filed (lib/libraryEvents.ts) once anything has asked - never as the app starts: Search is
 * mounted then, hidden, and the first /library/owned after deadwax restarts walks the whole
 * library, which on a spun-down array is the whole wait (the saved scan's note in CLAUDE.md). A
 * failed ask keeps the last answer - or none, and then nothing is left out of "Not in your library
 * yet", and the album page says neither "in" nor "not in your library": no answer must never read
 * as "you hold none of this", nor as "you hold all of it".
 *
 * refreshOwned() answers when the ask that covers it has landed (or failed): Search waits on it, a
 * moment, before drawing what MusicBrainz found, so a held album isn't drawn and then taken away
 * under a finger. search.sim.cjs drives all of this against a faked /library/owned.
 */

export interface Owned {
  index: OwnedIndex
  /** every album artist the library has a folder of, for reading the search box */
  artists: string[]
}

let held: Owned | null = null
let asking = false
let again = false
//? something has asked: from then on a filed album asks again - even after a first ask that failed
let wanted = false
let hearing = false
const listeners = new Set<() => void>()
//? who is waiting on the NEXT ask to land: the ask out now may predate what they asked about
let waiting: (() => void)[] = []
//? ...and who is waiting on the ask out NOW, whichever question it answers (whenOwned)
let landing: (() => void)[] = []

function tell(): void {
  for (const listener of [...listeners]) listener()
}

function ask(): void {
  asking = true
  const settles = waiting
  waiting = []
  landing = settles
  owned().then(
    (answer) => {
      const artists = [...new Set(answer.albums.map((album) => (album.artist ?? '').trim()).filter(Boolean))]
      held = { index: buildOwnedIndex(answer.albums), artists }
      tell()
    },
    () => {
      //? kept as it was - the next search, album page or filing asks again
    },
  ).finally(() => {
    asking = false
    for (const settle of settles) settle()
    if (again) {
      again = false
      ask()
    }
  })
}

/**
 * Ask the library what it holds - now, or straight after the ask already out. Resolves once an ask
 * made after this call has landed, answered or not (it never rejects).
 */
export function refreshOwned(): Promise<void> {
  wanted = true
  const settled = new Promise<void>((resolve) => waiting.push(resolve))
  if (asking) again = true
  else ask()
  return settled
}

/**
 * Resolves once the library has answered at least once - or the ask that would have has failed:
 * at once when an answer is in hand, when the ask out now lands, else after one asked now. Asks
 * nothing new while one is out. The artist page waits on it before saying an album is NOT in your
 * library, or that MusicBrainz doesn't know who someone is (2.0.0-player.17, review).
 */
export function whenOwned(): Promise<void> {
  if (held) return Promise.resolve()
  if (asking) return new Promise<void>((resolve) => landing.push(resolve))
  return refreshOwned()
}

/** What the library holds right now - for code that has awaited and must not read a render's copy. */
export function ownedNow(): Owned | null {
  return held
}

/**
 * What the library holds, null until deadwax first says. Re-renders as a new answer lands. `ask`:
 * the screen is showing, so ask if nothing has been asked yet - Search passes whether it has been
 * shown (it is mounted, hidden, from the start), an album page true.
 */
export function useOwned(ask: boolean): Owned | null {
  const [, setSeen] = useState(0)
  useEffect(() => {
    const listener = () => setSeen((count) => count + 1)
    listeners.add(listener)
    if (!hearing) {
      hearing = true
      //? a filed album changes the answer - for whoever has asked, even if that ask failed
      onAlbumsFiled(() => {
        if (wanted) void refreshOwned()
      })
    }
    return () => {
      listeners.delete(listener)
    }
  }, [])
  useEffect(() => {
    if (ask && !held && !asking) void refreshOwned()
  }, [ask])
  return held
}
