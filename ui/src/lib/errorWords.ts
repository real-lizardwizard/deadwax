/**
 * What went wrong, in a listener's words (2.0.4, UX batch 1 - "errors and connections"). Pure, so
 * ui/test/errors.sim.cjs pins every class and every sentence.
 *
 * Until 2.0.4 the app put the error's own text on the screen: a browser's "Load failed", http.ts's
 * "GET /x failed", Navidrome's "Navidrome couldn't be reached at http://...: All connection attempts
 * failed", a Python traceback's last line out of slskd ("HTTPConnectionPool(host=...): Max retries
 * exceeded..."), a job's "nothing could be organized, check SLSKD_DOWNLOAD_PATH". A listener can do
 * nothing with any of it. Now every error line is a SENTENCE saying what happened, and WHAT TO DO
 * (try again, or tell whoever runs deadwax) - and, for someone who runs deadwax (an admin, or someone
 * given Settings and the log: app/access.ts seesDetail), the error's own words as well, in a smaller
 * line under it, since those are what they fix it from.
 *
 * THE CLASSES (errorKind), from what the error is - never from its words, but for one test below:
 *
 *  - offline: the request never reached deadwax (fetch's TypeError: "Failed to fetch", Safari's
 *    "Load failed", Firefox's "NetworkError...") - the phone off the network, the VPN down, deadwax
 *    restarting.
 *  - timeout: 408 or 504 - something took too long.
 *  - unreachable: 502 or 503 with no words fit for anyone - deadwax answered, and what it needed behind
 *    it didn't (Navidrome, slskd: their own words are an address, a setting, slskd). Said by whose answer
 *    it was (`service`, else serviceOf: the route the answer came from).
 *  - not-found: 404 - said by the caller (`gone`: "This album isn't here any more."), else deadwax's
 *    words ("That playlist isn't on Navidrome any more"), never FastAPI's bare "Not Found".
 *  - not-allowed: 401 (the sign-in comes up over it anyway) or 403 - a 403's words are deadwax's own
 *    ("That needs Edit albums, which an admin hasn't given you."), shown as they are.
 *  - refused: deadwax said no in words written for whoever reads them - a 4xx, or a 502/503, whose
 *    detail passes `plumbing` (a playlist that changed, "already in your library", "deadwax can't keep
 *    pins: its database isn't writable"), any answer deadwax split in two (src/auth.py Explained:
 *    `detail` for anyone, `why` for whoever runs it), or any refusal it named a `kind` of (a People
 *    route's or Change password's Refused - a 504 or a 500 among them), its words passing `plumbing`. Its words as written - a user's name in them is
 *    never re-cased.
 *  - other: anything else - a 500, an error of the page's own.
 *
 * `plumbing` is the one test of words: a sentence naming a setting (DB_PATH, SLSKD_URL), an address, an
 * exception, an errno, a file path or slskd is never a listener's line. The server's words reach a
 * listener only through it, so a detail that grows one of those falls back to the class's sentence.
 */

import { ApiError } from '../api/http'

export type ErrorKind = 'offline' | 'timeout' | 'unreachable' | 'not-found' | 'not-allowed' | 'refused' | 'other'

/** Whose answer an error is: the music server's (the Navidrome routes), the downloads' (slskd's), or deadwax's own. */
export type Service = 'music' | 'downloads' | 'deadwax'

/** What a listener can always do about a problem only whoever runs deadwax can fix. */
export const TELL = 'Tell whoever runs deadwax.'

/** Said to a listener after a problem that should pass: the try again, and the tell if it doesn't. */
const KEEPS = 'if it keeps happening, tell whoever runs deadwax.'
const KEEPS_TOLD = 'If it keeps happening, tell whoever runs deadwax.'

export const OFFLINE = "Can't connect to deadwax."
export const OFFLINE_ADVICE = 'Check your connection, then try again.'
/** ...beside a Try again the page draws itself */
export const OFFLINE_RETRY = 'Check your connection.'
export const TIMEOUT = 'That took too long.'
export const SIGNED_OUT = 'Your sign-in has ended - sign in again.'
export const NOT_ALLOWED = "You don't have permission for that."
export const GONE = "It isn't there any more."
export const OTHER = 'Something went wrong.'

