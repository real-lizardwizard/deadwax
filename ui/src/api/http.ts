/**
 * The one place that talks to the network.
 *
 * Everything here exists to keep two things from being confused with each other: a request
 * that failed, and a request that succeeded and found nothing. The original vanilla frontend blurred
 * that line and it cost real debugging time - a MusicBrainz outage rendered as though the
 * user had typed a bad search.
 */

const BASE = '/deadwax'

/** A non-2xx response. `detail` is FastAPI's HTTPException detail when it sent one. `busy` (2.0.0-player.55): the
 *  body said `busy: true` beside it - the app's Search's MusicBrainz searches, MusicBrainz shedding them. */
export class ApiError extends Error {
  readonly status: number
  readonly detail: string | null
  readonly busy: boolean
  /** (2.0.0-player.61) what kind of refusal a People route said it was - `locked` brings its unlock form back */
  readonly kind: string | null

  constructor(status: number, detail: string | null, fallback: string, busy = false, kind: string | null = null) {
    super(detail || fallback)
    this.name = 'ApiError'
    this.status = status
    this.detail = detail
    this.busy = busy
    this.kind = kind
  }
}

/**
 * MusicBrainz is down, as distinct from "no results".
 *
 * The backend deliberately answers 503 rather than 500 for this (src/routes/
 * search_musicbrainz.py) because nothing is wrong with the request. MusicBrainz is
 * unreachable from ordinary machines often enough that this happens regularly, so it needs
 * to surface as an upstream outage and not as a failed search.
 */
export class MusicBrainzUnavailable extends ApiError {
  /**
   * `busy` (2.0.0-player.55): MusicBrainz said it is shedding searches just now - the 503's body carried
   * `busy: true` (src/routes/search_musicbrainz.py) - and Search says "MusicBrainz is busy just now" by it, never by
   * matching the detail's words. False for every other 503.
   */
  constructor(detail: string | null, busy = false) {
    super(503, detail, 'MusicBrainz is unreachable right now', busy)
    this.name = 'MusicBrainzUnavailable'
  }
}

async function readBody(response: Response): Promise<{ detail: string | null; busy: boolean; kind: string | null }> {
  try {
    const body = (await response.json()) as { detail?: unknown; busy?: unknown; kind?: unknown }
    return { detail: typeof body.detail === 'string' ? body.detail : null, busy: body.busy === true,
             kind: typeof body.kind === 'string' ? body.kind : null }
  } catch {
    // an error response that isn't JSON is still an error; don't mask it with a parse failure
    return { detail: null, busy: false, kind: null }
  }
}

/**
 * What the page is told when a session ends (2.0.0-player.48): a 401 from any route but the sign-in's
 * own, with the server's words as the event's `detail`. The app's sign-in screen comes back over
 * whatever shows (app/signInGate.tsx) - as the main page's notice did, until it retired in
 * 2.0.0-player.66. With logins off nothing answers 401, so nothing is ever said.
 */
export const SIGNED_OUT = 'deadwax:signed-out'

/**
 * Which session the page's requests go out under: one more each time the app's sign-in screen goes
 * because someone signed in (app/signInGate.tsx calls `newSession`). A request carries the cookie it
 * was SENT with, so a 401 for one sent before then - under the session the sign-in replaced - says
 * nothing about the new one, and isn't taken for it ending: else a poll that left just before the
 * sign-in answered, and was answered just after, brought the sign-in straight back over someone who
 * had just signed in (over WireGuard, a few times in a hundred).
 */
let session = 0

export function newSession(): void {
  session += 1
}

/** (2.0.0-player.64) Which session the page's requests go out under now - app/useResume.ts stops saving the play queue
 *  at a 401 until it is another (someone signed in since). */
export function currentSession(): number {
  return session
}

function noteSignedOut(path: string, status: number, detail: string | null, sentUnder: number): void {
  if (status !== 401 || path.startsWith('/auth/') || sentUnder !== session) return
  if (typeof globalThis.dispatchEvent !== 'function') return
  globalThis.dispatchEvent(new CustomEvent(SIGNED_OUT, { detail }))
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const sentUnder = session
  const response = await fetch(`${BASE}${path}`, init)

  if (!response.ok) {
    const { detail, busy, kind } = await readBody(response)
    noteSignedOut(path, response.status, detail, sentUnder)
    // deliberately not special-cased here: 503 only means "MusicBrainz is down" on the
    // MusicBrainz routes, and slskd answers 502 for its own refusals. Mapping status codes
    // to meanings is each module's job - see musicbrainz.ts.
    throw new ApiError(response.status, detail, `${init?.method ?? 'GET'} ${path} failed`, busy, kind)
  }

  return (await response.json()) as T
}

export function get<T>(path: string, signal?: AbortSignal): Promise<T> {
  //? lib/latest.ts aborts a request that has been superseded - see there
  return request<T>(path, signal ? { signal } : undefined)
}

/**
 * A successful response, left for the caller to read - for the library scan, whose HEADERS matter
 * as much as its body: the fields that change on every scan come as headers, so an unchanged
 * library's body is a 304 (v0.9.20), and its ETag says whether the body needs reading at all.
 */
export async function fetchOk(path: string, init?: RequestInit): Promise<Response> {
  const sentUnder = session
  const response = await fetch(`${BASE}${path}`, init)
  if (!response.ok) {
    const { detail, busy } = await readBody(response)
    noteSignedOut(path, response.status, detail, sentUnder)
    throw new ApiError(response.status, detail, `${init?.method ?? 'GET'} ${path} failed`, busy)
  }
  return response
}

export function put<T>(path: string, body?: unknown): Promise<T> {
  return request<T>(path, {
    method: 'PUT',
    ...(body === undefined
      ? {}
      : { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }),
  })
}

export function post<T>(path: string, body?: unknown, signal?: AbortSignal, keepalive = false): Promise<T> {
  return request<T>(path, {
    method: 'POST',
    ...(body === undefined
      ? {}
      : { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }),
    //? lib/latest.ts aborts a request that has been superseded - see there
    ...(signal ? { signal } : {}),
    //? (2.0.0-player.64) sent on as the page goes away - the play queue's last save (app/useResume.ts)
    ...(keepalive ? { keepalive: true } : {}),
  })
}

/** For building EventSource URLs against the same prefix. */
export function url(path: string): string {
  return `${BASE}${path}`
}
