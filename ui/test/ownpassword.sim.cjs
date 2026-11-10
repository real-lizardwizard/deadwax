/**
 * Change your own password (2.0.2) - lib/ownPassword.ts and app/ChangePassword.tsx, You > About's row and its form,
 * compiled with the repo's TypeScript and rendered by a small stand-in for Preact into plain objects (the one
 * you.sim.cjs uses), deadwax's answer faked.
 *
 * What it pins:
 *
 *  - Who is offered it: logins on and a Navidrome sign-in - never the break-glass admin, never logins off.
 *  - While typing: nothing said until both new fields have something in them; then People's rules in src/people.py's
 *    words (8-128, no control characters, not the user name, twice the same) and the password you have refused.
 *    Save is live only for a current password and a new one that passes every rule.
 *  - The row: closed, a button that says it opens the form (aria-expanded, aria-controls); tapped, the form - a hidden
 *    user name for a password manager, Current (current-password), New and Again (new-password), Show, the plain-http
 *    note on http: alone - with focus in Current; tapped again or Cancel or Escape, closed and emptied.
 *  - Save: one request, its three fields as typed (read from the fields, so a password manager's fill counts), the
 *    button saying it is saving; a second press meanwhile sends nothing.
 *  - Done: the form closed, every field dropped, the words saying how many other devices were signed out and that
 *    this one wasn't, the server's warning when it sent one, and that Amperfy and other apps need the new password -
 *    in a live region always in the page; focus back on the row.
 *  - Refused: the server's words in an assertive region, the fields kept to correct - a wrong current password
 *    emptied and focused.
 *  - Nothing in it plays (app-rules.sim.cjs holds the files to that).
 *
 * Run it with:  node ui/test/ownpassword.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-ownpassword-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/ChangePassword.tsx', 'src/lib/ownPassword.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

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

//? (review 3) the real api/me.js kept aside, before the form's stand-in replaces it - its changePassword is checked below
fs.copyFileSync(path.join(OUT, 'api/me.js'), path.join(OUT, 'api/me-real.js'))

//? deadwax, faked: every change asked, answered as the test says next
const sent = []
const answers = []
fs.writeFileSync(path.join(OUT, 'api/me.js'), `
exports.changePassword = (body) => globalThis.__own.change(body)
`)
globalThis.__own = {
  change(body) {
    sent.push(body)
    const next = answers.shift()
    return next ? next() : new Promise(() => {})
  },
}
globalThis.location = { protocol: 'http:' }

const { ApiError } = require(path.join(OUT, 'api/http.js'))
const L = require(path.join(OUT, 'lib/ownPassword.js'))
const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { ChangePassword } = require(path.join(OUT, 'app/ChangePassword.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

console.log('\nwho is offered it')
check('logins on and a Navidrome sign-in; never break-glass, never logins off, never before /me answers', [
  L.changeOffered({ auth: 'on', user: 'ethan' }), L.changeOffered({ auth: 'on', user: 'deadwax' }),
  L.changeOffered({ auth: 'off', user: 'local' }), L.changeOffered(null), L.changeOffered({ auth: 'on', user: '' })],
[true, false, false, false, false])

console.log('\nwhile typing, and when Save is live')
const form = (current, password, again) => ({ current, password, again })
check('nothing said for a field not yet reached', [L.formProblem(form('', '', ''), 'ethan'), L.formProblem(form('old-password', 'short', ''), 'ethan')], [null, null])
check('then People\'s rules, in src/people.py\'s words', [
  L.formProblem(form('old-password', 'short', 'short'), 'ethan'),
  L.formProblem(form('old-password', 'x'.repeat(129), 'x'.repeat(129)), 'ethan'),
  L.formProblem(form('old-password', 'EthanEthan', 'ethanethan'), 'ethanethan'),
  L.formProblem(form('old-password', 'long-enough', 'long-enougH'), 'ethan'),
  L.formProblem(form('old-password', 'tab\there-pw', 'tab\there-pw'), 'ethan'),
], ['A password is at least 8 characters.', 'A password is at most 128 characters.', "A password can't be the user name.",
  "The two passwords aren't the same.", "A password can't have control characters in it."])
check('...and the password you have now refused, in the server\'s words', L.formProblem(form('same-password', 'same-password', 'same-password'), 'ethan'),
  "That's the password you have now - type a new one.")
check('Save live only with a current password and a new one that passes', [
  L.formReady(form('old-password', 'a-new-password', 'a-new-password'), 'ethan'),
  L.formReady(form('', 'a-new-password', 'a-new-password'), 'ethan'),
  L.formReady(form('old-password', 'a-new-password', 'a-new-passworD'), 'ethan'),
  L.formReady(form('a-new-password', 'a-new-password', 'a-new-password'), 'ethan'),
  L.formReady(form('old-password', 'short', 'short'), 'ethan')], [true, false, false, false, false])

console.log('\nwhat is said once it is done')
check('how many other devices, and that this one stays', [L.doneWords(0), L.doneWords(1), L.doneWords(3)], [
  "Password changed. You're still signed in here.",
  "Password changed. Signed out of your other device - it signs in again with the new one. You're still signed in here.",
  "Password changed. Signed out of your other 3 devices - they sign in again with the new one. You're still signed in here."])
check('...and every app that signs in to Navidrome needs the new one', L.APPS_LINE, 'Amperfy and any other app you use with Navidrome need the new password too.')

/* ===== the request, as api/me.ts makes it (review 3) ===== */

