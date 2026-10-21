import { useEffect, useState } from 'preact/hooks'

import { queueSummary } from '../api/library'
import { onAlbumsFiled } from '../lib/libraryEvents'
import { asksQueueSummary } from '../lib/permissions'
import { accessNow } from './access'

/**
 * How many albums need a look (2.0.0-player.25): the count beside "Needs a look" in the desktop's
 * sidebar and You's row - kept in this module for the page's life, as useOwned and usePins keep theirs.
 *
 * Asked of GET /library/queue/summary, which reads the saved scan and never the disk, so it is cheap
 * to ask whenever the count could have moved: as the desktop frame first shows for an admin, as the
 * page comes back from hidden (App), when the downloads say an album was filed (lib/libraryEvents.ts,
 * once anything has asked), after every change the Edit panel reports (App) and every album the queue
 * page marks reviewed. ONE request in flight, and one more after it when asked meanwhile, so the
 * answer that lands last is always the newest question's. No timer: nothing here polls.
 *
 * While the queue page is showing with a REAL scan in hand it knows better than the saved scan, and
 * its own count stands in for the server's (`setPageQueueCount`) - the same function over the same
 * albums, so the badge and the page say one number. A failed ask keeps the last number; with none
 * yet the count is null, and nothing draws a badge of 0 over a count nobody knows.
 */

let server: number | null = null
//? whether deadwax can keep ignores (the route's tracking_enabled) - null until it has answered
let tracking: boolean | null = null
let page: number | null = null
let asking = false
let again = false
let hearing = false
const listeners = new Set<() => void>()

function tell(): void {
  for (const listener of [...listeners]) listener()
}

function ask(): void {
  asking = true
  queueSummary().then(
    (answer) => {
      server = answer.total
      tracking = answer.tracking_enabled !== false
      tell()
    },
    () => {
      //? kept as it was - the next change asks again
    },
  ).finally(() => {
    asking = false
    if (again) {
      again = false
      ask()
    }
  })
}

/** Ask deadwax how many albums need a look - now, or straight after the ask already out. */
export function askQueueSummary(): void {
  //? (2.0.0-player.61) the count is Look after the library's: never asked without it (the server answers 403)
  if (!asksQueueSummary(accessNow().permissions)) return
  if (!hearing) {
    hearing = true
    //? an album filed is a new import: the count moves
    onAlbumsFiled(() => askQueueSummary())
  }
  if (asking) again = true
  else ask()
}

/** The queue page's own count, from its real scan - or null as it stops knowing better (a session
 *  begun, the page hidden or gone), and the server's number stands again. */
export function setPageQueueCount(count: number | null): void {
  if (page === count) return
  page = count
  tell()
}

/** The count as it stands: the page's while it knows better, else the server's, else null. */
export function queueCountNow(): number | null {
  return page ?? server
}

/** Whether deadwax can keep ignores, as the count's route last said (2.0.0-player.42: Needs a look warns
 *  when it can't) - null until it has answered. */
export function queueTrackingNow(): boolean | null {
  return tracking
}

/** Re-render the caller as the store moves. */
function useHeard(): void {
  const [, setSeen] = useState(0)
  useEffect(() => {
    const listener = () => setSeen((count) => count + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
}

/** The count, re-rendering as it moves - null until deadwax has first said. */
export function useQueueSummary(): number | null {
  useHeard()
  return queueCountNow()
}

/** Whether deadwax can keep ignores, re-rendering as an answer says (null until one has). */
export function useQueueTracking(): boolean | null {
  useHeard()
  return queueTrackingNow()
}
