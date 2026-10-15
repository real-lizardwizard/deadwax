/**
 * Who is signed in, as the sign-in gate last heard it (2.0.0-player.48) - set by app/signInGate.tsx
 * before the app is first drawn, and again by each sign-in. With logins off it stays null: nothing asks,
 * and the app reads `/deadwax/me` as it always has.
 *
 * What it is for: the app's admin-only rows (the sidebar's Managing, You's, an album's Edit, an artist's
 * managing) start from the RIGHT answer with logins on, instead of from "admin until /me answers" -
 * which, for a user, drew an admin's rows for a moment. A module, as the app's other stores are.
 */

import type { Me } from '../api/me'

let signedIn: Me | null = null

export function sessionMe(): Me | null {
  return signedIn
}

export function setSessionMe(me: Me | null): void {
  signedIn = me
}

/** Whether to draw an admin's rows before deadwax has answered `/deadwax/me` here: the session's word
 *  when logins are on, and yes when they're off - everyone is the admin then. */
export function adminUntilAsked(): boolean {
  return signedIn ? signedIn.admin : true
}
