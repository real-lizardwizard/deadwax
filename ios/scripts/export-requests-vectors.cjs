#!/usr/bin/env node
/**
 * Requests, for the iPhone app (Phase 6, slice 1 - notes/ios-specs/phase6-get-requests.md 6.1): what the web app's own
 * TypeScript answers, written as a fixture for the Swift ports in ios/DeadwaxKit/Sources/DeadwaxCore (Requests.swift,
 * RequestOverlays.swift) to replay (Tests/DeadwaxCoreTests/RequestsVectorTests.swift) - so the phone's Requests tab
 * draws every download under the heading, and with the words, the web's board does.
 *
 * Compiles lib/requestsView.ts, lib/downloadOverlay.ts, lib/speed.ts, lib/permissions.ts and lib/libraryEvents.ts with
 * what they import (perPerson, myLibrary, errorWords, format, jobs), and reads the numbers and words that live in
 * components and the hook - useDownloadJobs.ts's cadences and refusals, Requests.tsx's lines, JobCard.tsx's, You.tsx's
 * and ConfirmCancelChoice.tsx's, the tab's label - from their source. Writes
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/requests/requests-vectors.json:
 *
 *   numbers     the poll's cadences, the overlays' 15 s, Arriving's three, the Done rows' looks' numbers
 *   words       the headings, the retry words, the cancel words, who asked, every line of Requests.tsx, the hook's
 *               refusals, the cards' words, Confirm before cancelling and its note, the tab's label, GET_OFF
 *   ordinals, badges, speeds, ages, partly, outcomes, problems, people, sections
 *               each rule over its inputs
 *   boards      whole boards from seeded random inputs: every row's every field, what is arriving, clearable, empty,
 *               and the old badge's activeCount over the same overlays
 *   changes     runs of boards: what a screen reader hears between each two, what moved and what went
 *   overlays    reconcile and the views of the overlays over seeded jobs; settlePending and withoutRefused
 *   speeds      sampleSpeeds over traces of polls
 *   watching    watchingOf, stallsOn and asksAgain over every combination
 *   looks       doneLooks over seeded rows and what the tab holds
 *   filed       libraryEvents.ts's newlyOrganized over runs of polls: the albums each saw filed
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any machine
 * writes the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-requests-vectors.cjs           write the fixture
 *   node ios/scripts/export-requests-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'requests', 'requests-vectors.json')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-requests-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/requestsView.ts', 'src/lib/downloadOverlay.ts', 'src/lib/speed.ts', 'src/lib/permissions.ts',
  'src/lib/libraryEvents.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const V = require(path.join(OUT, 'lib/requestsView.js'))
const O = require(path.join(OUT, 'lib/downloadOverlay.js'))
const S = require(path.join(OUT, 'lib/speed.js'))
const P = require(path.join(OUT, 'lib/perPerson.js'))
const M = require(path.join(OUT, 'lib/myLibrary.js'))
const F = require(path.join(OUT, 'lib/format.js'))
const E = require(path.join(OUT, 'lib/errorWords.js'))
const G = require(path.join(OUT, 'lib/permissions.js'))
const L = require(path.join(OUT, 'lib/libraryEvents.js'))

/** A line of a component's source, which the exporter can't compile without Preact - the first match's group. */
function sourceMatch(file, pattern) {
  const text = fs.readFileSync(path.join(UI, file), 'utf8')
  const found = text.match(pattern)
  if (!found) throw new Error(`${file} no longer has ${pattern}`)
  return found[1]
}

/** Whether a component's source still says `words` - for the words it builds inline. */
function sourceHas(file, words) {
  if (!fs.readFileSync(path.join(UI, file), 'utf8').includes(words)) throw new Error(`${file} no longer says ${words}`)
  return words
}

/* ===== seeded randomness ===== */

let seed = 6606
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/* ===== the numbers and the words ===== */

const NOW = 1794000000000

