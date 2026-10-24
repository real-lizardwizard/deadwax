/**
 * The app's Requests tab and Home's Arriving (2.0.0-player.12): the pure rules in
 * lib/requestsView.ts, and the components that draw them (app/Requests.tsx, app/JobCard.tsx,
 * app/Arriving.tsx, the badge in app/TabBar.tsx), compiled with the repo's TypeScript and rendered
 * by a small stand-in for Preact into plain objects.
 *
 * What it pins:
 *
 *  - Grouping: Downloading (downloading, organizing, or queued with bytes moving), Waiting (queued,
 *    and requests still asking slskd - those first), Needs attention (refusals, then failed and
 *    cancelled), Done (everything else, the newest to finish first). Each shown only with rows.
 *  - Every word each row says - "6 of 10 files · 1.8 MB/s", "#4 in their queue", "starting",
 *    "asking slskd…", "cancelling…", "Next peer · 2 left", "Trying next peer…", "Asking again…",
 *    "try 2", "organizing", and each outcome's ("In your library", "Already in your library,
 *    nothing filed", "Partly filed: …", "Interrupted while filing: …", "Not filed: …") - with the
 *    age from updated_at ("12 minutes ago").
 *  - ONE solid purple button on the screen: only the first Next peer is primary.
 *  - When Arriving shows: exactly the downloads the badge counts (downloadOverlay's activeCount -
 *    held to one answer case by case - and the badge given Arriving's own list in App, so Home and
 *    the badge can never disagree), at most three cards, NO section at all when nothing is
 *    arriving, drawn outside the Navidrome gate (Home rendered with Navidrome unset), and a note
 *    when deadwax didn't answer the last look.
 *  - What App is watching (watchingOf), when it asks again (asksAgain), and when a failed look
 *    keeps it asking (stallsOn), so a download started elsewhere shows and nothing freezes.
 *  - What a screen reader hears as rows change (changes), and which rows moved.
 *  - The components: the ✕ asks first IN the card ("Keep it" / "Cancel download") unless the
 *    preference says not to - never window.confirm(), which would hold the page playing the music
 *    - and hands the job to the hook's cancel; it waits aria-disabled while cancelling; Next peer
 *    and Ask again hand it to retry, the same peer or not, and wait aria-disabled while one runs,
 *    a refusal drawn under the reason; Clear done is disabled with nothing to clear; a spinner, not
 *    "Nothing requested yet", until deadwax first answers; a cover that fails is the plain tile;
 *    the tab's badge.
 *  - Done rows and the id bridge (2.0.0-player.17): a download whose album is in the library (filed,
 *    partly filed, already there) carries its release, so its row OPENS the album - a button - and
 *    one this download filed has the round ▶ too (named "Play <album>"), none for anything else; a
 *    tap with Navidrome's album not known yet asks the bridge for it, opens it on this tab when it
 *    comes - faded while it looks - and says why when it can't: Navidrome not having found it yet,
 *    no folder tagged with its release, Navidrome not set up or not answering - never playing from
 *    there; the note goes once a later look finds it, and that tap asks for the songs, so the next
 *    ▶ plays. A tap's look that answers after the tab stopped showing opens nothing; another row's
 *    tap calls it off. What the tab looks for ahead (doneLooks): an album filed while you watch,
 *    not before Navidrome can have scanned it, and again, backing off, until it is found; the songs
 *    again when a later download of the release may have added to them, or the tab comes back
 *    after a while - and, with effects running, the tab doing just that.
 *
 *  - Downloads per person (2.0.0-player.49, lib/perPerson.ts): an admin's rows say who asked
 *    ("Asked by ethan", "Asked by you, ethan and sam") on every card, a user's own-only and logins-off
 *    rows nothing; the ✕'s question says what a cancel does - a user's on a shared download "Leave it",
 *    an admin's on one somebody else waits for "Cancel for everyone", naming them, anything else the
 *    words it always had; how a folder's quality is put for a Get to send (candidateQuality - that a
 *    Get sends it is sources.sim's); and the store line for somebody else's
 *    download - the peer, the copy, how far, the quality floor's word (below, or not said by its
 *    folder; never "Get your own copy", not offered yet) and what Join does, in the page's own place -
 *    the copy as a source card's Quality says it; your own that somebody else waits for too, as a user,
 *    saying a cancel only leaves it; one failed and moving to its next peer by itself, saying so and
 *    nothing about cancelling; with your own, and logins off, word for word as before. A user's shared
 *    row says somebody else waits for it (never who); a leave reads "leaving…", is heard so, and once
 *    the card has gone is heard as left, focus going to the card beside it (focusAfterGone) - and,
 *    Requests' layout effect run against a stand-in document, really put there, or on the heading
 *    with no card left, and nowhere while focus is somewhere else; the ✕ is named for leaving. And a
 *    join tells every downloads list in the page to ask again - useDownloadJobs itself, effects
 *    running, polling again after a join.
 *  - Personal libraries (2.0.0-player.51, lib/myLibrary.ts grantWords): with logins on a Done row says
 *    what its filing gave - in your library, or (an admin's row of another's) in theirs; a second copy
 *    not filed, added; another copy's folder, not added and an admin asked to look (amber); partly
 *    filed, added marked incomplete - and logins off the words it always had. A download nothing of
 *    could be filed (`not_filed`, logins on) is under Needs attention saying why, the next peer offered
 *    and no Ask again; with logins off it is Done, as it always was.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/requests.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-requests-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/requestsView.ts', 'src/lib/downloadOverlay.ts', 'src/app/Requests.tsx', 'src/app/JobCard.tsx',
  'src/app/Arriving.tsx', 'src/app/TabBar.tsx', 'src/app/Home.tsx', 'src/state/persisted.ts', 'src/lib/downloadRequests.ts',
  'src/hooks/useDownloadJobs.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor - the same stand-in as settings.sim.cjs
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useCallback = (f) => f
//? effects run only where a test asks for them (globalThis.__effects), on its commit - and layout
//? effects, which reach for a document, only where a test gives them a stand-in one
//? (globalThis.__layoutEffects); either way each takes its slot, so a root's hooks keep their places
exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (globalThis.__layoutEffects && changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.useEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (globalThis.__effects && changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => { const outer = current; current = root; root.cursor = 0; try { return component(props) } finally { current = outer } }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  return render
}
`)

//? the player's actions, as a page reads them from App (Requests plays a Done row's album, 2.0.0-player.17),
//? and the id bridge, answered as the test says
fs.writeFileSync(path.join(OUT, 'app/context.js'), `exports.usePlayerActions = () => globalThis.__requests.actions\n`)
fs.writeFileSync(path.join(OUT, 'api/store.js'), `exports.storeAlbum = (by, signal) => globalThis.__requests.bridge(by.release_mbid, signal)\n`)
//? deadwax's join route, answered as the test says (lib/downloadRequests.ts joinDownload, 2.0.0-player.49)
//? and the jobs list useDownloadJobs polls, counted (a join makes it ask again)
fs.writeFileSync(path.join(OUT, 'api/download.js'), `exports.joinJob = (jobId) => globalThis.__joinAnswer(jobId)\nexports.enqueue = () => new Promise(() => {})
exports.listJobs = () => { globalThis.__listed = (globalThis.__listed || 0) + 1; return Promise.resolve({ jobs: [], tracking_enabled: true }) }
`)
//? the player's calls Requests and Home make: an album's songs asked for when the test says
fs.writeFileSync(path.join(OUT, 'player/api.js'), `
exports.albumPage = () => new Promise(() => {})
exports.dropPrefetch = () => {}
exports.prefetchAlbum = (id, keep, fresh) => globalThis.__requests.songs(id, !!fresh)
exports.rememberPlayed = (album) => globalThis.__requests.remembered.push(album.id)
exports.toQueueTrack = (song, album) => ({ id: song.id, albumId: album.id })
//? (2.0.0-player.65) an album warmed for Normalization, counted - and in order with the plays
exports.warmLevels = (id) => { globalThis.__requests.warmed.push(id); globalThis.__requests.order.push('warm') }
`)
globalThis.__requests = {
  plays: [],
  asked: [],
  answers: [],
  songAsks: [],
  songAnswers: [],
  remembered: [],
  warmed: [],
  order: [],
  actions: { playTracks: (...args) => { globalThis.__requests.plays.push(args); globalThis.__requests.order.push('play') } },
  bridge(release) {
    globalThis.__requests.asked.push(release)
    return new Promise((resolve, reject) => globalThis.__requests.answers.push({ resolve, reject, release }))
  },
  songs(id, fresh) {
    globalThis.__requests.songAsks.push([id, fresh])
    return new Promise((resolve, reject) => globalThis.__requests.songAnswers.push({ resolve, reject, id }))
  },
}
//? the bridge's answer for the oldest look out: Navidrome's id (or none), and the store's folders
const bridgeSays = (navidrome_id, present = [{ path: 'Massive Attack/Heligoland (2010)' }]) =>
  globalThis.__requests.answers.shift().resolve({ release_mbid: null, release_group_mbid: null, navidrome_id, present, other_pressings: [] })

//? a page's storage, as the components read it - and a window.confirm() that counts: the app
//? must never call it (a blocking dialog holds the page that plays the music)
const stored = new Map()
globalThis.localStorage = {
  getItem: (key) => (stored.has(key) ? stored.get(key) : null),
  setItem: (key, value) => stored.set(key, String(value)),
  removeItem: (key) => stored.delete(key),
}
const confirms = []
globalThis.window = { confirm: (words) => { confirms.push(words); return true } }
globalThis.console.error = () => {}

const V = require(path.join(OUT, 'lib/requestsView.js'))
const Q = require(path.join(OUT, 'app/Requests.js'))
const Q_SETTLE = V.DONE_SCAN_SETTLE_MS
const Q_RETRY = V.DONE_RETRY_MS
const O = require(path.join(OUT, 'lib/downloadOverlay.js'))
const { Requests } = require(path.join(OUT, 'app/Requests.js'))
const Cards = require(path.join(OUT, 'app/JobCard.js'))
const { Arriving } = require(path.join(OUT, 'app/Arriving.js'))
const { TabBar } = require(path.join(OUT, 'app/TabBar.js'))
const { Home } = require(path.join(OUT, 'app/Home.js'))
const H = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const Access = require(path.join(OUT, 'app/access.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== rendering ===== */

/** Render a tree all the way down: every component called, each with hooks of its own. */
function deep(node) {
  if (Array.isArray(node)) return node.map(deep)
  if (!node || typeof node !== 'object') return node
  if (typeof node.type === 'function') return deep(H.root(node.type)(node.props))
  const children = node.props.children
  return children === undefined ? node : { ...node, props: { ...node.props, children: deep(children) } }
}

function all(node, pick, found = []) {
  if (Array.isArray(node)) { for (const child of node) all(child, pick, found); return found }
  if (!node || typeof node !== 'object') return found
  if (pick(node)) found.push(node)
  all(node.props.children, pick, found)
  return found
}

function text(node) {
  if (Array.isArray(node)) return node.map(text).join('')
  if (node === null || node === undefined || typeof node === 'boolean') return ''
  if (typeof node !== 'object') return String(node)
  return text(node.props.children)
}

const hasClass = (name) => (node) => typeof node.props.class === 'string' && node.props.class.split(' ').includes(name)
const byClass = (tree, name) => all(tree, hasClass(name))

/* ===== the downloads, as useDownloadJobs gives them ===== */

const NOW = Date.parse('2026-09-30T12:00:00Z')
const ago = (seconds) => new Date(NOW - seconds * 1000).toISOString().replace('.000Z', '+00:00')

//? checks that wait for an answer to land: run in turn, each after the promises before it have settled
const later = []
const await_ = (fn) => later.push(fn)

let nextId = 1
function job(status, more = {}) {
  return {
    id: nextId++, artist: 'Massive Attack', album: 'Heligoland', year: '2010', username: 'mellotron',
    directory: 'd', status, error: null, created_at: ago(3600), queue_position: null, progress: 0,
    state: null, speed: 0, bytes_transferred: 0, files_done: 0, files_total: 10, matched: true,
    attempt: 1, release_mbid: null, release_group_mbid: null, edition: null, updated_at: ago(60),
    outcome: null, ...more,
  }
}

