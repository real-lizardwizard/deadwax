import type { DownloadJob } from '../api/types'
import type { PendingDownload } from './downloadOverlay'
import { formatSpeed } from './format'
import { isActive } from './jobs'
import { grantWords, partlyWords } from './myLibrary'
import { CANCEL_WORDS, askedByText, cancelWords, type CancelWords } from './perPerson'
import { jobErrorWords, safeWords } from './errorWords'

/**
 * The app's Requests tab and Home's Arriving (2.0.0-player.12): which download goes under which
 * heading, and every word it says - pure, so ui/test/requests.sim.cjs pins the rules rather than
 * a phone.
 *
 * The input is exactly what useDownloadJobs gives - the polled jobs with the overlays laid on
 * (lib/downloadOverlay.ts), the downloads still asking slskd, the derived speeds - so every state
 * the main page's downloads panel showed has its words here too. (2.0.6, UX batch 3) In a listener's
 * words, never the pipeline's: starting… (was "asking slskd…"), didn't start (was "refused"),
 * cancelling… (leaving… for a cancel that only withdraws your request - 2.0.0-player.49), trying
 * another source… (was "trying next peer…"), trying again… (was "asking again…"), 2nd try (was "try 2"),
 * adding to your library… (was "organizing").
 *
 * - Downloading: bytes are moving (downloading, or queued with progress slskd reports before the
 *   poller has moved it on), or it is being filed (organizing).
 * - Waiting: queued in the peer's queue ("4th in their queue", or "starting" before slskd says
 *   where; "3 failed" in amber beside it when the peer has already refused some files), or asked
 *   for and slskd hasn't answered yet ("starting…").
 * - Needs attention: failed or cancelled - with "Another source · N left" when the list it was picked
 *   from has runners-up and "Same source again" always, the two routes the downloads panel's buttons
 *   use - and a request slskd refused, which isn't a job at all and has neither.
 * - Done: finished, newest first, said by how it ended (the server's `outcome`) and how long ago.
 *
 * ONE solid purple button on the screen (STYLE.md): only the first "Another source" is primary, and any
 * after it is tinted.
 *
 * ARRIVING - Home's section, and the Requests tab's badge - is the set the old Downloads badge
 * counts (downloadOverlay's activeCount): queued, downloading and organizing jobs that aren't
 * being cancelled, failed ones being retried, and requests still asking slskd. Home and the badge
 * must never count different things (the lesson of the metadata queue's badge, CLAUDE.md), so App
 * gives the badge THIS list's length - one list, read twice - and the sim holds it to activeCount
 * case by case. (Where the two could part - a retry's overlay left on a job that has since
 * finished, which activeCount still counts - the list is right: it is drawn under Done.)
 */

export type Section = 'downloading' | 'waiting' | 'attention' | 'done'

export const SECTIONS: readonly Section[] = ['downloading', 'waiting', 'attention', 'done']

export const SECTION_TITLES: Readonly<Record<Section, string>> = {
  downloading: 'Downloading',
  waiting: 'Waiting',
  attention: 'Needs attention',
  done: 'Done',
}

/** How many cards Home's Arriving shows; "See all" has the rest. */
export const ARRIVING_MAX = 3

/** A line in the ordinary grey, the warning amber, or the failure red. */
export type Tone = 'plain' | 'warning' | 'danger'

