import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { unlockPeople } from '../api/people'
import { UNLOCK_TITLE, httpNote, unlockLine } from '../lib/people'
import { refusalOf } from './usePeople'

/**
 * Unlock People (2.0.0-player.61): the signed-in person's own Navidrome password, put to deadwax once - checked
 * against the login their session keeps before Navidrome is asked anything, and never kept. A hidden user name
 * field holds the session's name, so a password manager fills the right entry. The password is dropped as soon
 * as the answer is in, whatever it was. Under it, on plain http, the note that it crosses the network readable.
 *
 * A leaf: props, and its one request.
 */
export function UnlockPeople({ user, onUnlocked }: { user: string; onUnlocked: () => void }) {
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const field = useRef<HTMLInputElement>(null)
  const sending = useRef(false)

  useLayoutEffect(() => {
    field.current?.focus({ preventScroll: true })
  }, [])

  const unlock = () => {
    //? read from the field: a password manager's fill needn't fire input
    const typed = field.current?.value ?? password
    if (!typed || sending.current) return
    sending.current = true
    setBusy(true)
    setProblem(null)
    unlockPeople(typed).then(
      () => {
        sending.current = false
        setBusy(false)
        setPassword('')
        if (field.current) field.current.value = ''
        onUnlocked()
      },
      (reason: unknown) => {
        sending.current = false
        setBusy(false)
        setPassword('')
        if (field.current) field.current.value = ''
        setProblem(refusalOf(reason).words)
        field.current?.focus({ preventScroll: true })
      },
    )
  }

  const note = httpNote(location.protocol)
  return (
    <form
      class="app-card app-people-unlock"
      aria-labelledby="app-people-unlock-title"
      onSubmit={(event) => {
        event.preventDefault()
        unlock()
      }}
    >
      <h2 id="app-people-unlock-title" class="app-people-title">{UNLOCK_TITLE}</h2>
      <p class="app-people-line">{unlockLine(user)}</p>
      <input class="app-people-hidden" type="text" name="username" autoComplete="username" value={user} readOnly tabIndex={-1} aria-hidden="true" />
      <label class="app-people-field">
        <span class="app-people-label">Your Navidrome password</span>
        <input
          ref={field}
          class="app-people-input"
          type="password"
          name="password"
          autoComplete="current-password"
          autoCapitalize="none"
          autoCorrect="off"
          spellcheck={false}
          value={password}
          onInput={(event) => setPassword((event.currentTarget as HTMLInputElement).value)}
        />
      </label>
      <div class="app-people-buttons">
        <button type="submit" class="app-button is-primary app-people-unlock-button" aria-disabled={busy || !password}>
          {busy ? 'Unlocking…' : 'Unlock'}
        </button>
      </div>
      <div aria-live="assertive" aria-atomic="true">
        {problem && <p class="app-people-problem" role="alert">{problem}</p>}
      </div>
      {note && <p class="app-footnote app-people-http">{note}</p>}
    </form>
  )
}
