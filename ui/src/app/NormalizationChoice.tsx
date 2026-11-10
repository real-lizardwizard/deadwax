import { useState } from 'preact/hooks'

import type { Normalization } from '../lib/loudness'
import { CheckIcon } from '../player/icons'
import { readPlayerNormalization, writePlayerNormalization } from '../state/persisted'

/**
 * The player's Normalization choices (2.0.0-player.62), in the words You shows. Only what the code does:
 * lib/loudness.ts levelFor() is the table - Automatic levels by album whatever was queued as an album (an
 * album page's Play or a row, an album's Play Next or Play Last, a Search song's tap, a request's ▶, an
 * artist's Play), song by song everything else; By song and By album whatever was queued; Off asks for no
 * level, so every address is what it always was and deadwax sends the file as it did (src/levels.py,
 * src/resample.py). ui/test/settings.sim.cjs holds the words to this.
 */
export const NORMALIZATIONS: { value: Normalization; label: string; note: string }[] = [
  {
    value: 'auto',
    label: 'Automatic',
    note:
      'An album you play keeps one level for the whole album, so its quiet songs stay quiet beside its loud ones. ' +
      'Anything else - a playlist, a shuffle, a song you add with Play Next - is levelled song by song.',
  },
  {
    value: 'song',
    label: 'By song',
    note: 'Every song brought to the same loudness, even the quiet and loud songs of one album.',
  },
  {
    value: 'album',
    label: 'By album',
    note: "Every song at its album's level, even when it plays on its own or in a playlist.",
  },
  {
    value: 'off',
    label: 'Off',
    note: 'No levelling: every song plays exactly as the file is, bit for bit, unless Maximum quality converts it.',
  },
]

/**
 * "Normalization" as a radio group in You > Playback, right after Maximum quality - exactly like
 * QualityChoice.tsx: a tap picks; to the keyboard, the arrows move the choice - and the focus with it - round
 * the group, and only the chosen radio is a tab stop. Its state is its own, kept on this device
 * (state/persisted's readPlayerNormalization): it is not the player's - nothing in the engine reads it. The
 * songs about to be queued are read at the tap (player/levelling.ts), so a change applies from the next thing
 * played, which is what the note under it says.
 *
 * A leaf: props none, so the sim renders it alone.
 */
export function NormalizationChoice() {
  const [chosen, setChosen] = useState<Normalization>(readPlayerNormalization)
  const choose = (value: Normalization) => {
    writePlayerNormalization(value)
    setChosen(value)
  }

  //? a radio group's keys: an arrow moves the choice - and the focus with it - round the group
  const onGroupKeyDown = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const at = NORMALIZATIONS.findIndex((each) => each.value === chosen)
    const next = NORMALIZATIONS[(at + step + NORMALIZATIONS.length) % NORMALIZATIONS.length]!
    choose(next.value)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-level="${next.value}"]`)?.focus()
  }

  return (
    <div class="app-choice app-choice-follows">
      <h3 id="app-normalization-title" class="app-choice-title">Normalization</h3>
      <div class="app-group" role="radiogroup" aria-labelledby="app-normalization-title" onKeyDown={onGroupKeyDown}>
        {NORMALIZATIONS.map((each) => {
          const on = each.value === chosen
          return (
            <button
              key={each.value}
              type="button"
              role="radio"
              class="app-radio"
              data-level={each.value}
              aria-checked={on}
              aria-labelledby={`app-normalization-${each.value}-label`}
              aria-describedby={`app-normalization-${each.value}-note`}
              //? only the chosen one is a tab stop; the arrows reach the others
              tabIndex={on ? 0 : -1}
              onClick={() => choose(each.value)}
            >
              <span class="app-radio-text">
                <span id={`app-normalization-${each.value}-label`} class="app-radio-label">
                  {each.label}
                </span>
                <span id={`app-normalization-${each.value}-note`} class="app-radio-note">
                  {each.note}
                </span>
              </span>
              <CheckIcon class={`app-check${on ? '' : ' is-off'}`} />
            </button>
          )
        })}
      </div>
    </div>
  )
}