export interface RequestRow {
  /** stable across polls: the job's id, or the pending request's own key */
  key: string
  /** the job, for cancel and retry; null for a request slskd hasn't made a job of */
  jobId: number | null
  section: Section
  /** the album, and its edition where it has one: "Dummy · 2014 vinyl" */
  title: string
  artist: string
  /** the Cover Art Archive's front at 250px for the pressing, or null for the plain tile */
  cover: string | null
  /** under the title: who and from where ("Massive Attack · from mellotron"), or how it ended and when */
  line: string
  lineTone: Tone
  /** Needs attention: why it stopped, in red - (2.0.4) in a listener's words (lib/errorWords.ts jobErrorWords) */
  reason: string | null
  /** (2.0.4) ...only whoever runs deadwax can put it right: JobCard adds "Tell whoever runs deadwax." for anyone else */
  reasonTell: boolean
  /** (2.0.4) ...and the job's own words, which JobCard shows only to whoever runs deadwax - null when they're the reason */
  reasonDetail: string | null
  /** Needs attention: why the last retry didn't start it, in red, under the reason */
  problem: string | null
  /** (2.0.4) ...its own words, for whoever runs deadwax, when they weren't fit for the line */
  problemDetail: string | null
  /** the bar, 0-100 */
  progress: number
  /** Downloading: the monospace line, "6 of 10 files · 1.8 MB/s" */
  data: string | null
  /** an Arriving card's words at its right end: "6 of 10", "starting", "adding…" */
  brief: string
  /** the ✕: ready, waiting on the server (disabled), or none - nothing to cancel */
  cancel: 'ready' | 'cancelling' | null
  /** Needs attention's buttons, each with the words it shows now */
  nextPeer: { left: number; primary: boolean; label: string } | null
  askAgain: { label: string } | null
  /** a retry is under way: both buttons wait */
  busy: boolean
  /** being cancelled: drawn faded until the server agrees */
  dimmed: boolean
  /** counted by the badge and on Home: see ARRIVING above */
  arriving: boolean
  /** the album's own name, without the edition - what an album page opened from the row says first */
  album: string
  /** Done (2.0.0-player.17): the release it was, when the album it brought is in the library - filed,
   *  partly filed, or already there - so the row opens it (the id bridge finds Navidrome's album) */
  release: string | null
  /** ...and it was filed by this download: the row's ▶ plays it */
  plays: boolean
  /** with logins on (2.0.0-player.49), who asked (lib/perPerson.ts askedByText): an admin's row
   *  "Asked by ethan", "Asked by you and ethan"; a user's row of a download somebody else waits for
   *  too SHARED_TEXT ("Someone else asked for it too", nobody named) - null for one only you asked
   *  for, and with logins off */
  askedBy: string | null
  /** what the ✕ asks first, and its answer: a user's on a shared download leaves it, an admin's on one
   *  somebody else waits for cancels it for everyone (lib/perPerson.ts cancelWords) */
  cancelWords: CancelWords
}

export interface RequestsInput {
  jobs: readonly DownloadJob[]
  pending: readonly PendingDownload[]
  speeds: ReadonlyMap<number, number>
  cancelling: ReadonlySet<number>
  retrying: ReadonlySet<number>
  retryingSame: ReadonlySet<number>
  /** why a retry didn't start: deadwax's words, or (2.0.4) the hook's own sentence with the error's words beside it */
  retryProblems: ReadonlyMap<number, RetryProblem>
  /** (2.0.6) logins on with libraries of their own: what the server calls "your library" is the collection */
  personal?: boolean
}

/** (2.0.4) Why a retry didn't start: the retry route's own words, or a sentence with the error's own beside it. */
export type RetryProblem = string | { text: string; detail: string | null }

/** What a retry that couldn't start is said with when its words aren't fit for a listener's line. */
export const RETRY_FAILED = "The download couldn't be started."

/** (2.0.4) The retry routes' own words (src/poller.py) that name slskd - (2.0.6) or a peer - in a listener's; the rest
 *  are fit as written. */
export const RETRY_WORDS: Readonly<Record<string, string>> = {
  'slskd is still stopping the last attempt - try again in a moment': 'The last try is still stopping - try again in a moment.',
  'no other peers to try - search again for more': 'No other source to try - Get it again to search for more.',
  //? (2.0.6, review) src/poller.py MOVED_ON and CLEARED
  "this download has already moved on - it's been retried or restarted meanwhile": "It's already been tried again meanwhile.",
  'this download has been cleared from the list - search again to download it': "It's been cleared from the list - Get it again to download it.",
}

/** (2.0.6, review) The retry routes' words that carry a name or a path (src/store_index.py in_flight_words and
 *  already_have), by how they start: a source's name, "being filed", and a library folder's path - shown to a listener
 *  until now (safeWords catches only a path from the root) - in a listener's words; the route's own kept as the
 *  detail, for whoever runs deadwax. "your library" is the server's word for the whole store: with a library of your
 *  own it is the collection. */
function retryWordsStarting(problem: string, personal: boolean): string | null {
  if (problem.startsWith('already downloading from ')) return "It's already downloading."
  if (problem.startsWith('already downloaded from ')) return "It's already downloaded, and being added now."
  if (problem.startsWith('already in your library')) return personal ? "It's already in the collection." : "It's already in your library."
  return null
}

