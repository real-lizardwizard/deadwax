import { useEffect, useState } from 'preact/hooks'

import { markLibrarySeen, myLibrary } from '../api/me'
import type { MyLibrary } from '../api/types'
import { latestOnly } from '../lib/latest'
import { onAddedToLibrary, onAlbumsFiled, onRemovedFromLibrary } from '../lib/libraryEvents'
import { isNew, newMarks } from '../lib/myLibrary'
import { BREAK_GLASS_USER } from '../lib/signIn'
import { sessionMe } from './session'

/**
 * Your library (2.0.0-player.51, personal libraries) - GET /deadwax/me/library, kept in this module for the
 * page's life, as useQueueSummary and usePins keep theirs: Home's "New in your library" shelf, the
 * Library tab's New marks and You's Your library read it.
 *
 * Asked only with logins on, for somebody signed in through Navidrome (not the break-glass admin, who has
 * no library) - with logins off nothing is asked and nothing new is drawn: the one library isn't shown.
 * Asked as Home, the Library tab or You comes into view (App, You), and when the downloads say an album
 * was filed or a store line added one (once anything has asked); every ask through latestOnly(), so only
 * the newest answer draws. A failed ask keeps the last answer. No timer: nothing here polls.
 *
 * `seenAlbum` is the "cleared when you open it": App calls it as an album page opens - and again for the
 * album page on top once an answer lands, so one reached by its address, or opened before deadwax first
 * said, is cleared too - and for an album new in your library it tells deadwax (by its release id, else
 * the store's ids) and takes it off the marks at once. An album opened before any answer is kept, and
 * looked at as the first answer lands.
 */

let answer: MyLibrary | null = null
let hearing = false
//? albums opened before deadwax first said what is new - looked at as its answer lands (the last few)
const OPENED_KEPT = 20
let openedBefore: { id: string; musicBrainzId?: string }[] = []
const requests = latestOnly()
const listeners = new Set<() => void>()

function tell(): void {
  for (const listener of [...listeners]) listener()
}

/** Whether there is a library to ask about: logins on, signed in through Navidrome. */
export function hasLibrary(): boolean {
  const me = sessionMe()
  return me !== null && me.auth === 'on' && me.user !== BREAK_GLASS_USER
}

/** Ask deadwax for your library now - nothing with logins off. */
export function askMyLibrary(): void {
  if (!hasLibrary()) return
  if (!hearing) {
    hearing = true
    //? a filing puts albums into libraries, and Add to my library one: what's new, and the count, move -
    //? and (2.0.0-player.52) Remove from my library takes one out
    onAlbumsFiled(() => askMyLibrary())
    onAddedToLibrary(() => askMyLibrary())
    onRemovedFromLibrary(() => askMyLibrary())
  }
  const request = requests.begin()
  myLibrary(request.signal).then(
    (found) => {
      if (!request.current()) return
      answer = found
      const opened = openedBefore
      openedBefore = []
      for (const album of opened) seenAlbum(album)
      tell()
    },
    () => {
      //? kept as it was - the next look asks again
    },
  )
}

/** Your library as it stands - null until deadwax has first said (and always, with logins off). */
export function myLibraryNow(): MyLibrary | null {
  return answer
}

/**
 * An album opened: when it is new in your library, deadwax is told (by its release, else by the store's
 * ids) and the mark goes at once. Nothing for an album that isn't new, or with logins off.
 */
export function seenAlbum(album: { id: string; musicBrainzId?: string }): void {
  if (!hasLibrary()) return
  if (!answer) {
    //? not known yet whether it is new: looked at as the first answer lands (askMyLibrary)
    if (!openedBefore.some((one) => one.id === album.id)) openedBefore = [...openedBefore, album].slice(-OPENED_KEPT)
    return
  }
  if (!isNew(newMarks(answer), album)) return
  const release = (album.musicBrainzId ?? '').trim().toLowerCase()
  const opened = (answer.new ?? []).filter((entry) =>
    entry.navidrome_id === album.id || (release !== '' && (entry.release_mbid ?? '').toLowerCase() === release))
  answer = { ...answer, new: (answer.new ?? []).filter((entry) => !opened.includes(entry)) }
  tell()
  void markLibrarySeen(release ? { release_mbid: release } : { album_ids: opened.map((entry) => entry.album_id) }).catch(() => {
    //? the mark is gone here; deadwax keeps it until the next open - it says so at the next look
  })
}

/** Your library, re-rendering as it moves - null until deadwax has said. */
export function useMyLibrary(): MyLibrary | null {
  const [, setSeen] = useState(0)
  useEffect(() => {
    const listener = () => setSeen((count) => count + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
  return answer
}
