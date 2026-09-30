import { useRef } from 'preact/hooks'

import { useSheet } from './useSheet'

/**
 * Now Playing's ••• menu (2.0.0-player.10): Info, and "Go to album". A short sheet from the bottom
 * of the screen over a dimmed Now Playing, since the board draws the ••• button and not the menu
 * itself.
 *
 * Only what does something today is in it. "Go to album" is left out - not greyed - for a song the
 * queue has no album id for. (Pin joins it when pins are built.)
 *
 * A sheet like the others (useSheet.ts): its own scroll lock, focus in to its first row and back
 * to the ••• button, Escape, a tap on the backdrop; inert while closed. `opener` is left out by App
 * when the menu closes BECAUSE Info is opening - Info gives focus back to ••• itself, later.
 *
 * A leaf: props only.
 */
export function ActionMenu({
  open,
  opener,
  onClose,
  onInfo,
  onAlbum,
}: {
  open: boolean
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  onInfo: () => void
  /** null when the song playing names no album to go to */
  onAlbum: (() => void) | null
}) {
  const first = useRef<HTMLButtonElement>(null)
  useSheet({ open, onClose, lockClass: 'app-menu-open', first, opener })

  return (
    <div class={`app-layer app-menu-layer${open ? ' is-open' : ''}`} aria-hidden={!open} inert={!open}>
      <div class="app-backdrop" onClick={onClose} />
      <div class="app-menu" role="dialog" aria-modal="true" aria-label="More">
        <div class="app-group">
          <button ref={first} type="button" class="app-menu-item" onClick={onInfo}>
            Info
          </button>
          {onAlbum && (
            <button type="button" class="app-menu-item" onClick={onAlbum}>
              Go to album
            </button>
          )}
        </div>
        <button type="button" class="app-button app-menu-cancel" onClick={onClose}>
          Cancel
        </button>
      </div>
    </div>
  )
}
