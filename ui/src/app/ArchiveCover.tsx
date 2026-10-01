import { useState } from 'preact/hooks'

/**
 * A cover from the Cover Art Archive for an album you don't have (2.0.0-player.13): the first of
 * `addresses` that loads - the pressing's own front, then the album's - or the empty square that
 * stands in for one. Never a broken image.
 *
 * It remembers WHICH addresses failed, as player/Cover.tsx does, not that one did: the page's
 * pressing changes under one mounted cover, and the next pressing's front is still worth asking for.
 * The phone fetches it itself, so with no internet (or no picture on the Archive) it is the square.
 */
export function ArchiveCover({ addresses, class: cls }: { addresses: readonly string[]; class: string }) {
  const [failed, setFailed] = useState<readonly string[]>([])
  const src = addresses.find((address) => !failed.includes(address)) ?? null
  return src ? (
    <img
      class={cls}
      src={src}
      alt=""
      loading="lazy"
      decoding="async"
      onError={() => setFailed((before) => (before.includes(src) ? before : [...before, src]))}
    />
  ) : (
    <span class={`${cls} is-empty`} aria-hidden="true" />
  )
}
