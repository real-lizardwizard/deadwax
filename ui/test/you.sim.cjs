/**
 * The app's You tab (app/You.tsx, 2.0.0-player.9), the component itself, compiled with the repo's
 * TypeScript and rendered by a small stand-in for Preact into plain objects, with deadwax's
 * answers faked.
 *
 * What it pins:
 *
 *  - Nothing is asked until You first shows (the MusicBrainz ping is a real request to a
 *    rate-limited service), then the pings and /deadwax/me together.
 *  - "Check again" asks /deadwax/me again, not only the pings. deadwax restarting under Komodo
 *    while You first opened used to leave Version and Logins at "unknown" until the app was
 *    killed - the latch CLAUDE.md warns about. A failure clears as the new ask begins; a failed
 *    ask after a good one keeps the version, and says it failed.
 *  - The identity line says only what deadwax has said: not "Logins are off" when it hasn't
 *    answered.
 *  - Each connection row is a live region of its own, read whole, so VoiceOver hears "slskd,
 *    NOT_LOGGED_IN", not a bare word with no service - and the list itself is not one.
 *  - The link to the main page opens beside the app.
 *  - Playback holds Gapless and then Maximum quality (2.0.0-player.10): Gapless is handed the
 *    player itself - the object whose setGapless its tap calls - and the notes say where the
 *    settings are kept and when each applies, with no pointer to the now-playing screen.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/you.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-you-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/You.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - the same stand-in as
//? settings.sim.cjs. Effects run after a render whose deps changed.
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

/* ===== deadwax, faked: each answer is what the test says next ===== */

const asked = { me: 0, musicbrainz: 0, slskd: 0, navidrome: 0 }
const meAnswers = []
fs.writeFileSync(path.join(OUT, 'api/me.js'), `
exports.me = () => globalThis.__you.me()
`)
fs.writeFileSync(path.join(OUT, 'api/connections.js'), `
exports.pingMusicBrainz = () => globalThis.__you.ping('musicbrainz')
exports.pingSlskd = () => globalThis.__you.ping('slskd')
`)
fs.writeFileSync(path.join(OUT, 'player/api.js'), `
exports.navidromeStatus = () => globalThis.__you.ping('navidrome')
`)
fs.writeFileSync(path.join(OUT, 'app/context.js'), `
exports.usePlayerState = () => globalThis.__you.player
exports.usePlayerActions = () => ({ setMaxRate() {} })
`)
const ANSWERS = {
  musicbrainz: { status: 'ok' },
  slskd: { status: 'failed', code: 'NOT_LOGGED_IN', error: 'slskd is not logged in to Soulseek' },
  navidrome: { configured: true, ok: true, server: 'Navidrome 0.64.2', problem: null },
}
globalThis.__you = {
  player: { maxRate: '48000', gapless: false, setGapless() {} },
  me() {
    asked.me += 1
    const next = meAnswers.shift()
    return next ? next() : new Promise(() => {})
  },
  ping(service) {
    asked[service] += 1
    return Promise.resolve(ANSWERS[service])
  },
}
const ME = { user: 'local', admin: true, auth: 'off', version: '2.0.0-player.9' }
const answersWith = (value) => () => Promise.resolve(value)
const failsWith = (words) => () => Promise.reject(new Error(words))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== rendering ===== */

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { You } = require(path.join(OUT, 'app/You.js'))

