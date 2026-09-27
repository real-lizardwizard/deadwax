/**
 * The one place that talks to the network.
 *
 * Everything here exists to keep two things from being confused with each other: a request
 * that failed, and a request that succeeded and found nothing. The vanilla frontend blurred
 * that line and it cost real debugging time - a MusicBrainz outage rendered as though the
 * user had typed a bad search.
 */

const BASE = '/deadwax'

/** A non-2xx response. `detail` is FastAPI's HTTPException detail when it sent one. */
export class ApiError extends Error {
  readonly status: number
  readonly detail: string | null

  constructor(status: number, detail: string | null, fallback: string) {
    super(detail || fallback)
    this.name = 'ApiError'
    this.status = status
    this.detail = detail
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
  constructor(detail: string | null) {
    super(503, detail, 'MusicBrainz is unreachable right now')
    this.name = 'MusicBrainzUnavailable'
  }
}

async function readDetail(response: Response): Promise<string | null> {
  try {
    const body = (await response.json()) as { detail?: unknown }
    return typeof body.detail === 'string' ? body.detail : null
  } catch {
    // an error response that isn't JSON is still an error; don't mask it with a parse failure
    return null
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${BASE}${path}`, init)

  if (!response.ok) {
    const detail = await readDetail(response)
    // deliberately not special-cased here: 503 only means "MusicBrainz is down" on the
    // MusicBrainz routes, and slskd answers 502 for its own refusals. Mapping status codes
    // to meanings is each module's job - see musicbrainz.ts.
    throw new ApiError(response.status, detail, `${init?.method ?? 'GET'} ${path} failed`)
  }

  return (await response.json()) as T
}

export function get<T>(path: string): Promise<T> {
  return request<T>(path)
}

/**
 * A successful response, left for the caller to read - for the library scan, whose HEADERS matter
 * as much as its body: the fields that change on every scan come as headers, so an unchanged
 * library's body is a 304 (v0.9.20), and its ETag says whether the body needs reading at all.
 */
export async function fetchOk(path: string, init?: RequestInit): Promise<Response> {
  const response = await fetch(`${BASE}${path}`, init)
  if (!response.ok) {
    const detail = await readDetail(response)
    throw new ApiError(response.status, detail, `${init?.method ?? 'GET'} ${path} failed`)
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

export function post<T>(path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
  return request<T>(path, {
    method: 'POST',
    ...(body === undefined
      ? {}
      : { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }),
    //? lib/latest.ts aborts a request that has been superseded - see there
    ...(signal ? { signal } : {}),
  })
}

/** For building EventSource URLs against the same prefix. */
export function url(path: string): string {
  return `${BASE}${path}`
}
