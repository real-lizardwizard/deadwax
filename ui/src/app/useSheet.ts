import type { RefObject } from 'preact'
import { useEffect, useLayoutEffect, useRef } from 'preact/hooks'

/**
 * What every sheet over the app does (2.0.0-player.10): Now Playing, its ••• menu, and Info. A
 * hook and not a wrapping component, so each sheet calls it itself and the fake-Preact sims, which
 * render one component and none inside it, run all of it (ui/test/info.sim.cjs).
 *
 *  - ITS OWN SCROLL LOCK. Each sheet puts a class of its own on <html> while it is open, and the
 *    stylesheet stops the page behind scrolling for each. One shared class would be taken off by
 *    whichever sheet closed first, with another still open over the page.
 *  - FOCUS GOES IN as it opens, to `first`, before the paint - everything behind a sheet is inert,
 *    and focus left on something inert is focus nowhere.
 *  - FOCUS GOES BACK to what opened it as it closes. The opener is taken in the tap, by
 *    takeOpener() below, which has it focus ITSELF first: WebKit doesn't focus a button that was
 *    tapped or clicked, so without that there was nothing to give focus back to on an iPhone or in
 *    Safari, and it fell to the top of the page.
 *  - ESCAPE closes it - the sheet on top only. A sheet with another over it (`covered`) is still
 *    open and doesn't listen, so one press closes one sheet.
 *
 * What the hook can't do is the markup's: a sheet is `inert` while closed (and while covered), and
 * a tap on its backdrop calls the same `onClose`.
 */
export interface SheetOptions {
  open: boolean
  /** another sheet is over this one - it stays open, and isn't the one Escape closes */
  covered?: boolean
  onClose: () => void
  /** this sheet's own class on <html> while it is open */
  lockClass: string
  /** what takes focus as it opens */
  first: RefObject<HTMLElement>
  /** what opened it - see takeOpener() - given focus back as it closes */
  opener?: { current: HTMLElement | null } | undefined
}

export function useSheet({ open, covered = false, onClose, lockClass, first, opener }: SheetOptions): void {
  //? read through a ref, so a new onClose each render doesn't take the key listener off and on
  const close = useRef(onClose)
  close.current = onClose

  useEffect(() => {
    document.documentElement.classList.toggle(lockClass, open)
  }, [open, lockClass])

  const wasOpen = useRef(false)
  useLayoutEffect(() => {
    if (open) {
      wasOpen.current = true
      first.current?.focus({ preventScroll: true })
      return
    }
    //? never opened: there is nothing to give back, and a first render must not move focus
    if (!wasOpen.current) return
    wasOpen.current = false
    opener?.current?.focus({ preventScroll: true })
  }, [open])

  useEffect(() => {
    if (!open || covered) return
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || event.defaultPrevented) return
      event.preventDefault()
      close.current()
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [open, covered])
}

/**
 * The control a sheet was opened from, taken in its tap: it focuses itself first - the WebKit
 * rule, since a tapped button there never had focus - and is then what the sheet gives focus back
 * to as it closes. Null for an event with no element behind it.
 */
export function takeOpener(event: { currentTarget: EventTarget | null }): HTMLElement | null {
  const target = event.currentTarget
  if (!(target instanceof HTMLElement)) return null
  target.focus({ preventScroll: true })
  return target
}