function numbers() {
  const hook = 'src/hooks/useDownloadJobs.ts'
  return {
    pollOpenMs: Number(sourceMatch(hook, /const POLL_OPEN_MS = (\d+)/)),
    pollBackgroundMs: Number(sourceMatch(hook, /const POLL_BACKGROUND_MS = (\d+)/)),
    pollFilingMs: Number(sourceMatch(hook, /const POLL_FILING_MS = (\d+)/)),
    optimisticTtlMs: Number(sourceMatch(hook, /const OPTIMISTIC_TTL_MS = (\d+)/)),
    arrivingMax: V.ARRIVING_MAX,
    donePrefetched: Number(sourceMatch('src/app/Requests.tsx', /export const DONE_PREFETCHED = (\d+)/)),
    doneScanSettleMs: V.DONE_SCAN_SETTLE_MS,
    doneFreshMs: V.DONE_FRESH_MS,
    doneRetryMs: V.DONE_RETRY_MS,
    doneRetryMaxMs: V.DONE_RETRY_MAX_MS,
  }
}

const squash = (text) => text.replace(/\s+/g, ' ').trim()

function words() {
  const page = 'src/app/Requests.tsx'
  const hook = 'src/hooks/useDownloadJobs.ts'
  const card = 'src/app/JobCard.tsx'
  const untrackedRuns = sourceMatch(page, /\{runs \? \(\s*<p class="app-placeholder-text">([\s\S]*?)<\/p>/)
  return {
    tab: sourceMatch('src/lib/appRoutes.ts', /requests: '([^']+)'/),
    sections: V.SECTIONS.map((section) => ({ section, title: V.SECTION_TITLES[section] })),
    retryFailed: V.RETRY_FAILED,
    retryWords: Object.entries(V.RETRY_WORDS).map(([said, words]) => ({ said, words })),
    anotherSource: [1, 2, 10].map((left) => ({ left, said: V.ANOTHER_SOURCE(left) })),
    tryingAnother: V.TRYING_ANOTHER,
    sameSource: V.SAME_SOURCE,
    tryingSame: V.TRYING_SAME,
    cancel: P.CANCEL_WORDS,
    shared: P.SHARED_TEXT,
    nobody: P.NOBODY_TEXT,
    getOff: G.GET_OFF,
    tell: E.TELL,
    notInNavidrome: sourceMatch(page, /export const NOT_IN_NAVIDROME = '([^']+)'/),
    notInStore: sourceMatch(page, /export const NOT_IN_STORE = "([^"]+)"/),
    notLookedUp: sourceMatch(page, /export const NOT_LOOKED_UP = "([^"]+)"/),
    cantOpenUnset: sourceMatch(page, /export const CANT_OPEN_UNSET = "([^"]+)"/),
    cantOpenDown: sourceMatch(page, /export const CANT_OPEN_DOWN = "([^"]+)"/),
    cantOpenOffline: sourceMatch(page, /export const CANT_OPEN_OFFLINE = "([^"]+)"/),
    empty: sourceMatch(page, /export const REQUESTS_EMPTY = "([^"]+)"/),
    emptyJoin: sourceHas(page, 'export const REQUESTS_EMPTY_JOIN = GET_OFF') && G.GET_OFF,
    nothingYet: sourceMatch(page, /<p class="app-placeholder-lead">(Nothing requested yet)<\/p>/),
    unreached: sourceMatch(page, /export const REQUESTS_UNREACHED = "([^"]+)"/),
    keepsAsking: sourceMatch(page, /\? '(It keeps asking while this tab is open\.)'/),
    keepsAskingBelow: sourceMatch(page, /: "(It keeps asking while this tab is open; what's below is from the last answer\.)"/),
    untracked: sourceMatch(page, /export const UNTRACKED = "([^"]+)"/),
    untrackedText: `${sourceMatch(page, /export const UNTRACKED_TEXT = `([^$`]+)\$\{TELL\}`/)}${E.TELL}`,
    untrackedRuns: squash(untrackedRuns.replace(/<span class="app-mono">([^<]*)<\/span>/, '$1')),
    sameRefused: sourceMatch(hook, /giveUp\(outcome\.problem \?\? '([^']+)'\)\s*\n\s*\} else/),
    nextRefused: sourceMatch(hook, /else giveUp\(outcome\.problem \?\? '([^']+)'\)\s*\n\s*\}\s*\n\s*\} catch/),
    retryBroke: sourceMatch(hook, /service: 'downloads', failed: "(That didn't work\.)", admin: true/),
    enqueueBroke: sourceMatch(hook, /service: 'downloads', failed: "(The download couldn't be started\.)", admin: true/),
    keepIt: sourceMatch(card, /<span class="app-job-action-label">(Keep it)<\/span>/),
    leave: sourceMatch(card, /\$\{row\.cancelWords\.leaves \? '(Leave)' : 'Cancel'\} \$\{row\.title\}`/),
    cancelVerb: sourceMatch(card, /\$\{row\.cancelWords\.leaves \? 'Leave' : '(Cancel)'\} \$\{row\.title\}`/),
    play: sourceMatch(card, /aria-label=\{`(Play) \$\{row\.title\}`\}/),
    confirmCancel: sourceMatch('src/app/ConfirmCancelChoice.tsx', /<span class="app-check-label">([^<]+)<\/span>/),
    confirmCancelNote: squash(sourceMatch('src/app/You.tsx', /<p id="app-confirm-cancel-note" class="app-footnote">([\s\S]*?)<\/p>/)),
    confirmCancelKey: sourceMatch('src/state/persisted.ts', /playerConfirmCancel: '([^']+)'/),
    gettingAlbums: squash(sourceMatch('src/app/You.tsx', /<h2 id="app-getting-title" class="app-section-title">([\s\S]*?)<\/h2>/)),
  }
}

/* ===== the small rules ===== */

const ordinals = () => [...Array(131).keys(), 211, 212, 213, 1001, 1011, 1012, 1013, 1021, 10111].map((n) => ({ n, said: V.ordinal(n) }))

const badges = () => [-3, 0, 1, 2, 9, 42, 99, 100, 101, 1000].map((count) => ({
  count, text: V.badgeText(count), label: V.badgeLabel('Requests', count),
}))

const speeds = () => [0, 1, 512, 1023, 1024, 1536, 10239, 524287.5, 1048063, 1048064, 1048575, 1048576, 1887436.8,
  5242880, 10485759, 104857600, 1073741824].map((bytes) => ({ bytes, said: F.formatSpeed(bytes) }))

const iso = (ms) => new Date(ms).toISOString()
const plusZero = (ms) => iso(ms).replace(/\.\d{3}Z$/, '+00:00')

function ages() {
  const offsets = [0, 400, 29499, 29500, 59000, 59499, 59500, 60000, 61000, 119000, 3599000, 3599500, 3600000,
    7199000, 86399000, 86400000, 172799000, 172800000, 864000000, -5000, -90000000]
  const out = []
  for (const back of offsets) {
    out.push({ iso: iso(NOW - back), now: NOW, said: V.ageText(iso(NOW - back), NOW) })
    out.push({ iso: plusZero(NOW - back - 123), now: NOW, said: V.ageText(plusZero(NOW - back - 123), NOW) })
  }
  for (const odd of [null, '', 'nope', '2026-13-01T00:00:00+00:00', '2026-11-14T10:00:00.5+01:00', '2026-11-14T10:00:00Z']) {
    out.push({ iso: odd, now: NOW, said: V.ageText(odd, NOW) })
  }
  return out
}

const PARTLY = [null, '', '2 file(s) failed to organize', '1 file(s) failed to organize: disc 2', '  12 file(s) failed to organize',
  'Partly filed: 3 file(s) failed to organize', 'x file(s) failed to organize', '0 file(s) failed to organize']

const partly = () => PARTLY.map((error) => ({ error, said: M.partlyWords(error) }))

const ERRORS = [null, '', 'the peer refused to send it', 'the peer stopped responding', 'the transfer errored',
  'no transfers reported by slskd', '2 file(s) failed to organize', 'organize failed: [Errno 13] Permission denied: /music',
  'cancelled from deadwax', 'Interrupted while filing: check the library and slskd\'s folder',
  'nothing that could be filed in /downloads/x', 'Something nobody wrote down', 'Traceback (most recent call last): boom']
const OUTCOMES = [undefined, null, 'filed', 'already_there', 'partly_filed', 'interrupted', 'failed', 'not_filed', 'odd']
const LIBRARIES = [undefined, null, 'added', 'incomplete', 'flagged', 'looked']

function outcomes() {
  const out = []
  for (const outcome of OUTCOMES) {
    for (const error of ERRORS) {
      for (const library of LIBRARIES) {
        for (const mine of [undefined, true, false]) {
          if (!chance(0.18) && !(library === undefined && mine === undefined)) continue
          const job = clean({ outcome, error, library, mine })
          out.push({ job, ...V.outcomeWords(job) })
        }
      }
    }
  }
  return out
}

const PROBLEMS = [
  ...Object.keys(V.RETRY_WORDS),
  'already downloading from mellotron', 'already downloaded from mellotron - being filed', 'already in your library',
  'already in your library: /music/Portishead/Dummy (1994)', 'mellotron refused', 'slskd refused: peer offline',
  '', '   ', '/config/deadwax.db is locked', 'Traceback (most recent call last): boom', 'They refused - try another source.',
]

function problems() {
  const out = []
  for (const problem of PROBLEMS) {
    for (const personal of [false, true]) out.push({ problem, personal, ...V.retryProblemWords(problem, personal) })
  }
  out.push({ problem: { text: "That didn't work.", detail: 'POST /download/jobs/3/retry failed' }, personal: false,
    ...V.retryProblemWords({ text: "That didn't work.", detail: 'POST /download/jobs/3/retry failed' }) })
  out.push({ problem: { text: 'Can\'t connect to deadwax.', detail: null }, personal: true,
    ...V.retryProblemWords({ text: 'Can\'t connect to deadwax.', detail: null }, true) })
  return out
}

const ASKERS = [undefined, [], ['ethan'], ['ethan', 'sam'], ['ethan', 'sam', 'jo']]

function people() {
  const out = []
  for (const mine of [undefined, true, false]) {
    for (const shared of [undefined, true, false]) {
      for (const requested_by of ASKERS) {
        const job = clean({ mine, shared, requested_by })
        out.push({ job, askedBy: P.askedByText(job), cancel: P.cancelWords(job), leaves: P.leavesOnCancel(job) })
      }
    }
  }
  return out
}

const STATUSES = ['queued', 'downloading', 'organizing', 'organized', 'complete', 'failed', 'cancelled', 'paused']

function sections() {
  const out = []
  for (const status of STATUSES) {
    for (const progress of [undefined, 0, 0.5, 100]) {
      for (const outcome of OUTCOMES) {
        const job = clean({ status, progress, outcome })
        out.push({ job, section: V.sectionOf(job) })
      }
    }
  }
  return out
}

/** Undefined fields left out, as JSON leaves them. */
function clean(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined))
}

/* ===== whole boards ===== */

const ARTISTS = ['Massive Attack', 'Portishead', '', 'Björk', 'Sigur Rós']
const ALBUMS = ['Mezzanine', 'Dummy', '', 'Homogenic', '( )', 'Blue Lines']
const EDITIONS = [undefined, null, '', '2014 vinyl', 'Deluxe']
const USERS = ['mellotron', 'cratedigger', '', 'vinylhead']
const RELEASES = [undefined, null, '', '  ', '76df3287-6cda-33eb-8e9a-044b5e15ffdd', ' 8d1b2a33-12f0-4f21-9d7e-1e0c5e1c8b1a ', 'a b/c']
const JOB_ERRORS = ERRORS
const PENDING_ERRORS = [undefined, undefined, '', "The download couldn't be started.", 'already downloading from mellotron',
  'already in your library: /music/x', "That didn't work.", 'mellotron refused']

function seededJob(id) {
  const status = pick(STATUSES)
  const total = pick([0, 1, 10, 12])
  const job = {
    id,
    artist: pick(ARTISTS),
    album: pick(ALBUMS),
    year: pick([null, '1994']),
    username: pick(USERS),
    directory: 'music\\x',
    status,
    error: pick(JOB_ERRORS),
    created_at: iso(NOW - between(0, 99) * 60000),
    queue_position: pick([undefined, null, null, 0, 1, 4, 11, 22, 103]),
    progress: pick([0, 0, 12.5, 37.04, 100, 101, -3]),
    state: pick([null, 'Queued, Remotely', 'InProgress']),
    speed: pick([0, 123456]),
    bytes_transferred: between(0, 9) * 1000,
    files_done: between(0, total),
    files_total: total,
    files_failed: pick([undefined, 0, 0, 2]),
    failure_reason: pick([undefined, null, 'the peer refused to send it']),
    matched: chance(0.5),
    alternatives_left: pick([undefined, 0, 1, 2, 9]),
    attempt: pick([undefined, 1, 1, 2, 3, 11, 22]),
    release_mbid: pick(RELEASES),
    release_group_mbid: pick([undefined, null, 'ad44f6e1-0a7c-31b0-9e1d-2f0b2b0c4a3d']),
    edition: pick(EDITIONS),
    updated_at: pick([undefined, plusZero(NOW - between(0, 300000) * 1000), iso(NOW - between(0, 4000) * 1000), 'nope']),
    outcome: pick(OUTCOMES),
    library: pick(LIBRARIES),
  }
  if (chance(0.5)) {
    job.mine = pick([true, true, false])
    job.shared = chance(0.4)
    if (chance(0.4)) job.requested_by = pick(ASKERS.slice(1))
  }
  return clean(job)
}

function seededPending(at) {
  return clean({
    key: `pending-${at}`,
    artist: pick(ARTISTS),
    album: pick(ALBUMS),
    username: pick(USERS),
    jobId: chance(0.3) ? between(1, 40) : undefined,
    error: pick(PENDING_ERRORS),
    detail: chance(0.3) ? 'POST /download/enqueue failed: 502' : undefined,
  })
}

const subset = (ids, p) => ids.filter(() => chance(p))

function seededInput() {
  const count = pick([0, 1, 2, 3, 5, 8, 12])
  const ids = []
  while (ids.length < count) {
    const id = between(1, 60)
    if (!ids.includes(id)) ids.push(id)
  }
  const jobs = ids.map(seededJob)
  const pending = chance(0.4) ? [...Array(between(1, 3)).keys()].map((at) => seededPending(at + 1)) : []
  const problems = {}
  for (const id of subset(ids, 0.2)) {
    problems[id] = chance(0.7) ? pick(PROBLEMS) : { text: "That didn't work.", detail: pick([null, 'POST failed']) }
  }
  return {
    jobs,
    pending,
    speeds: subset(ids, 0.4).map((id) => [id, pick([0, 1887436.8, 524288, 3])]),
    cancelling: subset(ids, 0.2),
    retrying: subset(ids, 0.2),
    retryingSame: subset(ids, 0.2),
    retryProblems: Object.entries(problems).map(([id, problem]) => [Number(id), problem]),
    personal: chance(0.3),
  }
}

/** The input as requestsView takes it. */
function webInput(input) {
  return {
    jobs: input.jobs,
    pending: input.pending,
    speeds: new Map(input.speeds),
    cancelling: new Set(input.cancelling),
    retrying: new Set(input.retrying),
    retryingSame: new Set(input.retryingSame),
    retryProblems: new Map(input.retryProblems),
    personal: input.personal,
  }
}

function boardOut(view) {
  return {
    sections: Object.fromEntries(V.SECTIONS.map((section) => [section, view.sections[section]])),
    arriving: view.arriving.map((row) => row.key),
    clearable: view.clearable,
    empty: view.empty,
  }
}

function boards() {
  const out = []
  for (let number = 0; number < 100; number++) {
    const input = seededInput()
    const now = NOW + between(0, 100) * 1000
    const view = V.requestsView(webInput(input), now)
    const overlays = { cancelling: new Set(input.cancelling), cleared: new Set(), pending: input.pending, retrying: new Set(input.retrying) }
    out.push({ input, now, board: boardOut(view), activeCount: O.activeCount(input.jobs, overlays) })
  }
  return out
}

/* ===== what a screen reader hears ===== */

/** The next look at the same downloads: some moved on, some gone, a retry or a cancel under way, a refusal. */
function nextInput(input) {
  const jobs = []
  for (const job of input.jobs) {
    if (chance(0.15)) continue
    const next = { ...job }
    if (chance(0.35)) next.status = pick(STATUSES)
    if (chance(0.2)) next.progress = pick([0, 40, 100])
    if (chance(0.2)) next.outcome = pick(OUTCOMES.filter((each) => each !== undefined))
    jobs.push(clean(next))
  }
  if (chance(0.3)) jobs.push(seededJob(between(61, 99)))
  const ids = jobs.map((job) => job.id)
  const problems = new Map(input.retryProblems.filter(([id]) => ids.includes(id) && chance(0.7)))
  for (const id of subset(ids, 0.15)) problems.set(id, pick(PROBLEMS))
  return {
    jobs,
    pending: input.pending.filter(() => chance(0.7)),
    speeds: input.speeds.filter(([id]) => ids.includes(id)),
    cancelling: [...new Set([...input.cancelling.filter((id) => ids.includes(id) && chance(0.6)), ...subset(ids, 0.15)])],
    retrying: [...new Set([...input.retrying.filter((id) => ids.includes(id) && chance(0.6)), ...subset(ids, 0.15)])],
    retryingSame: subset(ids, 0.25),
    retryProblems: [...problems],
    personal: input.personal,
  }
}

function changes() {
  const out = []
  for (let run = 0; run < 30; run++) {
    const inputs = [seededInput()]
    for (let step = 0; step < 4; step++) inputs.push(nextInput(inputs[inputs.length - 1]))
    const now = NOW + run * 1000
    const views = inputs.map((input) => V.requestsView(webInput(input), now))
    const steps = views.map((view, at) => {
      const said = V.changes(at === 0 ? null : views[at - 1], view)
      return { said: said.said, moved: said.moved, gone: [...said.gone] }
    })
    out.push({ now, inputs, steps })
  }
  return out
}

/* ===== the overlays ===== */

function overlays() {
  const out = []
  for (let number = 0; number < 120; number++) {
    const count = pick([0, 1, 3, 6])
    const jobs = []
    while (jobs.length < count) {
      const id = between(1, 12)
      if (!jobs.some((job) => job.id === id)) jobs.push({ id, status: pick(STATUSES) })
    }
    const anyIds = () => [...new Set([...Array(between(0, 3)).keys()].map(() => between(1, 14)))]
    const pending = [...Array(between(0, 3)).keys()].map((at) => clean({
      key: `pending-${at + 1}`, artist: 'A', album: 'B', username: 'u',
      jobId: chance(0.5) ? between(1, 14) : undefined,
      error: chance(0.4) ? pick(['', 'nope']) : undefined,
    }))
    const given = { cancelling: anyIds(), cleared: anyIds(), pending, retrying: anyIds() }
    const web = { cancelling: new Set(given.cancelling), cleared: new Set(given.cleared), pending, retrying: new Set(given.retrying) }
    const reconciled = O.reconcile(jobs, web)
    const settleKey = pending.length ? pick(pending).key : 'pending-9'
    const outcome = chance(0.5) ? { jobId: between(1, 14) } : clean({ error: 'nope', detail: chance(0.5) ? 'why' : undefined })
    out.push({
      jobs,
      overlays: given,
      reconciled: {
        unchanged: reconciled === web,
        cancelling: [...reconciled.cancelling], cleared: [...reconciled.cleared],
        pending: reconciled.pending.map((each) => each.key), retrying: [...reconciled.retrying],
      },
      visibleJobs: O.visibleJobs(jobs, web).map((job) => job.id),
      visiblePending: O.visiblePending(jobs, web).map((each) => each.key),
      activeCount: O.activeCount(jobs, web),
      finishedIds: O.finishedIds(jobs),
      withoutRefused: O.withoutRefused(web).pending.map((each) => each.key),
      settle: { key: settleKey, outcome, pending: O.settlePending(web, settleKey, outcome).pending },
    })
  }
  return out
}

/* ===== speeds ===== */

function speedTraces() {
  const out = []
  for (let trace = 0; trace < 40; trace++) {
    const samples = new Map()
    const ids = [1, 2, 3].slice(0, between(1, 3))
    const bytes = new Map(ids.map((id) => [id, 0]))
    let now = 1000 + between(0, 5000)
    const steps = []
    for (let step = 0; step < 14; step++) {
      now += pick([0, 250, 500, 500, 700, 1000, 1500, 5000, 7000])
      const jobs = []
      for (const id of ids) {
        if (chance(0.08)) continue
        const moved = pick([0, 0, 1000, 4096, 123457, 1048576, -50000])
        bytes.set(id, Math.max(0, bytes.get(id) + moved))
        jobs.push({ id, status: chance(0.9) ? pick(['downloading', 'queued', 'organizing']) : pick(['failed', 'organized']),
          bytes_transferred: bytes.get(id) })
      }
      const speeds = S.sampleSpeeds(samples, jobs, now)
      steps.push({ now, jobs, speeds: [...speeds] })
    }
    out.push({ steps })
  }
  return out
}

/* ===== watching ===== */

const WATCHING = ['requests', 'home', 'other', 'hidden']

function watching() {
  const shows = []
  for (const shown of [true, false]) {
    for (const tab of ['requests', 'home', 'library', 'search', 'you']) {
      for (const depth of [0, 1, 3]) {
        for (const sheetOpen of [false, true]) shows.push({ shown, tab, depth, sheetOpen, watching: V.watchingOf({ shown, tab, depth, sheetOpen }) })
      }
    }
  }
  const stalls = []
  for (const each of WATCHING) {
    for (const error of [null, '', 'failed to fetch download jobs']) {
      for (const arriving of [0, 1, 3]) stalls.push({ watching: each, error, arriving, stalls: V.stallsOn(each, error, arriving) })
    }
  }
  const asks = []
  for (const before of WATCHING) for (const now of WATCHING) asks.push({ before, now, asks: V.asksAgain(before, now) })
  return { shows, stalls, asks }
}

/* ===== the Done rows' looks ===== */

function looks() {
  const out = []
  const RELEASES = ['r1', 'r2', 'r3', 'r4', 'r5', 'r6']
  for (let number = 0; number < 200; number++) {
    const now = 1000000 + between(0, 200) * 1000
    const rows = [...Array(between(0, 6)).keys()].map(() => ({
      release: pick(RELEASES),
      since: pick([0, 0, now - between(0, 30) * 1000, now - 9000, now - 10000, now + 2000]),
    }))
    const ids = [], asked = [], misses = [], inFlight = []
    for (const release of RELEASES) {
      if (chance(0.45)) ids.push([release, `al-${release}`])
      if (chance(0.45)) asked.push([release, now - pick([0, 5000, 20000, 40000, 100000, 400000])])
      if (chance(0.35)) misses.push([release, { count: pick([1, 2, 3, 5, 9, 40, 1100]), at: now - pick([0, 3000, 5000, 9000, 30000, 70000]) }])
      if (chance(0.12)) inFlight.push(release)
    }
    const activeSince = now - pick([0, 10000, 31000, 60000, 500000])
    const held = { ids: new Map(ids), asked: new Map(asked), misses: new Map(misses), inFlight: new Set(inFlight), activeSince }
    const said = V.doneLooks(rows, held, now)
    out.push({ rows, held: { ids, asked, misses, inFlight, activeSince }, now, ...said })
  }
  return out
}

/* ===== an album just filed ===== */

/** newlyOrganized over runs of polls: which jobs each poll saw turn organized since the last (none on the first). */
function filed() {
  const out = []
  for (let run = 0; run < 40; run++) {
    let previous = null
    let jobs = [...Array(between(0, 5)).keys()].map(() => ({ id: between(1, 9), status: pick(STATUSES) }))
    const steps = []
    for (let step = 0; step < 6; step++) {
      const seen = jobs.filter((job, at) => jobs.findIndex((other) => other.id === job.id) === at)
      steps.push({ jobs: seen, filed: L.newlyOrganized(previous, seen) })
      previous = L.statusesOf(seen)
      jobs = seen.filter(() => chance(0.85)).map((job) => (chance(0.4) ? { ...job, status: pick(STATUSES) } : job))
      if (chance(0.4)) jobs.push({ id: between(1, 12), status: pick(['organized', 'queued', 'downloading', 'organizing']) })
    }
    out.push({ steps })
  }
  return out
}

/* ===== out ===== */

function vectors() {
  return {
    numbers: numbers(),
    words: words(),
    ordinals: ordinals(),
    badges: badges(),
    speeds: speeds(),
    ages: ages(),
    partly: partly(),
    outcomes: outcomes(),
    problems: problems(),
    people: people(),
    sections: sections(),
    boards: boards(),
    changes: changes(),
    overlays: overlays(),
    speedTraces: speedTraces(),
    watching: watching(),
    looks: looks(),
    filed: filed(),
  }
}

/** JSON with every character outside printable ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[^\n -~]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const made = say(vectors())
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== made) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-requests-vectors.cjs, then port the change to DeadwaxCore and see RequestsVectorTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, made)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
