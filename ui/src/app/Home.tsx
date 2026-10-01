import { useEffect, useMemo, useState } from 'preact/hooks'

import { isAbort, latestOnly } from '../lib/latest'
import type { RequestRow } from '../lib/requestsView'
import { albumPage, dropPrefetch, prefetchAlbum, type Album, type NavidromeStatus } from '../player/api'
import { Cover } from '../player/Cover'
import { Arriving } from './Arriving'
import { NeedsNavidrome } from './NeedsNavidrome'

/** How many albums the shelf shows. */
export const RECENT_COUNT = 20

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/**
 * "Recently added": Navidrome's newest albums (getAlbumList2 `newest`), in a row you swipe along.
 * A tile OPENS the album - it never plays it, since Play has to be pressed in the tap that starts
 * it, with the songs already in hand - and asks for the album's songs as the finger lands
 * (prefetchAlbum), so the page usually has them by the time it opens.
 */
function RecentlyAdded({ onOpen }: { onOpen: (album: Album) => void }) {
  const [albums, setAlbums] = useState<Album[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const requests = useMemo(latestOnly, [])

  function load() {
    const request = requests.begin()
    setError(null)
    albumPage('newest', 0, request.signal, RECENT_COUNT).then(
      (page) => {
        if (request.current()) setAlbums(page)
      },
      (reason: unknown) => {
        if (request.current() && !isAbort(reason)) setError(message(reason))
      },
    )
  }

  useEffect(() => {
    load()
    return () => requests.supersede()
  }, [requests])

  return (
    <section class="app-section app-shelf-section" aria-labelledby="app-recent-title">
      <h2 id="app-recent-title" class="app-section-title app-shelf-title">
        Recently added
      </h2>
      {error ? (
        <div class="pl-notice">
          <p>{error}</p>
          <button type="button" class="pl-text-button" onClick={load}>
            Try again
          </button>
        </div>
      ) : albums === null ? (
        <div class="pl-spinner" aria-label="Loading" />
      ) : albums.length ? (
        <ul class="app-shelf">
          {albums.map((album) => (
            <li key={album.id} class="app-shelf-item">
              <button
                type="button"
                class="app-tile"
                onPointerDown={() => prefetchAlbum(album.id)}
                onPointerCancel={() => dropPrefetch(album.id)}
                onClick={() => onOpen(album)}
              >
                <Cover id={album.coverArt} size={260} class="app-tile-cover" />
                {/* one block, as the board has it: the two lines sit together under the cover */}
                <span class="app-tile-text">
                  <span class="app-tile-title">{album.name}</span>
                  <span class="app-tile-artist">{album.artist}</span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p class="pl-notice">No albums in Navidrome yet.</p>
      )}
    </section>
  )
}

/**
 * Home, the first tab: what's arriving - only while something is (2.0.0-player.12) - and what was
 * added recently. Pinned albums and artists, and what hasn't been played in a while, come in later
 * steps; none of them is faked meanwhile.
 *
 * Arriving is deadwax's, not Navidrome's, so it draws whatever Navidrome says; the shelf needs
 * Navidrome and is gated on it. The shelf is memoised on what it reads: App re-renders Home as the
 * downloads move, and that must not re-render twenty tiles each time.
 */
export function Home({
  status,
  onRetry,
  onOpen,
  arriving,
  onSeeAll,
  arrivingTrouble = false,
}: {
  status: NavidromeStatus | null
  onRetry: () => void
  onOpen: (album: Album) => void
  /** the downloads on their way, up to three - none, and there is no Arriving section at all */
  arriving: readonly RequestRow[]
  /** "See all", and a tap on an Arriving card: the Requests tab's list, at its root */
  onSeeAll: () => void
  /** deadwax didn't answer the last look: Arriving says its cards are the last answer */
  arrivingTrouble?: boolean
}) {
  const shelf = useMemo(
    () => (
      <NeedsNavidrome status={status} onRetry={onRetry}>
        <RecentlyAdded onOpen={onOpen} />
      </NeedsNavidrome>
    ),
    [status, onRetry, onOpen],
  )

  return (
    <section class="app-home">
      <header class="pl-large-header">
        <h1 class="pl-large-title">Home</h1>
      </header>
      <Arriving rows={arriving} onSeeAll={onSeeAll} trouble={arrivingTrouble} />
      {shelf}
    </section>
  )
}
