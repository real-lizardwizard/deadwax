/**
 * People's rules on the page (2.0.0-player.61) - pure, so ui/test/people.sim.cjs pins them. The name and password
 * checks mirror src/people.py's, for feedback while typing (tests/test_people.py holds the numbers to the
 * server's); the SERVER decides. Also what each row says, which actions it offers (from the server's `can`), the
 * typed-name gate on Remove, the plain-http note and the Navidrome version note.
 */

import type { KnownOnly, PeopleState, Person } from '../api/people'

export const NAME_PATTERN = /^[a-z0-9][a-z0-9._-]{0,31}$/
export const NAME_MAX = 32
export const DISPLAY_MAX = 64
export const PASSWORD_MIN = 8
export const PASSWORD_MAX = 128
/** How long an unlock lasts unused (src/api/navidrome_admin.py UNLOCK_IDLE_SECONDS) */
export const UNLOCK_IDLE_MINUTES = 15
/** The names deadwax keeps for itself (src/auth.py RESERVED_NAMES) */
export const RESERVED: readonly string[] = ['local', 'deadwax']
/** The Navidrome People was made for: another minor version gets a note, never a block */
export const TESTED_NAVIDROME = '0.64'

/* ----- the words ----- */

export const UNLOCK_TITLE = 'Unlock People'
export function unlockLine(user: string): string {
  return `People changes Navidrome's accounts as you, ${user}. Navidrome needs your password for that; deadwax uses it once and doesn't keep it.`
}
export const UNLOCKED_LINE = `Unlocked on this device for ${UNLOCK_IDLE_MINUTES} minutes since you last use it - Lock ends it now.`
export const HTTP_NOTE = "This page isn't over HTTPS: a password typed here crosses your network readable, as everyone's sign-in does. That's fine on your own network or over WireGuard; anywhere else, put HTTPS in front of deadwax first."
export const SHARING_DOC = 'https://github.com/real-lizardwizard/deadwax/blob/main/docs/sharing.md'
export const KNOWN_ONLY_TITLE = 'Known only to deadwax'
export const KNOWN_ONLY_LINE = "Names deadwax keeps things for that have no Navidrome account - deleted in Navidrome's own Users page, or a removal deadwax couldn't finish."

/** The control characters a field may not have: what Python calls Cc, Cf, Zl and Zp, near enough. */
const CONTROL = /[\u0000-\u001f\u007f-\u009f\u00ad\u200b-\u200f\u2028-\u202e\u2060-\u2064\ufeff]/

export function cleanName(typed: string): string {
  return typed.trim().toLowerCase()
}

/** Why `name` (cleaned) can't be a new account's - or null. src/people.py name_problem's words. */
export function nameProblem(name: string): string | null {
  if (!name) return 'Type a user name.'
  if (name.length > NAME_MAX) return `A user name is at most ${NAME_MAX} characters.`
  if (!NAME_PATTERN.test(name)) return 'A user name is lowercase letters, digits, dots, underscores and hyphens, starting with a letter or a digit.'
  if (RESERVED.includes(name)) return `'${name}' is a name deadwax keeps for itself - choose another.`
  return null
}

export function displayProblem(display: string): string | null {
  const shown = display.trim()
  if (shown.length > DISPLAY_MAX) return `A display name is at most ${DISPLAY_MAX} characters.`
  if (CONTROL.test(shown)) return "A display name can't have control characters in it."
  return null
}

/** Why a password won't do for the account `name` - or null. Never trimmed. */
export function passwordProblem(password: string, again: string, name: string): string | null {
  if (password.length < PASSWORD_MIN) return `A password is at least ${PASSWORD_MIN} characters.`
  if (password.length > PASSWORD_MAX) return `A password is at most ${PASSWORD_MAX} characters.`
  if (CONTROL.test(password)) return "A password can't have control characters in it."
  if (name && password.toLowerCase() === name.toLowerCase()) return "A password can't be the user name."
  if (password !== again) return "The two passwords aren't the same."
  return null
}

/** What the page shows while typing: the first problem of a field once there is something in it - never a scold
 *  for a field not yet reached. */
