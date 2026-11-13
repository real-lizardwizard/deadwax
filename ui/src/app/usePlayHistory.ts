import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { isAbort, latestOnly } from '../lib/latest'
import { NOTHING_HELD, merged, withNewest, withOlder, type Held, type Played } from '../lib/playHistory'
import { historyPage } from '../player/api'
import { onStarts, ownStarts } from '../player/historyOutbox'

/**
 * The person's play history as Up Next draws it (2.1.15, notes/play-history.md) - deadwax's pages and this page's own
 * starts, newest first, each start once (lib/playHistory.ts merged). Called once, in App.
 *
 *  - THE NEWEST PAGE is asked for each time Up Next opens and each time the page shows again while it is open (a
 *    desktop's panel left open picks up the phone's plays), and joined to what is held (withNewest).
 *  - OLDER PAGES as Up Next is scrolled near its top (app/UpNext.tsx calls `older`), one at a time, from the cursor the
 *    last one gave (withOlder) - until there are none.
 *  - THIS PAGE'S OWN STARTS (player/historyOutbox.ts) drawn the moment they are made, before deadwax has them.
 *  - ONLY THE NEWEST ANSWER DRAWS (lib/latest.ts): the newest page's asks and the older ones' each their own.
 *  - A FAILURE is kept, for Up Next to say in a listener's words with Try again (`retry`, the ask that failed) -
 *    and scrolling asks no more until it is tried again.
 *
 * A different person signing in reloads the page (app/signInGate.tsx), so nothing here is ever anyone else's.
 */
export interface PlayHistory {
  /** every start held, newest first */
  plays: readonly Played[]
  /** there are older plays than those held */
  more: boolean
  /** an older page is on its way */
  loading: boolean
  /** the last ask's failure; null when it didn't fail */
  error: unknown
  /** the page before the oldest held */
  older(): void
  /** the ask that failed, again */
  retry(): void
}

export function usePlayHistory(
  /** Up Next is open (a phone's sheet, a desktop's panel) */
  open: boolean,
  /** the page is showing (App's usePageShown) */
  shown: boolean,
): PlayHistory {
  const [held, setHeldShown] = useState<Held>(NOTHING_HELD)
  const [own, setOwn] = useState(ownStarts)
  const [loading, setLoading] = useState(false)
  const [failed, setFailed] = useState<{ error: unknown; ask: 'newest' | 'older' } | null>(null)
  const newest = useRef(latestOnly())
  const earlier = useRef(latestOnly())
  //? what is held, read by an ask without being one of its reasons to be made again
  const now = useRef(held)
  const setHeld = (change: (was: Held) => Held) => {
    const next = change(now.current)
    now.current = next
    setHeldShown(next)
  }
  const asking = useRef(false)

  useEffect(() => onStarts(() => setOwn(ownStarts())), [])

  const refresh = useCallback(() => {
    const ticket = newest.current.begin()
    historyPage(null, ticket.signal).then(
      (page) => {
        if (!ticket.current()) return
        setHeld((was) => withNewest(was, page))
        setFailed((was) => (was?.ask === 'newest' ? null : was))
      },
      (error: unknown) => {
        if (!ticket.current() || isAbort(error)) return
        setFailed({ error, ask: 'newest' })
      },
    )
  }, [])

  const older = useCallback(() => {
    const from = now.current.before
    if (!from || asking.current) return
    asking.current = true
    setLoading(true)
    const ticket = earlier.current.begin()
    historyPage(from, ticket.signal).then(
      (page) => {
        if (!ticket.current()) return
        asking.current = false
        setLoading(false)
        setHeld((was) => withOlder(was, from, page))
        setFailed((was) => (was?.ask === 'older' ? null : was))
      },
      (error: unknown) => {
        if (!ticket.current() || isAbort(error)) return
        asking.current = false
        setLoading(false)
        setFailed({ error, ask: 'older' })
      },
    )
  }, [])

  const retry = useCallback(() => {
    const ask = failed?.ask
    setFailed(null)
    if (ask === 'older') older()
    else refresh()
  }, [failed, older, refresh])

  //? the newest page as Up Next opens, and as the page shows again while it is open
  useEffect(() => {
    if (open && shown) refresh()
  }, [open, shown])

  const plays = useMemo(() => merged(held.plays, own), [held.plays, own])
  return useMemo(
    () => ({ plays, more: held.before !== null, loading, error: failed?.error ?? null, older, retry }),
    [plays, held.before, loading, failed, older, retry],
  )
}
