import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'

import { removePerson, type Person } from '../api/people'
import { removeLines, removeReady } from '../lib/people'
import { refusalOf } from './usePeople'

/** What can take focus inside the dialog, in order. */
const FOCUSABLE = 'button:not([disabled]), input:not([disabled]), [href], [tabindex]:not([tabindex="-1"])'

/**
 * Remove a person (2.0.0-player.61) - a real dialog, as DeleteAlbumDialog's: what goes in Navidrome for good, what
 * goes in deadwax, what stays (from the server's numbers), that there is no undo - and their user name typed to
 * remove them: **Remove <name>** is live only when the field is exactly the name (the server checks it too).
 * Escape cancels; Enter does NOT confirm (the one action here with no undo takes a deliberate tap); focus stays
 * inside while it is open; a sheet from the foot of a phone, clear of the home bar. No confirm() - it would hold
 * the page, and the page plays the music.
 *
 * A leaf: props, and its one request.
 */
export function RemovePerson({ person, onRemoved, onCancel, onLocked }: {
  person: Person
  onRemoved: (words: string) => void
  onCancel: () => void
  onLocked: () => void
}) {
  const [typed, setTyped] = useState('')
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const box = useRef<HTMLDivElement>(null)
  const field = useRef<HTMLInputElement>(null)
  const sending = useRef(false)
  const lines = removeLines(person)
  const ready = removeReady(typed, person.user)

  useLayoutEffect(() => {
    field.current?.focus({ preventScroll: true })
  }, [])

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault()
        if (!sending.current) onCancel()
        return
      }
      if (event.key !== 'Tab' || !box.current) return
      //? focus stays inside: Tab from the last goes to the first, Shift-Tab from the first to the last
      const inside = [...box.current.querySelectorAll<HTMLElement>(FOCUSABLE)]
      if (!inside.length) return
      const first = inside[0]!
      const last = inside[inside.length - 1]!
      const at = document.activeElement
      if (event.shiftKey && (at === first || !box.current.contains(at))) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && (at === last || !box.current.contains(at))) {
        event.preventDefault()
        first.focus()
      }
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [onCancel])

  const remove = () => {
    if (!ready || sending.current) return
    sending.current = true
    setBusy(true)
    setProblem(null)
    removePerson(person.id, { user: person.user, confirm: typed }).then(
      () => {
        sending.current = false
        setBusy(false)
        onRemoved(`Removed ${person.user} from Navidrome and deadwax.`)
      },
      (reason: unknown) => {
        sending.current = false
        setBusy(false)
        const refusal = refusalOf(reason)
        setProblem(refusal.words)
        if (refusal.locked) onLocked()
      },
    )
  }

  return (
    <div class="app-people-dialog-layer" onClick={(event) => {
      if (event.target === event.currentTarget && !sending.current) onCancel()
    }}>
      <div ref={box} class="app-people-dialog" role="dialog" aria-modal="true" aria-labelledby="app-people-remove-title" aria-describedby="app-people-remove-undo">
        <h2 id="app-people-remove-title" class="app-people-title is-danger">Remove {person.user}?</h2>
        <p class="app-people-line">{lines.navidrome}</p>
        <p class="app-people-line">{lines.deadwax}</p>
        <p class="app-people-line">{lines.stays}</p>
        <p id="app-people-remove-undo" class="app-people-line is-danger">{lines.undo}</p>
        <label class="app-people-field">
          <span class="app-people-label">Type their user name to remove them</span>
          <input
            ref={field}
            class="app-people-input"
            type="text"
            name="remove-confirm"
            value={typed}
            autoComplete="off"
            autoCapitalize="none"
            autoCorrect="off"
            spellcheck={false}
            onInput={(event) => setTyped((event.currentTarget as HTMLInputElement).value)}
            onKeyDown={(event) => {
              //? Enter never confirms
              if (event.key === 'Enter') event.preventDefault()
            }}
          />
        </label>
        <div class="app-people-buttons">
          <button type="button" class="app-button" disabled={busy} onClick={onCancel}>Cancel</button>
          <button type="button" class="app-button is-danger app-people-remove" disabled={!ready || busy} onClick={remove}>
            {busy ? 'Removing…' : `Remove ${person.user}`}
          </button>
        </div>
        <div aria-live="assertive" aria-atomic="true">
          {problem && <p class="app-people-problem" role="alert">{problem}</p>}
        </div>
      </div>
    </div>
  )
}
