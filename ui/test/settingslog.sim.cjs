/**
 * Server settings and the log in the app, on a desktop (2.0.0-player.33): the pure rules in
 * lib/eventLog.ts and lib/serverSettings.ts, and both pages (app/ServerSettings.tsx, app/EventLog.tsx)
 * compiled with the repo's TypeScript and rendered by the small stand-in for Preact the other page sims
 * use (needslook.sim, group.sim) - here with function components drawn through, since the settings page
 * is drawn from the main page's own parts (components/SettingsView.tsx's ServerGroup, SettingRow,
 * OrganizingVerdict, OrganizeModes), which this renders for real.
 *
 * What it pins:
 *
 *  - SERVER SETTINGS: the server's groups only - no browser preference of the main page's, no Re-time
 *    lyrics (one line says they are the main page's, its link beside the app); every rule of a row (a
 *    secret masked, choices a dropdown, a locked one saying why, revert, the retype note); drafts kept
 *    across the tabs (a tab holding one marked) and ONE save sending them all in one batch; a refusal
 *    said in the bar with every draft still there, until the next save or Discard; Save the one solid
 *    purple button; read when it first shows and again on coming back only with no draft; a save calling
 *    a read still out off; an edit made while a save is on its way kept as a draft; a failed read's line
 *    gone once a save answers; focus given to the bar as Save or Discard goes, never to the page; the
 *    bar's live region its words alone, never its buttons; the drafts, the refusal and the tab outliving
 *    the page (left for a sibling, Back, Go to album - and mid-save), two copies drawn being one page,
 *    each told to draw again as it changes and a copy gone told nothing;
 *    the arrow keys moving through the tabs; on a phone a note, with nothing asked.
 *  - THE LOG: the history read, then the stream opened from its last number; history and stream joined
 *    by number - no gap, no line twice (the replay and a reconnect included); another run (deadwax
 *    restarted) starting again from its own numbers; a line holding markup drawn as its text, no element
 *    made of it; at most 500 lines; Clear emptying the view, saying so, and nothing cleared coming back;
 *    a history that failed filled in by the next; errors red, warnings amber; the lost stream ONE line,
 *    never a column - and asked again by hand when the browser gives up on it; the stream closed when the
 *    page is not what shows, and rejoined from the history on coming back; the lines, a Clear and a gap
 *    outliving the page (the page told to draw again by the history and by each line, and a page left told
 *    nothing); the history's and the stream's addresses as the REAL api/logs.ts makes them
 *    (deadwax faked at fetch, never the module); on a phone a note, with nothing asked.
 *
 * Run it with:  node ui/test/settingslog.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-settingslog-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/ServerSettings.tsx', 'src/app/EventLog.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - needslook.sim's stand-in
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
exports.useCallback = (f) => f
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
  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === 'function') s.cleanup() }
  //? the hooks' slots, so a sim can see whether a page was told to draw again (its first useState)
  render.slots = root.slots
  return render
}
`)

const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
//? deadwax, as the test says it answers: each ask kept, answered by hand
write('api/settings.js', `
exports.getServerSettings = (signal) => new Promise((resolve, reject) => globalThis.__w.reads.push({ resolve, reject, signal }))
exports.saveServerSettings = (updates) => new Promise((resolve, reject) => globalThis.__w.saves.push({ updates, resolve, reject }))
`)
//? the log's api/logs.ts is the REAL one (review: a copy of it here pinned nothing of the file - its
//? stream address could lose `boot` with every suite passing): deadwax is faked one layer down, at
//? fetch, which api/http.ts's get() calls - each ask kept with its address, answered by hand
globalThis.fetch = (address, init) => new Promise((resolve, reject) => globalThis.__w.recents.push({
  address, signal: init?.signal, reject,
  resolve: (body) => resolve({ ok: true, status: 200, json: () => Promise.resolve(body) }),
}))
write('player/icons.js', `exports.ChevronLeftIcon = function Icon() { return null }\n`)
//? the main page's settings tab pulls in modules the server half never calls
write('components/Loading.js', `exports.Loading = () => null; exports.LoadingPanel = () => null\n`)
write('state/persisted.js', `
exports.readSettingsTab = () => null; exports.writeSettingsTab = () => {}
exports.useDownloadDefaults = () => [{}, () => {}]; exports.usePreferences = () => [{}, () => {}, () => {}]
`)

//? the stream: each EventSource made, kept, closable
class FakeSource {
  static CONNECTING = 0
  static OPEN = 1
  static CLOSED = 2
  constructor(url) { this.url = url; this.closed = false; this.readyState = 0; globalThis.__w.sources.push(this) }
  close() { this.closed = true; this.readyState = 2 }
  send(line) { this.onmessage?.({ data: JSON.stringify(line) }) }
}
globalThis.EventSource = FakeSource

const W = globalThis.__w = { reads: [], saves: [], recents: [], sources: [] }

const L = require(path.join(OUT, 'lib/eventLog.js'))
const S = require(path.join(OUT, 'lib/serverSettings.js'))
const API = require(path.join(OUT, 'api/logs.js'))
const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { ServerSettings, forgetServerSettingsPage } = require(path.join(OUT, 'app/ServerSettings.js'))
const { EventLog, forgetEventLogPage } = require(path.join(OUT, 'app/EventLog.js'))
//? a fresh page: the asks forgotten, and what both pages keep beyond their own life (their modules)
const reset = () => {
  W.reads.length = 0; W.saves.length = 0; W.recents.length = 0; W.sources.length = 0
  forgetServerSettingsPage(); forgetEventLogPage()
}

/* ===== the tree ===== */

let tree = null
//? function components drawn through (none of the parts drawn here holds state of its own)
function expand(node) {
  if (node === null || node === undefined || typeof node !== 'object') return node
  if (Array.isArray(node)) return node.map(expand)
  if (typeof node.type === 'function') return expand(node.type(node.props))
  return { ...node, props: { ...node.props, children: expand(node.props?.children) } }
}
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
function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const classed = (name, within) => find(byClass(name), within)
const button = (label) => find((node) => node.type === 'button' && words(node).trim() === label)[0]

function mount(component, props) {
  const render = hooks.root(component)
  const all = { desktop: true, live: true, backLabel: 'You', onBack() {}, ...props }
  const draw = (more = {}) => {
    Object.assign(all, more)
    tree = expand(render(all))
    render.commit()
    tree = expand(render(all))
    render.commit()
    return tree
  }
  //? how many times the page has been told to draw again - its first hook, the `redraw` counter each
  //? page keeps (their state is their module's: nothing else would draw them again in a real page)
  const redraws = () => render.slots[0]?.v ?? 0
  return { draw, all, redraws, unmount: () => render.unmount() }
}

