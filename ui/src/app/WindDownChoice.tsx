import { CheckIcon } from '../player/icons'

/**
 * "Pause winds the record down" in You > Playback (2.0.0-player.14): a checkbox, on by default, beside
 * "Now Playing opens as". James agreed the turntable's pause should slow its sound to a stop with the
 * record over about a second, as a real deck's does - with a way to turn that off. It applies to the
 * turntable only: the cover's pause, the lock screen's and a song ending are always instant.
 *
 * Kept on this device (deadwax-player-wind-down, readPlayerWindDown in state/persisted), App's state,
 * handed here and to Now Playing. Changing it starts nothing - the turntable's deck reads it at the
 * next pause - so this is no gesture and names no playback action.
 *
 * A leaf: the setting and the way to change it come as props, so the sim renders it alone.
 */
export function WindDownChoice({ on, onChange }: { on: boolean; onChange: (on: boolean) => void }) {
  return (
    <div class="app-group">
      <button
        type="button"
        role="checkbox"
        class="app-check-row"
        aria-checked={on}
        aria-describedby="app-wind-down-note"
        onClick={() => onChange(!on)}
      >
        <span class="app-check-label">Pause winds the record down</span>
        <span class={`app-checkbox${on ? ' is-on' : ''}`} aria-hidden="true">
          <CheckIcon class="app-checkbox-tick" />
        </span>
      </button>
    </div>
  )
}
