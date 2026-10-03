import { PinIcon } from '../player/icons'

/** What a pin control says while deadwax's database can't keep pins. */
export const PINS_UNSAVED = "deadwax can't keep pins just now: its database isn't writable"

/**
 * The pin on an album page and an artist page (2.0.0-player.18): a toggle button, `aria-pressed`
 * saying whether it is pinned. On an album (`look` 'icon') it is Album.dc.html's 32px icon button in
 * the bar's top right, named "Pin to Home" whichever way it is; on an artist (`look` 'chip') it is
 * Artist.dc.html's chip in the hero's top right, saying "Pin" or "Pinned", toggled purple when on.
 *
 * Its tap calls `onToggle` and nothing else - pinning plays nothing, so no gesture rule binds it -
 * and while what it pins isn't known yet (`ready` false: the album's release still being asked for,
 * the artist's MusicBrainz id not settled, the pins not answered yet) or deadwax can't keep pins
 * (`unsaved`), it is aria-disabled and its tap does nothing: drawn from the first frame, so nothing
 * moves as it comes alive, and focus is never dropped from it. A tap while deadwax can't keep pins
 * calls `onRefused`, which says why in the app's notice - a title alone never shows on a phone.
 *
 * A leaf: props only.
 */
export function PinToggle({
  look,
  pinned,
  ready,
  unsaved = false,
  onToggle,
  onRefused,
}: {
  look: 'icon' | 'chip'
  pinned: boolean
  ready: boolean
  unsaved?: boolean
  onToggle: () => void
  /** a tap while deadwax can't keep pins */
  onRefused?: () => void
}) {
  const off = !ready || unsaved
  return (
    <button
      type="button"
      class={`app-pin-toggle is-${look}${pinned ? ' is-on' : ''}`}
      aria-pressed={pinned}
      aria-disabled={off}
      {...(look === 'icon' ? { 'aria-label': 'Pin to Home' } : {})}
      {...(unsaved ? { title: PINS_UNSAVED } : {})}
      onClick={() => {
        if (!off) onToggle()
        else if (unsaved) onRefused?.()
      }}
    >
      <PinIcon class="app-pin-icon" />
      {look === 'chip' && <span class="app-pin-word">{pinned ? 'Pinned' : 'Pin'}</span>}
    </button>
  )
}