/* ===== the pure rules ===== */

console.log('\nthe log: history and stream joined by number')
{
  const line = (seq, words, boot = 'A', more = {}) => ({ event_type: 'INFO', event_content: words, seq, boot, time: 1700000000 + seq, ...more })
  let state = L.joinHistory(L.emptyLog(), { boot: 'A', last: 3, lines: [line(1, 'one'), line(2, 'two'), line(3, 'three')] })
  check('the history in, newest first, its run and last number kept', [state.lines.map((l) => l.event_content), state.boot, state.last], [['three', 'two', 'one'], 'A', 3])
  state = L.joinLine(state, line(3, 'three'))
  state = L.joinLine(state, line(2, 'two'))
  check('...a line at or below what the page has is dropped - the stream\'s replay, a reconnect', state.lines.length, 3)
  state = L.joinLine(state, line(4, 'four'))
  check('...a newer one goes on top', [state.lines[0].event_content, state.last], ['four', 4])
  state = L.joinLine(state, line(1, 'after the restart', 'B'))
  check('another run (deadwax restarted) starts again from its own numbers', [state.lines[0].event_content, state.boot, state.last], ['after the restart', 'B', 1])
  check('...and its own number 1 again is dropped', L.joinLine(state, line(1, 'after the restart', 'B')).lines.length, 5)
  const cleared = L.clearLog(state)
  check('Clear empties the view, keeping the number - and says it was cleared', [cleared.lines.length, cleared.boot, cleared.last, cleared.cleared], [0, 'B', 1, true])
  check('...which the next line taken undoes', L.joinLine(cleared, line(2, 'next', 'B')).cleared, false)
  check('what an empty log says: nothing yet, or cleared', [L.EMPTY_WORDS.never, L.EMPTY_WORDS.cleared], ['Nothing logged yet.', 'Cleared. New lines show here as deadwax logs them.'])
  check('...so nothing cleared comes back from the history', L.joinHistory(cleared, { boot: 'B', last: 1, lines: [line(1, 'after the restart', 'B')] }).lines.length, 0)
  check('a history of a later run with nothing logged yet: that run\'s, from its number',
    (({ boot, last }) => [boot, last])(L.joinHistory(state, { boot: 'C', last: 0, lines: [] })), ['C', 0])
  console.log('\nthe log: a history that couldn\'t be read, filled in by the next')
  let gapped = L.emptyLog()
  for (let n = 101; n <= 103; n++) gapped = L.joinLine(gapped, line(n, `line ${n}`))
  check('a run\'s first line heard with no history: a gap below it', [gapped.gap, gapped.last], [101, 103])
  const filled = L.joinHistory(gapped, { boot: 'A', last: 104, lines: Array.from({ length: 104 }, (_, i) => line(i + 1, `line ${i + 1}`)) })
  check('...the next history fills it: every line once, in order, newest first, the gap gone',
    [filled.lines.length, filled.lines[0].event_content, filled.lines.at(-1).event_content, filled.lines.map((l) => l.seq).join() === Array.from({ length: 104 }, (_, i) => 104 - i).join(), filled.gap],
    [104, 'line 104', 'line 1', true, null])
  check('a run\'s line 1 leaves no gap (it is the first deadwax logged)', L.joinLine(L.emptyLog(), line(1, 'first')).gap, null)
  check('a history starting past 1 (all deadwax kept) leaves no gap',
    L.joinHistory(L.emptyLog(), { boot: 'A', last: 502, lines: [line(501, 'a'), line(502, 'b')] }).gap, null)
  let twoRuns = L.joinHistory(L.emptyLog(), { boot: 'A', last: 2, lines: [line(1, 'A one'), line(2, 'A two')] })
  twoRuns = L.joinLine(twoRuns, line(40, 'B forty', 'B'))
  check('deadwax restarted with the stream from now: the new run\'s gap', [twoRuns.boot, twoRuns.gap], ['B', 40])
  check('...filled under the new run\'s lines and above the old run\'s',
    L.joinHistory(twoRuns, { boot: 'B', last: 41, lines: [line(39, 'B thirty-nine', 'B'), line(40, 'B forty', 'B'), line(41, 'B forty-one', 'B')] }).lines.map((l) => l.event_content),
    ['B forty-one', 'B forty', 'B thirty-nine', 'A two', 'A one'])
  check('...a history of ANOTHER run fills nothing of it', L.joinHistory(twoRuns, { boot: 'C', last: 0, lines: [] }).lines.length, 3)
  check('Clear drops the gap too: nothing older than the view comes back', L.joinHistory(L.clearLog(gapped), { boot: 'A', last: 103, lines: [line(1, 'line 1'), line(103, 'line 103')] }).lines.length, 0)
  let many = L.emptyLog()
  for (let n = 1; n <= 600; n++) many = L.joinLine(many, line(n, `line ${n}`))
  check('at most 500 lines kept, the oldest dropped', [L.LOG_KEPT, many.lines.length, many.lines.at(-1).event_content, many.lines[0].event_content], [500, 500, 'line 101', 'line 600'])
  check('errors red, warnings amber, the rest plain', ['ERROR', 'CRITICAL', 'WARNING', 'INFO', 'DEBUG'].map(L.levelOf), ['error', 'error', 'warning', 'info', 'info'])
  check('a line\'s time: HH:MM:SS from the server\'s; none when it sent none', [/^\d\d:\d\d:\d\d$/.test(L.lineTime(line(1, 'x'))), L.lineTime({ event_type: 'INFO', event_content: 'x' })], [true, ''])
  check('where the stream stands, in words', L.STREAM_WORDS, { connecting: 'Connecting…', live: 'Live', lost: 'The stream was lost - trying again' })
}

console.log('\nthe log: its addresses, as api/logs.ts makes them')
{
  check('the stream from now: no query (the main page\'s stream, exactly as before)', API.logStreamUrl(null, null), '/deadwax/interface_logs/interface_logs')
  check('...from a number of a run: after it, of that run', API.logStreamUrl(3, 'A'), '/deadwax/interface_logs/interface_logs?after=3&boot=A')
  check('...from 0 (a run nothing was heard of yet): still sent', API.logStreamUrl(0, 'B'), '/deadwax/interface_logs/interface_logs?after=0&boot=B')
  check('...the run\'s name encoded', API.logStreamUrl(7, 'a b&c'), '/deadwax/interface_logs/interface_logs?after=7&boot=a%20b%26c')
  check('...a number with no run is from now (deadwax would read it as its own run\'s)', API.logStreamUrl(5, null), '/deadwax/interface_logs/interface_logs')
  reset()
  void API.recentLog()
  check('the history: GET /deadwax/interface_logs/recent', W.recents.map((ask) => ask.address), ['/deadwax/interface_logs/recent'])
  reset()
}

