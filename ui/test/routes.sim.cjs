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
 *  - What the browser's own back and forward do to the stacks: within a tab it follows them - back
 *    to the page, forward by putting the pages passed back on top, never by searching the stack,
 *    since Go to album can put one album in a stack twice; onto another tab's entry it shows that
 *    tab AS IT WAS LEFT, pages kept, and rewrites the entry.
 *  - The album you don't have (2.0.0-player.13): `#/<tab>/group/<rgid>?release=<mbid>` read and
 *    written; the pressing is in the address but not part of the page's identity, so choosing
 *    another REPLACES the entry (never a page pushed over it), keeps the page's scroll, and back
 *    still leaves the page; back and forward land on the pressing the entry names.
 *  - An artist (2.0.0-player.17): `#/<tab>/artist/<id>` read and written - Navidrome's id, or
 *    `mb:<mbid>` - its id round-tripping, never taking a pressing, a page of its own beside an album
 *    of the same id, and an album opened from it going back to it, named on the back button.
 *  - All of it end to end: lib/appHistory.ts's router driven against a fake browser history that
 *    keeps entries and their state across a reload, fires popstate and then hashchange on a
 *    traversal, and runs history.go() later, as a browser does.
 *  - The desktop frame (2.0.0-player.19, lib/appFrame.ts): the phone's below 1024px, the desktop's
 *    from it - and the desktop frame picks PANELS over sheets: Sources and Info a drawer over the
 *    page's edge from 1024 to 1279px and a third column from 1280, neither modal, the main area
 *    making room only for a column; one panel at a time; crossing into the desktop closes Now
 *    Playing (and what is over it), crossing back the Info panel. The sidebar: its items, the one
 *    for where the app is, and what a tap on each does - Home, Requests, You and the Library view
 *    showing as their tabs' buttons, another Library view that view at the Library's root - Songs
 *    left out where Navidrome lists none, and "Recently added" the desktop's alone - never kept on the
 *    device, as the Library's store (app/libraryPick.ts) holds it, the view left told before it goes.
 *    A drawer, showing, lies over the page (`liesOver`: the shell's `.has-drawer`, and the Info drawer
 *    going as you go to an album). And app/useFrame.ts against a fake matchMedia: the frame the two
 *    media queries say on the first render, followed as the window crosses 1024 and 1280px, a resize
 *    within one frame making no new state, a change between the first render and the listening caught
 *    up, iOS 13's addListener, no matchMedia at all the phone's, and the listeners taken off after.
 *  - Editing an album on a desktop (2.0.0-player.21, lib/albumEdit.ts): the Edit panel a third kind
 *    of side panel (one at a time, making room as a column, lying over the page as a drawer, closed
 *    crossing back to the phone); the album page an edit gave a new id in Navidrome becoming that
 *    album's page in place (`becomeTop`: its entry replaced, back still leaving it); and the panel's
 *    pure rules - its tabs and their keys, which folder an album page's album is (the id bridge's
 *    rows, else the scan by the release, else - an album with no release anywhere - by its name and
 *    artist, several of them a choice the user makes), when the page is followed to a new id, and a
 *    track's number in the Tags tab. After review: a move remembered (`noteMove`, `movedTo`), so a
 *    page of the old id coming back on top is the new one's; whether a delete leaves Navidrome nothing
 *    of the album (`deletesAll`); and what the panel says (`editStatus`) - never "Finding" for good
 *    after the real scan failed, nothing over an album still being edited.
 *  - Needs a look (2.0.0-player.25): `#/you/queue/all?facet=<id>` - one page whatever its facet (the
 *    facet replaced in the address as it is chosen, as a group page's pressing is, kept by a reload,
 *    back leaving the page in one step); the sidebar's "Needs a look", current while its page is on
 *    top and opening it on You; and the Edit panel opened on a folder (`folderOnly`).
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
  'src/lib/appRoutes.ts', 'src/lib/appHistory.ts', 'src/lib/appFrame.ts', 'src/lib/albumEdit.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const R = require(path.join(OUT, 'appRoutes.js'))
const H = require(path.join(OUT, 'appHistory.js'))
const F = require(path.join(OUT, 'appFrame.js'))
const E = require(path.join(OUT, 'albumEdit.js'))

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

console.log('\nthe album you don\'t have: a group, and the pressing shown')
const group = (id, release, label) => ({ kind: 'group', id, ...(label ? { label } : {}), ...(release ? { release } : {}) })
check('a group pushed on Search', R.parseHash('#/search/group/rg-1'), { route: { tab: 'search', page: group('rg-1') }, canonical: '#/search/group/rg-1' })
check('...with the pressing shown', R.parseHash('#/search/group/rg-1?release=r-2'),
  { route: { tab: 'search', page: group('rg-1', 'r-2') }, canonical: '#/search/group/rg-1?release=r-2' })
