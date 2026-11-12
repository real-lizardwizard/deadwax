import { useRef } from 'preact/hooks'

import type { PanelStyle } from '../lib/appFrame'
import { LYRICS } from '../lib/lyricsView'
import { Lyrics } from '../player/Lyrics'
import type { Player } from '../player/usePlayer'
import type { LyricsAnswers } from './useLyrics'
import { useSheet } from './useSheet'

/**
 * A desktop's Lyrics (2.1.6, notes/app-lyrics.md 3.4): the song's lyrics beside the page, opened from the player bar's
 * Lyrics - as Music on a Mac has them in its sidebar. In Up Next's panel shell (app/UpNext.tsx), the other panel the
 * bar opens and Info's shell too, so app-desktop.css's `.app-layer.is-panel .app-info` rules place, slide and colour
 * it: the title and Done in Info's head, the view (player/Lyrics.tsx) its body. Drawn on a desktop only (App) and never
 * modal: a desktop's side panel leaves the page beside it as it is (useSheet's `modal: false` - focus in to Done as it
 * opens, back to the bar's Lyrics as it closes, Escape from inside it), so its lock class is never put on.
 *
 * The song changing with it open shows the next song's lyrics, at their top - or "No lyrics for this song." With
 * nothing playing (the queue ended or cleared) it stays until closed, saying "Nothing playing", as the bar does.
 */
export function LyricsPanel({
  open,
  opener,
  onClose,
  player,
  answers,
  panel,
  covered = false,
}: {
  open: boolean
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  player: Pick<Player, 'track' | 'playing' | 'position' | 'onPosition' | 'seek' | 'toggle'>
  answers: LyricsAnswers
  /** a desktop's: a drawer over the page's edge, or a column beside it */
  panel: PanelStyle
  /** something over it - the visualizer, the song menu, the picker: inert, out of a screen reader's reach */
  covered?: boolean
}) {
  const done = useRef<HTMLButtonElement>(null)
  const box = useRef<HTMLDivElement>(null)
  useSheet({ open, covered, onClose, lockClass: 'app-lyrics-open', first: done, opener, modal: false, area: box })

  return (
    <div class={`app-layer app-info-layer app-lyrics-layer${open ? ' is-open' : ''} is-panel is-${panel}`} aria-hidden={!open || covered} inert={!open || covered}>
      <div class="app-backdrop" onClick={onClose} />
      {/* the box takes focus from a click on anything in it that can't, so Escape there is still from inside it */}
      <div ref={box} class="app-info app-lyrics-panel" role="dialog" aria-modal="false" aria-labelledby="app-lyrics-title" tabIndex={-1}>
        <header class="app-info-head">
          <h2 id="app-lyrics-title" class="app-info-title">
            {LYRICS}
          </h2>
          <button ref={done} type="button" class="app-info-done" onClick={onClose}>
            Done
          </button>
        </header>
        <Lyrics player={player} answers={answers} shows={open} covered={covered} place="panel" />
      </div>
    </div>
  )
}
