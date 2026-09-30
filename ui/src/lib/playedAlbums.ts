/**
 * The album answers the queue's songs were played from, kept so Info can say more about the song
 * playing than the queue does (2.0.0-player.10) - its track number, its disc's title, the album's
 * year, and the names of every field Navidrome sent - without asking a server again.
 *
 * The queue keeps only what playing needs (lib/playQueue.ts's QueueTrack, which the engine owns
 * and this leaves alone). The screen that starts playback has the whole answer in hand at the tap,
 * so it remembers it here, in the same turn, before it calls the player. Only the last few are
 * kept: a queue is one album's songs, and an answer nobody is playing from is only memory.
 *
 * Pure - a small most-recent-first store - so ui/test/info.sim.cjs can hold it to its bound.
 */

/** How many album answers are kept. */
export const PLAYED_KEPT = 8

export interface PlayedAlbums<T extends { id: string }> {
  /** called in the tap that starts playback, with the answer the songs came from */
  remember(album: T): void
  /** the answer for that album id, or null when it was never played from (or has been let go of) */
  get(id: string | null | undefined): T | null
}

export function createPlayedAlbums<T extends { id: string }>(kept: number = PLAYED_KEPT): PlayedAlbums<T> {
  const albums = new Map<string, T>()
  return {
    remember(album) {
      //? taken out first, so the one just played from is the newest whether or not it was there
      albums.delete(album.id)
      albums.set(album.id, album)
      while (albums.size > Math.max(1, kept)) {
        const [oldest] = albums.keys()
        if (oldest === undefined) break
        albums.delete(oldest)
      }
    },
    get(id) {
      return (id ? albums.get(id) : undefined) ?? null
    },
  }
}
