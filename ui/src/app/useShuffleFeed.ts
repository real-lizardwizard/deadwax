import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { ApiError } from '../api/http'
import { isAbort, latestOnly } from '../lib/latest'
import type { QueueTrack } from '../lib/playQueue'
import type { UpNextQueue } from '../lib/upNext'
import { shufflePage, shuffleStart, toQueueTrack, type Song } from '../player/api'
import type { Player } from '../player/usePlayer'
import { sayPins } from './usePins'

/** Fewer songs than this of a library's shuffle after the song playing, and its next page is asked for - about
 *  three hours of music ahead, so an effect a locked iPhone's throttled timers hold back still has hours to land. */
export const FEED_BELOW = 50
/** A page that wouldn't come is asked for again this long after, while the queue still has songs. */
export const FEED_RETRY_MS = 30_000
/** What the app's notice says, once, when the shuffle's order had gone from deadwax and a fresh one took over. */
export const SHUFFLE_STARTED_OVER = 'Your shuffle started over - deadwax had restarted'

/** A song of a shuffle as the queue takes it: its album known only by its id and name (Info asks for the rest). */
export function shuffledTrack(song: Song): QueueTrack {
  return toQueueTrack(song, { id: song.albumId ?? '', name: song.album ?? '' })
}

/** A fresh order's first page, to follow the queue's last song: never starting with that same song - with any other to
 *  start with, the first is swapped with a random later place (as lib/upNext's toppedUp does for a time round). */
export function startingElsewhere(tracks: readonly QueueTrack[], ending: string | null, random: () => number = Math.random): QueueTrack[] {
  const out = [...tracks]
  if (ending === null || out.length < 2 || out[0]!.id !== ending) return out
  const later = out.map((track, place) => ({ track, place })).filter(({ track, place }) => place > 0 && track.id !== ending)
  const pick = later[Math.floor(random() * later.length)]
  if (pick) [out[0], out[pick.place]] = [out[pick.place]!, out[0]!]
  return out
}

/** How many of the list's songs come after the song playing - what the feed keeps above FEED_BELOW. */
export function songsAhead(queue: UpNextQueue): number {
  const marks = queue.upNext?.marks ?? []
  let count = 0
  for (let place = queue.index + 1; place < marks.length; place++) if (marks[place]!.from === 'source') count++
  return count
}

/**
 * The feed of a whole library's shuffle (2.0.0-player.57, Part B): called once, in App, with the player. While the
 * queue playing is a library's shuffle (its `upNext.paged`) and fewer than FEED_BELOW of its songs follow the song
 * playing, it asks deadwax for the next page of the order (shufflePage - one ask at a time, the newest only) and
 * hands it to the player (extendQueue), which appends it like Play Last. At the end of the whole order: with Repeat
 * All a fresh order (shuffleStart - the list built again if it is old, so songs added since are in it) as the next
 * time round, never starting with the song that ends this one (startingElsewhere); with Repeat off nothing, and the
 * queue ends after the last song, every song heard once. The order
 * gone from deadwax (a 404 - it restarted, or a day untouched): a fresh order as the rest of this round, said once.
 * A page that won't come is asked again after FEED_RETRY_MS while the queue still has songs; the music plays on.
 * Its fresh orders are asked for `claim`ed - they play at once, so deadwax keeps them as orders playing. Repeat
 * turned off (or to One) while a fresh round is on its way lets the ask go, and an answer that lands anyway is
 * dropped unless Repeat is still All; a fresh order with no songs at all (a library emptied meanwhile) is
 * appended as nothing and asked for no more (lib/upNext's withMore hands the queue back as it was).
 *
 * It calls nothing of the player but extendQueue (ui/test/app-rules.sim.cjs): nothing here plays.
 */
export function useShuffleFeed(player: Pick<Player, 'queue' | 'repeat' | 'extendQueue'>): void {
  const queue = player.queue
  const paged = queue.upNext?.paged ?? null
  const ahead = paged ? songsAhead(queue) : Infinity
  const low = ahead < FEED_BELOW
  const asks = useMemo(latestOnly, [])
  //? what is being asked for - the order and where in it - so a render meanwhile asks nothing twice
  const asking = useRef<string | null>(null)
  //? a failed ask's second go: bumped FEED_RETRY_MS later
  const [tries, setTries] = useState(0)
  const extend = player.extendQueue
  const token = paged?.token ?? null
  const fetched = paged?.fetched ?? 0
  const total = paged?.total ?? 0
  const scope = paged?.scope ?? 'store'
  const whole = !!paged && fetched >= total
  const wanted = !!paged && low && (!whole || player.repeat === 'all')
  const ending = queue.tracks[queue.tracks.length - 1]?.id ?? null
  //? Repeat as it is when an answer lands, which may be after a render the effect hasn't caught up with
  const repeatNow = useRef(player.repeat)
  repeatNow.current = player.repeat

  //? another shuffle, or none: what was asked for the one before is let go
  useEffect(() => () => asks.supersede(), [token])

  useEffect(() => {
    if (!wanted || token === null) {
      //? no longer wanted - Repeat turned off while a fresh round was on its way: that ask let go
      if (asking.current !== null) {
        asks.supersede()
        asking.current = null
      }
      return
    }
    const key = `${token}:${fetched}:${whole ? player.repeat : ''}`
    if (asking.current === key) return
    asking.current = key
    const request = asks.begin()
    const fresh = (startedOver: boolean) =>
      shuffleStart(scope, request.signal, { claim: true }).then((first) => {
        if (!request.current()) return
        //? a next round asked for under Repeat All, landing after Repeat changed: not wanted now
        if (!startedOver && repeatNow.current !== 'all') {
          asking.current = null
          return
        }
        extend(token, startingElsewhere(first.songs.map(shuffledTrack), ending), { token: first.token, total: first.total, fetched: 0, scope })
        if (startedOver && first.songs.length) sayPins(SHUFFLE_STARTED_OVER)
      })
    const asked = whole
      ? fresh(false)
      : shufflePage(token, fetched, request.signal).then(
        (page) => {
          if (request.current()) extend(token, page.songs.map(shuffledTrack))
        },
        (reason: unknown) => {
          if (reason instanceof ApiError && reason.status === 404 && request.current()) return fresh(true)
          throw reason
        },
      )
    asked.catch((reason: unknown) => {
      if (isAbort(reason) || !request.current()) return
      //? asked again a while later, from the same place - the music plays on meanwhile
      asking.current = null
      setTimeout(() => setTries((n) => n + 1), FEED_RETRY_MS)
    })
  }, [wanted, token, fetched, whole, player.repeat, tries])
}
