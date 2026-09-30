/**
 * Where the app at /player/ is - lib/appRoutes.ts, the tab and the pages pushed on it
 * (2.0.0-player.9).
 *
 * What it pins:
 *
 *  - The address: `#/<tab>` and `#/<tab>/album/<id>` read and written, ids of any characters
 *    round-tripping; the player's old `#/album/<id>` links opening the Library's album and
 *    rewritten to its new address; an empty hash going to Home; nonsense going somewhere sensible.
 *  - Per-tab stacks, as in iOS: a page opened stays under the tab that opened it, switching tabs
 *    shows each as it was left, re-tapping the tab you are on pops it to its root and tapping it
 *    again at the root only scrolls (nothing changes), and a double tap opens one page, not two.
 *  - Back labels name the page below: the tab at the bottom, the page under this one above that.
 *  - The browser's history: back is history's own back only when the entries below are exactly
 *    the pages below, made in this session - so a cold deep link, or a page below that another
 *    tab's switch wrote over, is gone back from by replacing the address instead. After a reload
 *    the entries below are known again from the tab's sessionStorage (lib/appHistory.ts), so back
 *    is still history's own and leaves no copy of the entry below behind - never another load's.
 *  - What the browser's own back and forward do to the stacks: within a tab it follows them; onto
 *    another tab's entry it shows that tab AS IT WAS LEFT, pages kept, and rewrites the entry.
 *  - All of it end to end: lib/appHistory.ts's router driven against a fake browser history that
 *    keeps entries and their state across a reload, fires popstate and then hashchange on a
 *    traversal, and runs history.go() later, as a browser does.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/routes.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-routes-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/appRoutes.ts', 'src/lib/appHistory.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const R = require(path.join(OUT, 'appRoutes.js'))
const H = require(path.join(OUT, 'appHistory.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const album = (id, label) => (label ? { kind: 'album', id, label } : { kind: 'album', id })
const stackIds = (nav, tab) => nav.stacks[tab].map((page) => page.id)

console.log('\nthe five tabs, You at the right end')
check('in the tab bar\'s order', R.TABS, ['home', 'library', 'search', 'requests', 'you'])
check('their names', R.TABS.map((tab) => R.TAB_LABELS[tab]), ['Home', 'Library', 'Search', 'Requests', 'You'])

console.log('\nreading and writing the address')
for (const tab of R.TABS) {
  check(`#/${tab} is its root`, R.parseHash(`#/${tab}`), { route: { tab, page: null }, canonical: `#/${tab}` })
}
check('an album pushed on Library', R.parseHash('#/library/album/al-1'),
  { route: { tab: 'library', page: album('al-1') }, canonical: '#/library/album/al-1' })
check('an album pushed on Home', R.parseHash('#/home/album/al-1').route, { tab: 'home', page: album('al-1') })
{
  const id = 'a b/c?d#e%f ü'
  const address = R.formatRoute({ tab: 'library', page: album(id) })
  check('an id of any characters is escaped', address, '#/library/album/a%20b%2Fc%3Fd%23e%25f%20%C3%BC')
  check('...and reads back as itself', R.parseHash(address).route.page.id, id)
}
check('a stray % that isn\'t an escape is taken as it is', R.parseHash('#/library/album/100%').route.page.id, '100%')
check('a label is never part of the address', R.formatRoute({ tab: 'home', page: album('x', 'Dummy') }), '#/home/album/x')

console.log('\nthe player\'s old links, and an empty hash')
check('#/album/<id> opens in Library', R.parseHash('#/album/al-9'),
  { route: { tab: 'library', page: album('al-9') }, canonical: '#/library/album/al-9' })
check('an escaped legacy id keeps its characters', R.parseHash('#/album/a%2Fb').route.page.id, 'a/b')
for (const hash of ['', '#', '#/']) {
  check(`${JSON.stringify(hash)} is Home`, R.parseHash(hash), { route: { tab: 'home', page: null }, canonical: '#/home' })
}
check('an unknown tab is Home', R.parseHash('#/nowhere').canonical, '#/home')
check('an unknown page is its tab\'s root', R.parseHash('#/library/nope/x').canonical, '#/library')
check('an album with no id is its tab\'s root', R.parseHash('#/library/album/').canonical, '#/library')
check('a query string is dropped, not read as part of the id', R.parseHash('#/library/album/x?y=1').route.page.id, 'x')

console.log('\nper-tab stacks')
{
  let nav = R.startNav(R.parseHash('#/home').route)
  check('starts on Home at its root', [nav.tab, stackIds(nav, 'home')], ['home', []])
  nav = R.openPage(nav, album('A', 'Dummy'))
  check('an album opened from Home is pushed on Home', [nav.tab, stackIds(nav, 'home')], ['home', ['A']])
  const twice = R.openPage(nav, album('A', 'Dummy'))
  check('opening the page already on top changes nothing (a double tap)', twice === nav, true)
  let step = R.selectTab(nav, 'library')
  check('another tab: switch', step.action, 'switch')
  nav = step.nav
  check('Library shows at its root, and Home keeps its album', [nav.tab, stackIds(nav, 'library'), stackIds(nav, 'home')], ['library', [], ['A']])
  nav = R.openPage(nav, album('B', 'Third'))
  nav = R.openPage(nav, album('C', 'Portishead'))
  check('Library has its own pages', stackIds(nav, 'library'), ['B', 'C'])
  nav = R.selectTab(nav, 'home').nav
  check('back to Home: its album, as it was left', R.currentRoute(nav), { tab: 'home', page: album('A', 'Dummy') })
  nav = R.selectTab(nav, 'library').nav
  check('back to Library: its top page', R.currentRoute(nav).page.id, 'C')

  step = R.selectTab(nav, 'library')
  check('the tab you are on, with pages: pop to its root', [step.action, stackIds(step.nav, 'library')], ['pop-to-root', []])
  check('...and the other tab is left alone', stackIds(step.nav, 'home'), ['A'])
  const again = R.selectTab(step.nav, 'library')
  check('tapped again at its root: scroll to the top, nothing else', [again.action, again.nav === step.nav], ['scroll-to-top', true])

  check('back takes one page off', stackIds(R.popPage(nav), 'library'), ['B'])
  const atRoot = R.popPage(R.popPage(nav))
  check('back at the root changes nothing', R.popPage(atRoot) === atRoot, true)
}

console.log('\nback labels come from the page below')
{
  let nav = R.startNav({ tab: 'library', page: null })
  check('no back button at a root', R.backLabel(nav), null)
  nav = R.openPage(nav, album('B', 'Third'))
  check('one page up: the tab', R.backLabel(nav), 'Library')
  nav = R.openPage(nav, album('C', 'Roseland NYC Live'))
  check('two up: the page under it', R.backLabel(nav), 'Third')
  nav = R.openPage(nav, album('D'))
  check('under it a page with no label: still named', R.backLabel(nav), 'Roseland NYC Live')
  check('for another tab, asked by name', R.backLabel(R.openPage(R.selectTab(nav, 'home').nav, album('E')), 'home'), 'Home')
  check('the addresses below, nearest first, down to the root', R.addressesBelow(nav),
    ['#/library/album/C', '#/library/album/B', '#/library'])
  check('none below a root', R.addressesBelow(R.startNav({ tab: 'you', page: null })), [])
}

console.log('\na cold deep link')
{
  const { route, canonical } = R.parseHash('#/home/album/X')
  const nav = R.startNav(route)
  check('opens on its tab, with its page on the root', [nav.tab, stackIds(nav, 'home')], ['home', ['X']])
  check('back says the tab', R.backLabel(nav), 'Home')
  const note = R.startHistory(null, canonical)
  check('nothing of this app\'s below it: back replaces the address', R.stepsBack(note, R.addressesBelow(nav).slice(0, 1)), 0)
  check('...and lands on the tab\'s root', R.currentRoute(R.popPage(nav)), { tab: 'home', page: null })
  const legacy = R.startNav(R.parseHash('#/album/Y').route)
  check('a legacy link, cold: the Library, its album, back to the Library', [legacy.tab, stackIds(legacy, 'library'), R.backLabel(legacy)], ['library', ['Y'], 'Library'])
}

console.log('\nthe browser\'s history')
{
  let note = R.startHistory(0, '#/library')
  note = R.pushed(note, '#/library/album/A')
  check('a page opened here pushes an entry', [note.index, note.entries], [1, ['#/library', '#/library/album/A']])
  check('back from it is history\'s own back', R.stepsBack(note, ['#/library']), 1)
  note = R.pushed(note, '#/library/album/B')
  check('popping two pages to the root is two steps of it', R.stepsBack(note, ['#/library/album/A', '#/library']), 2)
  check('an entry below that isn\'t the page below: replace instead', R.stepsBack(note, ['#/library/album/Z']), 0)

  // Library: open A. Switch to Home (replaces the entry). Open B there (pushes). Switch back to
  // Library (replaces B's entry with A's). The entry under A is now Home's, not Library's root.
  let mixed = R.pushed(R.startHistory(0, '#/library'), '#/library/album/A')
  mixed = R.replaced(mixed, '#/home')
  mixed = R.pushed(mixed, '#/home/album/B')
  mixed = R.replaced(mixed, '#/library/album/A')
  check('a page below written over by another tab\'s switch: replace, never go back into Home', R.stepsBack(mixed, ['#/library']), 0)

  const reloaded = R.startHistory(3, '#/library/album/A')
  check('after a reload the entries below are unknown: replace', R.stepsBack(reloaded, ['#/library']), 0)
  check('a reload keeps the place the entry says', reloaded.index, 3)

  let typed = R.moved(note, null, '#/you')
  check('an address typed in is a new entry after this one', [typed.index, typed.entries[typed.index]], [3, '#/you'])
  const back = R.moved(note, 1, '#/library/album/A')
  check('the browser\'s back to an entry this page made', back.index, 1)
  check('nothing to go back through: 0 steps', R.stepsBack(R.startHistory(0, '#/home'), []), 0)
}

console.log('\nthe browser moving on its own')
{
  let nav = R.startNav({ tab: 'library', page: null })
  nav = R.openPage(R.openPage(nav, album('A')), album('B'))
  check('back to a page in the stack: the stack goes back to it', stackIds(R.followRoute(nav, { tab: 'library', page: album('A') }), 'library'), ['A'])
  check('back to the root: empty', stackIds(R.followRoute(nav, { tab: 'library', page: null }), 'library'), [])
  check('forward to a page not in it: pushed', stackIds(R.followRoute(nav, { tab: 'library', page: album('C') }), 'library'), ['A', 'B', 'C'])
  const other = R.followRoute(nav, { tab: 'home', page: null })
  check('to another tab: it shows, and this one keeps its pages', [other.tab, stackIds(other, 'library')], ['home', ['A', 'B']])
}

console.log('\nthe browser\'s own back or forward onto another tab\'s entry: that tab as it was left')
{
  // Home: open Dummy (pushed). Tap Library (the entry is replaced). The entry below is Home's root.
  let nav = R.openPage(R.startNav({ tab: 'home', page: null }), album('A', 'Dummy'))
  nav = R.selectTab(nav, 'library').nav
  let note = R.replaced(R.pushed(R.startHistory(0, '#/home'), '#/home/album/A'), '#/library')
  const back = R.browserMoved(nav, note, 0, '#/home')
  check('Home shows, with its album still on it', [back.nav.tab, stackIds(back.nav, 'home')], ['home', ['A']])
  check('...and the entry is rewritten to the album, the page on show', [back.address, back.rewrite, back.note.entries], ['#/home/album/A', true, ['#/home/album/A', '#/library']])
  check('the Library is left as it was', stackIds(back.nav, 'library'), [])

  // Home: A then B. Tap Library. Back lands on Home's A entry: Home keeps B on top.
  nav = R.selectTab(R.openPage(R.openPage(R.startNav({ tab: 'home', page: null }), album('A')), album('B')), 'library').nav
  note = R.replaced(R.pushed(R.pushed(R.startHistory(0, '#/home'), '#/home/album/A'), '#/home/album/B'), '#/library')
  const deeper = R.browserMoved(nav, note, 1, '#/home/album/A')
  check('landing on a page lower in that tab\'s stack keeps the pages above it', [stackIds(deeper.nav, 'home'), deeper.address], [['A', 'B'], '#/home/album/B'])

  // Within the tab showing, the stack follows the entry, as before.
  nav = R.openPage(R.openPage(R.startNav({ tab: 'library', page: null }), album('A')), album('B'))
  note = R.pushed(R.pushed(R.startHistory(0, '#/library'), '#/library/album/A'), '#/library/album/B')
  const same = R.browserMoved(nav, note, 1, '#/library/album/A')
  check('within the tab showing: back to the page, nothing rewritten', [stackIds(same.nav, 'library'), same.address, same.rewrite], [['A'], '#/library/album/A', false])

  // An address typed in says where to go, even another tab's root.
  const typed = R.browserMoved(R.openPage(R.startNav({ tab: 'home', page: null }), album('A')), R.startHistory(0, '#/home/album/A'), null, '#/library/album/Z')
  check('an address typed in is followed, onto its tab', [typed.nav.tab, stackIds(typed.nav, 'library'), typed.rewrite, typed.note.index], ['library', ['Z'], true, 1])
  const legacy = R.browserMoved(R.startNav({ tab: 'home', page: null }), R.startHistory(0, '#/home'), null, '#/album/Y')
  check('a legacy address typed in is followed and rewritten', [legacy.nav.tab, legacy.address], ['library', '#/library/album/Y'])
}

console.log('\nafter a reload, the entries below are known again')
{
  const saved = ['#/library', '#/library/album/B']
  const note = R.startHistory(1, '#/library/album/B', saved)
  check('the saved note says what is below', R.stepsBack(note, ['#/library']), 1)
  check('JSON\'s nulls are unknown entries, not addresses', R.startHistory(2, '#/you', [null, '#/home']).entries, [undefined, '#/home', '#/you'])
  check('a load on an entry with no place of its own uses no saved note', R.startHistory(null, '#/home', saved).entries, ['#/home'])

  const store = new Map()
  const storage = { getItem: (key) => (store.has(key) ? store.get(key) : null), setItem: (key, value) => store.set(key, value) }
  H.saveNote(storage, 'L1', note)
  check('a note is kept under its load', H.readNote(storage, 'L1'), saved)
  check('...and never read for another load', H.readNote(storage, 'L2'), null)
  const refusing = { getItem() { throw new Error('denied') }, setItem() { throw new Error('denied') } }
  check('a storage that refuses: nothing read, nothing thrown', [H.readNote(refusing, 'L1'), H.saveNote(refusing, 'L1', note)], [null, undefined])
  store.set('deadwax-player-history:L3', '{"not": "a list"}')
  check('something else under the key is no note', H.readNote(storage, 'L3'), null)
  check('an entry\'s state: its place and its load', H.entryState(note, 'L1'), { n: 1, load: 'L1' })
  check('...read back', [H.placeOf({ n: 1, load: 'L1' }), H.loadOf({ n: 1, load: 'L1' })], [1, 'L1'])
  check('a state from before loads were recorded has a place and no load', [H.placeOf({ n: 3 }), H.loadOf({ n: 3 })], [3, null])
  check('nothing, or nonsense, is neither', [H.placeOf(null), H.placeOf({ n: -1 }), H.placeOf({ n: 1.5 }), H.loadOf({ load: '' })], [null, null, null, null])
  const a = H.newLoad(), b = H.newLoad()
  check('a load\'s name is a word, and each is its own', [typeof a === 'string' && a.length > 6, a !== b], [true, true])
}

/* ===== end to end: the router against a fake browser history ===== */

