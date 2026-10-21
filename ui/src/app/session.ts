/**
 * Who is signed in, as the sign-in gate last heard it (2.0.0-player.48) - set by app/signInGate.tsx
 * before the app is first drawn, and again by each sign-in. With logins off it stays null: nothing asks,
 * and the app reads `/deadwax/me` as it always has.
 *
 * What it is for: the app's managing rows (the sidebar's Managing, You's, an album's Edit, an artist's
 * managing) start from the RIGHT answer with logins on, instead of from "admin until /me answers" -
 * which, for a user, drew an admin's rows for a moment. Since 2.0.0-player.61 by the session's
 * permissions (lib/permissions.ts). A module, as the app's other stores are.
 */

import type { Me } from '../api/me'
import { ALL, permissionsOf, type Permissions } from '../lib/permissions'

let signedIn: Me | null = null

export function sessionMe(): Me | null {
  return signedIn
}

export function setSessionMe(me: Me | null): void {
  signedIn = me
}

/** What to draw before deadwax has answered `/deadwax/me` here (2.0.0-player.61, in place of "admin until
 *  asked"): the session's word when logins are on - its permissions - and everything when they're off, when
 *  everyone is the admin. app/access.ts keeps what the app draws by from then on. */
export function permissionsUntilAsked(): Permissions {
  return signedIn ? permissionsOf(signedIn) : ALL
}