export function formProblem(form: { user: string; name: string; password: string; again: string }): string | null {
  const name = cleanName(form.user)
  if (form.user && nameProblem(name)) return nameProblem(name)
  if (displayProblem(form.name)) return displayProblem(form.name)
  if (form.password && form.again && passwordProblem(form.password, form.again, name)) return passwordProblem(form.password, form.again, name)
  return null
}

/** Whether Make account can be pressed: every rule met. */
export function formReady(form: { user: string; name: string; password: string; again: string }): boolean {
  const name = cleanName(form.user)
  return !nameProblem(name) && !displayProblem(form.name) && !passwordProblem(form.password, form.again, name)
}

/* ----- a row ----- */

/** The chips after a person's name. */
export function chips(person: Pick<Person, 'you' | 'admin' | 'shared_account' | 'reserved'>): string[] {
  return [
    ...(person.you ? ['You'] : []),
    ...(person.admin ? ['Admin'] : []),
    ...(person.shared_account ? ["deadwax's own account"] : []),
    ...(person.reserved ? ["Can't sign in to deadwax"] : []),
  ]
}

const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`

/** How long ago, in words: "just now", "5 minutes ago", "3 days ago". */
export function ago(seconds: number): string {
  if (seconds < 60) return 'just now'
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${plural(minutes, 'minute', 'minutes')} ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${plural(hours, 'hour', 'hours')} ago`
  const days = Math.floor(hours / 24)
  if (days < 60) return `${plural(days, 'day', 'days')} ago`
  return `${plural(Math.floor(days / 30), 'month', 'months')} ago`
}

/** Their deadwax sign-in: "Signed in on 2 devices" / "Last signed in 3 days ago" / "Never signed in to deadwax". */
export function signInWords(person: Pick<Person, 'signed_in' | 'last_sign_in'>, nowSeconds: number): string {
  if (person.signed_in > 0) return `Signed in on ${plural(person.signed_in, 'device', 'devices')}`
  if (person.last_sign_in !== null) return `Last signed in ${ago(Math.max(0, nowSeconds - person.last_sign_in))}`
  return 'Never signed in to deadwax'
}

export function libraryWords(person: Pick<Person, 'library'>): string {
  return `${plural(person.library, 'album', 'albums')} in their library`
}

/** Only when a non-admin has no Navidrome library at all. */
export function librariesWarning(person: Pick<Person, 'admin' | 'libraries'>): string | null {
  if (person.admin || person.libraries !== 0) return null
  return "Navidrome gives them no library - they'll see nothing. Tick one for them in Navidrome's Users page."
}

export type ActionKind = 'reset' | 'admin' | 'remove'

export interface Action {
  kind: ActionKind
  label: string
  /** why it isn't offered - the server's words - or null */
  refused: string | null
}

/** A row's actions, each present or with its reason in words (never a bare greyed button). */
export function actions(person: Pick<Person, 'admin' | 'can'>): Action[] {
  return [
    { kind: 'reset', label: 'Reset password…', refused: person.can.reset },
    { kind: 'admin', label: person.admin ? 'No longer admin' : 'Make admin', refused: person.can.admin },
    { kind: 'remove', label: 'Remove…', refused: person.can.remove },
  ]
}

/** The reasons a row shows, once each (several actions can share one). */
export function refusals(person: Pick<Person, 'admin' | 'can'>): string[] {
  return [...new Set(actions(person).map((action) => action.refused).filter((said): said is string => !!said))]
}

/** Remove's typed-name gate: exactly their user name - not another case, not with a space. */
export function removeReady(typed: string, user: string): boolean {
  return typed === user && user.length > 0
}

/** Make admin's question, and what it gives. */
export function makeAdminWords(user: string): { question: string; body: string } {
  return {
    question: `Make ${user} an admin?`,
    body: `In deadwax they'll edit and delete albums, see everyone's downloads, the albums that need a look, Library care, the settings, the log and People. In Navidrome they become an admin too: its Users, libraries and settings, every library, and in Amperfy everyone's playlists, private ones included.`,
  }
}

/** No longer admin's question - and what they keep (Navidrome's libraries; what was ticked before). */
export function unmakeAdminWords(user: string, ticked: readonly string[]): { question: string; body: string } {
  const before = ticked.length ? ` They keep what was ticked for them before: ${ticked.join(', ')}.` : ''
  return {
    question: `${user} no longer an admin?`,
    body: `${user} keeps every library Navidrome gave them as an admin - narrow them in Navidrome's Users page if they shouldn't see them all.${before}`,
  }
}

