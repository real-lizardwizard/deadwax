#!/usr/bin/env node
/**
 * The iPhone app's Navidrome gate (app 0.2, Phase 1): what the web app's app/NeedsNavidrome.tsx draws - written as a
 * fixture the Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/NavidromeGate.swift) replays in
 * Tests/DeadwaxCoreTests/ScreenGateTests.swift, so the phone's Library says what the web's says when Navidrome isn't
 * set up or isn't answering, to each kind of reader.
 *
 * Compiles, as ui/test/errors.sim.cjs does, lib/errorWords.ts, app/NeedsNavidrome.tsx, app/access.ts and
 * lib/navidromeCheck.ts with the repo's TypeScript, and runs the gate AS IT IS against a stand-in for Preact: every
 * status (none yet, reached, not set up, set up and not answering, a status with no problem, the check failing with
 * deadwax unreached or answering an error) for every kind of reader (a listener, someone given Settings and the log,
 * a Navidrome admin, logins off), and what it draws - its heading, its lines, its buttons, its spinner, or what it
 * guards. And what navidromeChecks makes of a check that failed: deadwax not answering (fetch's TypeError) is
 * `offline`, an answer that is an error isn't. Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/gate/navidrome.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/iosgate.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a \u escape), so a run on any machine writes the
 * same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-gate-vectors.cjs           write the fixture
 *   node ios/scripts/export-gate-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'gate', 'navidrome.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-gate-vectors.cjs'
const SOURCES = ['app/NeedsNavidrome.tsx', 'app/access.ts', 'lib/errorWords.ts', 'lib/navidromeCheck.ts']

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-gate-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
exports.useState = (v) => [typeof v === 'function' ? v() : v, () => {}]
exports.useEffect = () => {}
exports.useCallback = (f) => f
exports.useMemo = (f) => f()
`)

const Gate = require(path.join(OUT, 'app/NeedsNavidrome.js'))
const Access = require(path.join(OUT, 'app/access.js'))
const NC = require(path.join(OUT, 'lib/navidromeCheck.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))

/* ===== the drawn tree (errors.sim's) ===== */

function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  return text(node.props?.children)
}
function find(test, node, hits = []) {
  if (!node || typeof node !== 'object') return hits
  if (Array.isArray(node)) { node.forEach((one) => find(test, one, hits)); return hits }
  if (test(node)) hits.push(node)
  find(test, node.props?.children, hits)
  return hits
}

const GUARDED = 'GUARDED'
/** What the gate draws for `status`: what it guards, its spinner, or why not - its heading, lines and buttons. */
function drawn(status) {
  const tree = Gate.NeedsNavidrome({ status, onRetry() {}, children: GUARDED })
  if (tree?.type === 'fragment' && tree.props.children === GUARDED) return 'open'
  if (find((n) => n.props?.class === 'pl-spinner', tree).length) {
    return { spinner: find((n) => n.props?.class === 'pl-spinner', tree)[0].props['aria-label'] }
  }
  return {
    title: text(find((n) => n.props?.class === 'app-needs-title', tree)[0]),
    lines: find((n) => n.props?.class === 'app-needs-text', tree).map(text),
    buttons: find((n) => n.type === 'button', tree).map(text),
  }
}

/* ===== the cases ===== */

const NOT_CONFIGURED = "Navidrome isn't set up - fill in NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASSWORD in Server settings (Connections)"
const STATUSES = {
  none: null,
  reached: { configured: true, ok: true, server: 'Navidrome 0.64.2', problem: null },
  unset: { configured: false, ok: false, server: null, problem: NOT_CONFIGURED },
  down: { configured: true, ok: false, server: null, problem: "Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed" },
  quiet: { configured: true, ok: false, server: null, problem: null },
  unsetQuiet: { configured: false, ok: false, server: null, problem: null },
  offline: { configured: true, ok: false, server: null, problem: 'TypeError: Failed to fetch', offline: true },
}
const READERS = {
  listener: { user: 'ethan', admin: false, auth: 'on', permissions: ['request'] },
  settings: { user: 'sam', admin: false, auth: 'on', permissions: ['request', 'server'] },
  admin: { user: 'james', admin: true, auth: 'on' },
  breakGlass: { user: 'deadwax', admin: true, auth: 'on' },
  off: { user: 'local', admin: true, auth: 'off' },
}

