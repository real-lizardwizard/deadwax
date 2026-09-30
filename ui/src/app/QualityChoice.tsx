import type { MaxRate } from '../lib/streamWrap'
import { CheckIcon } from '../player/icons'
import type { Player } from '../player/usePlayer'

/**
 * The "Maximum quality" choices, in the words You shows. Only what the code does: a FLAC at 88.2,
 * 96, 176.4, 192, 352.8 or 384 kHz is resampled (resamples() in lib/streamWrap - a 128 kHz FLAC, 20
 * or 32 bits, ALAC or WAV is sent as it is under both), lowered by src/resample.py's HEADROOM_DB,
 * and no song plays without a gap unless Gapless is on (the checkbox above this in You,
 * GaplessChoice.tsx) - it is off until turned on, and a stream never goes to AirPlay.
 * ui/test/settings.sim.cjs holds the words to this, and the name to that checkbox's own label.
 *
 * Moved here from the player's settings sheet (player/Settings.tsx, deleted in 2.0.0-player.9)
 * word for word: the words, the storage key (usePlayer's deadwax-player-max-rate, per device) and
 * the keyboard handling are all as they were - until 2.0.0-player.10, when Gapless stopped being a
 * switch and the two notes stopped calling it one ("with Gapless on").
 */
export const QUALITIES: { rate: MaxRate; label: string; note: string }[] = [
  {
    rate: '48000',
    label: 'Up to 48 kHz',
    note:
      'FLAC songs at 88.2 to 384 kHz are resampled by deadwax to 48 kHz, or 44.1 kHz, and sent as lossless ' +
      '24-bit FLAC, so with Gapless on they play without a gap. Nothing below 20 kHz changes, except ' +
      'that they are 3 dB quieter, so nothing can clip.',
  },
  {
    rate: 'original',
    label: 'Original',
    note:
      'Songs above 48 kHz are sent as they are. With Gapless on, FLAC songs play without a gap too, ' +
      'but an iPhone can only hold a few seconds of them ahead, so a weak connection can make them stall. The ' +
      'iPhone converts them to 44.1 or 48 kHz itself, unless a USB DAC takes them at their own rate.',
  },
]

/**
 * "Maximum quality" as a radio group in You > Playback: a tap picks; to the keyboard, the arrows
 * move the choice - and the focus with it - round the group, and only the chosen radio is a tab
 * stop. It applies from the next song started or got ready (usePlayer's setMaxRate), which is what
 * the note under it says.
 *
 * A leaf: it takes the player's two members as props, never a context, so the sim renders it alone.
 */
export function QualityChoice({ player }: { player: Pick<Player, 'maxRate' | 'setMaxRate'> }) {
  //? a radio group's keys: an arrow moves the choice - and the focus with it - round the group
  const onGroupKeyDown = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const at = QUALITIES.findIndex((quality) => quality.rate === player.maxRate)
    const next = QUALITIES[(at + step + QUALITIES.length) % QUALITIES.length]!
    player.setMaxRate(next.rate)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-rate="${next.rate}"]`)?.focus()
  }

  return (
    <div class="app-choice">
      <h3 id="app-quality-title" class="app-choice-title">Maximum quality</h3>
      <div class="app-group" role="radiogroup" aria-labelledby="app-quality-title" onKeyDown={onGroupKeyDown}>
        {QUALITIES.map((quality) => {
          const chosen = quality.rate === player.maxRate
          return (
            <button
              key={quality.rate}
              type="button"
              role="radio"
              class="app-radio"
              data-rate={quality.rate}
              aria-checked={chosen}
              aria-labelledby={`app-quality-${quality.rate}-label`}
              aria-describedby={`app-quality-${quality.rate}-note`}
              //? only the chosen one is a tab stop; the arrows reach the other
              tabIndex={chosen ? 0 : -1}
              onClick={() => player.setMaxRate(quality.rate)}
            >
              <span class="app-radio-text">
                <span id={`app-quality-${quality.rate}-label`} class="app-radio-label">
                  {quality.label}
                </span>
                <span id={`app-quality-${quality.rate}-note`} class="app-radio-note">
                  {quality.note}
                </span>
              </span>
              <CheckIcon class={`app-check${chosen ? '' : ' is-off'}`} />
            </button>
          )
        })}
      </div>
    </div>
  )
}