const render = hooks.root(You)
let tree = null
const draw = (props) => {
  tree = render(props)
  render.commit()
  return tree
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

//? every node of the tree drawn last that passes `test` (no default for the node: an undefined
//? child would take it, and walk the whole tree again)
function find(test) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(tree)
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
//? About's rows, as label -> value: each a <div class="app-row"> holding a <dt> and a <dd>
const about = () => Object.fromEntries(find((node) => node.type === 'div' && node.props?.class === 'app-row')
  .map((row) => [text(row.props.children[0]), text(row.props.children[1])]))
const identity = () => find(byClass('app-identity-sub')).map(text)
const failure = () => find(byClass('app-error')).map(text)
const checkAgain = () => find((node) => node.type === 'button' && text(node) === 'Check again')[0]

async function main() {
  console.log('\nnothing is asked until You first shows')
  draw({ shown: false })
  await settle()
  check('hidden, never opened: no ping, no /me', asked, { me: 0, musicbrainz: 0, slskd: 0, navidrome: 0 })

  console.log('\n/deadwax/me asked with the pings, and asked again')
  meAnswers.push(failsWith('deadwax is restarting'))
  draw({ shown: true })
  check('shown: /me and the three pings, once each', asked, { me: 1, musicbrainz: 1, slskd: 1, navidrome: 1 })
  await settle()
  draw({ shown: true })
  check('/me failed: the version and logins say they are not known', about(), { Version: 'unknown', Logins: 'unknown' })
  check('...the failure is said', failure(), ["deadwax didn't answer: deadwax is restarting"])
  check('...and the identity line claims nothing', identity(), [])
  check('drawn again, nothing is asked again by itself', asked.me, 1)

  meAnswers.push(answersWith(ME))
  checkAgain().props.onClick()
  check('"Check again" asks /me again, with the pings', asked, { me: 2, musicbrainz: 2, slskd: 2, navidrome: 2 })
  draw({ shown: true })
  check('...the old failure cleared as the ask begins', [failure(), about().Version], [[], '…'])
  await settle()
  draw({ shown: true })
  check('deadwax back: the version and logins, and nothing failed', [about(), failure()], [{ Version: '2.0.0-player.9', Logins: 'Off' }, []])
  check('...and the identity line says what deadwax said', identity(), ['Logins are off'])

  meAnswers.push(failsWith('no answer'))
  checkAgain().props.onClick()
  await settle()
  draw({ shown: true })
  check('a failed ask after a good one keeps the version, and says it failed', [about().Version, failure()], ['2.0.0-player.9', ["deadwax didn't answer: no answer"]])

  console.log('\neach connection row is read whole')
  const list = find((node) => node.type === 'ul' && byClass('app-group')(node))[0]
  const rows = find((node) => node.type === 'li' && byClass('app-status-row')(node))
  check('the list itself is no live region', list?.props['aria-live'] ?? null, null)
  check('every row is one, polite and atomic', rows.map((row) => [row.props['aria-live'], row.props['aria-atomic']]), [['polite', 'true'], ['polite', 'true'], ['polite', 'true']])
  check('...holding its service with its answer', rows.map(text), [
    'MusicBrainzConnected',
    'slskdNOT_LOGGED_INslskd is not logged in to Soulseek',
    'NavidromeNavidrome 0.64.2',
  ])

  console.log('\nPlayback: Gapless, then Maximum quality')
  const named = (name) => find((node) => typeof node.type === 'function' && node.type.name === name)
  const playback = find((node) => node.type === 'section' && node.props?.['aria-labelledby'] === 'app-playback-title')[0]
  const inPlayback = []
  const notes = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (typeof node.type === 'function') inPlayback.push(node.type.name)
    if (node.type === 'p' && byClass('app-footnote')(node)) notes.push(text(node))
    visit(node.props?.children)
  }
  visit(playback)
  check('both in the Playback section, Gapless first', inPlayback, ['GaplessChoice', 'QualityChoice'])
  check('Gapless is handed the player itself', named('GaplessChoice')[0]?.props.player === globalThis.__you.player, true)
  check('the notes: what Gapless does, and where both are kept', notes, [
    'An experiment: it shortens the pause between songs, and FLAC songs played one after another can join in one stream, with none at all.',
    'Both are kept on this device. Maximum quality is used from the next song.',
  ])
  check('...the first is what the checkbox is described by', find((node) => node.props?.id === 'app-gapless-note').map(text).length, 1)

  console.log('\nthe main page opens beside the app')
  const link = find((node) => node.type === 'a')[0]
  check('the Managing row links to / in a new tab, rel="noopener"', [link?.props.href, link?.props.target, link?.props.rel], ['/', '_blank', 'noopener'])

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main()