/**
 * A browser's session history as far as the app can see it: entries with their address and state
 * (kept across a reload), pushState dropping what was ahead, history.go() run LATER (a task, as a
 * browser queues it), and a traversal firing popstate and then - when the address changed -
 * hashchange, both read by the app after any rewrite the first one made. An entry that isn't the
 * app's (a page before it) means going back to it left the app.
 */
function makeBrowser(startHash, { before = [], storage } = {}) {
  const b = {
    entries: [...before.map((hash) => ({ app: false, hash, state: null })), { app: true, hash: startHash, state: null }],
    index: before.length,
    queued: [],
    left: false,
    shown: [],
    router: null,
    loads: 0,
  }
  const store = new Map()
  b.storage = storage ?? { getItem: (key) => (store.has(key) ? store.get(key) : null), setItem: (key, value) => store.set(key, value) }
  const copy = (state) => (state === null || state === undefined ? null : JSON.parse(JSON.stringify(state)))
  b.history = {
    get state() { return b.entries[b.index].state },
    pushState(state, _unused, url) {
      b.entries.splice(b.index + 1)
      b.entries.push({ app: true, hash: url, state: copy(state) })
      b.index += 1
    },
    replaceState(state, _unused, url) {
      b.entries[b.index] = { ...b.entries[b.index], hash: url, state: copy(state) }
    },
    go(delta) { b.queued.push(() => b.traverse(delta)) },
  }
  b.traverse = (delta) => {
    const from = b.entries[b.index].hash
    const to = b.index + delta
    if (to < 0 || to >= b.entries.length) return
    b.index = to
    if (!b.entries[to].app) { b.left = true; return }
    const arrived = b.entries[to].hash
    b.router.moved()                      // popstate
    if (arrived !== from) b.router.moved() // hashchange
  }
  b.settle = () => { while (b.queued.length) b.queued.shift()() }
  b.back = () => { b.traverse(-1); b.settle() }
  b.forward = () => { b.traverse(1); b.settle() }
  b.type = (hash) => {
    b.entries.splice(b.index + 1)
    b.entries.push({ app: true, hash, state: null })
    b.index += 1
    b.router.moved()
    b.router.moved()
  }
  /** A page load - the first, or a reload on the entry showing. */
  b.load = () => {
    b.router = H.createRouter({
      history: b.history,
      hash: () => b.entries[b.index].hash,
      storage: () => b.storage,
      leaving: () => {},
      show: (nav) => b.shown.push(nav),
      newLoad: () => `load${++b.loads}`,
    })
    b.router.start()
    return b.router
  }
  b.hashes = () => b.entries.map((entry) => entry.hash)
  return b
}

