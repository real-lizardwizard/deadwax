#!/usr/bin/env node
/**
 * Change password on the iPhone app (Phase 8, slice 10 - notes/ios-specs/phase8-managing.md 9): who is offered it, the
 * line over the form, what shows while typing (People's password rules and the same password again), when Change can
 * be pressed, what is said after, the plain-http note and the Amperfy line - written as a fixture the Swift port
 * (ios/DeadwaxKit/Sources/DeadwaxCore/OwnPassword.swift) replays in Tests/DeadwaxCoreTests/OwnPasswordVectorTests.swift.
 *
 * Compiles lib/ownPassword.ts, lib/people.ts and lib/signIn.ts with the repo's TypeScript and runs them AS THEY ARE, on
 * inputs from the plain to the awkward: lengths either side of 8 and 128 counted in UTF-16 units (a character outside the
 * BMP is two), every edge of the control characters' ranges, a password that is the user name in another case (the
 * Turkish dotted I, the German sharp s, a Greek final sigma), the two passwords alike but for their normalization, and
 * forms at random from an alphabet of all of them. And reads out of app/ChangePassword.tsx and api/me.ts what the page
 * works out itself - the fields' labels, the body it sends, the button's words, what a refusal of the current password
 * does, what a change done empties - each by a pattern, compiled and run as written where it is code. A pattern that no
 * longer matches stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/password/password-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/iospassword.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a backslash-u escape), so a run on any machine writes
 * the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-password-vectors.cjs           write the fixture
 *   node ios/scripts/export-password-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'password', 'password-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-password-vectors.cjs'
const SOURCES = ['lib/ownPassword.ts', 'lib/people.ts', 'lib/signIn.ts']
const PAGE = 'app/ChangePassword.tsx'
const API = 'api/me.ts'

const sha256 = (body) => crypto.createHash('sha256').update(body).digest('hex')
const source = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
const madeFrom = Object.fromEntries(SOURCES.map((file) => [`ui/src/${file}`, sha256(source(file))]))

/** A piece read out of a source by `pattern`: its match, hashed - the script stops when it is gone. */
function piece(file, pattern, what) {
  const found = pattern.exec(source(file))
  if (!found) throw new Error(`couldn't read ${what} out of ui/src/${file} - the web app's code moved; change this script with it`)
  madeFrom[`ui/src/${file} ${what}`] = sha256(found[0])
  return found
}

/** A sentence or line the component has as written, hashed with what it is - the script stops when it is gone. */
function says(file, text, what) {
  if (!source(file).includes(text)) throw new Error(`ui/src/${file} no longer says ${JSON.stringify(text)} (${what})`)
  madeFrom[`ui/src/${file} ${what}`] = sha256(text)
  return text
}

/* ===== the web's code, compiled ===== */

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-password-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const O = require(path.join(OUT, 'lib/ownPassword.js'))
const People = require(path.join(OUT, 'lib/people.js'))
const S = require(path.join(OUT, 'lib/signIn.js'))
const ts = require(path.join(UI, 'node_modules/typescript'))
fs.rmSync(OUT, { recursive: true, force: true })