/** (2.0.6, UX batch 3) Needs attention's two buttons, and what each says while it runs: another source from the list
 *  it was picked from (was "Next peer · N left" / "Trying next peer…"), and the same source again ("Ask again" /
 *  "Asking again…"). */
export const ANOTHER_SOURCE = (left: number) => `Another source · ${left} left`
export const TRYING_ANOTHER = 'Trying another source…'
export const SAME_SOURCE = 'Same source again'
export const TRYING_SAME = 'Trying again…'

/** A retry's problem as the row says it, and its own words where they weren't fit to be (lib/errorWords.ts). */
export function retryProblemWords(problem: RetryProblem | undefined, personal = false): { text: string | null; detail: string | null } {
  if (problem === undefined) return { text: null, detail: null }
  if (typeof problem !== 'string') return problem
  const known = RETRY_WORDS[problem] ?? retryWordsStarting(problem, personal)
  if (known) return { text: known, detail: problem }
  const safe = safeWords(problem, RETRY_FAILED)
  //? fit as they are: the retry route's own words (and the hook's), kept as written
  return safe.detail === null ? { text: problem, detail: null } : safe
}

export interface RequestsView {
  sections: Readonly<Record<Section, readonly RequestRow[]>>
  /** everything the badge counts, in the order Home shows them */
  arriving: readonly RequestRow[]
  /** "Clear done" has something to clear: a finished, failed or cancelled job, or a refusal */
  clearable: boolean
  /** nothing at all to show */
  empty: boolean
}

const RETRYABLE = new Set(['failed', 'cancelled'])

const CAA = 'https://coverartarchive.org/release'

/** The pressing's front cover from the Cover Art Archive, 250px - or null with no release id. */
export function jobCoverUrl(releaseMbid: string | null | undefined): string | null {
  return releaseMbid ? `${CAA}/${encodeURIComponent(releaseMbid)}/front-250` : null
}

const plural = (count: number, one: string, many: string) => (count === 1 ? one : many)