function input(jobs, more = {}) {
  return {
    jobs, pending: [], speeds: new Map(), cancelling: new Set(), retrying: new Set(), retryingSame: new Set(),
    retryProblems: new Map(), ...more,
  }
}

const view = (jobs, more) => V.requestsView(input(jobs, more), NOW)
const keys = (rows) => rows.map((row) => row.key)
const MB = 1024 * 1024

/* ========================================================================== */
console.log('\nDone rows open, and play, their album (2.0.0-player.17)')
{
  const R1 = '11111111-1111-4111-8111-111111111111'
  const doneOf = (status, more) => view([job(status, { release_mbid: R1, ...more })]).sections.done[0]
  const filed = doneOf('organized', { outcome: 'filed' })
  check('filed: its release, and it plays', [filed.release, filed.plays, filed.album], [R1, true, 'Heligoland'])
  check('partly filed: its release, and it plays what landed', [doneOf('complete', { outcome: 'partly_filed', error: 'x' }).release, doneOf('complete', { outcome: 'partly_filed', error: 'x' }).plays], [R1, true])
  check('already there: its release - the album is in the library - but nothing of this download to play',
    [doneOf('complete', { outcome: 'already_there', error: 'already in the store: x' }).release, doneOf('complete', { outcome: 'already_there', error: 'x' }).plays], [R1, false])
  check('interrupted, or not filed: no album to open',
    [doneOf('complete', { outcome: 'interrupted', error: 'x' }).release, doneOf('complete', { error: 'Not filed: dry run' }).release], [null, null])
  check('no release id: nothing to open', [view([job('organized', { outcome: 'filed' })]).sections.done[0].release], [null])
  check('...and nothing still going carries one', view([job('downloading', { release_mbid: R1 })]).sections.downloading[0].release, null)

  const drawn = (row, more = {}) => deep(H.root(Cards.DoneRow)({ row, onOpen() {}, onPlay() {}, ...more }))
  const filedRow = drawn(filed)
  check('a filed row: the row a button that opens it, and the round ▶ named for the album',
    [all(filedRow, (n) => n.type === 'button' && n.props.class === 'app-done-open').length, all(filedRow, (n) => n.props.class === 'app-done-play').map((n) => n.props['aria-label'])],
    [1, ['Play Heligoland']])
  const there = drawn(doneOf('complete', { outcome: 'already_there', error: 'x' }))
  check('already there: it opens, with no ▶', [all(there, (n) => n.type === 'button').map((n) => n.props.class)], [['app-done-open']])
  const plain = drawn(view([job('organized', { outcome: 'filed' })]).sections.done[0])
  check('no album to open: no button at all', all(plain, (n) => n.type === 'button').length, 0)
  check('the note when it can\'t be opened, in amber', byClass(drawn(filed, { note: 'gone' }), 'app-job-line').map((n) => [text(n), n.props.class]),
    [[byClass(filedRow, 'app-job-line').map(text)[0], 'app-job-line'], ['gone', 'app-job-line is-warning']])

  //? the page: a tap before the album's songs are in hand opens it, through the bridge - never plays.
  //? Run after everything synchronous, in order, each step after the answers before it have landed
  await_(async () => {
    const tick = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))
    const opened = []
    const R = globalThis.__requests
    R.asked.length = 0; R.answers.length = 0; R.songAsks.length = 0; R.songAnswers.length = 0; R.plays.length = 0; R.remembered.length = 0
    const v = view([job('organized', { outcome: 'filed', release_mbid: R1 })])
    const props = (more = {}) => ({ view: v, trackingEnabled: true, error: null, active: true, onCancel: async () => {}, onRetry: async () => {}, onClear: async () => {}, onOpenAlbum: (album) => opened.push(album), ...more })
    const openButtons = (tree) => all(tree, (n) => typeof n.props.class === 'string' && n.props.class.split(' ')[0] === 'app-done-open')
    const notes = (tree) => byClass(tree, 'app-job-line').map(text).slice(1)

    const live = H.root(Requests)
    const draw = (more) => deep(live(props(more)))
    all(draw(), (n) => n.props.class === 'app-done-play')[0].props.onClick()
    check('the ▶ with nothing in hand: the bridge asked for the album, nothing played', [R.asked, R.plays.length], [[R1], 0])
    check('...the row busy - and faded - meanwhile', [openButtons(draw())[0].props['aria-busy'], openButtons(draw())[0].props.class], [true, 'app-done-open is-busy'])
    bridgeSays('nd-heligoland')
    await tick()
    check('...and it opens on this tab when Navidrome\'s album comes, by its own name', opened, [{ id: 'nd-heligoland', name: 'Heligoland', artist: 'Massive Attack' }])
    check('...its songs asked for as it opens, so the next ▶ plays', R.songAsks, [['nd-heligoland', false]])
    R.songAnswers.shift().resolve({ id: 'nd-heligoland', name: 'Heligoland', song: [{ id: 's1' }, { id: 's2' }] })
    await tick()
    all(draw(), (n) => n.props.class === 'app-done-play')[0].props.onClick()
    check('...and it does: the album remembered, then played from the top - nothing asked', [R.remembered, R.plays.map((play) => [play[0].map((t) => t.id), play[1]]), R.asked.length],
      [['nd-heligoland'], [[['s1', 's2'], 0]], 1])
    openButtons(draw())[0].props.onClick()
    check('a tap opens it at once, asking nothing', [opened.length, R.asked.length], [2, 1])
    check('...an album with no FLAC song is warmed for nothing - nothing levels it', R.warmed, [])

    //? (2.0.0-player.65, the 2.0.0 release review) a FLAC album played from its ▶: warmed for Normalization, after the play
    const RF = '44444444-4444-4444-8444-444444444444'
    const flac = H.root(Requests)
    const drawFlac = () => deep(flac(props({ view: view([job('organized', { outcome: 'filed', release_mbid: RF })]), onOpenAlbum: () => {} })))
    all(drawFlac(), (n) => n.props.class === 'app-done-play')[0].props.onClick()
    bridgeSays('nd-dummy')
    await tick()
    R.songAnswers.shift().resolve({ id: 'nd-dummy', name: 'Dummy', song: [{ id: 'f1', suffix: 'flac' }, { id: 'f2', suffix: 'flac' }] })
    await tick()
    R.order.length = 0
    all(drawFlac(), (n) => n.props.class === 'app-done-play')[0].props.onClick()
    check('a FLAC album\'s ▶ warms its measuring - once, right after the play', [R.warmed, R.order], [['nd-dummy'], ['play', 'warm']])
    localStorage.setItem('deadwax-player-normalization', 'off')
    all(drawFlac(), (n) => n.props.class === 'app-done-play')[0].props.onClick()
    check('...and under Off, nothing', R.warmed, ['nd-dummy'])
    localStorage.removeItem('deadwax-player-normalization')

    const R2 = '22222222-2222-4222-8222-222222222222'
    const lost = H.root(Requests)
    const drawLost = (more = {}) => deep(lost(props({ view: view([job('organized', { outcome: 'filed', release_mbid: R2 })]), ...more })))
    openButtons(drawLost())[0].props.onClick()
    bridgeSays(null)
    await tick()
    check('Navidrome hasn\'t got it: the row says so, and opens nothing', [notes(drawLost()), opened.length], [[Q.NOT_IN_NAVIDROME], 2])
    check('(2.0.6) ...in a listener\'s words, never the music server\'s name', Q.NOT_IN_NAVIDROME, 'Not ready to play yet - it may still be scanning.')
    //? (2.0.6, review) hedged as the code can know: a folder Navidrome never lists won't be ready in a minute, and a
    //? present-less store answer is also a filed folder since moved or deleted outside deadwax
    check('(2.0.6) ...and the store\'s miss says it may have moved, not only that it isn\'t matched', Q.NOT_IN_STORE, "Can't find this album to open it - it may have moved, or isn't matched to a pressing.")
    openButtons(drawLost())[0].props.onClick()
    bridgeSays('nd-lost')
    await tick()
    check('...a later tap that finds it opens it, and the note goes', [opened.slice(-1).map((album) => album.id), notes(drawLost())], [['nd-lost'], []])

    const R3 = '33333333-3333-4333-8333-333333333333'
    const untagged = H.root(Requests)
    const drawThere = (more = {}) => deep(untagged(props({ view: view([job('complete', { outcome: 'already_there', error: 'already in the store: x', release_mbid: R3 })]), ...more })))
    openButtons(drawThere())[0].props.onClick()
    bridgeSays(null, [])
    await tick()
    check('no folder of the library tagged with its release (an untagged copy it matched): said so - no scan will help', notes(drawThere()), [Q.NOT_IN_STORE])
    const down = "Navidrome isn't answering just now, so deadwax can't open the album here"
    openButtons(drawThere({ navidromeProblem: down }))[0].props.onClick()
    bridgeSays(null)
    await tick()
    check('Navidrome not answering: said so, not "still scanning"', notes(drawThere()), [down])
    openButtons(drawThere())[0].props.onClick()
    R.answers.shift().reject(new Error('deadwax away'))
    await tick()
    check('deadwax not answering the look: said so', notes(drawThere()), [Q.NOT_LOOKED_UP])

    const R4 = '44444444-4444-4444-8444-444444444444'
    const away = H.root(Requests)
    const drawAway = (more = {}) => deep(away(props({ view: view([job('organized', { outcome: 'filed', release_mbid: R4 })]), ...more })))
    const before = opened.length
    openButtons(drawAway())[0].props.onClick()
    drawAway({ active: false })
    bridgeSays('nd-away')
    await tick()
    check('the tab left before the look answered: nothing opened on whichever tab you went to', opened.length, before)

    const both = H.root(Requests)
    const twoView = view([job('organized', { outcome: 'filed', release_mbid: R4, album: 'Known' }), job('organized', { outcome: 'filed', release_mbid: '55555555-5555-4555-8555-555555555555', album: 'Slow' })])
    const rows = () => openButtons(deep(both(props({ view: twoView }))))
    rows()[0].props.onClick()
    bridgeSays('nd-known')
    await tick()
    rows()[1].props.onClick()
    rows()[0].props.onClick()
    bridgeSays('nd-slow')
    await tick()
    check('a tap on another row calls a look still out off: only the rows tapped open', opened.slice(before).map((album) => album.id), ['nd-known', 'nd-known'])
  })
}

console.log('\nwhat the tab looks for ahead (doneLooks)')
{
  const NOW = 1_000_000
  const none = { ids: new Map(), asked: new Map(), misses: new Map(), inFlight: new Set(), activeSince: NOW }
  check('a row done before the page loaded: looked up at once', V.doneLooks([{ release: 'a', since: 0 }], none, NOW), { look: ['a'], songs: [], nextIn: null })
  check('a row filed just now: not before Navidrome can have scanned it',
    V.doneLooks([{ release: 'a', since: NOW - 2000 }], none, NOW), { look: [], songs: [], nextIn: V.DONE_SCAN_SETTLE_MS - 2000 })
  const missed = { ...none, misses: new Map([['a', { count: 1, at: NOW - 1000 }]]) }
  check('a look that found nothing: again after DONE_RETRY_MS', V.doneLooks([{ release: 'a', since: 0 }], missed, NOW).nextIn, V.DONE_RETRY_MS - 1000)
  check('...doubling, to DONE_RETRY_MAX_MS', [
    V.doneLooks([{ release: 'a', since: 0 }], { ...none, misses: new Map([['a', { count: 3, at: NOW }]]) }, NOW).nextIn,
    V.doneLooks([{ release: 'a', since: 0 }], { ...none, misses: new Map([['a', { count: 20, at: NOW }]]) }, NOW).nextIn,
  ], [4 * V.DONE_RETRY_MS, V.DONE_RETRY_MAX_MS])
  check('...and once due, looked up', V.doneLooks([{ release: 'a', since: 0 }], missed, NOW + V.DONE_RETRY_MS).look, ['a'])
  const found = { ...none, ids: new Map([['a', 'nd-a']]) }
  check('found: its songs asked for', V.doneLooks([{ release: 'a', since: 0 }], found, NOW), { look: [], songs: ['a'], nextIn: null })
  const asked = { ...found, asked: new Map([['a', NOW - 1000]]) }
  check('...asked lately: nothing more', V.doneLooks([{ release: 'a', since: 0 }], asked, NOW), { look: [], songs: [], nextIn: null })
  check('...a later download of the release, filed just now: asked again once Navidrome can have scanned it',
    [V.doneLooks([{ release: 'a', since: 0 }, { release: 'a', since: NOW - 500 }], asked, NOW).nextIn, V.doneLooks([{ release: 'a', since: NOW - 500 }], asked, NOW + V.DONE_SCAN_SETTLE_MS).songs],
    [V.DONE_SCAN_SETTLE_MS - 500, ['a']])
  check('...asked long before the tab last came back: asked again',
    V.doneLooks([{ release: 'a', since: 0 }], { ...asked, asked: new Map([['a', NOW - V.DONE_FRESH_MS - 1]]) }, NOW).songs, ['a'])
  check('asked now: nothing again until it answers', V.doneLooks([{ release: 'a', since: 0 }], { ...none, inFlight: new Set(['a']) }, NOW), { look: [], songs: [], nextIn: null })
}

