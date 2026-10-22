/**
 * Logins in the app and on the main page (2.0.0-player.48): the sign-in gate (app/signInGate.tsx), the
 * sign-in screen (app/SignIn.tsx), You's Sign out (app/SignOutRow.tsx) and its admin rows from the
 * session (app/session.ts), the main page's signed-out notice (components/SignedOutNotice.tsx), and the
 * rules under them (lib/signIn.ts, api/auth.ts, api/http.ts's 401) - compiled with the repo's TypeScript
 * and run against deadwax faked AT FETCH (the real api/http.ts, api/me.ts and api/auth.ts in between),
 * a small stand-in for Preact (JSX as objects, hooks with a cursor, `render` recorded) and a stand-in
 * page (a host element, a layer, <html>'s classes, the address).
 *
 * What it pins:
 *
 *  - THE GATE: who is asked BEFORE anything is drawn; signed in, the app is drawn at once and the
 *    session knows whether this is an admin; signed out, the sign-in screen is drawn ALONE (the app is
 *    not), and the app only once someone signs in. A 401 from ANY request over the running app brings
 *    the sign-in screen back OVER it - the app is never drawn away (no render into its host), only made
 *    inert - so nothing it holds is lost; the same person signing in carries on (nothing reloaded, the app
 *    not drawn again, focus back where it was), someone else starts the app again. A 401 for a request
 *    sent BEFORE that sign-in brings nothing back, through get and fetchOk alike. A song that fails to
 *    load (a media element's error, heard on the document in the CAPTURE phase - errors are dispatched
 *    here as the browser does, to capture listeners only) asks who is signed in; nothing else's error
 *    does. Asked again as the page comes back to the front or is shown again from the back-forward
 *    cache - the sign-in screen showing included, which a 200 then takes away. deadwax not answering
 *    at launch is said on the sign-in screen; over the running app (no 401) it leaves the app alone.
 *    The sign-in coming up leaves full screen (the visualizer's), and focuses the name field once the
 *    browser has. `?return=/` goes back to the main page once signed in - replacing the sign-in in the
 *    history - and nowhere else.
 *  - THE SCREEN: a user name and a password field, labelled, with the autocomplete words password
 *    managers read and no capitals or corrections on the name; read from the fields as sent (a password
 *    manager's fill needn't say so); deadwax's own words when a sign-in fails (a wrong password, too
 *    many tries) in a live region that is always in the page; the password typed gone once its sign-in
 *    has answered; empty fields said, and nothing sent; a 401 from the sign-in itself is no "signed
 *    out"; why it is showing said above the form, and as the dialog's description - but not the plain
 *    "sign in".
 *  - SIGN OUT: in You only with logins on, naming who - the break-glass admin as such; it signs out,
 *    then starts the app again; deadwax not answering said, and nothing started again. Admin rows from
 *    the session's word until /me answers.
 *  - THE MAIN PAGE: on any 401 a notice over the page, the page behind inert, a link to the app's
 *    sign-in that comes back (`/player/?return=/`); /me asked once as it loads only with logins on, and
 *    again while the notice shows as the page comes back (Back, the front) - signed in by then, the
 *    page starts again.
 *  - Off is today: player/main.tsx draws the app at once with no ask when the page has no mark - and
 *    reloads it at its first 401 (logins switched on under it), once, not again within a minute (noted
 *    for the tab; reloading regardless where the browser keeps nothing).
 *
 * Run it with:  node ui/test/signin.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const SRC = path.join(UI, 'src')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-signin-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/signInGate.tsx', 'src/app/You.tsx', 'src/components/SignedOutNotice.tsx',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

/* ===== the stand-ins ===== */

fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `
exports.Fragment = 'fragment'
exports.createContext = () => ({ Provider: 'provider' })
exports.render = (vnode, host) => globalThis.__signin.rendered.push([host, vnode])
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
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
//? the app itself is not what is tested here - only whether, and when, it is drawn
fs.writeFileSync(path.join(OUT, 'app/App.js'), `exports.App = function App() { return null }\n`)
//? You's other neighbours, as you.sim fakes them
fs.writeFileSync(path.join(OUT, 'api/connections.js'), `
exports.pingMusicBrainz = () => new Promise(() => {})
exports.pingSlskd = () => new Promise(() => {})
`)
fs.writeFileSync(path.join(OUT, 'player/api.js'), `exports.navidromeStatus = () => new Promise(() => {})\n`)
fs.writeFileSync(path.join(OUT, 'app/useGetSettings.js'), `
exports.useGetSettings = () => ({ settings: null, canSave: true, problem: null })
exports.askGetSettings = () => Promise.resolve()
exports.chooseGetSettings = () => Promise.resolve()
`)
fs.writeFileSync(path.join(OUT, 'app/context.js'), `
exports.usePlayerState = () => ({ maxRate: '48000', gapless: false })
exports.usePlayerActions = () => ({ setMaxRate() {} })
`)

/* ===== deadwax, faked at fetch ===== */

const sent = []
let answer = () => ({ status: 200, body: {} })
globalThis.fetch = async (url, init = {}) => {
  sent.push({ url, method: init.method ?? 'GET', body: init.body ?? null })
  const reply = answer(url, init)
  if (reply instanceof Error) throw reply
  return { ok: reply.status < 400, status: reply.status, json: async () => reply.body }
}
const ME = (user, admin) => ({ user, admin, auth: 'on', version: '2.0.0-player.48' })

/* ===== the page, faked ===== */

globalThis.__signin = { rendered: [] }
const rendered = globalThis.__signin.rendered
const classes = new Set()
let pageListeners = {}
//? each listener's options, beside it (a media error is heard only by a listener asking for capture)
let pageOptions = {}
let appended = []
let assigned = []
let replaced = []
let reloads = 0
let mainContainer = null
const element = (tag) => ({ tag, id: '', inert: false, attrs: {}, isConnected: true, focused: [], focus(options) { this.focused.push(options) }, setAttribute(k, v) { this.attrs[k] = v }, removeAttribute(k) { delete this.attrs[k] }, querySelector: () => null })
//? what api/http.ts's caller can't fake: a media element, for the gate's "a song failed" (instanceof)
globalThis.HTMLMediaElement = class HTMLMediaElement {}
globalThis.document = {
  createElement: element,
  body: { appendChild: (el) => appended.push(el) },
  documentElement: { classList: { add: (c) => classes.add(c), remove: (c) => classes.delete(c) } },
  addEventListener: (type, fn, options) => { (pageListeners[type] ??= []).push(fn); (pageOptions[type] ??= []).push(options) },
  removeEventListener: (type, fn) => {
    const at = (pageListeners[type] ?? []).indexOf(fn)
    if (at >= 0) { pageListeners[type].splice(at, 1); pageOptions[type].splice(at, 1) }
  },
  visibilityState: 'visible',
  //? full screen (the desktop visualizer's): what is in it, and the way out
  fullscreenElement: null,
  exited: 0,
  exitFullscreen() { this.exited += 1; return Promise.resolve() },
  activeElement: null,
  querySelector: () => null,
  getElementById: (id) => (id === 'main-container' ? mainContainer : null),
}
globalThis.location = { search: '', assign: (to) => assigned.push(to), replace: (to) => replaced.push(to), reload: () => { reloads += 1 } }
//? the window's events (api/http.ts dispatches, api/auth.ts listens): a fresh target per case, so a gate
//? from an earlier case hears nothing of a later one
function freshWindow() {
  const target = new EventTarget()
  globalThis.addEventListener = target.addEventListener.bind(target)
  globalThis.removeEventListener = target.removeEventListener.bind(target)
  globalThis.dispatchEvent = target.dispatchEvent.bind(target)
}

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))
//? an element's error as the browser sends it to the document: it doesn't bubble (a media element's
//? never does), so only a listener registered for the CAPTURE phase hears it
const captures = (options) => options === true || !!options?.capture
function pageError(target) {
  const listeners = [...(pageListeners.error ?? [])]
  const options = [...(pageOptions.error ?? [])]
  listeners.forEach((fn, at) => { if (captures(options[at])) fn({ target }) })
}
//? the browser showing a page again from its back-forward cache (persisted), or loading it afresh
function pageshow(persisted) {
  const event = new Event('pageshow')
  Object.defineProperty(event, 'persisted', { value: persisted })
  globalThis.dispatchEvent(event)
}

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { startWithLogins } = require(path.join(OUT, 'app/signInGate.js'))
const session = require(path.join(OUT, 'app/session.js'))
const access = require(path.join(OUT, 'app/access.js'))
const rules = require(path.join(OUT, 'lib/signIn.js'))
const auth = require(path.join(OUT, 'api/auth.js'))
const http = require(path.join(OUT, 'api/http.js'))
const { You } = require(path.join(OUT, 'app/You.js'))
const { SignIn } = require(path.join(OUT, 'app/SignIn.js'))
const { SignOutRow } = require(path.join(OUT, 'app/SignOutRow.js'))
const notice = require(path.join(OUT, 'components/SignedOutNotice.js'))

const name = (vnode) => (vnode && typeof vnode.type === 'function' ? vnode.type.name : vnode === null ? null : String(vnode?.type))
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

/** A fresh gate over a fresh page, deadwax answering /me with `meAnswer`. */
async function gate(meAnswer, search = '') {
  freshWindow()
  rendered.length = 0
  classes.clear()
  pageListeners = {}
  pageOptions = {}
  appended = []
  assigned = []
  replaced = []
  reloads = 0
  sent.length = 0
  document.activeElement = null
  session.setSessionMe(null)
  location.search = search
  answer = meAnswer
  const host = element('div')
  startWithLogins(host)
  await settle()
  const layer = appended[0]
  const into = (target) => rendered.filter(([h]) => h === target).map(([, vnode]) => vnode)
  return { host, layer, app: () => into(host), screen: () => into(layer) }
}
const isSignIn = (vnode) => name(vnode) === 'SignIn'
const signedOutAnswer = (detail) => (url) => (String(url).endsWith('/deadwax/me') ? { status: 401, body: { detail } } : { status: 200, body: {} })

async function main() {
  console.log('\nlib/signIn.ts')
  {
    check('a failure in deadwax\'s own words', rules.signInProblem(new http.ApiError(429, 'Too many tries for ethan - wait 42 seconds and try again.', 'x')),
      'Too many tries for ethan - wait 42 seconds and try again.')
    check('...a wordless 401 and 429 said plainly', [rules.signInProblem(new http.ApiError(401, null, 'x')), rules.signInProblem(new http.ApiError(429, null, 'x'))],
      ["That user name and password didn't work.", 'Too many tries - wait a minute and try again.'])
    check('...no answer at all', rules.signInProblem(new TypeError('Failed to fetch')),
      "deadwax didn't answer - check you can reach it (on your network, or over WireGuard) and try again.")
    check('the plain "sign in" isn\'t said again above the form; why it ended is',
      [rules.reasonShown('Sign in to use deadwax.'), rules.reasonShown(null), rules.reasonShown(' Navidrome no longer accepts it ')], [null, null, 'Navidrome no longer accepts it'])
    check('?return=/ goes back to the main page - and nothing else does',
      ['?return=/', '?return=%2F', '?return=//evil.example', '?return=https://evil.example/', '?return=/settings', ''].map(rules.returnTarget), ['/', '/', null, null, null, null])
    check('the same person carries on, someone else starts again, a first sign-in carries on',
      [rules.afterSignIn('ethan', 'ethan'), rules.afterSignIn('james', 'ethan'), rules.afterSignIn(null, 'ethan')], ['carry-on', 'start-again', 'carry-on'])
  }

  console.log('\napi/auth.ts and api/http.ts: the mark, and a 401 heard')
  {
    const doc = (content) => ({ querySelector: (selector) => (selector === 'meta[name="deadwax-auth"]' && content ? { getAttribute: () => content } : null) })
    check('logins on only when the page carries the mark', [auth.loginsOn(doc('on')), auth.loginsOn(doc(null)), auth.loginsOn(doc('off')), auth.loginsOn(undefined)], [true, false, false, false])
    freshWindow()
    const heard = []
    const stop = auth.onSignedOut((detail) => heard.push(detail))
    answer = (url) => (String(url).includes('/auth/') ? { status: 401, body: { detail: 'wrong' } }
      : String(url).includes('/forbidden') ? { status: 403, body: { detail: 'admin only' } } : { status: 401, body: { detail: 'You\'ve been signed out - sign in again.' } })
    await http.get('/me').catch(() => {})
    await http.fetchOk('/library/albums').catch(() => {})
    await http.post('/auth/login', { username: 'a', password: 'b' }).catch(() => {})
    await http.get('/forbidden').catch(() => {})
    check('a 401 from any route is heard, with deadwax\'s words; the sign-in\'s own 401 and a 403 are not', heard,
      ['You\'ve been signed out - sign in again.', 'You\'ve been signed out - sign in again.'])
    stop()
    await http.get('/me').catch(() => {})
    check('...and no more once stopped', heard.length, 2)
  }

  console.log('\nthe gate: signed out at launch - the sign-in alone')
  {
    const page = await gate(signedOutAnswer('Sign in to use deadwax.'))
    check('/deadwax/me asked first, and nothing else', sent.map((request) => `${request.method} ${request.url}`), ['GET /deadwax/me'])
    check('the sign-in screen drawn into a layer of its own, the app not drawn at all', [page.screen().map(name), page.app().map(name)], [['SignIn'], []])
    check('...over a page held still, with the plain "sign in" as its reason (not said again)', [classes.has('has-signin'), page.screen()[0].props.reason], [true, 'Sign in to use deadwax.'])
    check('...nothing is made inert while there is no app under it', page.host.inert, false)

    page.screen()[0].props.onSignedIn(ME('ethan', false))
    check('signed in: the screen goes and the app is drawn, once', [page.screen().map(name), page.app().map(name)], [['SignIn', null], ['App']])
    //? (2.0.0-player.61) by its permissions - an answer from before them (no list) by its `admin`: none for a user
    check('...knowing already this is no admin', [session.sessionMe()?.user, [...session.permissionsUntilAsked()]], ['ethan', []])
    check('...the page free again', classes.has('has-signin'), false)

    console.log('\nthe gate: a session ending mid-use - the sign-in over the app, the app kept under it')
    //? what had focus in the app as the session ended - You's Sign out, say
    const opener = element('button')
    document.activeElement = opener
    answer = () => ({ status: 401, body: { detail: 'Navidrome no longer accepts the login you signed in with.' } })
    await http.post('/navidrome/scrobble/so-1?submission=true').catch(() => {})
    check('any 401 brings the screen back, saying why', [page.screen().map(name), page.screen().at(-1).props.reason],
      [['SignIn', null, 'SignIn'], 'Navidrome no longer accepts the login you signed in with.'])
    check('...the app never drawn away - only made inert and hidden from assistive tech under it',
      [page.app().map(name), page.host.inert, page.host.attrs['aria-hidden']], [['App'], true, 'true'])
    await http.get('/navidrome/albums').catch(() => {})
    check('...a second 401 draws no second screen', page.screen().filter((vnode) => name(vnode) === 'SignIn').length, 2)
    const visible = pageListeners.visibilitychange?.[0]
    const asksBefore = sent.length
    visible?.()
    await settle()
    check('...coming back to the front asks again while it shows - still signed out, the screen left as it was',
      [sent.length - asksBefore, sent.at(-1).url, page.screen().filter(isSignIn).length, page.screen().at(-1).props.reason],
      [1, '/deadwax/me', 2, 'Navidrome no longer accepts the login you signed in with.'])

    //? a poll that left under the ended session, its answer held until after the sign-in below - sent with
    //? the cookie that sign-in replaces
    let release = () => {}
    const held = new Promise((resolve) => { release = resolve })
    const fetchNow = globalThis.fetch
    globalThis.fetch = async () => { await held; return { ok: false, status: 401, json: async () => ({ detail: "You've been signed out - sign in again." }) } }
    const late = http.get('/download/jobs').catch(() => {})
    //? ...and the library's scan, which goes through fetchOk - its own copy of the 401's handling
    const lateScan = http.fetchOk('/library/albums').catch(() => {})
    globalThis.fetch = fetchNow

    page.screen().at(-1).props.onSignedIn(ME('ethan', false))
    check('the same person signs in again: carried on - nothing reloaded, the app not drawn again, live again',
      [reloads, page.app().map(name), page.host.inert, 'aria-hidden' in page.host.attrs, page.screen().at(-1)], [0, ['App'], false, false, null])
    check('...focus back where it was in the app, the page not scrolled to it', opener.focused, [{ preventScroll: true }])
    release()
    await late
    await lateScan
    await settle()
    check('...and a 401 for a request sent BEFORE the sign-in brings nothing back - get and fetchOk alike', [classes.has('has-signin'), page.host.inert, page.screen().filter(isSignIn).length],
      [false, false, 2])

    console.log('\nthe gate: coming back to the front')
    answer = signedOutAnswer('Your sign-in ran out after 30 days without use - sign in again.')
    visible()
    await settle()
    check('who is asked again as the app comes to the front, and a 401 brings the screen back',
      [sent.at(-1).url, page.screen().at(-1).props.reason], ['/deadwax/me', 'Your sign-in ran out after 30 days without use - sign in again.'])

    page.screen().at(-1).props.onSignedIn(ME('james', true))
    check('someone else signs in: the app started again (what it holds was the other person\'s)', reloads, 1)
  }

  console.log('\nthe gate: signed in at launch')
  {
    const page = await gate(() => ({ status: 200, body: ME('james', true) }))
    check('the app drawn at once, no sign-in screen, the session an admin\'s', [page.app().map(name), page.screen().map(name), [...session.permissionsUntilAsked()]],
      [['App'], [], ['request', 'edit', 'library', 'downloads', 'server', 'people']])
  }

  console.log('\nthe gate: the main page sent you')
  {
    const signedIn = await gate(() => ({ status: 200, body: ME('james', true) }), '?return=/')
    check('already signed in: straight back to the main page, the app not drawn', [replaced, signedIn.app().length], [['/'], 0])
    const signedOut = await gate(signedOutAnswer('Sign in to use deadwax.'), '?return=/')
    signedOut.screen()[0].props.onSignedIn(ME('ethan', false))
    check('signed in from the screen: back to the main page - REPLACING the sign-in, so Back skips it', [replaced, assigned, signedOut.app().length], [['/'], [], 0])
    const elsewhere = await gate(signedOutAnswer('Sign in to use deadwax.'), '?return=https://evil.example/')
    elsewhere.screen()[0].props.onSignedIn(ME('ethan', false))
    check('...and anywhere else is ignored: the app drawn here', [replaced, assigned, elsewhere.app().map(name)], [[], [], ['App']])
  }

  console.log('\nthe gate: a sign-in left showing after signing in elsewhere')
  {
    const page = await gate(signedOutAnswer('Sign in to use deadwax.'))
    answer = () => ({ status: 200, body: ME('ethan', false) })
    pageListeners.visibilitychange[0]()
    await settle()
    check('coming back to the front, signed in elsewhere: the screen goes and the app is drawn',
      [page.screen().map(name), page.app().map(name), classes.has('has-signin')], [['SignIn', null], ['App'], false])

    const back = await gate(signedOutAnswer('Sign in to use deadwax.'), '?return=/')
    answer = () => ({ status: 200, body: ME('james', true) })
    const asked = sent.length
    pageshow(false)
    await settle()
    check('a page loaded afresh asks nothing more of pageshow', sent.length, asked)
    pageshow(true)
    await settle()
    check('shown again from the back-forward cache, signed in by then: on to the main page, replacing it',
      [sent.at(-1).url, replaced, assigned, back.app().length], ['/deadwax/me', ['/'], [], 0])
  }

  console.log('\nthe gate: what it hears is what the app draws by (2.0.0-player.61 review)')
  {
    access.forgetAccess()
    const withList = (list) => ({ ...ME('ethan', false), permissions: list, permissions_unverified: false })
    await gate(() => ({ status: 200, body: withList(['request']) }))
    //? App's own ask as the desktop frame shows - once; after it, nothing on a desktop asks /me but the gate
    access.noteAccess(withList(['request']))
    check('the first answer noted', [...access.accessNow().permissions], ['request'])
    answer = () => ({ status: 200, body: withList(['request', 'edit']) })
    pageListeners.visibilitychange[0]()
    await settle()
    check('an admin ticked Edit albums: the next re-ask (back to the front) is what the app draws by - no reload, no You',
      [...access.accessNow().permissions], ['request', 'edit'])
    answer = () => ({ status: 200, body: withList([]) })
    pageError(new HTMLMediaElement())
    await settle()
    check('...and one taken away is gone at the re-ask a failing song makes', [...access.accessNow().permissions], [])
    access.forgetAccess()

    //? (2.0.0-player.63) Info's Debug is an admin's: the store says who is one - from /me, and before /me the session
    session.setSessionMe(ME('ethan', false))
    check('Debug\'s role: an ordinary person\'s session, before /me answers here - not an admin', access.accessNow().admin, false)
    session.setSessionMe(ME('james', true))
    check('...a Navidrome admin\'s session - an admin', access.accessNow().admin, true)
    session.setSessionMe(null)
    check('...no session (logins off): everyone is the admin, as ever', access.accessNow().admin, true)
    access.noteAccess({ ...ME('james', true), permissions: ['request', 'edit', 'library', 'downloads', 'server', 'people'] })
    check('/me says an admin: an admin', access.accessNow().admin, true)
    access.noteAccess({ ...ME('james', false), permissions: ['request', 'edit', 'library', 'downloads', 'server'] })
    check('...the role taken away (every box ticked still): not one', access.accessNow().admin, false)
    access.noteAccess({ user: 'local', auth: 'off', version: 'x' })
    check('...logins off: the admin, by logins being off alone', access.accessNow().admin, true)
    access.forgetAccess()
  }

  console.log('\nthe gate: a song that fails to load asks who is signed in')
  {
    const page = await gate(() => ({ status: 200, body: ME('ethan', false) }))
    check('heard on the document in the CAPTURE phase - a media element\'s error doesn\'t bubble, so nothing else hears it',
      (pageOptions.error ?? []).map(captures), [true])
    sent.length = 0
    pageError(element('img'))
    check('a picture that didn\'t load asks nothing', sent.length, 0)
    answer = signedOutAnswer('Navidrome no longer accepts the login you signed in with.')
    pageError(new HTMLMediaElement())
    await settle()
    check('a song that didn\'t: /me asked, and its 401 brings the sign-in over the app, saying why',
      [sent.map((request) => request.url), page.screen().at(-1)?.props.reason, page.host.inert], [['/deadwax/me'], 'Navidrome no longer accepts the login you signed in with.', true])
    sent.length = 0
    pageError(new HTMLMediaElement())
    check('...the next song failing under it asks nothing more', sent.length, 0)
  }

  console.log('\nthe gate: deadwax not answering over the running app')
  {
    //? the phone unlocked while WireGuard is still reconnecting, or a song failing while deadwax can't be
    //? reached: /me fails, but not with a 401 - nobody was signed out, and the app is left as it is
    const page = await gate(() => ({ status: 200, body: ME('ethan', false) }))
    const asked = sent.length
    answer = () => new TypeError('Failed to fetch')
    pageListeners.visibilitychange[0]()
    await settle()
    pageError(new HTMLMediaElement())
    await settle()
    answer = () => ({ status: 503, body: { detail: "deadwax can't read its database" } })
    pageListeners.visibilitychange[0]()
    await settle()
    check('asked each time - and no sign-in drawn, nothing made inert, the page not held',
      [sent.length - asked, page.screen().filter(isSignIn).length, page.host.inert, classes.has('has-signin'), page.app().map(name)], [3, 0, false, false, ['App']])
  }

  console.log('\nthe gate: a session ending under the visualizer in full screen')
  {
    //? the desktop visualizer's full screen is the browser's top layer: the sign-in, outside it, wouldn't show
    const page = await gate(() => ({ status: 200, body: ME('james', true) }))
    const field = element('input')
    page.layer.querySelector = (selector) => (selector === 'input' ? field : null)
    document.fullscreenElement = element('div')
    document.exited = 0
    answer = () => ({ status: 401, body: { detail: 'Navidrome no longer accepts the login you signed in with.' } })
    await http.get('/navidrome/albums').catch(() => {})
    check('the sign-in comes up and full screen is left, once', [page.screen().filter(isSignIn).length, document.exited], [1, 1])
    check('...the name field not focused while the browser is still in full screen (it couldn\'t take it)', field.focused, [])
    document.fullscreenElement = null
    for (const fn of [...(pageListeners.fullscreenchange ?? [])]) fn({})
    check('...and focused once the browser has left', field.focused, [{ preventScroll: true }])
    check('...the full-screen listeners gone with it', [(pageListeners.fullscreenchange ?? []).length, (pageListeners.webkitfullscreenchange ?? []).length], [0, 0])
    const plain = await gate(() => ({ status: 200, body: ME('james', true) }))
    document.exited = 0
    answer = () => ({ status: 401, body: { detail: 'Navidrome no longer accepts the login you signed in with.' } })
    await http.get('/navidrome/albums').catch(() => {})
    check('nothing in full screen: nothing left', [plain.screen().filter(isSignIn).length, document.exited, (pageListeners.fullscreenchange ?? []).length], [1, 0, 0])
  }

  console.log('\nthe gate: deadwax not answering at launch')
  {
    const page = await gate(() => new TypeError('Failed to fetch'))
    check('said on the sign-in screen, the app not drawn', [page.screen()[0]?.props.reason, page.app().length],
      ["deadwax didn't answer - check you can reach it (on your network, or over WireGuard) and try again.", 0])
    const closed = await gate(() => ({ status: 503, body: { detail: 'Logins are on, but DEADWAX_SECRET_KEY isn\'t set, so deadwax can\'t sign anyone in.' } }))
    check('...and logins that can\'t work, in deadwax\'s words', closed.screen()[0]?.props.reason, 'Logins are on, but DEADWAX_SECRET_KEY isn\'t set, so deadwax can\'t sign anyone in.')
  }

  console.log('\nthe sign-in screen')
  {
    freshWindow()
    const heard = []
    auth.onSignedOut((detail) => heard.push(detail))
    const signedIn = []
    const draw = hooks.root(SignIn)
    let tree = null
    const props = { reason: 'Navidrome no longer accepts the login you signed in with.', onSignedIn: (me) => signedIn.push(me) }
    const redraw = () => { tree = draw(props); draw.commit(); return tree }
    redraw()
    const inputs = find(tree, (node) => node.type === 'input')
    check('a user name and a password field', inputs.map((input) => [input.props.id, input.props.name, input.props.type, input.props.autocomplete]),
      [['app-signin-user', 'username', 'text', 'username'], ['app-signin-password', 'password', 'password', 'current-password']])
    check('...the name with no capitals, corrections or spelling marks', [inputs[0].props.autocapitalize, inputs[0].props.autocorrect, inputs[0].props.spellcheck], ['none', 'off', false])
    check('...each labelled', find(tree, (node) => node.type === 'label').map((label) => [label.props.for, text(label)]),
      [['app-signin-user', 'User name'], ['app-signin-password', 'Password']])
    check('a dialog over the page, named by deadwax\'s name and described by why it shows',
      [tree.props.role, tree.props['aria-modal'], tree.props['aria-labelledby'], tree.props['aria-describedby'], find(tree, byClass('app-signin-reason'))[0]?.props.id],
      ['dialog', 'true', 'app-signin-title', 'app-signin-reason', 'app-signin-reason'])
    check('why it is showing, above the form', find(tree, byClass('app-signin-reason')).map(text), ['Navidrome no longer accepts the login you signed in with.'])
    const region = find(tree, byClass('app-signin-problem'))[0]
    check('the failure\'s live region is in the page before anything failed', [region?.props['aria-live'], text(region)], ['assertive', ''])

    const form = find(tree, (node) => node.type === 'form')[0]
    const submitWith = (username, password) => form.props.onSubmit({
      preventDefault() {}, currentTarget: { elements: { namedItem: (field) => ({ value: { username, password }[field] }) } },
    })
    sent.length = 0
    submitWith('', 'x')
    redraw()
    check('empty fields said, and nothing sent', [find(tree, byClass('app-error')).map(text), sent.length], [['Type your user name and your password.'], 0])

    answer = () => ({ status: 401, body: { detail: "That user name and password didn't work." } })
    find(tree, (node) => node.type === 'input')[1].props.onInput({ currentTarget: { value: 'the-password' } })
    redraw()
    check('the password typed is in its field until it is sent', find(tree, (node) => node.type === 'input')[1].props.value, 'the-password')
    submitWith(' Ethan ', 'the-password')
    redraw()
    check('the fields read as sent (a password manager\'s fill needn\'t say so), the name trimmed',
      sent.map((request) => [request.method, request.url, JSON.parse(request.body)]), [['POST', '/deadwax/auth/login', { username: 'Ethan', password: 'the-password' }]])
    check('...the button says it is signing in, and can\'t be pressed twice', [text(find(tree, byClass('app-signin-submit'))[0]), find(tree, byClass('app-signin-submit'))[0].props.disabled], ['Signing in…', true])
    await settle()
    redraw()
    check('a wrong password in deadwax\'s words, the password gone', [find(tree, byClass('app-error')).map(text), find(tree, (node) => node.type === 'input')[1].props.value],
      [["That user name and password didn't work."], ''])
    check('...and the sign-in\'s own 401 is no "signed out"', heard, [])

    answer = () => ({ status: 429, body: { detail: 'Too many tries for ethan - wait 51 seconds and try again.' } })
    submitWith('ethan', 'again')
    await settle()
    redraw()
    check('too many tries, and how long to wait', find(tree, byClass('app-error')).map(text), ['Too many tries for ethan - wait 51 seconds and try again.'])

    answer = () => ({ status: 200, body: ME('ethan', false) })
    submitWith('ethan', 'right-one')
    await settle()
    redraw()
    check('signed in: handed on, the failure cleared', [signedIn.map((me) => me.user), find(tree, byClass('app-error')).length], [['ethan'], 0])
    const plain = hooks.root(SignIn)({ reason: 'Sign in to use deadwax.', onSignedIn() {} })
    check('the plain "sign in" isn\'t said above the form, nor describes the dialog', [find(plain, byClass('app-signin-reason')).length, plain.props['aria-describedby'] ?? null], [0, null])
  }

  console.log('\nYou: Sign out with logins on, and the admin rows from the session')
  {
    freshWindow()
    const draw = hooks.root(You)
    const LOOK = { opensAs: 'cover', onOpensAs() {}, windDown: false, onWindDown() {} }
    let tree = null
    const redraw = (props) => { tree = draw(props); draw.commit(); return tree }
    const managing = () => find(tree, (node) => node.type === 'section' && node.props?.['aria-labelledby'] === 'app-managing-title').length
    const signOut = () => find(tree, (node) => name(node) === 'SignOutRow')

    //? (2.0.0-player.61) what the app draws by is the access store's - the session's word until /me answers
    access.forgetAccess()
    session.setSessionMe(ME('ethan', false))
    const real = globalThis.fetch
    //? /me never answers here, so only the session can say
    globalThis.fetch = async (url, init) => (String(url).endsWith('/deadwax/me') ? new Promise(() => {}) : real(url, init))
    redraw({ shown: true, current: true, ...LOOK })
    check('before /me answers here: a user\'s session draws no admin rows', managing(), 0)
    session.setSessionMe(null)
    redraw({ shown: true, current: true, ...LOOK })
    check('...with logins off (no session) everyone is the admin, as ever', managing(), 1)
    globalThis.fetch = real
  }
  {
    //? You with /me answered: off, and on as ethan
    const real = globalThis.fetch
    const youWith = async (me) => {
      globalThis.fetch = async (url, init) => (String(url).endsWith('/deadwax/me') ? { ok: true, status: 200, json: async () => me } : real(url, init))
      const draw = hooks.root(You)
      const LOOK = { opensAs: 'cover', onOpensAs() {}, windDown: false, onWindDown() {} }
      draw({ shown: true, current: true, ...LOOK }); draw.commit()
      await settle()
      const tree = draw({ shown: true, current: true, ...LOOK }); draw.commit()
      globalThis.fetch = real
      return tree
    }
    const off = await youWith({ user: 'local', admin: true, auth: 'off', version: 'v' })
    check('logins off: no Sign out', find(off, (node) => name(node) === 'SignOutRow').length, 0)
    const on = await youWith(ME('ethan', false))
    check('logins on: Sign out, naming who; no admin rows for a user', [find(on, (node) => name(node) === 'SignOutRow').map((node) => node.props.user),
      find(on, (node) => node.type === 'section' && node.props?.['aria-labelledby'] === 'app-managing-title').length], [['ethan'], 0])
  }

  console.log('\nSign out')
  {
    const draw = hooks.root(SignOutRow)
    let tree = draw({ user: 'ethan' })
    check('a row saying Sign out, naming who', text(find(tree, (node) => node.type === 'button')[0]), 'Sign outethan')
    const footnote = (user) => text(find(hooks.root(SignOutRow)({ user }), byClass('app-footnote')).at(-1))
    check('...signed in with a Navidrome account - or, for the break-glass admin, with its password and its 12 hours',
      [footnote('ethan'), footnote('deadwax'), footnote('admin')],
      ["Signed in as ethan, with your Navidrome account. Signing out ends this device's session and stops what's playing.",
        "Signed in as deadwax, with the break-glass password - it lasts 12 hours. Signing out ends this device's session and stops what's playing.",
        //? (2.0.0-player.61) break-glass is `deadwax` now: Navidrome's own `admin` is a person like any other
        "Signed in as admin, with your Navidrome account. Signing out ends this device's session and stops what's playing."])
    reloads = 0
    sent.length = 0
    answer = () => ({ status: 200, body: { signed_out: true } })
    find(tree, (node) => node.type === 'button')[0].props.onClick()
    await settle()
    check('signs out, then starts the app again (at the sign-in)', [sent.map((request) => `${request.method} ${request.url}`), reloads], [['POST /deadwax/auth/logout'], 1])
    answer = () => ({ status: 503, body: { signed_out: true, problem: 'couldn\'t forget it' } })
    find(hooks.root(SignOutRow)({ user: 'ethan' }), (node) => node.type === 'button')[0].props.onClick()
    await settle()
    check('...deadwax answering with a failure still cleared the cookie: started again', reloads, 2)
    answer = () => new TypeError('Failed to fetch')
    const again = hooks.root(SignOutRow)
    find(again({ user: 'ethan' }), (node) => node.type === 'button')[0].props.onClick()
    await settle()
    tree = again({ user: 'ethan' })
    check('...no answer at all: said, and nothing started again', [find(tree, byClass('app-error')).map(text), reloads],
      [["deadwax didn't answer, so you're still signed in - try again."], 2])
  }

  console.log('\nthe main page signed out')
  {
    const tree = notice.SignedOutNotice({ reason: 'Sign in to use deadwax.' })
    const link = find(tree, (node) => node.type === 'a')[0]
    check('a plain message, and a link to the app\'s sign-in that comes back here', [text(find(tree, byClass('signed-out-title'))[0]), link.props.href, text(link)],
      ['You\'re signed out', '/player/?return=/', 'Sign in'])
    check('...the plain "sign in" put in its own words; why it ended said as deadwax said it',
      [text(find(tree, byClass('signed-out-text'))[0]), text(find(notice.SignedOutNotice({ reason: 'Your sign-in ran out.' }), byClass('signed-out-text'))[0])],
      ['deadwax has logins on, so sign in to use it.', 'Your sign-in ran out.'])

    freshWindow()
    rendered.length = 0
    appended = []
    sent.length = 0
    mainContainer = element('div')
    notice.watchSignedOut()
    check('logins off (no mark): nothing asked', sent.length, 0)
    answer = () => ({ status: 401, body: { detail: 'Sign in to use deadwax.' } })
    await http.get('/download/jobs').catch(() => {})
    await http.get('/download/jobs').catch(() => {})
    check('a 401: the notice drawn once, over a page made inert', [rendered.map(([, vnode]) => name(vnode)), appended.length, 'inert' in mainContainer.attrs], [['SignedOutNotice'], 1, true])

    freshWindow()
    sent.length = 0
    const marked = document.querySelector
    document.querySelector = (selector) => (selector === 'meta[name="deadwax-auth"]' ? { getAttribute: () => 'on' } : null)
    answer = () => ({ status: 200, body: ME('james', true) })
    reloads = 0
    notice.watchSignedOut()
    await settle()
    pageshow(true)
    await settle()
    check('logins on: /me asked once as the page loads - and, signed in, not again as it is shown again', [sent.map((request) => request.url), reloads], [['/deadwax/me'], 0])

    freshWindow()
    sent.length = 0
    rendered.length = 0
    appended = []
    pageListeners = {}
    pageOptions = {}
    mainContainer = element('div')
    answer = () => ({ status: 401, body: { detail: 'Sign in to use deadwax.' } })
    notice.watchSignedOut()
    await settle()
    check('logins on, signed out as it loads: the notice', [rendered.map(([, vnode]) => name(vnode)), 'inert' in mainContainer.attrs], [['SignedOutNotice'], true])
    answer = () => ({ status: 200, body: ME('james', true) })
    pageshow(true)
    await settle()
    check('...shown again from the back-forward cache (Back, after signing in), signed in by then: the page starts again',
      [sent.at(-1).url, reloads], ['/deadwax/me', 1])
    pageListeners.visibilitychange?.[0]?.()
    await settle()
    check('...and coming back to the front, the same', reloads, 2)
    document.querySelector = marked
  }

  console.log('\nthe app drawn with logins off, and logins switched on under it')
  {
    //? the home-screen app iOS kept in memory, a tab left open: no mark, no gate - its first 401 reloads it
    //? (the page that comes back carries the mark), once, and not again within a minute
    const stored = new Map()
    globalThis.sessionStorage = { getItem: (key) => stored.get(key) ?? null, setItem: (key, value) => stored.set(key, String(value)) }
    const { reloadWhenLoginsComeOn, RELOAD_AGAIN_MS } = require(path.join(OUT, 'app/signInGate.js'))
    const signedOutEverywhere = () => ({ status: 401, body: { detail: 'Sign in to use deadwax.' } })
    freshWindow()
    reloads = 0
    sent.length = 0
    reloadWhenLoginsComeOn()
    check('nothing asked while nothing is refused (logins off answer no 401)', [sent.length, reloads], [0, 0])
    answer = () => ({ status: 403, body: { detail: 'admin only' } })
    await http.get('/settings').catch(() => {})
    check('...nor for a 403', reloads, 0)
    answer = signedOutEverywhere
    await http.get('/navidrome/albums').catch(() => {})
    await http.fetchOk('/library/albums').catch(() => {})
    await http.get('/me').catch(() => {})
    check('logins switched on: the first 401 reloads the page, and only the first', reloads, 1)

    //? the page that came back, still without the mark - something else answering 401 (a proxy in front)
    freshWindow()
    reloadWhenLoginsComeOn()
    await http.get('/navidrome/albums').catch(() => {})
    check('...a page reloaded for it within the minute doesn\'t reload again (no reloading over and over)', reloads, 1)
    stored.set('deadwax-reloaded-for-logins', String(Date.now() - RELOAD_AGAIN_MS - 1))
    freshWindow()
    reloadWhenLoginsComeOn()
    await http.get('/navidrome/albums').catch(() => {})
    check('...after it, it does', reloads, 2)

    globalThis.sessionStorage = { getItem() { throw new Error('denied') }, setItem() { throw new Error('denied') } }
    freshWindow()
    reloadWhenLoginsComeOn()
    await http.get('/navidrome/albums').catch(() => {})
    await http.get('/download/jobs').catch(() => {})
    check('...and with the browser keeping nothing for the tab, it reloads regardless - still once for the page', reloads, 3)
    delete globalThis.sessionStorage
  }

  console.log('\nthe sources: off is today, and the app starts from the session')
  {
    const read = (file) => fs.readFileSync(path.join(SRC, file), 'utf8')
    const main = read('player/main.tsx')
    check('player/main.tsx: without the mark the app is drawn at once, nothing asked first - and loaded again at its first 401',
      [/else if \(loginsOn\(\)\) startWithLogins\(host\)\s*else \{\s*render\(<App \/>, host\)\s*reloadWhenLoginsComeOn\(\)\s*\}/.test(main), /\bme\(|fetch\(/.test(main)], [true, false])
    //? (2.0.0-player.61) its permissions, from the access store - the session's word until /me answers, everything with logins off
    check('App\'s admin starts from the session\'s word (true with logins off)',
      [/const access = useAccess\(\)\s*const perms = access\.permissions/.test(read('app/App.tsx')), /return signedIn \? permissionsOf\(signedIn\) : ALL/.test(read('app/session.ts'))], [true, true])
    const gateSource = read('app/signInGate.tsx')
    check('the gate never draws the app away: nothing rendered into its host but the app', [...gateSource.matchAll(/render\(([^,]+), host\)/g)].map((m) => m[1]), ['<App />'])
    check('...and reaches nothing of the player', /usePlayer|PlayerContext|ActionsContext|playTracks/.test(gateSource), false)
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
