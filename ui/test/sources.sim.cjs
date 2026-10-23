/**
 * The Sources sheet (app/Sources.tsx), its cards (app/SourceCard.tsx), what is already here of a
 * pressing (app/StoreState.tsx) and the search behind them (hooks/useCandidateSearch.ts) -
 * 2.0.0-player.15, compiled with the repo's TypeScript and rendered by the small stand-in for Preact
 * the other component sims use, with Soulseek's answers, the downloads and the settings faked.
 *
 * What it pins - the rules the main page's candidates panel learned, carried into the app's copy:
 *
 *  - A Get searches Soulseek for ITS release (no override, the format preference read per search),
 *    saying what it asks for while it asks; the newest Get's answer only is drawn, and a superseded
 *    search is called off - closing the sheet calls it off too.
 *  - The cards come in the order shown (the chips, the sort), the first the best match; a card's Get
 *    asks for the download in the tap - with the release the search was FOR, and up to ten
 *    runners-up as shown - and hands over; a second tap asks nothing more.
 *  - The chips start as the quality floor; tapping one filters; none passing says so, with Clear
 *    filters.
 *  - "Pick the best source for me": a fresh Get takes the best match at 75 or more under the chips
 *    and hands over; nothing good enough, or a pressing held or on its way, shows the cards with the
 *    reason; a Re-search never picks.
 *  - Re-search overrides only with an edited query; nothing found offers the query to edit.
 *  - slskd unable to search: its own words, and Try again asks again.
 *  - Held whole or downloading whole: the store's box where the cards would be, and its notes.
 *  - The card's own words: Speed leading, Tracks, Quality, Size, Starts, the amber missing line.
 *
 * And after review:
 *
 *  - Cancel, the backdrop and Escape let the search go IN the gesture - an answer landing before the
 *    next frame's effect picks nothing.
 *  - The best match keeps its purple edge and solid Get whatever the sort; each Get is named for its
 *    folder and its peer.
 *  - No pick for the album as a whole (no tracklist, no release id), said why; Try again after slskd
 *    failed is a fresh Get, so it picks; the settings landing late re-seed the chips only when they
 *    weren't tapped.
 *  - One live region, always there, says each outcome; Try again, Re-search and Clear filters hand
 *    focus to the list before the state they sit in goes; the subtitle has the head's whole width.
 *
 * And on a desktop (2.0.0-player.19), where it is the side panel beside the page:
 *
 *  - Not a modal sheet: its layer says it is a panel (a drawer or a column), it is no modal dialog,
 *    and the hook is told so - no scroll lock, and Escape only from inside its box.
 *  - The board's head: "Sources", what they are for under it, and a close button focus goes to.
 *  - A Signals chip before the sort: the least each signal may score, a count on the chip of how
 *    many are set, a slider each and Reset - and the minimums filter the cards, and a pick, and are
 *    cleared with the rest by Clear filters.
 *  - Searched again for another pressing (`again`, the album page's pressing changed beside it): the
 *    chips and minimums as they were set, never re-seeded from the floor, and nothing picked - while a
 *    fresh Get in the panel still picks when told to, and starts with no minimums set.
 *  - (review) A pick made with a minimum set - set while the search runs - goes by it: the source
 *    under it is never queued. The minimums filter only where the chip is drawn: carried into a
 *    phone's sheet (a window narrowed, an iPad turned) they filter nothing, and are back as they were
 *    on the panel. The panel's box takes focus from a click (a tab stop of -1); a sheet's has none.
 *
 * And for the search extras (2.0.0-player.50): Complete albums only among the chips on both frames -
 * off on every fresh Get, the folder missing a track left out and the whole CD of a CD+DVD kept, as the
 * cards count Tracks, and cleared with the rest - on a desktop after Signals, which keeps its place right
 * after Free slot (review); and a desktop's sample-rate floor after them - by the
 * worst file, unreported never passing, kept on `again`, off on a fresh Get, cleared by Clear filters,
 * filtering nothing in a phone's sheet, and a pick going by it - with the chip itself drawn.
 *
 * And for Get, as the main page had it (2.0.0-player.41):
 *
 *  - The Format a search is scored by is You's (the store's formatPreferenceNow), sent as it is in
 *    hand - and when it isn't yet, the search shows as asking and waits for deadwax's word, sending
 *    nothing before it and nothing at all if the sheet was closed meanwhile.
 *  - Each card's reasons: the edition words in its folder's name and the score's signals as chips,
 *    last on the card - behind a tap on the score in a phone's sheet (a button, aria-expanded,
 *    aria-controls the reasons, which are hidden until it is tapped) and always shown on a desktop's
 *    panel (the score no button there).
 *  - Search again, when folders were found - under the cards' footer, and under "none pass your
 *    filters" - a disclosure opening the same query form: an unedited Re-search overrides nothing,
 *    an edited one is searched as typed, and a search starting closes it. Never where the query form
 *    already is (nothing found), nor while asking, failing, or the store's box stands in.
 *  - (review) Every search the sheet starts asks deadwax for the settings BEFORE reading the Format - a
 *    Get, another Get or the page's next pressing reaching a desktop panel already open, a Re-search,
 *    Try again - so a Format changed on another device is the one searched by.
 *  - (review) Scored Lossless only, an answer Soulseek gave with nothing left of it says "Nothing
 *    lossless", and names the Format and where it is - with the query still there to edit - to the eye
 *    and to VoiceOver; Soulseek answering nothing, or any other Format, still says it found nothing.
 *
 * And downloads per person (2.0.0-player.49): a download somebody else asked for stands where the
 * cards would be with what you'd get and your quality floor's word, nothing picked; its Join joins
 * that download and hands over to Requests, as a Get does. JoinDownload drawn: keyed on the
 * download, only where the page gives a way to join and the download isn't yours; the tap asks at
 * once and waits (aria-disabled), a second tap asks nothing; a refusal in deadwax's words in an
 * alert, with Join back; joined, the button gives way to saying so, handing its focus to the box
 * (never to the page) - unless focus had moved on. The main page's box (components/StoreStatusBox.tsx)
 * drawn too: Join, waiting aria-disabled (never disabled), refused in an alert, joined - its focus
 * handed to the box - and no Join for a download of your own. A Get - a card's, and a pick for you -
 * sends its folder's quality, and each runner-up's, as candidateQuality puts it.
 *
 * And personal libraries (2.0.0-player.51): a pressing the store holds whole that isn't yours (`yours`
 * false, logins on) is "In the store, not in your library" with a line saying adding downloads nothing,
 * and offers Add to my library - yours, or logins off, is "Already in your library" word for word; a part
 * the store holds that isn't yours is "The store has". AddToLibrary drawn: only where offered and the page
 * gives a way; the tap asks at once and waits (aria-disabled), a second tap asks nothing; refused in an
 * alert with Add back; added, said, its focus handed to the box. The main page's box: Add for the release
 * the Find was for, waiting, added - and none with no release to send.
 *
 * Run it with:  node ui/test/sources.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-sources-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/Sources.tsx', 'src/components/StoreStatusBox.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - the stand-in group.sim.cjs uses
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
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
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => {
    const outer = current; current = root; root.cursor = 0
    try { return component(props) } finally { current = outer }
  }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  return render
}
`)

/* ===== Soulseek, the downloads and the settings, faked: each answer is what the test says next ===== */

fs.writeFileSync(path.join(OUT, 'api/download.js'), `
exports.findCandidates = (body, signal) => globalThis.__sources.find(body, signal)
`)
fs.writeFileSync(path.join(OUT, 'lib/downloadRequests.js'), `
exports.requestDownload = (body) => globalThis.__sources.request(body)
exports.joinDownload = (jobId) => globalThis.__sources.join(jobId)
`)
fs.writeFileSync(path.join(OUT, 'app/useGetSettings.js'), `
exports.useGetSettings = (ask) => { globalThis.__sources.settingsAsked.push(ask); return { settings: globalThis.__sources.settings, canSave: true, problem: null } }
exports.getSettingsNow = () => globalThis.__sources.settings || { get_mode: 'sources', quality_floor: 'any', format_preference: 'prefer_lossless' }
exports.formatPreferenceNow = () => { globalThis.__sources.settingsLog.push('format'); return globalThis.__sources.format() }
exports.askGetSettings = () => { globalThis.__sources.settingsLog.push('ask'); return Promise.resolve() }
`)
fs.writeFileSync(path.join(OUT, 'app/useSheet.js'), `
exports.useSheet = (options) => { globalThis.__sources.sheet = options }
`)
//? (2.0.0-player.51) Add to my library: every add kept, answered when the test says
fs.writeFileSync(path.join(OUT, 'api/me.js'), `
exports.addToMyLibrary = (release) => globalThis.__sources.add(release)
`)
fs.writeFileSync(path.join(OUT, 'player/icons.js'), `exports.ChevronDownIcon = function ChevronDownIcon() { return null }\nexports.CloseIcon = function CloseIcon() { return null }\n`)

function deferred() {
  const d = {}
  d.promise = new Promise((yes, no) => { d.resolve = yes; d.reject = no })
  return d
}

const asks = []
const requested = []
const joined = []
const adds = []
globalThis.__sources = {
  join(jobId) { joined.push(jobId); return Promise.resolve(true) },
  add(release) { const d = deferred(); adds.push({ release, ...d }); return d.promise },
  settings: { get_mode: 'sources', quality_floor: 'lossless' },
  settingsAsked: [],
  //? the store asked (askGetSettings) and the Format read for a search (formatPreferenceNow), in order
  settingsLog: [],
  sheet: null,
  //? You's Format, as the store hands it: the settings', or a promise of it the test resolves
  format: () => globalThis.__sources.settings?.format_preference ?? 'prefer_lossless',
  find(body, signal) { const d = deferred(); asks.push({ body, signal, ...d }); return d.promise },
  request(body) { requested.push(body); return Promise.resolve({ status: 'queued', queued: body.files.length, job_id: requested.length }) },
}

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { Sources, SignalsChip, RateChip } = require(path.join(OUT, 'app/Sources.js'))
const { SourceCard } = require(path.join(OUT, 'app/SourceCard.js'))
const { JoinDownload, StoreState } = require(path.join(OUT, 'app/StoreState.js'))
const { StoreStatusBox } = require(path.join(OUT, 'components/StoreStatusBox.js'))

