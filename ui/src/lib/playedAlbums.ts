/**
 * The album answers the queue's songs were played from, kept so Info can say more about the song
 * playing than the queue does (2.0.0-player.10) - its track number, its disc's title, the album's
 * year, and the names of every field Navidrome sent - without asking a server again.
 *
 * The queue keeps only what playing needs (lib/playQueue.ts's QueueTrack, which the engine owns
 * and this leaves alone). The screen that starts playback has the whole answer in hand at the tap,
 * so it remembers it here, in the same turn, before it calls the player. Only the last few are
 * kept: an answer nobody is playing from is only memory.
 *
 * A queue is usually one album's songs. Since 2.0.0-player.17 an artist's Play queues every album of
 * theirs you have at once (`rememberQueue`), and every one of them is kept - up to
 * QUEUE_ALBUMS_KEPT, the first to play kept longest - until the next queue is started: keeping only
 * PLAYED_KEPT of them let go of the albums that play FIRST, and Info then had nothing to say about
 * the song playing, nor the turntable which disc's art to show (review).
 *
 * Pure - a small most-recent-first store - so ui/test/info.sim.cjs can hold it to its bounds.
 */

/** How many album answers are kept. */
export const PLAYED_KEPT = 8

/** ...and how many of a queue of several albums, at most (an artist's Play: every album of theirs). */
export const QUEUE_ALBUMS_KEPT = 64

export interface PlayedAlbums<T extends { id: string }> {
  /** called in the tap that starts playback, with the answer the songs came from */
  remember(album: T): void
  /** called in the tap that starts a queue of several albums, with each one's answer in the order
   *  they play: every one kept (up to QUEUE_ALBUMS_KEPT) until the next queue starts */
  rememberQueue(albums: readonly T[]): void
  /** the answer for that album id, or null when it was never played from (or has been let go of) */
  get(id: string | null | undefined): T | null
}

export function createPlayedAlbums<T extends { id: string }>(
  kept: number = PLAYED_KEPT, queueKept: number = QUEUE_ALBUMS_KEPT,
): PlayedAlbums<T> {
  const albums = new Map<string, T>()
  //? how many the newest queue needs kept, past `kept`: its albums, none once another queue starts
  let floor = 0
  const put = (album: T) => {
    //? taken out first, so the one just played from is the newest whether or not it was there
    albums.delete(album.id)
    albums.set(album.id, album)
  }
  const trim = () => {
    while (albums.size > Math.max(1, kept, floor)) {
      const [oldest] = albums.keys()
      if (oldest === undefined) break
      albums.delete(oldest)
    }
  }
  return {
    remember(album) {
      floor = 0
      put(album)
      trim()
    },
    rememberQueue(list) {
      floor = Math.min(new Set(list.map((album) => album.id)).size, Math.max(1, queueKept))
      //? the first to play remembered last - the newest, so the last to be let go past the bound
      for (let index = list.length - 1; index >= 0; index--) put(list[index]!)
      trim()
    },
    get(id) {
      return (id ? albums.get(id) : undefined) ?? null
    },
  }
}
