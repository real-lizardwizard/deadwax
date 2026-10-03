import type { DownloadJob } from '../api/types'
import type { PendingDownload } from './downloadOverlay'
import { formatSpeed } from './format'
import { isActive } from './jobs'

/**
 * The app's Requests tab and Home's Arriving (2.0.0-player.12): which download goes under which
 * heading, and every word it says - pure, so ui/test/requests.sim.cjs pins the rules rather than
 * a phone.
 *
 * The input is exactly what useDownloadJobs gives - the polled jobs with the overlays laid on
 * (lib/downloadOverlay.ts), the downloads still asking slskd, the derived speeds - so every state
 * the main page's downloads panel shows has its words here too: asking slskd…, refused,
 * cancelling…, trying next peer…, asking again…, try N, organizing.
 *
 * - Downloading: bytes are moving (downloading, or queued with progress slskd reports before the
 *   poller has moved it on), or it is being filed (organizing).
 * - Waiting: queued in the peer's queue ("#4 in their queue", or "starting" before slskd says
 *   where; "3 failed" in amber beside it when the peer has already refused some files), or asked
 *   for and slskd hasn't answered yet ("asking slskd…").
 * - Needs attention: failed or cancelled - with "Next peer · N left" when the list it was picked
 *   from has runners-up and "Ask again" always, the two routes the downloads panel's buttons use -
 *   and a request slskd refused, which isn't a job at all and has neither.
 * - Done: finished, newest first, said by how it ended (the server's `outcome`) and how long ago.
 *
 * ONE solid purple button on the screen (STYLE.md): only the first "Next peer" is primary, and any
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
  /** Needs attention: why it stopped, in red */
  reason: string | null
  /** Needs attention: why the last retry didn't start it, in red, under the reason */
  problem: string | null
  /** the bar, 0-100 */
  progress: number
  /** Downloading: the monospace line, "6 of 10 files · 1.8 MB/s" */
  data: string | null
  /** an Arriving card's words at its right end: "6 of 10", "starting", "organizing" */
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
}

