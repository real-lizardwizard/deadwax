#!/usr/bin/env node
/**
 * People on the iPhone app (Phase 8, slice 11 - notes/ios-specs/phase8-managing.md 10): the rules a new person's form
 * and a reset are typed against, what each row says and offers (the server's `can`), Remove's lines and its typed-name
 * gate, the flip's question, a person's Permissions, what each change says once done, the Navidrome version note and
 * which of People's four faces the page draws - written as a fixture the Swift port
 * (ios/DeadwaxKit/Sources/DeadwaxCore/People.swift, PeopleFlow.swift) replays in
 * Tests/DeadwaxCoreTests/PeopleVectorTests.swift.
 *
 * Compiles lib/people.ts and lib/permissions.ts with the repo's TypeScript and runs them AS THEY ARE, on inputs from the
 * plain to the awkward: names either side of 32 UTF-16 units and the pattern's every edge, a name JavaScript folds into
 * another (the Kelvin sign, the dotted I, a final sigma), display names either side of 64 with every edge of the control
 * characters' ranges, passwords as Change password's fixture has them, rows at random from the server's own refusals,
 * counts at 0, 1 and many, ages at each step's edge, version strings that look nearly right. And reads out of
 * app/People.tsx, app/UnlockPeople.tsx, app/AddPerson.tsx, app/ResetPassword.tsx, app/RemovePerson.tsx,
 * app/usePeople.ts and api/people.ts what the page works out itself - the labels and buttons, each body sent, which
 * actions are drawn, the flip's and Forget's words, what a `locked` refusal does, each route - each by a pattern,
 * compiled and run as written where it is code. A pattern that no longer matches stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/people/people-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/iospeople.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a backslash-u escape), so a run on any machine writes
 * the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-people-vectors.cjs           write the fixture
 *   node ios/scripts/export-people-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'people', 'people-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-people-vectors.cjs'
const SOURCES = ['lib/people.ts', 'lib/permissions.ts']
const PAGE = 'app/People.tsx'
const UNLOCK = 'app/UnlockPeople.tsx'
const ADD = 'app/AddPerson.tsx'
const RESET = 'app/ResetPassword.tsx'
const REMOVE = 'app/RemovePerson.tsx'
const HOOK = 'app/usePeople.ts'
const API = 'api/people.ts'

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

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-people-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const P = require(path.join(OUT, 'lib/people.js'))
const R = require(path.join(OUT, 'lib/permissions.js'))
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

let seed = 61115
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const chance = (p) => rand() < p

/* ===== People.tsx's own ===== */

const lockButton = piece(PAGE, /<button type="button" class="app-button app-people-lock" onClick=\{lock\}>([^<]+)<\/button>/, 'Lock')
const everyone = piece(PAGE, /<h2 id="app-people-list-title" class="app-section-title">([^<]+)<\/h2>/, "the list's title")
const sharing = piece(PAGE, /<a class="app-text-button" href=\{SHARING_DOC\} target="_blank" rel="noopener">([^<]+)<\/a>/, 'the Sharing deadwax link')
says(PAGE, '{!state.on && (', 'the link with logins off')
says(PAGE, '<p class="app-placeholder-text">{PEOPLE_ONLY}</p>', 'PEOPLE_ONLY without the permission')
says(PAGE, "{view === 'locked' && state && <UnlockPeople user={state.you} onUnlocked={ask} />}", 'Unlock People as the state names you')
says(PAGE, "const note = view === 'list' ? versionNote(server) : null", 'the version note, unlocked')
says(PAGE, '{offered.filter((action) => !action.refused).map((action) => (', 'only the actions not refused, drawn')
says(PAGE, '{reasons.map((reason) => <p key={reason} class="app-footnote app-people-reason">{reason}</p>)}', 'each refusal said')
const tickedOf = compiled(['person', 'CATEGORIES', 'LABELS'], `return ${piece(PAGE,
  /const ticked = (person\.permissions \? CATEGORIES\.filter\(\(category\) => person\.permissions!\[category\]\)\.map\(\(category\) => LABELS\[category\]\) : \[\])/,
  "what was ticked, for No longer admin's words")[1]}`)
const flipOf = compiled(['person', 'ticked', 'makeAdminWords', 'unmakeAdminWords'], `return ${piece(PAGE,
  /const words = (person\.admin \? unmakeAdminWords\(person\.user, ticked\) : makeAdminWords\(person\.user\))/, "the flip's question")[1]}`)
