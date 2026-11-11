#!/usr/bin/env node
/**
 * The iPhone app's screens' own rules (app 0.2, Phase 1): what the web app's TypeScript answers, written as fixtures
 * the Swift ports in ios/DeadwaxKit/Sources/DeadwaxCore replay (Tests/DeadwaxCoreTests/Screen*.swift) - so the
 * phone's sign-in, album page, queue menu, mini player and Now Playing decide exactly as the web's do, and draw only.
 *
 * Compiles, as the sims do, ui/src/lib/signIn.ts, lib/whose.ts, lib/discTitles.ts, lib/format.ts, lib/scrub.ts,
 * lib/titles.ts, lib/playQueue.ts, lib/upNext.ts, lib/loudness.ts and api/http.ts, and the components whose rules live
 * in them - app/SignIn.tsx, app/SignOutRow.tsx, app/QueueMenu.tsx, player/MiniPlayer.tsx, player/levelling.ts - which
 * run AS THEY ARE against stand-ins for Preact, the network, the device's setting and the player (as signin.sim.cjs,
 * info.sim.cjs and app-rules.sim.cjs stand them in). Lines that live inside a big component (AlbumPage.tsx's footer,
 * meta line and rows, NowPlaying.tsx's byline and clocks, signInGate.tsx's launch) are read out of its source by a
 * pattern and evaluated as written; a pattern that no longer matches stops this script, naming what moved. Writes,
 * under ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/screens/:
 *
 *   signin.json  the sign-in screen driven step by step (typing, Sign in, deadwax's answer) and what it draws after
 *                each; the gate's launch reason; which 401 ends a session (api/http.ts); Sign out driven
 *   whose.json   albumMine over every combination of its inputs, whose.sim's cases by name, heldPhrase/heldLabel,
 *                the six words and the mine block's button words
 *   discs.json   discs.sim's cases by name and seeded random albums: the headings and the title map
 *   format.json  trackTime, formatDuration, clock and sharedFormat over awkward numbers and suffixes; the album
 *                page's meta line, footer, rows, long title and warm
 *   scrub.json   scrub.sim's checks by name; seeded drags, seeks on their way, and seek readings step by step
 *   player.json  miniPlayerLabel and the mini player's line drawn; afterFailure over its inputs; Now Playing's
 *                byline, Go to album and clocks; the constants
 *   queue.json   the song menu (QueueMenu.tsx) driven: which call, each song's level under each setting, the notice;
 *                its words, and the album page's two picks
 *
 * Each file names the sources it was made from with their sha256 (a whole file, or for a line read out of a big
 * component, that line), so ui/test/iosscreens.sim.cjs - which runs this with --check - fails when one changes, in
 * what it does or only in its text, until the fixtures are written again and the Swift ports follow.
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any
 * machine writes the same bytes. Numbers JSON can't hold are written as strings: "NaN", "Infinity", "-Infinity",
 * "-0". Never edit a fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-screen-vectors.cjs           write the fixtures
 *   node ios/scripts/export-screen-vectors.cjs --check   write nothing; exit 1 when a fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURES = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'screens')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-screen-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/signIn.ts', 'src/lib/whose.ts', 'src/lib/discTitles.ts', 'src/lib/format.ts', 'src/lib/scrub.ts', 'src/lib/titles.ts',
  'src/lib/playQueue.ts', 'src/lib/upNext.ts', 'src/lib/loudness.ts', 'src/api/http.ts',
  'src/app/SignIn.tsx', 'src/app/SignOutRow.tsx', 'src/app/QueueMenu.tsx', 'src/player/MiniPlayer.tsx', 'src/player/levelling.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

/* ===== the stand-ins (signin.sim.cjs's Preact; the network, the setting and the player as each step says) ===== */

