import { useRef } from 'preact/hooks'

import { queuedWords, type QueuePick } from '../lib/upNext'
import { rememberAdded, type AlbumWithSongs } from '../player/api'
import type { Player } from '../player/usePlayer'
import { sayPins } from './usePins'
import { useSheet } from './useSheet'

/**
 * The song menu (2.0.0-player.57, Up Next, shuffle and repeat): a song's ••• - on an album page's rows,
 * Search's library songs and the Library's Songs - or an album page's own ••• for the whole album, as
 * ActionMenu's sheet is drawn: Play Next, Play Last, Cancel. On a desktop the same sheet, at the bottom of the
 * window (`.app-menu`'s width) - a side panel would be wrong for a two-second choice.
 *
 * A row's tap, straight from the click, nothing awaited (the gesture rule - Play Next with nothing playing
 * starts the music): the albums remembered for Info (rememberAdded), then player.playNext or playLast with the
 * songs the menu was opened with, then the menu closes and - only when the songs were QUEUED rather than
 * started (the player says which) - the app's one notice says so ("Playing next: Roads"). When the music
 * started from it, the mini player says so.
 *
 * A sheet like the others (useSheet.ts): its own scroll lock, focus in to its first row and back to the •••
 * that opened it, Escape, a tap on the backdrop; inert while closed. The ONE file that calls playNext and
 * playLast (ui/test/app-rules.sim.cjs). A leaf: props only.
 */
export function QueueMenu({
  open,
  pick,
  opener,
  onClose,
  player,
}: {
  open: boolean
  /** what it was opened with - one song or an album's songs, always in hand; kept as it slides away */
  pick: QueuePick<AlbumWithSongs> | null
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  player: Pick<Player, 'playNext' | 'playLast'>
}) {
  const first = useRef<HTMLButtonElement>(null)
  useSheet({ open, onClose, lockClass: 'app-queue-menu-open', first, opener })

  const add = (how: 'next' | 'last') => {
    if (!pick || !pick.tracks.length) return
    rememberAdded(pick.albums)
    const started = how === 'next' ? player.playNext(pick.tracks) : player.playLast(pick.tracks)
    onClose()
    if (!started) sayPins(queuedWords(how, pick.label))
  }

  return (
    <div class={`app-layer app-menu-layer app-queue-menu-layer${open ? ' is-open' : ''}`} aria-hidden={!open} inert={!open}>
      <div class="app-backdrop" onClick={onClose} />
      <div class="app-menu" role="dialog" aria-modal="true" aria-label={pick?.label || 'Up Next'}>
        <div class="app-group">
          <button ref={first} type="button" class="app-menu-item" onClick={() => add('next')}>
            Play Next
          </button>
          <button type="button" class="app-menu-item" onClick={() => add('last')}>
            Play Last
          </button>
        </div>
        <button type="button" class="app-button app-menu-cancel" onClick={onClose}>
          Cancel
        </button>
      </div>
    </div>
  )
}
