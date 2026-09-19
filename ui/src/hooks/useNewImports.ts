import { useCallback, useEffect, useState } from 'preact/hooks'

import * as api from '../api/library'
import { bridge } from '../bridge'
import { onAlbumsFiled } from '../lib/libraryEvents'
import type { NewImportsResponse } from '../api/types'

/**
 * How many albums jimbrainz has filed that you haven't looked at yet.
 *
 * This is the "prompt me when a release gets added" half of the metadata queue, and it exists
 * as its own tiny hook because of one constraint: the library is deliberately not scanned until
 * its tab is opened (a first scan reads tags off every file), so anything that wanted to badge
 * the tab from the scan would either be absent exactly when it mattered or would tax every page
 * load. The poller records each album as it files it, so this is one indexed table read and can
 * safely run on mount.
 *
 * Recounted the moment the downloads poll sees an album filed (lib/libraryEvents.ts), which is
 * the one thing that changes the count without the user doing anything. The slow poll stays as
 * a floor for whatever that misses - an album filed while this page was closed and not yet
 * noticed, say. Acting on the queue calls `refreshNewImports` through the bridge, so the badge
 * also reacts immediately to anything *you* did.
 */
const POLL_INTERVAL_MS = 60_000

export function useNewImports(): NewImportsResponse & { refresh: () => void } {
  const [state, setState] = useState<NewImportsResponse>({
    count: 0, albums: [], tracking_enabled: true,
  })

  const refresh = useCallback(() => {
    void api.newImports()
      .then(setState)
      //? a failure here must be silent. This drives a badge; the library view is where a real
      //? problem with the library gets reported, loudly.
      .catch(() => undefined)
  }, [])

  useEffect(() => {
    refresh()

    const timer = setInterval(refresh, POLL_INTERVAL_MS)
    const stopHearing = onAlbumsFiled(refresh)

    //? Set rather than called: this is the entry the OTHER tree uses to say "I just reviewed
    //? something, recount". Registered here so it's always the live copy.
    bridge().refreshNewImports = refresh

    return () => {
      clearInterval(timer)
      stopHearing()
      if (bridge().refreshNewImports === refresh) delete bridge().refreshNewImports
    }
  }, [refresh])

  return { ...state, refresh }
}
