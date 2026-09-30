import { useState } from 'preact/hooks'

import { coverUrl } from './api'

/**
 * A cover, or the empty square that stands in for one - never a broken image.
 *
 * It remembers WHICH address failed, not that one did: the mini player and the now-playing sheet
 * keep one Cover mounted from song to song, and a plain "failed" flag - set once by Navidrome
 * restarting, or a dropped connection - blanked their art for every song after it.
 *
 * Its own module since the app's tabs (2.0.0-player.9): Home's shelf, the Library grid, the album
 * page, the mini player and Now Playing all draw one.
 */
export function Cover({ id, size, class: cls }: { id: string | null | undefined; size: number; class: string }) {
  const [failed, setFailed] = useState<string | null>(null)
  const address = coverUrl(id, size)
  const src = address !== failed ? address : null
  return src ? (
    <img class={cls} src={src} alt="" loading="lazy" decoding="async" onError={() => setFailed(src)} />
  ) : (
    <span class={`${cls} is-empty`} aria-hidden="true" />
  )
}