console.log('\nthe tab looking ahead, effects running')
await_(async () => {
  const tick = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))
  globalThis.__effects = true
  const R = globalThis.__requests
  R.asked.length = 0; R.answers.length = 0; R.songAsks.length = 0; R.songAnswers.length = 0; R.plays.length = 0
  const timers = []
  const realSetTimeout = globalThis.setTimeout
  const realClear = globalThis.clearTimeout
  const realNow = Date.now
  globalThis.setTimeout = (fn, ms) => { const timer = { fn, ms, live: true }; timers.push(timer); return timer }
  globalThis.clearTimeout = (timer) => { if (timer && timer.fn) timer.live = false; else realClear(timer) }
  const fire = () => { for (const timer of timers.splice(0)) if (timer.live) timer.fn() }
  try {
    const R5 = '66666666-6666-4666-8666-666666666666'
    const tab = H.root(Requests)
    let current = view([])
    const draw = (more = {}) => {
      const tree = deep(tab({ view: current, trackingEnabled: true, error: null, active: true, onCancel: async () => {}, onRetry: async () => {}, onClear: async () => {}, onOpenAlbum() {}, ...more }))
      tab.commit()
      return tree
    }
    draw()
    current = view([job('organized', { outcome: 'filed', release_mbid: R5 })])
    draw()
    check('a download filed while the tab shows: not looked up straight away (Navidrome hasn\'t scanned it)', [R.asked, timers.filter((t) => t.live).map((t) => t.ms <= Q_SETTLE)], [[], [true]])
    Date.now = () => realNow() + Q_SETTLE + 1
    fire()
    draw()
    check('...then looked up', R.asked, [R5])
    bridgeSays(null)
    await tick()
    draw()
    check('nothing found yet: looked at again later, not given up on', timers.filter((t) => t.live).length, 1)
    Date.now = () => realNow() + Q_SETTLE + 1 + Q_RETRY + 1
    fire()
    draw()
    check('...looked up again', R.asked, [R5, R5])
    bridgeSays('nd-five')
    await tick()
    draw()
    check('...found: its songs asked for (kept)', R.songAsks, [['nd-five', false]])
    R.songAnswers.shift().resolve({ id: 'nd-five', name: 'Five', song: [{ id: 'f1' }] })
    await tick()
    const tree = draw()
    all(tree, (n) => n.props.class === 'app-done-play')[0].props.onClick()
    check('...and its ▶ plays it, from the tap', R.plays.slice(-1).map((play) => play[0].map((t) => t.id)), [['f1']])
  } finally {
    globalThis.setTimeout = realSetTimeout
    globalThis.clearTimeout = realClear
    Date.now = realNow
    globalThis.__effects = false
  }
})


/* ========================================================================== */
console.log('\ngrouping: which heading each download goes under')
{
  const downloading = job('downloading', { progress: 60, files_done: 6 })
  const filing = job('organizing', { files_done: 10 })
  const movingQueued = job('queued', { progress: 12 })
  const queued = job('queued')
  const failed = job('failed', { error: 'the peer went offline' })
  const cancelled = job('cancelled', { error: 'cancelled from deadwax' })
  const filedOld = job('organized', { outcome: 'filed', updated_at: ago(7200) })
  const filedNew = job('organized', { outcome: 'filed', updated_at: ago(60) })
  const complete = job('complete', { error: 'dry run - not organized', updated_at: ago(600) })
  const pending = [
    { key: 'pending-2', artist: 'Portishead', album: 'Third', username: 'vinylhead' },
    { key: 'pending-1', artist: 'Portishead', album: 'Dummy', username: 'bob', error: 'User bob appears to be offline' },
  ]
  const v = V.requestsView(input([downloading, filing, movingQueued, queued, failed, cancelled, filedOld, filedNew, complete], { pending }), NOW)

  check('the headings, in order', V.SECTIONS.map((section) => V.SECTION_TITLES[section]), ['Downloading', 'Waiting', 'Needs attention', 'Done'])
  check('Downloading: downloading, being filed, and queued with bytes moving', keys(v.sections.downloading),
    [`job-${downloading.id}`, `job-${filing.id}`, `job-${movingQueued.id}`])
  check('Waiting: the request still asking slskd first, then the queued job', keys(v.sections.waiting), ['pending-2', `job-${queued.id}`])
  check('Needs attention: the refusal first, then failed and cancelled', keys(v.sections.attention),
    ['pending-1', `job-${failed.id}`, `job-${cancelled.id}`])
  check('Done: the newest to finish first, by updated_at - not by id', keys(v.sections.done),
    [`job-${filedNew.id}`, `job-${complete.id}`, `job-${filedOld.id}`])
  check('something to clear, and not empty', [v.clearable, v.empty], [true, false])
  check('sectionOf, one status at a time', ['queued', 'downloading', 'organizing', 'failed', 'cancelled', 'complete', 'organized']
    .map((status) => V.sectionOf({ status, progress: 0 })), ['waiting', 'downloading', 'downloading', 'attention', 'attention', 'done', 'done'])

  const idle = view([job('queued'), job('downloading')], { pending: [pending[0]] })
  check('only moving downloads and a request asking: nothing for Clear done', idle.clearable, false)
  check('...a refusal is something to clear', view([], { pending: [pending[1]] }).clearable, true)
  check('nothing at all is empty', [view([]).empty, view([]).clearable], [true, false])
}

/* ========================================================================== */
console.log('\nwhat each row says')
{
  const down = job('downloading', { progress: 60, files_done: 6, username: 'mellotron' })
  const v = view([down], { speeds: new Map([[down.id, 1.8 * MB]]) })
  const row = v.sections.downloading[0]
  check('who and from where', row.line, 'Massive Attack · from mellotron')
  check('the files and the speed, in the monospace line', row.data, '6 of 10 files · 1.8 MB/s')
  check('the bar and the Arriving card\'s words', [row.progress, row.brief], [60, '6 of 10'])
  check('a ✕ to cancel it', row.cancel, 'ready')

  const refused = job('downloading', { files_done: 3, files_failed: 1, attempt: 2 })
  const r2 = view([refused]).sections.downloading[0]
  check('files refused while the rest move, no speed yet, and which try', [r2.data, r2.line],
    ['3 of 10 files · 1 failed', 'Massive Attack · from mellotron · 2nd try'])
  check('one file is a file', view([job('downloading', { files_total: 1 })]).sections.downloading[0].data, '0 of 1 file')

  const filing = view([job('organizing', { files_done: 10 })]).sections.downloading[0]
  check('being filed: the bar full, "organizing", and nothing left to cancel',
    [filing.progress, filing.data, filing.brief, filing.cancel], [100, '10 of 10 files · adding to your library…', 'adding…', null])

  const going = job('downloading', { files_done: 2 })
  const cancelling = view([going], { cancelling: new Set([going.id]) }).sections.downloading[0]
  check('being cancelled: "cancelling…", faded, the ✕ waiting - and no longer arriving',
    [cancelling.data, cancelling.brief, cancelling.dimmed, cancelling.cancel, cancelling.arriving],
    ['cancelling…', 'cancelling…', true, 'cancelling', false])

  const starting = view([job('queued', { artist: 'Portishead', album: 'Third', username: 'vinylhead' })]).sections.waiting[0]
  check('queued before slskd says where: "starting", as the board says', [starting.line, starting.brief, starting.cancel],
    ['Portishead · from vinylhead · starting', 'starting', 'ready'])
  const placed = view([job('queued', { queue_position: 4, attempt: 3 })]).sections.waiting[0]
  check('its place in the peer\'s queue, and which try', [placed.line, placed.brief],
    ['Massive Attack · from mellotron · 4th in their queue · 3rd try', '4th in line'])
  //? (2.0.6, UX batch 3) a place or a try as a listener says it - "4th", never "#4" or "try 4"
  check('(2.0.6) ordinals: 1st, 2nd, 3rd, 4th, the teens th, then 21st, 22nd, 23rd, 101st, 111th, 112th',
    [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111, 112].map(V.ordinal), ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '101st', '111th', '112th'])
  const q = job('queued')
  check('a queued one being cancelled', view([q], { cancelling: new Set([q.id]) }).sections.waiting[0].line,
    'Massive Attack · from mellotron · cancelling…')
  const partRefused = view([job('queued', { queue_position: 4, files_failed: 3 })]).sections.waiting[0]
  check('files the peer already refused while the rest wait: said now, in amber, as the downloads panel says',
    [partRefused.line, partRefused.lineTone, partRefused.section], ['Massive Attack · from mellotron · 4th in their queue · 3 failed', 'warning', 'waiting'])
  const startingRefused = view([job('queued', { files_failed: 1 })]).sections.waiting[0]
  check('...before slskd says where too', [startingRefused.line, startingRefused.lineTone], ['Massive Attack · from mellotron · starting · 1 failed', 'warning'])
  check('...and an ordinary wait stays plain', placed.lineTone, 'plain')

  const asking = view([], { pending: [{ key: 'pending-9', artist: 'Portishead', album: 'Third', username: 'vinylhead' }] }).sections.waiting[0]
  check('asking slskd: no job yet, so nothing to cancel', [asking.line, asking.brief, asking.cancel, asking.jobId],
    ['Portishead · from vinylhead · starting…', 'starting…', null, null])

  const refusal = view([], { pending: [{ key: 'pending-3', artist: 'Portishead', album: 'Dummy', username: 'bob', error: 'User bob appears to be offline' }] }).sections.attention[0]
  check('refused: slskd\'s own words in red, and no buttons', [refusal.line, refusal.reason, refusal.nextPeer, refusal.askAgain],
    ['Portishead · from bob · didn\'t start', 'User bob appears to be offline', null, null])
  //? (2.0.6, review) /enqueue's 409 carries already_have's words - a folder's path, "being filed" - said as a listener's,
  //? the route's own the detail for whoever runs deadwax; "your library" the collection with logins on
  const refusedAs = (error, more = {}) => view([], { pending: [{ key: 'pending-4', artist: 'Portishead', album: 'Dummy', username: 'bob', error }], ...more }).sections.attention[0]
  check('(2.0.6) ...a 409 already_have wrote: no path, no "filed" - its own words the detail',
    [[refusedAs('already in your library: Portishead/Dummy (1994)').reason, refusedAs('already in your library: Portishead/Dummy (1994)').reasonDetail],
      refusedAs('already downloaded from bob, and being filed now').reason, refusedAs('already in your library: Portishead/Dummy (1994)', { personal: true }).reason],
    [["It's already in your library.", 'already in your library: Portishead/Dummy (1994)'], "It's already downloaded, and being added now.", "It's already in the collection."])
  const failedHeld = job('failed', { error: 'the peer went offline' })
  const heldRetry = (personal) => view([failedHeld], { personal, retryProblems: new Map([[failedHeld.id, 'already in your library: Portishead/Dummy (1994)']]) }).sections.attention[0]
  check('(2.0.6) ...and a retry refused for it: the collection\'s copy with a library of your own, the path the detail',
    [heldRetry(false).problem, heldRetry(true).problem, heldRetry(true).problemDetail],
    ["It's already in your library.", "It's already in the collection.", 'already in your library: Portishead/Dummy (1994)'])

  check('the edition on the title, and an album with no name',
    [view([job('organized', { album: 'Dummy', edition: '2014 vinyl' })]).sections.done[0].title,
      view([job('organized', { album: '' })]).sections.done[0].title], ['Dummy · 2014 vinyl', 'Unknown album'])
  check('the cover: the pressing\'s front from the Cover Art Archive, and none without an id',
    [view([job('organized', { release_mbid: 'a b/c' })]).sections.done[0].cover, view([job('organized')]).sections.done[0].cover],
    ['https://coverartarchive.org/release/a%20b%2Fc/front-250', null])
}