/** "12 minutes ago", from an ISO timestamp; '' when it can't be read. Never in the future. */
export function ageText(iso: string | null | undefined, now: number): string {
  const then = iso ? Date.parse(iso) : NaN
  if (!Number.isFinite(then)) return ''
  const seconds = Math.max(0, Math.round((now - then) / 1000))
  if (seconds < 60) return 'just now'
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes} ${plural(minutes, 'minute', 'minutes')} ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} ${plural(hours, 'hour', 'hours')} ago`
  const days = Math.floor(hours / 24)
  return days === 1 ? 'yesterday' : `${days} days ago`
}

/**
 * How a finished download ended, in words, from the server's `outcome` - never read out of the
 * error text, which is shown only as the row's own words where no outcome names it.
 */
export function outcomeWords(job: Pick<DownloadJob, 'outcome' | 'error' | 'library' | 'mine'>): {
  text: string
  tone: Tone
  /** (2.0.4) only whoever runs deadwax can put it right: DoneRow tells anyone else so (jobErrorWords' tell) */
  tell?: boolean
  /** (2.0.4) the job's own words, which DoneRow draws under the line for whoever runs deadwax */
  detail?: string | null
} {
  //? (2.0.0-player.51, logins on) what its filing gave those who asked, where the server says
  const granted = grantWords(job)
  if (granted) return granted
  switch (job.outcome) {
    case 'filed':
      return { text: 'In your library', tone: 'plain' }
    case 'already_there':
      //? every track was already in the folder; the download happened, and nothing new was filed
      return { text: 'You already had it', tone: 'plain' }
    case 'partly_filed':
      //? (2.0.6, UX batch 3) in your library, but not whole: how many files didn't make it, in a listener's words
      //? (partlyWords - it said "Partly filed: 2 file(s) failed to organize"), the job's own for whoever runs deadwax
      return { text: `In your library - ${partlyWords(job.error)}`, tone: 'warning', detail: job.error || null }
    case 'interrupted':
      //? deadwax stopped while filing it: only whoever runs deadwax can look (it said "Interrupted while filing:
      //? check the library and slskd's folder" to everyone) - that, as the job's own words, is theirs
      return { text: 'Stopped while being added to your library', tone: 'warning', tell: true, detail: job.error || null }
    default:
      //? a dry run, nothing that could be filed, no track filed: (2.0.4) the row's words in a listener's
      //? (jobErrorWords - never "check SLSKD_DOWNLOAD_PATH" or an exception). With no words at all,
      //? organizing is off - ORGANIZE_MODE 'off', or LIBRARY_PATH or SLSKD_DOWNLOAD_PATH not set
      //? - their own words (SLSKD_DOWNLOAD_PATH, the exception) kept for whoever runs deadwax, the one who fixes it,
      //? as a Needs-attention reason keeps them (review: a Done row lost them)
      if (!job.error) return { text: 'Downloaded, but not added to your library', tone: 'warning', tell: true }
      {
        const why = jobErrorWords(job.error)
        return { text: why.text, tone: 'warning', tell: why.tell, detail: why.detail }
      }
  }
}

/** The badge's number: none at zero, and "99+" past 99. */
export function badgeText(count: number): string {
  if (!(count > 0)) return ''
  return count > 99 ? '99+' : String(count)
}

/** What VoiceOver hears for the Requests tab with its badge: "Requests, 2 arriving". */
export function badgeLabel(tab: string, count: number): string {
  return count > 0 ? `${tab}, ${count} arriving` : tab
}

const who = (artist: string, username: string, ...more: (string | null | false | undefined)[]) =>
  [artist, username ? `from ${username}` : '', ...more].filter(Boolean).join(' · ')

/** "2nd", "3rd", "11th", "21st" - (2.0.6) a place or a try, as a listener says it. */
export function ordinal(count: number): string {
  const tens = count % 100
  const suffix = tens >= 11 && tens <= 13 ? 'th' : count % 10 === 1 ? 'st' : count % 10 === 2 ? 'nd' : count % 10 === 3 ? 'rd' : 'th'
  return `${count}${suffix}`
}

const tryText = (job: DownloadJob) => ((job.attempt ?? 1) > 1 ? `${ordinal(job.attempt!)} try` : null)

const titleOf = (album: string | null | undefined, edition?: string | null) =>
  `${album || 'Unknown album'}${edition ? ` · ${edition}` : ''}`

const files = (done: number, total: number) => `${done} of ${total} ${plural(total, 'file', 'files')}`

/** Which heading a job goes under. */
export function sectionOf(job: Pick<DownloadJob, 'status' | 'progress' | 'outcome'>): Section {
  if (job.status === 'downloading' || job.status === 'organizing') return 'downloading'
  //? bytes moving before the poller has moved it on from queued (it looks every 5 s)
  if (job.status === 'queued') return (job.progress ?? 0) > 0 ? 'downloading' : 'waiting'
  if (RETRYABLE.has(job.status)) return 'attention'
  //? (2.0.0-player.51, logins on) downloaded, and nothing of it could be filed: it needs a look, and the
  //? next peer is offered - the plan's table
  if (job.outcome === 'not_filed') return 'attention'
  return 'done'
}

const blank = (key: string, jobId: number | null, section: Section, title: string, artist: string, album = ''): RequestRow => ({
  key, jobId, section, title, artist, cover: null, line: '', lineTone: 'plain', reason: null, reasonTell: false,
  reasonDetail: null, problem: null, problemDetail: null,
  progress: 0, data: null, brief: '', cancel: null, nextPeer: null, askAgain: null, busy: false, dimmed: false,
  arriving: false, album, release: null, plays: false, askedBy: null, cancelWords: CANCEL_WORDS,
})

/** The endings whose album is in the library (2.0.0-player.17): a Done row of one opens it... */
const IN_THE_LIBRARY = new Set(['filed', 'partly_filed', 'already_there'])
/** ...and the ones this download filed, which its ▶ plays. */
const FILED = new Set(['filed', 'partly_filed'])

function jobRow(job: DownloadJob, input: RequestsInput, now: number): RequestRow {
  const section = sectionOf(job)
  const row = blank(`job-${job.id}`, job.id, section, titleOf(job.album, job.edition), job.artist || '', job.album || '')
  row.cover = jobCoverUrl(job.release_mbid)
  row.askedBy = askedByText(job)
  row.cancelWords = cancelWords(job)
  const cancelling = input.cancelling.has(job.id)
  //? (2.0.0-player.49) a cancel that only withdraws your request says so while it is out
  const going = row.cancelWords.leaves ? 'leaving…' : 'cancelling…'
  const done = job.files_done ?? 0
  const total = job.files_total ?? 0

  if (section === 'downloading') {
    const organizing = job.status === 'organizing'
    const speed = input.speeds.get(job.id)
    row.line = who(row.artist, job.username, tryText(job))
    row.progress = organizing ? 100 : Math.min(100, Math.max(0, job.progress || 0))
    row.data = cancelling ? going
      : organizing ? `${files(done, total)} · adding to your library…`
      : [files(done, total), job.files_failed ? `${job.files_failed} failed` : null, speed ? formatSpeed(speed) : null]
        .filter(Boolean).join(' · ')
    row.brief = cancelling ? going : organizing ? 'adding…' : `${done} of ${total}`
    //? nothing in slskd is left to cancel once it is being filed, and the filing can't be stopped
    row.cancel = organizing ? null : cancelling ? 'cancelling' : 'ready'
    row.dimmed = cancelling
    row.arriving = !cancelling
    return row
  }

  if (section === 'waiting') {
    const place = job.queue_position ?? null
    const state = cancelling ? going : place !== null ? `${ordinal(place)} in their queue` : 'starting'
    //? files the peer already refused while the rest wait in its queue, said now, in amber - as the
    //? downloads panel says it: otherwise it reads as an ordinary wait right up until it fails
    const failed = !cancelling && job.files_failed ? `${job.files_failed} failed` : null
    row.line = who(row.artist, job.username, state, failed, tryText(job))
    if (failed) row.lineTone = 'warning'
    row.brief = cancelling ? going : place !== null ? `${ordinal(place)} in line` : 'starting'
    row.cancel = cancelling ? 'cancelling' : 'ready'
    row.dimmed = cancelling
    row.arriving = !cancelling
    return row
  }

  if (section === 'attention') {
    const retrying = input.retrying.has(job.id)
    const same = retrying && input.retryingSame.has(job.id)
    const left = job.alternatives_left ?? 0
    row.line = who(row.artist, job.username, tryText(job))
    //? (2.0.4) the server's words in a listener's (jobErrorWords), its own kept for whoever runs deadwax
    const why = jobErrorWords(job.error)
    row.reason = why.text || (job.status === 'cancelled' ? 'Cancelled' : 'It stopped without saying why')
    row.reasonTell = why.tell
    row.reasonDetail = why.detail
    const retried = retryProblemWords(input.retryProblems.get(job.id), input.personal)
    row.problem = retried.text
    row.problemDetail = retried.detail
    row.nextPeer = left > 0
      ? { left, primary: false, label: retrying && !same ? TRYING_ANOTHER : ANOTHER_SOURCE(left) }
      : null
    //? the same peer again is for a download that stopped - not one filing couldn't use (not_filed)
    row.askAgain = job.outcome === 'not_filed' ? null : { label: same ? TRYING_SAME : SAME_SOURCE }
    row.busy = retrying
    //? short, for an Arriving card's end, where a long word would squeeze the album's name
    row.brief = retrying ? 'retrying…' : ''
    //? being started again: counted as arriving from the click, as the badge counts it
    row.arriving = retrying
    return row
  }

  const outcome = outcomeWords(job)
  const age = ageText(job.updated_at, now)
  row.line = age ? `${outcome.text} · ${age}` : outcome.text
  row.lineTone = outcome.tone
  //? (2.0.4) a Done row that wasn't added: the tell and the job's own words, drawn under the line (JobCard DoneRow)
  row.reasonTell = outcome.tell === true
  row.reasonDetail = outcome.detail ?? null
  row.progress = 100
  //? the album it brought, where the library has it: the row opens it, and plays what was filed
  const release = (job.release_mbid ?? '').trim()
  if (release && job.outcome && IN_THE_LIBRARY.has(job.outcome)) {
    row.release = release
    row.plays = FILED.has(job.outcome)
  }
  return row
}

function pendingRow(pending: PendingDownload, personal = false): RequestRow {
  const refused = pending.error !== undefined
  const row = blank(pending.key, null, refused ? 'attention' : 'waiting', titleOf(pending.album), pending.artist || '', pending.album || '')
  if (refused) {
    row.line = who(row.artist, pending.username, "didn't start")
    //? (2.0.4) the hook's sentence for it (lib/errorWords.ts), the error's own words for whoever runs deadwax
    //? (2.0.6, review) /enqueue's 409 is already_have's words, as the retries' are: a source's name, "being filed", a
    //? folder's path - said as a retry's refusal is, the route's own kept for whoever runs deadwax
    const known = pending.error ? retryWordsStarting(pending.error, personal) : null
    row.reason = known ?? (pending.error || RETRY_FAILED)
    row.reasonDetail = known ? pending.error ?? null : pending.detail ?? null
    return row
  }
  row.line = who(row.artist, pending.username, 'starting…')
  row.brief = 'starting…'
  row.arriving = true
  return row
}

const updatedAt = (job: DownloadJob) => {
  const at = job.updated_at ? Date.parse(job.updated_at) : NaN
  return Number.isFinite(at) ? at : 0
}

/** Every download, under its heading, with its words. `now` is for "12 minutes ago". */
export function requestsView(input: RequestsInput, now: number): RequestsView {
  const jobs = [...input.jobs]
  const byId = new Map(jobs.map((job) => [job.id, job]))
  const rows = jobs.map((job) => jobRow(job, input, now))
  const pending = input.pending.map((each) => pendingRow(each, input.personal))
  const of = (section: Section, list: RequestRow[]) => list.filter((row) => row.section === section)

  const doneRows = of('done', rows).sort((a, b) => {
    const jobA = byId.get(a.jobId as number) as DownloadJob
    const jobB = byId.get(b.jobId as number) as DownloadJob
    return updatedAt(jobB) - updatedAt(jobA) || jobB.id - jobA.id
  })

  const attention = [...of('attention', pending), ...of('attention', rows)]
  //? one solid purple button on the screen: the first "Next peer", and the rest tinted
  const first = attention.find((row) => row.nextPeer)
  if (first?.nextPeer) first.nextPeer = { ...first.nextPeer, primary: true }

  const sections: Record<Section, RequestRow[]> = {
    downloading: of('downloading', rows),
    waiting: [...of('waiting', pending), ...of('waiting', rows)],
    attention,
    done: doneRows,
  }

  const arriving = [...sections.downloading, ...sections.waiting, ...sections.attention].filter((row) => row.arriving)

  return {
    sections,
    arriving,
    clearable: jobs.some((job) => !isActive(job)) || input.pending.some((p) => p.error !== undefined),
    empty: jobs.length === 0 && input.pending.length === 0,
  }
}

/** Home's cards: the first ARRIVING_MAX of what is arriving, or none - and then no section at all. */
export function arrivingCards(view: RequestsView): readonly RequestRow[] {
  return view.arriving.slice(0, ARRIVING_MAX)
}

/**
 * What the app is looking at, as far as downloads go: Requests (whose `open` polls by itself),
 * Home (whose Arriving wants a fresh answer as it comes into view), another tab, or nothing - the
 * page hidden, a locked phone.
 */
export type Watching = 'requests' | 'home' | 'other' | 'hidden'

/**
 * Watching, from what App shows. A tab counts only at its ROOT - an album pushed on it (Go to album
 * can push one on Requests) is 'other' - and only with Now Playing not over it; and nothing counts
 * while the page is hidden. So Requests' fast poll never runs behind a sheet, an album page or a
 * locked phone.
 */
export function watchingOf(shows: {
  /** the page is visible (visibilitychange) */
  shown: boolean
  /** the tab showing */
  tab: string
  /** how many pages are on it above its root */
  depth: number
  /** Now Playing is open over everything */
  sheetOpen: boolean
}): Watching {
  if (!shows.shown) return 'hidden'
  if (shows.depth > 0 || shows.sheetOpen) return 'other'
  return shows.tab === 'requests' ? 'requests' : shows.tab === 'home' ? 'home' : 'other'
}

/**
 * Whether App should keep the downloads polling although the Requests tab isn't showing: the last
 * look FAILED while something was on its way, and the app is on screen. useDownloadJobs stops for
 * good after a failed look in the background (nothing active seen, nothing open), which left
 * Home's Arriving and the badge frozen on the last answer after one blip - a Komodo redeploy, the
 * phone off the VPN for a moment. Asking with `open` until an answer comes keeps them honest; the
 * first answer turns this off again. Not while hidden (iOS suspends the page anyway), and not for
 * Requests, which polls by itself.
 */
export function stallsOn(watching: Watching, error: string | null, arriving: number): boolean {
  return (watching === 'home' || watching === 'other') && error !== null && arriving > 0
}

/** What a row is doing now, in a few words, for the page's announcement. */
function sectionWords(row: RequestRow): string {
  if (row.section === 'downloading') return 'downloading'
  if (row.section === 'waiting') return 'waiting'
  if (row.section === 'attention') return row.reason ? `needs attention: ${row.reason}` : 'needs attention'
  return row.line
}

/**
 * What changed between two looks at the Requests tab that a screen reader should hear, and which
 * rows moved to another heading. The page says it in one polite live region, since a card that
 * moves is drawn afresh in another list, and the button that was tapped goes with it; and it puts
 * focus back on a moved card whose control had it.
 *
 * - A row under another heading: "Heligoland: waiting", "...: needs attention: <why>",
 *   "...: In your library · just now".
 * - A retry's refusal appearing: "Heligoland: No other source would send it.".
 * - A tap's answer starting: "Heligoland: trying another source…", "...: trying again…",
 *   "...: cancelling…" ("...: leaving…" for a cancel that only withdraws your request) - the button
 *   tapped says it too, but its new name isn't read by itself.
 * - A row you were leaving gone from your list (2.0.0-player.49): "Heligoland: left - it carries on
 *   for whoever else asked" - the one way a tap on a card takes the card away.
 *
 * Any other row that has only just appeared, or has gone (cleared), says nothing. Empty `said` when
 * there is nothing to say. `gone` is every row of `before` that `now` hasn't got, with the row to put
 * focus on in its place (focusAfterGone) - for a page whose focus was in it.
 */
export function changes(before: RequestsView | null, now: RequestsView): { said: string; moved: string[]; gone: Map<string, string | null> } {
  if (!before || before === now) return { said: '', moved: [], gone: new Map() }
  const was = new Map<string, RequestRow>()
  for (const section of SECTIONS) for (const row of before.sections[section]) was.set(row.key, row)
  const phrases: string[] = []
  const moved: string[] = []
  const still = new Set<string>()
  for (const section of SECTIONS) {
    for (const row of now.sections[section]) {
      still.add(row.key)
      const prev = was.get(row.key)
      if (!prev) continue
      if (prev.section !== row.section) {
        moved.push(row.key)
        phrases.push(`${row.title}: ${sectionWords(row)}`)
      } else if (row.problem && row.problem !== prev.problem) {
        phrases.push(`${row.title}: ${row.problem}`)
      } else if (row.busy && !prev.busy) {
        const label = row.askAgain?.label === TRYING_SAME ? 'trying again…' : 'trying another source…'
        phrases.push(`${row.title}: ${label}`)
      } else if (row.cancel === 'cancelling' && prev.cancel !== 'cancelling') {
        phrases.push(`${row.title}: ${row.cancelWords.leaves ? 'leaving…' : 'cancelling…'}`)
      }
    }
  }
  const gone = new Map<string, string | null>()
  for (const [key, prev] of was) {
    if (still.has(key)) continue
    gone.set(key, focusAfterGone(before, now, key))
    if (prev.cancel === 'cancelling' && prev.cancelWords.leaves) phrases.push(`${prev.title}: left - it carries on for whoever else asked`)
  }
  return { said: phrases.join('. '), moved, gone }
}

/**
 * Where focus goes when the row `key` - in `before`, not in `now` - had it (2.0.0-player.49: a leave
 * takes the card away): the card that came after it under its heading, still there; else the one
 * before it; else the first card on the page; null with no card left (the page's heading then).
 */
export function focusAfterGone(before: RequestsView, now: RequestsView, key: string): string | null {
  const present = new Set<string>()
  for (const section of SECTIONS) for (const row of now.sections[section]) present.add(row.key)
  for (const section of SECTIONS) {
    const rows = before.sections[section]
    const at = rows.findIndex((row) => row.key === key)
    if (at < 0) continue
    const after = rows.slice(at + 1).find((row) => present.has(row.key))
    if (after) return after.key
    const earlier = rows.slice(0, at).reverse().find((row) => present.has(row.key))
    if (earlier) return earlier.key
  }
  for (const section of SECTIONS) {
    const first = now.sections[section][0]
    if (first) return first.key
  }
  return null
}

/**
 * Whether App should ask for the downloads again as what it shows goes from `before` to `now`,
 * so a download started on another device appears without a poll left running:
 *
 * - Home coming into view (a tab switch, back to its root, Now Playing closing over it) asks.
 * - The app coming back from the background asks, on any tab - the badge is on every one.
 * - Requests never needs to: useDownloadJobs polls the moment its `open` turns on. And nothing
 *   asks just after leaving Requests either, since `open` turning off polled once already.
 * - Nothing changed, or the page is hidden: nothing to ask.
 */
export function asksAgain(before: Watching, now: Watching): boolean {
  if (now === before || now === 'hidden' || now === 'requests' || before === 'requests') return false
  return now === 'home' || before === 'hidden'
}

/**
 * How long after a Done row first shows Navidrome is taken to have scanned what it filed: its watcher
 * waits about 5 s after a folder changes, then scans it (a second or so for one album).
 */
export const DONE_SCAN_SETTLE_MS = 10_000
/** Songs asked for longer ago than this, before the tab was last come back to, are asked again. */
export const DONE_FRESH_MS = 30_000
/** A look that found no album: the next after this, doubling, to DONE_RETRY_MAX_MS. */
export const DONE_RETRY_MS = 5_000
export const DONE_RETRY_MAX_MS = 60_000

/** What the Requests tab holds of its Done rows' albums, by release, for doneLooks. */
export interface DoneHeld {
  /** Navidrome's album id, once the id bridge found it */
  ids: ReadonlyMap<string, string>
  /** when the album's songs were last asked for (ms, this device's clock) */
  asked: ReadonlyMap<string, number>
  /** looks in a row that found no album: how many, and when the last was */
  misses: ReadonlyMap<string, { count: number; at: number }>
  /** asked for now: not asked again until it answers */
  inFlight: ReadonlySet<string>
  /** when the tab last came into view (ms): songs asked long before it are asked again */
  activeSince: number
}

/**
 * What the Requests tab asks about its first Done rows' albums now, and when it should look again
 * (2.0.0-player.17, review). Each row is its release and when it first showed as done (`since`, this
 * device's clock - never the server's, whose clock can differ: 0 for a row already done as the page
 * loaded). For each release, the newest row's:
 *
 *  - no Navidrome id yet: `look` it up (the id bridge) - but not before Navidrome can have scanned
 *    what the row filed, and after a look that found nothing, again only after DONE_RETRY_MS,
 *    doubling to DONE_RETRY_MAX_MS. The first look straight after filing always missed, and nothing
 *    ever asked again, so a ▶ on an album filed while you watched only ever opened it;
 *  - an id: its `songs` asked for when never asked, when asked before Navidrome can have scanned
 *    what the newest row filed (a second download of the release filling the first's gaps), and
 *    when asked longer ago than DONE_FRESH_MS before the tab last came into view - so a ▶ plays the
 *    album as Navidrome has it, not as it was an hour ago.
 *
 * `nextIn`: how long until the soonest look falls due (a miss backing off, an ask too early), or
 * null for none - the tab looks again then, while it shows. Pure; requests.sim.cjs pins it.
 */
export function doneLooks(
  rows: readonly { release: string; since: number }[], held: DoneHeld, now: number,
): { look: string[]; songs: string[]; nextIn: number | null } {
  const since = new Map<string, number>()
  for (const row of rows) since.set(row.release, Math.max(since.get(row.release) ?? 0, row.since))
  const look: string[] = []
  const songs: string[] = []
  let due: number | null = null
  const later = (at: number) => {
    due = due === null ? at : Math.min(due, at)
  }
  for (const [release, at] of since) {
    if (held.inFlight.has(release)) continue
    const scanned = at + DONE_SCAN_SETTLE_MS
    if (!held.ids.has(release)) {
      const miss = held.misses.get(release)
      const backoff = miss ? miss.at + Math.min(DONE_RETRY_MS * 2 ** Math.max(0, miss.count - 1), DONE_RETRY_MAX_MS) : 0
      const when = Math.max(scanned, backoff)
      if (now >= when) look.push(release)
      else later(when)
      continue
    }
    const asked = held.asked.get(release)
    if (asked === undefined || asked < held.activeSince - DONE_FRESH_MS) songs.push(release)
    else if (asked < scanned) {
      if (now >= scanned) songs.push(release)
      else later(scanned)
    }
  }
  return { look, songs, nextIn: due === null ? null : Math.max(0, due - now) }
}
