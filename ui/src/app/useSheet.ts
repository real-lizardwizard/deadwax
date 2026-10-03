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
 *
 * A DESKTOP SIDE PANEL (2.0.0-player.19, lib/appFrame.ts's panel rule) is the same sheet drawn
 * beside the page - Sources and Info - and is not modal (`modal: false`): the page beside it is
 * still the page you are using, so it takes no scroll lock. Focus still goes in as it opens and
 * back as it closes, and Escape still closes it - from inside it (`area`): Escape in the page beside
 * it is the page's (a search field clearing itself, a list closing). A panel that becomes a sheet
 * while open (or a sheet a panel) takes focus in again, unless it already has it.
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
  /** false for a desktop side panel: the page beside it isn't locked (default true, a sheet) */
  modal?: boolean
  /** a panel's own box: when it isn't modal, Escape closes it only from inside */
  area?: RefObject<HTMLElement>
}

export function useSheet({ open, covered = false, onClose, lockClass, first, opener, modal = true, area }: SheetOptions): void {
  //? read through a ref, so a new onClose each render doesn't take the key listener off and on
  const close = useRef(onClose)
  close.current = onClose

  useEffect(() => {
    document.documentElement.classList.toggle(lockClass, open && modal)
  }, [open, lockClass, modal])

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

  //? A panel turned into a sheet, or a sheet into a panel, while it is open - the window crossing
  //? 1024px, an iPad turned (2.0.0-player.19): behind a sheet the page goes inert, so focus left out
  //? there is focus nowhere, and the head's button may be another one now (Cancel, or the panel's
  //? close), the one that had focus gone. So focus goes in again, unless it is already inside.
  const wasModal = useRef(modal)
  useLayoutEffect(() => {
    if (wasModal.current === modal) return
    wasModal.current = modal
    if (!open) return
    if (area?.current && area.current.contains(document.activeElement)) return
    first.current?.focus({ preventScroll: true })
  }, [modal])

  useEffect(() => {
    if (!open || covered) return
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || event.defaultPrevented) return
      //? a panel beside the page: Escape out there is the page's
      if (!modal && area?.current && !area.current.contains(event.target as Node | null)) return
      event.preventDefault()
      close.current()
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [open, covered, modal])
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