console.log('\nserver settings: the tabs')
{
  check('the three server tabs, Library first (the main page lists Downloads, Library, Connections after its Search)', S.SERVER_TABS.map((tab) => tab.id), ['library', 'downloads', 'connections'])
  check('an arrow key moves round from the ends', [S.serverTabAfter('library', 1), S.serverTabAfter('connections', 1), S.serverTabAfter('library', -1)], ['downloads', 'library', 'connections'])
}

console.log('\nserver settings: the drafts left once a save is answered')
{
  const sent = { A: 'one', B: null }
  check('what was sent, still as sent, goes; a key typed again since, or one never sent, stays',
    S.draftsAfterSave({ A: 'one', B: null, C: 'three' }, sent), { C: 'three' })
  check('...a key sent and typed again meanwhile is kept, as typed', S.draftsAfterSave({ A: 'changed', B: null }, sent), { A: 'changed' })
  check('...a revert made since a value was sent is kept (null is a draft too)', S.draftsAfterSave({ A: null }, sent), { A: null })
  check('...nothing left when nothing changed meanwhile', S.draftsAfterSave({ A: 'one', B: null }, sent), {})
}

/* ===== the settings page ===== */

const setting = (key, more = {}) => ({
  key, value: null, source: '.env', status: 'ok', detail: null, effect: `what ${key} does`, required: false,
  secret: false, editable: true, locked_reason: null, overridden: false, env_value: null, choices: null, ...more,
})
const SETTINGS = () => ({
  version: '2.0.0-player.33', editable: true,
  organizing: { enabled: false, blockers: ['SLSKD_DOWNLOAD_PATH is not set'] },
  organize_modes: { off: 'Nothing is filed', dry_run: 'Says what it would do', copy: 'Copies', move: 'Moves' },
  groups: [
    { id: 'connections', label: 'Connections', note: '', settings: [
      setting('NAVIDROME_URL', { value: 'http://navidrome:4533', source: 'the container environment' }),
      setting('NAVIDROME_PASSWORD', { secret: true, value: 'set' }),
    ] },
    { id: 'paths', label: 'Paths', note: 'Where files are', settings: [
      setting('LIBRARY_PATH', { value: '/music', overridden: true, env_value: '/data/music' }),
      setting('DB_PATH', { value: '/config/deadwax.db', editable: false, locked_reason: 'It is the database the overrides live in.' }),
      setting('SLSKD_DOWNLOAD_PATH', { status: 'error', detail: 'Not set: nothing can be filed.' }),
    ] },
    { id: 'organizing', label: 'Organizing', note: '', settings: [
      setting('ORGANIZE_MODE', { value: 'dry_run', choices: { off: 'Off', dry_run: 'Dry run', copy: 'Copy', move: 'Move' } }),
    ] },
    { id: 'lyrics', label: 'Lyrics', note: '', settings: [setting('LYRICS_LEAD_MS', { value: '0' })] },
    { id: 'soulseek', label: 'Soulseek searches', note: '', settings: [setting('SLSKD_SEARCH_TIMEOUT', { value: '8' })] },
  ],
})
const row = (key) => find((node) => byClass('settings-env')(node) && find((child) => child.type === 'code' && words(child) === key, node).length > 0)[0]
const input = (key) => find((node) => node.type === 'input' || node.type === 'select', row(key))[0]
const type = (key, value) => input(key).props[input(key).type === 'select' ? 'onChange' : 'onInput']({ currentTarget: { value } })
const tab = (id) => find((node) => node.props?.role === 'tab' && node.props['data-tab'] === id)[0]
const savebar = () => words(classed('app-settings-savebar-text')[0])

