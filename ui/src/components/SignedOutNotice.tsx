import { render } from 'preact'

import { loginsOn, onSignedOut } from '../api/auth'
import { me } from '../api/me'
import { reasonShown } from '../lib/signIn'

/**
 * The main page signed out (2.0.0-player.48): a plain message over the page, with a link to the app's
 * sign-in that comes back here afterwards (`/player/?return=/`). The main page retires once the app does
 * everything it does, so it gets no sign-in of its own - this is all of it.
 *
 * Shown on any 401 (api/http.ts says so as an event) - and, when the page says logins are on, after
 * asking `/deadwax/me` once as it loads, since the vanilla half's own requests don't go through http.ts.
 * With logins off neither happens: nothing is asked, and nothing ever answers 401.
 *
 * While it shows, who is asked again as the page comes back to the front and as the browser shows the
 * page again from its back-forward cache (Back, after signing in on the app's page): signed in by then,
 * the page starts again (a reload - its panels gave up while it was signed out), rather than leaving a
 * "You're signed out" over someone who isn't.
 */
export function SignedOutNotice({ reason }: { reason: string | null }) {
  const why = reasonShown(reason)
  return (
    <div class="signed-out" role="dialog" aria-modal="true" aria-labelledby="signed-out-title">
      <div class="signed-out-card">
        <h2 id="signed-out-title" class="signed-out-title">You're signed out</h2>
        <p class="signed-out-text">{why ?? "deadwax has logins on, so sign in to use it."}</p>
        <a class="signed-out-link" href="/player/?return=/">
          Sign in
        </a>
        <p class="signed-out-note">You sign in on the app's page, and come back here afterwards.</p>
      </div>
    </div>
  )
}

//? whether the notice is up: what a panel's failing poll asks before logging a failure that is only this
let shown = false

/** Whether the main page has been told it is signed out - its panels' failures since are that, said above. */
export function signedOutNow(): boolean {
  return shown
}

/** Watch for the main page being signed out, and say so over it. Called once by ui/src/main.tsx. */
export function watchSignedOut(): void {
  let host: HTMLElement | null = null
  shown = false
  const show = (reason: string | null) => {
    if (host) return
    shown = true
    host = document.createElement('div')
    host.id = 'signed-out-root'
    document.body.appendChild(host)
    document.getElementById('main-container')?.setAttribute('inert', '')
    render(<SignedOutNotice reason={reason} />, host)
    host.querySelector<HTMLElement>('.signed-out-link')?.focus()
  }
  onSignedOut(show)
  if (!loginsOn()) return
  const ask = () =>
    me().then(
      () => {
        if (shown) location.reload()
      },
      () => {},
    )
  ask()
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && shown) ask()
  })
  globalThis.addEventListener('pageshow', (event) => {
    if ((event as PageTransitionEvent).persisted && shown) ask()
  })
}
