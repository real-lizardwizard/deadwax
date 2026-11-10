/**
 * Change your own password (2.0.2) - You > Change password, src/routes/own_password.py - pure, so
 * ui/test/ownpassword.sim.cjs pins it: who is offered it, what shows while typing (People's password rules, in
 * src/people.py's words, and the same password again refused), when Save can be pressed, and what is said after.
 * The SERVER decides; these are for feedback while typing.
 */

import { passwordProblem } from './people'
import { BREAK_GLASS_USER } from './signIn'

export { PASSWORD_MAX, httpNote } from './people'

export const CHANGE_TITLE = 'Change password'
/** src/routes/own_password.py SAME_PASSWORD */
export const SAME_PASSWORD = "That's the password you have now - type a new one."
/** What is said under it after a change: the new password is Navidrome's, so every app that signs in to it needs it */
export const APPS_LINE = 'Amperfy and any other app you use with Navidrome need the new password too.'

export interface OwnPasswordForm {
  current: string
  password: string
  again: string
}

export const EMPTY_FORM: OwnPasswordForm = { current: '', password: '', again: '' }

/** Whether You offers it: logins on and a Navidrome sign-in - never with logins off (there is no password of yours
 *  in deadwax), never the break-glass admin (no Navidrome account behind it). */
export function changeOffered(me: { auth: string; user: string } | null | undefined): boolean {
  return !!me && me.auth === 'on' && !!me.user && me.user !== BREAK_GLASS_USER
}

/** The line at the top of the form. */
export function changeLine(user: string): string {
  return `Your Navidrome password, ${user} - the one you sign in to deadwax, Navidrome and Amperfy with. deadwax changes it in Navidrome as you, and doesn't keep it.`
}

/** What shows while typing: nothing until both new fields have something in them, then the first problem with them. */
export function formProblem(form: OwnPasswordForm, user: string): string | null {
  if (!form.password || !form.again) return null
  const problem = passwordProblem(form.password, form.again, user)
  if (problem) return problem
  if (form.current && form.password === form.current) return SAME_PASSWORD
  return null
}

/** Whether Save can be pressed: a current password, and a new one that meets every rule and isn't the current one. */
export function formReady(form: OwnPasswordForm, user: string): boolean {
  return !!form.current && !passwordProblem(form.password, form.again, user) && form.password !== form.current
}

/** What is said once it's done - how many of your other devices were signed out, and that this one wasn't. */
export function doneWords(signedOut: number): string {
  if (signedOut <= 0) return "Password changed. You're still signed in here."
  const devices = signedOut === 1 ? 'your other device' : `your other ${signedOut} devices`
  return `Password changed. Signed out of ${devices} - ${signedOut === 1 ? 'it signs' : 'they sign'} in again with the new one. You're still signed in here.`
}