let tree = null
function find(test, within = tree) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(within)
  return hits
}
function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''  // a component, not drawn here
  return text(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const classed = (name) => find(byClass(name))
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

/** The sheet, mounted: draw it (effects and all), as App does. */
function sheet() {
  const render = hooks.root(Sources)
  const queued = []
  const closed = []
  const all = { open: false, request: null, opener: { current: null }, onClose: () => closed.push(1), onQueued: () => queued.push(1) }
  const draw = (more = {}) => {
    Object.assign(all, more)
    tree = render(all)
    render.commit()
    tree = render(all)
    return tree
  }
  return { draw, queued, closed }
}

const RELEASE = {
  artist: 'Portishead', album_artist: 'Portishead', artist_mbids: ['p'], album: 'Third', year: '2008', original_year: '2008',
  release_mbid: 'rel-third', edition_tags: [], tracks: [{ position: 1, title: 'Silence' }], release_group_mbid: 'rg-third',
}
const OTHER = { ...RELEASE, album: 'Dummy', release_mbid: 'rel-dummy', release_group_mbid: 'rg-dummy' }
const MB = 1024 * 1024
const source = (username, fields = {}) => ({
  username, directory: `share\\${username}\\Third`, directory_name: `Portishead - Third [${username}]`, score: 0.9,
  signals: { title_match: 1, track_count: 1, duration_match: 1, edition: 0.5, format: 1, peer: 0.2 },
  matched_tracks: 11, expected_tracks: 11, audio_file_count: 11, detected_edition_tags: [], formats: ['flac'],
  upload_speed: MB, queue_length: 0, has_free_slot: true, total_size: 342 * MB, bitrates: [], bit_depths: [16], sample_rates: [44100],
  variable_bitrate: false, missing_tracks: [], missing_count: 0, files: [{ filename: `share\\${username}\\Third\\01 Silence.flac`, size: 1 }],
  ...fields,
})
const answer = (candidates, fields = {}) => ({
  query: 'Portishead Third', queries: ['Portishead Third'], response_count: 9, candidates,
  held: null, downloading: null, downloading_part: null, other_pressings: [], ...fields,
})
const cards = () => find((node) => node.type === SourceCard)
//? a card has state of its own since 2.0.0-player.41 (its reasons open or not): drawn through a root
const drawCard = (props, render = hooks.root(SourceCard)) => { tree = render(props); return render }
const chips = () => find(byClass('app-chip')).filter((node) => node.type === 'button').map((node) => [text(node), node.props['aria-pressed']])
const chip = (label) => find(byClass('app-chip')).find((node) => node.type === 'button' && text(node) === label)

async function main() {
  console.log('\na Get: Soulseek asked for its release, saying so while it asks')
  const { draw, queued } = sheet()
  draw()
  check('closed, never opened: nothing asked', asks.length, 0)
  draw({ open: true, request: { release: RELEASE, subtitle: 'Third · CD · 2008 · GB · Island', key: 1 } })
  check('one search, for the release, no override, the format preference read for it',
    [asks.length, asks[0]?.body.release_mbid, asks[0]?.body.query_override, asks[0]?.body.format_preference], [1, 'rel-third', '', 'prefer_lossless'])
  check('...the search can be called off (it carries a signal)', !!asks[0]?.signal, true)
  check('the heading: what it is, and what for', [text(find((node) => node.props?.id === 'app-sources-title')[0]), text(classed('app-sources-subtitle')[0])],
    ['Choose a source', 'Third · CD · 2008 · GB · Island'])
  check('...Cancel, the title and the subtitle side by side in the head, so the subtitle can take its whole width',
    find(byClass('app-sources-head'))[0]?.props.children.filter(Boolean).map((child) => child.props.class), ['app-sources-cancel', 'app-sources-title', 'app-sources-subtitle'])
  const region = () => find((node) => node.props?.role === 'status')
  check('one live region, always in the sheet, polite and read whole - saying what it asks for',
    [region().length, region()[0]?.props['aria-live'], region()[0]?.props['aria-atomic'], region()[0]?.props.class, text(region()[0])],
    [1, 'polite', 'true', 'app-visually-hidden', 'Asking Soulseek for “Third” by Portishead…'])
  check('asking: the sweep, and the album and its artist', [classed('app-sweep').length, text(classed('app-sources-state-text')[0])], [1, 'Asking Soulseek for “Third” by Portishead…'])
  check('the sheet is a sheet by the one hook, its own scroll lock, focus in to Cancel', [globalThis.__sources.sheet?.lockClass, globalThis.__sources.sheet?.first?.current === undefined],
    ['app-sources-open', false])
  check('the chips start as the quality floor (Lossless), then the sort', chips(), [['Lossless', true], ['24-bit', false], ['Free slot', false], ['Complete albums only', false]])
  check('...the settings asked as it opened', globalThis.__sources.settingsAsked.at(-1), true)

  console.log('\nthe answer: cards in the order shown, the first the best match')
  const ANSWER = [
    source('vinylhead', { measured_speed: 2.1 * MB, measured_samples: 1 }),
    source('bob', { has_free_slot: false, queue_length: 3, upload_speed: 0 }),
    source('mp3guy', { formats: ['mp3'], bitrates: [320], bit_depths: [], sample_rates: [] }),
    source('crate_dig', { score: 0.63, matched_tracks: 10, total_size: 312 * MB, missing_tracks: [{ position: 11, disc: 1, title: 'Threads' }], missing_count: 1 }),
  ]
  asks[0].resolve(answer(ANSWER))
  await settle()
  draw()
  check('Lossless pressed: the MP3 folder left out', cards().map((card) => card.props.candidate.username), ['vinylhead', 'bob', 'crate_dig'])
  check('...the first card the best match', cards().map((card) => card.props.best), [true, false, false])
  check('...and the live region says how many', text(find((node) => node.props?.role === 'status')[0]), '3 sources')
  check('under them: what was searched, how many folders, how many pass', text(classed('app-sources-footer')[0]),
    'Searched Soulseek for “Portishead Third” · 4 folders, 3 match your filters')
  chip('Lossless').props.onClick()
  draw()
  check('Lossless off: all four', cards().length, 4)
  find((node) => node.type === 'select')[0].props.onChange({ currentTarget: { value: 'size_asc' } })
  draw()
  const sortChip = find(byClass('app-sources-sort'))[0]
  check('the sort, as chosen, shown on its chip', [cards().map((card) => card.props.candidate.username)[0], text(find((node) => node.props?.['aria-hidden'] === 'true', sortChip)[0])],
    ['crate_dig', 'Smallest first'])
  check('...the best match keeps its edge and the solid Get wherever the sort puts it - never the 63 on top',
    cards().filter((card) => card.props.best).map((card) => card.props.candidate.username), ['vinylhead'])
  find((node) => node.type === 'select')[0].props.onChange({ currentTarget: { value: 'score' } })
  chip('Lossless').props.onClick()
  draw()

  console.log('\na card\'s Get: the download asked for in the tap, then Requests')
  cards()[1].props.onGet(cards()[1].props.candidate)
  check('asked for at once, as the release the search was FOR', [requested.length, requested[0]?.username, requested[0]?.release.release_mbid], [1, 'bob', 'rel-third'])
  check('...with the runners-up as shown, the one got left out', requested[0]?.alternatives.map((alt) => alt.username), ['vinylhead', 'crate_dig'])
  //? what the copy is (2.0.0-player.49): kept on the job, for whoever is offered to join it - and each
  //? runner-up's, for a retry to the next peer to take on
  check('...with its folder\'s quality', requested[0]?.quality,
    { formats: ['flac'], bitrates: [], bit_depths: [16], sample_rates: [44100], variable_bitrate: false })
  check('...and each runner-up\'s', requested[0]?.alternatives.map((alt) => alt.quality),
    [{ formats: ['flac'], bitrates: [], bit_depths: [16], sample_rates: [44100], variable_bitrate: false },
      { formats: ['flac'], bitrates: [], bit_depths: [16], sample_rates: [44100], variable_bitrate: false }])
  check('...and handed over to Requests', queued.length, 1)
  cards()[0].props.onGet(cards()[0].props.candidate)
  check('a second tap before the sheet went asks nothing more', [requested.length, queued.length], [1, 1])

  console.log('\nonly the newest Get\'s answer is drawn; closing calls the search off')
  draw({ request: { release: OTHER, subtitle: 'Dummy · CD', key: 2 } })
  check('a new Get searches again, for its own release', [asks.length, asks[1]?.body.release_mbid], [2, 'rel-dummy'])
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 3 } })
  check('...and a third supersedes it, calling its fetch off', [asks.length, asks[1].signal.aborted], [3, true])
  asks[1].resolve(answer([source('late')]))
  await settle()
  draw()
  check('the superseded answer, landing late, is not drawn', [cards().length, classed('app-sweep').length], [0, 1])
  draw({ open: false })
  check('closing calls the search off', asks[2].signal.aborted, true)

  console.log('\nnone passing the chips: said, with Clear filters')
  draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 4 } })
  asks[3].resolve(answer([source('mp3guy', { formats: ['mp3'], bitrates: [320], bit_depths: [], sample_rates: [] })]))
  await settle()
  draw()
  check('one folder, none passes Lossless', text(classed('app-sources-state-text')[0]), '1 folder on Soulseek, none pass your filters')
  find((node) => node.type === 'button' && text(node) === 'Clear filters')[0].props.onClick()
  draw()
  check('Clear filters: every chip off, and the card shows', [chips().every(([, on]) => on === false), cards().length], [true, 1])

  console.log('\n"Pick the best source for me": a fresh Get takes the best match at 75 or more under the chips')
  globalThis.__sources.settings = { get_mode: 'pick', quality_floor: '24bit' }
  const before = requested.length
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 5 } })
  check('the chips start as the 24-bit floor', chips(), [['Lossless', false], ['24-bit', true], ['Free slot', false], ['Complete albums only', false]])
  asks[4].resolve(answer([source('cd', { score: 0.95 }), source('hires', { score: 0.8, bit_depths: [24], sample_rates: [96000] })]))
  await settle()
  draw()
  check('the 24/96 picked, asked for, handed over', [requested.length - before, requested.at(-1)?.username, queued.length], [1, 'hires', 2])
  check('...sending the 24/96\'s own quality', [requested.at(-1)?.quality?.bit_depths, requested.at(-1)?.quality?.sample_rates], [[24], [96000]])
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 6 } })
  asks[5].resolve(answer([source('cd', { score: 0.95 }), source('hires', { score: 0.7, bit_depths: [24], sample_rates: [96000] })]))
  await settle()
  draw()
  check('the 24/96 under 75: nothing picked, the cards shown, and why',
    [requested.length - before, text(classed('app-sources-not-picked')[0]), cards().map((card) => card.props.candidate.username)],
    [1, "Didn't pick a source for you: none scores 75 or more and passes your filters.", ['hires']])
  const held = { path: 'Portishead/Third (2008)', paths: ['Portishead/Third (2008)'], artist: 'Portishead', album: 'Third', edition: '', track_count: 9, expected_tracks: 11, formats: ['flac'], complete: false, fills_gaps: true, filed_to: 'Portishead/Third (2008)' }
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 7 } })
  asks[6].resolve(answer([source('hires', { score: 0.99, bit_depths: [24], sample_rates: [96000] })], { held }))
  await settle()
  draw()
  check('part held: never picked, whatever scores well - and the note says how much is held',
    [requested.length - before, text(classed('app-sources-not-picked')[0]), find((node) => node.type === StoreState)[0]?.props.notes.length], [1, "Didn't pick a source for you: you already have part of it.", 1])

  console.log('\nRe-search: an edited query only, and never a pick')
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 8 } })
  asks[7].resolve(answer([], { query: 'Portishead Third', queries: ['Portishead Third'] }))
  await settle()
  draw()
  check('nothing found: said, with every query, and the query to edit', [text(classed('app-sources-state-text')[0]), find((node) => node.type === 'input')[0]?.props.value],
    ['Soulseek found nothing for “Portishead Third”.', 'Portishead Third'])
  find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} })
  check('an unedited Re-search overrides nothing - it would drop every other name', asks[8]?.body.query_override, '')
  asks[8].resolve(answer([source('hires', { score: 0.99, bit_depths: [24], sample_rates: [96000] })]))
  await settle()
  draw()
  check('...and a Re-search never picks, whatever scores well', [requested.length - before, cards().length], [1, 1])
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 9 } })
  asks[9].resolve(answer([]))
  await settle()
  draw()
  find((node) => node.type === 'input')[0].props.onInput({ currentTarget: { value: 'Portishead - Third (2008)' } })
  draw()
  find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} })
  check('an edited one is searched as typed', asks[10]?.body.query_override, 'Portishead - Third (2008)')
  globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }

  console.log('\nslskd unable to search: its own words, and Try again')
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 10 } })
  asks[11].reject(new Error("slskd isn't logged in to Soulseek, so it can't search. It's waiting for its VPN."))
  await settle()
  draw()
  check('the server\'s words, in amber', [text(classed('app-sources-state-text')[0]), classed('app-sources-state-text')[0]?.props.class.includes('is-warning')],
    ["slskd isn't logged in to Soulseek, so it can't search. It's waiting for its VPN.", true])
  find((node) => node.type === 'button' && text(node) === 'Try again')[0].props.onClick()
  check('Try again asks again, for the same release', [asks.length, asks[12]?.body.release_mbid], [13, 'rel-third'])
  asks[12].resolve(answer([]))
  await settle()

  console.log('\nheld whole, or downloading whole: the store\'s box where the cards would be')
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 11 } })
  asks[13].resolve(answer([], { held: { ...held, track_count: 11, complete: true }, query: '', queries: [] }))
  await settle()
  draw()
  const box = find((node) => node.type === StoreState)[0]
  check('"Already in your library", the folder, the tracks - and no cards, no "nothing found"',
    [box?.props.status, cards().length, classed('app-sources-state-text').length],
    [{ kind: 'held', title: 'Already in your library', lines: ['Portishead/Third (2008)', '11 of 11 tracks · FLAC'] }, 0, 0])
  draw({ request: { release: RELEASE, subtitle: 'Third', key: 12 } })
  asks[14].resolve(answer([], { downloading: { job_id: 3, status: 'queued', username: 'bob', files: 11 }, query: '', queries: [] }))
  await settle()
  draw()
  check('"Already downloading", from whom, and to cancel it in Requests', find((node) => node.type === StoreState)[0]?.props.status,
    { kind: 'downloading', title: 'Already downloading', lines: ['From bob · queued', 'Open Requests to cancel it if you want another peer.'] })

  console.log('\nCancel, the backdrop and Escape let the search go in the gesture (review)')
  {
    globalThis.__sources.settings = { get_mode: 'pick', quality_floor: 'any' }
    const before = requested.length
    const queuedBefore = queued.length
    const fresh = sheet()
    for (const [how, close] of [
      ['Cancel', () => find(byClass('app-sources-cancel'))[0].props.onClick()],
      ['the backdrop', () => find(byClass('app-backdrop'))[0].props.onClick()],
      ['Escape (the sheet hook\'s close)', () => globalThis.__sources.sheet.onClose()],
    ]) {
      fresh.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 100 + asks.length } })
      const ask = asks.at(-1)
      close()
      check(`${how}: the search is called off at once, before any frame - and the sheet told to close`, [ask.signal.aborted, fresh.closed.length > 0], [true, true])
      //? the answer landing in the frame before the closing effect would run
      ask.resolve(answer([source('hires', { score: 0.99 })]))
      await settle()
      check(`...its answer landing anyway picks nothing`, [requested.length - before, queued.length - queuedBefore], [0, 0])
      fresh.closed.length = 0
      fresh.draw({ open: false })
    }
  }

  console.log('\n"Pick the best source for me" and the album as a whole: no tracklist, no pick (review)')
  {
    const fresh = sheet()
    const before = requested.length
    const WHOLE = { ...RELEASE, release_mbid: null, tracks: [] }
    fresh.draw({ open: true, request: { release: WHOLE, subtitle: 'Third · the album as a whole', key: 1 } })
    //? a two-track lossless folder from a fast peer: 100 with no tracklist to be held to
    asks.at(-1).resolve(answer([source('two-tracks', { score: 1, matched_tracks: 0, expected_tracks: 0, audio_file_count: 2 })]))
    await settle()
    fresh.draw()
    check('nothing picked, the cards shown, and why',
      [requested.length - before, cards().length, text(classed('app-sources-not-picked')[0])],
      [0, 1, "Didn't pick a source for you: with no tracklist to match the folders against, no score can be trusted."])
    check('...the live region says it too', text(find((node) => node.props?.role === 'status')[0]),
      "1 source. Didn't pick a source for you: with no tracklist to match the folders against, no score can be trusted.")

    console.log('\nTry again after slskd failed is the Get again: it picks (review)')
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 2 } })
    asks.at(-1).reject(new Error("slskd isn't logged in to Soulseek, so it can't search."))
    await settle()
    fresh.draw()
    check('the refusal said in the live region', text(find((node) => node.props?.role === 'status')[0]), "slskd isn't logged in to Soulseek, so it can't search.")
    const scroll = find(byClass('app-sources-scroll'))[0]
    const focused = []
    scroll.props.ref.current = { focus: (options) => focused.push(options), scrollTop: 0 }
    check('the list can take focus, but is no tab stop', scroll.props.tabIndex, -1)
    const queuedBefore = fresh.queued.length
    find((node) => node.type === 'button' && text(node) === 'Try again')[0].props.onClick()
    check('Try again hands focus to the list before its own state goes - never to the page', focused, [{ preventScroll: true }])
    asks.at(-1).resolve(answer([source('hires', { score: 0.9 })]))
    await settle()
    fresh.draw()
    check('...and the answer it brings is picked, as a fresh Get\'s is', [requested.length - before, requested.at(-1)?.username, fresh.queued.length - queuedBefore], [1, 'hires', 1])

    console.log('\nRe-search and Clear filters hand focus to the list too')
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'lossless' }
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 3 } })
    asks.at(-1).resolve(answer([]))
    await settle()
    fresh.draw()
    find(byClass('app-sources-scroll'))[0].props.ref.current = { focus: (options) => focused.push(options), scrollTop: 0 }
    find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} })
    check('Re-search', focused.length, 2)
    asks.at(-1).resolve(answer([source('mp3guy', { formats: ['mp3'], bitrates: [320], bit_depths: [], sample_rates: [] })]))
    await settle()
    fresh.draw()
    find((node) => node.type === 'button' && text(node) === 'Clear filters')[0].props.onClick()
    check('Clear filters', focused.length, 3)

    console.log('\nthe settings landing after the sheet opened re-seed the chips - unless they were tapped')
    globalThis.__sources.settings = null
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 4 } })
    check('no settings yet: the defaults\' chips, none pressed', chips(), [['Lossless', false], ['24-bit', false], ['Free slot', false], ['Complete albums only', false]])
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'lossless' }
    fresh.draw()
    check('the settings landing: the chips become the floor', chips(), [['Lossless', true], ['24-bit', false], ['Free slot', false], ['Complete albums only', false]])
    globalThis.__sources.settings = null
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 5 } })
    chip('Free slot').props.onClick()
    fresh.draw()
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'lossless' }
    fresh.draw()
    check('...but a chip already tapped stands: the settings re-seed nothing', chips(), [['Lossless', false], ['24-bit', false], ['Free slot', true], ['Complete albums only', false]])
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }
  }

  console.log('\na desktop\'s side panel (2.0.0-player.19): the board\'s head, Signals, and searched again for another pressing')
  {
    globalThis.__sources.settings = { get_mode: 'pick', quality_floor: 'lossless' }
    const phone = sheet()
    phone.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 19 } })
    check('a phone\'s sheet has no Signals chip, nor the panel\'s head', [find((node) => node.type === SignalsChip).length, classed('app-sources-close').length, classed('app-sources-cancel').length], [0, 0, 1])
    const sheetBox = find(byClass('app-sources'))[0].props.tabIndex
    phone.draw({ open: false })
    const desk = sheet()
    desk.draw({ open: true, panel: 'column', request: { release: RELEASE, subtitle: 'Third · CD · 2008 · GB · Island', key: 20, from: 'rg-third' } })
    const layer = find(byClass('app-sources-layer'))[0]
    check('a panel, not a sheet: its layer says so (a column here), and it is no modal dialog',
      [layer.props.class.split(' ').filter((name) => name.startsWith('is-')), find(byClass('app-sources'))[0].props['aria-modal']], [['is-open', 'is-panel', 'is-column'], 'false'])
    check('...the hook told it is not modal (no scroll lock), with its box (Escape only from inside it)',
      [globalThis.__sources.sheet.modal, globalThis.__sources.sheet.area === find(byClass('app-sources'))[0].props.ref, globalThis.__sources.sheet.lockClass], [false, true, 'app-sources-open'])
    const close = classed('app-sources-close')[0]
    check('the board\'s head: "Sources", what they are for under it, a close button focus goes to - and no Cancel',
      [text(find((node) => node.props?.id === 'app-sources-title')[0]), text(classed('app-sources-subtitle')[0]), close?.props['aria-label'],
        close?.props.ref === globalThis.__sources.sheet.first, classed('app-sources-cancel').length],
      ['Sources', 'for Third · CD · 2008 · GB · Island', 'Close the sources', true, 0])
    const chipRow = () => find(byClass('app-sources-chips'))[0].props.children.flat().filter(Boolean)
      .map((child) => child.type === SignalsChip ? 'Signals' : child.type === RateChip ? 'Sample rate' : child.props?.class?.includes('app-sources-sort') ? 'sort' : text(child))
    //? (review, 2.0.0-player.50: Complete albums only before Signals put Signals at the row's very edge -
    //? its label growing as a minimum was set, or Complete pressed and bolder, wrapped it and its popover
    //? out from under the slider being dragged; after Free slot it keeps the place it always had)
    check('the chips gain Signals right after Free slot - then Complete albums only and the sample-rate floor (2.0.0-player.50) - before the sort',
      chipRow(), ['Lossless', '24-bit', 'Free slot', 'Signals', 'Complete albums only', 'Sample rate', 'sort'])
    const signalsChip = () => find((node) => node.type === SignalsChip)[0]
    check('...none set to begin with', Object.values(signalsChip().props.minimums).filter(Boolean).length, 0)
    check('the panel\'s box takes focus from a click on what can\'t (a tab stop of -1) - a sheet\'s has none',
      [find(byClass('app-sources'))[0].props.tabIndex, sheetBox], [-1, undefined])

    const FRESH = [
      source('vinylhead', { score: 0.95 }),
      source('weak', { score: 0.8, signals: { title_match: 0.4, track_count: 1, duration_match: 1, edition: 0.5, format: 1, peer: 0.2 } }),
    ]
    asks.at(-1).resolve(answer(FRESH))
    await settle()
    desk.draw()
    check('a fresh Get in the panel still picks when told to, and hands over', [desk.queued.length, requested.at(-1)?.username], [1, 'vinylhead'])

    //? the panel stays (on a desktop App keeps it while you look): set a chip and a minimum, then the
    //? album page's pressing changes - searched again, `again`
    chip('Free slot').props.onClick()
    signalsChip().props.onChange({ ...signalsChip().props.minimums, title_match: 50 })
    desk.draw()
    check('a minimum set: the chip counts it, and the card under it is left out', [Object.values(signalsChip().props.minimums).filter(Boolean).length, cards().map((card) => card.props.candidate.username)],
      [1, ['vinylhead']])
    chip('Complete albums only').props.onClick()
    desk.draw()
    check('...Signals still right after Free slot with a minimum set and Complete albums only pressed (review)',
      chipRow(), ['Lossless', '24-bit', 'Free slot', 'Signals', 'Complete albums only', 'Sample rate', 'sort'])
    chip('Complete albums only').props.onClick()
    desk.draw()
    const before = asks.length
    desk.draw({ request: { release: OTHER, subtitle: 'Third · 2×12" Vinyl · 2008', key: 21, from: 'rg-third', again: true } })
    check('another pressing chosen beside it: Soulseek asked again, for that pressing', [asks.length - before, asks.at(-1)?.body.release_mbid], [1, 'rel-dummy'])
    check('...the chips and the minimum as they were set - never re-seeded from the floor',
      [chips(), signalsChip().props.minimums.title_match], [[['Lossless', true], ['24-bit', false], ['Free slot', true], ['Complete albums only', false]], 50])
    asks.at(-1).resolve(answer([source('vinylhead', { score: 0.95 })]))
    await settle()
    desk.draw()
    check('...and nothing picked for you: you are choosing', [desk.queued.length, cards().map((card) => card.props.candidate.username)], [1, ['vinylhead']])

    //? Clear filters takes the minimums with the chips - shown for a minimum alone, no chip pressed
    chip('Free slot').props.onClick()
    chip('Lossless').props.onClick()
    desk.draw({ request: { release: RELEASE, subtitle: 'Third', key: 22, from: 'rg-third', again: true } })
    asks.at(-1).resolve(answer([source('weak', { score: 0.8, signals: { title_match: 0.4, track_count: 1, duration_match: 1, edition: 0.5, format: 1, peer: 0.2 } })]))
    await settle()
    desk.draw()
    const clear = find((node) => node.type === 'button' && text(node) === 'Clear filters')[0]
    check('none passing, no chip pressed: Clear filters all the same, the minimum counted as a chip pressed', [chips().filter(([, on]) => on).length, !!clear], [0, true])
    clear.props.onClick()
    desk.draw()
    check('...which clears the minimum too', [Object.values(signalsChip().props.minimums).filter(Boolean).length, cards().length], [0, 1])

    //? (review) a minimum set while a fresh Get's search runs: the pick goes by it, as the cards do
    const WEAK_ONLY = [source('weak', { score: 0.95, signals: { title_match: 0.4, track_count: 1, duration_match: 1, edition: 0.5, format: 1, peer: 0.2 } })]
    const queuedBefore = desk.queued.length
    const requestedBefore = requested.length
    desk.draw({ request: { release: RELEASE, subtitle: 'Third', key: 23, from: 'rg-third' } })
    signalsChip().props.onChange({ ...signalsChip().props.minimums, title_match: 50 })
    desk.draw()
    asks.at(-1).resolve(answer(WEAK_ONLY))
    await settle()
    desk.draw()
    check('a pick with a minimum set: the source under it is never queued - nothing qualifies, and the cards say so',
      [desk.queued.length - queuedBefore, requested.length - requestedBefore, cards().length], [0, 0, 0])
    //? (review) and the next fresh Get starts with none
    desk.draw({ request: { release: OTHER, subtitle: 'Dummy', key: 24, from: 'rg-dummy' } })
    check('a fresh Get afterwards (not `again`): every minimum off again', Object.values(signalsChip().props.minimums).filter(Boolean).length, 0)
    asks.at(-1).resolve(answer([]))
    await settle()

    //? (review) the minimums filter only where the chip is drawn: the panel carried into a phone's sheet
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }
    const TWO = [source('vinylhead', { score: 0.95 }), ...WEAK_ONLY.map((one) => ({ ...one, score: 0.8 }))]
    desk.draw({ request: { release: RELEASE, subtitle: 'Third', key: 25, from: 'rg-third' } })
    asks.at(-1).resolve(answer(TWO))
    await settle()
    desk.draw()
    signalsChip().props.onChange({ ...signalsChip().props.minimums, title_match: 50 })
    desk.draw()
    check('on the panel, a minimum leaves out the card under it', cards().map((card) => card.props.candidate.username), ['vinylhead'])
    desk.draw({ panel: 'sheet' })
    check('...the window narrowed into a phone\'s sheet: no Signals chip, and nothing filtered by it - every card, the footer saying so',
      [find((node) => node.type === SignalsChip).length, cards().map((card) => card.props.candidate.username), text(classed('app-sources-footer')[0]), globalThis.__sources.sheet.modal],
      [0, ['vinylhead', 'weak'], 'Searched Soulseek for “Portishead Third” · 2 folders, all match your filters', true])
    desk.draw({ panel: 'drawer' })
    check('...and back on the panel the minimum is as it was set', [signalsChip().props.minimums.title_match, cards().map((card) => card.props.candidate.username)], [50, ['vinylhead']])
    desk.draw({ open: false, panel: 'column' })
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }

    console.log('\nthe Signals chip, drawn')
    const changes = []
    const render = hooks.root(SignalsChip)
    const props = { minimums: { title_match: 0, track_count: 60, duration_match: 0, edition: 0, format: 0, peer: 0 }, onChange: (next) => changes.push(next) }
    tree = render(props)
    const button = find((node) => node.type === 'button' && node.props['aria-controls'])[0]
    check('the chip: pressed with a minimum set, counting it, and closed', [text(button), button.props.class.includes('is-on'), button.props['aria-expanded'], find((node) => node.props?.role === 'group')[0].props.hidden],
      ['Signals · 1', true, false, true])
    button.props.onClick()
    tree = render(props)
    const rows = classed('app-signals-row')
    check('opened: a slider each - the score\'s six signals - with what it is set to', [find((node) => node.props?.role === 'group')[0].props.hidden,
      rows.map((row) => [text(row.props.children[0]), text(row.props.children[2])])],
      [false, [['Titles', 'any'], ['Count', '60'], ['Lengths', 'any'], ['Edition', 'any'], ['Format', 'any'], ['Peer', 'any']]])
    rows[0].props.children[1].props.onInput({ currentTarget: { value: '75' } })
    check('...a slider moved: that minimum, the rest kept', changes.at(-1), { title_match: 75, track_count: 60, duration_match: 0, edition: 0, format: 0, peer: 0 })
    const reset = classed('app-signals-reset')[0]
    reset.props.onClick()
    check('Reset: every minimum off - and it can\'t be pressed with none set', [Object.values(changes.at(-1)).filter(Boolean).length, reset.props.disabled,
      (() => { tree = render({ ...props, minimums: { title_match: 0 } }); return classed('app-signals-reset')[0].props.disabled })()], [0, false, true])
    const keys = []
    const escape = { key: 'Escape', preventDefault: () => keys.push('prevented') }
    tree = render(props)
    find(byClass('app-signals'))[0].props.onKeyDown(escape)
    tree = render(props)
    check('Escape closes it, taken here so the panel stays open', [keys, find((node) => node.props?.role === 'group')[0].props.hidden], [['prevented'], true])
  }

  console.log('\nthe store\'s box, drawn')
  {
    tree = StoreState({ status: { kind: 'held', title: 'Already in your library', lines: ['Portishead/Third (2008)', '11 of 11 tracks · FLAC'] }, notes: ['You also have another pressing: 2008 vinyl'] })
    check('the title, each line - the last the detail - and the notes', [text(classed('app-store-title')[0]), classed('app-store-line').map((line) => [text(line), line.props.class.includes('is-detail')]), classed('app-store-note').map(text)],
      ['Already in your library', [['Portishead/Third (2008)', false], ['11 of 11 tracks · FLAC', true]], ['You also have another pressing: 2008 vinyl']])
    check('...and nothing at all with nothing to say', StoreState({ status: null, notes: [] }), null)

    //? (2.0.0-player.49) somebody else's download: Join under its words - its own component, keyed on it
    const status = { kind: 'downloading', title: 'Already downloading for someone else', lines: ['From bob · FLAC · queued', 'Join it…'], joinJobId: 7 }
    const asked = []
    let answerJoin = null
    const onJoin = (jobId) => { asked.push(jobId); return new Promise((resolve, reject) => { answerJoin = { resolve, reject } }) }
    tree = StoreState({ status, notes: [], onJoin })
    const join = find((node) => node.type === JoinDownload)[0]
    check('a download somebody else asked for: Join, for it, keyed on it', [join?.props.jobId, join?.key], [7, 7])
    tree = StoreState({ status, notes: [] })
    check('...none where the page gives no way to join', find((node) => node.type === JoinDownload).length, 0)
    //? (2.0.0-player.65, the release review's nit) ...and no "Join it" above no button, for someone without Get albums
    const theirs = { kind: 'downloading', title: 'Already downloading for someone else',
      lines: ['From bob · FLAC · queued', 'Join it to have it in your Requests too - one download, everyone who asked waiting for it.'], joinJobId: 7 }
    tree = StoreState({ status: theirs, notes: [] })
    check('...nor the line saying what Join does', classed('app-store-line').map(text), ['From bob · FLAC · queued'])
    tree = StoreState({ status: theirs, notes: [], onJoin })
    check('...which stays where Join is drawn', classed('app-store-line').length, 2)
    tree = StoreState({ status: { ...status, joinJobId: undefined }, notes: [], onJoin })
    check('...nor for a download of your own', find((node) => node.type === JoinDownload).length, 0)

    const drawJoin = hooks.root(JoinDownload)
    tree = drawJoin({ jobId: 7, onJoin })
    const button = () => find((node) => node.type === 'button')[0]
    check('Join this download', [text(button()), button().props['aria-disabled']], ['Join this download', false])
    button().props.onClick()
    tree = drawJoin({ jobId: 7, onJoin })
    check('the tap asks at once, and the button waits - still in the tab order', [asked, text(button()), button().props['aria-disabled']], [[7], 'Joining…', true])
    button().props.onClick()
    check('...a second tap asks nothing more', asked, [7])
    answerJoin.reject(new Error('that download has been filed into the library since - get it again to see where it stands'))
    await settle()
    tree = drawJoin({ jobId: 7, onJoin })
    check('refused: deadwax\'s words in an alert, and Join there to try again',
      [find((node) => node.props?.role === 'alert').map(text), text(button()), button().props['aria-disabled']],
      [['that download has been filed into the library since - get it again to see where it stands'], 'Join this download', false])
    //? the page as far as focus goes: the button in its box, and where the focus is
    const focused = []
    const storeBox = { focus: (options) => focused.push(['box', options]) }
    const fakeButton = { closest: (selector) => (selector === '.app-store-box' ? storeBox : null) }
    globalThis.document = { body: {}, activeElement: fakeButton }
    button().props.onClick()
    button().props.ref.current = fakeButton
    answerJoin.resolve(true)
    await settle()
    tree = drawJoin({ jobId: 7, onJoin })
    check('joined: the button gives way to saying so', [find((node) => node.type === 'button').length, find((node) => node.props?.role === 'status').map(text)],
      [0, ["Joined - it's in your Requests."]])
    check('...handing the focus it had to the box, which the page keeps drawn - never dropped to the page', focused, [['box', { preventScroll: true }]])
    tree = StoreState({ status, notes: [], onJoin })
    check('...a box that can hold it (a target, not in the tab order)', classed('app-store-box')[0].props.tabIndex, -1)

    //? focus somewhere else as the answer lands (the person moved on): left where it is
    const elsewhere = hooks.root(JoinDownload)
    tree = elsewhere({ jobId: 8, onJoin })
    globalThis.document.activeElement = { somewhere: 'else' }
    button().props.onClick()
    button().props.ref.current = fakeButton
    answerJoin.resolve(true)
    await settle()
    check('...but focus elsewhere by then is left alone', focused.length, 1)
    delete globalThis.document
  }

  console.log('\nthe main page\'s store box (components/StoreStatusBox.tsx): Join, waiting, joined, refused')
  {
    const answers = []
    const realJoin = globalThis.__sources.join
    globalThis.__sources.join = (jobId) => new Promise((resolve, reject) => { answers.push({ jobId, resolve, reject }) })
    const status = { kind: 'downloading', title: 'Already downloading for someone else', lines: ['From bob · FLAC 16/44.1 · queued',
      'Join it to have it in your Downloads too - one download, everyone who asked waiting for it.'], joinJobId: 5 }
    const draw = hooks.root(StoreStatusBox)
    tree = draw({ status })
    const button = () => find((node) => node.type === 'button')[0]
    check('the title, the lines, and Join', [text(find((node) => node.type === 'h4')[0]), find((node) => node.type === 'p').map(text), text(button()), button().props['aria-disabled']],
      ['Already downloading for someone else', status.lines, 'Join this download', false])
    check('...a box that can hold the focus Join gives up', find((node) => byClass('candidates-store')(node))[0].props.tabIndex, -1)
    button().props.onClick()
    tree = draw({ status })
    check('the tap asks at once; the button waits, aria-disabled - still focusable, never disabled',
      [answers.map((a) => a.jobId), text(button()), button().props['aria-disabled'], button().props.disabled], [[5], 'Joining…', true, undefined])
    button().props.onClick()
    check('...a second tap asks nothing more', answers.length, 1)
    answers[0].reject(new Error('that download has been cancelled since - get it again to see where it stands'))
    await settle()
    tree = draw({ status })
    check('refused: deadwax\'s words in an alert, and Join back', [find((node) => node.props?.role === 'alert').map(text), text(button())],
      [['that download has been cancelled since - get it again to see where it stands'], 'Join this download'])
    const focused = []
    const fakeButton = { closest: (selector) => (selector === '.candidates-store' ? { focus: () => focused.push('box') } : null) }
    globalThis.document = { body: {}, activeElement: fakeButton }
    button().props.onClick()
    button().props.ref.current = fakeButton
    answers[1].resolve(true)
    await settle()
    tree = draw({ status })
    check('joined: "Joined - it\'s in Downloads.", the button gone - its focus handed to the box',
      [find((node) => node.type === 'button').length, find((node) => node.props?.role === 'status').map(text), focused], [0, ["Joined - it's in Downloads."], ['box']])
    delete globalThis.document
    tree = draw({ status: { ...status, joinJobId: undefined } })
    check('a download of your own: no Join', find((node) => node.type === 'button').length, 0)
    globalThis.__sources.join = realJoin
  }

  console.log('\nAdd to my library (2.0.0-player.51): the store line\'s case, the app\'s button, the main page\'s box')
  {
    const { storeStatusFor } = require(path.join(OUT, 'lib/perPerson.js'))
    const { storeNotes } = require(path.join(OUT, 'lib/candidates.js'))
    const held = { path: 'Portishead/Third (2008)', paths: ['Portishead/Third (2008)'], artist: 'Portishead', album: 'Third', edition: '',
      track_count: 11, expected_tracks: 11, formats: ['flac'], complete: true, fills_gaps: false, filed_to: null }
    const notYours = storeStatusFor({ held: { ...held, yours: false }, downloading: null }, 'Requests')
    check('held whole, not yours: "In the store, not in your library", what it is, that adding downloads nothing - and Add',
      [notYours.title, notYours.lines, notYours.add],
      ['In the store, not in your library', ['Portishead/Third (2008)', '11 of 11 tracks · FLAC',
        'Add it to your library to have it starred for you in Navidrome - nothing is downloaded.'], true])
    const yours = storeStatusFor({ held: { ...held, yours: true }, downloading: null }, 'Requests')
    const off = storeStatusFor({ held, downloading: null }, 'Requests')
    check('...yours, or logins off (no `yours`): "Already in your library" as it always was, no Add',
      [yours.title, yours.add, off.title, off.add, JSON.stringify(off) === JSON.stringify(yours)], ['Already in your library', undefined, 'Already in your library', undefined, true])
    const part = { ...held, complete: false, track_count: 9, filed_to: 'Portishead/Third (2008)', fills_gaps: true }
    check('a part the store holds that isn\'t yours is the store\'s; yours (or logins off) is yours',
      [storeNotes({ held: { ...part, yours: false }, downloading_part: null, other_pressings: [] })[0].slice(0, 40),
        storeNotes({ held: part, downloading_part: null, other_pressings: [] })[0].slice(0, 40)],
      ['The store has 9 of 11 tracks of this pre', 'You have 9 of 11 tracks of this pressing'])

    const { AddToLibrary } = require(path.join(OUT, 'app/StoreState.js'))
    const asked = []
    let answerAdd = null
    const onAdd = () => { asked.push('add'); return new Promise((resolve, reject) => { answerAdd = { resolve, reject } }) }
    tree = StoreState({ status: notYours, notes: [], onAdd })
    check('the app\'s box draws Add where it is offered and the page gives a way', find((node) => node.type === AddToLibrary).length, 1)
    tree = StoreState({ status: notYours, notes: [] })
    check('...none where the page gives none', find((node) => node.type === AddToLibrary).length, 0)
    tree = StoreState({ status: yours, notes: [], onAdd })
    check('...nor for a pressing of yours', find((node) => node.type === AddToLibrary).length, 0)

    //? (review) the Sources panel doesn't ask the store again after its Add: its box says it's yours itself
    const { addedStatus } = require(path.join(OUT, 'lib/perPerson.js'))
    const added = addedStatus(notYours)
    check('added from the box: "Already in your library", the add note gone - Add kept, so its own "Added" words stay',
      [added.title, added.lines, added.add, addedStatus(yours) === yours], ['Already in your library', ['Portishead/Third (2008)', '11 of 11 tracks · FLAC'], true, true])
    tree = StoreState({ status: added, notes: [], onAdd })
    const kept = find((node) => node.type === AddToLibrary)
    check('...the same AddToLibrary (its key the folder line, as before), so it keeps saying it was added', [kept.length, kept[0]?.key], [1, notYours.lines[0]])
    const sourcesCode = require('fs').readFileSync(path.join(UI, 'src/app/Sources.tsx'), 'utf8')
    const pageCode = require('fs').readFileSync(path.join(UI, 'src/app/ReleaseGroupPage.tsx'), 'utf8')
    check('...the Sources panel draws that once its add is in, and tells the album page beside it, which asks the store again (review)',
      [/const status = found && result !== null && addedFrom === result \? addedStatus\(found\) : found/.test(sourcesCode),
        /return addToMyLibrary\(search\.release\)\.then\(\(\) => \{\s*setAddedFrom\(from\)\s*announceAddedToLibrary\(\)/.test(sourcesCode),
        /useEffect\(\(\) => onAddedToLibrary\(\(\) => setFiled\(\(n\) => n \+ 1\)\), \[\]\)/.test(pageCode),
        /addToMyLibrary\(download\.release\)\.then\(announceAddedToLibrary\)/.test(pageCode)],
      [true, true, true, true])
    const drawAdd = hooks.root(AddToLibrary)
    tree = drawAdd({ onAdd })
    const button = () => find((node) => node.type === 'button')[0]
    check('Add to my library', [text(button()), button().props['aria-disabled']], ['Add to my library', false])
    button().props.onClick()
    tree = drawAdd({ onAdd })
    check('the tap asks at once, the button waiting - still in the tab order; a second tap asks nothing more',
      [(button().props.onClick(), asked), text(button()), button().props['aria-disabled']], [['add'], 'Adding…', true])
    answerAdd.reject(new Error("That pressing isn't in the store now - Get it instead."))
    await settle()
    tree = drawAdd({ onAdd })
    check('refused: deadwax\'s words in an alert, Add back', [find((node) => node.props?.role === 'alert').map(text), text(button())],
      [["That pressing isn't in the store now - Get it instead."], 'Add to my library'])
    const focused = []
    const fakeButton = { closest: (selector) => (selector === '.app-store-box' ? { focus: () => focused.push('box') } : null) }
    globalThis.document = { body: {}, activeElement: fakeButton }
    button().props.onClick()
    button().props.ref.current = fakeButton
    answerAdd.resolve({ added: true })
    await settle()
    tree = drawAdd({ onAdd })
    check('added: said, the button gone, its focus handed to the box', [find((node) => node.type === 'button').length, find((node) => node.props?.role === 'status').map(text), focused],
      [0, ["Added - it's in your library, and deadwax stars it for you in Navidrome."], ['box']])
    delete globalThis.document

    const draw = hooks.root(StoreStatusBox)
    const release = { artist: 'Portishead', album: 'Third', release_mbid: 'rel-third' }
    tree = draw({ status: notYours, release })
    const mainButton = () => find((node) => node.type === 'button')[0]
    check('the main page\'s box: Add, for the release the Find was for', text(mainButton()), 'Add to my library')
    mainButton().props.onClick()
    tree = draw({ status: notYours, release })
    check('...asked at once, waiting aria-disabled', [adds.map((a) => a.release.release_mbid), text(mainButton()), mainButton().props['aria-disabled']], [['rel-third'], 'Adding…', true])
    adds[0].resolve({ added: true })
    await settle()
    tree = draw({ status: notYours, release })
    check('...added, said', [find((node) => node.type === 'button').length, find((node) => node.props?.role === 'status').map(text)],
      [0, ["Added - it's in your library, and deadwax stars it for you in Navidrome."]])
    //? (review) the main page doesn't ask the store again either: the box says it's yours itself, as the panel does
    check('...and the box above it says it is yours now: "Already in your library", the add note gone',
      [find((node) => node.type === 'h4').map(text), find((node) => node.type === 'p' && node.props?.role === undefined).map(text)],
      [['Already in your library'], ['Portishead/Third (2008)', '11 of 11 tracks · FLAC']])
    tree = hooks.root(StoreStatusBox)({ status: notYours })
    check('...and no Add with no release to send', find((node) => node.type === 'button').length, 0)
  }

  console.log('\na card, drawn: Speed leading, the facts, the missing line')
  {
    const gets = []
    drawCard({ candidate: source('vinylhead', { measured_speed: 2.1 * MB, measured_samples: 1 }), best: true, onGet: (c) => gets.push(c.username) })
    check('the score, the folder, who from, and Get - the best match\'s the solid purple, named for its folder and peer',
      [text(classed('app-source-score')[0]), classed('app-source-score')[0].props.class.includes('is-good'), text(classed('app-source-folder')[0]), text(classed('app-source-peer')[0]),
        classed('app-source-get')[0].props.class, classed('app-source-get')[0].props['aria-label']],
      ['90', true, 'Portishead - Third [vinylhead]', 'from vinylhead', 'app-source-get is-primary', 'Get Portishead - Third [vinylhead] from vinylhead'])
    //? one peer, two folders of the album (FLAC and MP3): two Gets VoiceOver's rotor can tell apart
    const label = (fields) => { drawCard({ candidate: source('bob', fields), best: false, onGet() {} }); return classed('app-source-get')[0].props['aria-label'] }
    check('...so one peer\'s two folders are two different buttons', [label({ directory_name: 'Third [FLAC]' }), label({ directory_name: 'Third [MP3 320]' })],
      ['Get Third [FLAC] from bob', 'Get Third [MP3 320] from bob'])
    drawCard({ candidate: source('vinylhead', { measured_speed: 2.1 * MB, measured_samples: 1 }), best: true, onGet: (c) => gets.push(c.username) })
    check('Speed: measured, green, said so, its bar', [text(classed('app-source-speed-text')[0]), classed('app-source-speed-text')[0].props.class.includes('is-measured'), text(classed('app-source-speed-note')[0]),
      classed('app-source-bar-fill')[0].props.style.width], ['2.1 MB/s', true, 'what you got from them', '70%'])
    check('the facts: Tracks, Quality, Size, Starts', classed('app-source-fact').map((fact) => [text(fact.props.children[0]), text(fact.props.children[1])]),
      [['Tracks', '11 of 11'], ['Quality', 'FLAC 16/44.1'], ['Size', '342 MB'], ['Starts', 'now']])
    classed('app-source-get')[0].props.onClick()
    check('Get is the tap', gets, ['vinylhead'])
    drawCard({ candidate: source('crate_dig', { score: 0.63, upload_speed: 0, has_free_slot: false, queue_length: 3, matched_tracks: 10, missing_tracks: [{ position: 11, disc: 1, title: 'Threads' }], missing_count: 1, disc_folders: ['CD 1', 'CD 2'] }), best: false, onGet() {} })
    check('another: amber score, tinted Get, no speed, amber Tracks and Starts, and what is missing',
      [classed('app-source-score')[0].props.class.includes('is-low'), classed('app-source-get')[0].props.class, text(classed('app-source-speed-text')[0]), text(classed('app-source-speed-note')[0]),
        classed('app-source-value').filter((value) => value.props.class.includes('is-warning')).map(text), text(classed('app-source-missing')[0]), text(classed('app-source-peer')[0])],
      [true, 'app-source-get is-tinted', 'Unknown', 'no speed reported yet', ['10 of 11', '3 ahead'], 'Missing “Threads”', 'from crate_dig · 2 disc folders'])
    drawCard({ candidate: source('bob', { upload_speed: 1.2 * MB }), best: false, onGet() {} })
    check('the peer\'s own average is never the download speed: grey, and says whose it is',
      [text(classed('app-source-speed-text')[0]), classed('app-source-speed-text')[0].props.class.includes('is-advertised'), text(classed('app-source-speed-note')[0])],
      ['1.2 MB/s', true, 'their own average'])
  }

  console.log('\na card\'s reasons (2.0.0-player.41): why it scored what it did, as the main page shows it')
  {
    const REASONED = source('vinylhead', {
      detected_edition_tags: ['DELUXE', 'REMASTER'],
      signals: { title_match: 1, track_count: 1, duration_match: null, edition: 0.5, format: 0.45, peer: 0.2 },
    })
    const reasons = () => classed('app-source-reasons')[0]
    const render = drawCard({ candidate: REASONED, best: false, onGet() {}, reasons: 'tap' })
    const score = () => classed('app-source-score')[0]
    check('a phone\'s: the score is a button, closed, controlling the reasons - which are there, hidden',
      [score().type, score().props['aria-expanded'], score().props['aria-controls'] === reasons().props.id, reasons().props.hidden, score().props['aria-label']],
      ['button', false, true, true, 'Match score 90'])
    check('...the reasons last on the card, so opening them moves nothing above',
      find((node) => node.type === 'li' && byClass('app-source')(node))[0].props.children.filter(Boolean).at(-1)?.props.class, 'app-source-reasons')
    check('...named for what they are, a group', [reasons().props.role, reasons().props['aria-label']], ['group', 'Why it scored 90'])
    score().props.onClick()
    tree = render({ candidate: REASONED, best: false, onGet() {}, reasons: 'tap' })
    check('a tap on the score opens them', [score().props['aria-expanded'], reasons().props.hidden], [true, false])
    check('the edition words in the folder\'s name, each in its colour',
      classed('app-source-tag').map((tag) => [text(tag), tag.props.class]), [['DELUXE', 'app-source-tag is-purple'], ['REMASTER', 'app-source-tag is-amber']])
    check('the signals: each judged one a chip - its word, its number, its band - the unjudged left out',
      classed('app-source-signal').map((chip) => [text(chip), chip.props.class]),
      [['Titles 100', 'app-source-signal is-good'], ['Count 100', 'app-source-signal is-good'], ['Edition 50', 'app-source-signal is-mid'],
       ['Format 45', 'app-source-signal is-mid'], ['Peer 20', 'app-source-signal is-bad']])
    score().props.onClick()
    tree = render({ candidate: REASONED, best: false, onGet() {}, reasons: 'tap' })
    check('...a second tap closes them', [score().props['aria-expanded'], reasons().props.hidden], [false, true])
    drawCard({ candidate: REASONED, best: false, onGet() {}, reasons: 'shown' })
    check('a desktop\'s: always shown - the score no button, nothing to open', [score().type, score().props['aria-expanded'], reasons().props.hidden, classed('app-source-signal').length],
      ['span', undefined, false, 5])
    drawCard({ candidate: source('bob'), best: false, onGet() {} })
    check('...shown is the default, and no edition words found draws none', [reasons().props.hidden, classed('app-source-tags').length], [false, 0])
  }

  console.log('\nthe sheet hands each card how its reasons show, and You\'s Format goes with each search (2.0.0-player.41)')
  {
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any', format_preference: 'lossless_only' }
    const phone = sheet()
    phone.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 410 } })
    check('the search sends You\'s Format, as the store has it', asks.at(-1)?.body.format_preference, 'lossless_only')
    asks.at(-1).resolve(answer([source('vinylhead'), source('bob', { score: 0.8 })]))
    await settle()
    phone.draw()
    check('a phone\'s sheet: behind a tap on the score', cards().map((card) => card.props.reasons), ['tap', 'tap'])
    phone.draw({ panel: 'column' })
    check('a desktop\'s panel: always shown', cards().map((card) => card.props.reasons), ['shown', 'shown'])
    phone.draw({ open: false, panel: 'sheet' })

    //? nothing in hand yet: the store hands a promise - the search shows as asking, and waits
    let answerFormat = null
    globalThis.__sources.format = () => new Promise((resolve) => { answerFormat = resolve })
    const before = asks.length
    phone.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 411 } })
    check('deadwax not yet asked: asking shows, and Soulseek is asked nothing before its word', [asks.length - before, classed('app-sweep').length], [0, 1])
    answerFormat('any')
    await settle()
    check('...its word in: the search goes, with that Format', [asks.length - before, asks.at(-1)?.body.format_preference], [1, 'any'])
    asks.at(-1).resolve(answer([]))
    await settle()
    phone.draw({ open: false })
    phone.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 412 } })
    phone.draw({ open: false })
    answerFormat('any')
    await settle()
    check('...and the sheet closed while it waited: Soulseek is asked nothing at all', asks.length - before, 1)
    globalThis.__sources.format = () => globalThis.__sources.settings?.format_preference ?? 'prefer_lossless'
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }
  }

  console.log('\nevery search the sheet starts asks deadwax for the settings first - a desktop panel left open too (review)')
  {
    const log = globalThis.__sources.settingsLog
    const desk = sheet()
    log.length = 0
    desk.draw({ open: true, panel: 'column', request: { release: RELEASE, subtitle: 'Third', key: 430 } })
    check('a Get opening the panel: deadwax asked, then the Format read for its search', log, ['ask', 'format'])
    asks.at(-1).resolve(answer([source('vinylhead')]))
    await settle()
    desk.draw()
    log.length = 0
    desk.draw({ request: { release: OTHER, subtitle: 'Dummy', key: 431 } })
    check('another Get with the panel still open: asked again before its search reads the Format', [log, asks.at(-1)?.body.release_mbid], [['ask', 'format'], 'rel-dummy'])
    asks.at(-1).resolve(answer([source('vinylhead')]))
    await settle()
    desk.draw()
    log.length = 0
    desk.draw({ request: { release: RELEASE, subtitle: 'Third', key: 432, again: true } })
    check('...and the panel following the page to another pressing', [log, asks.at(-1)?.body.release_mbid], [['ask', 'format'], 'rel-third'])
    asks.at(-1).resolve(answer([]))
    await settle()
    desk.draw()
    log.length = 0
    find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} })
    check('a Re-search', log, ['ask', 'format'])
    asks.at(-1).reject(new Error("slskd isn't logged in to Soulseek, so it can't search."))
    await settle()
    desk.draw()
    log.length = 0
    find((node) => node.type === 'button' && text(node) === 'Try again')[0].props.onClick()
    check('Try again', log, ['ask', 'format'])
    asks.at(-1).resolve(answer([]))
    await settle()
    desk.draw({ open: false, panel: 'sheet' })
  }

  console.log('\nLossless only, and Soulseek answered with nothing lossless: said so, and why (review)')
  {
    const status = () => text(find((node) => node.props?.role === 'status')[0])
    const NOTE = 'Soulseek answered, but your Format is Lossless only, which leaves out folders with no lossless files. You can change it in You, under Getting albums.'
    const phone = sheet()
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any', format_preference: 'lossless_only' }
    phone.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 440 } })
    asks.at(-1).resolve(answer([], { response_count: 4 }))
    await settle()
    phone.draw()
    check('nothing lossless on Soulseek - never "found nothing" - with the Format named, and where it is',
      [text(classed('app-sources-state-text')[0]), text(classed('app-sources-state-note')[0])],
      ['Nothing lossless on Soulseek for “Portishead Third”.', NOTE])
    check('...the query still there to edit, and Re-search', [find((node) => node.type === 'form').length, find((node) => node.type === 'input')[0]?.props.value], [1, 'Portishead Third'])
    check('...and VoiceOver told the same', status(), `Nothing lossless on Soulseek for “Portishead Third”. ${NOTE}`)
    phone.draw({ request: { release: RELEASE, subtitle: 'Third', key: 441 } })
    asks.at(-1).resolve(answer([], { response_count: 0 }))
    await settle()
    phone.draw()
    check('Lossless only, and no peer answered at all: Soulseek found nothing, as ever', [text(classed('app-sources-state-text')[0]), classed('app-sources-state-note').length],
      ['Soulseek found nothing for “Portishead Third”.', 0])
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any', format_preference: 'prefer_lossless' }
    phone.draw({ request: { release: RELEASE, subtitle: 'Third', key: 442 } })
    asks.at(-1).resolve(answer([], { response_count: 4 }))
    await settle()
    phone.draw()
    check('another Format, answers in and nothing left: Soulseek found nothing, as ever', [text(classed('app-sources-state-text')[0]), status()],
      ['Soulseek found nothing for “Portishead Third”.', 'Soulseek found nothing for “Portishead Third”.'])
    //? the Format the search was SENT with, as the store answered it - not what the settings said before
    let answerFormat = null
    globalThis.__sources.format = () => new Promise((resolve) => { answerFormat = resolve })
    phone.draw({ request: { release: RELEASE, subtitle: 'Third', key: 443 } })
    answerFormat('lossless_only')
    await settle()
    check('...the search sent with the Format deadwax answered', asks.at(-1)?.body.format_preference, 'lossless_only')
    asks.at(-1).resolve(answer([], { response_count: 2 }))
    await settle()
    phone.draw()
    check('...and it is that Format the sheet speaks of', text(classed('app-sources-state-text')[0]), 'Nothing lossless on Soulseek for “Portishead Third”.')
    globalThis.__sources.format = () => globalThis.__sources.settings?.format_preference ?? 'prefer_lossless'
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }
    phone.draw({ open: false })
  }

  console.log('\nSearch again, when folders were found (2.0.0-player.41)')
  {
    const again = () => find((node) => node.type === 'button' && text(node) === 'Search again')[0]
    const forms = () => find((node) => node.type === 'form')
    const fresh = sheet()
    fresh.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 420 } })
    check('not while asking', again(), undefined)
    asks.at(-1).resolve(answer([source('vinylhead'), source('bob', { score: 0.8 })], { query: 'Portishead Third', queries: ['Portishead Third', 'Third Portishead'] }))
    await settle()
    fresh.draw()
    const scroll = find(byClass('app-sources-scroll'))[0]
    const list = scroll.props.children.props.children.filter(Boolean)
    const order = list.at(-1).props.children.flat(Infinity).filter(Boolean).map((child) => child.props?.class ?? child.type)
    check('under the cards and the line saying what was searched: Search again, closed - no query form yet',
      [order.slice(-3, -1).concat(order.at(-1) === 'fragment' ? ['fragment'] : []), !!again(), again()?.props['aria-expanded'], forms().length],
      [['app-sources-list', 'app-sources-footer', 'fragment'], true, false, 0])
    again().props.onClick()
    fresh.draw()
    const form = forms()[0]
    check('a tap opens the query to edit under it - the form it controls, holding what was searched',
      [again()?.props['aria-expanded'], form?.props.id === again()?.props['aria-controls'], find((node) => node.type === 'input')[0]?.props.value, form?.props.class],
      [true, true, 'Portishead Third', 'app-sources-state is-again'])
    check('...its field the one focus goes to as it opens', find((node) => node.type === 'input')[0]?.props.ref !== undefined, true)
    check('...the cards still there above it', cards().length, 2)
    const before = asks.length
    form.props.onSubmit({ preventDefault() {} })
    check('an unedited Re-search overrides nothing - every name searched again', [asks.length - before, asks.at(-1)?.body.query_override], [1, ''])
    fresh.draw()
    check('...and a search starting closes Search again', [again(), forms().length], [undefined, 0])
    asks.at(-1).resolve(answer([source('vinylhead')], { query: 'Portishead Third' }))
    await settle()
    fresh.draw()
    check('the answer in: Search again closed', [again()?.props['aria-expanded'], forms().length], [false, 0])
    again().props.onClick()
    fresh.draw()
    find((node) => node.type === 'input')[0].props.onInput({ currentTarget: { value: 'Portishead - Third (2008) FLAC' } })
    fresh.draw()
    forms()[0].props.onSubmit({ preventDefault() {} })
    check('an edited one is searched as typed', asks.at(-1)?.body.query_override, 'Portishead - Third (2008) FLAC')
    asks.at(-1).resolve(answer([source('vinylhead')]))
    await settle()
    fresh.draw()
    again().props.onClick()
    fresh.draw()
    again().props.onClick()
    fresh.draw()
    check('a second tap on Search again closes it', [again()?.props['aria-expanded'], forms().length], [false, 0])

    //? none passing the chips: folders were found, so Search again is there too
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'lossless' }
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 421 } })
    asks.at(-1).resolve(answer([source('mp3guy', { formats: ['mp3'], bitrates: [320], bit_depths: [], sample_rates: [] })]))
    await settle()
    fresh.draw()
    check('none passing your filters: Search again under Clear filters', [text(classed('app-sources-state-text')[0]), !!again(), forms().length],
      ['1 folder on Soulseek, none pass your filters', true, 0])
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }

    //? nothing found: the query form is already there - no Search again beside it
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 422 } })
    asks.at(-1).resolve(answer([]))
    await settle()
    fresh.draw()
    check('nothing found: the one query form, as it always was, and no Search again', [forms().length, again()], [1, undefined])
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 423 } })
    asks.at(-1).reject(new Error("slskd isn't logged in to Soulseek, so it can't search."))
    await settle()
    fresh.draw()
    check('slskd unable to search: no Search again (Try again is the way)', again(), undefined)
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 424 } })
    asks.at(-1).resolve(answer([], { held: { path: 'P/T', paths: ['P/T'], artist: 'P', album: 'T', edition: '', track_count: 11, expected_tracks: 11, formats: ['flac'], complete: true, fills_gaps: false, filed_to: null }, query: '', queries: [] }))
    await settle()
    fresh.draw()
    check('held whole - the store\'s box, nothing searched: no Search again', again(), undefined)
    fresh.draw({ open: false })
  }

  console.log('\nsomebody else\'s download (2.0.0-player.49): what you\'d get, your floor\'s word, and Join - which hands over to Requests')
  {
    globalThis.__sources.settings = { get_mode: 'pick', quality_floor: 'lossless' }
    const before = requested.length
    const fresh = sheet()
    fresh.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 490 } })
    asks.at(-1).resolve(answer([], { downloading: { job_id: 7, status: 'downloading', username: 'mp3guy', files: 11, done_files: 3, yours: false,
      formats: ['mp3'], bitrates: [320], bit_depths: [], sample_rates: [44100], variable_bitrate: false }, query: '', queries: [] }))
    await settle()
    fresh.draw()
    const box = find((node) => node.type === StoreState)[0]
    check('"Already downloading for someone else": the peer, the copy, how far - below the floor, said - and what Join does', box?.props.status,
      { kind: 'downloading', title: 'Already downloading for someone else', lines: [
        'From mp3guy · MP3 320k · 3 of 11 files',
        "It's below your quality floor (Lossless), and getting a copy of your own isn't offered yet.",
        'Join it to have it in your Requests too - one download, everyone who asked waiting for it.'], joinJobId: 7 })
    check('...nothing picked for you, and nothing asked for', [requested.length - before, fresh.queued.length], [0, 0])
    await box.props.onJoin(7)
    check('Join joins that download, and hands over to Requests, as a Get does', [joined, fresh.queued.length], [[7], 1])
    //? a join answering after the sheet was closed hands over nothing - the sheet stays closed
    fresh.draw({ request: { release: RELEASE, subtitle: 'Third', key: 491 } })
    asks.at(-1).resolve(answer([], { downloading: { job_id: 8, status: 'queued', username: 'bob', files: 11, yours: false, formats: ['flac'] }, query: '', queries: [] }))
    await settle()
    fresh.draw()
    const joining = find((node) => node.type === StoreState)[0].props.onJoin(8)
    fresh.draw({ open: false })
    await joining
    check('...but not once the sheet has closed meanwhile', [joined, fresh.queued.length], [[7, 8], 1])
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }
  }

  console.log('\nComplete albums only, on both frames, and a desktop\'s sample-rate floor (2.0.0-player.50)')
  {
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }
    //? the whole CD of a CD+DVD ("14 of 14", nothing missing), a folder missing Threads, a 24/96 rip, and
    //? one whose client reported no sample rate
    const FOUR = [
      source('cddvd', { expected_tracks: 34, matched_tracks: 14, audio_expected: 14 }),
      source('short', { score: 0.85, matched_tracks: 10, audio_expected: 11, missing_tracks: [{ position: 11, disc: 1, title: 'Threads' }], missing_count: 1 }),
      source('hires', { score: 0.8, audio_expected: 11, bit_depths: [24], sample_rates: [96000] }),
      source('unsaid', { score: 0.75, audio_expected: 11, sample_rates: [] }),
    ]
    const names = () => cards().map((card) => card.props.candidate.username)
    const phone = sheet()
    phone.draw({ open: true, request: { release: RELEASE, subtitle: 'Third', key: 500 } })
    check('a phone\'s sheet: Complete albums only among the chips, off - and no sample-rate chip', [chips().at(-1), find((node) => node.type === RateChip).length],
      [['Complete albums only', false], 0])
    check('...the sheet\'s row: the three, Complete albums only, then the sort - no Signals there to keep a place for',
      find(byClass('app-sources-chips'))[0].props.children.flat().filter(Boolean).map((child) => child.props?.class?.includes('app-sources-sort') ? 'sort' : text(child)),
      ['Lossless', '24-bit', 'Free slot', 'Complete albums only', 'sort'])
    asks.at(-1).resolve(answer(FOUR))
    await settle()
    phone.draw()
    check('...every folder while it is off', names(), ['cddvd', 'short', 'hires', 'unsaid'])
    chip('Complete albums only').props.onClick()
    phone.draw()
    check('pressed: the folder missing a track left out - the whole CD of a CD+DVD kept, as its card counts it', [chip('Complete albums only').props['aria-pressed'], names()],
      [true, ['cddvd', 'hires', 'unsaid']])
    check('...the footer counting what passes', text(classed('app-sources-footer')[0]), 'Searched Soulseek for “Portishead Third” · 4 folders, 3 match your filters')
    phone.draw({ request: { release: RELEASE, subtitle: 'Third', key: 501 } })
    check('a fresh Get: it starts off again', chip('Complete albums only').props['aria-pressed'], false)
    asks.at(-1).resolve(answer([FOUR[1]]))
    await settle()
    phone.draw()
    chip('Complete albums only').props.onClick()
    phone.draw()
    check('none passing it: said, with Clear filters', [text(classed('app-sources-state-text')[0]), !!find((node) => node.type === 'button' && text(node) === 'Clear filters')[0]],
      ['1 folder on Soulseek, none pass your filters', true])
    find((node) => node.type === 'button' && text(node) === 'Clear filters')[0].props.onClick()
    phone.draw()
    check('...which turns it off', [chip('Complete albums only').props['aria-pressed'], names()], [false, ['short']])
    phone.draw({ open: false })

    const desk = sheet()
    desk.draw({ open: true, panel: 'column', request: { release: RELEASE, subtitle: 'Third', key: 502, from: 'rg-third' } })
    const rateChip = () => find((node) => node.type === RateChip)[0]
    check('a desktop\'s panel: the sample-rate chip, any to begin with', [!!rateChip(), rateChip()?.props.rate], [true, 0])
    asks.at(-1).resolve(answer(FOUR))
    await settle()
    desk.draw()
    rateChip().props.onChange(96000)
    desk.draw()
    check('96 kHz and up: only the 24/96 - the 44.1 folders and the one that said nothing left out', names(), ['hires'])
    rateChip().props.onChange(44100)
    desk.draw()
    check('44.1 and up: everything that said, never the one that didn\'t', names(), ['cddvd', 'short', 'hires'])
    chip('Complete albums only').props.onClick()
    desk.draw()
    check('...with Complete albums only too', names(), ['cddvd', 'hires'])
    const before = asks.length
    desk.draw({ request: { release: OTHER, subtitle: 'Third · 2×12" Vinyl', key: 503, from: 'rg-third', again: true } })
    check('another pressing chosen beside it (`again`): searched again, the floor and the chip as they were set',
      [asks.length - before, rateChip().props.rate, chip('Complete albums only').props['aria-pressed']], [1, 44100, true])
    asks.at(-1).resolve(answer([FOUR[3]]))
    await settle()
    desk.draw()
    chip('Complete albums only').props.onClick()
    desk.draw()
    const clear = find((node) => node.type === 'button' && text(node) === 'Clear filters')[0]
    check('the floor alone leaving out the one folder: Clear filters all the same, the floor counted as pressed', [chips().filter(([, on]) => on).length, !!clear], [0, true])
    clear.props.onClick()
    desk.draw()
    check('...which clears the floor too', [rateChip().props.rate, names()], [0, ['unsaid']])
    rateChip().props.onChange(96000)
    desk.draw({ request: { release: RELEASE, subtitle: 'Third', key: 504, from: 'rg-third' } })
    check('a fresh Get afterwards (not `again`): the floor off again', rateChip().props.rate, 0)
    asks.at(-1).resolve(answer(FOUR))
    await settle()
    desk.draw()
    rateChip().props.onChange(96000)
    desk.draw()
    desk.draw({ panel: 'sheet' })
    check('carried into a phone\'s sheet (a window narrowed): no chip, and nothing filtered by the floor', [find((node) => node.type === RateChip).length, names()],
      [0, ['cddvd', 'short', 'hires', 'unsaid']])
    desk.draw({ panel: 'column' })
    check('...and back on the panel, the floor as it was set', [rateChip().props.rate, names()], [96000, ['hires']])
    //? a pick goes by the floor too: told to pick, a fresh Get with a floor set as it runs
    globalThis.__sources.settings = { get_mode: 'pick', quality_floor: 'any' }
    const queuedBefore = desk.queued.length
    desk.draw({ request: { release: RELEASE, subtitle: 'Third', key: 505, from: 'rg-third' } })
    rateChip().props.onChange(96000)
    desk.draw()
    asks.at(-1).resolve(answer([source('cd', { score: 0.95 }), source('hires', { score: 0.8, bit_depths: [24], sample_rates: [96000] })]))
    await settle()
    desk.draw()
    check('a pick with a floor set takes the source above it, never the better match under it', [desk.queued.length - queuedBefore, requested.at(-1)?.username], [1, 'hires'])
    globalThis.__sources.settings = { get_mode: 'sources', quality_floor: 'any' }
    desk.draw({ open: false })

    console.log('\nthe sample-rate chip, drawn')
    const changes = []
    tree = RateChip({ rate: 0, onChange: (next) => changes.push(next) })
    const label = tree
    const select = find((node) => node.type === 'select')[0]
    check('a chip holding the platform\'s own picker: "Sample rate" for any, not pressed - and its name said', [label.props.class, text(find((node) => node.props?.['aria-hidden'] === 'true')[0]),
      text(classed('app-visually-hidden')[0]), select.props.class], ['app-chip app-sources-rate', 'Sample rate', 'The least sample rate', 'app-sources-sort-select'])
    check('...its choices: any, 44.1, 48, 88.2 and 96 kHz and up', find((node) => node.type === 'option').map((option) => [option.props.value, text(option)]),
      [['0', 'Any sample rate'], ['44100', '44.1 kHz or more'], ['48000', '48 kHz or more'], ['88200', '88.2 kHz or more'], ['96000', '96 kHz or more']])
    select.props.onChange({ currentTarget: { value: '88200' } })
    check('...a choice handed on as a number', changes, [88200])
    tree = RateChip({ rate: 88200, onChange: () => {} })
    check('a floor set: pressed, saying it', [tree.props.class, text(find((node) => node.props?.['aria-hidden'] === 'true')[0]), find((node) => node.type === 'select')[0].props.value],
      ['app-chip app-sources-rate is-on', '88.2 kHz+', '88200'])
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main()
