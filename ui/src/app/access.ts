/**
 * What the app draws by (2.0.0-player.61): this person's permissions as deadwax last said them, whether logins
 * are on, and whether an admin gave them something this session doesn't honour - a store, as the app's others
 * are, so any part of the app reads it with useAccess() and redraws as /deadwax/me says something new: Get
 * becomes "off for you" at the next ask after an admin takes it away, with no sign-in.
 *
 * Before deadwax has answered here it is the session's word (session.ts, set by the sign-in gate before the app
 * is first drawn) with logins on, and everything with them off - so nothing shows that shouldn't for a moment.
 * Set from every /me answer the app has (noteAccess): App's, You's, and since the review the sign-in gate's - its
 * re-asks as the page comes back to the front, as a song fails, and a sign-in again (signInGate.tsx).
 */

import { useEffect, useState } from 'preact/hooks'

import type { Me } from '../api/me'
import { ALL, permissionsOf, samePermissions, type Permissions } from '../lib/permissions'
import { permissionsUntilAsked, sessionMe } from './session'

export interface Access {
  permissions: Permissions
  /** logins are on - People is there only then */
  on: boolean
  /** /me's permissions_unverified */
  unverified: boolean
  /** (2.0.0-player.63) /me's `admin`: a Navidrome admin, break-glass, or everyone with logins off - Info's Debug
   *  is theirs alone */
  admin: boolean
}

//? what /me last said here - null until it has: the session's word (session.ts) stands until then
let noted: Access | null = null
const listeners = new Set<(access: Access) => void>()

export function accessOf(me: Me): Access {
  return { permissions: me.auth === 'off' ? ALL : permissionsOf(me), on: me.auth === 'on', unverified: !!me.permissions_unverified, admin: me.auth === 'off' || me.admin === true }
}

//? the session's word, made once per session object - so a reader's memo keyed on it holds still between renders
let fromSession: { session: Me | null; access: Access } | null = null

export function accessNow(): Access {
  if (noted) return noted
  const session = sessionMe()
  if (fromSession?.session !== session || fromSession === null) {
    fromSession = {
      session,
      //? no session is logins off, when everyone is the admin
      access: { permissions: permissionsUntilAsked(), on: session?.auth === 'on', unverified: !!session?.permissions_unverified, admin: session ? session.auth === 'off' || session.admin === true : true },
    }
  }
  return fromSession.access
}

/** What /me has just said - drawn by every reader when it changed. */
export function noteAccess(me: Me): void {
  const next = accessOf(me)
  const was = accessNow()
  noted = next
  if (samePermissions(was.permissions, next.permissions) && was.on === next.on && was.unverified === next.unverified && was.admin === next.admin) return
  for (const listener of listeners) listener(next)
}

/** Forget what /me said (the sims, between cases). */
export function forgetAccess(): void {
  noted = null
}

/** What this person may do now - read at every render (one object while nothing changed, so a memo keyed on it holds),
 *  the component drawn again as /me changes it. */
export function useAccess(): Access {
  const [, drawn] = useState(0)
  useEffect(() => {
    const redraw = () => drawn((count) => count + 1)
    listeners.add(redraw)
    return () => {
      listeners.delete(redraw)
    }
  }, [])
  return accessNow()
}
