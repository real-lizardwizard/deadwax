/**
 * The sign-in screen's rules (2.0.0-player.48), pure - app/SignIn.tsx and app/signInGate.tsx draw from
 * them, and ui/test/signin.sim.cjs holds them.
 */

import { ApiError } from '../api/http'

/** The break-glass admin's fixed name (src/auth.py BREAK_GLASS_USER): no Navidrome account signs in as it. `deadwax`
 *  since 2.0.0-player.61 - `admin` until then, an ordinary Navidrome name now (Navidrome's own admin signs in as it). */
export const BREAK_GLASS_USER = 'deadwax'

/** What deadwax says to a request with no session at all - the screen's own lede says it already. */
export const PLAIN_SIGN_IN = 'Sign in to use deadwax.'

/**
 * What the screen says about a sign-in that failed. deadwax's own words where it sent some - a wrong
 * password, too many tries and how long to wait, Navidrome not answering - since they are written to be
 * read as they are; otherwise what kind of failure it was, plainly.
 */
export function signInProblem(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.detail) return error.detail
    if (error.status === 401) return "That user name and password didn't work."
    if (error.status === 429) return 'Too many tries - wait a minute and try again.'
    return `deadwax answered ${error.status} - try again in a moment.`
  }
  return "deadwax didn't answer - check you can reach it (on your network, or over WireGuard) and try again."
}

/** Why the screen is showing, said above the form - nothing for the plain "sign in". */
export function reasonShown(detail: string | null | undefined): string | null {
  const text = detail?.trim()
  return text && text !== PLAIN_SIGN_IN ? text : null
}

/**
 * Where a sign-in hands over to: the main page, when it sent you here to sign in (`/player/?return=/`)
 * - and nowhere else, so the address can't be made to send anybody off the site.
 */
export function returnTarget(search: string): '/' | null {
  return new URLSearchParams(search).get('return') === '/' ? '/' : null
}

/**
 * A sign-in made over the running app - its session had ended - carries on when it is the same person
 * (the app under it was never drawn away), and starts the app again for someone else: what is in hand - the
 * pins, Getting albums, the queue - was the other person's.
 */
export function afterSignIn(before: string | null, now: string): 'carry-on' | 'start-again' {
  return before !== null && before !== now ? 'start-again' : 'carry-on'
}