/* ========================================================================== */
console.log('\nNeeds attention: the two ways on, and one primary on the screen')
{
  const first = job('failed', { error: 'reel2reel went offline after 4 of 10 files', alternatives_left: 2 })
  const second = job('cancelled', { error: null, alternatives_left: 1 })
  const lone = job('failed', { error: 'the transfer failed', alternatives_left: 0 })
  const v = view([first, second, lone])
  const [a, b, c] = v.sections.attention
  check('the reason in red, "Cancelled" when a cancel gave none', [a.reason, b.reason], ['reel2reel went offline after 4 of 10 files', 'Cancelled'])
  check('Next peer says how many are left, Ask again always', [a.nextPeer.label, b.nextPeer.label, a.askAgain.label], ['Another source · 2 left', 'Another source · 1 left', 'Same source again'])
  check('only the FIRST Next peer is the solid purple one', v.sections.attention.map((row) => row.nextPeer && row.nextPeer.primary), [true, false, null])
  check('no runners-up: no Next peer, still Ask again', [c.nextPeer, c.askAgain.label], [null, 'Same source again'])

  const next = view([first], { retrying: new Set([first.id]) }).sections.attention[0]
  check('trying the next peer: its words on its button, both waiting, and arriving again',
    [next.nextPeer.label, next.askAgain.label, next.busy, next.arriving, next.brief],
    ['Trying another source…', 'Same source again', true, true, 'retrying…'])
  const same = view([first], { retrying: new Set([first.id]), retryingSame: new Set([first.id]) }).sections.attention[0]
  check('asking the same peer again', [same.nextPeer.label, same.askAgain.label, same.busy, same.brief],
    ['Another source · 2 left', 'Trying again…', true, 'retrying…'])
  check('an Arriving card\'s word for either is short, so the album\'s name keeps its room', next.brief.length <= 'retrying…'.length, true)
  const refusedRetry = view([first], { retryProblems: new Map([[first.id, 'no other peer would take it']]) }).sections.attention[0]
  check('a retry nobody would take: its words under the reason', [refusedRetry.problem, refusedRetry.busy], ['no other peer would take it', false])
  check('the refusal first still leaves the primary to the first job with runners-up',
    view([first], { pending: [{ key: 'p', artist: '', album: 'X', username: 'u', error: 'no' }] }).sections.attention.map((row) => row.nextPeer && row.nextPeer.primary),
    [null, true])
}

/* ========================================================================== */
console.log('\nDone: how it ended, and how long ago')
{
  const words = (outcome, error) => V.outcomeWords({ outcome, error })
  check('filed', words('filed', null), { text: 'In your library', tone: 'plain' })
  check('every track already there', words('already_there', 'already in the store: all 10 track(s) were already there, nothing was filed'),
    { text: 'You already had it', tone: 'plain' })
  check('some files didn\'t file', words('partly_filed', '2 file(s) failed to organize'), { text: "In your library - 2 files couldn't be added", tone: 'warning', detail: '2 file(s) failed to organize' })
  //? (2.0.6, review) without a count in the job's words, still a listener's: never the old "failed" wording back
  check('...and without a count, "some files"', [words('partly_filed', null).text, words('partly_filed', 'organize failed: x').text, words('partly_filed', '1 file(s) failed to organize').text],
    ["In your library - some files couldn't be added", "In your library - some files couldn't be added", "In your library - 1 file couldn't be added"])
  check('a stop caught it filing', words('interrupted', "deadwax stopped while filing this - check the library and slskd's folder"),
    { text: 'Stopped while being added to your library', tone: 'warning', tell: true, detail: "deadwax stopped while filing this - check the library and slskd's folder" })
  //? (2.0.4) the row's own words in a listener's (lib/errorWords.ts jobErrorWords) - never "check SLSKD_DOWNLOAD_PATH"
  check('any other ending, in the row\'s words, as a listener reads them - and the tell and its own words, for the row to draw',
    words(null, 'dry run - not organized'), { text: 'Downloaded, but not added to your library: deadwax is set to rehearse adding albums, without moving any files.', tone: 'warning', tell: true, detail: 'dry run - not organized' })
  check('finished with organizing off', words(null, null), { text: 'Downloaded, but not added to your library', tone: 'warning', tell: true })
  check('never read out of the error text: "already in the store" with no outcome is its own words',
    words(null, 'already in the store: all 3 track(s)').text, 'already in the store: all 3 track(s)')

  const done = view([job('organized', { outcome: 'filed', updated_at: ago(12 * 60) })]).sections.done[0]
  check('the line, as the board has it', [done.line, done.lineTone], ['In your library · 12 minutes ago', 'plain'])
  const unknown = view([job('complete', { outcome: 'partly_filed', error: '1 file(s) failed to organize', updated_at: 'nonsense' })]).sections.done[0]
  check('an age that can\'t be read is left off', [unknown.line, unknown.lineTone], ["In your library - 1 file couldn't be added", 'warning'])
  check('a done row is not arriving, and has no ✕', [done.arriving, done.cancel], [false, null])
}

/* ========================================================================== */
console.log('\npersonal libraries (2.0.0-player.51): what a filing gave, and a download nothing could be filed of')
{
  const words = (outcome, error, library, mine) => V.outcomeWords({ outcome, error, library, ...(mine === undefined ? {} : { mine }) })
  check('filed, into your library', words('filed', null, 'added', true), { text: 'In your library', tone: 'plain' })
  check('...an admin\'s row of somebody else\'s', words('filed', null, 'added', false), { text: 'In their library', tone: 'plain' })
  check('a second copy not filed, given', words('already_there', 'already in the store: all 10 track(s) were already there, nothing was filed', 'added', true),
    { text: 'Already in the collection, added to your library', tone: 'plain' })
  check('...given to them', words('already_there', 'x', 'added', false).text, 'Already in the collection, added to their library')
  check('everything already in another copy\'s folder: not added, an admin looks - amber', words('already_there', 'x', 'flagged', true),
    { text: "Not added - the collection's copy may be another pressing, so an admin has been asked to check it", tone: 'warning' })
  check('...the admin\'s Add for them makes it added; their Put away says the admin has looked (review: it kept saying an admin had been asked)',
    [words('already_there', 'x', 'added', true).text, words('already_there', 'x', 'looked', true)],
    ['Already in the collection, added to your library', { text: "Not added - the collection's copy may be another pressing; an admin has checked it", tone: 'warning' }])
  check('some files failed: added, marked incomplete', words('partly_filed', '2 file(s) failed to organize', 'incomplete', true),
    { text: "In your library - 2 files couldn't be added", tone: 'warning', detail: '2 file(s) failed to organize' })
  check('logins off (no `library`): the words it always had', [words('filed', null, undefined).text, words('already_there', 'x', undefined).text],
    ['In your library', 'You already had it'])
  check('...and nothing given says its own words, as a listener reads them', words(null, 'dry run - not organized', null, true).text, 'Downloaded, but not added to your library: deadwax is set to rehearse adding albums, without moving any files.')

  const notFiled = job('complete', { outcome: 'not_filed', error: 'nothing could be organized, check SLSKD_DOWNLOAD_PATH', alternatives_left: 2 })
  const v = view([notFiled])
  const [row] = v.sections.attention
  check('nothing of it could be filed (logins on): under Needs attention, saying why, the next peer offered - not Ask again',
    [v.sections.done.length, row.reason, row.nextPeer.label, row.askAgain], [0, "It downloaded, but deadwax couldn't find its files to add them to your library.", 'Another source · 2 left', null])
  check('...only whoever runs deadwax can put it right (JobCard tells anyone else so), and the job\'s own words kept for them',
    [row.reasonTell, row.reasonDetail], [true, 'nothing could be organized, check SLSKD_DOWNLOAD_PATH'])
  const off = view([job('complete', { outcome: null, error: 'nothing could be organized, check SLSKD_DOWNLOAD_PATH' })])
  check('...with logins off (no such outcome): Done, as it always was', [off.sections.done.length, off.sections.attention.length, off.sections.done[0].line.startsWith("It downloaded, but deadwax couldn't find its files")],
    [1, 0, true])
  //? (review) the Done row keeps the job's own words for whoever runs deadwax - with logins off, everyone - and the
  //? tell for anyone else, as a Needs-attention card does
  const offRow = off.sections.done[0]
  check('...its own words and the tell carried onto the Done row', [offRow.reasonTell, offRow.reasonDetail], [true, 'nothing could be organized, check SLSKD_DOWNLOAD_PATH'])
  const offDrawn = deep(H.root(Cards.DoneRow)({ row: offRow }))
  check('...drawn for whoever runs deadwax (logins off): the setting under the line, no tell',
    [byClass(offDrawn, 'app-error-detail').map(text), byClass(offDrawn, 'app-job-line').map(text).some((t) => t.includes('Tell whoever'))],
    [['nothing could be organized, check SLSKD_DOWNLOAD_PATH'], false])
  const failedFiling = view([job('complete', { outcome: null, error: "organize failed: [Errno 13] Permission denied: '/music/x'" })]).sections.done[0]
  check('...an exception the filing raised, the same way', byClass(deep(H.root(Cards.DoneRow)({ row: failedFiling })), 'app-error-detail').map(text),
    ["organize failed: [Errno 13] Permission denied: '/music/x'"])
  Access.noteAccess({ auth: 'on', user: 'ethan', admin: false, permissions: ['request'] })
  const offListener = deep(H.root(Cards.DoneRow)({ row: offRow }))
  check('...a listener: the tell under the line, and no setting anywhere',
    [byClass(offListener, 'app-job-line').map(text).slice(1), byClass(offListener, 'app-error-detail').length, JSON.stringify(offListener).includes('SLSKD_DOWNLOAD_PATH')],
    [['Tell whoever runs deadwax.'], 0, false])
  Access.forgetAccess()
  const filedRow = view([job('organized', { outcome: 'filed' })]).sections.done[0]
  check('...a filed row carries neither', [filedRow.reasonTell, filedRow.reasonDetail], [false, null])
}

/* ========================================================================== */
console.log('\nthe age, from updated_at')
{
  const age = (seconds) => V.ageText(ago(seconds), NOW)
  check('under a minute', [age(0), age(59)], ['just now', 'just now'])
  check('minutes', [age(60), age(12 * 60 + 30), age(59 * 60)], ['1 minute ago', '12 minutes ago', '59 minutes ago'])
  check('hours', [age(3600), age(3 * 3600), age(23 * 3600 + 59 * 60)], ['1 hour ago', '3 hours ago', '23 hours ago'])
  check('days', [age(24 * 3600), age(47 * 3600), age(48 * 3600), age(30 * 86400)], ['yesterday', 'yesterday', '2 days ago', '30 days ago'])
  check('a clock ahead of the phone\'s is never "in the future"', V.ageText(new Date(NOW + 90000).toISOString(), NOW), 'just now')
  check('nothing, or nonsense, says nothing', [V.ageText(null, NOW), V.ageText('', NOW), V.ageText('yesterday-ish', NOW)], ['', '', ''])
}

