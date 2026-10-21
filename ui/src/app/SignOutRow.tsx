import { useState } from 'preact/hooks'

import { signOut } from '../api/auth'
import { ApiError } from '../api/http'
import { BREAK_GLASS_USER } from '../lib/signIn'

/**
 * You > About's Sign out (2.0.0-player.48), drawn only with logins on. It ends this browser's session -
 * deadwax forgets it and clears the cookie - and starts the app again, at the sign-in: signing out is
 * leaving, so what was playing stops with it (unlike a session that ENDS, which the sign-in screen comes
 * back over, the app and its player left as they are - app/signInGate.tsx). deadwax answering with a
 * failure still cleared the cookie and ended the session in memory, so that starts again too; only no
 * answer at all is said here, and nothing is left half done. The break-glass admin (`admin`,
 * DEADWAX_ADMIN_PASSWORD) is told so: no Navidrome account is behind that sign-in, and it has its 12 hours.
 */
export function SignOutRow({ user }: { user: string }) {
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)

  const leave = () => {
    if (busy) return
    setBusy(true)
    setProblem(null)
    signOut().then(
      () => location.reload(),
      (error: unknown) => {
        if (error instanceof ApiError) {
          location.reload()
          return
        }
        setBusy(false)
        setProblem("deadwax didn't answer, so you're still signed in - try again.")
      },
    )
  }

  return (
    <>
      <div class="app-group app-signout">
        <button type="button" class="app-row app-link-row app-signout-row" onClick={leave} disabled={busy}>
          <span class="app-row-label">{busy ? 'Signing out…' : 'Sign out'}</span>
          <span class="app-row-value">{user}</span>
        </button>
      </div>
      <div aria-live="polite" aria-atomic="true">
        {problem && <p class="app-footnote app-error">{problem}</p>}
      </div>
      <p class="app-footnote">
        {user === BREAK_GLASS_USER
          ? `Signed in as ${BREAK_GLASS_USER}, with the break-glass password - it lasts 12 hours. `
          : `Signed in as ${user}, with your Navidrome account. `}
        Signing out ends this device's session and stops what's playing.
      </p>
    </>
  )
}