//? Done, the answer has moved this device's session under a new id (its cookie): the page's requests go out under a
//? new session then, so a 401 for one sent with the old cookie before the answer came isn't taken for a sign-out
async function theRequest() {
  console.log('\nthe request, and the new session it starts')
  const http = require(path.join(OUT, 'api/http.js'))
  const real = require(path.join(OUT, 'api/me-real.js'))
  const asked = []
  let answer = null
  globalThis.fetch = async (url, init) => {
    asked.push([url, init.method])
    return answer
  }
  const reply = (status, body) => ({ ok: status < 400, status, json: async () => body })
  const before = http.currentSession()
  answer = reply(409, { detail: "That isn't your current password", kind: 'not_your_password' })
  const refused = await real.changePassword({ current: 'x', password: 'a-new-password', password_again: 'a-new-password' })
    .then(() => 'answered', (e) => e.status)
  check('a refusal starts no new session', [refused, http.currentSession() - before], [409, 0])
  answer = reply(200, { changed: true, signed_out: 1, warning: null })
  const done = await real.changePassword({ current: 'x', password: 'a-new-password', password_again: 'a-new-password' })
  check('done: one new session, and the answer as it came', [http.currentSession() - before, done.signed_out], [1, 1])
  check('...asked once each, as a POST to /deadwax/me/password', asked, [['/deadwax/me/password', 'POST'], ['/deadwax/me/password', 'POST']])
  delete globalThis.fetch
}

/* ===== the component ===== */

