/**
 * Logins (2.0.0-player.48): whether deadwax has them on, signing in and out, and hearing that a
 * session ended. The server's side is src/routes/auth.py and src/auth.py.
 *
 * Whether logins are on is read from the PAGE, not asked: deadwax marks the head of its pages with
 * `<meta name="deadwax-auth" content="on">` when they are (src/api/app.py LOGINS_MARK) - so with logins
 * off the app draws at once, exactly as it always has, with no extra round trip before it.
 *
 * The session is a cookie this script never sees (HttpOnly); every request to deadwax carries it, the
 * player's audio included. Nothing here ever holds a password past the one request that sends it.
 */

import { SIGNED_OUT, post } from './http'
import type { Me } from './me'

/** Whether this page was served with logins on. */
export function loginsOn(doc: Pick<Document, 'querySelector'> | undefined = globalThis.document): boolean {
  return doc?.querySelector('meta[name="deadwax-auth"]')?.getAttribute('content') === 'on'
}

/** Sign in with a Navidrome user name and password. Answers what /deadwax/me answers. */
export function signIn(username: string, password: string): Promise<Me> {
  return post<Me>('/auth/login', { username, password })
}

/** End this browser's session (and clear its cookie). */
export function signOut(): Promise<unknown> {
  return post<unknown>('/auth/logout')
}

/** Hear every 401 from deadwax (api/http.ts): the server's words, or null. Returns the way to stop. */
export function onSignedOut(listener: (detail: string | null) => void): () => void {
  const heard = (event: Event) => listener((event as CustomEvent<string | null>).detail ?? null)
  globalThis.addEventListener(SIGNED_OUT, heard)
  return () => globalThis.removeEventListener(SIGNED_OUT, heard)
}
