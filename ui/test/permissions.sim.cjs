/**
 * What the app shows by what the person may do (2.0.0-player.61) - lib/permissions.ts.
 *
 * What it pins:
 *
 *  - /me's answer read: only the names it knows; an answer from before the list by its `admin`.
 *  - Every managing part for every single-permission set and for none: Managing deadwax's rows (Albums that need a
 *    look by Look after the library, Library care by it or Edit albums, People by People - with logins on only -,
 *    Server settings and Log by Settings and the log), the group gone with none; Library care's parts; the album
 *    page's Edit and its tabs; the artist page's managing; Get; the queue count.
 *  - People's checkboxes: an admin's all ticked and locked ("Admins can do everything."), a refused row locked with
 *    the server's words, an ordinary person's as ticked - with the warnings Settings and the log and Look after the
 *    library add, and unticking Get albums' line; a draft changed or not; Save's words.
 *  - Get's replacement words, and the page note's.
 *
 * Run it with:  node ui/test/permissions.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-permissions-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/permissions.ts', 'src/lib/albumEdit.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })
const P = require(path.join(OUT, 'permissions.js'))
const E = require(path.join(OUT, 'albumEdit.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const set = (...names) => new Set(names)
const list = (perms) => P.PERMISSIONS.filter((name) => perms.has(name))

console.log('\nreading /me')
check('the six, in /me\'s order', P.PERMISSIONS, ['request', 'edit', 'library', 'downloads', 'server', 'people'])
check('...the five an admin ticks', P.CATEGORIES, ['request', 'edit', 'library', 'downloads', 'server'])
check('only names it knows, whatever order', list(P.permissionsOf({ permissions: ['edit', 'request', 'root', 'people '] })), ['request', 'edit'])
check('an answer with no list: by its admin', [list(P.permissionsOf({ admin: true })), list(P.permissionsOf({ admin: false })), list(P.permissionsOf(null))],
  [P.PERMISSIONS, [], []])
check('...a list beats admin (a Navidrome admin is sent every one anyway)', list(P.permissionsOf({ admin: true, permissions: ['request'] })), ['request'])
check('sets compared by what is in them', [P.samePermissions(set('edit', 'request'), set('request', 'edit')), P.samePermissions(set('edit'), set('request'))], [true, false])

console.log('\nevery managing part, for each single permission and for none')
const ALLROWS = { queue: true, care: true, people: true, settings: true, log: true, any: true }
const rows = {
  none: { queue: false, care: false, people: false, settings: false, log: false, any: false },
  request: { queue: false, care: false, people: false, settings: false, log: false, any: false },
  edit: { queue: false, care: true, people: false, settings: false, log: false, any: true },
  library: { queue: true, care: true, people: false, settings: false, log: false, any: true },
  downloads: { queue: false, care: false, people: false, settings: false, log: false, any: false },
  server: { queue: false, care: false, people: false, settings: true, log: true, any: true },
  people: { queue: false, care: false, people: true, settings: false, log: false, any: true },
}
for (const [name, expected] of Object.entries(rows)) {
  const perms = name === 'none' ? P.NONE : set(name)
  check(`Managing deadwax with ${name}`, P.managing(perms), expected)
}
check('an admin: every row', P.managing(P.ALL), ALLROWS)
check('...People only with logins on (off, `local` has it, and there is nobody to manage)', [P.managing(P.ALL, false).people, P.managing(P.ALL, false).any], [false, true])
check('...but its page opens on its permission alone, and says why itself', [P.opensPage(P.ALL, 'people'), P.opensPage(set('library'), 'people'), P.opensPage(set('library'), 'queue')], [true, false, true])

const care = { none: [false, false, false, false], edit: [true, false, false, true], library: [true, true, true, false], server: [false, false, false, false] }
for (const [name, expected] of Object.entries(care)) {
  const c = P.careParts(name === 'none' ? P.NONE : set(name))
  check(`Library care's parts with ${name} (shown, rescan, held, bulk)`, [c.shown, c.rescan, c.held, c.bulk], expected)
}
check('...an admin\'s: all', Object.values(P.careParts(P.ALL)), [true, true, true, true])

const edits = { none: [false, false, false], request: [false, false, false], edit: [true, true, false], library: [true, false, true], downloads: [false, false, false] }
for (const [name, expected] of Object.entries(edits)) {
  const e = P.albumEdit(name === 'none' ? P.NONE : set(name))
  check(`the album page's Edit with ${name} (shown, editors, delete)`, [e.shown, e.editors, e.delete], expected)
}
check('...its tabs: the editors with Edit albums, Delete with Look after the library',
  [E.editTabs(true, false).map((tab) => tab.id), E.editTabs(false, true).map((tab) => tab.id), E.editTabs(true, true).map((tab) => tab.id)],
  [['release', 'tags', 'artwork', 'lyrics'], ['delete'], ['release', 'tags', 'artwork', 'lyrics', 'delete']])
check('Delete\'s Cancel goes back to the first editor\'s tab - or, Delete the only tab, closes the panel (second review)',
  [E.cancelDeleteTo(E.editTabs(true, true)), E.cancelDeleteTo(E.editTabs(false, true)), E.cancelDeleteTo(E.editTabs(true, false)), E.cancelDeleteTo([])],
  ['release', null, 'release', null])
check('...the arrow keys go round the tabs shown, never to one hidden', [E.tabAfter('lyrics', 1, E.editTabs(true, false)), E.tabAfter('delete', 1, E.editTabs(false, true)), E.tabAfter('release', -1)],
  ['release', 'delete', 'delete'])

const artist = { none: [false, false, false, false], edit: [true, true, false, true], library: [false, false, true, true], server: [false, false, false, false] }
for (const [name, expected] of Object.entries(artist)) {
  const a = P.artistManaging(name === 'none' ? P.NONE : set(name))
  check(`the artist page's managing with ${name} (images, which artist, move, any)`, [a.images, a.whichArtist, a.move, a.any], expected)
}
check('Get, Sources, Next peer and Ask again: Get albums\'', [P.gets(set('request')), P.gets(set('edit', 'library', 'downloads', 'server')), P.gets(P.ALL)], [true, false, true])
check('...without it, said in Get\'s place', P.GET_OFF, 'Getting albums is off for you - ask an admin.')
check('the queue count asked only with Look after the library', [P.asksQueueSummary(set('library')), P.asksQueueSummary(set('edit')), P.asksQueueSummary(P.NONE)], [true, false, false])
check('a Managing page refused, in words', P.NO_PERMISSION, "You don't have permission for this page.")

console.log('\nPeople\'s checkboxes')
const ticked = { request: true, edit: false, library: false, downloads: false, server: false }
const boxes = P.checkboxes(false, null, ticked)
check('an ordinary person\'s: the five, as ticked, none locked', boxes.map((box) => [box.category, box.checked, box.locked]),
  [['request', true, false], ['edit', false, false], ['library', false, false], ['downloads', false, false], ['server', false, false]])
check('...each labelled and explained', boxes.map((box) => box.label), ['Get albums', 'Edit albums', 'Look after the library', "Everyone's downloads", 'Settings and the log'])
check('...nothing to warn of at the defaults', boxes.map((box) => box.warning), [null, null, null, null, null])
const risky = P.checkboxes(false, null, { request: false, edit: true, library: true, downloads: true, server: true })
check('ticking Settings and the log, and Look after the library, says what they open; unticking Get albums what is left',
  [risky[4].warning, risky[2].warning, risky[0].warning, risky[1].warning, risky[3].warning],
  [P.WARN_SERVER, P.WARN_LIBRARY, P.WARN_NO_REQUEST, null, null])
check('...the words', [P.WARN_SERVER, P.WARN_LIBRARY, P.WARN_NO_REQUEST],
  ["Settings can point deadwax at other folders and change how it downloads and files - give it only to someone you'd trust as an admin.",
    "This includes deleting albums from disk, which can't be undone.", 'They can still play, browse and add what the store has.'])
const admin = P.checkboxes(true, 'Admins have every permission - that changes with Make admin.', null)
check('a Navidrome admin\'s: all ticked, all locked, no warnings - "Admins can do everything."',
  [admin.every((box) => box.checked && box.locked && !box.warning), P.lockedReason(true, 'whatever')], [true, 'Admins can do everything.'])
check('...locked by being an admin alone, whatever the server said of the row', P.checkboxes(true, null, ticked).every((box) => box.checked && box.locked), true)
const yours = P.checkboxes(false, "That's you - an admin has every permission.", ticked)
check('a row People refuses them for (you, deadwax\'s own account, a reserved name): locked as they are, with its reason',
  [yours.every((box) => box.locked && !box.warning), yours.map((box) => box.checked), P.lockedReason(false, "That's you - an admin has every permission.")],
  [true, [true, false, false, false, false], "That's you - an admin has every permission."])
check('People is no checkbox', [boxes.some((box) => box.category === 'people'), P.PEOPLE_LINE], [false, 'People - Navidrome admins only'])
check('Save offered only when the draft differs from what was saved',
  [P.changed(ticked, { ...ticked }), P.changed(ticked, { ...ticked, edit: true }), P.changed(null, ticked)], [false, true, false])
check('...and what it says once saved', P.savedWords('ethan'), 'Saved - ethan has them from their next tap.')
check('You, when an admin gave something this session doesn\'t honour', P.UNVERIFIED,
  "deadwax couldn't check your account with Navidrome as you signed in, so the extra permissions an admin gave you are off until you sign in again.")

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
