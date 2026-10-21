/**
 * People (2.0.0-player.61) - src/routes/people.py: Navidrome's accounts, managed as the signed-in Navidrome admin,
 * unlocked with their own password. Every write is a JSON POST (the same-origin guard stands in front of each);
 * a refusal is an ApiError with the server's words and its `kind` - `locked` meaning "unlock People again".
 */

import type { Category } from '../lib/permissions'
import { get, post } from './http'

/** One Navidrome account, joined with what deadwax knows of it. */
export interface Person {
  id: string
  user: string
  name: string
  admin: boolean
  /** it is NAVIDROME_USER - deadwax's own account */
  shared_account: boolean
  /** `local` or `deadwax`: nobody signs in to deadwax as it */
  reserved: boolean
  you: boolean
  /** live deadwax sessions */
  signed_in: number
  /** when they last signed in to deadwax, epoch seconds - null never */
  last_sign_in: number | null
  /** albums in their library */
  library: number
  /** downloads still coming that only they are waiting for */
  waiting_alone: number
  /** how many Navidrome libraries they may see (null: Navidrome didn't say) */
  libraries: number | null
  /** what an admin ticked for them - null for an admin, who has everything */
  permissions: Record<Category, boolean> | null
  /** for each action, why People refuses it - null when it is allowed */
  can: { reset: string | null; remove: string | null; admin: string | null; permissions: string | null }
}

/** A name deadwax keeps things for that Navidrome has no account for. */
export interface KnownOnly {
  user: string
  sessions: number
  credential: boolean
  library: number
  pins: number
  preferences: boolean
  requests: number
  permissions: number
}

export interface PeopleState {
  /** logins are on */
  on: boolean
  /** People can work here: logins on, a Navidrome sign-in, NAVIDROME_URL usable */
  available: boolean
  locked: boolean
  problem: string | null
  fix: string | null
  you: string
  /** NAVIDROME_USER, lowercased */
  account: string | null
  people: Person[]
  known_only: KnownOnly[]
}

export function getPeople(signal?: AbortSignal): Promise<PeopleState> {
  return get<PeopleState>('/people', signal)
}

export function unlockPeople(password: string): Promise<{ unlocked: boolean }> {
  return post('/people/unlock', { password })
}

export function lockPeople(): Promise<{ locked: boolean }> {
  return post('/people/lock', {})
}

export interface Made {
  made: { id: string; user: string; name: string }
  warning: string | null
}

export function createPerson(body: { user: string; name: string; password: string; password_again: string }): Promise<Made> {
  return post<Made>('/people/create', body)
}

export function resetPassword(id: string, body: { user: string; password: string; password_again: string }): Promise<{ reset: string; signed_out: number }> {
  return post(`/people/${encodeURIComponent(id)}/password`, body)
}

export function setAdmin(id: string, body: { user: string; admin: boolean }): Promise<{ user: string; admin: boolean; changed: boolean }> {
  return post(`/people/${encodeURIComponent(id)}/admin`, body)
}

export function removePerson(id: string, body: { user: string; confirm: string }): Promise<{ removed: string }> {
  return post(`/people/${encodeURIComponent(id)}/remove`, body)
}

export function forgetPerson(user: string): Promise<{ forgot: string }> {
  return post('/people/forget', { user })
}

export function savePermissions(id: string, body: { user: string } & Record<Category, boolean>): Promise<{ user: string; permissions: Record<Category, boolean> }> {
  return post(`/people/${encodeURIComponent(id)}/permissions`, body)
}