const flipConfirm = piece(PAGE,
  /words=\{words\.question\}\n\s*confirm=\{(person\.admin \? '[^']+' : '[^']+')\}\n\s*keep="([^"]+)"\n\s*busy=\{busy\}\n\s*busyLabel="([^"]+)"/,
  "the flip's buttons")
const confirmOf = compiled(['person'], `return ${flipConfirm[1]}`)
const flippedOf = compiled(['answer'], `return ${piece(PAGE,
  /onChanged\((answer\.admin \? `\$\{answer\.user\} is an admin now\.` : `\$\{answer\.user\} is no longer an admin\.`)\)/,
  'what a flip says')[1]}`)
const adminBodyOf = compiled(['person'], `return ${piece(PAGE,
  /setAdmin\(person\.id, (\{ user: person\.user, admin: !person\.admin \})\)/, "the flip's body")[1]}`)
const legend = piece(PAGE, /<legend class="app-people-label">([^<]+)<\/legend>/, "the Permissions' legend")
const saveButton = piece(PAGE, /\{busy \? '([^']+)' : '([^']+)'\}\n\s*<\/button>/, 'Save permissions')
const savesOf = compiled(['person', 'refused'], `return ${piece(PAGE, /\{(!person\.admin && !refused) && \(/, 'who has Save permissions')[1]}`)
const saveBodyOf = compiled(['person', 'draft'], `return ${piece(PAGE,
  /savePermissions\(person\.id, (\{ user: person\.user, \.\.\.draft \})\)/, 'the permissions sent')[1]}`)
says(PAGE, 'const refused = person.can.permissions', 'the refusal the boxes are locked by')
says(PAGE, 'const boxes = checkboxes(person.admin, refused, draft)', 'the boxes, from the draft')
says(PAGE, 'const reason = lockedReason(person.admin, refused)', 'the reason over the boxes')
says(PAGE, 'const dirty = changed(person.permissions, draft)', 'Save on a change')
says(PAGE, 'if (!draft || !dirty || sending.current) return', 'one save at a time, and only a change')
says(PAGE, 'useEffect(() => setDraft(person.permissions), [JSON.stringify(person.permissions)])', 'a fresh list puts the draft back')
says(PAGE, '<p class="app-footnote app-people-permission-people">{PEOPLE_LINE}</p>', "People's own line under the boxes")
says(PAGE, 'onChanged(savedWords(person.user))', 'what a save says')
const forgetConfirm = piece(PAGE,
  /words=\{(`Forget what deadwax keeps for \$\{entry\.user\}\?[^`]*`)\}\n\s*confirm="([^"]+)"\n\s*keep="([^"]+)"\n\s*danger\n\s*busy=\{busy\}\n\s*busyLabel="([^"]+)"/,
  "Forget's question and buttons")
const forgetQuestionOf = compiled(['entry'], `return ${forgetConfirm[1]}`)
const forgotOf = compiled(['entry'], `return ${piece(PAGE, /onChanged\((`deadwax forgot what it kept for \$\{entry\.user\}\.`)\)/, 'what Forget says')[1]}`)
const forgetButton = piece(PAGE, /onClick=\{\(\) => setAsking\(true\)\}>([^<]+)<\/button>/, "a Known only row's button")
says(PAGE, 'forgetPerson(entry.user).then(', 'Forget sends the name')

/* ===== UnlockPeople.tsx's ===== */

const unlockLabel = piece(UNLOCK, /<span class="app-people-label">([^<]+)<\/span>/, "the password's label")
const unlockButton = piece(UNLOCK, /\{busy \? '([^']+)' : '([^']+)'\}\n\s*<\/button>/, 'Unlock')
says(UNLOCK, '<p class="app-people-line">{unlockLine(user)}</p>', 'the line over the field')
says(UNLOCK, 'if (!typed || sending.current) return', 'one unlock at a time, with a password')
piece(UNLOCK, /unlockPeople\(typed\)\.then\(\n\s*\(\) => \{\n\s*sending\.current = false\n\s*setBusy\(false\)\n\s*setPassword\(''\)[\s\S]*?\(reason: unknown\) => \{\n\s*sending\.current = false\n\s*setBusy\(false\)\n\s*setPassword\(''\)/,
  'the password emptied whatever the answer')
says(UNLOCK, 'setProblem(refusalOf(reason).words)\n        field.current?.focus({ preventScroll: true })', 'a refusal said, the field focused again')

/* ===== AddPerson.tsx's ===== */

const addTitle = piece(ADD, /<h2 id="app-people-add-title" class="app-people-title">([^<]+)<\/h2>\n\s*<p class="app-people-line">([^<]+)<\/p>/, 'the title and line')
const addLabels = piece(ADD,
  /<span class="app-people-label">([^<]+)<\/span>[\s\S]*?<span class="app-people-label">([^<]+)<\/span>[\s\S]*?<span class="app-people-label">([^<]+)<\/span>[\s\S]*?<span class="app-people-label">([^<]+)<\/span>/,
  "the fields' labels")
const addButton = piece(ADD, /\{busy \? '([^']+)' : '([^']+)'\}\n\s*<\/button>/, 'Make account')
const createBodyOf = compiled(['form', 'cleanName'], `const user = cleanName(form.user)\nreturn ${piece(ADD,
  /const user = cleanName\(form\.user\)\n\s*createPerson\((\{ user, name: form\.name\.trim\(\), password: form\.password, password_again: form\.again \})\)/,
  'the body sent')[1]}`)
const fieldMax = [
  piece(ADD, /maxLength=\{NAME_MAX \+ (\d+)\}/, "the user name's field")[1],
  piece(ADD, /maxLength=\{DISPLAY_MAX \+ (\d+)\}/, "the display name's field")[1],
  piece(ADD, /maxLength=\{PASSWORD_MAX \+ (\d+)\}/, "the passwords' fields")[1],
].map(Number)
says(ADD, 'const typing = formProblem(form)', 'the problem as typed')
says(ADD, 'const ready = formReady(form)', 'Make account by formReady')
says(ADD, 'if (!ready || sending.current) return', 'one at a time, when ready')
says(ADD, "setForm({ user: '', name: '', password: '', again: '' })\n        setSaid({ words: madeWords(answer.made.user, location.origin), warning: answer.warning, refused: false })",
  'made: the fields emptied, what to tell them and the warning')
says(ADD, "if (refusal.locked) {\n          setForm((was) => ({ ...was, password: '', again: '' }))\n          onLocked()",
  'locked: the passwords emptied, the names kept')

/* ===== ResetPassword.tsx's ===== */

const resetLabels = piece(RESET, /<span class="app-people-label">([^<]+)<\/span>[\s\S]*?<span class="app-people-label">([^<]+)<\/span>/, "the fields' labels")
const resetButtons = piece(RESET,
  /\{busy \? '([^']+)' : '([^']+)'\}<\/button>\n\s*<button type="button" class="app-button" onClick=\{onCancel\}>([^<]+)<\/button>/, 'the buttons')
const resetRule = piece(RESET,
  /const wrong = (password && again \? passwordProblem\(password, again, person\.user\) : null)\n\s*const ready = (!passwordProblem\(password, again, person\.user\))/,
  'what shows while typing, and when Reset can be pressed')
const wrongOf = compiled(['password', 'again', 'person', 'passwordProblem'], `return ${resetRule[1]}`)
const resetReadyOf = compiled(['password', 'again', 'person', 'passwordProblem'], `return ${resetRule[2]}`)
const resetBodyOf = compiled(['person', 'password', 'again'], `return ${piece(RESET,
  /resetPassword\(person\.id, (\{ user: person\.user, password, password_again: again \})\)/, 'the body sent')[1]}`)
const resetNameOf = compiled(['person'], `return ${piece(RESET, /aria-label=\{(`Reset \$\{person\.user\}'s password`)\}/, "the form's name")[1]}`)
says(RESET, 'onDone(resetWords(answer.reset, answer.signed_out))', 'what a reset says')

/* ===== RemovePerson.tsx's ===== */

says(REMOVE, '>Remove {person.user}?</h2>', 'the title')
const removeLabel = piece(REMOVE, /<span class="app-people-label">([^<]+)<\/span>/, "the name's label")
const removeCancel = piece(REMOVE, /disabled=\{busy\} onClick=\{onCancel\}>([^<]+)<\/button>/, 'Cancel')
const removeBusy = piece(REMOVE, /\{busy \? '([^']+)' : (`Remove \$\{person\.user\}`)\}/, 'Remove')
const removeButtonOf = compiled(['person'], `return ${removeBusy[2]}`)
const removedOf = compiled(['person'], `return ${piece(REMOVE, /onRemoved\((`Removed \$\{person\.user\} from Navidrome and deadwax\.`)\)/, 'what a removal says')[1]}`)
const removeBodyOf = compiled(['person', 'typed'], `return ${piece(REMOVE, /removePerson\(person\.id, (\{ user: person\.user, confirm: typed \})\)/, 'the body sent')[1]}`)
says(REMOVE, 'const ready = removeReady(typed, person.user)', 'Remove by removeReady')
says(REMOVE, "if (event.key === 'Enter') event.preventDefault()", 'Enter never confirms')

/* ===== usePeople.ts's and api/people.ts's ===== */

const readFailed = piece(HOOK, /setProblem\(sayError\(reason, '', \{ failed: "([^"]+)" \}\)\)/, "a read's failure")
const lockedKind = piece(HOOK,
  /if \(reason instanceof ApiError && reason\.kind && reason\.detail\) return \{ words: reason\.detail, locked: reason\.kind === '([a-z_]+)' \}\n\s*return \{ words: sayError\(reason\), locked: false \}/,
  "a refusal's words, and the kind that locks")
says(HOOK, 'setState((was) => (was ? { ...was, locked: true, people: [], known_only: [] } : was))\n    ask()', 'locked again: nobody listed, then asked again')
says(API, "return post('/people/lock', {})", 'Lock sends nothing')

const routes = []
for (const name of ['getPeople', 'unlockPeople', 'lockPeople', 'createPerson', 'resetPassword', 'setAdmin', 'removePerson', 'forgetPerson', 'savePermissions']) {
  const found = piece(API, new RegExp(`export function ${name}\\([^)]*\\)[\\s\\S]*?\\{\\n\\s*return (get|post)(?:<[^>]+>)?\\((['\`])([^'\`]+)\\2`), `${name}'s route`)
  routes.push({ name, method: found[1] === 'get' ? 'GET' : 'POST', path: '/deadwax' + found[3].replace('${encodeURIComponent(id)}', '{person_id}') })
}

const page = {
  lock: lockButton[1],
  everyone: everyone[1],
  sharing: sharing[1],
  flip: { keep: flipConfirm[2], busy: flipConfirm[3] },
  permissions: { legend: legend[1], busy: saveButton[1], button: saveButton[2] },
  forget: { confirm: forgetConfirm[2], keep: forgetConfirm[3], busy: forgetConfirm[4], button: forgetButton[1] },
  unlock: { label: unlockLabel[1], busy: unlockButton[1], button: unlockButton[2] },
  add: { title: addTitle[1], line: addTitle[2], labels: [addLabels[1], addLabels[2], addLabels[3], addLabels[4]], busy: addButton[1], button: addButton[2], fieldMax },
  reset: { labels: [resetLabels[1], resetLabels[2]], busy: resetButtons[1], button: resetButtons[2], cancel: resetButtons[3] },
  remove: { label: removeLabel[1], cancel: removeCancel[1], busy: removeBusy[1] },
  readFailed: readFailed[1],
  lockedKind: lockedKind[1],
  routes,
}

/* ===== the words ===== */

const words = {
  NAME_MAX: P.NAME_MAX, DISPLAY_MAX: P.DISPLAY_MAX, PASSWORD_MIN: P.PASSWORD_MIN, PASSWORD_MAX: P.PASSWORD_MAX,
  UNLOCK_IDLE_MINUTES: P.UNLOCK_IDLE_MINUTES, RESERVED: P.RESERVED, TESTED_NAVIDROME: P.TESTED_NAVIDROME,
  UNLOCK_TITLE: P.UNLOCK_TITLE, UNLOCKED_LINE: P.UNLOCKED_LINE, HTTP_NOTE: P.HTTP_NOTE, SHARING_DOC: P.SHARING_DOC,
  KNOWN_ONLY_TITLE: P.KNOWN_ONLY_TITLE, KNOWN_ONLY_LINE: P.KNOWN_ONLY_LINE,
  CATEGORIES: R.CATEGORIES, LABELS: R.LABELS, LINES: R.LINES, PEOPLE_LINE: R.PEOPLE_LINE, ADMINS_EVERYTHING: R.ADMINS_EVERYTHING,
  WARN_SERVER: R.WARN_SERVER, WARN_LIBRARY: R.WARN_LIBRARY, WARN_NO_REQUEST: R.WARN_NO_REQUEST, PEOPLE_ONLY: R.PEOPLE_ONLY,
}

/* ===== the inputs ===== */

//? each edge of people.ts CONTROL's ranges, and the units just outside them
const EDGES = [0x00, 0x09, 0x0a, 0x1f, 0x20, 0x7e, 0x7f, 0x85, 0x9f, 0xa0, 0xac, 0xad, 0xae, 0x200a, 0x200b, 0x200d,
  0x200f, 0x2010, 0x2027, 0x2028, 0x2029, 0x202e, 0x202f, 0x205f, 0x2060, 0x2064, 0x2065, 0xfefe, 0xfeff, 0xff00]
const AWKWARD = ['a', 'Z', '7', '-', '.', '_', ' ', '\u00e9', 'e\u0301', '\u0130', '\u0131', '\u00df', '\u1e9e', '\u03a3', '\u03c2', '\u01c5', '\u65e5',
  '\u{1f39b}', '\u00a0', '\u2003', '\t', '\n', '\u200b', '\u00ad', '\ufeff', '\u0301', '\ufb00', '\u212a', '\u212b', '\u00c5', 'A', '9']
const word = (length, from) => {
  let typed = ''
  for (let i = 0; i < length; i++) typed += chance(0.6) ? pick(from.split('')) : pick(AWKWARD)
  return typed
}

/* ===== the names and display names ===== */

const names = []
const name = (typed) => {
  const clean = P.cleanName(typed)
  names.push({ typed, clean, problem: P.nameProblem(clean) })
}
for (const typed of ['', ' ', 'ethan', ' Ethan ', 'ETHAN', 'a', '0', '9lives', 'a'.repeat(31), 'a'.repeat(32), 'a'.repeat(33),
  ' ' + 'b'.repeat(32) + ' ', '-ethan', '.x', '_x', 'x-', 'x.', 'x.y_z-1', 'a--b', 'local', 'LOCAL', ' deadwax ', 'deadwax2',
  'locals', 'loc al', 'ma\u00f1ana', '\u0130stanbul', '\u212aelvin', '\u212a', '\u01c5emal', '\ufb00', '\u039f\u0394\u03a5\u03a3\u03a3\u0395\u03a5\u03a3',
  'ethan\n', '\nethan', 'eth\nan', '\u00a0ethan\u00a0', '\u2003ethan', '\u200bethan', '\ufeffethan', 'ethan\u0301', 'a'.repeat(31) + '\u00e9',
  '\u{1f642}', 'abc/def', 'a b', 'A.B', 'x@y', 'x+y', '\u0131', 'I', 'ethan\t']) {
  name(typed)
}
for (let n = 0; n < 120; n++) name(word(pick([0, 1, 2, 5, 8, 12, 31, 32, 33, 40]), 'abcdefxyz0123-._'))

const displays = []
const display = (typed) => displays.push({ typed, problem: P.displayProblem(typed) })
for (const typed of ['', '  ', 'Maya', 'Maya Long-Name', 'x'.repeat(63), 'x'.repeat(64), 'x'.repeat(65), ' ' + 'x'.repeat(64) + ' ',
  '\u{1f642}'.repeat(32), '\u{1f642}'.repeat(32) + 'x', 'Zo\u00eb', 'e\u0301'.repeat(32), 'e\u0301'.repeat(33), '\u65e5\u672c\u306e\u540d\u524d',
  '\u00a0Maya\u00a0', '\u200bMaya', '\ufeffMaya', 'Maya\ufeff']) {
  display(typed)
}
for (const unit of EDGES) {
  const c = String.fromCharCode(unit)
  display(c + 'Maya')
  display('Ma' + c + 'ya')
  display('Maya' + c)
}
for (let n = 0; n < 60; n++) display(word(pick([0, 3, 10, 30, 63, 64, 65, 70]), 'abcxyz ABC'))

/* ===== Add a person, and a reset ===== */

const NAMES = ['ethan', 'maya-long-name', 'james', 'odysseus', 'istanbul', 'strasse', 'zoe', '', 'a.b_c-d', 'x', 'local', ' Ethan ']
const forms = []
const form = (user, display, password, again) => {
  const typed = { user, name: display, password, again }
  forms.push({ ...typed, problem: P.formProblem(typed), ready: P.formReady(typed), body: createBodyOf(typed, P.cleanName) })
}
//? nothing said for a field not yet reached; each field's rule in turn; the name checked before the passwords
form('', '', '', '')
form('ethan', '', '', '')
form(' Ethan ', ' Ethan Hunt ', '', '')
form('ethan', '', 'short', '')
form('ethan', '', '', 'short')
form('ethan', '', 'short', 'short')
form('ethan', '', 'a-fresh-password', 'a-fresh-password')
form('ethan', 'Ethan', 'a-fresh-password', 'a-fresh-passwor')
form('ethan', 'Ethan', 'ETHAN', 'ETHAN')
form('ethan', 'Ethan', 'Ethan-ethan', 'Ethan-ethan')
form(' ETHAN ', '', 'ethan', 'ethan')
form('ethan', '', 'ethan', 'ethan')
form('local', '', 'a-fresh-password', 'a-fresh-password')
form('Local', '', 'a-fresh-password', 'a-fresh-password')
form('-ethan', '', 'a-fresh-password', 'a-fresh-password')
form('', '', 'a-fresh-password', 'a-fresh-password')
form('ethan', 'x'.repeat(65), 'a-fresh-password', 'a-fresh-password')
form('ethan', 'Ma\u200bya', 'a-fresh-password', 'a-fresh-password')
form('-ethan', 'x'.repeat(65), 'short', 'short')
form('ethan', '', 'tab\there-pw', 'tab\there-pw')
form('ethan', '', 'x'.repeat(129), 'x'.repeat(129))
form('ethan', '', 'x'.repeat(128), 'x'.repeat(128))
form('\u212aelvin', '', 'kelvin-k1', 'kelvin-k1')
form('\u212aelvin', '', 'KELVIN', 'KELVIN')
form('\u0130stanbul', '', 'i\u0307stanbul', 'i\u0307stanbul')
form('ethan', '', 'caf\u00e9-latte', 'cafe\u0301-latte')
form('ethan', '  ', 'a-fresh-password', 'a-fresh-password')
for (let n = 0; n < 160; n++) {
  const user = chance(0.6) ? pick(NAMES) : word(pick([0, 3, 8, 33]), 'abcxyz019-._')
  const shown = chance(0.5) ? '' : chance(0.7) ? pick(['Ethan', ' Maya ', 'Zo\u00eb', 'x'.repeat(65)]) : word(pick([3, 10, 64, 66]), 'abc XYZ')
  const password = chance(0.15) ? user.toUpperCase() : word(pick([0, 3, 7, 8, 9, 14, 20]), 'abcdefghij-0123456789')
  const again = chance(0.75) ? password : chance(0.5) ? '' : word(pick([7, 8, 9]), 'abcdef-012')
  form(user, shown, password, again)
}

const resets = []
const reset = (password, again, user) => {
  const person = { id: 'id-r', user }
  resets.push({
    password, again, user,
    wrong: wrongOf(password, again, person, P.passwordProblem),
    ready: resetReadyOf(password, again, person, P.passwordProblem),
    body: resetBodyOf(person, password, again),
    title: resetNameOf(person),
  })
}
reset('', '', 'ethan')
reset('a-fresh-password', '', 'ethan')
reset('', 'a-fresh-password', 'ethan')
reset('short', 'short', 'ethan')
reset('a-fresh-password', 'a-fresh-password', 'ethan')
reset('a-fresh-password', 'a-fresh-passworD', 'ethan')
reset('ETHAN-ETHAN', 'ETHAN-ETHAN', 'ethan-ethan')
reset('EthanEthan', 'EthanEthan', 'ethanethan')
reset('ethanethan', 'ethanethan', '')
reset('x'.repeat(129), 'x'.repeat(129), 'ethan')
reset('\u{1f39b}'.repeat(4), '\u{1f39b}'.repeat(4), 'ethan')
reset('\u{1f39b}'.repeat(3) + 'x', '\u{1f39b}'.repeat(3) + 'x', 'ethan')
reset('pass\u200bword-x', 'pass\u200bword-x', 'ethan')
reset('\u212aELVIN-1', '\u212aELVIN-1', 'kelvin-1')
for (let n = 0; n < 100; n++) {
  const user = pick(NAMES)
  const password = chance(0.15) ? user.toUpperCase() : word(pick([0, 4, 7, 8, 9, 12, 20]), 'abcdefghij-0123456789')
  const again = chance(0.7) ? password : chance(0.5) ? '' : password + 'x'
  reset(password, again, user)
}

/* ===== the rows ===== */

const NOW = 1763300000
const LAST_ADMIN = 'maya is Navidrome\'s last admin - make someone else one first.'
const REASONS = [null, null, null, null, '', 'That\'s deadwax\'s own account (NAVIDROME_USER) - deadwax would lose its way into Navidrome.',
  'That\'s you - change your own password in You \u2192 Account \u2192 Change password.', 'deadwax doesn\'t remove the account you\'re signed in with.',
  'You can\'t take away your own admin role.', 'That\'s you - an admin has every permission.', LAST_ADMIN,
  'Admins have every permission - that changes with Make admin.', 'deadwax keeps that name for itself - nobody signs in to deadwax as it.']
const AGES = [0, 1, 30, 59, 60, 61, 119, 120, 3599, 3600, 3601, 7199, 86399, 86400, 172799, 86400 * 59, 86400 * 60 - 1, 86400 * 60,
  86400 * 89, 86400 * 90, 86400 * 365, 86400 * 1000, -50, 59.5, 60.5]

const people = []
const row = (person) => {
  const ticked = tickedOf(person, R.CATEGORIES, R.LABELS)
  const question = flipOf(person, ticked, P.makeAdminWords, P.unmakeAdminWords)
  const actions = P.actions(person)
  people.push({
    person,
    chips: P.chips(person),
    signIn: P.signInWords(person, NOW),
    library: P.libraryWords(person),
    warning: P.librariesWarning(person),
    actions,
    drawn: actions.filter((action) => !action.refused).map((action) => action.kind),
    refusals: P.refusals(person),
    remove: P.removeLines(person),
    removeButton: removeButtonOf(person),
    removed: removedOf(person),
    ticked,
    question,
    confirm: confirmOf(person),
    adminBody: adminBodyOf(person),
    boxes: R.checkboxes(person.admin, person.can.permissions, person.permissions),
    reason: R.lockedReason(person.admin, person.can.permissions),
    saves: !!savesOf(person, person.can.permissions),
    saveBody: person.permissions ? saveBodyOf(person, person.permissions) : null,
  })
}
let ids = 0
const someone = (over) => ({
  id: `nd-${++ids}`, user: 'ethan', name: 'Ethan', admin: false, shared_account: false, reserved: false, you: false,
  signed_in: 0, last_sign_in: null, library: 0, waiting_alone: 0, libraries: 1,
  permissions: { request: true, edit: false, library: false, downloads: false, server: false },
  can: { reset: null, remove: null, admin: null, permissions: null },
  ...over,
})
const YOU = { reset: REASONS[6], remove: REASONS[7], admin: REASONS[8], permissions: REASONS[9] }
//? you; deadwax's own account; the last admin; a reserved name; an ordinary person with each count at 0, 1 and many
row(someone({ user: 'james', name: 'James', admin: true, you: true, signed_in: 2, permissions: null, can: YOU }))
row(someone({ user: 'demo', name: 'demo', shared_account: true, can: { reset: REASONS[5], remove: REASONS[5], admin: REASONS[5], permissions: REASONS[5] } }))
row(someone({ user: 'maya', name: 'Maya', admin: true, permissions: null, can: { reset: null, remove: LAST_ADMIN, admin: LAST_ADMIN, permissions: REASONS[11] } }))
row(someone({ user: 'local', name: 'local', reserved: true, can: { reset: null, remove: null, admin: null, permissions: REASONS[12] } }))
row(someone({ user: 'ethan', library: 1, signed_in: 1, waiting_alone: 1, libraries: 0 }))
row(someone({ user: 'zoe', name: 'Zo\u00eb', library: 37, waiting_alone: 7, libraries: null, last_sign_in: NOW - 3 * 86400,
  permissions: { request: false, edit: true, library: true, downloads: true, server: true } }))
row(someone({ user: 'odysseus', admin: true, permissions: null, libraries: 0, library: 2, signed_in: 5, waiting_alone: 2 }))
row(someone({ user: 'empty', permissions: { request: false, edit: false, library: false, downloads: false, server: false },
  can: { reset: '', remove: '', admin: '', permissions: '' } }))
row(someone({ user: 'dupes', can: { reset: LAST_ADMIN, remove: LAST_ADMIN, admin: REASONS[8], permissions: null } }))
for (const age of AGES) row(someone({ user: 'aged', last_sign_in: NOW - age }))
for (let n = 0; n < 90; n++) {
  const admin = chance(0.3)
  const user = pick(['ethan', 'maya-long-name', 'james', 'zoe', 'x', 'a.b_c-d', 'demo', 'local'])
  row(someone({
    user, name: pick([user, user.toUpperCase(), 'Maya Long-Name', 'Zo\u00eb', '\u65e5\u672c']), admin,
    shared_account: chance(0.1), reserved: chance(0.08), you: chance(0.15),
    signed_in: pick([0, 0, 1, 2, 5]), last_sign_in: chance(0.3) ? null : NOW - pick(AGES),
    library: pick([0, 1, 2, 37, 1000]), waiting_alone: pick([0, 0, 1, 2, 7]), libraries: pick([null, 0, 1, 3]),
    permissions: admin ? null : { request: chance(0.7), edit: chance(0.3), library: chance(0.3), downloads: chance(0.3), server: chance(0.2) },
    can: { reset: pick(REASONS), remove: pick(REASONS), admin: pick(REASONS), permissions: pick(REASONS) },
  }))
}

const agos = AGES.concat([0.5, 3600 * 23.99, 86400 * 59.99, 86400 * 30 * 13]).map((seconds) => ({ seconds, said: P.ago(seconds) }))

const known = []
const knownRow = (entry) => known.push({ entry, said: P.knownWords(entry), question: forgetQuestionOf(entry), forgot: forgotOf(entry) })
knownRow({ user: 'gone', sessions: 0, credential: false, library: 0, pins: 0, preferences: false, requests: 0, permissions: 0 })
knownRow({ user: 'gone-one', sessions: 1, credential: true, library: 1, pins: 1, preferences: true, requests: 1, permissions: 1, queue: true, history: 1 })
knownRow({ user: 'gone-many', sessions: 3, credential: false, library: 40, pins: 2, preferences: false, requests: 12, permissions: 3, queue: false, history: 1234567 })
for (const history of [0, 2, 999, 1000, 9999, 10000, 100000, 1000000, 12345678]) {
  knownRow({ user: 'played', sessions: 0, credential: false, library: 0, pins: 0, preferences: false, requests: 0, permissions: 0, history })
}
for (let n = 0; n < 40; n++) {
  const entry = { user: pick(['gone', 'old-ethan', 'x', 'maya']), sessions: pick([0, 1, 2]), credential: chance(0.3), library: pick([0, 1, 5]),
    pins: pick([0, 1, 3]), preferences: chance(0.3), requests: pick([0, 1, 4]), permissions: pick([0, 1, 2]) }
  if (chance(0.6)) entry.queue = chance(0.5)
  if (chance(0.6)) entry.history = pick([0, 1, 12, 1000, 54321])
  knownRow(entry)
}

const ready = []
for (const [typed, user] of [['ethan', 'ethan'], ['Ethan', 'ethan'], ['ethan ', 'ethan'], [' ethan', 'ethan'], ['', ''], ['', 'ethan'],
  ['eth', 'ethan'], ['ethanx', 'ethan'], ['caf\u00e9', 'cafe\u0301'], ['cafe\u0301', 'cafe\u0301'], ['\u212a', 'k'], ['x', 'x']]) {
  ready.push({ typed, user, ready: P.removeReady(typed, user) })
}

const changes = []
const TICKS = [null, { request: true, edit: false, library: false, downloads: false, server: false },
  { request: false, edit: false, library: false, downloads: false, server: false },
  { request: true, edit: true, library: true, downloads: true, server: true },
  { request: true, edit: false, library: true, downloads: false, server: false }]
for (const saved of TICKS) for (const draft of TICKS) changes.push({ saved, draft, changed: R.changed(saved, draft) })

const after = []
for (const user of ['ethan', 'maya-long-name', 'Zo\u00eb', '']) {
  for (const [origin, signedOut] of [['http://deadwax.lan:8080', 0], ['https://music.example.org', 1], ['http://192.168.1.20:8080', 2], ['http://[::1]:8080', 10], ['http://deadwax.test', -1]]) {
    after.push({
      user, origin, signedOut,
      made: P.madeWords(user, origin),
      reset: P.resetWords(user, signedOut),
      saved: R.savedWords(user),
      flippedOn: flippedOf({ user, admin: true }),
      flippedOff: flippedOf({ user, admin: false }),
      unlockLine: P.unlockLine(user),
    })
  }
}

const versions = [null, '', 'Navidrome 0.64.2 (abc)', 'Navidrome 0.64 (abc)', '0.64', '0.65.0', 'Navidrome 0.65.0 (7a8b)', 'Navidrome 0.640.1',
  'v1.2', 'x10.64.1', '0.6', 'abc 12', 'Navidrome 0.64.2 (1.2.3)', '1..2 3.4', '00.64', '0.064', '\u0661.\u0662 0.65', '0.65.', '.64.1',
  'Navidrome 0.65.0-SNAPSHOT', ' 12.3.4.5', '1.2.3.4', '0.64.10', '10.64', 'no version here', '0.6a.1 2.0', '1.0.0'].map((server) => ({ server, said: P.versionNote(server) }))

const views = [null,
  { on: false, available: false, locked: true, problem: 'People needs logins on.', fix: null, you: 'local', account: null, people: [], known_only: [] },
  { on: true, available: true, locked: true, problem: null, fix: null, you: 'james', account: 'demo', people: [], known_only: [] },
  { on: true, available: true, locked: false, problem: null, fix: null, you: 'james', account: 'demo', people: [], known_only: [] },
  { on: true, available: false, locked: false, problem: 'Navidrome says james is not one of its admins.', fix: 'Ask one.', you: 'james', account: 'demo', people: [], known_only: [] },
  { on: true, available: true, locked: true, problem: 'Navidrome asked for your password again.', fix: null, you: 'james', account: 'demo', people: [], known_only: [] },
].map((state) => ({ state, view: P.peopleView(state) }))

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
  about: "People (lib/people.ts and lib/permissions.ts run as they are; app/People.tsx's, UnlockPeople.tsx's, AddPerson.tsx's, ResetPassword.tsx's, RemovePerson.tsx's, usePeople.ts's and api/people.ts's own, read out of their source). A row's `person` is the server's shape; `now` is the epoch second its sign-in words are said at. `said`, `problem`, `warning` and `reason` are null where the web says nothing.",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  now: NOW,
  words,
  page,
  names,
  displays,
  forms,
  resets,
  people,
  agos,
  known,
  ready,
  changes,
  after,
  versions,
  views,
}
const LISTED = new Set(['names', 'displays', 'forms', 'resets', 'people', 'agos', 'known', 'ready', 'changes', 'after', 'versions', 'views'])
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => LISTED.has(key)
    ? `  ${flat(key)}: [\n${value.map((item) => `    ${flat(item)}`).join(',\n')}\n  ]`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')
const counted = `${names.length} names, ${displays.length} display names, ${forms.length} forms, ${resets.length} resets, ${people.length} rows, ${known.length} known only`
if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`People's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`People's fixture matches the web app's TypeScript (${counted}).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
}
