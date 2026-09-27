import { useEffect, useRef } from 'preact/hooks'
import type { RefObject } from 'preact'

/**
 * Close something that hangs open - a panel, a dropdown - on a click outside it, and on Escape
 * when asked to.
 *
 * Judged by where the press BEGAN as well as where it ended. A press inside released outside - a
 * drag on a toolbar, a text selection run off the edge, a press on a label that slips off it -
 * fires its click on what the two have in common, which is outside, and closed whatever it
 * started in. Found on the downloads panel once it stopped moving with the pointer (v0.6.8);
 * shared since v0.9.23, when the candidate dropdowns turned out to have the same bug. (A range
 * slider's own drag was always safe: the slider keeps the pointer, so the click lands on it.)
 * Cleared on every click, so a keyboard click, which has no press, is judged by its target alone.
 *
 * `close` is read through a ref, so a new one each render doesn't re-subscribe - which would
 * forget a press in progress whenever something rendered between the press and the release.
 */
export function useDismiss(
  rootRef: RefObject<HTMLElement>,
  open: boolean,
  close: () => void,
  { escape = false }: { escape?: boolean } = {},
): void {
  const closeRef = useRef(close)
  closeRef.current = close

  useEffect(() => {
    if (!open) return

    let pressedInside = false

    const onPointerDown = (event: PointerEvent) => {
      pressedInside = rootRef.current?.contains(event.target as Node) ?? false
    }

    const onClick = (event: MouseEvent) => {
      const root = rootRef.current
      if (root && !pressedInside && !root.contains(event.target as Node)) closeRef.current()
      pressedInside = false
    }

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') closeRef.current()
    }

    document.addEventListener('pointerdown', onPointerDown, true)
    document.addEventListener('click', onClick)
    if (escape) document.addEventListener('keydown', onKeyDown)

    return () => {
      document.removeEventListener('pointerdown', onPointerDown, true)
      document.removeEventListener('click', onClick)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [open, escape])
}