check('a group page on any tab', R.parseHash('#/home/group/rg-1').route, { tab: 'home', page: group('rg-1') })
check('the pressing is written only for a group, and escaped', [
  R.formatRoute({ tab: 'search', page: group('rg 1', 'r/2') }),
  R.formatRoute({ tab: 'library', page: { kind: 'album', id: 'al-1', release: 'r-2' } }),
], ['#/search/group/rg%201?release=r%2F2', '#/library/album/al-1'])
check('...and read back as itself', R.parseHash(R.formatRoute({ tab: 'search', page: group('rg 1', 'r/2?&x') })).route.page, group('rg 1', 'r/2?&x'))
check('an empty pressing is none', [R.parseHash('#/search/group/rg-1?release=').canonical, R.parseHash('#/search/group/rg-1?release=%20').canonical], ['#/search/group/rg-1', '#/search/group/rg-1'])
check('another query on an album is dropped', R.parseHash('#/library/album/x?release=r-2').route.page, album('x'))
check('a group with no id is its tab\'s root', R.parseHash('#/search/group/').canonical, '#/search')
check('the pressing is not who the page is', [R.samePage(group('rg-1', 'r-1'), group('rg-1', 'r-2')), R.samePage(group('al-1'), album('al-1'))], [true, false])
check('...and not where its scroll is kept', [R.scrollKey({ tab: 'search', page: group('rg-1', 'r-2', 'Third') }), R.scrollKey({ tab: 'search', page: null })], ['#/search/group/rg-1', '#/search'])
{
  let nav = R.openPage(R.startNav({ tab: 'search', page: null }), group('rg-1', null, 'Third'))
  const picked = R.replaceTop(nav, group('rg-1', 'r-2'))
  check('choosing a pressing replaces the page on top, its label kept', [picked.stacks.search, R.formatRoute(R.currentRoute(picked))],
    [[group('rg-1', 'r-2', 'Third')], '#/search/group/rg-1?release=r-2'])
  check('...the same pressing again changes nothing', R.replaceTop(picked, group('rg-1', 'r-2')) === picked, true)
  check('...the default again takes the pressing out of the address', R.formatRoute(R.currentRoute(R.replaceTop(picked, group('rg-1')))), '#/search/group/rg-1')
  check('...another page is never replaced by it', R.replaceTop(nav, group('rg-9', 'r-2')) === nav, true)
  check('opening the same group again is the same page, whatever the pressing', R.openPage(picked, group('rg-1', 'r-3')) === picked, true)
  nav = R.openPage(picked, album('al-1', 'Dummy'))
  const back = R.followRoute(nav, R.parseHash('#/search/group/rg-1?release=r-4').route)
  check('back onto it shows the pressing its entry names, label kept', back.stacks.search, [group('rg-1', 'r-4', 'Third')])
}

console.log('\nan artist (2.0.0-player.17)')
{
  const artist = (id, label) => (label ? { kind: 'artist', id, label } : { kind: 'artist', id })
  check('an artist pushed on Library', R.parseHash('#/library/artist/ar-1'), { route: { tab: 'library', page: artist('ar-1') }, canonical: '#/library/artist/ar-1' })
  check('...one known only by MusicBrainz, its id kept whole', R.parseHash('#/search/artist/mb%3A8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11').route.page,
    artist('mb:8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11'))
  check('...and written back escaped', R.formatRoute({ tab: 'search', page: artist('mb:x y') }), '#/search/artist/mb%3Ax%20y')
  check('an artist takes no pressing', [R.parseHash('#/library/artist/ar-1?release=r-2').canonical, R.formatRoute({ tab: 'library', page: { ...artist('ar-1'), release: 'r-2' } })],
    ['#/library/artist/ar-1', '#/library/artist/ar-1'])
  check('an artist with no id is its tab\'s root', R.parseHash('#/library/artist/').canonical, '#/library')
  check('an artist is not an album of the same id', R.samePage(artist('x'), album('x')), false)
  let nav = R.openPage(R.startNav({ tab: 'library', page: null }), artist('ar-1', 'Portishead'))
  nav = R.openPage(nav, album('al-1', 'Dummy'))
  check('an album opened from the artist page: back names the artist', [R.backLabel(nav), R.addressesBelow(nav)], ['Portishead', ['#/library/artist/ar-1', '#/library']])
  check('...and back lands on the artist', R.currentRoute(R.popPage(nav)).page, artist('ar-1', 'Portishead'))
}

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

  // Forward, within the tab showing, with the page gone forward to also lower in the stack (Go to
  // album onto X, over X and Y): pushed, not searched for - the search took the lower X and cut Y.
  nav = R.openPage(R.openPage(R.startNav({ tab: 'home', page: null }), album('X')), album('Y'))
  note = { index: 2, entries: ['#/home', '#/home/album/X', '#/home/album/Y', '#/home/album/X'] }
  const ahead = R.browserMoved(nav, note, 3, '#/home/album/X')
  check('forward onto a page lower in the stack too: put on top, the pages between it kept', [stackIds(ahead.nav, 'home'), ahead.rewrite], [['X', 'Y', 'X'], false])
  const skipped = R.browserMoved(R.startNav({ tab: 'library', page: null }), { index: 0, entries: ['#/library', '#/library/album/A', '#/home', '#/library/album/B'] }, 3, '#/library/album/B')
  check('forward over several entries: each of this tab\'s put back in turn, another tab\'s passed over', stackIds(skipped.nav, 'library'), ['A', 'B'])

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