const write = (file, body) => {
  fs.mkdirSync(path.dirname(path.join(OUT, file)), { recursive: true })
  fs.writeFileSync(path.join(OUT, file), body)
}
write('node_modules/preact/jsx-runtime.js', [
  'exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })',
  "exports.Fragment = 'fragment'",
  '',
].join('\n'))
write('node_modules/preact/index.js', "exports.Fragment = 'fragment'\nexports.render = () => {}\n")
write('node_modules/preact/hooks.js', `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useCallback = (f) => f
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useContext = () => null
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
write('api/auth.js', [
  'exports.signIn = (name, secret) => globalThis.__screens.signIn(name, secret)',
  'exports.signOut = () => globalThis.__screens.signOut()',
  '',
].join('\n'))
write('player/api.js', [
  'exports.rememberAdded = (albums) => { globalThis.__screens.remembered.push(albums.map((album) => album.id)) }',
  'exports.warmLevels = (id) => { globalThis.__screens.warmed.push(id) }',
  '',
].join('\n'))
write('app/usePins.js', 'exports.sayPins = (words) => { globalThis.__screens.said.push(words) }\n')
write('app/useSheet.js', 'exports.useSheet = () => {}\n')
write('state/persisted.js', 'exports.readPlayerNormalization = () => globalThis.__screens.setting\n')
write('player/Cover.js', 'exports.Cover = function Cover() { return null }\n')
write('player/icons.js', 'exports.NextIcon = exports.PauseIcon = exports.PlayIcon = function Icon() { return null }\n')
write('player/usePlayer.js', 'exports.usePosition = () => globalThis.__screens.position\n')

const G = (globalThis.__screens = { remembered: [], warmed: [], said: [], setting: 'auto', position: 0 })
const load = (file) => require(path.join(OUT, file))
const hooks = load('node_modules/preact/hooks.js')
const S = load('lib/signIn.js'), W = load('lib/whose.js'), D = load('lib/discTitles.js'), F = load('lib/format.js')
const SC = load('lib/scrub.js'), T = load('lib/titles.js'), Q = load('lib/playQueue.js'), U = load('lib/upNext.js')
const L = load('lib/loudness.js'), H = load('api/http.js'), LV = load('player/levelling.js')
const { SignIn } = load('app/SignIn.js')
const { SignOutRow } = load('app/SignOutRow.js')
const { QueueMenu } = load('app/QueueMenu.js')
const { MiniPlayer, miniPlayerLabel } = load('player/MiniPlayer.js')
const { ApiError } = H

/* ===== the sources, and lines read out of them ===== */

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex')
const source = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
/** A whole source, by its hash. */
const whole = (file) => [`ui/src/${file}`, sha256(source(file))]
/** A line (or a few) read out of a big source by `pattern`: its match, hashed - the script stops when it is gone. */
function lines(file, pattern, what) {
  const found = pattern.exec(source(file))
  if (!found) throw new Error(`couldn't read ${what} out of ui/src/${file} - the web app's code moved; change this script with it`)
  return { found, from: [`ui/src/${file} ${what}`, sha256(found[0])] }
}
/** An expression read out of a source, as a function of the names it uses. */
const expression = (text, ...names) => new Function(...names, `return (${text})`)

/* ===== output: plain ASCII ===== */

const BACKSLASH = String.fromCharCode(92)
function ascii(text) {
  let out = ''
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i)
    out += unit < 0x7f ? text[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return out
}
const flat = (value) => ascii(JSON.stringify(value))
const primitive = (value) => value === null || typeof value !== 'object'
//? objects and arrays laid out to `depth` levels, one member a line; deeper, and arrays of plain values, on one line
function laid(value, depth, indent = '') {
  if (primitive(value) || depth === 0 || (Array.isArray(value) && value.every(primitive))) return flat(value)
  const inner = indent + '  '
  if (Array.isArray(value)) {
    if (!value.length) return '[]'
    return '[\n' + value.map((item) => inner + laid(item, depth - 1, inner)).join(',\n') + '\n' + indent + ']'
  }
  const keys = Object.keys(value)
  if (!keys.length) return '{}'
  return '{\n' + keys.map((key) => inner + flat(key) + ': ' + laid(value[key], depth - 1, inner)).join(',\n') + '\n' + indent + '}'
}
const files = {}
const emit = (name, value, depth) => {
  files[name] = laid(value, depth) + '\n'
}
const MADE_BY = 'ios/scripts/export-screen-vectors.cjs - never edit by hand: change the TypeScript and run it again'

/** A number as the fixtures hold it: JSON's own, or a string for what JSON can't say. */
function num(value) {
  if (value === undefined || value === null) return null
  if (Number.isNaN(value)) return 'NaN'
  if (value === Infinity) return 'Infinity'
  if (value === -Infinity) return '-Infinity'
  if (Object.is(value, -0)) return '-0'
  return value
}

/* ===== seeded randomness ===== */

const seeded = (start) => {
  let state = start
  return () => (state = (state * 1103515245 + 12345) % 2147483648) / 2147483648
}
const ch = (...codes) => String.fromCharCode(...codes)
const NBSP = ch(0xa0), VT = ch(0x0b), BOM = ch(0xfeff), NEL = ch(0x85), IDEO = ch(0x3000), ELLIPSIS = ch(0x2026)
const E_ACUTE = ch(0xe9), E_COMBINING = 'e' + ch(0x301), DOT = ch(0xb7), EMDASH = ch(0x2014), SHARP_S = ch(0xdf)

/* ===== text and finding, in a drawn tree (signin.sim's) ===== */

function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return text(node.props?.children)
}
function find(tree, test) {
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
const byClass = (cls) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(cls)
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

/* ===== errors, made as the web makes them ===== */

/** An error as a fixture says it: deadwax's answer (`status` ...), no answer (`offline`), no answer in time
 *  (`timeout`) - each as api/http.ts and fetch make them. */
function made(spec, route = '/auth/login', method = 'POST') {
  if ('offline' in spec) return new TypeError(spec.offline)
  if ('timeout' in spec) return Object.assign(new Error(spec.timeout), { name: 'TimeoutError' })
  if ('other' in spec) return new Error(spec.other)
  return new ApiError(spec.status, spec.detail ?? null, `${method} ${route} failed`, spec.busy === true, spec.kind ?? null, spec.why ?? null,
    spec.path ?? route)
}

const SIGN_IN_FORM = "deadwax couldn't read that sign-in - a user name is at most 200 characters and a password at most 1000. Check what you typed and try again."
const NOKEY = "deadwax isn't ready for signing in, so nobody can use it just now."
const NOKEY_WHY = "Logins are on, but DEADWAX_SECRET_KEY isn't set, so deadwax can't sign anyone in."
const DB_DOWN = "deadwax can't read its database just now, so it can't check who you are."
const DB_WHY = "deadwax can't read its database, so nothing is let in until it can. Check DB_PATH points at a writable volume."
const ANSWERS = [
  { status: 401, detail: "That user name and password didn't work." },
  { status: 401 },
  { status: 429, detail: 'Too many tries for ethan - wait 42 seconds and try again. deadwax holds off so Navidrome doesn\'t lock the account.' },
  { status: 429 },
  { status: 503, detail: NOKEY, why: NOKEY_WHY },
  { status: 503, detail: DB_DOWN, why: DB_WHY },
  { status: 503, detail: "Navidrome isn't answering, so deadwax can't check your password right now - try again in a moment." },
  { status: 503, detail: 'deadwax broke', why: 'NAVIDROME_URL is unset' },
  { status: 503, why: 'only a why' },
  { status: 502, detail: 'Navidrome couldn\'t check your password just now - try again in a moment.', why: 'Navidrome said: database is locked' },
  { status: 502, detail: 'Navidrome said: database is locked (NAVIDROME_URL)' },
  { status: 500 },
  { status: 500, detail: '' },
  { status: 422, detail: SIGN_IN_FORM },
  { status: 400, detail: 'Type your user name and your password.' },
  { status: 400, detail: "'local' is a name deadwax keeps for itself - nobody signs in as it." },
  { status: 409, detail: "Logins are off, so there's nothing to sign in to: deadwax lets everyone in." },
  { status: 418, detail: 'Errno 111 Connection refused' },
  { offline: 'Failed to fetch' },
  { timeout: 'The operation timed out.' },
]
const ME = (user, admin = false) => ({ me: { user, admin, auth: 'on', version: '2.1.0' } })

/* ===================================================================================== signin.json */

function signInTraces() {
  const traces = []
  /** One trace: the screen drawn with `reason` and `reasonWhy`, then each step - and what it draws after each. */
  async function run(name, reason, reasonWhy, steps, seededRun = false) {
    const pending = []
    const sent = []
    G.signIn = (username, password) => {
      sent.push([username, password])
      return new Promise((resolve, reject) => pending.push({ resolve, reject }))
    }
    const signedIn = []
    const draw = hooks.root(SignIn)
    const props = { reason, reasonWhy, onSignedIn: (me) => signedIn.push(me.user) }
    let tree = null
    const redraw = () => { tree = draw(props); draw.commit(); return tree }
    redraw()
    const field = (id) => find(tree, (node) => node.type === 'input' && node.props.id === id)[0]
    const drawn = () => {
      const form = find(tree, (node) => node.type === 'form')[0]
      const parts = [].concat(form.props.children).flat()
      //? the reason's fold comes before the fields, the problem's after the problem's region
      const folds = []
      let pastFields = false
      for (const part of parts) {
        if (part && typeof part === 'object' && part.type === 'label') pastFields = true
        if (part && typeof part === 'object' && typeof part.type === 'function' && part.type.name === 'ForWhoever') folds.push([pastFields, part.props.why])
      }
      const reasonLine = find(tree, byClass('app-signin-reason')).map(text)
      const problem = find(find(tree, byClass('app-signin-problem'))[0], byClass('app-error')).map(text)
      const button = find(tree, byClass('app-signin-submit'))[0]
      return {
        reason: reasonLine.length ? reasonLine[0] : null,
        reasonWhy: folds.filter(([after]) => !after).map(([, why]) => why)[0] ?? null,
        problem: problem.length ? problem[0] : null,
        problemWhy: folds.filter(([after]) => after).map(([, why]) => why)[0] ?? null,
        button: text(button),
        disabled: button.props.disabled === true,
        describedBy: tree.props['aria-describedby'] ?? null,
        username: field('app-signin-user').props.value,
        password: field('app-signin-password').props.value,
      }
    }
    const out = []
    for (const step of steps) {
      const before = sent.length
      if (step.op === 'type') {
        field(step.field === 'username' ? 'app-signin-user' : 'app-signin-password').props.onInput({ currentTarget: { value: step.value } })
        redraw()
      } else if (step.op === 'submit') {
        const form = find(tree, (node) => node.type === 'form')[0]
        //? the fields read as the browser holds them - here, what was typed
        const values = { username: field('app-signin-user').props.value, password: field('app-signin-password').props.value }
        form.props.onSubmit({ preventDefault() {}, currentTarget: { elements: { namedItem: (name) => ({ value: values[name] }) } } })
        redraw()
      } else if (step.op === 'answer') {
        const waiting = pending.shift()
        //? a seeded run's answer with no sign-in on its way is left out of its trace; a fixed one's is this script's mistake
        if (!waiting && seededRun) continue
        if (!waiting) throw new Error(`${name}: an answer with no sign-in on its way, after ${JSON.stringify(out.map((o) => [o.step, o.sent, o.drawn.problem]))}`)
        if (step.answer.me) waiting.resolve(step.answer.me)
        else waiting.reject(made(step.answer))
        await settle()
        redraw()
      }
      out.push({ step, sent: sent.length > before ? sent[sent.length - 1] : null, signedIn: signedIn.length, drawn: drawn() })
    }
    traces.push({ name, reason, reasonWhy, steps: out })
  }
  const type = (field, value) => ({ op: 'type', field, value })
  const submit = { op: 'submit' }
  const answer = (spec) => ({ op: 'answer', answer: spec })
  const fixed = [
    ['empty fields said, and nothing sent', 'Navidrome no longer accepts the login you signed in with.', null, [submit, type('username', 'ethan'), submit, type('password', 'x'), type('username', ''), submit]],
    ['the name trimmed, the password as typed', null, null, [type('username', ' Ethan '), type('password', ' the-password '), submit, answer(ANSWERS[0])]],
    ['a name of spaces is no name', null, null, [type('username', '   '), type('password', 'pw'), submit, type('username', NBSP + VT + BOM + IDEO), submit,
      type('username', NEL + 'ethan' + NEL), submit, answer(ME('ethan'))]],
    ['a password of spaces is a password', null, null, [type('username', 'ethan'), type('password', '   '), submit, answer(ANSWERS[0])]],
    ['busy: a second Sign in sends nothing', null, null, [type('username', 'ethan'), type('password', 'pw'), submit, submit, answer(ANSWERS[2]), submit]],
    ['a wrong password in deadwax\'s words, the password gone', 'Navidrome no longer accepts the login you signed in with.', null,
      [type('username', 'ethan'), type('password', 'the-password'), submit, answer(ANSWERS[0])]],
    ['nobody can sign in: the sentence, to tell whoever runs deadwax, DB_PATH folded', null, null,
      [type('username', 'ethan'), type('password', 'pw'), submit, answer(ANSWERS[5])]],
    ['too many tries, and how long to wait', null, null, [type('username', 'ethan'), type('password', 'again'), submit, answer(ANSWERS[2])]],
    ['signed in: handed on, the failure cleared', null, null, [type('username', 'ethan'), type('password', 'wrong'), submit, answer(ANSWERS[0]),
      type('password', 'right-one'), submit, answer(ME('ethan'))]],
    ['the screen up with no key: the reason and its fold; a sign-in answered the same: said once', `${NOKEY} Tell whoever runs deadwax.`, NOKEY_WHY,
      [type('username', 'ethan'), type('password', 'x'), submit, answer(ANSWERS[4])]],
    ['the plain "sign in" isn\'t said above the form, nor describes the dialog', 'Sign in to use deadwax.', 'a why that is never shown', [submit]],
    ['a reason with nothing folded under it when its why is empty', ' Your account was removed. ', '', [submit]],
    ['no answer at all', null, null, [type('username', 'ethan'), type('password', 'pw'), submit, answer(ANSWERS[18]), submit, type('password', 'pw'), submit,
      answer(ANSWERS[19])]],
  ]
  return (async () => {
    for (const [name, reason, why, steps] of fixed) await run(name, reason, why, steps)
    //? seeded runs: every answer, reasons that are and aren't shown, and the problem the same as the reason
    const rand = seeded(20261110)
    const pick = (list) => list[Math.floor(rand() * list.length)]
    const NAMES = ['', ' ', 'ethan', ' Ethan ', NBSP + 'x' + NBSP, 'deadwax', 'Bj' + E_ACUTE + 'rk', VT, 'a b']
    const SECRETS = ['', ' ', 'pw', 'the-password', ELLIPSIS]
    const REASONS = [null, '', 'Sign in to use deadwax.', ' Sign in to use deadwax. ', 'You\'ve been signed out - sign in again.',
      `${NOKEY} Tell whoever runs deadwax.`, "That user name and password didn't work.", 'Too many tries - wait a minute and try again.',
      "Can't reach deadwax. Check you're on the right network (or your VPN is on) and try again.", BOM + 'Your account was removed.' + IDEO]
    const WHYS = [null, '', NOKEY_WHY, 'Navidrome said: no']
    for (let run_ = 0; run_ < 60; run_++) {
      const steps = []
      //? answers fall anywhere; one with no sign-in on its way is left out of the trace (run, above)
      for (let i = 0; i < 14; i++) {
        const roll = rand()
        if (roll < 0.3) steps.push(answer(rand() < 0.15 ? ME(pick(['ethan', 'james'])) : pick(ANSWERS)))
        else if (roll < 0.65) steps.push(type(rand() < 0.5 ? 'username' : 'password', rand() < 0.5 ? pick(NAMES) : pick(SECRETS)))
        else steps.push(submit)
      }
      await run(`seeded ${run_}`, pick(REASONS), pick(WHYS), steps, true)
    }
    return traces
  })()
}

/** The gate's launch (signInGate.tsx): /me failed - a 401 says its words, anything else what kind it was. */
function launchCases() {
  const { found, from } = lines('app/signInGate.tsx',
    /if \(error instanceof ApiError && error\.status === 401\) showSignIn\(error\.detail\)\s*else showSignIn\(signInProblem\(error\), signInWhy\(error\)\)/,
    'the launch reason')
  const gate = new Function('error', 'ApiError', 'showSignIn', 'signInProblem', 'signInWhy', found[0])
  const specs = [
    { status: 401, detail: 'Sign in to use deadwax.' }, { status: 401, detail: "You've been signed out - sign in again." }, { status: 401 },
    { status: 401, detail: 'Your sign-in ran out after 30 days without use - sign in again.', why: 'a why a 401 never shows' },
    ...ANSWERS.filter((spec) => spec.status !== 401),
  ]
  const cases = specs.map((spec) => {
    let shown = null
    gate(made(spec, '/me', 'GET'), ApiError, (reason, why = null) => { shown = { reason, why } }, S.signInProblem, S.signInWhy)
    return { error: spec, ...shown }
  })
  return { cases, from }
}

/** Which 401 ends the session the page holds (api/http.ts noteSignedOut), heard as the page hears it. */
async function sessionCases() {
  const { from } = lines('api/http.ts', /function noteSignedOut\([\s\S]*?\n\}/, 'noteSignedOut')
  const target = new EventTarget()
  globalThis.addEventListener = target.addEventListener.bind(target)
  globalThis.dispatchEvent = target.dispatchEvent.bind(target)
  const heard = []
  target.addEventListener(H.SIGNED_OUT, (event) => heard.push(event.detail))
  const cases = []
  const PATHS = ['/me', '/navidrome/albums', '/navidrome/scrobble/so-1?submission=true', '/auth/login', '/auth/logout', '/auth', '/authors', '/me/library/add']
  const STATUSES = [401, 403, 404, 500, 503]
  const DETAILS = [null, "You've been signed out - sign in again.", '']
  let n = 0
  for (const route of PATHS) {
    for (const status of STATUSES) {
      for (const signedInSince of [false, true]) {
        const detail = DETAILS[n++ % DETAILS.length]
        let release = () => {}
        const held = new Promise((resolve) => { release = resolve })
        globalThis.fetch = async () => { await held; return { ok: status < 400, status, json: async () => (detail === null ? {} : { detail }) } }
        const asked = H.get(route).catch(() => {})
        if (signedInSince) H.newSession()
        heard.length = 0
        release()
        await asked
        cases.push({ path: route, status, detail, signedInSince, ends: heard.length > 0, said: heard.length ? heard[0] : null })
      }
    }
  }
  delete globalThis.fetch
  return { cases, from }
}

/** You's Sign out (SignOutRow.tsx), driven. */
async function signOutTraces() {
  const traces = []
  let reloads = 0
  globalThis.location = { reload: () => { reloads += 1 } }
  const footnote = (user) => text(find(hooks.root(SignOutRow)({ user }), byClass('app-footnote')).at(-1))
  const USERS = ['ethan', 'deadwax', 'admin', 'Deadwax', 'deadwax ', '', 'Bj' + E_ACUTE + 'rk']
  const footnotes = USERS.map((user) => ({ user, footnote: footnote(user) }))
  const FLOWS = [
    ['signed out: started again', [{ op: 'click' }, { op: 'answer', answer: { ok: true } }]],
    ['deadwax answering with a failure still signed out', [{ op: 'click' }, { op: 'answer', answer: { status: 503, detail: "couldn't forget it" } }]],
    ['a 401: signed out already', [{ op: 'click' }, { op: 'answer', answer: { status: 401 } }]],
    ['no answer at all: said, and nothing started again', [{ op: 'click' }, { op: 'answer', answer: { offline: 'Failed to fetch' } }, { op: 'click' }, { op: 'answer', answer: { ok: true } }]],
    ['no answer in time: the same', [{ op: 'click' }, { op: 'answer', answer: { timeout: 'timed out' } }]],
    ['a second press while it asks does nothing', [{ op: 'click' }, { op: 'click' }, { op: 'answer', answer: { offline: 'Load failed' } }]],
  ]
  for (const [name, steps] of FLOWS) {
    reloads = 0
    const pending = []
    let asks = 0
    G.signOut = () => { asks += 1; return new Promise((resolve, reject) => pending.push({ resolve, reject })) }
    const draw = hooks.root(SignOutRow)
    let tree = draw({ user: 'ethan' })
    const out = []
    for (const step of steps) {
      if (step.op === 'click') find(tree, (node) => node.type === 'button')[0].props.onClick()
      else {
        const waiting = pending.shift()
        if (step.answer.ok) waiting.resolve({ signed_out: true })
        else waiting.reject(made(step.answer, '/auth/logout'))
        await settle()
      }
      tree = draw({ user: 'ethan' })
      const button = find(tree, (node) => node.type === 'button')[0]
      const problem = find(tree, byClass('app-error')).map(text)
      out.push({ step, asks, reloads, row: text(find(button, byClass('app-row-label'))[0]), value: text(find(button, byClass('app-row-value'))[0]),
        disabled: button.props.disabled === true, problem: problem.length ? problem[0] : null })
    }
    traces.push({ name, steps: out })
  }
  delete globalThis.location
  return { footnotes, traces }
}

/* ===================================================================================== whose.json */

const MINE_WORDS = {
  ADD_FROM_PAGE: W.ADD_FROM_PAGE, ADDED_FROM_PAGE: W.ADDED_FROM_PAGE, REMOVED_FROM_PAGE: W.REMOVED_FROM_PAGE,
  REMOVED_STAR_TO_RETURN: W.REMOVED_STAR_TO_RETURN, NO_RELEASE_TO_ADD: W.NO_RELEASE_TO_ADD, NOT_FOUND_TO_ADD: W.NOT_FOUND_TO_ADD,
}
const noteName = (note) => (note === null ? null : Object.keys(MINE_WORDS).find((key) => MINE_WORDS[key] === note) ?? `?${note}`)
const mineOut = (mine) => [mine.yours, mine.badge, mine.action, noteName(mine.note), mine.pending]

function whoseFixture() {
  //? the inputs as the page passes them: undefined for the bridge's yours (not sent), null for the rest's unknowns
  const product = []
  for (const personal of [true, false])
    for (const starred of [null, true, false])
      for (const storeDone of [true, false])
        for (const bridgeFailed of [false, true])
          for (const bridgeYours of [undefined, true, false])
            for (const present of [0, 2])
              for (const release of [null, '', 'rel-1'])
                for (const releaseSaid of [null, '', 'rel-1'])
                  for (const changed of [null, 'added', 'removed']) {
                    const mine = W.albumMine({ personal, starred, storeDone, bridgeFailed, bridgeYours, present, release, releaseSaid, changed })
                    product.push([[personal, starred, storeDone, bridgeFailed, bridgeYours === undefined ? null : bridgeYours, present, release, releaseSaid, changed], mineOut(mine)])
                  }
  //? whose.sim.cjs's cases (lines 107-180), built as it builds them, by its names
  const page = (over) => ({ personal: true, starred: false, storeDone: true, bridgeFailed: false, bridgeYours: false, present: 1,
    release: 'rel-third', releaseSaid: 'rel-third', changed: null, ...over })
  const asInput = (input) => [input.personal, input.starred, input.storeDone, input.bridgeFailed ?? false,
    input.bridgeYours === undefined ? null : input.bridgeYours, input.present, input.release, input.releaseSaid ?? null, input.changed]
  const SIM = [
    ['logins off: "In your library", nothing offered - as it always was', [{ personal: false, starred: null, storeDone: false, bridgeYours: undefined, present: 1, release: 'r', changed: null }]],
    ['the store\'s, not yours: "In the collection" and Add to my library, with what Add does', [page({})]],
    ['yours by the bridge, or starred by you: "In your library" and Remove', [page({ bridgeYours: true }), page({ starred: true })]],
    ['...starred by the album\'s own answer even before the bridge has answered', [page({ starred: true, storeDone: false, bridgeYours: undefined })]],
    ['not yours with no release id to keep it by: no Add, and the line says why', [page({ release: null, releaseSaid: '', present: 0, bridgeYours: undefined })]],
    ['...nor with a release the store has no folder of - and the line says that, never "no release id" (review)',
      [page({ present: 0, bridgeYours: undefined }), page({ present: 0, bridgeYours: false })]],
    ['the bridge unable to say (a folder, no `yours`): "In the collection" - true either way - and nothing offered', [page({ bridgeYours: undefined })]],
    ['...nor once the bridge has FAILED - never the "no release id" line for a check that couldn\'t be made (review)',
      [page({ bridgeFailed: true, release: null, present: 0, bridgeYours: undefined }), page({ bridgeFailed: true, release: null, releaseSaid: null, present: 0, bridgeYours: undefined }),
        page({ bridgeFailed: true, release: null, releaseSaid: '', present: 0, bridgeYours: undefined })]],
    ['...nor when the bridge found no release where Navidrome names one', [page({ release: null, releaseSaid: 'rel-third', present: 0, bridgeYours: undefined })]],
    ['...nor before the bridge has answered - said to be on its way, so its place is held', [page({ storeDone: false, bridgeYours: undefined })]],
    ['...nor before the album\'s own answer - a list\'s tile is never read for `starred` (review: one from before a Remove)',
      [page({ starred: null }), page({ starred: null, bridgeYours: false, storeDone: true })]],
    ['an Add just taken: "In your library", the added words, Remove to undo it', [page({ changed: 'added' })]],
    ['a Remove just taken: "In the collection", saying nothing was deleted, Add to undo it - even over a stale `starred`',
      [page({ changed: 'removed', starred: true, bridgeYours: true })]],
    ['...but no Add after removing an album deadwax can\'t keep - and the line says how to have it back (review)',
      [page({ changed: 'removed', release: null, releaseSaid: '', present: 0, bridgeYours: undefined, starred: true }), page({ changed: 'removed', present: 0, bridgeYours: undefined, starred: true })]],
  ]
  const sim = SIM.map(([name, inputs]) => ({ name, cases: inputs.map((input) => [asInput(input), mineOut(W.albumMine(input))]) }))
  const held = []
  for (const personal of [true, false]) for (const yours of [true, false, null, undefined]) {
    held.push({ personal, yours: yours === undefined ? 'undefined' : yours, phrase: W.heldPhrase(personal, yours), label: W.heldLabel(personal, yours) })
  }
  //? the mine block's button (AlbumPage.tsx), as written
  const button = lines('player/AlbumPage.tsx',
    /\{(mine\.action === 'add' \? \(mineBusy \? '[^']+' : '[^']+'\) : mineBusy \? '[^']+' : '[^']+')\}/, 'the mine button')
  const buttonWords = expression(button.found[1], 'mine', 'mineBusy')
  const buttons = []
  for (const action of ['add', 'remove']) for (const busy of [false, true]) buttons.push({ action, busy, words: buttonWords({ action }, busy) })
  //? the placeholder held while whose it is is still to come
  const placeholder = lines('player/AlbumPage.tsx',
    /<div class="app-album-mine is-waiting" aria-hidden="true">\s*<p class="app-store-line">\{ADD_FROM_PAGE\}<\/p>\s*<button[^>]*>\s*([^<]+?)\s*<\/button>/, 'the mine placeholder')
  const wiring = lines('player/AlbumPage.tsx', /const mine = albumMine\((\{[\s\S]*?\n {2}\})\)/, 'the mine wiring')
  const derived = lines('player/AlbumPage.tsx', /const release = (store\?\.release_mbid \?\? null)\s*const storeDone = (store !== null \|\| storeFailed)/, 'release and storeDone')
  //? what the page draws of it, and when (AlbumPage.tsx, as written): the badge once the bridge is done and nothing
  //? pends; the unseen placeholder while it pends with the album in; the mine block with an action, a note or a refusal
  const badgeWhen = lines('player/AlbumPage.tsx', /<div class=\{`app-album-chips\$\{(storeDone && !mine\.pending) \? '' : ' is-waiting'\}`\}>/, 'the badge shown')
  const placeholderWhen = lines('player/AlbumPage.tsx', /\{(mine\.pending && album && !mineRefused) && \(\s*<div class="app-album-mine is-waiting"/, 'the placeholder shown')
  const blockWhen = lines('player/AlbumPage.tsx', /\{\((mine\.action \|\| mine\.note \|\| !!mineRefused)\) && \(\s*<div class="app-album-mine" tabIndex=\{-1\}>/, 'the mine block shown')
  const badgeShown = expression(badgeWhen.found[1], 'storeDone', 'mine')
  const placeholderShown = expression(placeholderWhen.found[1], 'mine', 'album', 'mineRefused')
  const blockShown = expression(blockWhen.found[1], 'mine', 'mineRefused')
  const REFUSED = new ApiError(503, "Navidrome isn't answering", 'POST /me/library/add failed', false, null, null, '/me/library/add')
  //? the page's state, as AlbumPage.tsx turns it into albumMine's inputs - evaluated as written
  const inputsOf = expression(wiring.found[1], 'hasLibrary', 'album', 'error', 'storeDone', 'storeFailed', 'store', 'release', 'changed')
  const releaseOf = expression(derived.found[1], 'store'), storeDoneOf = expression(derived.found[2], 'store', 'storeFailed')
  const ALBUMS = [null, { id: 'al' }, { id: 'al', starred: '2026-11-01T10:00:00Z', musicBrainzId: 'rel-1' }, { id: 'al', starred: '', musicBrainzId: '' },
    { id: 'al', musicBrainzId: 'rel-1' }]
  const STORES = [null, { present: [], other_pressings: [] }, { release_mbid: 'rel-1', present: [{}], other_pressings: [], yours: true },
    { release_mbid: 'rel-1', present: [{}, {}], other_pressings: [], yours: false }, { release_mbid: null, present: [], other_pressings: [], yours: false },
    { release_mbid: 'rel-1', present: [], other_pressings: [] }]
  const wired = []
  for (const personal of [true, false])
    for (const album of ALBUMS)
      for (const error of [false, true])
        for (const store of STORES)
          for (const storeFailed of [false, true])
            for (const changed of [null, 'added', 'removed']) {
              if (store && storeFailed) continue
              const release = releaseOf(store)
              const storeDone = storeDoneOf(store, storeFailed)
              const input = inputsOf(() => personal, album, error, storeDone, storeFailed, store, release, changed)
              const mine = W.albumMine(input)
              wired.push({
                personal, album, error, store: store && { release_mbid: store.release_mbid ?? null, present: store.present.length, yours: store.yours ?? null },
                storeFailed, changed, mine: mineOut(mine),
                //? [not refused, refused] for the two the last refusal decides
                shown: { badge: !!badgeShown(storeDone, mine), placeholder: [null, REFUSED].map((refused) => !!placeholderShown(mine, album, refused)),
                  block: [null, REFUSED].map((refused) => !!blockShown(mine, refused)) },
              })
            }
  return {
    about: 'lib/whose.ts: albumMine over every combination of its inputs - [personal, starred, storeDone, bridgeFailed, bridgeYours (null: not sent), present, release, releaseSaid, changed] -> [yours, badge, action, note (by its name in words), pending]; whose.sim.cjs\'s cases by name; heldPhrase and heldLabel; the words; the mine block\'s button and placeholder, and `wired`: the album page\'s state (the album\'s answer or none, its error, the id bridge\'s answer - present as a count - or its failure, the last change) turned into albumMine\'s inputs as AlbumPage.tsx does it, and what albumMine says, with `shown`: whether the page draws the badge, the unseen placeholder and the mine block from it - the last two [with no refusal, with one] (AlbumPage.tsx, evaluated as written).',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('lib/whose.ts'), button.from, placeholder.from, wiring.from, derived.from, badgeWhen.from, placeholderWhen.from,
      blockWhen.from]),
    words: { IN_YOUR_LIBRARY: W.IN_YOUR_LIBRARY, IN_THE_STORE: W.IN_THE_STORE, ...MINE_WORDS },
    held,
    buttons,
    placeholder: placeholder.found[1],
    sim,
    wired,
    product,
  }
}

/* ===================================================================================== discs.json */

function discsFixture() {
  const songs = (...discs) => discs.map((discNumber) => (discNumber === undefined ? {} : { discNumber }))
  const WEMBLEY = 'TDSOTM - Live at Wembley - From Pre-FM Master Tape'
  const SIM = [
    ['a heading at each disc\'s first song, the fourth with its title', songs(1, 1, 2, 2, 3, 4, 4), [{ disc: 4, title: WEMBLEY }]],
    ['an ordinary one-disc album: none, as before', songs(1, 1, 1), undefined],
    ['...and none with discTitles empty', songs(1, 1), []],
    ['a one-disc album whose disc HAS a title: its heading', songs(1, 1), [{ disc: 1, title: 'Remastered' }]],
    ['...but deadwax\'s own one-disc files carry no disc number, so Navidrome sends none: no heading', songs(undefined, undefined), undefined],
    ['two discs, no titles: "Disc 1", "Disc 2"', songs(1, 2), undefined],
    ['the Experience edition, both titled', songs(1, 1, 2), [{ disc: 1, title: '2011 Remaster' }, { disc: 2, title: 'Unreleased Tracks' }]],
    ['no disc number is disc 1', songs(undefined, 2), [{ disc: 1, title: 'Side one' }]],
    ['a blank title is no title', songs(1, 1), [{ disc: 1, title: '   ' }]],
    ['a title for a disc with no songs is ignored', songs(1, 1), [{ disc: 2, title: 'Bonus' }]],
    ['a disc number sent as a string still matches', songs(1, 2), [{ disc: '2', title: 'Live' }]],
    ['a title is trimmed', songs(2, 3), [{ disc: 2, title: '  Live  ' }]],
    ['the first title given for a disc wins', songs(1), [{ disc: 1, title: 'A' }, { disc: 1, title: 'B' }]],
    ['nonsense entries are left out', songs(1), [{ disc: 0, title: 'x' }, { disc: 'two', title: 'y' }, { title: 'z' }]],
  ]
  const one = (name, list, titles) => ({
    name, songs: list, titles: titles ?? null,
    headings: D.discHeadings(list, titles),
    map: [...D.discTitleMap(titles)],
  })
  const sim = SIM.map(([name, list, titles]) => one(name, list, titles))
  //? seeded albums: disc numbers as Navidrome sends them (whole numbers, or none), titles as anything at all
  const rand = seeded(424242)
  const pick = (list) => list[Math.floor(rand() * list.length)]
  const DISCS = [undefined, undefined, null, 0, 1, 1, 1, 2, 2, 3, 4, 10, -1]
  const TITLES = ['Live', '  Live  ', '', '   ', 'Bonus', 'Disc', '2011 Remaster', 'Bj' + E_ACUTE + 'rk' + NBSP, E_COMBINING, IDEO + 'x' + IDEO, VT + 'y', null, 5]
  const TITLE_DISCS = [1, 2, 3, 4, 0, -1, 2.5, '2', '10', 'two', null, undefined, 1e3]
  const seededCases = []
  for (let i = 0; i < 220; i++) {
    const length = Math.floor(rand() * 9)
    const list = []
    for (let j = 0; j < length; j++) {
      const discNumber = pick(DISCS)
      list.push(discNumber === undefined ? {} : { discNumber })
    }
    //? Navidrome's order is by disc, then track - but a list may come in any order
    if (rand() < 0.7) list.sort((a, b) => (a.discNumber || 1) - (b.discNumber || 1))
    let titles
    const kind = rand()
    if (kind < 0.25) titles = undefined
    else if (kind < 0.35) titles = []
    else {
      titles = []
      const count = 1 + Math.floor(rand() * 4)
      for (let j = 0; j < count; j++) {
        const entry = {}
        const disc = pick(TITLE_DISCS)
        if (disc !== undefined) entry.disc = disc
        const title = pick(TITLES)
        if (title !== undefined) entry.title = title
        titles.push(entry)
      }
    }
    seededCases.push(one(`seeded ${i}`, list, titles))
  }
  const heading = [[4, [[4, WEMBLEY]]], [2, [[4, WEMBLEY]]], [1, []], [12, [[12, 'Twelve']]]].map(([disc, entries]) => ({
    disc, titles: entries, heading: D.discHeading(disc, new Map(entries)),
  }))
  return {
    about: 'lib/discTitles.ts: discHeadings (one per song: the heading over it, or null) and discTitleMap ([disc, title] in the order kept) of discs.sim.cjs\'s albums by its names, and of seeded ones; discHeading of a few. `songs` are as Navidrome sends them ({} for no disc number); `titles` as anything, null for none sent.',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('lib/discTitles.ts')]),
    dot: DOT,
    heading,
    sim,
    seeded: seededCases,
  }
}

/* ===================================================================================== format.json */

function formatFixture() {
  const NUMBERS = [
    null, undefined, 0, -0, NaN, Infinity, -Infinity, 0.4, 0.49999999999999994, 0.5, 1, 1.5, 9.5, 59, 59.4, 59.5, 59.9, 60, 60.5, 61, 89.5,
    90, 119.5, 125, 187.9, 245.3, 299.99, 300, 599.5, 1799, 1800, 2999.9, 3569, 3570, 3599.5, 3600, 3630, 3659, 4321.7, 7199.4, 7200,
    86399.5, 86400, 359999, 1e6 + 0.5, 4503599627370495.5, 1e12 + 0.5, 1e15, -0.4, -0.5, -0.6, -1, -5, -29.9, -30, -59.5, -61, -3600,
    -3599.5, 1e-300, Number.MIN_VALUE, -Number.MIN_VALUE, 2 ** 31, 2 ** 31 + 0.5,
  ]
  const rand = seeded(777)
  for (let i = 0; i < 120; i++) {
    const scale = [1, 60, 600, 3600, 36000][Math.floor(rand() * 5)]
    NUMBERS.push(Math.round(rand() * scale * 1000) / 1000 * (rand() < 0.1 ? -1 : 1))
    NUMBERS.push(Math.floor(rand() * scale) + 0.5)
  }
  const trackTime = NUMBERS.map((seconds) => [num(seconds), seconds === undefined, F.trackTime(seconds)])
  const formatDuration = NUMBERS.filter((seconds) => seconds !== null && seconds !== undefined).map((seconds) => [num(seconds), F.formatDuration(seconds)])
  const clock = NUMBERS.filter((seconds) => seconds !== null && seconds !== undefined).map((seconds) => [num(seconds), SC.clock(seconds)])
  const SUFFIXES = [
    [], ['flac'], ['flac', 'FLAC', 'Flac'], ['flac', 'mp3'], ['flac', null], [null], [''], ['', ''], [null, ''], ['mp3', 'mp3', 'mp3'],
    [SHARP_S], [SHARP_S, 'SS'], ['ss', SHARP_S], ['i'], [ch(0x131)], [ch(0xfb00)], [ch(0x149)], [ch(0x1c6)], ['m4a', 'M4A', undefined],
    ['flac', 'fla' + ch(0x0441)], [E_COMBINING], [E_ACUTE, E_COMBINING], ['ogg', 'OGG', 'oga'],
  ]
  const sharedFormat = SUFFIXES.map((suffixes) => ({
    suffixes: suffixes.map((suffix) => (suffix === undefined ? 'undefined' : suffix)),
    format: F.sharedFormat(suffixes.map((suffix) => (suffix === undefined ? {} : { suffix }))),
  }))

  //? the album page's lines, read out of AlbumPage.tsx and evaluated as written
  const meta = lines('player/AlbumPage.tsx', /\{(\[shown\?\.genre, shown\?\.year, format\]\.filter\(Boolean\)\.join\('[^']*'\))\}/, 'the meta line')
  const metaOf = expression(meta.found[1], 'shown', 'format')
  const metas = []
  for (const genre of [undefined, null, '', 'Trip Hop', 'Rock' + DOT])
    for (const year of [undefined, null, 0, 1994, -1])
      for (const format of [null, 'FLAC', '']) {
        const shown = {}
        if (genre !== undefined) shown.genre = genre
        if (year !== undefined) shown.year = year
        metas.push({ genre: genre ?? null, year: year ?? null, format, line: metaOf(shown, format) })
      }
  metas.push({ genre: null, year: null, format: 'MP3', shown: null, line: metaOf(null, 'MP3') })
  const total = lines('player/AlbumPage.tsx', /const total = (songs\.reduce\(\(sum, song\) => sum \+ \(song\.duration \?\? 0\), 0\))/, 'the total')
  const totalOf = expression(total.found[1], 'songs')
  const footer = lines('player/AlbumPage.tsx',
    /<p class="pl-album-footer">\s*\{(songs\.length)\} \{(songs\.length === 1 \? 'song' : 'songs')\}\s*\{(total \? `, \$\{formatDuration\(total\)\}` : '')\}\s*<\/p>/,
    'the footer')
  const footerOf = (songs) => {
    const sum = totalOf(songs)
    return String(expression(footer.found[1], 'songs')(songs)) + ' ' + expression(footer.found[2], 'songs')(songs)
      + expression(footer.found[3], 'total', 'formatDuration')(sum, F.formatDuration)
  }
  const DURATIONS = [undefined, 0, 1, 59.5, 60, 187.9, 245.3, 2999.4, 3600, 0.1, 29.9, 30]
  const footers = []
  const rand2 = seeded(31337)
  for (let i = 0; i < 80; i++) {
    const count = i < 4 ? i : Math.floor(rand2() * 24)
    const list = []
    for (let j = 0; j < count; j++) {
      const duration = DURATIONS[Math.floor(rand2() * DURATIONS.length)]
      list.push(duration === undefined ? { id: `s${j}` } : { id: `s${j}`, duration: duration * (rand2() < 0.5 ? 1 : 7.3) })
    }
    footers.push({ durations: list.map((song) => num(song.duration)), total: num(totalOf(list)), footer: footerOf(list) })
  }
  const artist = lines('player/AlbumPage.tsx', /const showArtist = (song\.artist && song\.artist !== shown\?\.artist)/, 'a row\'s artist')
  const artistOf = expression(artist.found[1], 'song', 'shown')
  const number = lines('player/AlbumPage.tsx', /<PlayingBars paused=\{!player\.playing\} \/> : (song\.track \?\? '')\}/, 'a row\'s number')
  const numberOf = expression(number.found[1], 'song')
  const rows = []
  for (const track of [undefined, 0, 1, 12, -1])
    for (const songArtist of [undefined, '', 'Portishead', 'portishead', 'Beth Gibbons'])
      for (const albumArtist of [undefined, '', 'Portishead']) {
        const song = { id: 's', title: 'Roads' }
        if (track !== undefined) song.track = track
        if (songArtist !== undefined) song.artist = songArtist
        const shown = albumArtist === undefined ? { id: 'al' } : { id: 'al', artist: albumArtist }
        const shows = artistOf(song, shown)
        //? JSX draws a number as its digits, and nothing for '' (or false)
        const drawn = numberOf(song)
        rows.push({ track: track ?? null, artist: songArtist ?? null, albumArtist: albumArtist ?? null, number: String(drawn), artistShown: shows ? song.artist : null })
      }
  rows.push({ track: null, artist: 'Portishead', albumArtist: null, shownMissing: true, number: String(numberOf({ id: 's' })), artistShown: artistOf({ id: 's', artist: 'Portishead' }, null) ? 'Portishead' : null })
  const more = lines('player/AlbumPage.tsx', /aria-label=\{`(More for )\$\{song\.title\}`\}/, 'a row\'s more')
  const moreAlbum = lines('player/AlbumPage.tsx', /aria-label="(More for this album)"/, 'the album\'s more')
  const spinner = lines('player/AlbumPage.tsx', /\{!drawSongs && !error && <div class="pl-spinner" aria-label="([^"]+)" \/>\}/, 'the spinner')
  const TITLES = [null, undefined, '', 'Dummy', 'x'.repeat(60), 'x'.repeat(61), ' ' + 'x'.repeat(60) + ' ', E_ACUTE.repeat(61), E_COMBINING.repeat(31),
    String.fromCodePoint(0x1f600).repeat(60), String.fromCodePoint(0x1f600).repeat(61), NBSP + 'y'.repeat(60) + BOM, IDEO.repeat(70),
    "When the Pawn Hits the Conflicts He Thinks like a King What He Knows Throws the Blows When He Goes to the Fight"]
  const longTitles = TITLES.map((title) => ({ title: title === undefined ? 'undefined' : title, long: T.isLongTitle(title) }))
  //? the warm (levelling.ts warmAlbum), the setting as this device keeps it
  const WARM_SONGS = [
    [], [{ suffix: 'flac' }], [{ suffix: 'mp3' }, { suffix: 'FLAC' }], [{ suffix: 'mp3' }], [{ contentType: 'audio/flac' }],
    [{ contentType: 'audio/x-flac; rate=44100' }], [{ contentType: ' Audio/FLAC ' }], [{ contentType: 'audio/mpeg' }], [{}],
    [{ suffix: 'fla' }], [{ suffix: 'Flac', contentType: 'audio/mpeg' }], null,
  ]
  const warms = []
  for (const setting of ['auto', 'song', 'album', 'off']) {
    for (const [i, list] of WARM_SONGS.entries()) {
      G.warmed.length = 0
      G.setting = setting
      const album = list === null ? { id: `al-${i}` } : { id: `al-${i}`, song: list.map((song, j) => ({ id: `s${j}`, title: 't', ...song })) }
      LV.warmAlbum(album)
      warms.push({ setting, songs: list, warmed: G.warmed.length === 1 && G.warmed[0] === album.id })
    }
  }
  return {
    about: 'lib/format.ts\'s trackTime ([seconds, undefined?, words]), formatDuration and lib/scrub.ts\'s clock over awkward numbers; sharedFormat over suffixes ("undefined": none sent); the album page\'s meta line, footer, rows, spinner and its ••• labels (AlbumPage.tsx, evaluated as written); lib/titles.ts isLongTitle; player/levelling.ts warmAlbum under each setting.',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('lib/format.ts'), whole('lib/titles.ts'), whole('player/levelling.ts'), ['ui/src/lib/scrub.ts', sha256(source('lib/scrub.ts'))],
      meta.from, total.from, footer.from, artist.from, number.from, more.from, moreAlbum.from, spinner.from]),
    trackTime, formatDuration, clock, sharedFormat,
    album: {
      meta: metas, footers, rows, longTitles, longTitle: T.LONG_TITLE, warms,
      words: { moreForSong: more.found[1], moreForAlbum: moreAlbum.found[1], loading: spinner.found[1] },
    },
  }
}

/* ===================================================================================== scrub.json */

function scrubFixture() {
  const sim = []
  const check = (name, fn, args, result) => sim.push({ name, fn, args: args.map(argOut), result: argOut(result) })
  const argOut = (value) => {
    if (typeof value === 'number' || value === undefined) return num(value)
    if (Array.isArray(value)) return value.map(argOut)
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, v]) => [key, argOut(v)]))
    return value
  }
  const call = (fn, ...args) => { const result = SC[fn](...args); check(currentName, fn, args, result); return result }
  let currentName = ''
  const named = (name, body) => { currentName = name; body() }
  //? scrub.sim.cjs's checks, made as it makes them - one name each
  named('the left end is the start', () => call('timeAt', 100, 100, 400, 300))
  named('the right end is the end', () => call('timeAt', 500, 100, 400, 300))
  named('the middle is half way', () => call('timeAt', 300, 100, 400, 300))
  named('60% across', () => call('timeAt', 340, 100, 400, 300))
  named('a finger past the left end is at the start', () => call('timeAt', 40, 100, 400, 300))
  named('a finger past the right end is at the end', () => call('timeAt', 900, 100, 400, 300))
  named('no length yet: nothing to seek to', () => call('timeAt', 300, 100, 400, 0))
  named('a bar with no width (not laid out): 0, not NaN', () => call('timeAt', 300, 100, 0, 300))
  named('right arrow: forward a step', () => call('keyTarget', 'ArrowRight', 60, 300))
  named('up arrow (VoiceOver swipe up): forward a step', () => call('keyTarget', 'ArrowUp', 60, 300))
  named('left arrow: back a step', () => call('keyTarget', 'ArrowLeft', 60, 300))
  named('down arrow: back a step', () => call('keyTarget', 'ArrowDown', 60, 300))
  named('page up: forward a page', () => call('keyTarget', 'PageUp', 60, 300))
  named('page down: back a page', () => call('keyTarget', 'PageDown', 60, 300))
  named('home: the start', () => call('keyTarget', 'Home', 60, 300))
  named('end: the end', () => call('keyTarget', 'End', 60, 300))
  named('back from 2 s stops at the start', () => call('keyTarget', 'ArrowLeft', 2, 300))
  named('forward from 298 s stops at the end', () => call('keyTarget', 'ArrowRight', 298, 300))
  named('a key that is not the bar\'s: null, so the page keeps it', () => call('keyTarget', 'Tab', 60, 300))
  named('space is not a seek', () => call('keyTarget', ' ', 60, 300))
  named('no length yet: no key seeks', () => call('keyTarget', 'ArrowRight', 0, 0))
  named('three quick presses step from each other\'s targets', () => {
    let at = 60
    for (let i = 0; i < 3; i++) {
      const reported = call('reportedPosition', { target: at, since: 0 }, 60, 10)
      const shown = call('shownTime', null, reported, 300)
      at = call('keyTarget', 'ArrowRight', shown, 300)
    }
  })
  let drag = null
  named('put down: it is where the finger is', () => { drag = call('dragStart', 7, 'song-a', 40) })
  named('the bar shows the finger, not the song', () => call('shownTime', drag, 12, 300))
  named('moved: it follows', () => { drag = call('dragMove', drag, 7, 90) })
  named('a second finger moving changes nothing', () => call('dragMove', drag, 8, 250))
  named('a move to where it already is is the same drag (no render)', () => call('dragMove', drag, 7, 90))
  named('no drag: a move is nothing', () => call('dragMove', null, 7, 90))
  named('a second finger lifted changes nothing', () => call('dragEnd', drag, 8, 'up'))
  named('let go: seeks to where the LAST move put it', () => call('dragEnd', drag, 7, 'up'))
  named('cancelled (the system took the touch): seeks nowhere, and lets go', () => call('dragEnd', drag, 7, 'cancel'))
  named('after it is gone, the lost capture that follows an up does nothing', () => call('dragEnd', null, 7, 'cancel'))
  named('a tap is a drag that never moved: seeks where it landed', () => call('dragEnd', SC.dragStart(3, 'song-a', 180), 3, 'up'))
  named('the song changed under the finger: the drag is let go of', () => call('dragFor', drag, 'song-b'))
  named('same song: the drag stays', () => call('dragFor', drag, 'song-a'))
  named('let go, the bar shows the song\'s position again', () => call('shownTime', null, 12, 300))
  named('the bar never shows past the end', () => call('shownTime', SC.dragStart(1, 'a', 400), 12, 300))
  named('nor before the start', () => call('shownTime', null, -3, 300))
  named('with no length yet, the position as it is', () => call('shownTime', null, 5, 0))
  const pending = { target: 180, since: 1000 }
  named('the target, not where the song was', () => call('reportedPosition', pending, 25, 1200))
  named('an update from before the seek lands can\'t move it', () => call('reportedPosition', pending, 24.8, 3000))
  named('no seek on its way: the song\'s position', () => call('reportedPosition', null, 25, 1200))
  named('one that never landed lets go after a while', () => call('reportedPosition', pending, 25, 1000 + SC.PENDING_MAX_MS))
  named('...and not before', () => call('reportedPosition', pending, 25, 1000 + SC.PENDING_MAX_MS - 1))
  named('3:07', () => call('clock', 187.9))
  named('nothing is 0:00', () => call('clock', NaN))
  named('never negative', () => call('clock', -4))

  //? the readout's checks, each a run of events from a reading - every reading after each event, and its words
  const readings = []
  const reading = (name, events, from = null) => {
    let r = from
    const after = []
    for (const event of events) {
      r = SC.seekStep(r, event)
      after.push({ reading: argOut(r), words: SC.describeSeek(r) })
    }
    readings.push({ name, from: argOut(from), events: events.map(argOut), after })
    return r
  }
  const asked = (at = 130, length = 300) => ({ kind: 'asked', asked: at, length, track: 's1' })
  readings.push({ name: 'nothing yet', from: null, events: [], after: [], words: SC.describeSeek(null) })
  const landed = reading('asked, on its way; landed, by the element\'s clock', [asked(), { kind: 'seeked', position: 130 }])
  reading('a second seeked (an older seek\'s) doesn\'t overwrite what it said', [{ kind: 'seeked', position: 90 }], landed)
  reading('an update before the end changes nothing', [{ kind: 'clock', position: 200, at: 5000 }], landed)
  reading('nothing asked yet: events are nothing', [{ kind: 'ended', position: 300, at: 1, rate: 1 }])
  reading('ended with its clock: landed where asked', [{ kind: 'clock', position: 299.8, at: 100000 }, { kind: 'clock', position: 300, at: 100200 },
    { kind: 'ended', position: 300, at: 100210, rate: 1 }], landed)
  reading('ran out 7 s before the clock: landed 7 s later', [{ kind: 'ended', position: 293, at: 50000, rate: 1 }], landed)
  reading('played on 7 s after its clock stopped: landed 7 s earlier', [{ kind: 'clock', position: 299.8, at: 100000 }, { kind: 'clock', position: 300, at: 103000 },
    { kind: 'ended', position: 300, at: 107200, rate: 1 }], landed)
  reading('the measured case: asked 4:00, landed 1:35 (145 s early)', [asked(240), { kind: 'seeked', position: 240 }, { kind: 'clock', position: 299.9, at: 0 },
    { kind: 'ended', position: 300, at: 144900, rate: 1 }])
  reading('at double speed the song plays on twice as far', [{ kind: 'clock', position: 300, at: 0 }, { kind: 'ended', position: 300, at: 3500, rate: 2 }], landed)
  //? `rate || 1`: a rate of 0 or NaN is no speed to measure by, so the wall clock counts as at 1 - the seeded runs
  //? below never reach a judged end with its clock, so these are what hold it
  reading('a rate of 0 at the end is measured as 1', [{ kind: 'clock', position: 299.9, at: 0 }, { kind: 'ended', position: 300, at: 2000, rate: 0 }], landed)
  reading('...and so is NaN', [{ kind: 'clock', position: 299.9, at: 0 }, { kind: 'ended', position: 300, at: 2000, rate: NaN }], landed)
  reading('...from asking, with the clock at its end', [asked(240), { kind: 'seeked', position: 240 }, { kind: 'clock', position: 299.9, at: 1000 },
    { kind: 'ended', position: 299.95, at: 4000, rate: 0 }])
  reading(`off by under ${SC.LANDED_WITHIN_S} s is where asked (Navidrome's rounded length, update spacing)`, [{ kind: 'ended', position: 299.2, at: 1, rate: 1 }], landed)
  reading(`the clock within ${SC.END_SLACK_S} s of the length counts as at the end`, [{ kind: 'clock', position: 300 - SC.END_SLACK_S, at: 5 }], landed)
  reading('...and further back does not', [{ kind: 'clock', position: 299, at: 5 }], landed)
  const judged = [{ kind: 'clock', position: 299.9, at: 0 }, { kind: 'ended', position: 300, at: 60000, rate: 1 }]
  reading('a pause near the end: the wall clock is no measure after it, so no judgement', [{ kind: 'paused' }, ...judged], landed)
  reading('another seek ("previous" restarting, a resume): the end is no longer about this one', [{ kind: 'other seek' }, ...judged], landed)
  reading('the song changed before its end: never judged', [{ kind: 'song change' }, ...judged], landed)
  reading('not landed yet when the song ended: nothing to judge', [asked(), { kind: 'ended', position: 300, at: 1, rate: 1 }])
  reading('"previous" during a seek to 2:00: the restart\'s 0:00 is not what the player said for it', [asked(120), { kind: 'other seek' }, { kind: 'seeked', position: 0 }])
  reading('the song changed before the seek landed: interrupted, not "seeking..." for good', [asked(90), { kind: 'song change' }, { kind: 'seeked', position: 12 }, { kind: 'song change' }])
  reading('the song failed under the seek: interrupted', [asked(90), { kind: 'failed' }])
  reading('...and its end is judged no more', [{ kind: 'failed' }], landed)
  reading('a pause doesn\'t stop a seek on its way: its \'seeked\' still counts', [asked(90), { kind: 'paused' }, { kind: 'seeked', position: 90 }])
  reading('a new seek starts a new reading', [{ kind: 'ended', position: 293, at: 50000, rate: 1 }, { kind: 'asked', asked: 60, length: 300, track: 's1' }], landed)
  reading('a seek with no length known can\'t be judged', [asked(130, 0)])
  //? seeded runs of every event, rates of 0 and NaN among them (their judged ends are the named runs' above)
  const rand = seeded(9001)
  const pick = (list) => list[Math.floor(rand() * list.length)]
  for (let run = 0; run < 80; run++) {
    const events = []
    let clock = 0
    for (let i = 0; i < 10; i++) {
      clock += Math.floor(rand() * 4000)
      const length = pick([0, 30, 300, 301.5])
      const kind = pick(['asked', 'asked', 'seeked', 'other seek', 'song change', 'failed', 'paused', 'clock', 'clock', 'clock', 'ended', 'ended'])
      if (kind === 'asked') events.push({ kind, asked: Math.floor(rand() * 3000) / 10, length, track: pick(['s1', 's2']) })
      else if (kind === 'seeked') events.push({ kind, position: Math.floor(rand() * 3000) / 10 })
      else if (kind === 'clock') events.push({ kind, position: pick([299.6, 299.7, 300, 293, 150, 301.4, 29.8]), at: clock })
      else if (kind === 'ended') events.push({ kind, position: pick([300, 293, 299.2, 301.5, 30, 0]), at: clock, rate: pick([1, 1, 2, 0.5, 0, NaN]) })
      else events.push({ kind })
    }
    reading(`seeded ${run}`, events)
  }
  //? seeded drags: a finger, a second finger, the song changing, the bar asked what it shows
  const drags = []
  for (let run = 0; run < 60; run++) {
    let state = null
    const steps = []
    for (let i = 0; i < 14; i++) {
      const roll = rand()
      const length = pick([0, 300, 187.5])
      const step = roll < 0.15 ? { op: 'start', pointer: pick([1, 2]), track: pick(['a', 'b']), time: Math.floor(rand() * 4000) / 10 }
        : roll < 0.45 ? { op: 'move', pointer: pick([1, 1, 2]), time: Math.floor(rand() * 4000) / 10 - 20 }
        : roll < 0.6 ? { op: 'end', pointer: pick([1, 1, 2]), how: pick(['up', 'cancel']) }
        : roll < 0.7 ? { op: 'for', track: pick(['a', 'b']) }
        : { op: 'shown', position: pick([12, -3, 400, NaN, 150.25]), length }
      let result = null
      if (step.op === 'start') state = SC.dragStart(step.pointer, step.track, step.time)
      else if (step.op === 'move') state = SC.dragMove(state, step.pointer, step.time)
      else if (step.op === 'end') { const ended = SC.dragEnd(state, step.pointer, step.how); state = ended.drag; result = num(ended.seek) }
      else if (step.op === 'for') state = SC.dragFor(state, step.track)
      else result = num(SC.shownTime(state, step.position, step.length))
      steps.push({ ...argOut(step), drag: argOut(state), result })
    }
    drags.push(steps)
  }
  //? sweeps: a point on the bar, a key, a seek on its way
  const SPECIAL = [NaN, Infinity, -Infinity, -0, 0]
  const timeAt = []
  for (let i = 0; i < 160; i++) {
    const x = i < 5 ? SPECIAL[i] : Math.floor(rand() * 8000) / 10 - 100
    const left = pick([0, 100, -20, 16.5])
    const width = pick([0, 400, 343, -10, NaN, 0.5])
    const length = pick([0, 300, 187.9, -1, NaN, Infinity, 1e-9])
    timeAt.push([num(x), num(left), num(width), num(length), num(SC.timeAt(x, left, width, length))])
  }
  const keys = []
  for (const key of ['ArrowRight', 'ArrowUp', 'ArrowLeft', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', 'Tab', ' ', 'arrowright', 'Enter']) {
    for (const from of [0, 2, 60, 298, 300, 400, -5, NaN]) {
      for (const length of [300, 0, 4.5, NaN, Infinity]) keys.push([key, num(from), num(length), num(SC.keyTarget(key, from, length))])
    }
  }
  const reported = []
  for (let i = 0; i < 60; i++) {
    const since = pick([0, 1000, 5000.5])
    const pendingSeek = rand() < 0.2 ? null : { target: Math.floor(rand() * 3000) / 10, since }
    const now = since + pick([0, 1, 19999, 20000, 20001, -5, 1e6])
    const position = Math.floor(rand() * 3000) / 10
    reported.push([argOut(pendingSeek), num(position), num(now), num(SC.reportedPosition(pendingSeek, position, now))])
  }
  return {
    about: 'lib/scrub.ts: scrub.sim.cjs\'s checks by name (fn, args, result - a drag as {pointer, track, time}, a pending seek as {target, since}); the readout\'s runs (every reading and describeSeek after each event); seeded drags (each step\'s op, the drag after it, and what end seeks or shown shows); sweeps of timeAt [x, left, width, length, time], keyTarget [key, from, length, target] and reportedPosition [pending, position, now, reported].',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('lib/scrub.ts')]),
    constants: { KEY_STEP_S: SC.KEY_STEP_S, PAGE_STEP_S: SC.PAGE_STEP_S, PENDING_MAX_MS: SC.PENDING_MAX_MS, END_SLACK_S: SC.END_SLACK_S, LANDED_WITHIN_S: SC.LANDED_WITHIN_S },
    sim, readings, drags, timeAt, keys, reported,
  }
}