/** What navidromeChecks makes of a check that failed with `reason`: the status it draws by. */
async function failed(reason) {
  let status = null
  const asks = NC.navidromeChecks(() => Promise.reject(reason), (next) => { status = next(status) })
  asks.check()
  await new Promise((resolve) => setTimeout(resolve, 0))
  return { configured: status.configured, ok: status.ok, server: status.server, offline: status.offline === true }
}

/* ===== output: plain ASCII ===== */

const BACKSLASH = String.fromCharCode(92)
function ascii(json) {
  let out = ''
  for (let i = 0; i < json.length; i++) {
    const unit = json.charCodeAt(i)
    out += unit < 0x7f ? json[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return out
}
const sha256 = (body) => crypto.createHash('sha256').update(body).digest('hex')

async function main() {
  const cases = []
  for (const [reader, me] of Object.entries(READERS)) {
    Access.noteAccess(me)
    for (const [name, status] of Object.entries(STATUSES)) {
      cases.push({ reader, me, status: name, drawn: drawn(status) })
    }
  }
  Access.forgetAccess()

  const checks = {
    deadwaxUnreached: await failed(new TypeError('Failed to fetch')),
    navidromeRefused: await failed(new ApiError(502, "Navidrome couldn't be reached", 'GET /navidrome/status failed', false, null, null, '/navidrome/status')),
    timedOut: await failed(Object.assign(new Error('The operation timed out.'), { name: 'TimeoutError' })),
  }
  fs.rmSync(OUT, { recursive: true, force: true })

  const fixture = {
    made_by: MADE_BY,
    made_from: Object.fromEntries(SOURCES.map((file) => [`ui/src/${file}`, sha256(fs.readFileSync(path.join(UI, 'src', file), 'utf8'))])),
    statuses: STATUSES,
    words: {
      MUSIC_UNAVAILABLE: Gate.MUSIC_UNAVAILABLE,
      MUSIC_NOT_YET: Gate.MUSIC_NOT_YET,
      MUSIC_UNREACHED: Gate.MUSIC_UNREACHED,
      DEADWAX_UNREACHED: Gate.DEADWAX_UNREACHED,
      MUSIC_UNSET: Gate.MUSIC_UNSET,
      ADMIN_SETS_UP: Gate.ADMIN_SETS_UP,
      NAVIDROME_REQUIRED: Gate.NAVIDROME_REQUIRED,
      NAVIDROME_UNREACHED: Gate.NAVIDROME_UNREACHED,
    },
    checks,
    cases,
  }
  const body = '{\n' + Object.entries(fixture).map(([key, value]) => {
    if (key === 'cases' || key === 'statuses' || key === 'words' || key === 'checks' || key === 'made_from') {
      const inner = Array.isArray(value)
        ? '[\n' + value.map((one) => '    ' + ascii(JSON.stringify(one))).join(',\n') + '\n  ]'
        : '{\n' + Object.entries(value).map(([k, v]) => '    ' + ascii(JSON.stringify(k)) + ': ' + ascii(JSON.stringify(v))).join(',\n') + '\n  }'
      return `  ${JSON.stringify(key)}: ${inner}`
    }
    return `  ${JSON.stringify(key)}: ${ascii(JSON.stringify(value))}`
  }).join(',\n') + '\n}\n'

  if (CHECK) {
    if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
      console.log(`The Navidrome gate's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
      console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
      process.exit(1)
    }
    console.log(`The Navidrome gate's fixture matches the web app's TypeScript (${cases.length} cases).`)
    return
  }
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${cases.length} cases, ${Math.round(body.length / 1024)} KB`)
}

main().catch((caught) => {
  console.error(caught && caught.stack)
  process.exit(1)
})
