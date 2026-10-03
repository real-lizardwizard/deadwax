import { GET_MODES, QUALITY_FLOORS, type GetSettings } from '../lib/getSettings'
import { CheckIcon } from '../player/icons'

/**
 * You > Getting albums (2.0.0-player.15): "When I tap Get" and "Quality floor", each a radio group
 * as "Now Playing opens as" and "Maximum quality" are - a tap picks; to the keyboard the arrows move
 * the choice and the focus with it, and only the chosen radio is a tab stop. The board draws them as
 * rows leading to a list; in the app they are the list, one tap rather than two.
 *
 * Kept per user on the server (app/useGetSettings.ts), not on this device: getting an album is
 * something a person does from any device. Until deadwax has first answered, nothing is shown as
 * chosen and nothing can be chosen - showing the defaults as chosen would claim what nobody knows
 * yet. After that a choice is shown at once, whatever else is on its way: the store saves choices
 * in turn and lays any still being saved over the server's word, so no answer overwrites one.
 *
 * A leaf: the settings and the way to change them come as props, so the sim renders it alone.
 * Choosing starts nothing, so it is no gesture and names no playback action.
 */
export function GettingChoices({
  settings,
  onChoose,
}: {
  /** null until deadwax has answered */
  settings: GetSettings | null
  onChoose: (values: Partial<GetSettings>) => void
}) {
  return (
    <>
      <RadioGroup
        id="app-get-mode"
        title="When I tap Get"
        note="app-get-note"
        choices={GET_MODES}
        chosen={settings?.get_mode ?? null}
        onPick={(value) => onChoose({ get_mode: value })}
      />
      <RadioGroup
        id="app-quality-floor"
        title="Quality floor"
        note="app-get-note"
        choices={QUALITY_FLOORS}
        chosen={settings?.quality_floor ?? null}
        onPick={(value) => onChoose({ quality_floor: value })}
      />
    </>
  )
}

function RadioGroup<T extends string>({
  id,
  title,
  note,
  choices,
  chosen,
  onPick,
}: {
  id: string
  title: string
  /** the note under the section, which says what both mean */
  note: string
  choices: readonly { value: T; label: string }[]
  chosen: T | null
  onPick: (value: T) => void
}) {
  //? a radio group's keys: an arrow moves the choice - and the focus with it - round the group
  const onGroupKeyDown = (event: KeyboardEvent) => {
    if (chosen === null) return
    const step = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const at = choices.findIndex((choice) => choice.value === chosen)
    const after = choices[(at + step + choices.length) % choices.length]!
    onPick(after.value)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-value="${after.value}"]`)?.focus()
  }

  return (
    <div class="app-choice">
      <h3 id={`${id}-title`} class="app-choice-title">{title}</h3>
      <div
        class="app-group"
        role="radiogroup"
        aria-labelledby={`${id}-title`}
        aria-describedby={note}
        aria-busy={chosen === null}
        onKeyDown={onGroupKeyDown}
      >
        {choices.map((choice, index) => {
          const on = choice.value === chosen
          return (
            <button
              key={choice.value}
              type="button"
              role="radio"
              class="app-radio"
              data-value={choice.value}
              aria-checked={on}
              aria-disabled={chosen === null}
              //? only the chosen one is a tab stop - or, before deadwax has answered, the first
              tabIndex={on || (chosen === null && index === 0) ? 0 : -1}
              onClick={() => {
                if (chosen !== null) onPick(choice.value)
              }}
            >
              <span class="app-radio-text">
                <span class="app-radio-label">{choice.label}</span>
              </span>
              <CheckIcon class={`app-check${on ? '' : ' is-off'}`} />
            </button>
          )
        })}
      </div>
    </div>
  )
}
