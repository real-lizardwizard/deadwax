/**
 * People on the page (2.0.0-player.61) - lib/people.ts.
 *
 * What it pins:
 *
 *  - The name, display name and password checks, in src/people.py's words (tests/test_people.py holds the
 *    numbers to the server's): lowercase letters, digits, dot, underscore and hyphen, 1-32, starting with a letter
 *    or digit, never a reserved name; a display name 0-64 with no control characters; a password 8-128, no control
 *    characters, not the user name in any case, typed twice the same. What shows while typing: never a scold for a
 *    field not yet reached.
 *  - A row: its chips, its sign-in and library words, the no-library warning (a non-admin's only), its actions
 *    from the server's `can` - each present, or its reason in words - and Make admin's and No longer admin's words.
 *  - Remove: its lines from the server's numbers, and the typed-name gate - exactly the name; another case or a
 *    trailing space doesn't enable it.
 *  - The plain-http note on http: and not on https:; the version note only for another minor version.
 *  - The page's view: asking, unavailable, locked, the list.
 *
 * Run it with:  node ui/test/people.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-people-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/people.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })
const L = require(path.join(OUT, 'lib/people.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

console.log('\na new account\'s name')
check('trimmed and lowercased', L.cleanName('  Maya '), 'maya')
check('the ones that do', ['maya', 'm', 'maya.r_2-b', '0x', 'x'.repeat(32)].map(L.nameProblem), [null, null, null, null, null])
check('...and the ones that don\'t', ['', 'x'.repeat(33), '-maya', '.maya', 'ma ya', 'maya!', 'mäya', 'local', 'deadwax'].map(L.nameProblem), [
  'Type a user name.', 'A user name is at most 32 characters.',
  ...Array(5).fill('A user name is lowercase letters, digits, dots, underscores and hyphens, starting with a letter or a digit.'),
  "'local' is a name deadwax keeps for itself - choose another.", "'deadwax' is a name deadwax keeps for itself - choose another."])
check('a display name: optional, at most 64, no control characters',
  [L.displayProblem(''), L.displayProblem('Maya Rudolph'), L.displayProblem('x'.repeat(65)), L.displayProblem('bell\u0007'), L.displayProblem('zero​width')],
  [null, null, 'A display name is at most 64 characters.', "A display name can't have control characters in it.", "A display name can't have control characters in it."])

console.log('\na password')
check('8 to 128, not the user name in any case, typed twice the same, never trimmed', [
  L.passwordProblem('long-enough', 'long-enough', 'maya'), L.passwordProblem(' padded  ', ' padded  ', 'maya'),
  L.passwordProblem('short', 'short', 'maya'), L.passwordProblem('x'.repeat(129), 'x'.repeat(129), 'maya'),
  L.passwordProblem('MayaMaya', 'MayaMaya', 'mayamaya'), L.passwordProblem('long-enough', 'long-enougH', 'maya'),
  L.passwordProblem('tab\there-pw', 'tab\there-pw', 'maya')],
  [null, null, 'A password is at least 8 characters.', 'A password is at most 128 characters.', "A password can't be the user name.",
    "The two passwords aren't the same.", "A password can't have control characters in it."])
check('the numbers (the server\'s - test_people holds them)', [L.NAME_MAX, L.DISPLAY_MAX, L.PASSWORD_MIN, L.PASSWORD_MAX, L.UNLOCK_IDLE_MINUTES, L.RESERVED], [32, 64, 8, 128, 15, ['local', 'deadwax']])
const empty = { user: '', name: '', password: '', again: '' }
check('while typing: nothing said for a field not yet reached; the first problem once there is something to say', [
  L.formProblem(empty), L.formProblem({ ...empty, user: 'Ma Ya' }), L.formProblem({ ...empty, user: 'maya', password: 'short' }),
  L.formProblem({ ...empty, user: 'maya', password: 'long-enough', again: 'long' })],
  [null, 'A user name is lowercase letters, digits, dots, underscores and hyphens, starting with a letter or a digit.', null, "The two passwords aren't the same."])
check('...Make account only with every rule met', [L.formReady(empty), L.formReady({ user: 'Maya', name: '', password: 'long-enough', again: 'long-enough' })], [false, true])

console.log('\na row')
const person = (more = {}) => ({ id: 'nd1', user: 'ethan', name: 'Ethan', admin: false, shared_account: false, reserved: false, you: false,
  signed_in: 0, last_sign_in: null, library: 312, waiting_alone: 0, libraries: 1, permissions: null,
  can: { reset: null, remove: null, admin: null, permissions: null }, ...more })
check('its chips', [L.chips(person()), L.chips(person({ you: true, admin: true })), L.chips(person({ shared_account: true })), L.chips(person({ reserved: true }))],
  [[], ['You', 'Admin'], ["deadwax's own account"], ["Can't sign in to deadwax"]])
const now = 1_000_000
check('its deadwax sign-in', [L.signInWords(person({ signed_in: 2 }), now), L.signInWords(person({ signed_in: 1 }), now),
  L.signInWords(person({ last_sign_in: now - 3 * 86400 }), now), L.signInWords(person({ last_sign_in: now - 90 }), now), L.signInWords(person(), now)],
  ['Signed in on 2 devices', 'Signed in on 1 device', 'Last signed in 3 days ago', 'Last signed in 1 minute ago', 'Never signed in to deadwax'])
check('its library', [L.libraryWords(person()), L.libraryWords(person({ library: 1 }))], ['312 albums in their library', '1 album in their library'])
check('Navidrome giving a non-admin no library is said; an admin\'s never', [L.librariesWarning(person({ libraries: 0 })), L.librariesWarning(person({ libraries: 0, admin: true })), L.librariesWarning(person())],
  ["Navidrome gives them no library - they'll see nothing. Tick one for them in Navidrome's Users page.", null, null])
check('its actions, from the server\'s can', L.actions(person()).map((action) => [action.kind, action.label, action.refused]),
  [['reset', 'Reset password…', null], ['admin', 'Make admin', null], ['remove', 'Remove…', null]])
const you = person({ you: true, admin: true, can: { reset: "That's you - change your own password in You → Change password.", remove: "deadwax doesn't remove the account you're signed in with.",
  admin: "You can't take away your own admin role.", permissions: "That's you - an admin has every permission." } })
check('...refused ones with their reasons, in words - never a bare greyed button', [L.actions(you).map((action) => action.label), L.refusals(you)],
  [['Reset password…', 'No longer admin', 'Remove…'], ["That's you - change your own password in You → Change password.", "You can't take away your own admin role.", "deadwax doesn't remove the account you're signed in with."]])
const shared = person({ can: { reset: 'S', remove: 'S', admin: 'S', permissions: 'S' } })
check('...one reason said once, however many actions share it', L.refusals(shared), ['S'])
check('Make admin says what it gives, in Navidrome and Amperfy too', [L.makeAdminWords('maya').question, L.makeAdminWords('maya').body.includes('every library'),
  L.makeAdminWords('maya').body.includes("everyone's playlists, private ones included")], ['Make maya an admin?', true, true])
check('No longer admin says what they keep - and what was ticked before', [L.unmakeAdminWords('maya', []).body, L.unmakeAdminWords('maya', ['Edit albums']).body],
  ["maya keeps every library Navidrome gave them as an admin - narrow them in Navidrome's Users page if they shouldn't see them all.",
    "maya keeps every library Navidrome gave them as an admin - narrow them in Navidrome's Users page if they shouldn't see them all. They keep what was ticked for them before: Edit albums."])

console.log('\nRemove')
const lines = L.removeLines(person({ signed_in: 2, waiting_alone: 1 }))
check('what goes, what stays, from the server\'s numbers', [lines.navidrome, lines.deadwax, lines.stays, lines.undo], [
  "In Navidrome, for good: ethan's account, their play counts and play history, their favourites (the 312 albums in their library), all their playlists - shared ones too - and their Last.fm or ListenBrainz link.",
  'In deadwax: their sign-ins (2 devices), their library list, their pins, their play queue, Getting albums settings and permissions.',
  'Stays: every album in the store. 1 download only they are waiting for carries on and is filed for nobody - cancel it in Requests first if nobody wants it.',
  "There's no undo. If they might come back, reset their password instead."])
check('...no numbers where there are none - never "the 0 albums" or "(0 devices)"', [L.removeLines(person({ library: 0 })).navidrome.includes('their favourites, all'), L.removeLines(person()).deadwax.startsWith('In deadwax: their sign-ins, their')],
  [true, true])
check('...an admin\'s role named; nothing waiting, nothing said of it', [L.removeLines(person({ admin: true })).navidrome.endsWith(', and their admin role.'), L.removeLines(person()).stays],
  [true, 'Stays: every album in the store.'])
check('the typed name: exactly it - another case, a space, nothing, never', ['ethan', 'Ethan', 'ethan ', ' ethan', '', 'etha'].map((typed) => L.removeReady(typed, 'ethan')),
  [true, false, false, false, false, false])

console.log('\nthe page')
check('the plain-http note: on http, never on https', [L.httpNote('http:') === L.HTTP_NOTE, L.httpNote('https:')], [true, null])
check('...its words', L.HTTP_NOTE, "This page isn't over HTTPS: a password typed here crosses your network readable, as everyone's sign-in does. That's fine on your own network or over WireGuard; anywhere else, put HTTPS in front of deadwax first.")
check('the version note: only for another minor version - a note, never a block', [L.versionNote('navidrome 0.64.2 (abc123)'), L.versionNote('navidrome 0.65.0 (def)'), L.versionNote('navidrome'), L.versionNote(null)],
  [null, 'People was made for Navidrome 0.64 - this is 0.65.0.', null, null])
const state = (more) => ({ on: true, available: true, locked: true, problem: null, fix: null, you: 'admin', account: 'demo', people: [], known_only: [], ...more })
check('what it draws: asking, the problem alone, the unlock, the list', [L.peopleView(null), L.peopleView(state({ available: false })), L.peopleView(state()), L.peopleView(state({ locked: false }))],
  ['asking', 'unavailable', 'locked', 'list'])
check('the unlock\'s words name you', L.unlockLine('james'), "People changes Navidrome's accounts as you, james. Navidrome needs your password for that; deadwax uses it once and doesn't keep it.")
check('after a change', [L.madeWords('ethan2', 'http://deadwax.lan:8080'), L.resetWords('ethan', 2)],
  ["Made ethan2. Tell them their user name, the password you chose and deadwax's address (http://deadwax.lan:8080/player/) - Amperfy signs in with the same.",
    'Done. ethan is signed out of deadwax on 2 devices and signs in with the new password - Amperfy and any other app they use need it too.'])
check('Known only to deadwax: what is kept', L.knownWords({ user: 'olduser', sessions: 0, credential: true, library: 12, pins: 3, preferences: true, requests: 1, permissions: 0 }),
  'deadwax keeps a kept login, 12 albums in their library, 3 pins, Getting albums settings, 1 request.')
//? (2.0.0-player.64) a name with only a play queue left - which still keeps a new account of that name from being made
check('...a play queue alone, said', L.knownWords({ user: 'olduser', sessions: 0, credential: false, library: 0, pins: 0, preferences: false, requests: 0, permissions: 0, queue: true }),
  'deadwax keeps a play queue.')

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