const render = hooks.root(ChangePassword)
let tree = null
const draw = () => {
  tree = render({ user: 'ethan' })
  render.commit()
  return tree
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))
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
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return text(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const row = () => find(byClass('app-own-password-row'))[0]
const theForm = () => find((node) => node.type === 'form')[0]
const inputs = () => find((node) => node.type === 'input')
const field = (name) => inputs().find((node) => node.props.name === name)
const type = (name, value) => {
  field(name).props.onInput({ currentTarget: { value } })
  draw()
}
const submit = () => {
  theForm().props.onSubmit({ preventDefault() {} })
  draw()
}
const button = (words) => find((node) => node.type === 'button' && text(node) === words)[0]
const said = () => text(find(byClass('app-own-password-said'))[0])
const problem = () => find(byClass('app-people-problem')).map(text)
//? a focusable stand-in for the element a ref would hold
const focused = []
const element = (name, value = '') => ({ name, value, focus: () => focused.push(name) })

async function main() {
  await theRequest()
  console.log('\nthe row, closed')
  draw()
  check('a button, saying it opens the form - and no form', [text(row()), row().type, row().props['aria-expanded'], row().props['aria-controls'], !!theForm()],
    ['Change password', 'button', false, 'app-own-password-form', false])
  check('...and the region what is said goes in, always in the page and empty', [find(byClass('app-own-password-said'))[0]?.props['aria-live'], said()], ['polite', ''])

  console.log('\nopened')
  row().props.ref.current = element('row')
  row().props.onClick()
  draw()
  check('the form, by the id the row names, with its line', [theForm()?.props.id, row().props['aria-expanded'], text(find(byClass('app-people-line'))[0])],
    ['app-own-password-form', true, "Your Navidrome password, ethan - the one you sign in to deadwax, Navidrome and Amperfy with. deadwax changes it in Navidrome as you, and doesn't keep it."])
  check('its fields: the hidden user name, Current, New, Again - each as a password manager reads it', inputs().filter((node) => node.props.type !== 'checkbox')
    .map((node) => [node.props.name, node.props.autoComplete, node.props.type]),
  [['username', 'username', 'text'], ['current-password', 'current-password', 'password'], ['new-password', 'new-password', 'password'], ['new-password-again', 'new-password', 'password']])
  check('...the user name the session\'s, never reached', [field('username').props.value, field('username').props.tabIndex, field('username').props['aria-hidden']], ['ethan', -1, 'true'])
  field('current-password').props.ref.current = element('current')
  field('new-password').props.ref.current = element('new')
  field('new-password-again').props.ref.current = element('again')
  render.commit()
  check('the plain-http note under it on http:', find(byClass('app-people-http')).length, 1)
  check('Save not live yet', button('Save').props['aria-disabled'], true)

  console.log('\ntyping')
  type('current-password', 'old-password')
  type('new-password', 'short')
  check('one new field typed: nothing said', text(find(byClass('app-people-typing'))[0]), '')
  type('new-password-again', 'short')
  check('both: the first problem, politely', [text(find(byClass('app-people-typing'))[0]), find(byClass('app-people-typing'))[0].props['aria-live']], ['A password is at least 8 characters.', 'polite'])
  find((node) => node.type === 'input' && node.props.type === 'checkbox')[0].props.onChange({ currentTarget: { checked: true } })
  draw()
  check('Show: every field shown as text', [field('current-password').props.type, field('new-password').props.type, field('new-password-again').props.type], ['text', 'text', 'text'])
  submit()
  check('Save pressed while not ready sends nothing', sent.length, 0)

  console.log('\nsaving, and refused')
  type('new-password', 'a-new-password')
  type('new-password-again', 'a-new-password')
  check('ready: Save live', button('Save').props['aria-disabled'], false)
  //? the fields themselves hold what is typed: a password manager filling them fires no input
  field('current-password').props.ref.current.value = 'old-password'
  field('new-password').props.ref.current.value = 'a-new-password'
  field('new-password-again').props.ref.current.value = 'a-new-password'
  answers.push(() => Promise.reject(new ApiError(409, 'Navidrome is set not to let people change their own details - an admin can change it in People, or turn on EnableUserEditing in Navidrome.', 'x', false, 'editing_off')))
  submit()
  check('one request, its three fields as typed', sent, [{ current: 'old-password', password: 'a-new-password', password_again: 'a-new-password' }])
  check('...the button saying so', !!button('Saving…'), true)
  submit()
  check('...a second press meanwhile sends nothing', sent.length, 1)
  await settle()
  draw()
  check('refused: the server\'s words, assertively', [problem(), find((node) => node.props?.['aria-live'] === 'assertive').length],
    [['Navidrome is set not to let people change their own details - an admin can change it in People, or turn on EnableUserEditing in Navidrome.'], 1])
  check('...the fields kept to correct', [field('current-password').props.value, field('new-password').props.value, field('new-password-again').props.value],
    ['old-password', 'a-new-password', 'a-new-password'])

  focused.length = 0
  answers.push(() => Promise.reject(new ApiError(409, "That isn't your current password - the one you signed in to deadwax with. If you've changed it since, sign out and in again.", 'x', false, 'not_your_password')))
  submit()
  await settle()
  draw()
  check('a wrong current password: said, the field emptied and focused, the new ones kept',
    [problem().length, field('current-password').props.value, field('new-password').props.value, focused], [1, '', 'a-new-password', ['current']])

  console.log('\ndone')
  type('current-password', 'right-password')
  field('current-password').props.ref.current.value = 'right-password'
  focused.length = 0
  answers.push(() => Promise.resolve({ changed: true, signed_out: 2, warning: null }))
  submit()
  await settle()
  draw()
  check('the form closed and every field dropped', [!!theForm(), row().props['aria-expanded'], inputs().length], [false, false, 0])
  check('...the words: how many devices, this one kept, and the other apps', said(),
    "Password changed. Signed out of your other 2 devices - they sign in again with the new one. You're still signed in here.Amperfy and any other app you use with Navidrome need the new password too.")
  check('...focus back on the row', focused, ['row'])
  row().props.onClick()
  draw()
  check('opened again: empty, and what was said cleared', [field('current-password').props.value, field('new-password').props.value, said()], ['', '', ''])

  console.log('\na warning, and closing')
  field('current-password').props.ref.current = element('current', 'right-password')
  field('new-password').props.ref.current = element('new', 'another-new-pw')
  field('new-password-again').props.ref.current = element('again', 'another-new-pw')
  //? a password manager's fill: the fields hold it, and no input was fired - what is sent is the fields'
  type('new-password', 'another-new-pw')
  type('new-password-again', 'another-new-pw')
  answers.push(() => Promise.resolve({ changed: true, signed_out: 0, warning: "deadwax couldn't check that the new password works - Navidrome didn't answer that one question." }))
  submit()
  check('a current password filled with no input fired is the one sent', sent.at(-1), { current: 'right-password', password: 'another-new-pw', password_again: 'another-new-pw' })
  await settle()
  draw()
  check('the server\'s warning said with it', find(byClass('app-people-warning')).map(text), ["deadwax couldn't check that the new password works - Navidrome didn't answer that one question."])
  row().props.onClick()
  draw()
  type('current-password', 'typed-and-left')
  theForm().props.onKeyDown({ key: 'Escape', preventDefault() {} })
  draw()
  check('Escape closes it', !!theForm(), false)
  row().props.onClick()
  draw()
  check('...emptied', field('current-password').props.value, '')
  type('current-password', 'typed-and-left')
  button('Cancel').props.onClick()
  draw()
  row().props.onClick()
  draw()
  check('Cancel too', [field('current-password').props.value, problem()], ['', []])
  row().props.onClick()
  draw()
  check('the row tapped again closes it', !!theForm(), false)

  globalThis.location = { protocol: 'https:' }
  row().props.onClick()
  draw()
  check('on https: no plain-http note', find(byClass('app-people-http')).length, 0)

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main()