/* ========================================================================== */
console.log('\nArriving: exactly what the badge counts, at most three, and nothing when nothing is')
{
  const overlaysOf = (more) => ({ cancelling: new Set(), cleared: new Set(), pending: [], retrying: new Set(), ...more })
  const scenarios = []
  {
    const d = job('downloading'), q = job('queued'), o = job('organizing'), f = job('failed', { alternatives_left: 1 }), done = job('organized')
    scenarios.push(['every kind', [d, q, o, f, done], {}])
    scenarios.push(['one being cancelled', [d, q], { cancelling: new Set([d.id]) }])
    scenarios.push(['a failed one being retried', [f, done], { retrying: new Set([f.id]) }])
    scenarios.push(['a retry on a job already moving counts once', [d], { retrying: new Set([d.id]) }])
    scenarios.push(['requests asking and refused', [done], { pending: [{ key: 'a', artist: '', album: 'A', username: 'u' }, { key: 'b', artist: '', album: 'B', username: 'u', error: 'no' }] }])
    scenarios.push(['nothing moving', [done, f], {}])
  }
  for (const [label, jobs, more] of scenarios) {
    const v = V.requestsView(input(jobs, more), NOW)
    check(`${label}: Arriving counts what the badge counts`, v.arriving.length, O.activeCount(jobs, overlaysOf(more)))
  }
  //? where the two could part, the list is right - and App gives the badge the list's length, so
  //? they can't: a retry's overlay left on a job that has finished since (the phone locked straight
  //? after the tap, say) is drawn under Done, and activeCount alone would count it for good
  {
    const finished = job('organized', { outcome: 'filed' })
    const v = V.requestsView(input([finished], { retrying: new Set([finished.id]) }), NOW)
    check('a stale retry on a finished job: not arriving, though activeCount counts it',
      [v.arriving.length, O.activeCount([finished], overlaysOf({ retrying: new Set([finished.id]) })), v.sections.done.length], [0, 1, 1])
  }

  const four = [job('queued'), job('downloading', { progress: 50, files_done: 5 }), job('queued'), job('organizing')]
  const v = view(four, { pending: [{ key: 'p', artist: 'A', album: 'Asked', username: 'u' }] })
  check('in the order Requests has them: downloading first, then waiting', v.arriving.map((row) => row.section),
    ['downloading', 'downloading', 'waiting', 'waiting', 'waiting'])
  check('Home shows three', V.arrivingCards(v).length, V.ARRIVING_MAX)
  check('...and three is ARRIVING_MAX', V.ARRIVING_MAX, 3)
  check('nothing arriving: no cards', V.arrivingCards(view([job('organized'), job('failed')])).length, 0)

  const seen = []
  check('no rows: Arriving draws NOTHING - no heading, no section', H.root(Arriving)({ rows: [], onSeeAll: () => seen.push('all') }), null)
  const drawn = deep(H.root(Arriving)({ rows: V.arrivingCards(v), onSeeAll: () => seen.push('all') }))
  check('with rows: the heading "Arriving"', text(all(drawn, (n) => n.type === 'h2')), 'Arriving')
  const seeAll = all(drawn, (n) => n.type === 'button' && text(n) === 'See all')
  const cards = byClass(drawn, 'app-arriving-card')
  check('three cards and a See all', [cards.length, seeAll.length], [3, 1])
  seeAll[0].props.onClick()
  cards[1].props.onClick()
  check('See all, and a tap on a card, both go to Requests', seen, ['all', 'all'])
  check('a card: its title, the artist, the bar, and where it is', [text(byClass(cards[0], 'app-job-title')), text(byClass(cards[0], 'app-job-line')),
    byClass(cards[0], 'app-bar-fill')[0].props.style.width, text(byClass(cards[0], 'app-job-brief'))], ['Heligoland', 'Massive Attack', '50%', '5 of 10'])
  check('no note while deadwax answers', byClass(drawn, 'app-arriving-note').length, 0)
  const troubled = deep(H.root(Arriving)({ rows: V.arrivingCards(v), onSeeAll() {}, trouble: true }))
  check('deadwax not answering: the cards say they are its last answer, and it keeps asking',
    text(byClass(troubled, 'app-arriving-note')), "Can't update downloads right now - showing the last progress. Trying again…")

  //? Home rendered with Navidrome unset, down and still being asked: Arriving is deadwax's, and the
  //? gate draws in place of the shelf only - an Arriving inside the gate would show nowhere here
  for (const [label, status] of [['unset', { configured: false, ok: false, server: null, problem: null }],
    ['down', { configured: true, ok: false, server: null, problem: 'refused' }], ['not known yet', null]]) {
    const home = deep(H.root(Home)({ status, onRetry() {}, onOpen() {}, arriving: V.arrivingCards(v), onSeeAll() {} }))
    const titles = all(home, (n) => n.type === 'h2').map(text)
    check(`Home with Navidrome ${label}: Arriving still drawn, its cards there`, [titles.includes('Arriving'), byClass(home, 'app-arriving-card').length], [true, 3])
  }
  const homeNothing = deep(H.root(Home)({ status: null, onRetry() {}, onOpen() {}, arriving: [], onSeeAll() {} }))
  check('Home with nothing arriving: no Arriving heading at all', all(homeNothing, (n) => n.type === 'h2' && text(n) === 'Arriving').length, 0)
  const homeTrouble = deep(H.root(Home)({ status: null, onRetry() {}, onOpen() {}, arriving: V.arrivingCards(v), onSeeAll() {}, arrivingTrouble: true }))
  check('Home hands Arriving the trouble', byClass(homeTrouble, 'app-arriving-note').length, 1)

  const app = fs.readFileSync(path.join(UI, 'src/app/App.tsx'), 'utf8')
  check('App hands Home the cards, and one unchanging empty list when nothing is arriving',
    /const arriving = view\.arriving\.length \? arrivingCards\(view\) : NOTHING_ARRIVING/.test(app), true)
  check('...and the tab\'s badge the same list\'s length - one list, read twice - not the hook\'s own count',
    [/<TabBar\b[^>]*\barriving=\{view\.arriving\.length\}/.test(app), /activeCount/.test(app)], [true, false])
  check('See all and the cards go to the Requests tab\'s ROOT, whatever was left on it',
    /const seeRequests = useCallback\(\(\) => router\.root\('requests'\), \[\]\)/.test(app), true)
}

/* ========================================================================== */
console.log('\nwhat App is watching, and when a failed look keeps it asking')
{
  const at = (shown, tab, depth, sheetOpen) => V.watchingOf({ shown, tab, depth, sheetOpen })
  check('a tab\'s root showing', [at(true, 'requests', 0, false), at(true, 'home', 0, false), at(true, 'library', 0, false), at(true, 'you', 0, false)],
    ['requests', 'home', 'other', 'other'])
  check('an album pushed on Requests (Go to album) is not Requests: no fast poll behind it', [at(true, 'requests', 1, false), at(true, 'home', 2, false)], ['other', 'other'])
  check('Now Playing over a root: not that root', [at(true, 'requests', 0, true), at(true, 'home', 0, true)], ['other', 'other'])
  check('the page hidden (a locked phone): nothing, whatever shows', [at(false, 'requests', 0, false), at(false, 'home', 0, true)], ['hidden', 'hidden'])

  const stalls = V.stallsOn
  check('a failed look with something on its way, on Home or another tab: keep asking',
    [stalls('home', 'Failed to fetch', 2), stalls('other', 'Failed to fetch', 1)], [true, true])
  check('...not with nothing on its way, not without a failure, not hidden, not on Requests (which polls by itself)',
    [stalls('home', 'Failed to fetch', 0), stalls('home', null, 3), stalls('hidden', 'Failed to fetch', 3), stalls('requests', 'Failed to fetch', 3)],
    [false, false, false, false])
}

console.log('\nwhen App asks for the downloads again')
{
  const ask = (before, now) => V.asksAgain(before, now)
  check('Home coming into view asks', [ask('other', 'home'), ask('hidden', 'home')], [true, true])
  check('the app back from the background asks, on any tab but Requests', [ask('hidden', 'other'), ask('hidden', 'requests')], [true, false])
  check('Requests asks by itself (its open), coming or going', [ask('other', 'requests'), ask('home', 'requests'), ask('requests', 'home'), ask('requests', 'other')],
    [false, false, false, false])
  check('leaving Home, going hidden, or nothing changing: no', [ask('home', 'other'), ask('home', 'hidden'), ask('other', 'hidden'), ask('home', 'home'), ask('other', 'other')],
    [false, false, false, false, false])
}

/* ========================================================================== */
console.log('\nwhat a screen reader hears as rows change')
{
  //? what is said and what moved - `gone` (where focus goes from a card that went) has checks of its own
  const said = (before, after) => { const { said, moved } = V.changes(before, after); return { said, moved } }
  const f = job('failed', { error: 'offline', alternatives_left: 2, album: 'Heligoland' })
  const failedView = view([f])
  check('nothing to say the first time, or for the same view', [said(null, failedView), said(failedView, failedView)],
    [{ said: '', moved: [] }, { said: '', moved: [] }])
  const asking = view([f], { retrying: new Set([f.id]), retryingSame: new Set([f.id]) })
  check('a tap\'s answer starting: "asking again…"', said(failedView, asking).said, 'Heligoland: trying again…')
  const trying = view([f], { retrying: new Set([f.id]) })
  check('...or "trying next peer…"', said(failedView, trying).said, 'Heligoland: trying another source…')
  const refused = view([f], { retryProblems: new Map([[f.id, 'slskd is still stopping the last attempt - try again in a moment']]) })
  check('a retry\'s refusal, which is otherwise only a red line', said(asking, refused),
    //? (2.0.4) the retry route's words that name slskd, in a listener's (RETRY_WORDS)
    { said: 'Heligoland: The last try is still stopping - try again in a moment.', moved: [] })
  const moved = view([{ ...f, status: 'queued', error: null, queue_position: 2 }])
  check('a row under another heading: what it is now, and that it moved', said(trying, moved),
    { said: 'Heligoland: waiting', moved: [`job-${f.id}`] })
  const d = job('downloading', { album: 'Third' })
  const going = view([d]), cancellingView = view([d], { cancelling: new Set([d.id]) })
  check('a cancel tapped: "cancelling…"', said(going, cancellingView).said, 'Third: cancelling…')
  const stopped = view([{ ...d, status: 'cancelled', error: null }])
  check('...and then where it went, with why', said(cancellingView, stopped).said, 'Third: needs attention: Cancelled')
  const filed = view([{ ...d, status: 'organized', outcome: 'filed', updated_at: ago(0) }])
  check('a download finishing: how it ended', said(going, filed).said, 'Third: In your library · just now')
  check('two at once, in one breath, in the order the page lists them', said(view([d, f]), view([{ ...d, status: 'organized', outcome: 'filed', updated_at: ago(0) }, { ...f, status: 'queued', error: null }])).said,
    'Heligoland: waiting. Third: In your library · just now')
  check('a row just appeared, or gone (cleared): nothing', [said(view([]), going).said, said(going, view([])).said], ['', ''])
}

console.log('\nthe badge on the Requests tab')
{
  check('its number: none at zero, "99+" past 99', [V.badgeText(0), V.badgeText(3), V.badgeText(99), V.badgeText(150), V.badgeText(-1)], ['', '3', '99', '99+', ''])
  check('what VoiceOver hears', [V.badgeLabel('Requests', 2), V.badgeLabel('Requests', 0)], ['Requests, 2 arriving', 'Requests'])
  const bar = (arriving) => deep(H.root(TabBar)({ current: 'home', onSelect() {}, arriving }))
  const requestsTab = (tree) => all(tree, (n) => n.type === 'button' && text(byClass(n, 'app-tab-label')) === 'Requests')[0]
  const lit = requestsTab(bar(2))
  check('with downloads on their way: the count over the icon, heard with the tab', [text(byClass(lit, 'app-tab-badge')), lit.props['aria-label']],
    ['2', 'Requests, 2 arriving'])
  const dark = requestsTab(bar(0))
  check('at zero: no badge, and the tab\'s own name', [byClass(dark, 'app-tab-badge').length, dark.props['aria-label']], [0, undefined])
  check('only on Requests', all(bar(5), hasClass('app-tab-badge')).length, 1)
}

