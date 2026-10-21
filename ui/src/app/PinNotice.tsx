import { useEffect } from 'preact/hooks'

import { clearPinNotice, usePinNotice } from './usePins'

/** How long the notice stays on screen. */
export const PIN_NOTICE_MS = 5000

/**
 * The app's one notice for pins (2.0.0-player.18): what became of a pin made where nothing on screen
 * can say - a pin or an unpin deadwax wouldn't keep ("Couldn't pin Dummy: Home holds up to 50 pins -
 * unpin one first"), from an album page, an artist page or Now Playing's ••• menu; what the menu's pin
 * did, since the menu closes as it is tapped ("Pinned Dummy to Home"); why a greyed pin does
 * nothing when tapped (PINS_UNSAVED); (2.0.0-player.57) what Play Next or Play Last did ("Playing next:
 * Roads"), the song menu closing as it is tapped too; and (2.0.0-player.58) what became of an Add to a playlist
 * ("Added 11 songs to Late night"), a playlist made from the picker, or one deleted - the picker closing as it is
 * done. Drawn once, by App, over everything - Now Playing and its sheets
 * included - at the top of the screen, beside where a page's pin is; it takes no taps, so nothing
 * under it is lost while it shows, and goes after PIN_NOTICE_MS. Always in the page, as a polite
 * status region, since iOS reads only a region already there.
 */
export function PinNotice() {
  const notice = usePinNotice()
  const id = notice?.id ?? null
  useEffect(() => {
    if (id === null) return
    const timer = setTimeout(() => clearPinNotice(id), PIN_NOTICE_MS)
    return () => clearTimeout(timer)
  }, [id])
  return (
    <p class={`app-pin-notice${notice ? ' is-shown' : ''}`} role="status" aria-live="polite" aria-atomic="true">
      {notice?.text ?? ''}
    </p>
  )
}
