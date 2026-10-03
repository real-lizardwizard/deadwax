import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { isAbort, latestOnly } from '../lib/latest'

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/** A page added to the items already shown, leaving out any already there (by id). */
export function appendPage<T extends { id: string }>(shown: readonly T[], page: readonly T[]): T[] {
  const held = new Set(shown.map((item) => item.id))
  return [...shown, ...page.filter((item) => !held.has(item.id))]
}

export interface Paged<T> {
  items: T[]
  loading: boolean
  error: string | null
  /** every page is in: the list is the whole of it */
  done: boolean
  /** ask again for the page that failed */
  retry: () => void
  /** put on the element at the end of the list: the next page is asked for as it comes near */
  sentinel: { current: HTMLDivElement | null }
}

/**
 * A list a page at a time, the next page asked for as the end of it comes near - the Library's
 * albums (since 1.0.3, as Library.tsx's own code until 2.0.0-player.17) and its songs.
 *
 * Paged because a library is thousands of albums and Subsonic hands out 500 at most. Only the
 * newest request counts (lib/latest.ts): a new `key` (another order) calls off the page on its way
 * for the old one, so a slow answer can't land in the wrong list.
 *
 * The lists are LIVE, paged by offset: an album played moves to the front of "Recently played",
 * one filed joins "Recently added", so every later page shifts by one and repeats the item at the
 * old page's edge - which is why a page leaves out items already shown (appendPage), while the
 * offset goes on following what the server handed out.
 */
export function usePaged<T extends { id: string }>(
  fetchPage: (offset: number, signal: AbortSignal | undefined) => Promise<T[]>,
  pageSize: number,
  key: string,
): Paged<T> {
  const [items, setItems] = useState<T[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)
  const sentinel = useRef<HTMLDivElement>(null)
  const observer = useRef<IntersectionObserver | null>(null)
  const paging = useRef({ loading: false, done: false, count: 0 })
  const requests = useMemo(latestOnly, [])
  //? what the observer's callback reads, made once per key: this render's fetch, never the first's
  const fetcher = useRef(fetchPage)
  fetcher.current = fetchPage

  /**
   * Has the observer look at the sentinel afresh. It only speaks when the sentinel CROSSES into
   * range, and its first word, straight after the list appears, comes while page 1 is still
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

  function load(offset: number) {
    const request = requests.begin()
    paging.current.loading = true
    setLoading(true)
    setError(null)

    fetcher.current(offset, request.signal).then(
      (page) => {
        if (!request.current()) return
        setItems((shown) => (offset === 0 ? page : appendPage(shown, page)))
        paging.current = { loading: false, done: page.length < pageSize, count: offset + page.length }
        setDone(paging.current.done)
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
    setItems([])
    setDone(false)
    load(0)

    const host = sentinel.current
    if (!host || typeof IntersectionObserver !== 'function') return () => requests.supersede()
    const watcher = new IntersectionObserver(
      (entries) => {
        const state = paging.current
        if (entries.some((entry) => entry.isIntersecting) && !state.loading && !state.done) load(state.count)
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
  }, [key, requests])

  return { items, loading, error, done, retry: () => load(paging.current.count), sentinel }
}