/* ========================================================================== */
console.log('\nthe cards: taps go to the hook\'s actions, and what each draws')
{
  const down = job('downloading', { progress: 60, files_done: 6, release_mbid: 'rel-1' })
  const row = view([down]).sections.downloading[0]
  const cancelled = []
  const card = deep(H.root(Cards.DownloadingCard)({ row, onCancel: (r) => cancelled.push(r.jobId) }))
  const cross = all(card, (n) => n.type === 'button' && n.props.class === 'app-job-cancel')[0]
  check('the ✕ is named for what it cancels, ready, and not asking', [cross.props['aria-label'], cross.props['aria-disabled'], cross.props['aria-expanded']],
    ['Cancel Heligoland', false, false])
  cross.props.onClick()
  check('...and hands the row to the page', cancelled, [down.id])
  check('the data line and the cover', [text(byClass(card, 'app-job-data')), all(card, (n) => n.type === 'img')[0].props.src],
    ['6 of 10 files', 'https://coverartarchive.org/release/rel-1/front-250'])
  check('not faded while it downloads', byClass(card, 'is-dimmed').length, 0)
  const filing = deep(H.root(Cards.DownloadingCard)({ row: view([job('organizing')]).sections.downloading[0], onCancel() {} }))
  check('being filed: no ✕', all(filing, (n) => n.props.class === 'app-job-cancel').length, 0)

  //? being cancelled: faded, its ✕ waiting - aria-disabled, so focus stays on it, and the tap refused
  //? here, so a second tap can't send a second cancel
  const going = job('downloading', { files_done: 2 })
  const tapped = []
  const fading = deep(H.root(Cards.DownloadingCard)({ row: view([going], { cancelling: new Set([going.id]) }).sections.downloading[0], onCancel: (r) => tapped.push(r.jobId) }))
  const waitingCross = all(fading, (n) => n.props.class === 'app-job-cancel')[0]
  check('being cancelled: the card faded, its ✕ aria-disabled (never disabled)', [byClass(fading, 'is-dimmed').length, waitingCross.props['aria-disabled'], waitingCross.props.disabled],
    [1, true, undefined])
  waitingCross.props.onClick()
  check('...and a second tap on it sends nothing', tapped, [])

  //? asking first, in the card
  const keeps = [], confirmed = []
  const asked = deep(H.root(Cards.WaitingCard)({ row: view([job('queued')]).sections.waiting[0], onCancel() {}, asking: true, onKeep: () => keeps.push(1), onConfirm: (r) => confirmed.push(r.jobId) }))
  const question = byClass(asked, 'app-job-confirm')[0]
  const askedCross = all(asked, (n) => n.props.class === 'app-job-cancel')[0]
  check('asking: the question in the card, the ✕ saying it is open and naming it', [text(byClass(question, 'app-job-confirm-text')), askedCross.props['aria-expanded'], askedCross.props['aria-controls'] === question.props.id, byClass(asked, 'is-asking').length],
    ["Cancel this download? You'll lose your place in their queue.", true, true, 1])
  const [keepButton, cancelButton] = all(question, (n) => n.type === 'button')
  check('..."Keep it" secondary, "Cancel download" secondary in red - neither the solid purple', [text(keepButton), keepButton.props.class, text(cancelButton), cancelButton.props.class],
    ['Keep it', 'app-job-action is-secondary', 'Cancel download', 'app-job-action is-secondary is-danger'])
  keepButton.props.onClick()
  cancelButton.props.onClick()
  check('...each answer handed to the page', [keeps.length, confirmed.length], [1, 1])

  const refusedWait = deep(H.root(Cards.WaitingCard)({ row: view([job('queued', { queue_position: 4, files_failed: 3 })]).sections.waiting[0], onCancel() {} }))
  check('a Waiting card with refused files: its line in amber', byClass(refusedWait, 'app-job-line')[0].props.class, 'app-job-line is-warning')

  const failed = job('failed', { error: 'offline', alternatives_left: 2 })
  const retried = []
  const attention = deep(H.root(Cards.AttentionCard)({ row: view([failed]).sections.attention[0], onRetry: (r, same) => retried.push([r.jobId, same]) }))
  const [nextButton, againButton] = all(attention, (n) => n.type === 'button')
  check('Next peer is primary, Ask again secondary', [nextButton.props.class, againButton.props.class],
    ['app-job-action is-primary', 'app-job-action is-secondary'])
  check('...each label a span inside its button, where the ellipsis goes (clipping the button would clip its reach)',
    [byClass(nextButton, 'app-job-action-label').length, text(byClass(againButton, 'app-job-action-label'))], [1, 'Same source again'])
  nextButton.props.onClick()
  againButton.props.onClick()
  check('Next peer is retry on the next peer, Ask again on the same one', retried, [[failed.id, false], [failed.id, true]])
  const busyTaps = []
  const busy = deep(H.root(Cards.AttentionCard)({ row: view([failed], { retrying: new Set([failed.id]) }).sections.attention[0], onRetry: (r, same) => busyTaps.push(same) }))
  const busyButtons = all(busy, (n) => n.type === 'button')
  check('while a retry runs both buttons wait - aria-disabled, so the focus on the one tapped stays',
    busyButtons.map((b) => [b.props['aria-disabled'], b.props.disabled]), [[true, undefined], [true, undefined]])
  busyButtons.forEach((b) => b.props.onClick())
  check('...and a tap on either sends nothing', busyTaps, [])
  const refusedRow = view([failed], { retryProblems: new Map([[failed.id, 'no other peer would take it']]) }).sections.attention[0]
  const refusal = deep(H.root(Cards.AttentionCard)({ row: refusedRow, onRetry() {} }))
  check('a retry nobody would take: a second red line, under the reason', byClass(refusal, 'app-job-reason').map(text), ['offline', 'no other peer would take it'])
  const alone = deep(H.root(Cards.AttentionCard)({ row: view([job('failed', { error: 'x' })]).sections.attention[0], onRetry() {} }))
  check('Ask again alone takes the width', byClass(alone, 'app-job-actions')[0].props.class, 'app-job-actions is-single')

  const partly = deep(H.root(Cards.DoneRow)({ row: view([job('complete', { outcome: 'partly_filed', error: '2 file(s) failed to organize' })]).sections.done[0] }))
  const interrupted = deep(H.root(Cards.DoneRow)({ row: view([job('complete', { outcome: 'interrupted', error: 'x' })]).sections.done[0] }))
  const filed = deep(H.root(Cards.DoneRow)({ row: view([job('organized', { outcome: 'filed' })]).sections.done[0] }))
  check('Done: Partly filed and Interrupted in amber, In your library plain',
    [partly, interrupted, filed].map((tree) => byClass(tree, 'app-job-line')[0].props.class), ['app-job-line is-warning', 'app-job-line is-warning', 'app-job-line'])

  const coverOf = H.root(Cards.JobCover)
  const first = coverOf({ src: 'https://coverartarchive.org/release/x/front-250' })
  check('a cover is an image', first.type, 'img')
  first.props.onError()
  const after = coverOf({ src: 'https://coverartarchive.org/release/x/front-250' })
  check('...and after it fails (offline, or no picture) the plain tile, never a broken image', [after.type, after.props.class], ['span', 'app-job-cover is-empty'])
  check('the next pressing\'s cover is still asked for', coverOf({ src: 'https://coverartarchive.org/release/y/front-250' }).type, 'img')
  check('no release id: the plain tile', H.root(Cards.JobCover)({ src: null, large: true }).props.class, 'app-job-cover is-large is-empty')
}

/* ========================================================================== */
console.log('\nthe Requests tab as a whole')
{
  const calls = []
  const actions = {
    onCancel: async (id) => { calls.push(['cancel', id]) },
    onRetry: async (id, same) => { calls.push(['retry', id, !!same]) },
    onClear: async () => { calls.push(['clear']) },
  }
  const page = (v, more = {}) => deep(H.root(Requests)({ view: v, trackingEnabled: true, error: null, ...actions, ...more }))
  const headings = (tree) => all(tree, (n) => n.type === 'h2').map(text)

  const down = job('downloading', { files_done: 1 })
  const f1 = job('failed', { error: 'offline', alternatives_left: 3 })
  const f2 = job('failed', { error: 'refused', alternatives_left: 1 })
  const tree = page(view([down, f1, f2, job('organized', { outcome: 'filed' })]))
  check('only the headings with something under them, in order', headings(tree), ['Downloading', 'Needs attention', 'Done'])
  check('exactly one solid purple button on the screen', byClass(tree, 'is-primary').length, 1)
  check('...the other Next peer tinted', byClass(tree, 'is-tinted').length, 1)
  check('each heading drawn with its own card: Downloading a card, Needs attention cards, Done plain rows',
    [byClass(tree, 'is-downloading').length, byClass(tree, 'is-attention').length, byClass(tree, 'app-done-row').length], [1, 2, 1])
  check('every row is a list item a moved card\'s focus can go to', all(tree, (n) => n.type === 'li').map((n) => [n.props['data-row'] === n.key, n.props.tabIndex]),
    [[true, -1], [true, -1], [true, -1], [true, -1]])
  check('a polite, atomic live region, there before anything is said', all(tree, (n) => n.props.role === 'status' && n.props['aria-live'] === 'polite' && n.props['aria-atomic'] === 'true').length, 1)

  const clear = all(tree, (n) => n.type === 'button' && text(n) === 'Clear done')[0]
  check('Clear done in the title row, with something to clear', [clear.props.disabled], [false])
  clear.props.onClick()
  const idle = page(view([job('downloading')]))
  check('...disabled when nothing is finished', all(idle, (n) => n.type === 'button' && text(n) === 'Clear done')[0].props.disabled, true)

  //? the ✕, through the page: one root, so its state lasts between renders
  const live = H.root(Requests)
  const v = view([down, f1, f2])
  const draw = () => deep(live({ view: v, trackingEnabled: true, error: null, ...actions }))
  const crossOf = (t) => all(t, (n) => n.props.class === 'app-job-cancel')[0]
  crossOf(draw()).props.onClick()
  let shown = draw()
  check('the ✕ asks first, IN the card - no window.confirm(), nothing cancelled yet', [byClass(shown, 'app-job-confirm').length, confirms.length, calls.filter((c) => c[0] === 'cancel').length], [1, 0, 0])
  all(shown, (n) => n.type === 'button' && text(n) === 'Keep it')[0].props.onClick()
  shown = draw()
  check('"Keep it" closes the question and cancels nothing', [byClass(shown, 'app-job-confirm').length, calls.filter((c) => c[0] === 'cancel').length], [0, 0])
  crossOf(shown).props.onClick()
  crossOf(draw()).props.onClick()
  check('a second tap on the ✕ closes the question too', byClass(draw(), 'app-job-confirm').length, 0)
  crossOf(draw()).props.onClick()
  all(draw(), (n) => n.type === 'button' && text(n) === 'Cancel download')[0].props.onClick()
  shown = draw()
  check('"Cancel download" cancels it, and the question goes', [calls.filter((c) => c[0] === 'cancel'), byClass(shown, 'app-job-confirm').length], [[['cancel', down.id]], 0])
  //? "Confirm before cancelling" is this device's since 2.0.0-player.41 (You > Getting albums), carried
  //? over ONCE from the main page's own: the first ✕ above read it, the main page said nothing, so
  //? it was marked carried over as the default - and the main page turning it off now changes nothing
  check('the first ✕ carried the main page\'s setting over, once: nothing said there, so the default - stored as such, not as a choice',
    stored.get('deadwax-player-confirm-cancel'), 'default')
  stored.set('deadwax-preferences', JSON.stringify({ confirmCancel: false }))
  crossOf(draw()).props.onClick()
  check('...so the main page turned off since is not read again: the ✕ still asks', [calls.filter((c) => c[0] === 'cancel').length, byClass(draw(), 'app-job-confirm').length], [1, 1])
  all(draw(), (n) => n.type === 'button' && text(n) === 'Keep it')[0].props.onClick()
  stored.set('deadwax-player-confirm-cancel', 'off')
  crossOf(draw()).props.onClick()
  check('with You\'s "Confirm before cancelling" off, the ✕ cancels at once', [calls.filter((c) => c[0] === 'cancel').length, byClass(draw(), 'app-job-confirm').length], [2, 0])
  stored.delete('deadwax-player-confirm-cancel')
  stored.delete('deadwax-preferences')
  check('and never a blocking dialog, all along', confirms.length, 0)

  const buttons = all(tree, (n) => n.type === 'button' && /^(Another source|Same source again)/.test(text(n)))
  buttons[0].props.onClick()
  buttons[1].props.onClick()
  check('clear, and the retries, reach the hook\'s actions', calls.filter((c) => c[0] !== 'cancel'), [['clear'], ['retry', f1.id, false], ['retry', f1.id, true]])

  const waiting = page(view([]), { answered: false })
  check('before deadwax has answered: a spinner, and no "Nothing requested yet"',
    [byClass(waiting, 'pl-spinner').length, all(waiting, (n) => text(n) === 'Nothing requested yet').length], [1, 0])
  const empty = page(view([]))
  check('nothing yet, once it has answered: says so, and draws no heading', [text(byClass(empty, 'app-placeholder-lead')), headings(empty), byClass(empty, 'pl-spinner').length], ['Nothing requested yet', [], 0])
  //? (2.0.4) the error itself, as fetch throws it: in a listener's words, fetch's own under them for whoever runs deadwax
  const failing = page(view([down]), { error: 'Failed to fetch', failure: new TypeError('Failed to fetch') })
  check('deadwax not answering: says so in a listener\'s words, and keeps the rows from the last answer',
    [text(byClass(failing, 'app-placeholder-lead')), text(byClass(failing, 'app-error')), text(byClass(failing, 'app-error-detail')), headings(failing)],
    ["Can't update your requests right now", "Can't connect to deadwax.Failed to fetch", 'Failed to fetch', ['Downloading']])
  check('...and with nothing to show, no "Nothing requested yet" under the failure',
    all(page(view([]), { error: 'Failed to fetch' }), (n) => text(n) === 'Nothing requested yet').length, 0)
  const untracked = page(view([]), { trackingEnabled: false })
  check('a database deadwax can\'t write: says so, and where to look', [text(byClass(untracked, 'app-placeholder-lead')), text(byClass(untracked, 'app-mono'))],
    ["Downloads aren't being kept track of", 'DB_PATH'])
  //? (2.0.4) to someone who doesn't run deadwax: no DB_PATH, and to tell whoever does - and no fetch words under a failure
  Access.noteAccess({ auth: 'on', user: 'ethan', admin: false, permissions: ['request'] })
  //? (2.0.6, UX batch 3) "find one in Search and tap Get" only to someone who can Get: anyone else is told Getting is off
  check('(2.0.6) ...how to fill it, for someone who can Get', text(byClass(page(view([])), 'app-placeholder-text')),
    "Albums you get show here while they download, and once they've arrived - find one in Search and tap Get.")
  Access.noteAccess({ auth: 'on', user: 'ethan', admin: false, permissions: [] })
  check('(2.0.6) ...and without Get albums, never "tap Get": Getting is off for them', text(byClass(page(view([])), 'app-placeholder-text')),
    'Getting albums is off for you - ask an admin.')
  Access.noteAccess({ auth: 'on', user: 'ethan', admin: false, permissions: ['request'] })
  const untrackedListener = page(view([]), { trackingEnabled: false })
  const failingListener = page(view([down]), { error: 'Failed to fetch', failure: new TypeError('Failed to fetch') })
  check('...a listener: no DB_PATH, and to tell whoever runs deadwax; a failure with no detail under it',
    [text(byClass(untrackedListener, 'app-placeholder-text')), byClass(untrackedListener, 'app-mono').length, text(byClass(failingListener, 'app-error')), byClass(failingListener, 'app-error-detail').length],
    [Q.UNTRACKED_TEXT, 0, "Can't connect to deadwax.", 0])
  check('...which says so', Q.UNTRACKED_TEXT, "Requests can't be shown right now: deadwax can't keep track of downloads. Tell whoever runs deadwax.")
  //? (2.0.4) a download filing couldn't use, drawn: a listener reads why and to tell whoever runs deadwax - never
  //? SLSKD_DOWNLOAD_PATH; whoever runs it reads the job's own words under the reason instead
  const unfiled = view([job('complete', { outcome: 'not_filed', error: 'nothing could be organized, check SLSKD_DOWNLOAD_PATH', alternatives_left: 1 })]).sections.attention[0]
  const reasonOf = (drawn) => byClass(drawn, 'app-job-reason').map(text)
  check('...a listener\'s card: the reason and the tell, no setting',
    reasonOf(deep(H.root(Cards.AttentionCard)({ row: unfiled, onRetry() {} }))),
    ["It downloaded, but deadwax couldn't find its files to add them to your library. Tell whoever runs deadwax."])
  Access.forgetAccess()
  check('...whoever runs deadwax\'s: the reason, and the job\'s own words under it',
    [reasonOf(deep(H.root(Cards.AttentionCard)({ row: unfiled, onRetry() {} }))), text(byClass(deep(H.root(Cards.AttentionCard)({ row: unfiled, onRetry() {} })), 'app-error-detail'))],
    [["It downloaded, but deadwax couldn't find its files to add them to your library.nothing could be organized, check SLSKD_DOWNLOAD_PATH"], 'nothing could be organized, check SLSKD_DOWNLOAD_PATH'])
  //? (review) a retry that couldn't start, its own words plumbing: a listener reads the sentence alone, whoever runs
  //? deadwax the words under it
  const stuck = job('failed', { error: 'offline', alternatives_left: 1 })
  const stuckRow = view([stuck], { retryProblems: new Map([[stuck.id, 'slskd refused the enqueue: HTTP 500 from POST /api/v0/transfers']]) }).sections.attention[0]
  const detailOf = (drawn) => byClass(drawn, 'app-error-detail').map(text)
  Access.noteAccess({ auth: 'on', user: 'ethan', admin: false, permissions: ['request'] })
  const stuckListener = deep(H.root(Cards.AttentionCard)({ row: stuckRow, onRetry() {} }))
  check('...a retry that couldn\'t start, to a listener: the sentence, never the retry\'s own words',
    [reasonOf(stuckListener), detailOf(stuckListener), JSON.stringify(stuckListener).includes('HTTP 500')], [['offline', "The download couldn't be started."], [], false])
  Access.forgetAccess()
  check('...to whoever runs deadwax: the retry\'s own words under it', detailOf(deep(H.root(Cards.AttentionCard)({ row: stuckRow, onRetry() {} }))),
    ['slskd refused the enqueue: HTTP 500 from POST /api/v0/transfers'])

  //? the live region says what changed between two views
  const speak = H.root(Requests)
  const regionOf = (t) => text(all(t, (n) => n.props.role === 'status' && n.props['aria-live'] === 'polite')[0])
  const before = view([f1])
  deep(speak({ view: before, trackingEnabled: true, error: null, ...actions }))
  const refusedView = view([f1], { retryProblems: new Map([[f1.id, 'the peer refused']]) })
  check('the live region reads out a refused retry', regionOf(deep(speak({ view: refusedView, trackingEnabled: true, error: null, ...actions }))), 'Heligoland: the peer refused')
  check('...and keeps it through a re-render that changes nothing', regionOf(deep(speak({ view: refusedView, trackingEnabled: true, error: null, ...actions }))), 'Heligoland: the peer refused')
}

