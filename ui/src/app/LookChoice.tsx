import type { Look } from '../lib/turntable'
import { CheckIcon } from '../player/icons'

/** The two looks, in the words You shows. */
export const LOOKS: { look: Look; label: string }[] = [
  { look: 'cover', label: 'Cover' },
  { look: 'turntable', label: 'Turntable' },
]

/**
 * "Now Playing opens as" in You > Playback (2.0.0-player.11): the cover, as Now Playing always was,
 * or the turntable (player/Turntable.tsx). A radio group as "Maximum quality" is: a tap picks; to
 * the keyboard, the arrows move the choice - and the focus with it - round the group, and only the
 * chosen radio is a tab stop. Kept on this device (deadwax-player-opens-as), the cover until
 * changed. It is the look Now Playing OPENS in: the button at its top right switches for as long
 * as it stays open and leaves this alone.
 *
 * A leaf: the setting and the way to change it come as props (App keeps it), so the sim renders it
 * alone. Choosing a look starts nothing, so this is no gesture and names no playback action.
 */
export function LookChoice({ look, onChange }: { look: Look; onChange: (look: Look) => void }) {
  //? a radio group's keys: an arrow moves the choice - and the focus with it - round the group
  const onGroupKeyDown = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const at = LOOKS.findIndex((choice) => choice.look === look)
    const next = LOOKS[(at + step + LOOKS.length) % LOOKS.length]!
    onChange(next.look)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-look="${next.look}"]`)?.focus()
  }

  return (
    <div class="app-choice">
      <h3 id="app-look-title" class="app-choice-title">Now Playing opens as</h3>
      {/* described by the note under it in You (app-look-note): that the button on Now Playing
          switches the look only until it closes - why the two can disagree */}
      <div
        class="app-group"
        role="radiogroup"
        aria-labelledby="app-look-title"
        aria-describedby="app-look-note"
        onKeyDown={onGroupKeyDown}
      >
        {LOOKS.map((choice) => {
          const chosen = choice.look === look
          return (
            <button
              key={choice.look}
              type="button"
              role="radio"
              class="app-radio"
              data-look={choice.look}
              aria-checked={chosen}
              //? only the chosen one is a tab stop; the arrows reach the other
              tabIndex={chosen ? 0 : -1}
              onClick={() => onChange(choice.look)}
            >
              <span class="app-radio-text">
                <span class="app-radio-label">{choice.label}</span>
              </span>
              <CheckIcon class={`app-check${chosen ? '' : ' is-off'}`} />
            </button>
          )
        })}
      </div>
    </div>
  )
}
