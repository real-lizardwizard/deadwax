import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { resetPassword, type Person } from '../api/people'
import { PASSWORD_MAX, httpNote, passwordProblem, resetWords } from '../lib/people'
import { refusalOf } from './usePeople'

/**
 * Reset someone's password (2.0.0-player.61), inline under their row: New password, Again, Show - the same rules
 * as a new account's. Done: they are signed out of deadwax everywhere at once, and the words say so. A `locked`
 * refusal brings the unlock form back.
 *
 * A leaf: props, and its one request.
 */
export function ResetPassword({ person, onDone, onCancel, onLocked }: {
  person: Person
  onDone: (words: string) => void
  onCancel: () => void
  onLocked: () => void
}) {
  const [password, setPassword] = useState('')
  const [again, setAgain] = useState('')
  const [show, setShow] = useState(false)
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const field = useRef<HTMLInputElement>(null)
  const sending = useRef(false)

  useLayoutEffect(() => {
    field.current?.focus({ preventScroll: true })
  }, [])

  const wrong = password && again ? passwordProblem(password, again, person.user) : null
  const ready = !passwordProblem(password, again, person.user)
  const reset = () => {
    if (!ready || sending.current) return
    sending.current = true
    setBusy(true)
    setProblem(null)
    resetPassword(person.id, { user: person.user, password, password_again: again }).then(
      (answer) => {
        sending.current = false
        setBusy(false)
        setPassword('')
        setAgain('')
        onDone(resetWords(answer.reset, answer.signed_out))
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

  const note = httpNote(location.protocol)
  const kind = show ? 'text' : 'password'
  return (
    <form
      class="app-people-inline"
      aria-label={`Reset ${person.user}'s password`}
      onSubmit={(event) => {
        event.preventDefault()
        reset()
      }}
      onKeyDown={(event) => {
        if (event.key !== 'Escape') return
        event.preventDefault()
        onCancel()
      }}
    >
      <label class="app-people-field">
        <span class="app-people-label">New password</span>
        <input ref={field} class="app-people-input" type={kind} name="reset-password" value={password} maxLength={PASSWORD_MAX + 8}
          autoComplete="new-password" autoCapitalize="none" autoCorrect="off" spellcheck={false}
          onInput={(event) => setPassword((event.currentTarget as HTMLInputElement).value)} />
      </label>
      <label class="app-people-field">
        <span class="app-people-label">Again</span>
        <input class="app-people-input" type={kind} name="reset-password-again" value={again} maxLength={PASSWORD_MAX + 8}
          autoComplete="new-password" autoCapitalize="none" autoCorrect="off" spellcheck={false}
          onInput={(event) => setAgain((event.currentTarget as HTMLInputElement).value)} />
      </label>
      <label class="app-people-check">
        <input type="checkbox" class="app-people-checkbox" checked={show} onChange={(event) => setShow((event.currentTarget as HTMLInputElement).checked)} />
        <span>Show</span>
      </label>
      <p class="app-footnote app-people-typing" aria-live="polite">{wrong ?? ''}</p>
      <div class="app-people-buttons">
        <button type="submit" class="app-button is-primary" aria-disabled={!ready || busy}>{busy ? 'Resetting…' : 'Reset password'}</button>
        <button type="button" class="app-button" onClick={onCancel}>Cancel</button>
      </div>
      <div aria-live="assertive" aria-atomic="true">
        {problem && <p class="app-people-problem" role="alert">{problem}</p>}
      </div>
      {note && <p class="app-footnote app-people-http">{note}</p>}
    </form>
  )
}