/* ========================================================================== */
console.log('\ndownloads per person (2.0.0-player.49): who asked, what a cancel does, and what joining offers')
{
  const P = require(path.join(OUT, 'lib/perPerson.js'))
  //? logins off - none of the fields - and a user's own row: no line, and the question as it was
  const plain = view([job('queued')]).sections.waiting[0]
  check('logins off: no "asked by", the cancel as it always was', [plain.askedBy, plain.cancelWords],
    [null, { question: "Cancel this download? You'll lose your place in their queue.", action: 'Cancel download', leaves: false }])
  const own = view([job('queued', { mine: true, shared: false })]).sections.waiting[0]
  check('a user\'s own, nobody else waiting: the same', [own.askedBy, own.cancelWords.action], [null, 'Cancel download'])

  //? a user's on a download somebody else waits for too: cancel LEAVES it
  const sharedJob = job('downloading', { mine: true, shared: true, album: 'Shared' })
  const leaving = view([sharedJob]).sections.downloading[0]
  check('a user\'s shared download: that somebody else waits, never who (the admin\'s to see) - and the ✕ leaves it', [leaving.askedBy, leaving.cancelWords],
    ['Someone else asked for it too', { question: 'Leave this download? Someone else asked for it too, so it carries on for them.', action: 'Leave it', leaves: true }])

  //? an admin's rows: who asked, and a cancel that is for everyone
  const theirs = view([job('queued', { mine: false, shared: true, requested_by: ['ethan'] })]).sections.waiting[0]
  check('an admin\'s row of ethan\'s: "Asked by ethan", and the ✕ cancels it for him too', [theirs.askedBy, theirs.cancelWords],
    ['Asked by ethan', { question: 'Cancel this download for everyone? ethan asked for it.', action: 'Cancel for everyone', leaves: false }])
  const both = view([job('organized', { outcome: 'filed', mine: true, shared: true, requested_by: ['ethan', 'sam'] })]).sections.done[0]
  check('...one they share: "Asked by you, ethan and sam" - the others in the order they asked', [both.askedBy, P.cancelWords({ mine: true, shared: true, requested_by: ['ethan'] }).question],
    ['Asked by you, ethan and sam', 'Cancel this download for everyone? ethan asked for it too.'])
  const alone = view([job('queued', { mine: true, shared: false, requested_by: [] })]).sections.waiting[0]
  check('...and one only they asked for says nothing more', [alone.askedBy, alone.cancelWords.action], [null, 'Cancel download'])
  //? (2.0.0-player.61) one nobody waits for - its one asker removed in People: it carries on, filed for nobody
  const nobody = view([job('queued', { mine: false, shared: false, requested_by: [] })]).sections.waiting[0]
  check('...and one nobody waits for any more says so', [nobody.askedBy, nobody.cancelWords.action], ['Nobody is waiting for this any more', 'Cancel download'])

  //? drawn: the line under the title, and the question's words
  const drawnWait = deep(H.root(Cards.WaitingCard)({ row: theirs, onCancel() {}, asking: true, onKeep() {}, onConfirm() {} }))
  check('the card says who asked, under its line', byClass(drawnWait, 'app-job-line').map(text), ['Massive Attack · from mellotron · starting', 'Asked by ethan'])
  const question = byClass(drawnWait, 'app-job-confirm')[0]
  check('...and asks what its cancel does', [text(byClass(question, 'app-job-confirm-text')), all(question, (n) => n.type === 'button').map(text)],
    ['Cancel this download for everyone? ethan asked for it.', ['Keep it', 'Cancel for everyone']])
  const drawnDone = deep(H.root(Cards.DoneRow)({ row: both }))
  check('a Done row says who asked too', byClass(drawnDone, 'app-job-line').map(text).includes('Asked by you, ethan and sam'), true)
  const drawnDown = deep(H.root(Cards.DownloadingCard)({ row: theirs.section === 'downloading' ? theirs : view([job('downloading', { mine: false, shared: true, requested_by: ['ethan'] })]).sections.downloading[0], onCancel() {} }))
  check('...and a Downloading card', byClass(drawnDown, 'app-job-line').map(text).includes('Asked by ethan'), true)
  const drawnAttention = deep(H.root(Cards.AttentionCard)({ row: view([job('failed', { error: 'offline', mine: false, shared: true, requested_by: ['ethan'] })]).sections.attention[0], onRetry() {} }))
  check('...and a Needs attention card', byClass(drawnAttention, 'app-job-line').map(text).includes('Asked by ethan'), true)

  //? how a folder's quality is put for a Get to send, for someone offered to join it (that a Get sends
  //? it, and each runner-up's, is sources.sim's)
  check('a folder\'s quality, as a Get sends it', P.candidateQuality({ formats: ['flac'], bitrates: [], bit_depths: [24], sample_rates: [96000], variable_bitrate: false }),
    { formats: ['flac'], bitrates: [], bit_depths: [24], sample_rates: [96000], variable_bitrate: false })

  //? the store line for somebody else's download
  const theirsInFlight = (fields = {}) => ({ job_id: 9, status: 'queued', username: 'bob', files: 10, yours: false, formats: ['flac'], bitrates: [], bit_depths: [16], sample_rates: [44100], variable_bitrate: false, ...fields })
  const answerWith = (downloading) => ({ held: null, downloading })
  check('somebody else\'s download: who from, the copy as a source card says it, how far, what Join does - and the job Join joins',
    P.storeStatusFor(answerWith(theirsInFlight({ bitrates: [902] })), 'Requests', 'any'),
    { kind: 'downloading', title: 'Already downloading for someone else',
      lines: ['From bob · FLAC 16/44.1 · queued', 'Join it to have it in your Requests too - one download, everyone who asked waiting for it.'], joinJobId: 9 })
  check('...the main page\'s names its own place, Downloads', P.storeStatusFor(answerWith(theirsInFlight()))?.lines[1],
    'Join it to have it in your Downloads too - one download, everyone who asked waiting for it.')
  //? (2.0.0-player.65, the release review's nit) drawn with no Join - someone without Get albums: no "Join it" either
  const noJoin = P.withoutJoin(P.storeStatusFor(answerWith(theirsInFlight()), 'Requests', '24bit'))
  check('...drawn with no Join under it: the line saying what Join does goes, and the job it would join; the rest stays',
    [noJoin.lines, 'joinJobId' in noJoin, noJoin.title],
    [['From bob · FLAC 16/44.1 · queued', "It's below your quality floor (24-bit), and getting a copy of your own isn't offered yet."], false,
      'Already downloading for someone else'])
  check('...a line with no Join in it is left as it is', P.withoutJoin(P.storeStatusFor(answerWith(theirsInFlight({ yours: true })), 'Requests')),
    P.storeStatusFor(answerWith(theirsInFlight({ yours: true })), 'Requests'))
  check('the copy: lossless by depth and rate, never a bitrate; lossy by its bitrate - a source card\'s Quality',
    [P.copyText(theirsInFlight({ bitrates: [902] })), P.copyText(theirsInFlight({ formats: ['flac'], bit_depths: [24], sample_rates: [96000], bitrates: [2800, 3100] })),
      P.copyText(theirsInFlight({ formats: ['mp3'], bitrates: [320], bit_depths: [], sample_rates: [44100] })), P.copyText(theirsInFlight({ formats: [] }))],
    ['FLAC 16/44.1', 'FLAC 24/96', 'MP3 320k', ''])
  check('...being filed: already downloaded', P.storeStatusFor(answerWith(theirsInFlight({ status: 'organizing' })), 'Requests', 'any').title, 'Already downloaded for someone else')
  check('...below your floor: said, with no copy of your own offered yet', P.storeStatusFor(answerWith(theirsInFlight()), 'Requests', '24bit').lines[1],
    "It's below your quality floor (24-bit), and getting a copy of your own isn't offered yet.")
  check('...a floor its folder doesn\'t answer: said as unknown, not as below', P.storeStatusFor(answerWith(theirsInFlight({ bit_depths: [] })), 'Requests', '24bit').lines[1],
    "Its quality isn't known, so it may be below your quality floor (24-bit), and getting a copy of your own isn't offered yet.")
  check('the floor\'s own rules: lossless meets Lossless and 320; a 320 MP3 meets 320 but not Lossless; Any always',
    [P.floorVerdict(theirsInFlight(), 'lossless'), P.floorVerdict(theirsInFlight(), '320'), P.floorVerdict(theirsInFlight({ formats: ['mp3'], bitrates: [320], bit_depths: [] }), '320'),
      P.floorVerdict(theirsInFlight({ formats: ['mp3'], bitrates: [320], bit_depths: [] }), 'lossless'), P.floorVerdict(theirsInFlight({ formats: [] }), 'any')],
    [null, null, null, 'below', null])
  check('...and a copy known only by its files\' names: the format alone', P.copyText({ job_id: 1, status: 'queued', username: 'bob', files: 2, formats: ['flac'] }), 'FLAC')
  check('your own, or logins off (no `yours`): the store line word for word as it was', [P.storeStatusFor(answerWith(theirsInFlight({ yours: true })), 'Requests').title,
    P.storeStatusFor(answerWith({ job_id: 3, status: 'queued', username: 'bob', files: 11 }), 'Requests').lines],
    ['Already downloading', ['From bob · queued', 'To get it from another source, cancel it in Requests first.']])

  //? your own that somebody else waits for too: a user's cancel only leaves it - no peer is a cancel away
  check('your own, shared, as a user: what a cancel does there instead of "another peer"', P.storeStatusFor(answerWith(theirsInFlight({ yours: true, shared: true })), 'Requests').lines,
    ['From bob · queued', "Someone else asked for it too, so cancelling it in Requests only takes it off your list - another source isn't offered for a download you share."])
  check('...an admin\'s (their cancel is for everyone): as it was', P.storeStatusFor(answerWith(theirsInFlight({ yours: true, shared: true, requested_by: ['ethan'] })), 'Requests').lines,
    ['From bob · queued', 'To get it from another source, cancel it in Requests first.'])

  //? failed, its retry pending (AUTO_RETRY_PEER): moving to the next peer by itself - logins on or off
  const moving = { job_id: 4, status: 'failed', username: 'bob', files: 11 }
  check('a download moving to its next peer: said so, and nothing about cancelling it for one', P.storeStatusFor(answerWith(moving), 'Requests'),
    { kind: 'downloading', title: 'Already downloading', lines: ["From bob · didn't work - trying another source"] })
  check('...the same when it\'s somebody else\'s', P.storeStatusFor(answerWith({ ...theirsInFlight(), status: 'failed' }), 'Requests').lines[0],
    "From bob · FLAC 16/44.1 · didn't work - trying another source")

  //? leaving: the overlay, what is heard, and where focus goes once the card has gone from the list
  const leavingNow = view([sharedJob], { cancelling: new Set([sharedJob.id]) })
  check('a leave on its way says "leaving…", not "cancelling…"', [leavingNow.sections.downloading[0].data, leavingNow.sections.downloading[0].brief], ['leaving…', 'leaving…'])
  const waitingShared = job('queued', { mine: true, shared: true, album: 'Waiting' })
  check('...a waiting card too', view([waitingShared], { cancelling: new Set([waitingShared.id]) }).sections.waiting[0].line, 'Massive Attack · from mellotron · leaving…')
  const other = job('downloading', { album: 'Other' })
  const shown = view([sharedJob, other])
  const tapped = view([sharedJob, other], { cancelling: new Set([sharedJob.id]) })
  const after = view([other])
  check('...and is heard so', V.changes(shown, tapped).said, 'Shared: leaving…')
  const went = V.changes(tapped, after)
  check('the card gone from your list: heard that it carries on for the others, and focus to the card beside it',
    [went.said, [...went.gone.entries()]], ['Shared: left - it carries on for whoever else asked', [[`job-${sharedJob.id}`, `job-${other.id}`]]])
  check('...a card cleared away says nothing, as before', V.changes(view([other]), view([])).said, '')
  const third = job('queued', { album: 'Third' })
  check('focus from a gone card: the one after it, else before it, else the first on the page, else none (the heading)',
    [V.focusAfterGone(view([sharedJob, other]), view([sharedJob]), `job-${other.id}`), V.focusAfterGone(view([other, third]), view([third]), `job-${other.id}`),
      V.focusAfterGone(view([other]), view([third]), `job-${other.id}`), V.focusAfterGone(view([other]), view([]), `job-${other.id}`)],
    [`job-${sharedJob.id}`, `job-${third.id}`, `job-${third.id}`, null])
  const row3 = [job('downloading', { album: 'A' }), job('downloading', { album: 'B' }), job('downloading', { album: 'C' })]
  const listed = view(row3).sections.downloading.map((row) => row.key)
  check('...under one heading, the card that came AFTER it, not the one before',
    V.focusAfterGone(view(row3), view(row3.filter((each) => `job-${each.id}` !== listed[1])), listed[1]), listed[2])
  const drawnLeave = deep(H.root(Cards.DownloadingCard)({ row: leaving, onCancel() {}, asking: true, onKeep() {}, onConfirm() {} }))
  check('the ✕ and its question are named for leaving', [all(drawnLeave, (n) => n.props.class === 'app-job-cancel')[0].props['aria-label'],
    byClass(drawnLeave, 'app-job-confirm')[0].props['aria-label']], ['Leave Shared', 'Leave Shared?'])
  check('...and a user\'s card says somebody else waits for it', byClass(drawnLeave, 'app-job-line').map(text).includes('Someone else asked for it too'), true)
}

