import { CheckIcon } from '../player/icons'
import type { Player } from '../player/usePlayer'

/**
 * "Gapless" in You > Playback: a checkbox, as the You board draws it and as the rest of deadwax
 * does ("checkboxes, not switches"). Until 2.0.0-player.10 it was an iOS-style switch on the
 * now-playing screen, beside the album's name. James: "gapless should be a switch in the global
 * settings" - one setting for the player, not a control on a song.
 *
 * THE TAP IS THE GESTURE. Turning it on has the engine make and unlock its second audio element,
 * and iOS unlocks audio per element, from a tap: `setGapless` is called straight from the click,
 * in the same turn, exactly as the switch called it. Nothing may be awaited before it, and it is
 * a click, not a change event. ui/test/app-rules.sim.cjs allows this file, and no other screen, to
 * reach it; ui/test/settings.sim.cjs holds the call to the tap.
 *
 * Kept on this device (usePlayer's `deadwax-player-gapless`), off until turned on. It takes effect
 * at once: off, the song playing carries on alone and anything got ready is let go of.
 *
 * A leaf: it takes the player's two members as props, never a context, so the sim renders it alone.
 */
export function GaplessChoice({ player }: { player: Pick<Player, 'gapless' | 'setGapless'> }) {
  return (
    <div class="app-group">
      <button
        type="button"
        role="checkbox"
        class="app-check-row"
        aria-checked={player.gapless}
        aria-describedby="app-gapless-note"
        //? a click, in the tap: this is what unlocks the second player on iOS
        onClick={() => player.setGapless(!player.gapless)}
      >
        <span class="app-check-label">Gapless</span>
        <span class={`app-checkbox${player.gapless ? ' is-on' : ''}`} aria-hidden="true">
          <CheckIcon class="app-checkbox-tick" />
        </span>
      </button>
    </div>
  )
}