export interface RequestsInput {
  jobs: readonly DownloadJob[]
  pending: readonly PendingDownload[]
  speeds: ReadonlyMap<number, number>
  cancelling: ReadonlySet<number>
  retrying: ReadonlySet<number>
  retryingSame: ReadonlySet<number>
  retryProblems: ReadonlyMap<number, string>
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
export function outcomeWords(job: Pick<DownloadJob, 'outcome' | 'error'>): { text: string; tone: Tone } {
  switch (job.outcome) {
    case 'filed':
      return { text: 'In your library', tone: 'plain' }
    case 'already_there':
      //? every track was already in the folder; the download happened, and nothing new was filed
      return { text: 'Already in your library, nothing filed', tone: 'plain' }
    case 'partly_filed':
      return { text: job.error ? `Partly filed: ${job.error}` : 'Partly filed', tone: 'warning' }
    case 'interrupted':
      return { text: "Interrupted while filing: check the library and slskd's folder", tone: 'warning' }
    default:
      //? a dry run, nothing that could be filed, no track filed: the row's words. With no words at
      //? all, organizing is off - ORGANIZE_MODE 'off', or LIBRARY_PATH or SLSKD_DOWNLOAD_PATH not set
      return job.error ? { text: `Not filed: ${job.error}`, tone: 'warning' } : { text: 'Downloaded, not filed', tone: 'warning' }
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

const tryText = (job: DownloadJob) => ((job.attempt ?? 1) > 1 ? `try ${job.attempt}` : null)

const titleOf = (album: string | null | undefined, edition?: string | null) =>
  `${album || 'Unknown album'}${edition ? ` · ${edition}` : ''}`

const files = (done: number, total: number) => `${done} of ${total} ${plural(total, 'file', 'files')}`

/** Which heading a job goes under. */
export function sectionOf(job: Pick<DownloadJob, 'status' | 'progress'>): Section {
  if (job.status === 'downloading' || job.status === 'organizing') return 'downloading'
  //? bytes moving before the poller has moved it on from queued (it looks every 5 s)
  if (job.status === 'queued') return (job.progress ?? 0) > 0 ? 'downloading' : 'waiting'
  if (RETRYABLE.has(job.status)) return 'attention'
  return 'done'
}

const blank = (key: string, jobId: number | null, section: Section, title: string, artist: string, album = ''): RequestRow => ({
  key, jobId, section, title, artist, cover: null, line: '', lineTone: 'plain', reason: null, problem: null,
  progress: 0, data: null, brief: '', cancel: null, nextPeer: null, askAgain: null, busy: false, dimmed: false,
  arriving: false, album, release: null, plays: false,
})

/** The endings whose album is in the library (2.0.0-player.17): a Done row of one opens it... */
const IN_THE_LIBRARY = new Set(['filed', 'partly_filed', 'already_there'])
/** ...and the ones this download filed, which its ▶ plays. */
const FILED = new Set(['filed', 'partly_filed'])

function jobRow(job: DownloadJob, input: RequestsInput, now: number): RequestRow {
  const section = sectionOf(job)
  const row = blank(`job-${job.id}`, job.id, section, titleOf(job.album, job.edition), job.artist || '', job.album || '')
  row.cover = jobCoverUrl(job.release_mbid)
  const cancelling = input.cancelling.has(job.id)
  const done = job.files_done ?? 0
  const total = job.files_total ?? 0

  if (section === 'downloading') {
    const organizing = job.status === 'organizing'
    const speed = input.speeds.get(job.id)
    row.line = who(row.artist, job.username, tryText(job))
    row.progress = organizing ? 100 : Math.min(100, Math.max(0, job.progress || 0))
    row.data = cancelling ? 'cancelling…'
      : organizing ? `${files(done, total)} · organizing`
      : [files(done, total), job.files_failed ? `${job.files_failed} failed` : null, speed ? formatSpeed(speed) : null]
        .filter(Boolean).join(' · ')
    row.brief = cancelling ? 'cancelling…' : organizing ? 'organizing' : `${done} of ${total}`
    //? nothing in slskd is left to cancel once it is being filed, and the filing can't be stopped
    row.cancel = organizing ? null : cancelling ? 'cancelling' : 'ready'
    row.dimmed = cancelling
    row.arriving = !cancelling
    return row
  }

  if (section === 'waiting') {
    const place = job.queue_position ?? null
    const state = cancelling ? 'cancelling…' : place !== null ? `#${place} in their queue` : 'starting'
    //? files the peer already refused while the rest wait in its queue, said now, in amber - as the
    //? downloads panel says it: otherwise it reads as an ordinary wait right up until it fails
    const failed = !cancelling && job.files_failed ? `${job.files_failed} failed` : null
    row.line = who(row.artist, job.username, state, failed, tryText(job))
    if (failed) row.lineTone = 'warning'
    row.brief = cancelling ? 'cancelling…' : place !== null ? `#${place} in queue` : 'starting'
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
    row.reason = job.error || (job.status === 'cancelled' ? 'Cancelled' : 'It stopped without saying why')
    row.problem = input.retryProblems.get(job.id) ?? null
    row.nextPeer = left > 0
      ? { left, primary: false, label: retrying && !same ? 'Trying next peer…' : `Next peer · ${left} left` }
      : null
    row.askAgain = { label: same ? 'Asking again…' : 'Ask again' }
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
  row.progress = 100
  //? the album it brought, where the library has it: the row opens it, and plays what was filed
  const release = (job.release_mbid ?? '').trim()
  if (release && job.outcome && IN_THE_LIBRARY.has(job.outcome)) {
    row.release = release
    row.plays = FILED.has(job.outcome)
  }
  return row
}

function pendingRow(pending: PendingDownload): RequestRow {
  const refused = pending.error !== undefined
  const row = blank(pending.key, null, refused ? 'attention' : 'waiting', titleOf(pending.album), pending.artist || '', pending.album || '')
  if (refused) {
    row.line = who(row.artist, pending.username, 'refused')
    row.reason = pending.error || 'slskd refused it'
    return row
  }
  row.line = who(row.artist, pending.username, 'asking slskd…')
  row.brief = 'asking slskd…'
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
  const pending = input.pending.map(pendingRow)
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
 * - A retry's refusal appearing: "Heligoland: no other peer would take it".
 * - A tap's answer starting: "Heligoland: trying next peer…", "...: asking again…",
 *   "...: cancelling…" - the button tapped says it too, but its new name isn't read by itself.
 *
 * A row that has only just appeared, or has gone (cleared), says nothing. Empty `said` when there
 * is nothing to say.
 */
export function changes(before: RequestsView | null, now: RequestsView): { said: string; moved: string[] } {
  if (!before || before === now) return { said: '', moved: [] }
  const was = new Map<string, RequestRow>()
  for (const section of SECTIONS) for (const row of before.sections[section]) was.set(row.key, row)
  const phrases: string[] = []
  const moved: string[] = []
  for (const section of SECTIONS) {
    for (const row of now.sections[section]) {
      const prev = was.get(row.key)
      if (!prev) continue
      if (prev.section !== row.section) {
        moved.push(row.key)
        phrases.push(`${row.title}: ${sectionWords(row)}`)
      } else if (row.problem && row.problem !== prev.problem) {
        phrases.push(`${row.title}: ${row.problem}`)
      } else if (row.busy && !prev.busy) {
        const label = row.askAgain?.label === 'Asking again…' ? 'asking again…' : 'trying next peer…'
        phrases.push(`${row.title}: ${label}`)
      } else if (row.cancel === 'cancelling' && prev.cancel !== 'cancelling') {
        phrases.push(`${row.title}: cancelling…`)
      }
    }
  }
  return { said: phrases.join('. '), moved }
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