console.log('\nend to end: a link to a tab\'s root (Home\'s Arriving, "See all")')
{
  const b = makeBrowser('#/requests')
  b.load()
  //? Go to album from Now Playing, on the Requests tab, leaves an album on it
  b.router.open(album('A', 'Dummy'))
  b.router.tab('home')
  b.router.root('requests')
  b.settle()
  check('See all from Home: the list of downloads, not the album left on the Requests tab', where(b), ['requests', []])
  check('...as tapping the tab twice leaves the history: its root, the album ahead of it', [b.entries[b.index].hash, b.index, b.hashes()],
    ['#/requests', 0, ['#/requests', '#/requests/album/A']])
}
{
  const b = makeBrowser('#/home')
  b.load()
  b.router.root('requests')
  b.settle()
  check('with nothing on it, only the switch: one entry, replaced', [where(b), b.hashes()], [['requests', []], ['#/requests']])
  b.router.root('requests')
  b.settle()
  check('...and asked again there, nothing moves', [where(b), b.hashes()], [['requests', []], ['#/requests']])
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

console.log('\nend to end: one album twice in a stack (Go to album)')
{
  const b = makeBrowser('#/home')
  b.load()
  b.router.open(album('X', 'Dummy'))
  b.router.open(album('Y', 'Third'))
  //? Go to album for X, playing from the Library, while Home shows Y
  b.router.open(album('X', 'Dummy'))
  check('Home: X, Y, then X again on top', where(b), ['home', ['home:X+Y+X']])
  b.router.back()
  b.settle()
  check('back: Y, by history\'s own back', [where(b), b.index], [['home', ['home:X+Y']], 2])
  b.forward()
  check('forward: X on top again, Y kept under it - not cut back to the first X', [where(b), R.backLabel(b.router.nav, 'home'), b.index], [['home', ['home:X+Y+X']], 'Third', 3])
  b.router.back()
  b.settle()
  check('...and back from there is history\'s own back again, nothing replaced', [where(b), b.index, b.hashes()],
    [['home', ['home:X+Y']], 2, ['#/home', '#/home/album/X', '#/home/album/Y', '#/home/album/X']])
}
{
  const b = makeBrowser('#/library')
  b.load()
  b.router.open(album('A'))
  b.router.open(album('B'))
  b.router.tab('library')
  b.settle()
  b.traverse(2)
  b.settle()
  check('popped to the root, then forward two at once: both pages back, in order', where(b), ['library', ['library:A+B']])
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

console.log('\nend to end: choosing a pressing on the album you don\'t have')
{
  const b = makeBrowser('#/search')
  b.load()
  b.router.open({ kind: 'group', id: 'rg-1', label: 'Third' })
  check('the group is pushed', [b.hashes(), b.index], [['#/search', '#/search/group/rg-1'], 1])
  b.router.update({ kind: 'group', id: 'rg-1', release: 'r-2' })
  check('a pressing chosen REPLACES its entry - no new one', [b.hashes(), b.index], [['#/search', '#/search/group/rg-1?release=r-2'], 1])
  b.router.update({ kind: 'group', id: 'rg-1', release: 'r-3' })
  check('...each time', b.hashes(), ['#/search', '#/search/group/rg-1?release=r-3'])
  b.router.back()
  b.settle()
  check('back leaves the page, in one step, by history\'s own back', [where(b), b.index, b.left], [['search', []], 0, false])
  b.forward()
  check('forward lands on the pressing last chosen', [b.router.nav.stacks.search, b.entries[b.index].hash],
    [[{ kind: 'group', id: 'rg-1', release: 'r-3' }], '#/search/group/rg-1?release=r-3'])

  const c = makeBrowser('#/search/group/rg-7?release=r-9')
  c.load()
  check('a cold link opens the group on the pressing it names', c.router.nav.stacks.search, [{ kind: 'group', id: 'rg-7', release: 'r-9' }])
  c.router.update({ kind: 'group', id: 'rg-7', release: 'r-1' })
  c.router.back()
  c.settle()
  check('...and back from it is the tab\'s root, its address replaced', [where(c), c.hashes()], [['search', []], ['#/search']])

  const d = makeBrowser('#/search')
  d.load()
  d.router.open({ kind: 'group', id: 'rg-1', label: 'Third' })
  d.router.update({ kind: 'album', id: 'rg-1', release: 'r-2' })
  d.router.update({ kind: 'group', id: 'rg-other', release: 'r-2' })
  check('an update for another page does nothing', d.hashes(), ['#/search', '#/search/group/rg-1'])
}

console.log('\nan album an edit gave a new id: the page becomes it, in place (2.0.0-player.21)')
{
  const at = (stack) => ({ tab: 'library', stacks: { home: [], library: stack, search: [], requests: [], you: [] } })
  const nav = at([album('X', 'Dummy'), album('A', 'Dummy')])
  const moved = R.becomeTop(nav, { kind: 'album', id: 'A' }, album('B', 'Dummy'))
  check('the page on top becomes the new one, the rest of the stack as it was', stackIds(moved, 'library'), ['X', 'B'])
  check('...its label kept as given', moved.stacks.library[1], { kind: 'album', id: 'B', label: 'Dummy' })
  check('nothing when the page on top is another, or the same page',
    [R.becomeTop(nav, { kind: 'album', id: 'X' }, album('B')) === nav, R.becomeTop(nav, { kind: 'album', id: 'A' }, album('A')) === nav,
      R.becomeTop(nav, { kind: 'group', id: 'A' }, album('B')) === nav], [true, true, true])
  const twice = at([album('A'), album('X'), album('A')])
  check('...and a copy lower down (Go to album) is left as it is', stackIds(R.becomeTop(twice, { kind: 'album', id: 'A' }, album('B')), 'library'), ['A', 'X', 'B'])

  const b = makeBrowser('#/library')
  b.load()
  b.router.open(album('A', 'Dummy'))
  b.router.become({ kind: 'album', id: 'A' }, album('B', 'Dummy'))
  check('end to end: the entry REPLACED with the new address - no new one', [b.hashes(), b.index], [['#/library', '#/library/album/B'], 1])
  b.router.become({ kind: 'album', id: 'A' }, album('C'))
  check('...and once it is B, a move from A does nothing', b.hashes(), ['#/library', '#/library/album/B'])
  b.router.back()
  b.settle()
  check('back still leaves the page, by history\'s own back', [where(b), b.index, b.left], [['library', []], 0, false])
  b.forward()
  check('forward lands on the album as it is now', [stackIds(b.router.nav, 'library'), b.entries[b.index].hash], [['B'], '#/library/album/B'])
}

console.log('\nediting an album: the panel\'s rules (2.0.0-player.21, lib/albumEdit.ts)')
{
  check('the tabs, as the board has them', E.EDIT_TABS.map((tab) => tab.label), ['Release', 'Tags', 'Artwork', 'Lyrics', 'Delete'])
  check('the arrows move between them, round the ends',
    [E.tabAfter('release', 1), E.tabAfter('release', -1), E.tabAfter('delete', 1), E.tabAfter('tags', -1)], ['tags', 'delete', 'release', 'release'])
  check('the album as the page had it, songs left behind',
    [E.editAlbum({ id: 'n1', name: 'Dummy', artist: 'Portishead', songCount: 11, musicBrainzId: ' r-cd ', song: [{}] }), E.editAlbum({ id: 'n2', name: 'Rip', musicBrainzId: '' })],
    [{ id: 'n1', name: 'Dummy', artist: 'Portishead', songCount: 11, musicBrainzId: 'r-cd' }, { id: 'n2', name: 'Rip' }])

  const scan = [
    { path: 'Portishead/Dummy (1994)', album: 'Dummy', artist: 'Portishead', release_mbid: 'r-cd', track_count: 11 },
    { path: 'Portishead/Dummy (1994) [Vinyl]', album: 'Dummy', artist: 'Portishead', release_mbid: 'r-vinyl', track_count: 11 },
    { path: 'Portishead - Dummy', album: 'Dummy', artist: 'Portishead', release_mbid: '', track_count: 11 },
    { path: 'Old Rips/Dummy', album: 'Dummy', artist: 'Portishead', release_mbid: '', track_count: 10 },
    { path: 'Radiohead/OK Computer', album: 'OK Computer', artist: 'Radiohead', release_mbid: '', track_count: 12 },
  ]
  const bridge = (release, ...paths) => ({ release_mbid: release, present: paths.map((path) => ({ path })) })
  check('the id bridge\'s rows first - a set kept one folder per disc is both, in its order, each once',
    [E.editFolders(bridge('r-cd', 'Portishead/Dummy (1994)'), scan, { id: 'n', name: 'Dummy' }),
      E.editFolders(bridge('r-box', 'A/Box (Disc 1)', 'A/Box (Disc 2)', 'A/Box (Disc 1)'), scan, { id: 'n', name: 'Box' })],
    [{ paths: ['Portishead/Dummy (1994)'], from: 'store' }, { paths: ['A/Box (Disc 1)', 'A/Box (Disc 2)'], from: 'store' }])
  check('no rows in the store (not indexed yet): the scan, by the release - never by name for a tagged album',
    [E.editFolders(bridge('r-vinyl'), scan, { id: 'n', name: 'Dummy', artist: 'Portishead' }),
      E.editFolders(bridge('r-unknown'), scan, { id: 'n', name: 'Dummy', artist: 'Portishead' })],
    [{ paths: ['Portishead/Dummy (1994) [Vinyl]'], from: 'release' }, { paths: [], from: 'none' }])
  check('...the bridge not answering: the release Navidrome sent, as the album page had it (any case)',
    E.editFolders(null, scan, { id: 'n', name: 'Dummy', musicBrainzId: 'R-CD' }), { paths: ['Portishead/Dummy (1994)'], from: 'release' })
  check('no release anywhere (a stranger\'s rip): untagged folders by name and artist, folded - narrowed by the track count',
    [E.editFolders(bridge(null), scan, { id: 'n', name: 'dummy', artist: 'PORTISHEAD', songCount: 11 }),
      E.editFolders(bridge(null), scan, { id: 'n', name: 'OK Computer', artist: 'Radiohead' })],
    [{ paths: ['Portishead - Dummy'], from: 'name' }, { paths: ['Radiohead/OK Computer'], from: 'name' }])
  const several = E.editFolders(bridge(null), scan, { id: 'n', name: 'Dummy', artist: 'Portishead' })
  check('...several by name are a choice the user makes - several of a release are not',
    [several, E.needsChoice(several), E.needsChoice(E.editFolders(bridge('r-box', 'a', 'b'), scan, { id: 'n', name: 'Box' }))],
    [{ paths: ['Portishead - Dummy', 'Old Rips/Dummy'], from: 'name' }, true, false])
  check('...a count that matches none leaves them all; another artist, or no name, finds nothing',
    [E.editFolders(bridge(null), scan, { id: 'n', name: 'Dummy', artist: 'Portishead', songCount: 3 }).paths.length,
      E.editFolders(bridge(null), scan, { id: 'n', name: 'Dummy', artist: 'Massive Attack' }), E.editFolders(bridge(null), scan, { id: 'n', name: '' })],
    [2, { paths: [], from: 'none' }, { paths: [], from: 'none' }])

  check('the page is followed only after an apply changed the release - kept, or taken away, it keeps its id',
    [E.followRelease(null, 'r-cd'), E.followRelease('', 'R-CD'), E.followRelease('r-cd', 'r-vinyl'), E.followRelease('r-cd', 'R-CD '),
      E.followRelease(' R-CD', 'r-cd'), E.followRelease('r-cd', ''), E.followRelease('r-cd', null)],
    ['r-cd', 'r-cd', 'r-vinyl', null, null, null, null])
  check('...to Navidrome\'s album for it, when it has one that isn\'t the page\'s own',
    [E.followsTo('n1', 'n2'), E.followsTo('n1', 'n1'), E.followsTo('n1', null)], ['n2', null, null])
  check('...looked for at once, then less often - under a minute in all; the page asked again 10 s after a write',
    [E.FOLLOW_LOOKS_MS[0], E.FOLLOW_LOOKS_MS.every((ms, index, all) => index === 0 || ms > all[index - 1]), E.FOLLOW_LOOKS_MS.reduce((sum, ms) => sum + ms, 0) < 60000, E.EDIT_SETTLE_MS],
    [0, true, true, 10000])
  //? after review
  const moves = new Map()
  E.noteMove(moves, 'X', 'Y')
  check('a move remembered: a page of the old id goes to the new one, a page that never moved nowhere',
    [E.movedTo(moves, 'X'), E.movedTo(moves, 'Y'), E.movedTo(moves, 'Q')], ['Y', null, null])
  E.noteMove(moves, 'Y', 'Z')
  check('...moved twice, to where it is now', [E.movedTo(moves, 'X'), E.movedTo(moves, 'Y')], ['Z', 'Z'])
  E.noteMove(moves, 'Z', 'X')
  check('...and applied back to its first release (Navidrome\'s id for it the same): that id is live again, and no loop',
    [E.movedTo(moves, 'X'), E.movedTo(moves, 'Y'), E.movedTo(moves, 'Z')], [null, 'X', 'X'])
  check('...a loop that got in anyway is followed once round, not for ever',
    E.movedTo(new Map([['A', 'B'], ['B', 'A']]), 'A'), 'B')

  const one = { paths: ['P/Dummy'], from: 'store' }
  const twoOfARelease = { paths: ['A/Box (Disc 1)', 'A/Box (Disc 2)'], from: 'store' }
  const twoByName = { paths: ['Portishead - Dummy', 'Old Rips/Dummy'], from: 'name' }
  check('a delete leaves Navidrome nothing of the album: its only folder - not one of several of a release, which are ONE album there',
    [E.deletesAll(one, 11, { id: 'n', name: 'Dummy' }), E.deletesAll(null, 11, { id: 'n', name: 'Dummy' }),
      E.deletesAll(twoOfARelease, 10, { id: 'n', name: 'Box', songCount: 20 })], [true, true, false])
  check('...found by name among several: the page\'s whole album when the folder holds every song Navidrome lists for it',
    [E.deletesAll(twoByName, 11, { id: 'n', name: 'Dummy', songCount: 11 }), E.deletesAll(twoByName, 11, { id: 'n', name: 'Dummy', songCount: 21 }),
      E.deletesAll(twoByName, 11, { id: 'n', name: 'Dummy' })], [true, false, false])

  const facts = (over) => ({
    deleted: null, problem: null, error: null, albums: 3, loaded: true, stale: false, asked: true,
    folders: { paths: ['P/Dummy'], from: 'store' }, holding: false, release: 'r-cd', ...over,
  })
  check('what the panel says: busy until the bridge and the REAL scan are in, nothing once an album is held',
    [E.editStatus(facts({ asked: false })), E.editStatus(facts({ stale: true })), E.editStatus(facts({ loaded: false })), E.editStatus(facts({ holding: true }))],
    [{ text: "Finding the album's folder…", busy: true }, { text: "Finding the album's folder…", busy: true }, { text: "Finding the album's folder…", busy: true }, null])
  check('...the saved scan in and the real one FAILED: said, with Look again - never "Finding" for good',
    E.editStatus(facts({ stale: true, error: 'HTTP 504' })), { text: "deadwax couldn't read the library: HTTP 504", retry: true })
  check('...a failed read with nothing to show says so too; one under an album still being edited, nothing',
    [E.editStatus(facts({ albums: 0, error: 'down' })), E.editStatus(facts({ error: 'down', holding: true })), E.editStatus(facts({ error: 'down' }))],
    [{ text: "deadwax couldn't read the library: down", retry: true }, null, { text: "The library's scan doesn't list P/Dummy yet.", retry: true }])
  check('...an album held keeps its editors, whatever a later read finds (a hand edit renamed it out of the name it was found by)',
    E.editStatus(facts({ holding: true, folders: { paths: [], from: 'none' }, release: null })), null)
  check('...no folder: by release, or by name - Look again, and the main page',
    [E.editStatus(facts({ folders: { paths: [], from: 'none' } })).text.startsWith('deadwax has no folder of this album'),
      E.editStatus(facts({ folders: { paths: [], from: 'none' }, release: null })).text.startsWith("deadwax can't tell which folder"),
      E.editStatus(facts({ folders: null })).retry, E.editStatus(facts({ folders: null })).mainPage], [true, true, true, true])
  check('...several by name: the choice drawn instead; deleted, the folder named; LIBRARY_PATH unset, said first',
    [E.editStatus(facts({ folders: twoByName })), E.editStatus(facts({ deleted: 'P/Dummy', holding: true })), E.editStatus(facts({ problem: 'LIBRARY_PATH is not set', asked: false }))],
    [null, { text: 'Deleted P/Dummy.' }, { text: 'LIBRARY_PATH is not set' }])
  check('the editors let go once a drawer has slid away (player.css: 420ms)', E.EDIT_SLIDE_MS > 420 && E.EDIT_SLIDE_MS < 1000, true)

  check('a track\'s number in the Tags tab: the disc first on a set, a dot for none',
    [E.trackLabel({ position: 4, disc: 2 }, 2), E.trackLabel({ position: 4, disc: null }, 2), E.trackLabel({ position: 12, disc: 1 }, 0), E.trackLabel({ position: null, disc: 1 }, 2)],
    ['2-04', '1-04', '12', '·'])
}

console.log('\nthe desktop frame picks panels over sheets (2.0.0-player.19)')
{
  check('the breakpoints: 1024 and 1280, the media queries built from them',
    [F.DESKTOP_MIN, F.COLUMN_MIN, F.DESKTOP_QUERY, F.COLUMN_QUERY], [1024, 1280, '(min-width: 1024px)', '(min-width: 1280px)'])
  check('a phone, and a phone on its side, are the phone\'s frame, with sheets',
    [F.frameFor(390), F.frameFor(844), F.frameFor(1023)], [{ frame: 'phone', panel: 'sheet' }, { frame: 'phone', panel: 'sheet' }, { frame: 'phone', panel: 'sheet' }])
  check('from 1024px the desktop\'s: a drawer over the page\'s edge up to 1279, a third column from 1280',
    [F.frameFor(1024), F.frameFor(1279), F.frameFor(1280), F.frameFor(1440)],
    [{ frame: 'desktop', panel: 'drawer' }, { frame: 'desktop', panel: 'drawer' }, { frame: 'desktop', panel: 'column' }, { frame: 'desktop', panel: 'column' }])
  check('...the same from the media queries\' answers - and a "column" answer without the desktop one is still the phone\'s',
    [F.frameOf(false, false), F.frameOf(true, false), F.frameOf(true, true), F.frameOf(false, true)],
    [{ frame: 'phone', panel: 'sheet' }, { frame: 'desktop', panel: 'drawer' }, { frame: 'desktop', panel: 'column' }, { frame: 'phone', panel: 'sheet' }])
  check('only a sheet is modal: a drawer and a column leave the page beside them usable',
    ['sheet', 'drawer', 'column'].map(F.panelIsModal), [true, false, false])
  check('one panel at a time, and none on a phone - Info the one showing if both were ever open (it is opened over Sources)',
    [F.sideOf('desktop', { sources: true, info: false, edit: false }), F.sideOf('desktop', { sources: false, info: true, edit: false }), F.sideOf('desktop', { sources: false, info: false, edit: false }),
      F.sideOf('phone', { sources: true, info: false, edit: false }), F.sideOf('desktop', { sources: true, info: true, edit: false })], ['sources', 'info', 'none', 'none', 'info'])
  //? 2.0.0-player.21: the album page's Edit panel, a third kind - App opens one at a time, and this
  //? says which shows if two ever were
  check('the Edit panel is a side panel too: shown alone, under Info, over Sources - and never on a phone',
    [F.sideOf('desktop', { sources: false, info: false, edit: true }), F.sideOf('desktop', { sources: false, info: true, edit: true }),
      F.sideOf('desktop', { sources: true, info: false, edit: true }), F.sideOf('phone', { sources: false, info: false, edit: true })], ['edit', 'info', 'edit', 'none'])
  check('...making room as a column, lying over the page as a drawer',
    [F.makesRoom('column', 'edit'), F.makesRoom('drawer', 'edit'), F.liesOver('drawer', 'edit'), F.liesOver('column', 'edit')], [true, false, true, false])
  check('the main area makes room only for a third column - a drawer lies over it',
    [F.makesRoom('column', 'sources'), F.makesRoom('column', 'info'), F.makesRoom('column', 'none'), F.makesRoom('drawer', 'sources'), F.makesRoom('sheet', 'sources')],
    [true, true, false, false, false])
  check('crossing into the desktop closes Now Playing; back to the phone, the Info panel - and the Edit panel, which a phone has none of',
    [F.closesOnCrossing('desktop'), F.closesOnCrossing('phone')],
    [{ nowPlaying: true, infoPanel: false, editPanel: false }, { nowPlaying: false, infoPanel: true, editPanel: true }])
  check('a drawer, showing, lies over the page - a column makes room instead, and a sheet is no panel',
    [F.liesOver('drawer', 'sources'), F.liesOver('drawer', 'info'), F.liesOver('drawer', 'none'), F.liesOver('column', 'info'), F.liesOver('sheet', 'sources')],
    [true, true, false, false, false])

  check('the sidebar: Home and Requests, then the Library\'s views as the board lists them',
    [F.SIDEBAR_TOP.map((item) => item.label), F.libraryItems(null).map((item) => item.label)],
    [['Home', 'Requests'], ['Recently added', 'Albums', 'Artists', 'Songs']])
  check('...Songs left out when Navidrome lists none, kept while that isn\'t known',
    [F.libraryItems(false).map((item) => item.id), F.libraryItems(true).length], [['recent', 'albums', 'artists'], 4])
  check('where the app is: its tab - the Library\'s view showing - and none on Search, whose place is the field',
    [F.sidebarCurrent('home', 'albums', true), F.sidebarCurrent('requests', 'albums', true), F.sidebarCurrent('you', 'artists', true),
      F.sidebarCurrent('library', 'artists', true), F.sidebarCurrent('library', 'recent', true), F.sidebarCurrent('library', 'songs', false), F.sidebarCurrent('search', 'albums', true)],
    ['home', 'requests', 'you', 'artists', 'recent', 'albums', null])
  check('a tap: Home, Requests and You are their tabs\' buttons',
    ['home', 'requests', 'you'].map((item) => F.sidebarMove(item, 'albums', true)),
    [{ how: 'tab', tab: 'home' }, { how: 'tab', tab: 'requests' }, { how: 'tab', tab: 'you' }])
  check('...the Library view showing is the Library\'s button (as left, or back to its root); another is that view',
    [F.sidebarMove('albums', 'albums', true), F.sidebarMove('artists', 'albums', true), F.sidebarMove('recent', 'albums', true),
      F.sidebarMove('albums', 'songs', false)],
    [{ how: 'tab', tab: 'library' }, { how: 'view', tab: 'library', pick: 'artists' }, { how: 'view', tab: 'library', pick: 'recent' },
      { how: 'tab', tab: 'library' }])
  check('"Recently added" is the desktop\'s: a phone shows the albums for it, as for Songs with none listed',
    [F.shownPick('recent', true, 'phone'), F.shownPick('recent', true, 'desktop'), F.shownPick('songs', false, 'desktop'), F.shownPick('songs', null, 'phone'),
      F.shownPick('artists', true, 'phone')], ['albums', 'recent', 'albums', 'songs', 'artists'])
  check('each view\'s title on a desktop, the sidebar\'s own words',
    ['recent', 'albums', 'artists', 'songs'].map((pick) => F.LIBRARY_TITLES[pick]), ['Recently added', 'Albums', 'Artists', 'Songs'])

  //? the Library's store, which the Library's chips and the desktop sidebar both choose from
  const PICK = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-routes-pick-'))
  execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
    'src/app/libraryPick.ts', '--rootDir', 'src', '--outDir', PICK,
    '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
  ], { cwd: UI, stdio: 'inherit' })
  fs.mkdirSync(path.join(PICK, 'node_modules/preact'), { recursive: true })
  fs.writeFileSync(path.join(PICK, 'node_modules/preact/hooks.js'), 'exports.useState = () => [0, () => {}]\nexports.useEffect = () => {}\nexports.useCallback = (f) => f\n')
  const stored = new Map([['deadwax-player-library-view', 'artists']])
  globalThis.localStorage = { getItem: (key) => (stored.has(key) ? stored.get(key) : null), setItem: (key, value) => stored.set(key, String(value)), removeItem: (key) => stored.delete(key) }
  const L = require(path.join(PICK, 'app/libraryPick.js'))
  const left = []
  L.onLibraryLeaving(() => left.push(L.libraryPick()))
  check('the Library\'s view: the device\'s to begin with', L.libraryPick(), 'artists')
  L.chooseLibrary('recent')
  check('"Recently added" chosen: shown, the view left told before it went - and never kept on the device',
    [L.libraryPick(), left, stored.get('deadwax-player-library-view')], ['recent', ['artists'], 'artists'])
  L.chooseLibrary('songs')
  L.chooseLibrary('songs')
  check('Albums, Artists or Songs kept, as the chips always were; the same view again changes nothing',
    [L.libraryPick(), left, stored.get('deadwax-player-library-view')], ['songs', ['artists', 'recent'], 'songs'])
  check('whether Navidrome lists songs: unknown until the Library has asked', L.librarySongs(), null)
  L.setLibrarySongs(false)
  check('...then what it said', L.librarySongs(), false)
  delete globalThis.localStorage

  //? (review) the frame itself: app/useFrame.ts asks the two media queries the stylesheets use
  const FRAME = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-routes-frame-'))
  execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
    'src/app/useFrame.ts', '--rootDir', 'src', '--outDir', FRAME,
    '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
  ], { cwd: UI, stdio: 'inherit' })
  fs.mkdirSync(path.join(FRAME, 'node_modules/preact'), { recursive: true })
  //? one hook's state and one effect, run when the test commits - as Preact runs it after the paint
  fs.writeFileSync(path.join(FRAME, 'node_modules/preact/hooks.js'), `
const at = () => globalThis.__frame
exports.useState = (init) => {
  if (!at().state) at().state = { v: typeof init === 'function' ? init() : init }
  const s = at().state
  return [s.v, (x) => { const next = typeof x === 'function' ? x(s.v) : x; if (!Object.is(next, s.v)) { s.v = next; at().sets += 1 } }]
}
exports.useEffect = (f) => { if (!at().effect) at().effect = { f } }
`)
  //? a window as wide as the test says, its media queries telling their listeners as an answer changes
  const screen = { width: 0, lists: [] }
  const media = (query, { old = false } = {}) => {
    const min = Number(/min-width: (\d+)px/.exec(query)[1])
    const list = { query, listeners: [], was: screen.width >= min, get matches() { return screen.width >= min } }
    if (old) {
      list.addListener = (fn) => list.listeners.push(fn)
      list.removeListener = (fn) => { list.listeners = list.listeners.filter((each) => each !== fn) }
    } else {
      list.addEventListener = (name, fn) => name === 'change' && list.listeners.push(fn)
      list.removeEventListener = (name, fn) => { list.listeners = list.listeners.filter((each) => each !== fn) }
    }
    screen.lists.push(list)
    return list
  }
  const resize = (width, { tell = true } = {}) => {
    screen.width = width
    if (!tell) return
    for (const list of screen.lists) {
      if (list.matches !== list.was) { list.was = list.matches; for (const fn of [...list.listeners]) fn({ matches: list.matches }) }
    }
  }
  const mountFrame = ({ old = false } = {}) => {
    globalThis.__frame = { state: null, effect: null, sets: 0 }
    screen.lists = []
    const UF = require(path.join(FRAME, 'app/useFrame.js'))
    const render = () => UF.useFrame()
    const commit = () => { const effect = globalThis.__frame.effect; if (effect && !effect.cleanup) effect.cleanup = effect.f() }
    const unmount = () => globalThis.__frame.effect?.cleanup?.()
    return { render, commit, unmount, sets: () => globalThis.__frame.sets }
  }
  globalThis.window = { matchMedia: (query) => media(query) }

  resize(1440, { tell: false })
  let frame = mountFrame()
  check('the first render: the frame the media queries say - 1440px, the desktop\'s, a panel a column', frame.render(), { frame: 'desktop', panel: 'column' })
  frame.commit()
  check('...listening to both queries the stylesheets use, and nothing new as it starts', [screen.lists.filter((list) => list.listeners.length).map((list) => list.query).sort(), frame.sets()],
    [['(min-width: 1024px)', '(min-width: 1280px)'], 0])
  resize(1100)
  check('narrowed to 1100px: still the desktop\'s, a panel a drawer', [frame.render(), frame.sets()], [{ frame: 'desktop', panel: 'drawer' }, 1])
  resize(1200)
  check('...a resize within the frame: no answer changed, nothing new', [frame.render(), frame.sets()], [{ frame: 'desktop', panel: 'drawer' }, 1])
  screen.lists.at(-1).listeners.forEach((fn) => fn({}))
  check('...and a change event with the frame the same (a list re-telling) makes no new state', frame.sets(), 1)
  resize(800)
  check('narrowed under 1024px: the phone\'s, with sheets', [frame.render(), frame.sets()], [{ frame: 'phone', panel: 'sheet' }, 2])
  resize(1280)
  check('widened to 1280 at a stroke: the desktop\'s, a column', frame.render(), { frame: 'desktop', panel: 'column' })
  frame.unmount()
  check('unmounted: no listener left', screen.lists.reduce((sum, list) => sum + list.listeners.length, 0), 0)

  //? a window resized between the first render and the effect that starts listening
  resize(390, { tell: false })
  frame = mountFrame()
  check('a phone on the first render', frame.render(), { frame: 'phone', panel: 'sheet' })
  resize(1440, { tell: false })
  frame.commit()
  check('...widened before it listened: caught up as it starts listening', frame.render(), { frame: 'desktop', panel: 'column' })
  frame.unmount()

  //? iOS 13's MediaQueryList, with addListener and no addEventListener
  globalThis.window = { matchMedia: (query) => media(query, { old: true }) }
  resize(1440, { tell: false })
  frame = mountFrame()
  frame.render()
  frame.commit()
  resize(900)
  check('iOS 13\'s addListener followed the same', frame.render(), { frame: 'phone', panel: 'sheet' })
  frame.unmount()
  check('...and taken off with removeListener', screen.lists.reduce((sum, list) => sum + list.listeners.length, 0), 0)

  //? no matchMedia at all: the phone's frame, and nothing to listen to
  globalThis.window = {}
  frame = mountFrame()
  check('no matchMedia: the phone\'s frame', frame.render(), { frame: 'phone', panel: 'sheet' })
  frame.commit()
  delete globalThis.window
  delete globalThis.__frame
}

