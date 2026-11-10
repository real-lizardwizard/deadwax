/**
 * The sign-in screen's rules (2.0.0-player.48), pure - app/SignIn.tsx and app/signInGate.tsx draw from
 * them, and ui/test/signin.sim.cjs holds them.
 */

import { ApiError } from '../api/http'
import { asSentence, plumbing, TELL } from './errorWords'

/** The break-glass admin's fixed name (src/auth.py BREAK_GLASS_USER): no Navidrome account signs in as it. `deadwax`
 *  since 2.0.0-player.61 - `admin` until then, an ordinary Navidrome name now (Navidrome's own admin signs in as it). */
export const BREAK_GLASS_USER = 'deadwax'

/** What deadwax says to a request with no session at all - the screen's own lede says it already. */
export const PLAIN_SIGN_IN = 'Sign in to use deadwax.'

/** (2.0.4) deadwax not reached at all - the phone off the network, the VPN down, deadwax restarting. */
export const UNREACHED = "Can't reach deadwax. Check you're on the right network (or your VPN is on) and try again."
/** (2.0.4) an answer with no words of deadwax's own - a 500, something in front of it. */
export const SERVER_FAILED = 'Something went wrong on the server - try again in a moment.'
/** (2.0.4) the heading over what whoever runs deadwax needs (signInWhy), folded under the sentence */
export const FOR_WHOEVER = 'For whoever runs deadwax'

/**
 * What the screen says about a sign-in that failed. deadwax's own words where it sent some - a wrong
 * password, too many tries and how long to wait, Navidrome not answering - since they are written to be
 * read as they are (and since 2.0.4 hold no setting, address or exception: those are signInWhy's, and a
 * detail that holds one anyway is not shown here - lib/errorWords.ts plumbing); otherwise what kind of
 * failure it was, plainly.
 */
export function signInProblem(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.detail && !plumbing(error.detail)) {
      //? (2.0.4) deadwax's split 503 (src/auth.py Explained: logins it can't run, its database, Navidrome not set up) is
      //? a problem only whoever runs it can fix
      return error.why && error.status === 503 ? `${asSentence(error.detail)} ${TELL}` : error.detail
    }
    if (error.status === 401) return "That user name and password didn't work."
    if (error.status === 429) return 'Too many tries - wait a minute and try again.'
    return SERVER_FAILED
  }
  return UNREACHED
}

/**
 * (2.0.4) What whoever runs deadwax needs beside the sentence - the server's `why` (a setting, Navidrome's own
 * words), or a detail too technical for the sentence - shown folded under "For whoever runs deadwax": the
 * screen can't tell who is reading it. Null when there is nothing more.
 */
export function signInWhy(error: unknown): string | null {
  if (!(error instanceof ApiError)) return null
  if (error.why) return error.why
  return error.detail && plumbing(error.detail) ? error.detail : null
}

/** Why the screen is showing, said above the form - nothing for the plain "sign in". */
export function reasonShown(detail: string | null | undefined): string | null {
  const text = detail?.trim()
  return text && text !== PLAIN_SIGN_IN ? text : null
}

/**
 * A sign-in made over the running app - its session had ended - carries on when it is the same person
 * (the app under it was never drawn away), and starts the app again for someone else: what is in hand - the
 * pins, Getting albums, the queue - was the other person's.
 */
export function afterSignIn(before: string | null, now: string): 'carry-on' | 'start-again' {
  return before !== null && before !== now ? 'start-again' : 'carry-on'
}