const where = (b) => [b.router.nav.tab, R.TABS.filter((tab) => b.router.nav.stacks[tab].length).map((tab) => `${tab}:${stackIds(b.router.nav, tab).join('+')}`)]

console.log('\nend to end: another tab\'s entry, gone back onto')
{
  const b = makeBrowser('#/home')
  b.load()
  b.router.open(album('A', 'Dummy'))
  b.router.tab('library')
  check('Home: Dummy; then the Library - the entry is replaced', [b.hashes(), b.index], [['#/home', '#/library'], 1])
  const before = b.shown.length
  b.back()
  check('back from the Library\'s root: Home, with Dummy still on it', where(b), ['home', ['home:A']])
  check('...the entry rewritten to Dummy\'s, and one change drawn for popstate and hashchange together', [b.hashes(), b.shown.length - before], [['#/home/album/A', '#/library'], 1])
  b.router.tab('library')
  b.router.tab('home')
  check('the Library and back: Home still finds Dummy where it was left', where(b), ['home', ['home:A']])
  b.router.back()
  b.settle()
  check('back from Dummy is Home\'s root', where(b), ['home', []])
}
{
  const b = makeBrowser('#/library')
  b.load()
  b.router.open(album('X', 'Third'))
  b.router.tab('home')
  b.back()
  check('the Library: an album; then Home; back - the Library with its album', where(b), ['library', ['library:X']])
  b.forward()
  check('...and forward is Home again, as it was', where(b), ['home', ['library:X']])
}
{
  const b = makeBrowser('#/home')
  b.load()
  b.router.open(album('A'))
  b.router.open(album('B'))
  b.router.tab('library')
  b.back()
  check('Home: A then B; the Library; back lands on A\'s entry - Home keeps B on top', [where(b), b.entries[b.index].hash], [['home', ['home:A+B']], '#/home/album/B'])
}

