import { useEffect, useLayoutEffect, useRef } from 'preact/hooks'

import { ArtViewer, type ViewerImage } from '../components/ArtViewer'

/** The class on <html> while the viewer shows: the page behind it doesn't scroll (app.css). */
export const VIEWER_LOCK = 'app-viewer-open'

/**
 * The cover viewer in the app (2.0.0-player.44): the main page's own (components/ArtViewer.tsx - zoom
 * about the cursor, drag, pinch, notes/library.md "Looking at a cover close up"), as it is, over the
 * whole window - opened from an album page's cover (both frames: it only reads), from the Edit panel's
 * Artwork (the cover, each CD art picture) and from the track inspector's pictures.
 *
 * What the app adds round it, the way its sheets do (useSheet.ts): its own scroll lock on <html>; focus
 * into its Close button as it opens - before the paint - and back to what opened it as it closes (the
 * opener taken in the tap, by takeOpener, which has it focus itself: WebKit never focuses a tapped
 * button); and Tab kept inside it - it lies over everything with its scrim, so a key that walked out
 * of it would be on a control nobody can see. Escape is the viewer's own: it takes it on the window's
 * capture and stops it there, so one press closes the viewer and nothing under it (the Edit panel's
 * track inspector, the panel itself). Styled by app.css's `.app-viewer` on both frames, and inside the
 * Edit panel on a desktop as the release editor's "Compare full size" is (app-desktop.css).
 *
 * `images` null is closed. Drawn where it is opened from - inside the Edit panel for the panel's, so the
 * panel letting its editors go once it has closed lets this go too. A move through the browser's history
 * closes it (review): an album page in a tab not shown stays mounted, hidden, and so would its viewer.
 */
export function CoverViewer({
  images,
  onClose,
  opener,
}: {
  images: ViewerImage[] | null
  onClose: () => void
  /** what opened it, given focus back as it closes */
  opener?: { current: HTMLElement | null } | undefined
}) {
  const box = useRef<HTMLDivElement>(null)
  const open = !!images && images.length > 0

  useEffect(() => {
    if (!open) return
    const page = document.documentElement
    page.classList.add(VIEWER_LOCK)
    return () => page.classList.remove(VIEWER_LOCK)
  }, [open])

  //? (review) Back or Forward while it shows - a mouse's back button, a trackpad's swipe, a phone's back
  //? gesture - closes it. Its scrim covers every control that moves the app, so a move through the
  //? history is the one way the page it was opened from can stop showing under it; and a tab's page is
  //? kept mounted, only hidden, so a viewer left open in one would hold its lock on the page shown and
  //? take that page's next Escape, out of sight. The app's own moves (a tab, a page opened) push or
  //? replace the address, which fires neither event.
  const closeNow = useRef(onClose)
  closeNow.current = onClose
  useEffect(() => {
    if (!open) return
    const moved = () => closeNow.current()
    window.addEventListener('popstate', moved)
    window.addEventListener('hashchange', moved)
    return () => {
      window.removeEventListener('popstate', moved)
      window.removeEventListener('hashchange', moved)
    }
  }, [open])

  const wasOpen = useRef(false)
  useLayoutEffect(() => {
    if (open) {
      wasOpen.current = true
      box.current?.querySelector<HTMLElement>('.window-close')?.focus({ preventScroll: true })
      return
    }
    //? never opened: nothing to give back, and a first render must not move focus
    if (!wasOpen.current) return
    wasOpen.current = false
    opener?.current?.focus({ preventScroll: true })
  }, [open])

  //? Tab round its own buttons, never out to the page under the scrim
  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key !== 'Tab' || !box.current) return
    const stops = [...box.current.querySelectorAll<HTMLElement>('button:not([disabled])')]
    const first = stops[0]
    const last = stops[stops.length - 1]
    if (!first || !last) return
    const active = document.activeElement
    const inside = !!active && box.current.contains(active)
    if (event.shiftKey ? (!inside || active === first) : (!inside || active === last)) {
      event.preventDefault()
      ;(event.shiftKey ? last : first).focus({ preventScroll: true })
    }
  }

  return open ? (
    <div ref={box} class="app-viewer" onKeyDown={onKeyDown}>
      <ArtViewer images={images!} onClose={onClose} />
    </div>
  ) : null
}