async function settingsPage() {
  console.log('\nserver settings: on a phone, a note - and nothing asked')
  {
    reset()
    const phone = mount(ServerSettings, { desktop: false })
    phone.draw()
    const link = find((node) => node.type === 'a')[0]
    check('the note, and the main page beside the app', [words(classed('app-settings-phone')[0]).replace(/\s+/g, ' '), link.props.target, link.props.rel],
      ["Changing deadwax's settings needs a wider screen for now - or the main page.", '_blank', 'noopener'])
    check('...nothing read', W.reads.length, 0)
  }

  console.log('\nserver settings: read when it shows, its groups drawn from the main page\'s parts')
  reset()
  const page = mount(ServerSettings, { live: false })
  page.draw()
  check('not showing: nothing read (never at start-up)', W.reads.length, 0)
  page.draw({ live: true })
  check('showing: read once, through a call that can be called off', [W.reads.length, !!W.reads[0].signal], [1, true])
  check('...the spinner until it answers', classed('pl-spinner').length, 1)
  W.reads[0].resolve(SETTINGS())
  await settle()
  page.draw()
  check('the three server tabs, Library first', find((node) => node.props?.role === 'tab').map((node) => [node.props['data-tab'], node.props['aria-selected']]),
    [['library', true], ['downloads', false], ['connections', false]])
  check('Library: the organizing verdict, its blockers, the library groups, then the organize modes',
    [words(classed('settings-verdict-title')[0]), classed('settings-verdict-list')[0] && words(classed('settings-verdict-list')[0]), classed('settings-section-title').map(words)],
    ['Organizing will not file anything right now.', 'SLSKD_DOWNLOAD_PATH is not set', ['Paths', 'Organizing', 'Lyrics', 'Organize modes']])
  check('no browser preference of the main page\'s, no Re-time lyrics',
    [find((node) => /Results per search|Auto-grab|Studio albums|Open the log on start/.test(typeof node === 'string' ? node : '')).length,
      words(tree).includes('Results per search'), words(tree).includes('Auto-grab'), words(tree).includes('Re-time saved lyrics')],
    [0, false, false, false])
  const line = classed('app-settings-line')[0]
  const lineLink = find((node) => node.type === 'a', line)[0]
  check('...one line says they are the main page\'s, its link beside the app',
    [words(line).includes("This browser's preferences and re-timing saved lyrics are on"), lineLink.props.href, lineLink.props.target, lineLink.props.rel], [true, '/', '_blank', 'noopener'])
  check('a row: where its value came from, its status, what it does',
    [words(row('LIBRARY_PATH')).includes('Set here'), words(row('SLSKD_DOWNLOAD_PATH')).includes('Needs attention'), words(row('SLSKD_DOWNLOAD_PATH')).includes('Not set: nothing can be filed.'), words(row('LIBRARY_PATH')).includes('what LIBRARY_PATH does')],
    [true, true, true, true])
  check('...a setting that can\'t be edited says so, and why', [words(row('DB_PATH')).includes('Locked'), words(row('DB_PATH')).includes('the database the overrides live in'), find((node) => node.type === 'input', row('DB_PATH')).length], [true, true, 0])
  check('...choices as a dropdown', [input('ORGANIZE_MODE').type, find((node) => node.type === 'option', row('ORGANIZE_MODE')).map(words)], ['select', ['Off', 'Dry run', 'Copy', 'Move']])
  check('...an override offers to revert to the environment', !!button('Revert to the environment (/data/music)'), true)
  check('a tab holding a setting that needs attention is marked', classed('app-settings-mark', tab('library')).map((node) => node.props.class), ['app-settings-mark is-attention'])
  check('the save bar there and saying nothing; no save button yet', [classed('app-settings-savebar').length, savebar(), !!button('Save changes')], [1, '', false])

  console.log('\nserver settings: drafts across the tabs, one save')
  type('ORGANIZE_MODE', 'copy')
  page.draw()
  tab('connections').props.onClick()
  page.draw()
  check('another tab: its groups; the first tab marked as holding an unsaved change', [classed('settings-section-title').map(words), classed('app-settings-mark', tab('library')).length], [['Connections'], 1])
  const secret = input('NAVIDROME_PASSWORD')
  check('a secret masked: a password field, empty, saying one is set', [secret.props.type, secret.props.value, secret.props.placeholder], ['password', '', '•••••••• (set)'])
  type('NAVIDROME_URL', 'http://elsewhere:4533')
  page.draw()
  check('a new address: the secret\'s row asks for it again (the settings tab\'s own note)', words(row('NAVIDROME_PASSWORD')).includes('Type the password again'), true)
  type('NAVIDROME_PASSWORD', 'set')
  page.draw()
  check('...a secret has no value to read back: typing anything is a change, even the word the row says ("set")', words(row('NAVIDROME_PASSWORD')).includes('Unsaved'), true)
  type('NAVIDROME_PASSWORD', 'hunter2')
  page.draw()
  check('...typed: the note goes', words(row('NAVIDROME_PASSWORD')).includes('Type the password again'), false)
  check('three drafts across two tabs, one save bar', savebar(), '3 unsaved changes')
  type('NAVIDROME_URL', 'http://navidrome:4533')
  page.draw()
  check('set back to what is saved: no change', savebar(), '2 unsaved changes')
  type('NAVIDROME_URL', 'http://elsewhere:4533')
  page.draw()
  tab('library').props.onClick()
  page.draw()
  check('...seen from Library: Connections marked as holding an unsaved change (Library\'s own mark is for attention)',
    [classed('app-settings-mark', tab('connections')).map((node) => node.props.class), classed('app-settings-mark', tab('downloads')).length], [['app-settings-mark'], 0])
  tab('connections').props.onClick()
  page.draw()
  const primaries = find((node) => node.type === 'button' && /\bis-primary\b/.test(node.props.class ?? ''))
  check('Save is the one solid purple button', primaries.map(words), ['Save changes'])
  const statuses = find((node) => node.props?.role === 'status')
  check('the bar\'s live region is its words alone - never around Discard and Save, whose names a screen reader would read with every change',
    [statuses.map((node) => node.props.class), classed('app-settings-savebar')[0].props.role, statuses.flatMap((node) => find((child) => child.type === 'button', node)).length],
    [['app-settings-savebar-text'], undefined, 0])
  button('Save changes').props.onClick()
  page.draw()
  check('ONE batch with every draft, whichever tab it was made on', W.saves.map((save) => [...save.updates].sort((a, b) => a.key.localeCompare(b.key))),
    [[{ key: 'NAVIDROME_PASSWORD', value: 'hunter2' }, { key: 'NAVIDROME_URL', value: 'http://elsewhere:4533' }, { key: 'ORGANIZE_MODE', value: 'copy' }]])
  check('...saying so meanwhile, and refusing a second save', [words(button('Saving…')), button('Saving…').props['aria-disabled']], ['Saving…', 'true'])
  W.saves[0].reject(new Error("NAVIDROME_URL: has a user name or password in it - leave the login to NAVIDROME_USER"))
  await settle()
  page.draw()
  check('refused: said in the bar, every draft still there, nothing on the page changed',
    [savebar(), classed('is-edited').filter(byClass('settings-env')).length, input('NAVIDROME_URL').props.value, classed('app-settings-savebar')[0].props.class.includes('has-error')],
    ['Not saved: NAVIDROME_URL: has a user name or password in it - leave the login to NAVIDROME_USER', 2, 'http://elsewhere:4533', true])

  console.log('\nserver settings: read again on coming back - only with no draft')
  page.draw({ live: false })
  page.draw({ live: true })
  check('back with drafts: nothing read over them', W.reads.length, 1)
  button('Save changes').props.onClick()
  const fresh = SETTINGS()
  fresh.groups[0].settings[0].value = 'http://elsewhere:4533'
  fresh.groups[0].settings[0].overridden = true
  W.saves[1].resolve(fresh)
  await settle()
  page.draw()
  check('saved: the server\'s answer drawn, the drafts gone, "Saved."', [input('NAVIDROME_URL').props.value, savebar(), classed('is-edited').filter(byClass('settings-env')).length], ['http://elsewhere:4533', 'Saved.', 0])
  page.draw({ live: false })
  page.draw({ live: true })
  check('back with no draft: read again (a volume just fixed shows as fixed)', W.reads.length, 2)
  W.reads[1].resolve(SETTINGS())
  await settle()

  console.log('\nserver settings: revert, Discard, and a save calling a read still out off')
  page.draw()
  tab('library').props.onClick()
  page.draw()
  button('Revert to the environment (/data/music)').props.onClick()
  page.draw()
  check('revert: a draft of nothing, said on the row', [savebar(), words(row('LIBRARY_PATH')).includes('Will revert to the environment on save.')], ['1 unsaved change', true])
  button('Discard').props.onClick()
  page.draw()
  check('Discard: every draft dropped, the bar saying nothing', [savebar(), words(row('LIBRARY_PATH')).includes('Will revert')], ['', false])
  button('Revert to the environment (/data/music)').props.onClick()
  page.draw()
  button('Save changes').props.onClick()
  check('the revert sent as a null: the override deleted, never the environment\'s value written back', W.saves[2].updates, [{ key: 'LIBRARY_PATH', value: null }])
  const reverted = SETTINGS()
  reverted.groups[1].settings[0] = setting('LIBRARY_PATH', { value: '/data/music' })
  W.saves[2].resolve(reverted)
  await settle()
  page.draw()
  check('...the row as the save answered: the environment\'s, no revert offered', [input('LIBRARY_PATH').props.value, !!button('Revert to the environment (/data/music)')], ['/data/music', false])
  page.unmount()

  {
    reset()
    const raced = mount(ServerSettings)
    raced.draw()
    W.reads[0].resolve(SETTINGS())
    await settle()
    raced.draw()
    type('ORGANIZE_MODE', 'move')
    raced.draw()
    //? a read out when the save begins (here, begun by hand) must not land over the save's answer
    raced.draw({ live: false })
    button('Discard').props.onClick()
    raced.draw({ live: true })
    const out = W.reads[1]
    type('ORGANIZE_MODE', 'move')
    raced.draw()
    button('Save changes').props.onClick()
    const saved = SETTINGS()
    saved.groups[2].settings[0].value = 'move'
    W.saves[0].resolve(saved)
    await settle()
    out.resolve(SETTINGS())
    await settle()
    raced.draw()
    check('a read still out as a save began lands over nothing: the save\'s answer stands', [out.signal.aborted, input('ORGANIZE_MODE').props.value], [true, 'move'])
  }

  console.log('\nserver settings: an edit made while a save is on its way')
  {
    reset()
    const busy = mount(ServerSettings)
    busy.draw()
    W.reads[0].resolve(SETTINGS())
    await settle()
    busy.draw()
    type('ORGANIZE_MODE', 'copy')
    busy.draw()
    button('Save changes').props.onClick()
    busy.draw()
    //? the rows stay editable while it saves
    type('LYRICS_LEAD_MS', '300')
    type('ORGANIZE_MODE', 'move')
    busy.draw()
    const saved = SETTINGS()
    saved.groups[2].settings[0].value = 'copy'
    W.saves[0].resolve(saved)
    await settle()
    busy.draw()
    check('the save carried what was there at the click', W.saves[0].updates, [{ key: 'ORGANIZE_MODE', value: 'copy' }])
    check('...an edit made meanwhile stays a draft - a key it never sent, and a key typed again since - never wiped under "Saved."',
      [savebar(), input('LYRICS_LEAD_MS').props.value, input('ORGANIZE_MODE').props.value, classed('is-edited').filter(byClass('settings-env')).length],
      ['2 unsaved changes', '300', 'move', 2])
    button('Discard').props.onClick()
    busy.draw()
    check('...Discarded instead: the bar says nothing - never "Saved." for what Discard dropped', savebar(), '')
    type('LYRICS_LEAD_MS', '300')
    type('ORGANIZE_MODE', 'move')
    busy.draw()
    button('Save changes').props.onClick()
    check('...and the next save carries them', [...W.saves[1].updates].sort((a, b) => a.key.localeCompare(b.key)),
      [{ key: 'LYRICS_LEAD_MS', value: '300' }, { key: 'ORGANIZE_MODE', value: 'move' }])
    busy.unmount()
  }

  console.log('\nserver settings: a failed read\'s line goes once a save answers')
  {
    reset()
    const again = mount(ServerSettings)
    again.draw()
    W.reads[0].resolve(SETTINGS())
    await settle()
    again.draw({ live: false })
    again.draw({ live: true })
    W.reads[1].reject(new Error('HTTP 502'))
    await settle()
    again.draw()
    check('a read failing over settings in hand: said over them', words(classed('app-settings-problem')[0]), "Couldn't read the settings again just now: HTTP 502")
    type('SLSKD_SEARCH_TIMEOUT', '12')
    again.draw()
    button('Save changes').props.onClick()
    W.saves[0].resolve(SETTINGS())
    await settle()
    again.draw()
    check('...saved: the settings just answered, the line gone', [classed('app-settings-problem').length, savebar()], [0, 'Saved.'])
    again.unmount()
  }

  console.log('\nserver settings: a refusal stays until the next save or Discard')
  {
    reset()
    const refused = mount(ServerSettings)
    refused.draw()
    W.reads[0].resolve(SETTINGS())
    await settle()
    refused.draw()
    type('ORGANIZE_MODE', 'move')
    refused.draw()
    button('Save changes').props.onClick()
    W.saves[0].reject(new Error('ORGANIZE_MODE: no'))
    await settle()
    refused.draw()
    check('refused: said in the bar', [savebar(), classed('app-settings-savebar')[0].props.class], ['Not saved: ORGANIZE_MODE: no', 'app-settings-savebar has-error is-said'])
    button('Discard').props.onClick()
    refused.draw()
    check('...Discard: the drafts and the refusal gone, the bar saying nothing', [savebar(), classed('app-settings-savebar')[0].props.class], ['', 'app-settings-savebar'])
    refused.unmount()
  }

  console.log('\nserver settings: the drafts outlive the page - left for a sibling, Back, Go to album')
  {
    reset()
    const first = mount(ServerSettings)
    first.draw()
    W.reads[0].resolve(SETTINGS())
    await settle()
    first.draw()
    type('ORGANIZE_MODE', 'move')
    first.draw()
    tab('connections').props.onClick()
    first.draw()
    type('NAVIDROME_URL', 'http://elsewhere:4533')
    first.draw()
    button('Save changes').props.onClick()
    W.saves[0].reject(new Error('NAVIDROME_PASSWORD: type it again'))
    await settle()
    first.draw()
    //? App draws only a tab's top page: the sidebar's Log (which replaces it), Back, Go to album - it goes
    first.unmount()
    const again = mount(ServerSettings)
    again.draw()
    check('back: the refusal still said, on the tab it was left on, its draft drawn',
      [savebar(), tab('connections')?.props['aria-selected'], row('NAVIDROME_URL') && input('NAVIDROME_URL')?.props.value, classed('is-edited').filter(byClass('settings-env')).length],
      ['Not saved: NAVIDROME_PASSWORD: type it again', true, 'http://elsewhere:4533', 1])
    tab('library').props.onClick()
    again.draw()
    check('...and the other tab\'s draft too', [input('ORGANIZE_MODE').props.value, classed('is-edited').filter(byClass('settings-env')).length], ['move', 1])
    check('...nothing read over them', W.reads.length, 1)
    tab('connections').props.onClick()
    again.draw()
    type('NAVIDROME_PASSWORD', 'hunter2')
    again.draw()
    button('Save changes').props.onClick()
    check('...and Save sends them all, those made before it was left included', [...W.saves[1].updates].sort((a, b) => a.key.localeCompare(b.key)),
      [{ key: 'NAVIDROME_PASSWORD', value: 'hunter2' }, { key: 'NAVIDROME_URL', value: 'http://elsewhere:4533' }, { key: 'ORGANIZE_MODE', value: 'move' }])
    //? left while the save is on its way: its answer still lands
    again.unmount()
    const saved = SETTINGS()
    saved.groups[2].settings[0].value = 'move'
    W.saves[1].resolve(saved)
    await settle()
    const third = mount(ServerSettings, { live: false })
    third.draw()
    tab('library').props.onClick()
    third.draw()
    check('left while saving: back to what the save answered - "Saved.", no draft', [savebar(), input('ORGANIZE_MODE').props.value, classed('is-edited').filter(byClass('settings-env')).length], ['Saved.', 'move', 0])
    third.draw({ live: true })
    check('...and, with no draft, read again as it shows', W.reads.length, 2)
    W.reads[1].resolve(saved)
    await settle()
    third.draw()
    type('LYRICS_LEAD_MS', '300')
    third.draw()
    button('Discard').props.onClick()
    third.draw()
    third.unmount()
    const fourth = mount(ServerSettings)
    fourth.draw()
    check('Discarded and left: nothing kept, read again as it shows', [savebar(), W.reads.length], ['', 3])
    W.reads[2].resolve(SETTINGS())
    await settle()
    fourth.draw()
    //? an address can put the page on another tab too: two copies drawn are one page
    const other = mount(ServerSettings, { live: false })
    other.draw()
    fourth.draw()
    const otherTold = other.redraws()
    type('LYRICS_LEAD_MS', '250')
    check('...a draft made in one copy tells the other to draw again (the drafts are the module\'s: nothing else would)', other.redraws() > otherTold, true)
    other.draw()
    check('two copies of the page drawn: one page - a draft made in one is the other\'s', savebar(), '1 unsaved change')
    other.unmount()
    const goneTold = other.redraws()
    fourth.draw()
    type('LYRICS_LEAD_MS', '260')
    check('...a copy gone is told nothing more (its listener let go)', other.redraws(), goneTold)
    fourth.unmount()
  }

  console.log('\nserver settings: focus never dropped to the page as Save or Discard goes')
  {
    reset()
    const BODY = { body: true }
    let focused = 0
    globalThis.document = { body: BODY, activeElement: BODY }
    const kept = mount(ServerSettings)
    kept.draw()
    W.reads[0].resolve(SETTINGS())
    await settle()
    kept.draw()
    classed('app-settings-savebar-text')[0].props.ref.current = { focus() { focused++ } }
    check('what the bar says can take focus, out of the tab order', classed('app-settings-savebar-text')[0].props.tabIndex, -1)
    type('ORGANIZE_MODE', 'move')
    kept.draw()
    button('Save changes').props.onClick()
    W.saves[0].resolve(SETTINGS())
    await settle()
    kept.draw()
    check('saved, the buttons gone with the drafts, focus fallen to the page: given to what the bar says', focused, 1)
    type('ORGANIZE_MODE', 'copy')
    kept.draw()
    button('Discard').props.onClick()
    kept.draw()
    check('...and the same for Discard', focused, 2)
    type('ORGANIZE_MODE', 'copy')
    kept.draw()
    globalThis.document.activeElement = { elsewhere: true }
    button('Discard').props.onClick()
    kept.draw()
    check('...focus somewhere else meanwhile is left where it went', focused, 2)
    globalThis.document.activeElement = BODY
    type('ORGANIZE_MODE', 'copy')
    kept.draw()
    //? set back to the saved value, the last draft goes with focus still in the field
    globalThis.document.activeElement = { field: true }
    type('ORGANIZE_MODE', 'dry_run')
    kept.draw()
    check('...nor when typing a value back takes the buttons away with focus in the field', [savebar(), focused], ['', 2])
    delete globalThis.document
    kept.unmount()
  }

  console.log('\nserver settings: the arrow keys move through the tabs')
  {
    reset()
    const keys = mount(ServerSettings)
    keys.draw()
    W.reads[0].resolve(SETTINGS())
    await settle()
    keys.draw()
    let focusedTab = null
    let prevented = 0
    const tablist = () => find((node) => node.props?.role === 'tablist')[0]
    tablist().props.ref.current = { querySelector: (selector) => ({ focus() { focusedTab = selector } }) }
    const press = (key) => tablist().props.onKeyDown({ key, preventDefault() { prevented++ } })
    press('ArrowRight')
    keys.draw()
    check('ArrowRight from Library: Downloads chosen and focused', [tab('downloads').props['aria-selected'], focusedTab, prevented], [true, '[data-tab="downloads"]', 1])
    press('ArrowLeft')
    keys.draw()
    check('...ArrowLeft: back to Library', [tab('library').props['aria-selected'], focusedTab], [true, '[data-tab="library"]'])
    press('ArrowLeft')
    keys.draw()
    check('...round from the end', tab('connections').props['aria-selected'], true)
    press('a')
    keys.draw()
    check('...any other key moves nothing and is left to the page', [tab('connections').props['aria-selected'], prevented], [true, 3])
    keys.unmount()
  }
}