console.log('\nend to end: within a tab, back and forward follow the entries')
{
  const b = makeBrowser('#/library')
  b.load()
  b.router.open(album('A'))
  b.router.open(album('B'))
  b.back()
  check('back: one page off', where(b), ['library', ['library:A']])
  b.back()
  check('back: the root', where(b), ['library', []])
  b.forward()
  b.forward()
  check('forward twice: both pages again', where(b), ['library', ['library:A+B']])
  const count = b.entries.length
  b.router.open(album('B'))
  check('a double tap on what is showing opens nothing', b.entries.length, count)
  b.router.tab('library')
  b.settle()
  check('the tab you are on pops to its root by going back through history', [where(b), b.index, b.hashes()], [['library', []], 0, ['#/library', '#/library/album/A', '#/library/album/B']])
  check('...and tapped again, only scrolls', b.router.tab('library'), 'scroll-to-top')
}

console.log('\nend to end: a reload, and the swipe after it')
{
  const b = makeBrowser('#/library', { before: ['elsewhere'] })
  b.load()
  b.router.open(album('B', 'Third'))
  b.load()  // a reload on Third: a new page, the same entries
  check('the reload opens on Third, the Library under it', where(b), ['library', ['library:B']])
  b.router.back()
  b.settle()
  check('back is history\'s own, as before the reload: no copy of the entry below left behind', [b.index, b.hashes()], [1, ['elsewhere', '#/library', '#/library/album/B']])
  b.back()
  check('...so the next swipe leaves the app, not a swipe that shows nothing', b.left, true)
}
{
  const refusing = { getItem() { throw new Error('denied') }, setItem() { throw new Error('denied') } }
  const b = makeBrowser('#/library', { before: ['elsewhere'], storage: refusing })
  b.load()
  b.router.open(album('B'))
  b.load()
  b.router.back()
  b.settle()
  check('storage refused (a private window): back still lands on the root, by replacing the address', where(b), ['library', []])
}
{
  // Two loads of /player/ in one tab: the second counts its entries from 0 too, and its note is its own.
  const b = makeBrowser('#/library')
  b.load()
  b.router.open(album('A'))
  b.entries.push({ app: false, hash: 'elsewhere', state: null })
  b.index = b.entries.length - 1
  b.entries.push({ app: true, hash: '#/home', state: null })
  b.index += 1
  b.load()  // /player/ opened afresh, after leaving the site: its own entries, from 0
  b.router.open(album('C'))
  b.index = 1  // the browser back at the first load's A, which it loads again
  b.load()
  check('a reload on the first load\'s entry reads the first load\'s note', [b.router.nav.tab, stackIds(b.router.nav, 'library')], ['library', ['A']])
  b.router.back()
  b.settle()
  check('...and goes back through ITS entries, not the second load\'s', [b.index, b.entries[0].hash], [0, '#/library'])
}

console.log('\nend to end: cold links')
{
  const b = makeBrowser('#/home/album/X', { before: ['elsewhere'] })
  b.load()
  check('a cold deep link opens its page on its tab', where(b), ['home', ['home:X']])
  b.router.back()
  b.settle()
  check('back replaces the address with the tab\'s root - nothing of the app\'s is below', [where(b), b.index, b.hashes(), b.left], [['home', []], 1, ['elsewhere', '#/home'], false])
}
{
  const b = makeBrowser('#/album/Y')
  b.load()
  check('a legacy link: the Library\'s album, the address rewritten in place', [where(b), b.hashes()], [['library', ['library:Y']], ['#/library/album/Y']])
}
{
  const b = makeBrowser('')
  b.load()
  check('an empty hash: Home, written in', [where(b), b.hashes()], [['home', []], ['#/home']])
  b.type('#/you')
  check('an address typed in: followed, and given a place', [where(b), b.index, b.entries[1].state?.n], [['you', []], 1, 1])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
