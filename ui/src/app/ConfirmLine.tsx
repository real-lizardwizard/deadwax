import { useLayoutEffect, useRef } from 'preact/hooks'

/**
 * A question asked in place (2.0.0-player.58) - a playlist's Delete, and Edit's Cancel with changes: the words,
 * the button that goes ahead, the one that keeps things as they are - which takes focus as it shows - and, refused,
 * why. `danger` draws the first red (theme.css's --dw-danger-*, the Edit panel's "delete permanently" look).
 * Requests' "Keep it / Cancel download" is the app's precedent; confirm() is barred in app/ and player/.
 *
 * A leaf: props only.
 */
export function ConfirmLine({
  words,
  confirm,
  keep,
  busy = false,
  busyLabel,
  problem = null,
  danger = false,
  onConfirm,
  onKeep,
}: {
  words: string
  confirm: string
  keep: string
  busy?: boolean
  busyLabel?: string
  problem?: string | null
  danger?: boolean
  onConfirm: () => void
  onKeep: () => void
}) {
  const keeping = useRef<HTMLButtonElement>(null)
  useLayoutEffect(() => {
    keeping.current?.focus({ preventScroll: true })
  }, [])

  return (
    <div class="app-confirm-line" role="group" aria-label={words}>
      <p class="app-confirm-words">{words}</p>
      <div class="app-confirm-buttons">
        <button
          type="button"
          class={`app-button app-confirm-yes${danger ? ' is-danger' : ''}`}
          aria-disabled={busy}
          onClick={() => {
            if (!busy) onConfirm()
          }}
        >
          {busy && busyLabel ? busyLabel : confirm}
        </button>
        <button ref={keeping} type="button" class="app-button app-confirm-keep" onClick={onKeep}>
          {keep}
        </button>
      </div>
      {problem && (
        <p class="app-store-line is-refused" role="alert">
          {problem}
        </p>
      )}
    </div>
  )
}
