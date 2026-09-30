import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { isAbort, latestOnly } from '../lib/latest'
import { readPlayerOrder, writePlayerOrder } from '../state/persisted'
import { PAGE_SIZE, albumPage, dropPrefetch, prefetchAlbum, type Album, type AlbumOrder } from './api'
import { Cover } from './Cover'

const ORDERS: { id: AlbumOrder; label: string }[] = [
  { id: 'newest', label: 'Recently added' },
  { id: 'recent', label: 'Recently played' },
  { id: 'alphabeticalByArtist', label: 'Artist' },
  { id: 'alphabeticalByName', label: 'Title' },
]

function savedOrder(): AlbumOrder {
  const saved = readPlayerOrder()
  return ORDERS.find((order) => order.id === saved)?.id ?? 'newest'
}

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/** A page added to the albums already shown, leaving out any already there. */
function appendPage(shown: Album[], page: Album[]): Album[] {
  const held = new Set(shown.map((album) => album.id))
  return [...shown, ...page.filter((album) => !held.has(album.id))]
}

/**
 * Every album, a page at a time, in the order chosen.
 *
 * Paged because a library is thousands of albums and Subsonic hands them out 500 at most; the
 * next page is asked for as the end of the grid comes near. Only the newest request counts
 * (lib/latest.ts): changing the order calls off the page on its way for the old one, so a slow
 * answer can't land in the wrong list.
 *
 * The orders are LIVE lists, paged by offset. Playing an album from "Recently played" moves it to
 * the front, and an album filed while you browse joins "Recently added", so every later page
 * shifts by one and repeats the album at the old page's edge - which is why a page leaves out
 * albums already shown, while the offset goes on following what the server handed out.
 */
export function Library({ onOpen }: { onOpen: (album: Album) => void }) {
  const [order, setOrder] = useState<AlbumOrder>(savedOrder)
  const [albums, setAlbums] = useState<Album[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const sentinel = useRef<HTMLDivElement>(null)
  const observer = useRef<IntersectionObserver | null>(null)
  const paging = useRef({ loading: false, done: false, count: 0 })
  const requests = useMemo(latestOnly, [])

  /**
   * Has the observer look at the sentinel afresh. It only speaks when the sentinel CROSSES into
   * range, and its first word, straight after the grid appears, comes while page 1 is still
   * loading and so is passed over. A page that doesn't push the sentinel out of range - a wide
   * window fits 60 albums in a screen - then leaves nothing to cross, and paging would stop at
   * page 1. Observing again always brings one fresh answer.
   */
  function rearm() {
    const host = sentinel.current
    const watcher = observer.current
    if (!host || !watcher) return
    watcher.unobserve(host)
    watcher.observe(host)
  }

  function load(forOrder: AlbumOrder, offset: number) {
    const request = requests.begin()
    paging.current.loading = true
    setLoading(true)
    setError(null)

    albumPage(forOrder, offset, request.signal).then(
      (page) => {
        if (!request.current()) return
        setAlbums((shown) => (offset === 0 ? page : appendPage(shown, page)))
        paging.current = { loading: false, done: page.length < PAGE_SIZE, count: offset + page.length }
        setLoading(false)
        if (!paging.current.done) rearm()
      },
      (reason: unknown) => {
        if (!request.current()) return
        paging.current.loading = false
        setLoading(false)
        if (!isAbort(reason)) setError(message(reason))
      },
    )
  }

  useEffect(() => {
    paging.current = { loading: false, done: false, count: 0 }
    setAlbums([])
    load(order, 0)

    const host = sentinel.current
    if (!host) return () => requests.supersede()
    const watcher = new IntersectionObserver(
      (entries) => {
        const state = paging.current
        if (entries.some((entry) => entry.isIntersecting) && !state.loading && !state.done) {
          load(order, state.count)
        }
      },
      //? well before the end, so the next page is there by the time a flick gets to it
      { rootMargin: '800px 0px' },
    )
    observer.current = watcher
    watcher.observe(host)
    return () => {
      watcher.disconnect()
      observer.current = null
      requests.supersede()
    }
  }, [order, requests])

  function choose(next: AlbumOrder) {
    writePlayerOrder(next)
    setOrder(next)
  }

  return (
    <section class="pl-library">
      <header class="pl-large-header">
        <h1 class="pl-large-title">Library</h1>
      </header>

      <div class="pl-orders" role="tablist" aria-label="Order">
        {ORDERS.map((option) => (
          <button
            key={option.id}
            type="button"
            role="tab"
            aria-selected={option.id === order}
            class={`pl-order${option.id === order ? ' is-active' : ''}`}
            onClick={() => choose(option.id)}
          >
            {option.label}
          </button>
        ))}
      </div>

      <div class="pl-grid">
        {albums.map((album) => (
          <button
            key={album.id}
            type="button"
            class="pl-album"
            //? the album's songs asked for as the finger lands, so Play is usually ready by the time
            //? the page opens; a press that turns into a scroll lets go of the ask (api.ts)
            onPointerDown={() => prefetchAlbum(album.id)}
            onPointerCancel={() => dropPrefetch(album.id)}
            onClick={() => onOpen(album)}
          >
            <Cover id={album.coverArt} size={400} class="pl-album-cover" />
            <span class="pl-album-title">{album.name}</span>
            <span class="pl-album-artist">{album.artist}</span>
          </button>
        ))}
      </div>

      {error && (
        <div class="pl-notice">
          <p>{error}</p>
          <button type="button" class="pl-text-button" onClick={() => load(order, paging.current.count)}>
            Try again
          </button>
        </div>
      )}
      {!error && !loading && !albums.length && (
        <p class="pl-notice">
          {order === 'recent' ? 'Nothing played yet.' : 'No albums in Navidrome yet.'}
        </p>
      )}
      {loading && <div class="pl-spinner" aria-label="Loading" />}
      <div ref={sentinel} class="pl-sentinel" />
    </section>
  )
}