/* ===================================================================================== player.json */

function playerFixture() {
  const LINES = [null, undefined, '', 'Portishead', 'Skipped "Glory Box" - it wouldn\'t play', ELLIPSIS]
  const TITLES = ['Roads', '', 'Glory Box' + NBSP, 'Bj' + E_ACUTE + 'rk']
  const labels = []
  for (const title of TITLES) for (const line of LINES) labels.push({ title, line: line === undefined ? 'undefined' : line, label: miniPlayerLabel(title, line) })
  //? the mini player drawn: its second line, and its name, from the player's error and the song's artist
  const drawn = []
  for (const error of [null, '', 'The connection dropped while this song was loading', 'Skipped "Glory Box" - it wouldn\'t play'])
    for (const artist of ['Portishead', '']) {
      const tree = MiniPlayer({ player: { track: { id: 's', title: 'Roads', artist, album: 'Dummy', coverArt: null }, error, playing: true, buffering: false, duration: 300, toggle() {}, next() {} }, onOpen() {} })
      const open = find(tree, byClass('pl-mini-open'))[0]
      const buttons = find(tree, (node) => node.type === 'button').filter((node) => !byClass('pl-mini-open')(node))
      drawn.push({ error, artist, line: text(find(open, byClass('pl-mini-artist'))[0]), label: open.props['aria-label'], buttons: buttons.map((node) => node.props['aria-label']) })
    }
  const paused = MiniPlayer({ player: { track: { id: 's', title: 'Roads', artist: 'Portishead' }, error: null, playing: false, buffering: true, duration: 0, toggle() {}, next() {} }, onOpen() {} })
  const pausedButtons = find(paused, (node) => node.type === 'button').filter((node) => !byClass('pl-mini-open')(node))
  //? the hairline along its bottom (MiniPlayer.tsx's Progress, driven): what it scales to, from the position and the length
  const progress = []
  for (const duration of [300, 245.3, 0.5, 0, NaN, -10, Infinity])
    for (const position of [0, 1, 150, 299.9, 300, 450, -5, -0, NaN, Infinity]) {
      G.position = position
      const tree = MiniPlayer({ player: { track: { id: 's', title: 'Roads', artist: 'Portishead' }, error: null, playing: true, buffering: false, duration, toggle() {}, next() {} }, onOpen() {} })
      const bar = find(tree, (node) => typeof node.type === 'function' && node.type.name === 'Progress')[0]
      const line = bar.type(bar.props)
      progress.push({ position: num(position), duration: num(duration), transform: line.props.style.transform })
    }
  G.position = 0
  //? afterFailure over its inputs, a queue of `count` with the song failed at `index`
  const failures = []
  for (const code of [0, 1, 2, 3, 4, 5])
    for (const intendsToPlay of [true, false])
      for (const retried of [false, true])
        for (const [count, index] of [[3, 0], [3, 2], [1, 0], [0, -1], [5, 3]]) {
          const queue = { tracks: Array.from({ length: count }, (_, i) => ({ id: `s${i}` })), index }
          const next = Q.nextIndex(queue)
          failures.push([code, intendsToPlay, retried, next, Q.afterFailure({ queue, code, intendsToPlay, retried })])
        }
  //? Now Playing's lines, read out of NowPlaying.tsx and evaluated as written
  const byline = lines('player/NowPlaying.tsx', /const byline = (\[track\.artist, track\.album\]\.filter\(Boolean\)\.join\('[^']*'\))/, 'the byline')
  const bylineOf = expression(byline.found[1], 'track')
  const goTo = lines('player/NowPlaying.tsx', /aria-label=\{`(Go to the album: )\$\{byline\}`\}/, 'Go to album')
  const value = lines('player/NowPlaying.tsx', /aria-valuetext=\{`\$\{clock\(shown\)\}( of )\$\{clock\(length\)\}`\}/, 'the scrubber\'s value')
  const clocks = lines('player/NowPlaying.tsx', /<span>\{clock\(shown\)\}<\/span>\s*<span>(-)\{clock\(length - shown\)\}<\/span>/, 'the clocks')
  const scrubName = lines('player/NowPlaying.tsx', /role="slider"[\s\S]*?aria-label="([^"]+)"/, 'the scrubber\'s name')
  const dismiss = lines('player/NowPlaying.tsx', /const DISMISS_PX = (\d+)/, 'DISMISS_PX')
  const dragStart = lines('player/NowPlaying.tsx', /const DRAG_START_PX = (\d+)/, 'DRAG_START_PX')
  const skipMs = lines('player/usePlayer.ts', /const SKIP_NOTICE_MS = (\d+)/, 'SKIP_NOTICE_MS')
  const failedTitle = lines('player/usePlayer.ts', /skipNotice\(failed\?\.title \?\? '([^']+)', audio\.error\)/, 'a skipped song with no title')
  const afterFailureText = lines('lib/playQueue.ts', /export function afterFailure\([\s\S]*?\n\}/, 'afterFailure')
  const bylines = []
  for (const artist of [undefined, '', 'Portishead']) for (const album of [undefined, '', 'Dummy']) {
    const track = {}
    if (artist !== undefined) track.artist = artist
    if (album !== undefined) track.album = album
    const said = bylineOf(track)
    bylines.push({ artist: artist ?? null, album: album ?? null, byline: said, goTo: goTo.found[1] + said })
  }
  const scrub = []
  for (const [shown, length] of [[0, 0], [12.7, 300], [299.99, 300], [187.9, 245.3], [NaN, 300], [300, 300], [0, NaN], [61, 60], [3600, 7200.5]]) {
    scrub.push({ shown: num(shown), length: num(length), value: SC.clock(shown) + value.found[1] + SC.clock(length), elapsed: SC.clock(shown), remaining: clocks.found[1] + SC.clock(length - shown) })
  }
  return {
    about: 'player/MiniPlayer.tsx miniPlayerLabel ("undefined": no line) and the mini player drawn (its line, its name, its buttons\' names); its hairline (`progress`: the Progress component driven, its transform from the position and the length); lib/playQueue.ts afterFailure as [code, intendsToPlay, retried, next (nextIndex of the queue), action]; Now Playing\'s byline, Go to album and clocks (NowPlaying.tsx, evaluated as written); the constants.',
    made_by: MADE_BY,
    made_from: Object.fromEntries([['ui/src/player/MiniPlayer.tsx', sha256(source('player/MiniPlayer.tsx'))], afterFailureText.from, byline.from, goTo.from, value.from, clocks.from,
      scrubName.from, dismiss.from, dragStart.from, skipMs.from, failedTitle.from]),
    constants: {
      LOAD_RETRY_DELAY_MS: Q.LOAD_RETRY_DELAY_MS, SKIP_NOTICE_MS: Number(skipMs.found[1]), DISMISS_PX: Number(dismiss.found[1]),
      DRAG_START_PX: Number(dragStart.found[1]), MEDIA_ERR_ABORTED: Q.MEDIA_ERR_ABORTED, MEDIA_ERR_NETWORK: Q.MEDIA_ERR_NETWORK,
      MEDIA_ERR_DECODE: Q.MEDIA_ERR_DECODE, MEDIA_ERR_SRC_NOT_SUPPORTED: Q.MEDIA_ERR_SRC_NOT_SUPPORTED, untitled: failedTitle.found[1],
      scrubName: scrubName.found[1],
    },
    labels, drawn,
    pausedButtons: pausedButtons.map((node) => node.props['aria-label']),
    failures, bylines, scrub, progress,
  }
}

/* ===================================================================================== queue.json */

function queueFixture() {
  const tracks = (count, extra = {}) => Array.from({ length: count }, (_, i) => ({ id: `s${i}`, title: `song ${i}`, artist: 'Portishead', album: 'Dummy', albumId: 'al-1', ...extra }))
  const PICKS = [
    { name: 'a song', pick: { label: 'Roads', tracks: tracks(1), albums: [{ id: 'al-1' }] } },
    { name: 'a song, said to be songs', pick: { label: 'Roads', tracks: tracks(1), albums: [{ id: 'al-1' }], as: 'songs' } },
    { name: 'the album', pick: { label: 'Dummy', tracks: tracks(3), albums: [{ id: 'al-1' }], as: 'album' } },
    { name: 'no label', pick: { label: '', tracks: tracks(2), albums: [{ id: 'al-1' }], as: 'album' } },
    { name: 'no songs', pick: { label: 'Dummy', tracks: [], albums: [{ id: 'al-1' }], as: 'album' } },
  ]
  const menus = []
  let words = null
  for (const { name, pick } of PICKS)
    for (const setting of ['auto', 'song', 'album', 'off'])
      for (const how of ['next', 'last'])
        for (const started of [false, true]) {
          G.setting = setting
          G.said.length = 0
          G.remembered.length = 0
          const calls = []
          let closed = 0
          const player = {
            playNext: (queued) => { calls.push(['playNext', queued.map((track) => track.level ?? null)]); return started },
            playLast: (queued) => { calls.push(['playLast', queued.map((track) => track.level ?? null)]); return started },
          }
          const tree = hooks.root(QueueMenu)({ open: true, pick, onClose: () => { closed += 1 }, player })
          const items = find(tree, byClass('app-menu-item'))
          const cancel = find(tree, byClass('app-menu-cancel'))[0]
          const dialog = find(tree, (node) => node.props?.role === 'dialog')[0]
          words = words ?? { items: items.map(text), cancel: text(cancel) }
          items[how === 'next' ? 0 : 1].props.onClick()
          menus.push({ name, label: pick.label, count: pick.tracks.length, as: pick.as ?? null, setting, how, started, title: dialog.props['aria-label'],
            calls, closed, notice: G.said.length ? G.said[0] : null, remembered: G.remembered.slice() })
        }
  //? the album page's two picks, as it makes them
  const albumPick = lines('player/AlbumPage.tsx', /if \(album && tracks\.length\) onQueueMenu\(event as unknown as MouseEvent, (\{ label: album\.name, tracks, albums: \[album\], as: 'album' \})\)/, 'the album\'s pick')
  const songPick = lines('player/AlbumPage.tsx', /onQueueMenu\(event as unknown as MouseEvent, (\{ label: song\.title, tracks: \[toQueueTrack\(song, album\)\], albums: \[album\] \})\)/, 'a song\'s pick')
  const playTap = lines('player/AlbumPage.tsx', /player\.playTracks\(queued\(tracks, '(album)'\), start, shuffle\)/, 'Play\'s queueing')
  return {
    about: 'app/QueueMenu.tsx driven: a pick ({label, count of songs, as - null: not said}) under each setting, Play Next or Play Last, the music started from it or not -> the dialog\'s name, the player call made with each song\'s level (null: none), how often it closed, the notice said, the albums remembered; its words; the album page\'s picks (AlbumPage.tsx, as written).',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('app/QueueMenu.tsx'), whole('player/levelling.ts'),
      ['ui/src/lib/loudness.ts levelFor', sha256(lines('lib/loudness.ts', /export function levelFor\([\s\S]*?\n\}/, 'levelFor').found[0])],
      ['ui/src/lib/upNext.ts queuedWords', sha256(lines('lib/upNext.ts', /export function queuedWords\([\s\S]*?\n\}/, 'queuedWords').found[0])],
      albumPick.from, songPick.from, playTap.from]),
    words,
    picks: { album: albumPick.found[1], song: songPick.found[1], play: playTap.found[1] },
    menus,
  }
}

