import { useEffect, useRef } from 'preact/hooks'

import type { MaxRate } from '../lib/streamWrap'
import { CheckIcon } from './icons'
import type { Player } from './usePlayer'

/**
 * The "Maximum quality" choices, in the words the sheet shows. Only what the code does: a FLAC at
 * 88.2, 96, 176.4, 192, 352.8 or 384 kHz is resampled (resamples() in lib/streamWrap - a 128 kHz
 * FLAC, 20 or 32 bits, ALAC or WAV is sent as it is under both), lowered by src/resample.py's
 * HEADROOM_DB, and no song plays without a gap unless the Gapless switch is on - it is off until
 * turned on, and a stream never goes to AirPlay. ui/test/settings.sim.cjs holds the words to this.
 */
export const QUALITIES: { rate: MaxRate; label: string; note: string }[] = [
  {
    rate: '48000',
    label: 'Up to 48 kHz',
    note:
      'FLAC songs at 88.2 to 384 kHz are resampled by deadwax to 48 kHz, or 44.1 kHz, and sent as lossless ' +
      '24-bit FLAC, so with the Gapless switch on they play without a gap. Nothing below 20 kHz changes, except ' +
      'that they are 3 dB quieter, so nothing can clip.',
  },
  {
    rate: 'original',
    label: 'Original',
    note:
      'Songs above 48 kHz are sent as they are. With the Gapless switch on, FLAC songs play without a gap too, ' +
      'but an iPhone can only hold a few seconds of them ahead, so a weak connection can make them stall. The ' +
      'iPhone converts them to 44.1 or 48 kHz itself, unless a USB DAC takes them at their own rate.',
  },
]

/** Where the tab key may stop inside the sheet: its buttons, less a radio that isn't the chosen one. */
function stopsIn(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>('button:not([tabindex="-1"])')]
}

/**
 * The player's settings, as a sheet from the bottom - iOS's shape, over the library that opened it.
 * One setting for now, "Maximum quality" (usePlayer's maxRate), a choice of two as a radio group:
 * a tap picks, and to the keyboard the arrows move the choice and Tab stays inside the sheet.
 *
 * It closes on Done, on a tap outside it (the dimmed page, whose click only comes from a press that
 * began there too - a press inside released outside is not a tap outside), and on Escape. Focus goes
 * into the sheet as it opens, and back to what had it then as it closes - the Library's settings
 * button, which takes focus itself as it is tapped, since WebKit doesn't focus a tapped button (see
 * Library). Kept mounted, and hidden with `inert`, so it can slide in and out as the now-playing one does.
 */
export function Settings({ player, open, onClose }: { player: Player; open: boolean; onClose: () => void }) {
  const sheet = useRef<HTMLDivElement>(null)
  const opener = useRef<HTMLElement | null>(null)
  //? read through a ref: a new onClose each render must not re-subscribe the Escape listener
  const close = useRef(onClose)
  close.current = onClose

  //? The page behind must not scroll under a finger on the sheet. A class of its own, not
  //? pl-sheet-open: the now-playing sheet's effect owns that one and would switch it off.
  useEffect(() => {
    document.documentElement.classList.toggle('pl-settings-open', open)
  }, [open])

  useEffect(() => {
    if (open) {
      opener.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
      sheet.current?.focus()
      return
    }
    opener.current?.focus()
    opener.current = null
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close.current()
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [open])

  //? Tab and Shift-Tab go round the sheet's own stops, never out to the page under it
  const onSheetKeyDown = (event: KeyboardEvent) => {
    const root = sheet.current
    if (event.key !== 'Tab' || !root) return
    const stops = stopsIn(root)
    const first = stops[0]
    const last = stops[stops.length - 1]
    const active = document.activeElement
    if (event.shiftKey && (active === first || active === root)) {
      event.preventDefault()
      last?.focus()
    } else if (!event.shiftKey && active === last) {
      event.preventDefault()
      first?.focus()
    }
  }

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
    <div class={`pl-settings${open ? ' is-open' : ''}`} aria-hidden={!open} inert={!open}>
      <div class="pl-settings-backdrop" onClick={onClose} />
      <div
        ref={sheet}
        class="pl-settings-sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby="pl-settings-title"
        tabIndex={-1}
        onKeyDown={onSheetKeyDown}
      >
        <header class="pl-settings-header">
          <h2 id="pl-settings-title" class="pl-settings-title">Settings</h2>
          <button type="button" class="pl-settings-done" onClick={onClose}>
            Done
          </button>
        </header>

        <section class="pl-settings-section">
          <h3 id="pl-settings-quality" class="pl-settings-heading">Maximum quality</h3>
          <div class="pl-settings-group" role="radiogroup" aria-labelledby="pl-settings-quality" onKeyDown={onGroupKeyDown}>
            {QUALITIES.map((quality) => {
              const chosen = quality.rate === player.maxRate
              return (
                <button
                  key={quality.rate}
                  type="button"
                  role="radio"
                  class="pl-settings-row"
                  data-rate={quality.rate}
                  aria-checked={chosen}
                  aria-labelledby={`pl-settings-${quality.rate}-label`}
                  aria-describedby={`pl-settings-${quality.rate}-note`}
                  //? only the chosen one is a tab stop; the arrows reach the other
                  tabIndex={chosen ? 0 : -1}
                  onClick={() => player.setMaxRate(quality.rate)}
                >
                  <span class="pl-settings-text">
                    <span id={`pl-settings-${quality.rate}-label`} class="pl-settings-label">
                      {quality.label}
                    </span>
                    <span id={`pl-settings-${quality.rate}-note`} class="pl-settings-note">
                      {quality.note}
                    </span>
                  </span>
                  <CheckIcon class={`pl-settings-check${chosen ? '' : ' is-off'}`} />
                </button>
              )
            })}
          </div>
        </section>
      </div>
    </div>
  )
}