console.log('\nNeeds a look: the queue page, its facet in the address and not its identity (2.0.0-player.25)')
{
  const queue = (facet) => ({ kind: 'queue', id: 'all', ...(facet ? { facet } : {}) })
  check('pushed on You: #/you/queue/all', R.parseHash('#/you/queue/all'), { route: { tab: 'you', page: queue() }, canonical: '#/you/queue/all' })
  check('...a facet read from the address, and written back', [R.parseHash('#/you/queue/all?facet=no_art').route.page, R.formatRoute({ tab: 'you', page: queue('no_art') })],
    [queue('no_art'), '#/you/queue/all?facet=no_art'])
  check('...one queue page: any other id is it, its address made canonical', R.parseHash('#/you/queue/whatever?facet=new').canonical, '#/you/queue/all?facet=new')
  check('...an empty facet is none; another page takes no facet', [R.parseHash('#/you/queue/all?facet=').canonical, R.parseHash('#/library/album/x?facet=new').route.page],
    ['#/you/queue/all', album('x')])
  check('the same page whatever its facet; its scroll kept under one key', [R.samePage(queue('new'), queue('no_art')), R.scrollKey({ tab: 'you', page: queue('new') })],
    [true, '#/you/queue/all'])
  check('the page App opens: All, labelled for the back button above it', R.QUEUE_PAGE, { kind: 'queue', id: 'all', label: 'Needs a look' })
  const nav = R.openPage(R.startNav({ tab: 'you', page: null }), R.QUEUE_PAGE)
  const picked = R.replaceTop(nav, queue('no_art'))
  check('a facet chosen replaces the page on top - the same page, its label kept', [picked.stacks.you, R.formatRoute(R.currentRoute(picked))],
    [[{ kind: 'queue', id: 'all', label: 'Needs a look', facet: 'no_art' }], '#/you/queue/all?facet=no_art'])
  check('...the same facet again changes nothing; All takes it out', [R.replaceTop(picked, queue('no_art')) === picked, R.formatRoute(R.currentRoute(R.replaceTop(picked, queue())))],
    [true, '#/you/queue/all'])
  check('...and a group\'s pressing is still its own (the two never mix)', R.replaceTop(R.openPage(R.startNav({ tab: 'search', page: null }), { kind: 'group', id: 'g' }), { kind: 'group', id: 'g', release: 'r' }).stacks.search,
    [{ kind: 'group', id: 'g', release: 'r' }])

  const b = makeBrowser('#/you')
  b.load()
  b.router.open(R.QUEUE_PAGE)
  b.router.update(queue('new'))
  check('end to end: opened, then a facet - its entry replaced, no new one', [b.hashes(), b.index], [['#/you', '#/you/queue/all?facet=new'], 1])
  b.router.back()
  b.settle()
  check('...back leaves the page in one step', [where(b), b.index], [['you', []], 0])
  b.forward()
  check('...forward lands on the facet last chosen', b.entries[b.index].hash, '#/you/queue/all?facet=new')
  const c = makeBrowser('#/you/queue/all?facet=no_art')
  c.load()
  check('a reload (or a link) opens the page on the facet it names', c.router.nav.stacks.you, [queue('no_art')])

  check('the sidebar: Needs a look is Managing\'s own item', F.SIDEBAR_QUEUE, { id: 'queue', label: 'Needs a look' })
  check('...the current item while its page is on top, whatever its tab; otherwise as before',
    [F.sidebarCurrent('you', 'albums', true, R.QUEUE_PAGE), F.sidebarCurrent('home', 'albums', true, queue('new')), F.sidebarCurrent('you', 'albums', true, album('x')), F.sidebarCurrent('you', 'albums', true)],
    ['queue', 'queue', 'you', 'you'])
  check('...a tap opens its page, on You', F.sidebarMove('queue', 'albums', true), { how: 'queue', tab: 'you' })

  check('the Edit panel opened on a folder: that folder, nothing to find or choose', [E.folderOnly('Old Rips/Third rip'), E.needsChoice(E.folderOnly('a')), E.folderOnly('')],
    [{ paths: ['Old Rips/Third rip'], from: 'folder' }, false, { paths: [], from: 'none' }])
  check('...a delete there needs no Navidrome album to judge by', [E.deletesAll(E.folderOnly('a'), 3, undefined), E.deletesAll({ paths: ['a', 'b'], from: 'name' }, 3, undefined)], [true, false])
  check('...the panel says what it says for an album by any other way: the scan not listing it yet',
    E.editStatus({ deleted: null, problem: null, error: null, albums: 3, loaded: true, stale: false, asked: true, folders: E.folderOnly('Old Rips/Third rip'), holding: false, release: null }),
    { text: "The library's scan doesn't list Old Rips/Third rip yet.", retry: true })
  check('...but the scan LISTING it, the album just not taken yet (the render after a folder request is "asked"): still finding - never a flash of "doesn\'t list"',
    E.editStatus({ deleted: null, problem: null, error: null, albums: 3, loaded: true, stale: false, asked: true, folders: E.folderOnly('Old Rips/Third rip'), holding: false, listed: true, release: null }),
    { text: "Finding the album's folder…", busy: true })
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