/** Remove's dialog, from the server's numbers. */
export function removeLines(person: Pick<Person, 'user' | 'admin' | 'library' | 'signed_in' | 'waiting_alone'>): {
  navidrome: string
  deadwax: string
  stays: string
  undo: string
} {
  const role = person.admin ? ', and their admin role' : ''
  const waiting = person.waiting_alone
    ? ` ${plural(person.waiting_alone, 'download', 'downloads')} only they are waiting for carr${person.waiting_alone === 1 ? 'ies' : 'y'} on and ${person.waiting_alone === 1 ? 'is' : 'are'} filed for nobody - cancel ${person.waiting_alone === 1 ? 'it' : 'them'} in Requests first if nobody wants ${person.waiting_alone === 1 ? 'it' : 'them'}.`
    : ''
  //? the numbers only where there are some: "the 0 albums" and "(0 devices)" read as a fault
  const favourites = person.library ? ` (the ${plural(person.library, 'album', 'albums')} in their library)` : ''
  const devices = person.signed_in ? ` (${plural(person.signed_in, 'device', 'devices')})` : ''
  return {
    navidrome: `In Navidrome, for good: ${person.user}'s account, their play counts and play history, their favourites${favourites}, all their playlists - shared ones too - and their Last.fm or ListenBrainz link${role}.`,
    deadwax: `In deadwax: their sign-ins${devices}, their library list, their pins, their play queue, Getting albums settings and permissions.`,
    stays: `Stays: every album in the store.${waiting}`,
    undo: "There's no undo. If they might come back, reset their password instead.",
  }
}

/** What a known-only name keeps. */
export function knownWords(entry: KnownOnly): string {
  const parts = [
    ...(entry.sessions ? [plural(entry.sessions, 'sign-in', 'sign-ins')] : []),
    ...(entry.credential ? ['a kept login'] : []),
    ...(entry.library ? [plural(entry.library, 'album in their library', 'albums in their library')] : []),
    ...(entry.pins ? [plural(entry.pins, 'pin', 'pins')] : []),
    ...(entry.preferences ? ['Getting albums settings'] : []),
    ...(entry.requests ? [plural(entry.requests, 'request', 'requests')] : []),
    ...(entry.permissions ? [plural(entry.permissions, 'permission', 'permissions')] : []),
    ...(entry.queue ? ['a play queue'] : []),
  ]
  return parts.length ? `deadwax keeps ${parts.join(', ')}.` : 'deadwax keeps a little history for them.'
}

/* ----- after a change ----- */

export function madeWords(user: string, origin: string): string {
  return `Made ${user}. Tell them their user name, the password you chose and deadwax's address (${origin}/player/) - Amperfy signs in with the same.`
}

export function resetWords(user: string, signedOut: number): string {
  return `Done. ${user} is signed out of deadwax on ${plural(signedOut, 'device', 'devices')} and signs in with the new password - Amperfy and any other app they use need it too.`
}

/* ----- the page ----- */

/** The plain-http note under every password field: on anything but https. */
export function httpNote(protocol: string): string | null {
  return protocol === 'https:' ? null : HTTP_NOTE
}

/** "People was made for Navidrome 0.64 - this is …" when Navidrome's status names another minor version - a note,
 *  never a block. `server` is /deadwax/navidrome/status's ("Navidrome 0.65.0 (abc)"). */
export function versionNote(server: string | null | undefined): string | null {
  const found = /(\d+)\.(\d+)(?:\.(\d+))?/.exec(server ?? '')
  if (!found) return null
  if (`${found[1]}.${found[2]}` === TESTED_NAVIDROME) return null
  return `People was made for Navidrome ${TESTED_NAVIDROME} - this is ${found[0]}.`
}

/** What the page draws: the unlock form, the list, or only the problem. */
export type PeopleView = 'asking' | 'unavailable' | 'locked' | 'list'

export function peopleView(state: PeopleState | null): PeopleView {
  if (state === null) return 'asking'
  if (!state.available) return 'unavailable'
  return state.locked ? 'locked' : 'list'
}