/** An unreachable's sentence, by whose answer it was. */
export const DOWN: Readonly<Record<Service, string>> = {
  music: "Can't reach the music server right now.",
  downloads: "Downloads aren't working right now.",
  deadwax: "deadwax can't do that right now.",
}

export interface ErrorWords {
  kind: ErrorKind
  /** what happened, for everyone */
  text: string
  /** what to do about it - for a listener with the tell where only whoever runs deadwax can fix it; '' when the
   *  text says it, or there's nothing to do */
  advice: string
  /** the error's own words, for someone who runs deadwax - null for a listener, and when they'd add nothing */
  detail: string | null
}

export interface ErrorOptions {
  /** the reader runs deadwax (app/access.ts seesDetail): the detail too, and never "tell whoever runs deadwax" */
  admin?: boolean
  /** whose answer it was - an unreachable's sentence (DOWN) */
  service?: Service
  /** a 404's sentence - "This playlist has been deleted." */
  gone?: string
  /** what didn't work, said in place of an unreachable's or an other's sentence - "The download couldn't be started." */
  failed?: string
  /** the page draws its own Try again beside the line: the advice leaves "try again" to it (review: said twice) */
  retry?: boolean
}

/** Words a listener is never shown: a setting's name, an address, an exception, an errno, a path, slskd. */
const PLUMBING = [
  /https?:\/\//i,
  /\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b/,
  /\b[A-Za-z]*(Error|Exception)\b/,
  /Errno|Traceback|HTTPConnectionPool|Max retries|\bhost=|\bport=/,
  /\b(GET|POST|PUT|DELETE|PATCH) \//,
  /(^|[\s('"])\/[\w.-]+\/[\w./-]*/,
  /\bslskd\b|\bSubsonic\b/i,
  /\banswered [1-5]\d\d\b|\bHTTP [1-5]\d\d\b/,
  //? another program's own words, relayed
  /\b(Navidrome|MusicBrainz) said\b/,
]

/** Whether `text` holds something a listener should never be shown as their line (see PLUMBING). */
export function plumbing(text: string | null | undefined): boolean {
  if (!text) return false
  return PLUMBING.some((pattern) => pattern.test(text))
}

const OFFLINE_WORDS = /Failed to fetch|Load failed|NetworkError|Network request failed|network connection was lost/i

/** fetch's own failure: the request never reached deadwax (a TypeError, in every browser's words). */
export function isOffline(error: unknown): boolean {
  return error instanceof TypeError && OFFLINE_WORDS.test(error.message)
}

/**
 * Whose answer an error was, from the route that gave it (ApiError's path): the Navidrome routes' the music
 * server's, the downloads' and slskd's the downloads', anything else deadwax's own.
 */
export function serviceOf(error: unknown): Service {
  const path = error instanceof ApiError ? error.path ?? '' : ''
  if (path.startsWith('/navidrome')) return 'music'
  if (path.startsWith('/download') || path.startsWith('/monitor_slskd')) return 'downloads'
  return 'deadwax'
}

/** Which class an error is (see the head of this file). */
export function errorKind(error: unknown): ErrorKind {
  if (error instanceof ApiError) {
    //? a refusal deadwax named a kind of (src/routes/people.py Refused, own_password's: {detail, kind}) is its own
    //? words for whoever asked, whatever its status - "Navidrome didn't answer in time, so deadwax can't tell whether
    //? your password changed..." says what to do, where "That took too long. Try again." would send them wrong
    if (error.kind && error.status !== 401 && fit(error.detail)) return 'refused'
    if (error.status === 401 || error.status === 403) return 'not-allowed'
    if (error.status === 404) return 'not-found'
    if (error.status === 408 || error.status === 504) return 'timeout'
    //? deadwax split it in two itself: its detail is written for anyone
    if (error.why && error.detail) return 'refused'
    //? deadwax's routes say why in their own words ("deadwax can't keep pins: its database isn't writable") - kept
    //? where they hold no plumbing; Navidrome's and slskd's own (an address, a setting, slskd) never pass
    if ((error.status === 502 || error.status === 503) && fit(error.detail)) return 'refused'

    if (error.status === 502 || error.status === 503) return 'unreachable'
    if (error.status >= 400 && error.status < 500 && fit(error.detail)) return 'refused'
    return 'other'
  }
  if (isOffline(error)) return 'offline'
  if ((error as { name?: unknown } | null)?.name === 'TimeoutError') return 'timeout'
  return 'other'
}

/** The first letter up, and a full stop where the server left none - its words as a sentence. */
export function asSentence(text: string): string {
  const trimmed = text.trim()
  if (!trimmed) return trimmed
  //? never "Deadwax" or "Slskd": both are lower-case names, at a sentence's start too
  const upper = /^(deadwax|slskd)\b/.test(trimmed) ? trimmed : trimmed.charAt(0).toUpperCase() + trimmed.slice(1)
  return /[.!?…]$/.test(upper) ? upper : `${upper}.`
}

/** The error's own words, as an admin is shown them: the server's why, else its detail, else the message. */
export function rawWords(error: unknown): string {
  if (error instanceof ApiError) return error.why || error.detail || error.message
  if (error instanceof Error) return error.message || error.name
  return String(error)
}

/** What went wrong, for the reader `options.admin` says. */
export function errorWords(error: unknown, options: ErrorOptions = {}): ErrorWords {
  const admin = options.admin === true
  const retry = options.retry === true
  const service = options.service ?? serviceOf(error)
  const kind = errorKind(error)
  const api = error instanceof ApiError ? error : null
  let text: string
  let advice: string
  switch (kind) {
    case 'offline':
      text = OFFLINE
      advice = retry ? OFFLINE_RETRY : OFFLINE_ADVICE
      break
    case 'timeout':
      text = TIMEOUT
      advice = retry ? '' : 'Try again.'
      break
    case 'unreachable':
      text = options.failed ?? DOWN[service]
      advice = retry ? (admin ? '' : KEEPS_TOLD) : admin ? 'Try again in a minute.' : `Try again in a minute - ${KEEPS}`
      break
    case 'not-found':
      //? the caller's own sentence; else deadwax's ("That playlist isn't on Navidrome any more"), else ours
      text = options.gone ?? (fit(api?.detail) ? api!.detail! : GONE)
      advice = ''
      break
    case 'not-allowed':
      text = api?.status === 401 ? SIGNED_OUT : fit(api?.detail) ? api!.detail! : NOT_ALLOWED
      advice = ''
      break
    case 'refused':
      //? the server's words as it wrote them - a name in them ("reel2reel refused") is never re-cased
      text = api?.detail ?? ''
      //? deadwax's own split 503 (a database it can't read, logins it can't run): only whoever runs it can fix it -
      //? and its own words for a 5xx, which may pass
      advice = !api || admin || api.status < 500 ? '' : api.why ? (api.status === 503 ? TELL : '') : KEEPS_TOLD
      break
    default:
      text = options.failed ?? OTHER
      advice = retry ? (admin ? '' : KEEPS_TOLD) : admin ? 'Try again.' : `Try again - ${KEEPS}`
  }
  const raw = rawWords(error).trim()
  const detail = admin && raw && raw !== text ? raw : null
  return { kind, text, advice, detail }
}

/** The sentence and its advice, as one line - a full stop between them where the server's words left none. */
export function said(words: Pick<ErrorWords, 'text' | 'advice'>): string {
  if (!words.advice) return words.text
  if (!words.text) return words.advice
  return `${/[.!?…]$/.test(words.text) ? words.text : `${words.text}.`} ${words.advice}`
}

/**
 * One line, for a store that keeps words rather than errors (the pins, a notice): `lead`, what went wrong and what
 * to do - and, for whoever runs deadwax, the error's own words in brackets after it.
 */
export function noticeWords(lead: string, error: unknown, options: ErrorOptions = {}): string {
  const words = errorWords(error, options)
  const line = [lead, said(words)].filter(Boolean).join(' ')
  return words.detail ? `${line} (${words.detail})` : line
}

/** Words a server answer may be shown by as they are: there, not FastAPI's bare "Not Found", and no plumbing. */
function fit(text: string | null | undefined): boolean {
  return !!text && text.trim() !== 'Not Found' && !plumbing(text)
}

/** Server words a listener may see as they are - or `fallback` in their place when they hold plumbing. */
export function safeWords(text: string | null | undefined, fallback: string): { text: string; detail: string | null } {
  const raw = (text ?? '').trim()
  if (!raw) return { text: fallback, detail: null }
  if (plumbing(raw)) return { text: fallback, detail: raw }
  return { text: raw, detail: null }
}

/* ===== a download's own reasons ===================================================================== */

/**
 * Why a download stopped, or why it didn't file, as the server writes it into the job's `error` - every
 * string src/poller.py, src/store.py (TRANSFER_FAILURE_REASONS) and src/routes/download.py write there -
 * in a listener's words. errors.sim reads them out of the Python and holds every one to a sentence here.
 * `tell`: only whoever runs deadwax can put it right.
 */
export const JOB_ERRORS: Readonly<Record<string, { text: string; tell?: boolean }>> = {
  //? store.py TRANSFER_FAILURE_REASONS - slskd's "Completed, <substate>"
  'the peer refused to send it': { text: 'The person sharing it refused to send it.' },
  'the peer stopped responding': { text: 'The person sharing it stopped responding.' },
  'the transfer errored': { text: 'The download broke off.' },
  'the transfer was cancelled': { text: 'The download was cancelled before it finished.' },
  //? poller.py: a failed file with no substate deadwax knows
  'the transfer failed': { text: "The download didn't finish." },
  //? poller.py: slskd listed none of its transfers for UNMATCHED_GRACE_POLLS - the peer gone, usually, but just as
  //? well slskd down or restarted (get_downloads answers [] on any failure), mid-download too: true of both (review)
  'no transfers reported by slskd': { text: 'deadwax lost track of this download - the person sharing it may have gone offline, or downloads stopped working for a while.' },
  //? routes/download.py: the ✕
  'cancelled from deadwax': { text: 'Cancelled.' },
  //? poller.py: downloaded, and nothing filed
  'dry run - not organized': { text: 'Downloaded, but not added to your library: deadwax is set to try filing without moving anything.', tell: true },
  'nothing could be organized, check SLSKD_DOWNLOAD_PATH': { text: "It downloaded, but deadwax couldn't find its files to add them to your library.", tell: true },
  [`deadwax stopped while filing this - check the library and slskd's folder`]: { text: 'deadwax stopped while it was adding this to your library.', tell: true },
}

/** "3 of 10 file(s) arrived" after a failure's reason (poller.py). */
const ARRIVED = /^(.*) \((\d+) of (\d+) file\(s\) arrived\)$/

export interface JobWords {
  /** the reason, for everyone */
  text: string
  /** only whoever runs deadwax can put it right: a listener is told so (TELL) */
  tell: boolean
  /** the job's own words, for someone who runs deadwax - null when the text is them */
  detail: string | null
}

/** A download's `error`, in a listener's words. Unknown words pass through when they are fit to (safeWords). */
export function jobErrorWords(error: string | null | undefined): JobWords {
  const raw = (error ?? '').trim()
  if (!raw) return { text: '', tell: false, detail: null }
  const arrived = ARRIVED.exec(raw)
  const reason = arrived ? arrived[1] ?? raw : raw
  const words = JOB_ERRORS[reason] ?? null
  let tell = words?.tell === true
  let text = words?.text ?? null
  if (!text) {
    //? the filing's own messages, which carry a number or an exception (poller.py)
    if (reason.startsWith('organize failed:')) {
      text = "It downloaded, but couldn't be added to your library."
      tell = true
    } else if (/^\d+ file\(s\) failed to organize, no track was filed$/.test(reason)) {
      text = "It downloaded, but none of its songs could be added to your library."
      tell = true
    } else if (/^\d+ file\(s\) failed to organize$/.test(reason)) {
      const count = Number(reason.split(' ')[0])
      text = `${count} ${count === 1 ? 'file' : 'files'} couldn't be added to your library.`
      tell = true
    } else if (/^all \d+ file\(s\) already existed, nothing was filed$/.test(reason)) {
      text = 'Its files were already in the collection, so nothing was added.'
    } else if (/^already in the store: all \d+ track\(s\) were already there, nothing was filed$/.test(reason)) {
      text = 'Every song was already in the collection, so nothing was added.'
    } else {
      const safe = safeWords(reason, "It stopped, and deadwax couldn't say why.")
      text = safe.text
      tell = safe.detail !== null
    }
  }
  if (arrived) {
    const done = Number(arrived[2])
    const total = Number(arrived[3])
    text = `${text} ${done} of ${total} ${total === 1 ? 'file' : 'files'} arrived.`
  }
  return { text, tell, detail: raw !== text ? raw : null }
}

/* ===== You -> Connections ======================================================================== */

/**
 * The short word on a Connections row for each code a ping answers with (src/api/slskd_endpoint.py ping,
 * src/api/musicbrainz_endpoint.py) - the sentence under it is the server's own (slskd's PING_WORDS) or,
 * for MusicBrainz, MUSICBRAINZ_LINES. Only an admin and someone with Settings and the log see these rows.
 */
export const PING_STATUS: Readonly<Record<string, string>> = {
  CONNECTION_ERROR: "Can't reach it",
  NOT_SET_UP: 'Not set up',
  '401': 'Key refused',
  '502': 'Not running',
  NOT_LOGGED_IN: 'Not on Soulseek',
  NOT_CONNECTED: 'Not on Soulseek',
  CONNECTING: 'Connecting…',
  NO_STATE: 'Unclear',
  UNKNOWN_HTTP_ERROR: 'Unexpected answer',
  UNKNOWN_ERROR: 'Unexpected problem',
  MAX_RETRIES_EXCEEDED: 'No answer',
  VALUE_ERROR: 'Not set up',
  '503': 'Busy',
  '429': 'Busy',
  '403': 'Refused',
  '400': 'Refused',
}

/** MusicBrainz's ping answers with the log's words (request_with_retries's, shared with every MusicBrainz
 *  question) - so its row's sentence is said here, by code. */
export const MUSICBRAINZ_LINES: Readonly<Record<string, string>> = {
  CONNECTION_ERROR: "deadwax can't reach MusicBrainz - check the container can reach the internet.",
  MAX_RETRIES_EXCEEDED: "MusicBrainz didn't answer after a few tries - it often goes away for a few minutes.",
  '503': 'MusicBrainz is busy - it often is for a few minutes at a time.',
  '429': 'MusicBrainz is asking deadwax to slow down - it will answer again shortly.',
  '403': "MusicBrainz turned deadwax away - usually the contact in MUSICBRAINZ_EMAIL (Server settings, Connections).",
  '400': 'MusicBrainz refused the question deadwax asked - the log has the details.',
  VALUE_ERROR: 'No contact is set for MusicBrainz - set MUSICBRAINZ_EMAIL in Server settings (Connections).',
  UNKNOWN_HTTP_ERROR: 'MusicBrainz answered with an error deadwax doesn\'t know - the log has the details.',
  UNKNOWN_ERROR: 'Asking MusicBrainz failed in a way deadwax doesn\'t know - the log has the details.',
}

/** A failed ping's row: its word, and the sentence under it. */
export function pingWords(service: 'musicbrainz' | 'slskd', code: string | number | null | undefined, error: string | null | undefined): { text: string; line: string | null } {
  const key = code === undefined || code === null ? '' : String(code)
  const text = PING_STATUS[key] ?? 'Not connected'
  //? slskd's sentence as the server wrote it (PING_WORDS, or slskd's own state in describe_server_state's words)
  const line = service === 'musicbrainz' ? MUSICBRAINZ_LINES[key] ?? (error || null) : error || null
  return { text, line }
}

/** A ping that got no answer from deadwax at all. */
export const PING_UNANSWERED = "Couldn't check"

/** The sentence under a "Couldn't check" row: what went wrong, and - the rows are only ever drawn for whoever runs
 *  deadwax - the ask's own words in brackets after it ("Error pinging slskd: ..."), as a one-line notice says them. */
export function unansweredLine(error: unknown): string {
  return noticeWords('', error, { admin: true })
}