/* ===================================================================================== main */

async function main() {
  const traces = await signInTraces()
  const launch = launchCases()
  const sessions = await sessionCases()
  const signOut = await signOutTraces()
  const empty = traces[0].steps[0].drawn.problem
  const shownSignIn = hooks.root(SignIn)({ reason: null, onSignedIn() {} })
  const REASONS = [null, '', ' ', 'Sign in to use deadwax.', ' Sign in to use deadwax. ', 'Sign in to use deadwax', 'sign in to use deadwax.',
    BOM + 'Sign in to use deadwax.' + NBSP, NEL + 'x' + NEL, " Navidrome no longer accepts it ", 'Your account was removed.']
  emit('signin.json', {
    about: 'The sign-in screen (app/SignIn.tsx with lib/signIn.ts) driven a step at a time - type a field, Sign in, deadwax answers - and what it draws after each (the reason over the form and its fold, the problem and its fold, the button, the dialog\'s description, the fields), the sign-in sent; the gate\'s launch reason (signInGate.tsx, as written); which 401 ends the session (api/http.ts, heard as the page hears it); Sign out (SignOutRow.tsx) driven; reasonShown and afterSignIn; the words.',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('lib/signIn.ts'), whole('app/SignIn.tsx'), whole('app/SignOutRow.tsx'), launch.from, sessions.from]),
    words: {
      avatar: text(find(shownSignIn, byClass('app-avatar'))[0]),
      title: text(find(shownSignIn, byClass('app-signin-title'))[0]),
      lede: text(find(shownSignIn, byClass('app-signin-lede'))[0]),
      labels: find(shownSignIn, (node) => node.type === 'label').map(text),
      button: text(find(shownSignIn, byClass('app-signin-submit'))[0]),
      empty,
      PLAIN_SIGN_IN: S.PLAIN_SIGN_IN, UNREACHED: S.UNREACHED, SERVER_FAILED: S.SERVER_FAILED, FOR_WHOEVER: S.FOR_WHOEVER,
      BREAK_GLASS_USER: S.BREAK_GLASS_USER,
    },
    reasonShown: REASONS.map((detail) => ({ detail, shown: S.reasonShown(detail) })),
    afterSignIn: [[null, 'ethan'], ['ethan', 'ethan'], ['james', 'ethan'], ['Ethan', 'ethan'], ['ethan ', 'ethan'], [E_ACUTE, E_COMBINING], ['', 'ethan'], ['', '']]
      .map(([before, now]) => ({ before, now, result: S.afterSignIn(before, now) })),
    launch: launch.cases,
    sessions: sessions.cases,
    form: traces,
    signOut,
  }, 4)
  emit('whose.json', whoseFixture(), 2)
  emit('discs.json', discsFixture(), 2)
  emit('format.json', formatFixture(), 3)
  emit('scrub.json', scrubFixture(), 2)
  emit('player.json', playerFixture(), 2)
  emit('queue.json', queueFixture(), 2)

  fs.rmSync(OUT, { recursive: true, force: true })

  if (CHECK) {
    const differ = []
    for (const [name, body] of Object.entries(files)) {
      const at = path.join(FIXTURES, name)
      if (!fs.existsSync(at)) differ.push(`${name} (missing)`)
      else if (fs.readFileSync(at, 'utf8') !== body) differ.push(name)
    }
    if (differ.length) {
      console.log(`The screens' fixtures differ from what the web app's TypeScript answers now: ${differ.join(', ')}.`)
      console.log('Run node ios/scripts/export-screen-vectors.cjs, and see what the Swift ports must follow.')
      process.exit(1)
    }
    console.log(`The screens' ${Object.keys(files).length} fixtures match the web app's TypeScript.`)
    return
  }
  fs.mkdirSync(FIXTURES, { recursive: true })
  for (const [name, body] of Object.entries(files)) fs.writeFileSync(path.join(FIXTURES, name), body)
  console.log(`Wrote ${Object.keys(files).length} fixtures to ${path.relative(REPO, FIXTURES)}: ${Object.entries(files).map(([name, body]) => `${name} ${Math.round(body.length / 1024)} KB`).join(', ')}`)
}

main().catch((caught) => {
  console.error(caught && caught.stack)
  process.exit(1)
})
