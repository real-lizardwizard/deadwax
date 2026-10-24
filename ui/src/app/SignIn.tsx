import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { signIn } from '../api/auth'
import type { Me } from '../api/me'
import { FOR_WHOEVER, reasonShown, signInProblem, signInWhy } from '../lib/signIn'

/**
 * The sign-in screen (2.0.0-player.48): deadwax's name, a user name and a password - their Navidrome
 * account - and what went wrong, said plainly (a wrong password, Navidrome not answering, too many tries
 * and how long to wait: deadwax's own words, lib/signIn.ts). Drawn by app/signInGate.tsx, alone before
 * the app has been drawn, or OVER it when a session ends mid-use - the app inert under it, and the player
 * left to itself, since nothing here touches it: it plays nothing and reads nothing of it.
 *
 * `reason` is why it is showing, when that is more than "sign in" - the session ended because the
 * Navidrome password changed, say - said above the form, and the dialog's description, so VoiceOver
 * reads it with the dialog rather than only "User name, text field" (focus goes straight to the name,
 * which is all there is to do here; the reason would otherwise never be read out). The fields' text is never under 16px (iOS
 * zooms the page into a field that is), it fits a 320px phone and centres on a desktop, and the
 * home-screen app keeps it clear of the notch and the home bar (signin.css). The password is held only
 * until the sign-in it is sent with has answered.
 */
export function SignIn({
  reason,
  reasonWhy = null,
  onSignedIn,
}: {
  reason: string | null
  /** (2.0.4) what whoever runs deadwax needs beside `reason` (lib/signIn.ts signInWhy) - folded under it */
  reasonWhy?: string | null
  onSignedIn: (me: Me) => void
}) {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  //? (2.0.4) what whoever runs deadwax needs beside the problem, folded under it
  const [problemWhy, setProblemWhy] = useState<string | null>(null)
  const first = useRef<HTMLInputElement>(null)

  //? the user name field takes focus as the screen comes up - it is the only thing to do here
  useLayoutEffect(() => {
    first.current?.focus()
  }, [])

  const submit = (event: Event) => {
    event.preventDefault()
    if (busy) return
    //? read from the fields themselves: a password manager's fill doesn't always say so as input
    const form = event.currentTarget as HTMLFormElement
    const name = ((form.elements.namedItem('username') as HTMLInputElement | null)?.value ?? username).trim()
    const secret = (form.elements.namedItem('password') as HTMLInputElement | null)?.value ?? password
    if (!name || !secret) {
      setProblem('Type your user name and your password.')
      setProblemWhy(null)
      return
    }
    setBusy(true)
    setProblem(null)
    setProblemWhy(null)
    signIn(name, secret).then(
      (me) => {
        setPassword('')
        setBusy(false)
        onSignedIn(me)
      },
      (error: unknown) => {
        setPassword('')
        setBusy(false)
        setProblem(signInProblem(error))
        setProblemWhy(signInWhy(error))
      },
    )
  }

  //? (review) a sign-in answered with the very words the screen came up with (no secret key, say): said once - as the
  //? answer, which the live region reads out - and not again above the form, with a second fold
  const shown = reasonShown(reason)
  const why = shown !== null && shown === problem ? null : shown

  return (
    <div
      class="app-signin"
      role="dialog"
      aria-modal="true"
      aria-labelledby="app-signin-title"
      aria-describedby={why ? 'app-signin-reason' : undefined}
    >
      <form class="app-signin-card" onSubmit={submit} method="post" noValidate>
        <div class="app-signin-head">
          <span class="app-avatar" aria-hidden="true">
            d
          </span>
          <h1 id="app-signin-title" class="app-signin-title">
            deadwax
          </h1>
        </div>
        <p class="app-signin-lede">Sign in with your Navidrome account.</p>
        {why && (
          <p id="app-signin-reason" class="app-signin-reason">
            {why}
          </p>
        )}
        {why && reasonWhy && <ForWhoever why={reasonWhy} />}
        <label class="app-signin-label" for="app-signin-user">
          User name
        </label>
        <input
          ref={first}
          id="app-signin-user"
          class="app-signin-field"
          name="username"
          type="text"
          autocomplete="username"
          autocapitalize="none"
          autocorrect="off"
          spellcheck={false}
          value={username}
          onInput={(event) => setUsername((event.currentTarget as HTMLInputElement).value)}
        />
        <label class="app-signin-label" for="app-signin-password">
          Password
        </label>
        <input
          id="app-signin-password"
          class="app-signin-field"
          name="password"
          type="password"
          autocomplete="current-password"
          value={password}
          onInput={(event) => setPassword((event.currentTarget as HTMLInputElement).value)}
        />
        {/* always in the page, so VoiceOver hears a sign-in that failed (it reads a region only once
            it is there) */}
        <div class="app-signin-problem" aria-live="assertive" aria-atomic="true">
          {problem && <p class="app-error">{problem}</p>}
        </div>
        {problem && problemWhy && <ForWhoever why={problemWhy} />}
        <button type="submit" class="app-signin-submit" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  )
}

/**
 * (2.0.4) What whoever runs deadwax needs - a setting, Navidrome's own words - folded under the sentence everyone
 * reads: the sign-in screen can't tell a listener from whoever runs it, so the sentence is the listener's and this
 * is one tap away.
 */
function ForWhoever({ why }: { why: string }) {
  return (
    <details class="app-signin-why">
      <summary>{FOR_WHOEVER}</summary>
      <p>{why}</p>
    </details>
  )
}
