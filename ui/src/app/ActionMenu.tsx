import { useRef } from 'preact/hooks'

import { useSheet } from './useSheet'

/**
 * Now Playing's ••• menu (2.0.0-player.10): Info, "Go to album" and - since 2.0.0-player.18 - "Pin
 * album to Home" (or "Unpin album from Home"). A short sheet from the bottom of the screen over a
 * dimmed Now Playing, since the board draws the ••• button ("More: info, go to album, pin") and not
 * the menu itself.
 *
 * Only what does something today is in it. "Go to album" is left out - not greyed - for a song the
 * queue has no album id for, and the pin for an album that can't be pinned (no album, Navidrome
 * saying it has no release id, or deadwax unable to keep pins) - which App decides as the menu opens,
 * so no row comes or goes while it is up. Until it is known whether the album is pinned (`pinned`
 * null) - or once deadwax turns out unable to keep pins while it is up - the pin's row is drawn and
 * does nothing, so no row moves as an answer lands; its tap is App's - the menu closes, focus back
 * on •••, the pin is saved behind it, and the app's notice says what became of it.
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
  pinned = null,
  onPin = null,
}: {
  open: boolean
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  onInfo: () => void
  /** null when the song playing names no album to go to */
  onAlbum: (() => void) | null
  /** whether the playing song's album is pinned - null until that is known */
  pinned?: boolean | null
  /** pin or unpin it; null (or left out) when it can't be pinned */
  onPin?: (() => void) | null
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
          {onPin && (
            <button
              type="button"
              class="app-menu-item"
              aria-disabled={pinned === null}
              onClick={() => {
                if (pinned !== null) onPin()
              }}
            >
              {pinned ? 'Unpin album from Home' : 'Pin album to Home'}
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
