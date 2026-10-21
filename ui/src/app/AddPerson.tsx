import { useRef, useState } from 'preact/hooks'

import { createPerson } from '../api/people'
import { DISPLAY_MAX, NAME_MAX, PASSWORD_MAX, cleanName, formProblem, formReady, httpNote, madeWords } from '../lib/people'
import { refusalOf } from './usePeople'

/**
 * Add a person (2.0.0-player.61): a new, ORDINARY Navidrome account - User name, Display name (optional), Password
 * twice, Show passwords - made as you. The rules are checked as they are typed (lib/people.ts, src/people.py's
 * mirror) and again by the server, which decides. Made: what to tell them, and the fields cleared; refused: the
 * words, and the fields kept - but a `locked` refusal brings the unlock form back, with the passwords cleared.
 * Never the password shown back.
 *
 * A leaf: props, and its one request.
 */
export function AddPerson({ onMade, onLocked }: { onMade: () => void; onLocked: () => void }) {
  const [form, setForm] = useState({ user: '', name: '', password: '', again: '' })
  const [show, setShow] = useState(false)
  const [busy, setBusy] = useState(false)
  const [said, setSaid] = useState<{ words: string; warning: string | null; refused: boolean } | null>(null)
  const sending = useRef(false)
  const typing = formProblem(form)
  const ready = formReady(form)

  const set = (key: keyof typeof form) => (event: Event) => {
    const value = (event.currentTarget as HTMLInputElement).value
    setForm((was) => ({ ...was, [key]: value }))
  }

  const make = () => {
    if (!ready || sending.current) return
    sending.current = true
    setBusy(true)
    setSaid(null)
    const user = cleanName(form.user)
    createPerson({ user, name: form.name.trim(), password: form.password, password_again: form.again }).then(
      (answer) => {
        sending.current = false
        setBusy(false)
        setForm({ user: '', name: '', password: '', again: '' })
        setSaid({ words: madeWords(answer.made.user, location.origin), warning: answer.warning, refused: false })
        onMade()
      },
      (reason: unknown) => {
        sending.current = false
        setBusy(false)
        const refusal = refusalOf(reason)
        setSaid({ words: refusal.words, warning: null, refused: true })
        if (refusal.locked) {
          setForm((was) => ({ ...was, password: '', again: '' }))
          onLocked()
        }
      },
    )
  }

  const note = httpNote(location.protocol)
  const kind = show ? 'text' : 'password'
  return (
    <form
      class="app-card app-people-add"
      aria-labelledby="app-people-add-title"
      onSubmit={(event) => {
        event.preventDefault()
        make()
      }}
    >
      <h2 id="app-people-add-title" class="app-people-title">Add a person</h2>
      <p class="app-people-line">A new Navidrome account, made ordinary - making someone an admin is its own step.</p>
      <label class="app-people-field">
        <span class="app-people-label">User name</span>
        <input class="app-people-input" type="text" name="new-user" value={form.user} maxLength={NAME_MAX + 8} autoComplete="off"
          autoCapitalize="none" autoCorrect="off" spellcheck={false} onInput={set('user')} />
      </label>
      <label class="app-people-field">
        <span class="app-people-label">Display name (optional)</span>
        <input class="app-people-input" type="text" name="new-name" value={form.name} maxLength={DISPLAY_MAX + 8} autoComplete="off"
          autoCorrect="off" spellcheck={false} onInput={set('name')} />
      </label>
      <label class="app-people-field">
        <span class="app-people-label">Password</span>
        <input class="app-people-input" type={kind} name="new-password" value={form.password} maxLength={PASSWORD_MAX + 8}
          autoComplete="new-password" autoCapitalize="none" autoCorrect="off" spellcheck={false} onInput={set('password')} />
      </label>
      <label class="app-people-field">
        <span class="app-people-label">Password again</span>
        <input class="app-people-input" type={kind} name="new-password-again" value={form.again} maxLength={PASSWORD_MAX + 8}
          autoComplete="new-password" autoCapitalize="none" autoCorrect="off" spellcheck={false} onInput={set('again')} />
      </label>
      <label class="app-people-check">
        <input type="checkbox" class="app-people-checkbox" checked={show} onChange={(event) => setShow((event.currentTarget as HTMLInputElement).checked)} />
        <span>Show passwords</span>
      </label>
      <p class="app-footnote app-people-typing" aria-live="polite">{typing ?? ''}</p>
      <div class="app-people-buttons">
        <button type="submit" class="app-button is-primary app-people-make" aria-disabled={!ready || busy}>
          {busy ? 'Making…' : 'Make account'}
        </button>
      </div>
      <div aria-live="assertive" aria-atomic="true">
        {said && <p class={said.refused ? 'app-people-problem' : 'app-people-done'} role={said.refused ? 'alert' : 'status'}>{said.words}</p>}
        {said?.warning && <p class="app-people-warning">{said.warning}</p>}
      </div>
      {note && <p class="app-footnote app-people-http">{note}</p>}
    </form>
  )
}
