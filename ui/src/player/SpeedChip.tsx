import { SPEED_NORMAL, speedLabel, speedWords } from '../lib/playSpeed'
import { useSpeed, type Player } from './usePlayer'

/**
 * The speed, where there is no fader to show it (2.0.0-player.39): a small chip - "1.25x" - wherever
 * the speed isn't 1x, and a tap on it puts it back to exactly 1x. Now Playing's cover look has it in its
 * icon row (and the turntable look too on a phone on its side, where the plinth is too small to read
 * the fader's readout - app.css), and the desktop's player bar in its tools - so a speed set on a phone
 * is never stuck unseen in the desktop frame an iPad turns into. Nothing is drawn at 1x, and where it
 * sits nothing moves when it comes and goes: the icon row is one fixed height and holds its buttons at
 * its right end, as the bar's tools are. The mini player has none.
 *
 * - Its name starts with what it shows, "1.25x" - so Voice Control finds it by what is on screen - then
 *   says it in words and what a tap does (review: WCAG's label in name).
 * - Its tap takes it away, so focus on it - a keyboard's, VoiceOver's - goes on to the next button in its
 *   row, which stays (AirPlay, •••, the bar's Info), never to the page (review). A finger's tap gives a
 *   button no focus in WebKit, and moves none.
 *
 * ui/test/app-rules.sim.cjs allows this file setSpeed, and nothing else of the player.
 */
export function SpeedChip({ player }: { player: Pick<Player, 'speed' | 'onSpeed' | 'setSpeed'> }) {
  const speed = useSpeed(player)
  if (speed === SPEED_NORMAL) return null
  const onTap = (event: MouseEvent) => {
    const chip = event.currentTarget as HTMLElement
    const next = chip.ownerDocument.activeElement === chip ? (chip.nextElementSibling as HTMLElement | null) : null
    player.setSpeed(SPEED_NORMAL)
    next?.focus()
  }
  return (
    <button
      type="button"
      class="app-speed-chip"
      onClick={onTap}
      aria-label={`${speedLabel(speed)}, ${speedWords(speed)} the song's speed: back to normal speed`}
    >
      {/* a tap target tall, STYLE.md's toggled chip drawn inside it */}
      <span class="app-speed-chip-face">{speedLabel(speed)}</span>
    </button>
  )
}