/** A TypeScript expression or body, its types stripped by TypeScript itself, as a function of `names`. */
function compiled(names, body) {
  const js = ts.transpileModule(`module.exports = function (${names.join(', ')}) {\n${body}\n}`, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText
  const module = { exports: null }
  new Function('module', 'exports', js)(module, module.exports)
  return module.exports
}

let seed = 10374
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/* ===== ChangePassword.tsx's and api/me.ts's own, read out of them ===== */

const labels = piece(PAGE,
  /<span class="app-people-label">([^<]+)<\/span>[\s\S]*?<span class="app-people-label">([^<]+)<\/span>[\s\S]*?<span class="app-people-label">([^<]+)<\/span>/,
  "the fields' labels")
const buttonFound = piece(PAGE, /\{busy \? '([^']+)' : '([^']+)'\}<\/button>/, "the button's words")
const bodyOf = compiled(['typed'], `return ${piece(PAGE,
  /changePassword\((\{ current: typed\.current, password: typed\.password, password_again: typed\.again \})\)/, 'the body sent')[1]}`)
const wrongCurrent = piece(PAGE,
  /if \(reason instanceof ApiError && reason\.kind === '([a-z_]+)'\) \{\n\s*setForm\(\{ \.\.\.typed, current: '' \}\)\n\s*currentField\.current\?\.focus\(\{ preventScroll: true \}\)/,
  'a wrong current password, emptied and focused')
says(PAGE, 'if (!formReady(typed, user) || sending.current) return', 'one change at a time, when ready')
says(PAGE, "setForm(EMPTY_FORM)\n        setShow(false)\n        setOpen(false)\n        setDone({ words: doneWords(answer.signed_out), warning: answer.warning })",
  'a change done: the fields emptied, then what is said')
says(PAGE, 'setForm(typed)', 'a failure keeps the fields')
says(PAGE, 'const typing = formProblem(form, user)', 'the problem as typed')
says(PAGE, 'const ready = formReady(form, user)', 'Save by formReady')
says(PAGE, 'const note = httpNote(location.protocol)', 'the plain-http note')
says(PAGE, '<p class="app-people-line">{changeLine(user)}</p>', 'the line over the form')
says(PAGE, '<p class="app-footnote">{APPS_LINE}</p>', 'the Amperfy line')
const routeFound = piece(API, /const answer = await post<PasswordChanged>\('([^']+)', body\)\n\s*newSession\(\)\n\s*return answer/,
  "the route, and a new session after it")

const page = {
  labels: [labels[1], labels[2], labels[3]],
  busy: buttonFound[1],
  button: buttonFound[2],
  wrongCurrentKind: wrongCurrent[1],
  route: routeFound[1],
}

/* ===== the words ===== */

const words = {
  CHANGE_TITLE: O.CHANGE_TITLE,
  SAME_PASSWORD: O.SAME_PASSWORD,
  APPS_LINE: O.APPS_LINE,
  HTTP_NOTE: People.HTTP_NOTE,
  PASSWORD_MIN: People.PASSWORD_MIN,
  PASSWORD_MAX: People.PASSWORD_MAX,
  BREAK_GLASS_USER: S.BREAK_GLASS_USER,
}

/* ===== the rules ===== */

//? each edge of people.ts CONTROL's ranges, and the units just outside them
const EDGES = [0x00, 0x09, 0x0a, 0x1f, 0x20, 0x7e, 0x7f, 0x85, 0x9f, 0xa0, 0xac, 0xad, 0xae, 0x200a, 0x200b, 0x200d,
  0x200f, 0x2010, 0x2027, 0x2028, 0x2029, 0x202e, 0x202f, 0x205f, 0x2060, 0x2064, 0x2065, 0xfefe, 0xfeff, 0xff00]
const NAMES = ['ethan', 'maya-long-name', 'james', 'odysseus', 'istanbul', 'strasse', 'zoe', '', 'a.b_c-d', 'x']
const AWKWARD = ['a', 'Z', '7', '-', ' ', '\u00e9', 'e\u0301', '\u0130', '\u0131', '\u00df', '\u1e9e', '\u03a3', '\u03c3', '\u03c2', '\u01c5', '\u65e5', '\u{1f39b}', '\u{1f642}', '\u00a0',
  '\u2003', '\t', '\u200b', '\u00ad', '\ufeff', '\u0301', '\ufb00', '\u212a', '\u212b', 'K', '\u00c5']

const problems = []
const problem = (password, again, name) => problems.push({ password, again, name, said: People.passwordProblem(password, again, name) })

//? lengths, in UTF-16 units: one under and at each bound, with a character outside the BMP counted as two
for (const length of [0, 1, 7, 8, 9, 127, 128, 129, 200]) problem('p'.repeat(length), 'p'.repeat(length), 'ethan')
problem('\u{1f39b}'.repeat(3) + 'x', '\u{1f39b}'.repeat(3) + 'x', 'ethan')              // 7 units
problem('\u{1f39b}'.repeat(4), '\u{1f39b}'.repeat(4), 'ethan')                          // 8 units, 4 characters
problem('\u{1f642}'.repeat(64), '\u{1f642}'.repeat(64), 'ethan')                        // 128 units
problem('\u{1f642}'.repeat(64) + 'x', '\u{1f642}'.repeat(64) + 'x', 'ethan')            // 129 units
problem('e' + '\u0301'.repeat(7), 'e' + '\u0301'.repeat(7), 'ethan')      // 8 units, one character as Swift counts
//? the control characters' edges, at the start, the middle and the end
for (const unit of EDGES) {
  const c = String.fromCharCode(unit)
  problem(c + 'password-x', c + 'password-x', 'ethan')
  problem('pass' + c + 'word-x', 'pass' + c + 'word-x', 'ethan')
  problem('password-x' + c, 'password-x' + c, 'ethan')
}
//? the user name, in another case - as toLowerCase folds it
for (const [password, name] of [['ETHAN-ETHAN', 'ethan-ethan'], ['Ethan', 'ethan'], ['EthanEthan', 'ethan'],
  ['Maya-Long-Name', 'maya-long-name'], ['ODYSSEUS', 'odysseus'], ['\u039f\u0394\u03a5\u03a3\u03a3\u0395\u03a5\u03a3', '\u03bf\u03b4\u03c5\u03c3\u03c3\u03b5\u03c5\u03c2'], ['\u039f\u0394\u03a5\u03a3\u03a3\u0395\u03a5\u03a3', '\u03bf\u03b4\u03c5\u03c3\u03c3\u03b5\u03c5\u03c3'],
  ['\u0130STANBUL', 'istanbul'], ['\u0130STANBUL', 'i\u0307stanbul'], ['ISTANBUL', '\u0131stanbul'], ['STRASSE1', 'strasse1'],
  ['STRA\u1e9eE12', 'stra\u00dfe12'], ['stra\u00dfe12', 'STRASSE12'], ['\u01c5emal-\u01c5', '\u01c6emal-\u01c6'], ['KELVIN-\u212a', 'kelvin-k'],
  ['\u212bNGSTR\u00d6M', '\u00e5ngstr\u00f6m'], ['\u00c5NGSTR\u00d6M', '\u00e5ngstr\u00f6m'], ['password', ''], ['ETHAN-ETHAN', 'ETHAN-ETHAN']]) {
  problem(password, password, name)
}
//? the two passwords: alike but for their normalization, their case, a space - and the name checked before them
for (const [password, again] of [['caf\u00e9-latte', 'cafe\u0301-latte'], ['caf\u00e9-latte', 'caf\u00e9-latte'], ['password-x', 'Password-x'],
  ['password-x', 'password-x '], ['password-x', ''], ['', ''], ['ethan-ethan', 'other-pass'], ['\u212b-angstrom', '\u00c5-angstrom']]) {
  problem(password, again, 'ethan')
}
problem('ethan', 'other', 'ethan')
problem('ETHANETHAN', 'something-else', 'ethanethan')
//? at random, from the awkward alphabet
for (let n = 0; n < 160; n++) {
  let password = ''
  const length = between(0, 12)
  for (let i = 0; i < length; i++) password += chance(0.6) ? pick('abcdefghij-0123456789'.split('')) : pick(AWKWARD)
  const again = chance(0.75) ? password : chance(0.5) ? password + pick(AWKWARD) : password.slice(1)
  const name = chance(0.15) ? password.toUpperCase() : pick(NAMES)
  problem(password, again, name)
}

/* ===== the form ===== */

const forms = []
const form = (current, password, again, user) => {
  const typed = { current, password, again }
  forms.push({ ...typed, user, problem: O.formProblem(typed, user), ready: O.formReady(typed, user), body: bodyOf(typed) })
}
//? nothing until both new fields have something in them; then the rules; then the same password again
form('', '', '', 'ethan')
form('ethan-navidrome-pw', '', '', 'ethan')
form('ethan-navidrome-pw', 'short', '', 'ethan')
form('ethan-navidrome-pw', '', 'short', 'ethan')
form('ethan-navidrome-pw', 'short', 'short', 'ethan')
form('ethan-navidrome-pw', 'a-fresh-own-password', 'a-fresh-own-password', 'ethan')
form('', 'a-fresh-own-password', 'a-fresh-own-password', 'ethan')
form('ethan-navidrome-pw', 'ethan-navidrome-pw', 'ethan-navidrome-pw', 'ethan')
form('ethan-navidrome-pw', 'Ethan-Navidrome-PW', 'Ethan-Navidrome-PW', 'ethan')
form('caf\u00e9-latte-x', 'cafe\u0301-latte-x', 'cafe\u0301-latte-x', 'ethan')
form('cafe\u0301-latte-x', 'caf\u00e9-latte-x', 'caf\u00e9-latte-x', 'ethan')
form('ethan-navidrome-pw', 'EthanEthan', 'EthanEthan', 'ethan')
form('ethan-navidrome-pw', 'ETHAN-LONG', 'ETHAN-LONG', 'ethan-long')
form('ethan-navidrome-pw', 'a-fresh-own-password', 'a-fresh-own-passwor', 'ethan')
form('ethan-navidrome-pw', 'tab\there-pw', 'tab\there-pw', 'ethan')
form('x', 'x'.repeat(129), 'x'.repeat(129), 'ethan')
form('x', 'x'.repeat(128), 'x'.repeat(128), 'ethan')
form(' ', '        ', '        ', 'ethan')
form('ethan-navidrome-pw', '\u0130STANBUL-1', '\u0130STANBUL-1', 'i\u0307stanbul-1')
form('ethan-navidrome-pw', 'a-fresh-own-password', 'a-fresh-own-password', '')
for (let n = 0; n < 120; n++) {
  const word = () => {
    let typed = ''
    const length = pick([0, 0, 3, 7, 8, 9, 10, 14, 20])
    for (let i = 0; i < length; i++) typed += chance(0.7) ? pick('abcdefghij-0123456789'.split('')) : pick(AWKWARD)
    return typed
  }
  const password = word()
  const again = chance(0.7) ? password : word()
  const current = chance(0.2) ? password : chance(0.15) ? '' : word()
  form(current, password, again, chance(0.1) ? password.toLowerCase() : pick(NAMES))
}

/* ===== after, the line, the note, who ===== */

const done = [-3, -1, 0, 1, 2, 3, 5, 10, 99, 1000].map((signedOut) => ({ signedOut, said: O.doneWords(signedOut) }))
const lines = ['ethan', 'maya-long-name', 'James', 'zo\u00eb', '\u65e5\u672c', ''].map((user) => ({ user, said: O.changeLine(user) }))
const notes = ['http:', 'https:', 'HTTPS:', 'https', 'ftp:', ''].map((protocol) => ({ protocol, said: People.httpNote(protocol) }))
const offered = []
for (const me of [null, { auth: 'on', user: 'ethan' }, { auth: 'on', user: 'deadwax' }, { auth: 'on', user: 'Deadwax' },
  { auth: 'on', user: 'deadwax ' }, { auth: 'on', user: '' }, { auth: 'off', user: 'local' }, { auth: 'off', user: 'ethan' },
  { auth: 'On', user: 'ethan' }, { auth: 'on', user: 'local' }, { auth: 'on', user: 'admin' }]) {
  offered.push({ me, offered: O.changeOffered(me) })
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
const flat = (value) => ascii(JSON.stringify(value))

const fixture = {
  about: "Change password (lib/ownPassword.ts, lib/people.ts and lib/signIn.ts run as they are; app/ChangePassword.tsx's and api/me.ts's own, read out of their source). A form's `body` is what the page sends for it; `said` is null where the web says nothing.",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  words,
  page,
  problems,
  forms,
  done,
  lines,
  notes,
  offered,
}
const LISTED = new Set(['problems', 'forms', 'done', 'lines', 'notes', 'offered'])
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => LISTED.has(key)
    ? `  ${flat(key)}: [\n${value.map((row) => `    ${flat(row)}`).join(',\n')}\n  ]`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')
const counted = `${problems.length} passwords, ${forms.length} forms, ${done.length} counts, ${offered.length} sign-ins`
if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`Change password's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`Change password's fixture matches the web app's TypeScript (${counted}).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
}
