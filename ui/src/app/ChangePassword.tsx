import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { changePassword } from '../api/me'
import { ApiError } from '../api/http'
import {
  APPS_LINE,
  CHANGE_TITLE,
  EMPTY_FORM,
  PASSWORD_MAX,
  changeLine,
  doneWords,
  formProblem,
  formReady,
  httpNote,
  type OwnPasswordForm,
} from '../lib/ownPassword'
import { sayError } from './sayError'

/**
 * You > About's Change password (2.0.2, src/routes/own_password.py) - drawn by You only with logins on and a
 * Navidrome sign-in (lib/ownPassword.ts changeOffered), on a phone as on a desktop. A row; tapped, the form opens
 * under it: Current password, New password, Again, Show - People's rules for a new password, and not the one you
 * have. Save asks deadwax, which changes it in Navidrome as you. Done: this device stays signed in, every other
 * device of yours signs in again - the words say how many - and the line under them says Amperfy and other apps
 * need the new password too. Refused: the server's words, the fields kept to correct (a wrong current password
 * emptied and focused). Every field is dropped once a change is done; Escape and Cancel close the form, emptied.
 * A hidden user name field holds the session's name, so a password manager fills and saves the right entry. Under
 * it, on plain http, the note that a password typed here crosses the network readable.
 *
 * A leaf: props, and its one request. Nothing in it plays.
 */
export function ChangePassword({ user }: { user: string }) {
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<OwnPasswordForm>(EMPTY_FORM)
  const [show, setShow] = useState(false)
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const [done, setDone] = useState<{ words: string; warning: string | null } | null>(null)
  const row = useRef<HTMLButtonElement>(null)
  const currentField = useRef<HTMLInputElement>(null)
  const newField = useRef<HTMLInputElement>(null)
  const againField = useRef<HTMLInputElement>(null)
  const sending = useRef(false)

  useLayoutEffect(() => {
    if (open) currentField.current?.focus({ preventScroll: true })
  }, [open])

  const close = () => {
    setOpen(false)
    setForm(EMPTY_FORM)
    setShow(false)
    setProblem(null)
    row.current?.focus({ preventScroll: true })
  }

  const toggle = () => {
    if (open) {
      close()
      return
    }
    setDone(null)
    setProblem(null)
    setOpen(true)
  }

  const save = () => {
    //? read from the fields: a password manager's fill needn't fire input
    const typed: OwnPasswordForm = {
      current: currentField.current?.value ?? form.current,
      password: newField.current?.value ?? form.password,
      again: againField.current?.value ?? form.again,
    }
    if (!formReady(typed, user) || sending.current) return
    sending.current = true
    setBusy(true)
    setProblem(null)
    changePassword({ current: typed.current, password: typed.password, password_again: typed.again }).then(
      (answer) => {
        sending.current = false
        setBusy(false)
        setForm(EMPTY_FORM)
        setShow(false)
        setOpen(false)
        setDone({ words: doneWords(answer.signed_out), warning: answer.warning })
        row.current?.focus({ preventScroll: true })
      },
      (reason: unknown) => {
        sending.current = false
        setBusy(false)
        setForm(typed)
        //? (2.0.4) deadwax's own words where they're fit, a listener's otherwise (sayError)
        setProblem(sayError(reason))
        if (reason instanceof ApiError && reason.kind === 'not_your_password') {
          setForm({ ...typed, current: '' })
          currentField.current?.focus({ preventScroll: true })
        }
      },
    )
  }

  const typing = formProblem(form, user)
  const ready = formReady(form, user)
  const note = httpNote(location.protocol)
  const kind = show ? 'text' : 'password'
  const field = (key: keyof OwnPasswordForm) => (event: Event) => {
    const value = (event.currentTarget as HTMLInputElement).value
    setForm((now) => ({ ...now, [key]: value }))
  }
  return (
    <>
      <div class="app-group app-own-password">
        <button
          ref={row}
          type="button"
          class="app-row app-link-row app-own-password-row"
          aria-expanded={open}
          aria-controls="app-own-password-form"
          onClick={toggle}
        >
          <span class="app-row-label">{CHANGE_TITLE}</span>
        </button>
      </div>
      {open && (
        <form
          id="app-own-password-form"
          class="app-card app-own-password-form"
          aria-label={CHANGE_TITLE}
          onSubmit={(event) => {
            event.preventDefault()
            save()
          }}
          onKeyDown={(event) => {
            if (event.key !== 'Escape') return
            event.preventDefault()
            close()
          }}
        >
          <p class="app-people-line">{changeLine(user)}</p>
          <input class="app-people-hidden" type="text" name="username" autoComplete="username" value={user} readOnly tabIndex={-1} aria-hidden="true" />
          <label class="app-people-field">
            <span class="app-people-label">Current password</span>
            <input ref={currentField} class="app-people-input" type={kind} name="current-password" value={form.current} maxLength={PASSWORD_MAX + 8}
              autoComplete="current-password" autoCapitalize="none" autoCorrect="off" spellcheck={false} onInput={field('current')} />
          </label>
          <label class="app-people-field">
            <span class="app-people-label">New password</span>
            <input ref={newField} class="app-people-input" type={kind} name="new-password" value={form.password} maxLength={PASSWORD_MAX + 8}
              autoComplete="new-password" autoCapitalize="none" autoCorrect="off" spellcheck={false} onInput={field('password')} />
          </label>
          <label class="app-people-field">
            <span class="app-people-label">Again</span>
            <input ref={againField} class="app-people-input" type={kind} name="new-password-again" value={form.again} maxLength={PASSWORD_MAX + 8}
              autoComplete="new-password" autoCapitalize="none" autoCorrect="off" spellcheck={false} onInput={field('again')} />
          </label>
          <label class="app-people-check">
            <input type="checkbox" class="app-people-checkbox" checked={show} onChange={(event) => setShow((event.currentTarget as HTMLInputElement).checked)} />
            <span>Show</span>
          </label>
          <p class="app-footnote app-people-typing" aria-live="polite">{typing ?? ''}</p>
          <div class="app-people-buttons">
            <button type="submit" class="app-button is-primary" aria-disabled={!ready || busy}>{busy ? 'Saving…' : 'Save'}</button>
            <button type="button" class="app-button" onClick={close}>Cancel</button>
          </div>
          <div aria-live="assertive" aria-atomic="true">
            {problem && <p class="app-people-problem" role="alert">{problem}</p>}
          </div>
          {note && <p class="app-footnote app-people-http">{note}</p>}
        </form>
      )}
      <div class="app-own-password-said" aria-live="polite" aria-atomic="true">
        {done && (
          <>
            <p class="app-people-done">{done.words}</p>
            {done.warning && <p class="app-people-warning">{done.warning}</p>}
            <p class="app-footnote">{APPS_LINE}</p>
          </>
        )}
      </div>
    </>
  )
}