console.log('\njoining a download tells every downloads list in the page to ask again (2.0.0-player.49)')
{
  const asked = []
  globalThis.__joinAnswer = (jobId) => { asked.push(jobId); return Promise.resolve({ status: 'ok', job_id: jobId, joined: true }) }
  const R = require(path.join(OUT, 'lib/downloadRequests.js'))
  const heard = []
  const stop = R.onDownloadsChanged(() => heard.push('panel'))
  R.onDownloadsChanged(() => heard.push('requests'))
  await_(async () => {
    const joined = await R.joinDownload(7)
    check('a join asks deadwax, answers whether you joined, and tells every list', [asked, joined, heard], [[7], true, ['panel', 'requests']])
    stop()
    await R.joinDownload(8)
    check('...a list that stopped listening isn\'t told', heard, ['panel', 'requests', 'requests'])
    globalThis.__joinAnswer = () => Promise.reject(new Error('that download has been cancelled since - get it again to see where it stands'))
    let refused = null
    await R.joinDownload(9).catch((caught) => { refused = caught.message })
    check('...a refusal is deadwax\'s words, and nobody is told to ask again', [refused, heard.length],
      ['that download has been cancelled since - get it again to see where it stands', 3])
  })
}

console.log('\nthe downloads hook itself asks again after a join, effects running (2.0.0-player.49)')
{
  const { useDownloadJobs } = require(path.join(OUT, 'hooks/useDownloadJobs.js'))
  const R = require(path.join(OUT, 'lib/downloadRequests.js'))
  await_(async () => {
    const tick = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))
    globalThis.__effects = true
    try {
      const hook = H.root(({ open }) => useDownloadJobs(open))
      globalThis.__listed = 0
      hook({ open: false })
      hook.commit()
      await tick()
      hook({ open: false })
      hook.commit()
      await tick()
      check('mounted, closed and nothing active: the jobs asked for once, and no more', globalThis.__listed, 1)
      globalThis.__joinAnswer = (jobId) => Promise.resolve({ status: 'ok', job_id: jobId, joined: true })
      await R.joinDownload(11)
      hook({ open: false })
      hook.commit()
      await tick()
      check('...a download joined anywhere in the page: asked for again at once, so it is listed', globalThis.__listed, 2)
    } finally {
      globalThis.__effects = false
    }
  })
}

console.log('\nRequests puts focus where a left card\'s went, its layout effect run (2.0.0-player.49)')
{
  const body = { tag: 'body' }
  const focused = []
  const cardFor = (key) => ({ focus: () => focused.push(key) })
  const withDocument = (fn) => {
    const had = { document: globalThis.document, CSS: globalThis.CSS }
    globalThis.document = { body, activeElement: body }
    globalThis.CSS = { escape: (value) => value }
    globalThis.__layoutEffects = true
    try { fn() } finally {
      globalThis.__layoutEffects = false
      globalThis.document = had.document
      globalThis.CSS = had.CSS
    }
  }
  //? the page drawn and committed, its refs pointed at stand-ins: the section finds cards by data-row
  const mount = () => {
    const tab = H.root(Requests)
    let tree = null
    const draw = (jobs, more) => {
      tree = tab({ view: view(jobs, more), trackingEnabled: true, error: null, active: true, onCancel: async () => {}, onRetry: async () => {}, onClear: async () => {}, onOpenAlbum() {} })
      const section = all(tree, (n) => n.type === 'section' && n.props.ref)[0]
      section.props.ref.current = {
        querySelector: (selector) => { const key = /data-row="([^"]+)"/.exec(selector)?.[1]; return key ? cardFor(key) : null },
        contains: () => true,
      }
      all(tree, (n) => n.type === 'h1' && n.props.ref)[0].props.ref.current = { focus: () => focused.push('heading') }
      tab.commit()
      return tree
    }
    const focusIn = (key) => all(tree, (n) => n.type === 'section' && n.props.onFocusIn)[0].props
      .onFocusIn({ target: { closest: () => ({ dataset: { row: key } }) } })
    return { draw, focusIn }
  }
  withDocument(() => {
    const left = job('downloading', { mine: true, shared: true, album: 'Left' })
    const beside = job('downloading', { album: 'Beside' })
    const page = mount()
    page.draw([left, beside])
    page.focusIn(`job-${left.id}`)
    page.draw([left, beside], { cancelling: new Set([left.id]) })
    check('a leave on its way moves no focus', focused, [])
    page.draw([beside])
    check('the left card gone: focus put on the card beside it', focused, [`job-${beside.id}`])

    focused.length = 0
    page.focusIn(`job-${beside.id}`)
    page.draw([beside], { cancelling: new Set([beside.id]) })
    page.draw([])
    check('...the last card gone: focus on the page\'s heading', focused, ['heading'])

    focused.length = 0
    const again = mount()
    const one = job('downloading', { mine: true, shared: true, album: 'One' })
    const two = job('downloading', { album: 'Two' })
    again.draw([one, two])
    again.focusIn(`job-${one.id}`)
    globalThis.document.activeElement = { tag: 'search field' }
    again.draw([two])
    check('...and none moved while focus is somewhere else on the page', focused, [])
  })
}

/* ========================================================================== */
;(async () => {
  for (const fn of later) {
    await new Promise((resolve) => setImmediate(resolve))
    await fn()
  }
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})()
