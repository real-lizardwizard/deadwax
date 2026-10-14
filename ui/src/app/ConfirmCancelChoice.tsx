import { CheckIcon } from '../player/icons'

/**
 * "Confirm before cancelling" in You > Getting albums (2.0.0-player.41): a checkbox, on by default, as
 * "Pause winds the record down" is. On, the ✕ on a download in Requests asks first, in the card ("Keep
 * it" / "Cancel download"); off, it cancels at once. The main page's own setting of that name (its
 * Settings -> Downloads) was what the app read until now - in this browser's storage, which a
 * home-screen app never had - so it is carried over once, the first time this device reads it.
 *
 * Kept on this device (deadwax-player-confirm-cancel, readConfirmCancel in state/persisted), like the
 * main page's. Requests reads it at the tap. Changing it starts nothing, so it is no gesture and names
 * no playback action.
 *
 * A leaf: the setting and the way to change it come as props, so the sim renders it alone.
 */
export function ConfirmCancelChoice({ on, onChange }: { on: boolean; onChange: (on: boolean) => void }) {
  return (
    <div class="app-group">
      <button
        type="button"
        role="checkbox"
        class="app-check-row"
        aria-checked={on}
        aria-describedby="app-confirm-cancel-note"
        onClick={() => onChange(!on)}
      >
        <span class="app-check-label">Confirm before cancelling</span>
        <span class={`app-checkbox${on ? ' is-on' : ''}`} aria-hidden="true">
          <CheckIcon class="app-checkbox-tick" />
        </span>
      </button>
    </div>
  )
}
