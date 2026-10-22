import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { isAbort, latestOnly } from '../lib/latest'
import { shuffleStart, type ShuffleStart } from '../player/api'
import { queued } from '../player/levelling'
import { ShuffleIcon } from '../player/icons'
import type { PlayerActions } from './context'
import { shuffledTrack } from './useShuffleFeed'

/** How long a first page asked for ahead stays the one a tap plays - SHUFFLE_LIST_TTL_S in src/routes/navidrome.py:
 *  shown again after longer, the list asks afresh, so songs added meanwhile are in the next shuffle. */
export const SHUFFLE_FRESH_MS = 600_000
/** What the button says while its first page is on its way, and in its title when it won't come. */
export const SHUFFLE_GETTING_READY = 'Getting ready…'
export const SHUFFLE_UNREADY = "Couldn't get your songs ready to shuffle"

/**
 * The Library's Shuffle (2.0.0-player.57, Part B) - James: the Shuffle must play his WHOLE library, not a sample:
 * every song of the scope, each once, in a random order, nothing repeated until every one has played. At the top
 * of the Library's own list - your albums with logins on (`yours`: every song of every album you've starred), the
 * Songs with them off - and of Browse's Songs (`store`: everything). deadwax makes the order, as you
 * (src/routes/navidrome.py /shuffle); the app's feed (useShuffleFeed.ts) brings the rest of it in as it plays.
 *
 * Its first page is asked for as the list shows (and again each time it shows after SHUFFLE_FRESH_MS), so the tap
 * has the songs in hand: playTracks straight from the click, nothing awaited (the gesture rule) - and then a new
 * order asked for, so the next tap is another. Until a page is in, the button is aria-disabled, saying "Getting
 * ready…"; one that won't come leaves it so with why in its title and read out, and asks again the next time the
 * list shows. Under it, "12,480 songs" once known - with `count`, where the page's head counts something else (your
 * albums); the Songs views' head counts the same songs already. A scope with no songs at all draws nothing: the
 * Library says why it is empty.
 *
 * The ask after a tap names the order the tap played (`playing`), until one gets through, so deadwax claims it before
 * the new order replaces it as the one asked ahead - the order playing is paged only ~150 songs later
 * (src/routes/navidrome.py /shuffle; without it, its second page was a 404 and the shuffle "started over").
 *
 * `actions` is the ActionsContext object the Library reads, handed down as one object, so neither Library.tsx nor
 * LibraryViews.tsx names a playback action. A leaf: props only.
 */
export function ShuffleSongs({ scope, shown, actions, count = false }: {
  scope: 'yours' | 'store'
  shown: boolean
  actions: Pick<PlayerActions, 'playTracks'>
  count?: boolean
}) {
  const [first, setFirst] = useState<ShuffleStart | null>(null)
  const [failed, setFailed] = useState(false)
  const asks = useMemo(latestOnly, [])
  const askedAt = useRef<number | null>(null)
  //? the order the last tap played, named in each ask until one gets through - deadwax claims it then
  const played = useRef<string | null>(null)

  const ask = () => {
    const request = asks.begin()
    askedAt.current = Date.now()
    const playing = played.current
    shuffleStart(scope, request.signal, playing ? { playing } : {}).then(
      (answer) => {
        if (!request.current()) return
        if (played.current === playing) played.current = null
        setFirst(answer)
        setFailed(false)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        //? asked again the next time the list shows
        askedAt.current = null
        setFailed(true)
      },
    )
  }

  useEffect(() => {
    if (!shown) return
    const at = askedAt.current
    if (at === null || Date.now() - at > SHUFFLE_FRESH_MS) {
      setFirst(null)
      ask()
    }
  }, [shown])

  useEffect(() => () => asks.supersede(), [])

  const ready = !!first && first.songs.length > 0
  const play = () => {
    if (!first || !first.songs.length) return
    //? (2.0.0-player.62) songs, for the player's Normalization - and the level they got rides on the shuffle, so
    //? its feed queues the rest of it at the same level (useShuffleFeed.ts)
    const tracks = queued(first.songs.map(shuffledTrack), 'songs')
    const level = tracks[0]?.level
    actions.playTracks(tracks, 0, false, { token: first.token, total: first.total, fetched: first.songs.length, scope, ...(level ? { level } : {}) })
    //? a new order for the next tap - naming this one, so it is claimed before the new one replaces it
    played.current = first.token
    setFirst(null)
    ask()
  }

  //? nothing to shuffle: no dead button - the Library's own notice says the library is empty
  if (first && first.total === 0) return null

  return (
    <div class="app-shuffle-songs">
      <button
        type="button"
        class="pl-pill app-shuffle-button"
        aria-disabled={!ready}
        {...(failed ? { title: SHUFFLE_UNREADY } : {})}
        onClick={play}
      >
        <ShuffleIcon class="pl-pill-icon" />
        {ready ? 'Shuffle' : SHUFFLE_GETTING_READY}
      </button>
      {count && first && <p class="app-store-line">{`${first.total.toLocaleString('en-US')} ${first.total === 1 ? 'song' : 'songs'}`}</p>}
      <p class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">{failed ? SHUFFLE_UNREADY : ''}</p>
    </div>
  )
}