/* ===== the log page ===== */

const logLine = (seq, words, more = {}) => ({ event_type: 'INFO', event_content: words, seq, boot: 'A', time: 1700000000 + seq, ...more })
const drawnLines = () => classed('app-log-words').map(words)

async function logPage() {
  console.log('\nthe log: on a phone, a note - and nothing asked')
  {
    reset()
    const phone = mount(EventLog, { desktop: false })
    phone.draw()
    const link = find((node) => node.type === 'a')[0]
    check('the note, and the main page beside the app', [words(classed('app-log-phone')[0]).replace(/\s+/g, ' '), link.props.target, link.props.rel],
      ['The log needs a wider screen for now - or the main page.', '_blank', 'noopener'])
    check('...no history asked, no stream opened', [W.recents.length, W.sources.length], [0, 0])
  }

  console.log('\nthe log: the history, then the stream from its last number')
  reset()
  const page = mount(EventLog, { live: false })
  page.draw()
  check('not showing: nothing asked, no stream', [W.recents.length, W.sources.length], [0, 0])
  page.draw({ live: true })
  check('showing: the history asked first, no stream until it answers; "Connecting…"', [W.recents.length, W.sources.length, words(classed('app-log-stream')[0])], [1, 0, 'Connecting…'])
  check('...at its address, through a call that can be called off', [W.recents[0].address, !!W.recents[0].signal], ['/deadwax/interface_logs/recent', true])
  const beforeHistory = page.redraws()
  W.recents[0].resolve({ boot: 'A', last: 3, lines: [logLine(1, 'one'), logLine(2, 'two', { event_type: 'WARNING' }), logLine(3, 'three', { event_type: 'ERROR', src: 'SLSKD' })] })
  await settle()
  check('the history in: the page told to draw again (its lines are the module\'s: nothing else would)', page.redraws() > beforeHistory, true)
  page.draw()
  check('...then the stream, from its last number', W.sources.map((source) => source.url), ['/deadwax/interface_logs/interface_logs?after=3&boot=A'])
  check('the lines newest first', drawnLines(), ['three', 'two', 'one'])
  check('...errors red, warnings amber', classed('app-log-row').map((node) => node.props.class), ['app-log-row is-error', 'app-log-row is-warning', 'app-log-row is-info'])
  check('...each with its time, monospace, its level and where it came from', [/^\d\d:\d\d:\d\d$/.test(words(classed('app-log-time')[0])), classed('app-log-time')[0].props.class.includes('app-mono'), words(classed('app-log-level')[0]), words(classed('app-log-src')[0])],
    [true, true, 'ERROR', 'SLSKD'])
  const source = W.sources[0]
  source.onopen()
  page.draw()
  check('open: "Live"', words(classed('app-log-stream')[0]), 'Live')
  const beforeLines = page.redraws()
  source.send(logLine(3, 'three', { event_type: 'ERROR', src: 'SLSKD' }))
  source.send(logLine(4, 'four'))
  check('a line from the stream tells the page to draw again - as it comes, with nothing else drawing it', page.redraws() > beforeLines, true)
  source.send(logLine(4, 'four'))
  source.send(logLine(5, 'five'))
  page.draw()
  check('joined by number: the replay\'s line dropped, nothing twice, nothing missing', drawnLines(), ['five', 'four', 'three', 'two', 'one'])

  console.log('\nthe log: text, never markup')
  const markup = '<img src=x onerror="alert(1)"> re-filed <b>Third</b>'
  source.send(logLine(6, markup))
  page.draw()
  const shown = classed('app-log-words')[0]
  check('a line holding markup is its own words, as one text child', [shown.props.children, typeof shown.props.children], [markup, 'string'])
  check('...no element made of it, and nothing set as HTML anywhere on the page',
    [find((node) => node.type === 'img' || node.type === 'b').length, find((node) => 'dangerouslySetInnerHTML' in (node.props ?? {})).length], [0, 0])

  console.log('\nthe log: the lost stream is one line, never a column')
  source.onerror()
  source.onerror()
  source.onerror()
  page.draw()
  check('lost three times: one line above the log, and the log no longer for it', [classed('app-log-stream').length, words(classed('app-log-stream')[0]), drawnLines().length],
    [1, 'The stream was lost - trying again', 6])
  source.onopen()
  page.draw()
  check('...back: "Live" again', words(classed('app-log-stream')[0]), 'Live')

  console.log('\nthe log: the stream held only while the page shows')
  page.draw({ live: false })
  check('not showing (another page, the app behind, the visualizer over it): the stream closed', source.closed, true)
  page.draw({ live: true })
  check('back: the history asked again before a stream', [W.recents.length, W.sources.length], [2, 1])
  W.recents[1].resolve({ boot: 'A', last: 8, lines: [logLine(4, 'four'), logLine(5, 'five'), logLine(6, markup), logLine(7, 'while away'), logLine(8, 'and this')] })
  await settle()
  page.draw()
  check('...the lines logged while away joined, none twice; the stream from the new last number',
    [drawnLines().slice(0, 3), drawnLines().length, W.sources[1].url], [['and this', 'while away', markup], 8, '/deadwax/interface_logs/interface_logs?after=8&boot=A'])

  console.log('\nthe log: Clear, and a restart')
  button('Clear').props.onClick()
  page.draw()
  check('Clear empties the view only, and says it was cleared - not "Nothing logged yet."', [drawnLines().length, words(classed('app-log-empty')[0]), button('Clear').props['aria-disabled']],
    [0, 'Cleared. New lines show here as deadwax logs them.', 'true'])
  W.sources[1].send(logLine(8, 'and this'))
  W.sources[1].send(logLine(9, 'new'))
  page.draw()
  check('...a line it cleared, sent again, stays cleared; a new one shows', drawnLines(), ['new'])
  W.sources[1].send({ ...logLine(1, 'deadwax started again'), boot: 'B' })
  page.draw()
  check('deadwax restarted: its lines from 1 shown, on top', drawnLines(), ['deadwax started again', 'new'])
  page.draw({ live: false })
  page.draw({ live: true })
  W.recents[2].reject(new Error('HTTP 502'))
  await settle()
  page.draw()
  check('the history failing: said, and the stream opened from what the page has', [words(classed('app-log-problem')[0]), W.sources[2].url],
    ["deadwax couldn't send the lines it kept: HTTP 502", '/deadwax/interface_logs/interface_logs?after=1&boot=B'])
  page.unmount()
  check('...and left: the stream closed', W.sources[2].closed, true)

  {
    reset()
    const many = mount(EventLog)
    many.draw()
    W.recents[0].resolve({ boot: 'A', last: 0, lines: [] })
    await settle()
    many.draw()
    check('an empty history: "Nothing logged yet."', words(classed('app-log-empty')[0]), 'Nothing logged yet.')
    for (let n = 1; n <= 600; n++) W.sources[0].send(logLine(n, `line ${n}`))
    many.draw()
    check('at most 500 lines in the page, the oldest gone', [drawnLines().length, drawnLines()[0], drawnLines().at(-1)], [500, 'line 600', 'line 101'])
    many.draw({ live: false })
    check('...closed as it stops showing, before the history answered or after', W.sources[0].closed, true)
    many.draw({ live: true })
    many.draw({ live: false })
    W.recents[1].resolve({ boot: 'A', last: 600, lines: [] })
    await settle()
    many.draw()
    check('a history answering after the page stopped showing opens no stream', W.sources.length, 1)
  }

  console.log('\nthe log: a history that failed, filled in by the next')
  {
    reset()
    const gap = mount(EventLog)
    gap.draw()
    W.recents[0].reject(new Error('HTTP 504'))
    await settle()
    gap.draw()
    check('the history failing on a page that had nothing: the stream from now', W.sources[0].url, '/deadwax/interface_logs/interface_logs')
    for (let n = 101; n <= 110; n++) W.sources[0].send(logLine(n, `line ${n}`))
    gap.draw()
    gap.draw({ live: false })
    gap.draw({ live: true })
    W.recents[1].resolve({ boot: 'A', last: 110, lines: Array.from({ length: 110 }, (_, i) => logLine(i + 1, `line ${i + 1}`)) })
    await settle()
    gap.draw()
    check('...back, the history read: the lines kept from before the first one heard are there too, each once',
      [drawnLines().length, drawnLines()[0], drawnLines()[9], drawnLines()[10], drawnLines().at(-1), classed('app-log-problem').length],
      [110, 'line 110', 'line 101', 'line 100', 'line 1', 0])
    gap.unmount()
  }

  console.log('\nthe log: the lines outlive the page - left for a sibling, or Back')
  {
    reset()
    const first = mount(EventLog)
    first.draw()
    W.recents[0].resolve({ boot: 'A', last: 3, lines: [logLine(1, 'one'), logLine(2, 'two'), logLine(3, 'three')] })
    await settle()
    first.draw()
    W.sources[0].send(logLine(4, 'four'))
    first.draw()
    //? App draws only a tab's top page: the sidebar's Settings (which replaces it), Back - it goes
    first.unmount()
    const again = mount(EventLog)
    again.draw()
    check('back: the lines it had drawn at once, before the history answers', [drawnLines(), W.recents.length, W.sources.length], [['four', 'three', 'two', 'one'], 2, 1])
    const goneTold = first.redraws()
    W.recents[1].resolve({ boot: 'A', last: 6, lines: [logLine(3, 'three'), logLine(4, 'four'), logLine(5, 'while away'), logLine(6, 'and this')] })
    await settle()
    check('...the page left is told nothing more as lines come in (its listener let go)', first.redraws(), goneTold)
    again.draw()
    check('...the history joined by number - the lines logged while away, none twice; the stream from the new last number',
      [drawnLines(), W.sources[1].url], [['and this', 'while away', 'four', 'three', 'two', 'one'], '/deadwax/interface_logs/interface_logs?after=6&boot=A'])
    button('Clear').props.onClick()
    again.draw()
    again.unmount()
    const third = mount(EventLog)
    third.draw()
    check('Cleared and left: back, still "Cleared."', words(classed('app-log-empty')[0]), 'Cleared. New lines show here as deadwax logs them.')
    W.recents[2].resolve({ boot: 'A', last: 7, lines: [logLine(5, 'while away'), logLine(6, 'and this'), logLine(7, 'new')] })
    await settle()
    third.draw()
    check('...the lines it cleared don\'t come back from the history; a new one shows', drawnLines(), ['new'])
    third.unmount()
    reset()
    const gapped = mount(EventLog)
    gapped.draw()
    W.recents[0].reject(new Error('HTTP 504'))
    await settle()
    gapped.draw()
    for (let n = 41; n <= 42; n++) W.sources[0].send(logLine(n, `line ${n}`))
    gapped.unmount()
    const filled = mount(EventLog)
    filled.draw()
    W.recents[1].resolve({ boot: 'A', last: 42, lines: Array.from({ length: 42 }, (_, i) => logLine(i + 1, `line ${i + 1}`)) })
    await settle()
    filled.draw()
    check('a history that failed, the page left and come back to: the lines from before the first heard filled in, each once',
      [drawnLines().length, drawnLines()[0], drawnLines()[2], drawnLines().at(-1)], [42, 'line 42', 'line 40', 'line 1'])
    filled.unmount()
  }

  console.log('\nthe log: "trying again" kept true when the browser gives up on the stream')
  {
    reset()
    const timers = []
    const realSet = globalThis.setTimeout, realClear = globalThis.clearTimeout
    globalThis.setTimeout = (fn, ms) => { const timer = { fn, ms, cleared: false }; timers.push(timer); return timer }
    globalThis.clearTimeout = (timer) => { if (timer && typeof timer === 'object') timer.cleared = true; else realClear(timer) }
    try {
      const retry = mount(EventLog)
      retry.draw()
      W.recents[0].resolve({ boot: 'A', last: 2, lines: [logLine(1, 'one'), logLine(2, 'two')] })
      await settle()
      retry.draw()
      const first = W.sources[0]
      first.onopen()
      first.readyState = 0
      first.onerror()
      retry.draw()
      check('a network error: "trying again", left to EventSource (it tries again by itself)', [words(classed('app-log-stream')[0]), timers.length, first.closed], ['The stream was lost - trying again', 0, false])
      first.readyState = 1
      first.onopen()
      first.send(logLine(3, 'three'))
      //? an answer that isn't the stream - a proxy's 502 while deadwax restarts - ends it for good
      first.readyState = 2
      first.onerror()
      first.onerror()
      retry.draw()
      check('...the browser giving up (CLOSED): the line still says so, and the page asks again itself, once, after a pause',
        [words(classed('app-log-stream')[0]), timers.length, timers[0]?.ms, L.STREAM_RETRY_MS, first.closed], ['The stream was lost - trying again', 1, 5000, 5000, true])
      timers[0].fn()
      check('...the pause over: the history read again before a new stream', [W.recents.length, W.sources.length], [2, 1])
      W.recents[1].resolve({ boot: 'A', last: 5, lines: [logLine(3, 'three'), logLine(4, 'four'), logLine(5, 'five')] })
      await settle()
      retry.draw()
      check('...a new stream from where the page is, the lines logged meanwhile joined once', [W.sources[1].url, drawnLines()],
        ['/deadwax/interface_logs/interface_logs?after=5&boot=A', ['five', 'four', 'three', 'two', 'one']])
      W.sources[1].onopen()
      retry.draw()
      check('...open: "Live"', words(classed('app-log-stream')[0]), 'Live')
      W.sources[1].readyState = 2
      W.sources[1].onerror()
      retry.draw({ live: false })
      check('leaving with a retry waiting: it is called off', [timers.length, timers[1].cleared], [2, true])
      retry.unmount()
    } finally {
      globalThis.setTimeout = realSet
      globalThis.clearTimeout = realClear
    }
  }
}

settingsPage().then(logPage).then(() => {
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}, (error) => {
  console.error(error)
  process.exit(1)
})
