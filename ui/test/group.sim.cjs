/**
 * The album you don't have (app/ReleaseGroupPage.tsx) and its pressing dropdown
 * (app/PressingPicker.tsx), 2.0.0-player.13 - the components themselves, compiled with the repo's
 * TypeScript and rendered by the small stand-in for Preact the other component sims use, with
 * MusicBrainz's answers faked from the real groups in tests/fixtures/pressings/.
 *
 * What it pins:
 *
 *  - The page's states: "Asking MusicBrainz…" until the pressings come; a problem - MusicBrainz
 *    unreachable, or a list it broke off - with Try again, which asks again, and a broken-off list
 *    never kept for the session (reopening asks again); no pressings; an address that isn't a
 *    MusicBrainz album, said so with no Try again and nothing asked; an upper-case id asked for in
 *    lower case; and the header from what Search handed over, from the pressings' own group on a cold
 *    link, or nothing claimed until something is known.
 *  - "in your library" / "not in your library" only once the library has answered, judged by the
 *    group's id and every pressing's (a folder tagged with a release id alone counts).
 *  - The page opens on the default pressing, or the one the address names, and draws its tracklist:
 *    the line above it (amber when it differs), a Bonus row, what it leaves out.
 *  - A pick hands the page's group and the pressing to App - null for the default, which takes it
 *    out of the address.
 *  - The session keeps a group's pressings: a page opened on it again draws at once and asks nothing.
 *  - The dropdown is a listbox: the button says so, the options say which is chosen, the fold
 *    ("N more pressings with the usual tracklist") sits outside the listbox and expands it, a pick
 *    and Escape close it. Focus going NOWHERE (WebKit's tap on a button without a tabindex, an
 *    element removed) doesn't close it; focus going to something outside does; the fold takes
 *    tabIndex -1 so WebKit focuses it on a tap.
 *  - Get (2.0.0-player.15): not before a pressing is chosen; then "Get the album", the page's one
 *    solid purple button, opening the Sources sheet for the CHOSEN pressing - built by the one payload
 *    builder from the album's group, the opener taken in the tap. Under it (review: above it, an
 *    answer landing late moved Get under a finger), what the library and the downloads already have
 *    of that pressing, asked of the store (POST /download/store_state - no search) for the pressing
 *    shown, again as another is chosen, as an album is filed and as the page comes back into view
 *    (after a Get, or a download cancelled in Requests), and only the newest answer drawn - the last
 *    one standing while the same pressing is asked again, another pressing's never.
 *  - On a desktop (2.0.0-player.19): Get first and the pressing inline after it; the tracklist a
 *    table with an "Against the usual tracklist" column while any pressing of the album differs (and
 *    none when they are all alike), each marked track's chip and its note in the board's short words,
 *    the whole note and every title in the cell's tooltip; Get drawn pressed while the Sources panel
 *    shows the sources of the pressing ON SCREEN (never another pressing's of the album), a click on
 *    it then closing them; and with the panel open for this album, each other pressing chosen asked
 *    for again - `again`, from this page, focus going back to Get - as is the page's own pressing when
 *    it comes back to a panel left open for another; nothing asked by a page that isn't showing, nor
 *    once the panel shows something else. A phone's page is as it was: no pressed state on its Get.
 *
 * And for another pressing of an album you hold (2.0.0-player.41): every pressing the library holds -
 * by the group's folders or a release id alone, a release id tagged in capitals too - marked "In your
 * library" in the list and never folded away (only those marked), Get still offered on one you hold and opening the sources for it (the
 * existing path: the store line, and the sheet's box, say it is already there); and `title` - the
 * album's name from the page that opened it - standing in as the title on a cold page until
 * MusicBrainz's own group arrives, never over it.
 *
 * And for a song Search found (2.0.0-player.53): the page opens on a pressing that has the song - the usual
 * one when it has it (Borderline's single mix: the usual pressing has Borderline, as another recording), else
 * the one that does (Patience, only on The Slow Rush's Japanese CD) - never over a pressing the address
 * names; the song marked in the tracklist (a Bonus track still one) and said to a screen reader, on a phone and
 * in a desktop's table; brought into view once, as it is first drawn, only while the page shows and is at its
 * top; and a pick on it written into the address even for the usual pressing.
 *
 * And for the search extras (2.0.0-player.50): the chosen pressing's facts in one line under the picker
 * (under Get and it on a desktop), its whole in the tooltip, every option's facts between its label and
 * its note; "maybe in your library", dashed, for a folder of the album's name and artist with no ids -
 * never beside a pressing held by id, nor for another artist's or another album's folder, nor before the
 * library answers - its folders in the tooltip; the album and the pressing chosen on musicbrainz.org,
 * opening beside the app, last on the page (none for a link that isn't an album's); and the list's filter
 * for more than 30 pressings - outside the listbox, matching folded pressings with the fold stepped
 * aside, saying when nothing matches, its field's own keys left to it, ArrowDown and ArrowUp between it
 * and the first pressing, and empty again once the list closes - by a pick or by the Pressing button.
 *
 * And with logins on and a library of your own (2.0.0-player.52, second review), drawn as ethan: an album the
 * store holds that isn't his is "in the collection" in the meta line, "In the collection, not in your library" under Get
 * and "In the collection" in the pressing list - the page taking `personal` from the session, never drawn as logins
 * off; the library asked again every time the page shows; and a library answer kept from earlier in the
 * session (an unstar in Amperfy since, read back) giving way to the store line's fresh word once it lands - the
 * meta line never "in your library" over "In the collection, not in your library", nor the other way round. Logins
 * off after it: "in your library" and "Already in your library", as ever.
 *
 * Run it with:  node ui/test/group.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const FIXTURES = path.resolve(__dirname, '../../tests/fixtures/pressings')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-group-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/ReleaseGroupPage.tsx', 'src/app/PressingPicker.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - the stand-in you.sim.cjs uses
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
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

/* ===== MusicBrainz and the library, faked: each answer is what the test says next ===== */

fs.writeFileSync(path.join(OUT, 'api/musicbrainz.js'), `
exports.getReleaseGroup = (id, signal) => globalThis.__group.ask(id, signal)
`)
fs.writeFileSync(path.join(OUT, 'app/useOwned.js'), `
exports.useOwned = (ask) => globalThis.__group.owned
exports.refreshOwned = () => { globalThis.__group.ownedAsks += 1; return Promise.resolve() }
`)
fs.writeFileSync(path.join(OUT, 'hooks/useDismiss.js'), `
exports.useDismiss = () => {}
`)
fs.writeFileSync(path.join(OUT, 'player/icons.js'), `
exports.ChevronLeftIcon = exports.ChevronDownIcon = exports.CheckIcon = exports.GetIcon = function Icon() { return null }
`)
//? the store's answer for a pressing (2.0.0-player.15), faked; and the opener a tap would focus
fs.writeFileSync(path.join(OUT, 'api/download.js'), `
exports.storeState = (body, signal) => globalThis.__group.storeState(body, signal)
exports.joinJob = (jobId) => globalThis.__group.joinJob(jobId)
`)
fs.writeFileSync(path.join(OUT, 'app/useSheet.js'), `
exports.takeOpener = (event) => event.currentTarget
`)
//? (2.0.13) the album's description: what it was asked with kept, what it answers the test's - by default settled
//? with none, so the tracklist waits for nothing more than it did
fs.writeFileSync(path.join(OUT, 'app/useDescription.js'), `
exports.useDescription = (kind, ids, below, page) => {
  globalThis.__group.describeAsks.push([kind, ids, below, page])
  return globalThis.__group.describing
}
`)

const asked = []
const answers = []
//? groups that aren't in the fixtures, as MBIDs: the page refuses any address that isn't one
const UNREACHABLE = '00000000-0000-4000-8000-000000000001'
const EMPTY = '00000000-0000-4000-8000-000000000002'
const owning = (albums) => ({ index: OwnedIndex.buildOwnedIndex(albums), artists: [] })
const stateAsks = []
globalThis.__group = {
  owned: null,
  describeAsks: [],
  describing: { description: null, settled: true, at: null },
  //? how many times the page asked the library again (2.0.0-player.52, second review: every time it shows)
  ownedAsks: 0,
  storeState(body, signal) {
    const d = {}
    d.promise = new Promise((yes, no) => { d.resolve = yes; d.reject = no })
    stateAsks.push({ body, signal, ...d })
    return d.promise
  },
  ask(id) {
    asked.push(id)
    const next = answers.shift()
    return next ? next() : new Promise(() => {})
  },
}

const load = (name) => JSON.parse(fs.readFileSync(path.join(FIXTURES, `${name}.json`), 'utf8'))
const slowRush = load('slow-rush'), dummy = load('dummy')
const answering = (fixture, problem = null) => () => Promise.resolve({ id: fixture.group.id, releases: fixture.releases, problem })
const byPrefix = (fixture, prefix) => fixture.releases.find((release) => release.id.startsWith(prefix))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { ReleaseGroupPage, NOT_AN_ALBUM_LINK } = require(path.join(OUT, 'app/ReleaseGroupPage.js'))
const { PressingPicker } = require(path.join(OUT, 'app/PressingPicker.js'))
const { MusicBrainzUnavailable } = require(path.join(OUT, 'api/http.js'))
const P = require(path.join(OUT, 'lib/pressings.js'))
const OwnedIndex = require(path.join(OUT, 'lib/owned.js'))

let tree = null
function find(test, within = tree) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(within)
  return hits
}
function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''  // a component, not drawn here
  return text(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const classed = (name) => find(byClass(name))
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

/** A page, mounted: draw it (effects and all), and again after answers land. */
function page(props) {
  const render = hooks.root(ReleaseGroupPage)
  const picks = []
  const all = { release: null, preview: null, shown: true, backLabel: 'Search', onBack() {}, onPick: (group, release) => picks.push([group, release]), ...props }
  const draw = (more = {}) => {
    Object.assign(all, more)
    tree = render(all)
    render.commit()
    return tree
  }
  return { draw, picks }
}

const PREVIEW = { id: slowRush.group.id, title: 'The Slow Rush', 'primary-type': 'Album', 'first-release-date': '2020-02-14',
  'artist-credit': [{ name: 'Tame Impala', artist: { name: 'Tame Impala' } }] }

async function main() {
  console.log('\nasking MusicBrainz, with the header Search handed over')
  {
    const { draw } = page({ id: slowRush.group.id, preview: PREVIEW })
    draw()
    check('one ask, for the group', asked, [slowRush.group.id])
    check('(2.0.6) "Loading…", as a status, with the sweep', [text(classed('app-asking')[0]), classed('app-asking')[0]?.props.role, classed('app-sweep').length],
      ['Loading…', 'status', 1])
    check('the header: title, artist, and what it is - and nothing about the library before it answers',
      [text(classed('pl-hero-title')[0]), text(classed('pl-hero-artist')[0]), text(classed('pl-hero-meta')[0])],
      ['The Slow Rush', 'Tame Impala', '2020 · Album'])
    check('...an artist that isn\'t a link (here no MusicBrainz id) drawn plain, not in the link\'s colour (2.0.0-player.17)',
      [classed('pl-hero-artist')[0].type, classed('pl-hero-artist')[0].props.class], ['p', 'pl-hero-artist app-hero-plain'])
    globalThis.__group.owned = owning([{ path: 'Portishead/Dummy (1994)', release_group_mbid: dummy.group.id }])
    draw()
    check('...then, once it has, "not in your library"', text(classed('pl-hero-meta')[0]), '2020 · Album · not in your library')
    globalThis.__group.owned = null
    check('no dropdown before the pressings come', find((node) => node.type === PressingPicker).length, 0)
    check('the cover: the album\'s front, there being no pressing yet', find((node) => node.props?.addresses)[0]?.props.addresses,
      [`https://coverartarchive.org/release-group/${slowRush.group.id}/front-500`])
  }

  console.log('\na cold link claims nothing until something is known')
  {
    asked.length = 0
    const { draw } = page({ id: dummy.group.id })
    draw()
    check('no title, no artist, no meta line yet', [text(classed('pl-hero-title')[0]), text(classed('pl-hero-meta')[0])], ['', ''])
  }

  console.log('\nMusicBrainz away, or a list it broke off: a problem, with Try again')
  {
    asked.length = 0
    answers.push(() => Promise.reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now')))
    const { draw } = page({ id: UNREACHABLE })
    draw()
    await settle()
    draw()
    check('(2.0.6) it says the album\'s details can\'t be loaded, and offers to ask again', [text(classed('app-rg-trouble')[0]).startsWith("This album's details can't be loaded right now - try again in a few minutes."),
      find((node) => node.type === 'button' && text(node) === 'Try again').length], [true, 1])
    check('...and draws no tracklist', classed('app-rg-tracks').length, 0)
    answers.push(answering(slowRush, 'MusicBrainz failed part way'))
    find((node) => node.type === 'button' && text(node) === 'Try again')[0].props.onClick()
    await settle()
    draw()
    check('Try again asks again', asked, [UNREACHABLE, UNREACHABLE])
    check('a list MusicBrainz broke off is a problem too, never the album\'s pressings',
      [classed('app-rg-trouble').length, classed('app-rg-tracks').length, find((node) => node.type === PressingPicker).length], [1, 0, 0])
    //? and never kept: Try again, or the page opened again, asks MusicBrainz afresh (review)
    find((node) => node.type === 'button' && text(node) === 'Try again')[0].props.onClick()
    draw()
    check('...Try again after it asks again, drawing no tracklist from it', [asked.length, classed('app-rg-tracks').length, classed('app-asking').length], [3, 0, 1])
    const again = page({ id: UNREACHABLE })
    again.draw()
    check('...and the page opened again asks again too', [asked.length, classed('app-rg-tracks').length], [4, 0])
  }

  console.log('\nan address that isn\'t a MusicBrainz album')
  {
    asked.length = 0
    const { draw } = page({ id: 'not-an-album' })
    draw()
    draw()
    check('says so, with no Try again, and asks nothing', [text(classed('app-rg-trouble')[0]),
      find((node) => node.type === 'button' && text(node) === 'Try again').length, asked.length], [NOT_AN_ALBUM_LINK, 0, 0])
    const upper = page({ id: slowRush.group.id.toUpperCase(), preview: PREVIEW })
    upper.draw()
    check('an upper-case id is asked for as MusicBrainz writes it', asked, [slowRush.group.id])
  }

  console.log('\nthe pressings: the default, its tracklist, and a pick')
  {
    asked.length = 0
    answers.push(answering(slowRush))
    const { draw, picks } = page({ id: slowRush.group.id, preview: PREVIEW })
    draw()
    await settle()
    draw()
    const picker = find((node) => node.type === PressingPicker)[0]
    check('the dropdown opens on the default pressing', picker?.props.view.chosenId, slowRush.expected.representative)
    check('the line above the tracklist', [text(classed('app-rg-summary')[0]), classed('app-rg-summary')[0]?.props.class], ['The usual tracklist, shared by 9 of 10 pressings', 'app-rg-summary'])
    check('twelve tracks, numbered and timed, nothing marked', [classed('app-rg-track').length, classed('is-marked').length,
      text(classed('app-rg-number')[0]), text(classed('app-rg-length')[0])], [12, 0, '1', '5:22'])
    check('the cover: this pressing\'s front, then the album\'s', find((node) => node.props?.addresses)[0]?.props.addresses, [
      `https://coverartarchive.org/release/${slowRush.expected.representative}/front-500`,
      `https://coverartarchive.org/release-group/${slowRush.group.id}/front-500`])
    const japan = byPrefix(slowRush, '452ccdb4').id
    picker.props.onPick(japan)
    picker.props.onPick(slowRush.expected.representative)
    check('a pick hands App the group and the pressing; the default is null, out of the address', picks, [[slowRush.group.id, japan], [slowRush.group.id, null]])
    check('nothing is asked again for a pick', asked.length, 1)

    draw({ release: japan })
    check('the address\'s pressing: the line says what it changes, in amber', [text(classed('app-rg-summary')[0]), classed('app-rg-summary')[0]?.props.class],
      ['This pressing adds 1 track', 'app-rg-summary is-differs'])
    const bonus = classed('is-bonus')[0]
    check('...its thirteenth track a Bonus row, only on this pressing', [text(find(byClass('app-rg-title'), bonus)[0]), text(find(byClass('app-rg-chip'), bonus)[0]),
      text(find(byClass('app-rg-note'), bonus)[0])], ['Patience', 'Bonus', 'Only on this pressing'])
    check('a held album says so', (globalThis.__group.owned = { index: { byGroup: new Map([[slowRush.group.id, [{ path: 'x' }]]]), byRelease: new Map(), byName: new Map(), total: 1 }, artists: [] },
      draw(), text(classed('pl-hero-meta')[0])), '2020 · Album · in your library')
    //? an m4a deadwax filed carries a release id and no group id (Easy MP4 has no key for it)
    globalThis.__group.owned = owning([{ path: 'Tame Impala/The Slow Rush (2020)', release_mbid: japan, release_group_mbid: '' }])
    draw()
    check('...and so does one held by a pressing\'s id alone, with no group id', text(classed('pl-hero-meta')[0]), '2020 · Album · in your library')
    globalThis.__group.owned = null
  }

  console.log('\nthe session keeps a group\'s pressings')
  {
    asked.length = 0
    const { draw } = page({ id: slowRush.group.id })
    draw()
    check('opened again, it draws at once and asks nothing', [asked.length, classed('app-rg-track').length, classed('app-asking').length], [0, 12, 0])
  }

  console.log('\nwhat a pressing leaves out, and an album with none')
  {
    answers.push(answering(dummy))
    const { draw } = page({ id: dummy.group.id, release: byPrefix(dummy, '87888070').id })
    draw()
    await settle()
    draw()
    check('the ten-track CD: "Not on this pressing", with the usual length', [text(classed('app-rg-left-title')[0]),
      find(byClass('is-left')).map((row) => [text(find(byClass('app-rg-title'), row)[0]), text(find(byClass('app-rg-length'), row)[0])])],
      ['Not on this pressing', [['It’s a Fire', '3:49']]])
    answers.push(() => Promise.resolve({ id: EMPTY, releases: [], problem: null }))
    const empty = page({ id: EMPTY })
    empty.draw()
    await settle()
    empty.draw()
    check('no pressings at all says so', text(classed('pl-notice')[0]), 'There are no pressings of this album to get.')
  }

  console.log('\na cold link, with the group MusicBrainz sends beside each pressing')
  {
    const grouped = '00000000-0000-4000-8000-000000000003'
    const group = { id: grouped, title: 'Dummy', 'primary-type': 'Album', 'first-release-date': '1994-08-22' }
    answers.push(() => Promise.resolve({ id: grouped, releases: dummy.releases.map((release) => ({ ...release, 'release-group': group })), problem: null }))
    globalThis.__group.owned = owning([])
    const { draw } = page({ id: grouped })
    draw()
    await settle()
    draw()
    check('says what the album is, as Search would have', [text(classed('pl-hero-title')[0]), text(classed('pl-hero-meta')[0])], ['Dummy', '1994 · Album · not in your library'])
    globalThis.__group.owned = null
  }

  console.log('\nthe dropdown: a listbox')
  {
    const render = hooks.root(PressingPicker)
    const picked = []
    const view = P.pressingsView(slowRush.releases)
    const draw = () => { tree = render({ view, onPick: (id) => picked.push(id) }); render.commit(); return tree }
    draw()
    const button = () => classed('app-picker-button')[0]
    check('closed: a button saying "Pressing" and the one shown, its list hidden',
      [button().props['aria-haspopup'], button().props['aria-expanded'], text(button()), classed('app-picker-popover')[0].props.hidden],
      ['listbox', false, 'PressingCD · 2020 · AU · Caroline International', true])
    button().props.onClick()
    draw()
    const listbox = find((node) => node.props?.role === 'listbox')[0]
    const options = find((node) => node.props?.role === 'option', listbox)
    check('opened: the list shows, controlled by the button', [classed('app-picker-popover')[0].props.hidden, button().props['aria-expanded'], button().props['aria-controls'] === listbox.props.id],
      [false, true, true])
    check('the options: the shown pressings, the chosen one selected and ticked', [options.length, options.map((option) => option.props['aria-selected']).filter(Boolean).length,
      options[0].props['aria-selected'], find(byClass('app-picker-tick'), options[0])[0]?.props.class], [5, 1, true, 'app-picker-tick'])
    check('a pressing that differs says how, in amber', find(byClass('is-differs'), listbox).map(text), ['+1 bonus track: Patience', '1 other version: Borderline, 4:34'])
    const fold = classed('app-picker-more')[0]
    check('the fold, outside the listbox', [text(fold), find(byClass('app-picker-more'), listbox).length], ['5 more pressings with the usual tracklist', 0])
    check('...focusable on a tap in WebKit, as the options are (tabIndex -1)', [fold.props.tabIndex, options[0].props.tabIndex], [-1, -1])
    //? WebKit's tap on a button with no tabindex, or Chromium removing a focused element: focus goes
    //? nowhere, and the list must stay open for the click that follows (review)
    const picker = () => classed('app-picker')[0]
    picker().props.onFocusOut({ relatedTarget: null })
    draw()
    check('focus going nowhere leaves the list open', classed('app-picker-popover')[0].props.hidden, false)
    //? the stand-in draws no DOM, so the root's ref is given a contains() of its own
    const inside = { inside: true }
    picker().props.ref.current = { contains: (node) => node === inside }
    picker().props.onFocusOut({ relatedTarget: inside })
    draw()
    check('focus moving within the picker leaves it open', classed('app-picker-popover')[0].props.hidden, false)
    picker().props.onFocusOut({ relatedTarget: { outside: true } })
    draw()
    check('focus going to something outside closes it (Tab out of the list)', classed('app-picker-popover')[0].props.hidden, true)
    button().props.onClick()
    draw()
    fold.props.onClick()
    draw()
    check('the fold expands the list to every pressing, and goes', [find((node) => node.props?.role === 'option').length, classed('app-picker-more').length], [10, 0])
    find((node) => node.props?.role === 'option')[3].props.onClick()
    draw()
    check('a pick is handed on, and closes the list', [picked.length, classed('app-picker-popover')[0].props.hidden], [1, true])
    button().props.onClick()
    draw()
    classed('app-picker')[0].props.onKeyDown({ key: 'Escape', preventDefault() {} })
    draw()
    check('Escape closes it', classed('app-picker-popover')[0].props.hidden, true)
  }

  console.log('\nGet: the chosen pressing, built by the one payload builder, and what is already here of it')
  {
    const R = require(path.join(OUT, 'lib/releasePayload.js'))
    const { StoreState } = require(path.join(OUT, 'app/StoreState.js'))
    const { announceAlbumsFiled } = require(path.join(OUT, 'lib/libraryEvents.js'))
    stateAsks.length = 0
    const gets = []
    const onGet = (request, opener) => gets.push([request, opener])
    answers.push(() => new Promise(() => {}))
    const waiting = page({ id: '00000000-0000-4000-8000-000000000009', onGet })
    waiting.draw()
    check('no Get, and nothing asked of the store, before there is a pressing to get', [classed('app-rg-get').length, stateAsks.length], [0, 0])

    //? The Slow Rush, kept from above: drawn at once
    const { draw } = page({ id: slowRush.group.id, preview: PREVIEW, onGet })
    draw()
    const usual = byPrefix(slowRush, '1cf564b9')
    const expected = R.buildDownloadRelease(PREVIEW, usual).release
    check('"Get the album": one, the page\'s one solid purple button', [classed('app-rg-get').length, text(classed('app-rg-get')[0])], [1, 'Get the album'])
    check('the store asked about the pressing shown - the body Get would send', [stateAsks.length, JSON.stringify(stateAsks[0]?.body) === JSON.stringify(expected)], [1, true])
    check('...nothing said until it answers', find((node) => node.type === StoreState).length, 0)
    const opener = { focus() {} }
    classed('app-rg-get')[0].props.onClick({ currentTarget: opener })
    check('Get opens the sources for the CHOSEN pressing, the opener taken in the tap',
      [gets.length, gets[0]?.[0].release.release_mbid, gets[0]?.[0].subtitle, gets[0]?.[1] === opener, JSON.stringify(gets[0]?.[0].release) === JSON.stringify(expected)],
      [1, usual.id, 'The Slow Rush · CD · 2020 · AU · Caroline International', true, true])
    check('...searched as credited, filed under the current name, the album\'s own year', [gets[0]?.[0].release.artist, gets[0]?.[0].release.original_year], ['Tame Impala', '2020'])

    stateAsks[0].resolve({ held: null, downloading: { job_id: 1, status: 'queued', username: 'bob', files: 12 }, downloading_part: null, other_pressings: [] })
    await settle()
    draw()
    check('the answer drawn under the pressing: already downloading, cancelled in Requests', find((node) => node.type === StoreState)[0]?.props.status,
      { kind: 'downloading', title: 'Already downloading', lines: ['From bob · queued', 'To get it from another source, cancel it in Requests first.'] })
    check('...in a polite live region that is always there', classed('app-rg-store')[0]?.props['aria-live'], 'polite')
    check('...UNDER Get, where an answer landing late moves nothing a finger is reaching for (the pressing\'s facts, 2.0.0-player.50, under its picker)',
      classed('app-rg-actions')[0]?.props.children.filter(Boolean).map((child) => child.type === 'button' ? child.props.class : child.props?.class ?? child.type?.name), ['PressingPicker', 'app-rg-facts', 'app-rg-get', 'app-rg-store'].map((name) => name))

    //? another pressing: asked about afresh; the first's late answer must not stand for it
    const japan = byPrefix(slowRush, '452ccdb4')
    draw({ release: japan.id })
    check('another pressing chosen: the store asked about it', [stateAsks.length, stateAsks[1]?.body.release_mbid], [2, japan.id])
    check('...the last pressing\'s answer not drawn for this one', find((node) => node.type === StoreState).length, 0)
    classed('app-rg-get')[0].props.onClick({ currentTarget: opener })
    check('...and Get now gets THAT pressing - the dropdown decides what Get is for',
      [gets.length, gets[1]?.[0].release.release_mbid, gets[1]?.[0].release.tracks.length, gets[1]?.[0].subtitle], [2, japan.id, 13, 'The Slow Rush · CD · 2020 · JP · Caroline International'])
    draw({ release: null })
    check('back to the usual pressing: asked again, the Japanese CD\'s ask called off', [stateAsks.length, stateAsks[1].signal.aborted], [3, true])
    stateAsks[1].resolve({ held: null, downloading: { job_id: 2, status: 'queued', username: 'late', files: 13 }, downloading_part: null, other_pressings: [] })
    await settle()
    draw()
    check('the superseded answer, landing late, is not drawn - only this pressing\'s own last answer stands while it is asked again',
      find((node) => node.type === StoreState).map((box) => box.props.status.lines[0]), ['From bob · queued'])
    stateAsks[2].resolve({ held: { path: 'Tame Impala/The Slow Rush (2020)', paths: ['Tame Impala/The Slow Rush (2020)'], artist: 'Tame Impala', album: 'The Slow Rush', edition: '', track_count: 12, expected_tracks: 12, formats: ['flac'], complete: true, fills_gaps: false, filed_to: null },
      downloading: null, downloading_part: null, other_pressings: [{ path: 'Tame Impala/The Slow Rush (2020) [JP]', release_mbid: japan.id, edition: 'JP', year: '2020', track_count: 13, formats: ['flac'] }] })
    await settle()
    draw()
    check('held whole: said, with the other pressing as a note', [find((node) => node.type === StoreState)[0]?.props.status.title, find((node) => node.type === StoreState)[0]?.props.notes],
      ['Already in your library', ['You also have another pressing: JP · FLAC · Tame Impala/The Slow Rush (2020) [JP]']])
    announceAlbumsFiled()
    draw()
    check('an album filed: the store asked again', [stateAsks.length, stateAsks[3]?.body.release_mbid], [4, usual.id])
    //? an ask for the SAME pressing superseded (filed again while the last ask was out): its late answer
    //? must not stand - only the newest
    announceAlbumsFiled()
    draw()
    check('...and again, the last ask called off', [stateAsks.length, stateAsks[3].signal.aborted], [5, true])
    stateAsks[3].resolve({ held: null, downloading: { job_id: 9, status: 'queued', username: 'stale', files: 12 }, downloading_part: null, other_pressings: [] })
    await settle()
    draw()
    check('the superseded answer for the same pressing, landing late, is not drawn - the last real answer stands while it is asked again',
      find((node) => node.type === StoreState)[0]?.props.status.title, 'Already in your library')
    stateAsks[4].resolve({ held: null, downloading: null, downloading_part: null, other_pressings: [] })
    await settle()
    draw()
    check('...and the newest, with nothing to say, says nothing', find((node) => node.type === StoreState)[0]?.props.status ?? null, null)

    //? Get taps hand over to Requests, and the page stays mounted under Search's tab: coming back
    //? to it must say "Already downloading" - and a download cancelled in Requests meanwhile must not
    //? go on being said (review)
    draw({ shown: false })
    check('out of view (another tab, the sheet over it, the app in the background): nothing asked', stateAsks.length, 5)
    draw({ shown: true })
    check('shown again: asked again, for the same pressing', [stateAsks.length, stateAsks[5]?.body.release_mbid], [6, usual.id])
    stateAsks[5].resolve({ held: null, downloading: { job_id: 4, status: 'downloading', username: 'bob', files: 12, done_files: 3 }, downloading_part: null, other_pressings: [] })
    await settle()
    draw()
    check('...and the Get made meanwhile is said', find((node) => node.type === StoreState)[0]?.props.status.title, 'Already downloading')
    draw({ shown: false })
    draw({ shown: true })
    check('cancelled in Requests and back again: asked again - "Already downloading" standing until it answers',
      [stateAsks.length, find((node) => node.type === StoreState)[0]?.props.status.title], [7, 'Already downloading'])
    stateAsks[6].resolve({ held: null, downloading: null, downloading_part: null, other_pressings: [] })
    await settle()
    draw()
    check('...then no longer said', find((node) => node.type === StoreState)[0]?.props.status ?? null, null)
  }

  console.log('\nsomebody else\'s download on the album page (2.0.0-player.49): Join from the line, then the store asked again')
  {
    const { StoreState } = require(path.join(OUT, 'app/StoreState.js'))
    stateAsks.length = 0
    const joins = []
    globalThis.__group.joinJob = (jobId) => { joins.push(jobId); return Promise.resolve({ status: 'ok', job_id: jobId, joined: true }) }
    const { draw } = page({ id: slowRush.group.id, preview: PREVIEW })
    draw()
    stateAsks.at(-1).resolve({ held: null, downloading: { job_id: 12, status: 'queued', username: 'glassbeads', files: 12, yours: false,
      formats: ['flac'], bitrates: [], bit_depths: [16], sample_rates: [44100], variable_bitrate: false }, downloading_part: null, other_pressings: [] })
    await settle()
    draw()
    const box = find((node) => node.type === StoreState)[0]
    check('"Already downloading for someone else" under Get, what you\'d get, and a way to join it',
      [box?.props.status.title, box?.props.status.lines[0], box?.props.status.joinJobId, typeof box?.props.onJoin],
      ['Already downloading for someone else', 'From glassbeads · FLAC 16/44.1 · queued', 12, 'function'])
    const asksBefore = stateAsks.length
    await box.props.onJoin(12)
    draw()
    check('Join joins it - and the store is asked again, so the line can say it is yours', [joins, stateAsks.length], [[12], asksBefore + 1])
    stateAsks.at(-1).resolve({ held: null, downloading: { job_id: 12, status: 'queued', username: 'glassbeads', files: 12, yours: true, shared: true,
      formats: ['flac'] }, downloading_part: null, other_pressings: [] })
    await settle()
    draw()
    check('...and it does: yours now, a cancel only taking it off your list', find((node) => node.type === StoreState)[0]?.props.status,
      { kind: 'downloading', title: 'Already downloading', lines: ['From glassbeads · queued',
        "Someone else asked for it too, so cancelling it in Requests only takes it off your list - another source isn't offered for a download you share."] })
  }

  console.log('\na cold link: Get builds from the group the pressings carry, the pressing\'s credit where it has none')
  {
    const P2 = require(path.join(OUT, 'lib/pressings.js'))
    const bare = { id: dummy.group.id, title: 'Dummy', 'first-release-date': '1994-08-22' }
    const chosen = byPrefix(dummy, '87888070')
    check('the group\'s own title and year, the pressing\'s credit standing in for the missing one', P2.getGroup(dummy.group.id, null, dummy.releases.map((release) => ({ ...release, 'release-group': bare })), chosen),
      { id: dummy.group.id, title: 'Dummy', 'first-release-date': '1994-08-22', 'artist-credit': chosen['artist-credit'] })
    check('...no group at all: the pressing\'s title, the earliest date any pressing came out', [P2.getGroup('x', null, dummy.releases, chosen).title, P2.getGroup('x', null, dummy.releases, chosen)['first-release-date'].slice(0, 4)],
      ['Dummy', '1994'])
    check('...Search\'s group wins when it has one', P2.getGroup('x', PREVIEW, slowRush.releases, null)['artist-credit'], PREVIEW['artist-credit'])
  }

  console.log('\non a desktop (2.0.0-player.19): Get and the pressing inline, a table, and the Sources panel following the pressing')
  {
    const gets = []
    const closes = []
    const onGet = (request, opener) => gets.push([request, opener])
    const phone = page({ id: slowRush.group.id, preview: PREVIEW, onGet })
    phone.draw()
    check('a phone\'s Get says nothing of a panel', 'aria-pressed' in classed('app-rg-get')[0].props, false)
    const desk = page({ id: slowRush.group.id, preview: PREVIEW, onGet, desktop: true, onCloseSources: () => closes.push(1) })
    desk.draw()
    //? the desktop's tracklist is a component of its own (no hooks): drawn here from the page's element
    const table = () => {
      const element = find((node) => node.type?.name === 'DeskTracklist')[0]
      return element ? element.type(element.props) : null
    }
    check('Get first, the pressing inline after it, its facts (2.0.0-player.50) and what is already here under both',
      classed('app-rg-actions')[0]?.props.children.filter(Boolean).map((child) => child.type === 'button' ? child.props.class : child.props?.class ?? child.type?.name),
      ['app-rg-get', 'PressingPicker', 'app-rg-facts', 'app-rg-store'])
    check('...Get not pressed: the panel isn\'t showing this page\'s sources', classed('app-rg-get')[0].props['aria-pressed'], false)
    check('the tracklist: "Tracklist", the line, and a table - its "Against the usual tracklist" column, since some pressings differ',
      [text(find(byClass('app-rg-desk-title'), table())[0]), text(find(byClass('app-rg-summary'), table())[0]), find((node) => node.type === 'th', table()).map(text), classed('app-rg-list').length],
      ['Tracklist', 'The usual tracklist, shared by 9 of 10 pressings', ['#', 'Title', 'Compared with the usual', 'Length'], 0])
    check('...the usual pressing\'s twelve rows, none marked, their against cells empty',
      [find(byClass('app-rg-row'), table()).length, find(byClass('is-marked'), table()).length, find(byClass('app-rg-against'), table()).map(text).join('')], [12, 0, ''])
    const japan = byPrefix(slowRush, '452ccdb4')
    desk.draw({ release: japan.id })
    const bonus = find(byClass('is-bonus'), table())[0]
    check('the Japanese CD: Patience a Bonus row, its chip and note in that column - the board\'s short words, the whole note its tooltip',
      [text(find(byClass('app-rg-title'), bonus)[0]), text(find(byClass('app-rg-chip'), bonus)[0]), text(find(byClass('app-rg-note'), bonus)[0]),
        find(byClass('app-rg-against'), bonus)[0].props.title, find(byClass('app-rg-title'), bonus)[0].props.title],
      ['Patience', 'Bonus', 'only on this pressing', 'Bonus · Only on this pressing', 'Patience'])
    const singleMix = slowRush.releases.find((release) => /single mix/.test(release.disambiguation ?? ''))
    desk.draw({ release: singleMix.id })
    const version = find(byClass('is-version'), table())[0]
    check('...the single mix: "Other version · usually 3:58" - short enough for the column, the usual length kept',
      [text(find(byClass('app-rg-chip'), version)[0]), text(find(byClass('app-rg-note'), version)[0]), find(byClass('app-rg-against'), version)[0].props.title],
      ['Other version', 'usually 3:58', 'Other version · The usual version is 3:58'])
    check('...an unmarked row\'s against cell has no tooltip', find(byClass('app-rg-row'), table()).filter((row) => !row.props.class.includes('is-marked'))
      .map((row) => find(byClass('app-rg-against'), row)[0].props.title).filter((title) => title !== undefined), [])
    //? an album whose pressings are all alike: no such column (DesktopRequest.dc.html)
    const view = P.pressingsView(slowRush.releases)
    const usualIds = new Set([...view.shown, ...view.more].filter((row) => row.kind === 'usual').map((row) => row.id))
    const ALIKE = '00000000-0000-4000-8000-000000000010'
    answers.push(() => Promise.resolve({ id: ALIKE, releases: slowRush.releases.filter((release) => usualIds.has(release.id)), problem: null }))
    const alike = page({ id: ALIKE, onGet, desktop: true })
    alike.draw()
    await settle()
    alike.draw()
    check('every pressing alike: #, Title and Length, no column for differences', find((node) => node.type === 'th', table()).map(text), ['#', 'Title', 'Length'])
    check('...as anyPressingDiffers says', [P.anyPressingDiffers(view), P.anyPressingDiffers({ shown: [{ kind: 'usual' }], more: [{ kind: 'none' }] }), P.anyPressingDiffers(null)], [true, false, false])

    //? the panel opened by this page's Get, then following the pressing - App hands the page the
    //? pressing its panel searched for this album (`sourcesPressing`), as a Get's answer becomes it
    desk.draw({ release: null })
    const opener = { focus() {} }
    classed('app-rg-get')[0].props.onClick({ currentTarget: opener })
    check('Get opens the sources for the chosen pressing, saying which page asked', [gets.length, gets[0]?.[0].from, gets[0]?.[0].again ?? null], [1, slowRush.group.id, null])
    const usual = gets[0][0].release.release_mbid
    desk.draw({ sourcesPressing: usual })
    check('the panel showing this pressing\'s sources: Get pressed', classed('app-rg-get')[0].props['aria-pressed'], true)
    desk.draw()
    check('...nothing asked again for the pressing it was opened for', gets.length, 1)
    classed('app-rg-get')[0].props.ref.current = opener
    const single = slowRush.releases.find((release) => /single mix/.test(release.disambiguation ?? ''))
    desk.draw({ release: single.id })
    check('another pressing chosen beside it: Get no longer pressed (the panel shows the other\'s), and this one asked for - `again`, from this page, focus going back to Get',
      [classed('app-rg-get')[0].props['aria-pressed'], gets.length, gets[1]?.[0].release.release_mbid, gets[1]?.[0].again, gets[1]?.[0].from, gets[1]?.[1] === opener,
        gets[1]?.[0].subtitle.startsWith('The Slow Rush · Digital')],
      [false, 2, single.id, true, slowRush.group.id, true, true])
    desk.draw()
    check('...once for each pressing', gets.length, 2)
    desk.draw({ sourcesPressing: single.id })
    check('...and pressed again once the panel shows its sources, asking nothing more', [classed('app-rg-get')[0].props['aria-pressed'], gets.length], [true, 2])
    classed('app-rg-get')[0].props.onClick({ currentTarget: opener })
    check('Get, pressed, closes the panel - and gets nothing', [closes.length, gets.length], [1, 2])
    desk.draw({ sourcesPressing: null })
    desk.draw({ release: japan.id })
    check('the panel showing something else (or nothing): another pressing asks for nothing, and Get isn\'t pressed', [gets.length, classed('app-rg-get')[0].props['aria-pressed']], [2, false])

    //? (review) the page met again with the panel still open for another pressing of the album - Back to
    //? Search's results, and the same album again: it comes back at its usual pressing
    const again = []
    const back = page({ id: slowRush.group.id, preview: PREVIEW, onGet: (request, opener) => again.push([request, opener]), desktop: true,
      sourcesPressing: single.id, onCloseSources: () => closes.push(1) })
    back.draw()
    check('mounted at the usual pressing with the panel open for the single mix: Get isn\'t pressed, and the panel is asked to follow - `again`, for the pressing on screen',
      [classed('app-rg-get')[0].props['aria-pressed'], again.length, again[0]?.[0].release.release_mbid, again[0]?.[0].again],
      [false, 1, usual, true])
    back.draw({ sourcesPressing: usual })
    classed('app-rg-get')[0].props.onClick({ currentTarget: opener })
    check('...the panel following it: Get pressed, and a click closes it rather than searching', [classed('app-rg-get')[0].props['aria-pressed'], closes.length, again.length], [true, 2, 1])
    //? the same album open on another tab, at another pressing, doesn't show - it never takes a turn
    const hidden = []
    const other = page({ id: slowRush.group.id, preview: PREVIEW, release: japan.id, onGet: (request) => hidden.push(request), desktop: true, shown: false,
      sourcesPressing: usual })
    other.draw()
    check('a page of the album that isn\'t showing asks for nothing', hidden.length, 0)
    other.draw({ shown: true })
    check('...until it shows: then its own pressing', [hidden.length, hidden[0]?.release.release_mbid, hidden[0]?.again], [1, japan.id, true])
  }

  console.log('\nanother pressing of an album you hold (2.0.0-player.41): held ones marked, Get as ever')
  {
    const japan = byPrefix(slowRush, '452ccdb4').id
    //? the usual CD by the group's folders, the Japanese CD by a release id alone (an m4a deadwax filed)
    globalThis.__group.owned = owning([
      { path: 'Tame Impala/The Slow Rush (2020)', release_mbid: slowRush.expected.representative, release_group_mbid: slowRush.group.id },
      { path: 'Tame Impala/The Slow Rush (2020) [Japan]', release_mbid: japan, release_group_mbid: '' },
      { path: 'Portishead/Dummy (1994)', release_mbid: dummy.expected.representative, release_group_mbid: dummy.group.id },
    ])
    const gets = []
    const { draw } = page({ id: slowRush.group.id, preview: PREVIEW, onGet: (request) => gets.push(request) })
    draw()
    const view = find((node) => node.type === PressingPicker)[0]?.props.view
    const rows = [...(view?.shown ?? []), ...(view?.more ?? [])]
    check('the list marks every pressing you hold - the usual CD by its folder\'s group, the Japanese CD by its id alone - and only those',
      rows.filter((row) => row.held).map((row) => row.id).sort(), [slowRush.expected.representative, japan].sort())
    check('...neither folded away', view?.more.filter((row) => row.held).length, 0)
    check('Get still there on a pressing you hold, opening the sources for it - where the store line and the sheet say it is already here',
      (classed('app-rg-get')[0]?.props.onClick({ currentTarget: null }), gets.map((request) => request.release.release_mbid)), [slowRush.expected.representative])
    //? (review) a folder found by the group's own id whose release id tag was written in capitals, by
    //? hand - its pressing is still the one marked
    globalThis.__group.owned = owning([
      { path: 'Tame Impala/The Slow Rush (2020) [Japan]', release_mbid: ` ${japan.toUpperCase()} `, release_group_mbid: slowRush.group.id },
    ])
    draw()
    const capitals = find((node) => node.type === PressingPicker)[0]?.props.view
    check('a held folder\'s release id in capitals (and spaced), found by the group\'s id: its pressing still marked, and only it',
      [...(capitals?.shown ?? []), ...(capitals?.more ?? [])].filter((row) => row.held).map((row) => row.id), [japan])
    globalThis.__group.owned = null
    draw()
    check('the library not answered: nothing marked', [...find((node) => node.type === PressingPicker)[0].props.view.shown].some((row) => row.held), false)

    const render = hooks.root(PressingPicker)
    const marked = P.pressingsView(slowRush.releases, null, new Set([japan]))
    tree = render({ view: marked, onPick() {} })
    classed('app-picker-button')[0].props.onClick()
    tree = render({ view: marked, onPick() {} })
    const held = find((node) => node.props?.role === 'option').filter((option) => find(byClass('app-picker-held'), option).length)
    check('drawn: "In your library" under the held pressing\'s note, inside its option (read with it)',
      held.map((option) => [option.key, text(find(byClass('app-picker-held'), option)[0])]), [[japan, 'In your library']])

    asked.length = 0
    //? a group the session hasn't kept yet (Dummy's pressings, under an id of their own)
    const UNSEEN = '00000000-0000-4000-8000-000000000041'
    answers.push(() => Promise.resolve({ id: UNSEEN, releases: dummy.releases, problem: null }))
    const cold = page({ id: UNSEEN, title: 'Dummy (Remastered)' })
    cold.draw()
    check('opened from the album you have, no group from Search: its name as the title until MusicBrainz answers',
      [text(classed('pl-hero-title')[0]), text(classed('pl-hero-meta')[0])], ['Dummy (Remastered)', ''])
    await settle()
    cold.draw()
    check('...then MusicBrainz\'s own title for the album, never the name it was opened with', text(classed('pl-hero-title')[0]), 'Dummy')
  }

  console.log('\nsearch extras (2.0.0-player.50): the pressing\'s facts, the maybe, the links out, the list\'s filter')
  {
    globalThis.__group.owned = owning([])
    const { draw } = page({ id: slowRush.group.id, preview: PREVIEW })
    draw()
    const facts = () => classed('app-rg-facts')[0]
    const japan = byPrefix(slowRush, '452ccdb4')
    const usual = byPrefix(slowRush, '1cf564b9')
    check('the chosen pressing\'s facts under the picker - the one element, its whole in its tooltip',
      [classed('app-rg-facts').length, text(facts()), facts()?.props.title], [1, P.pressingFacts(usual), P.pressingFacts(usual)])
    check('...the usual CD\'s, as MusicBrainz gives them', text(facts()), 'Official · 2020-02-14 · Fiction / Interscope Records / Island · Cat. no. 7757960')
    draw({ release: japan.id })
    check('another pressing chosen: the same line, saying its facts', [classed('app-rg-facts').length, text(facts())], [1, 'Official · 2020-02-14 · Fiction / Island · Cat. no. UICB-1004'])
    check('...and every pressing\'s are in the list the picker draws', find((node) => node.type === PressingPicker)[0].props.view.shown.every((row) => row.facts === P.pressingFacts(slowRush.releases.find((release) => release.id === row.id))), true)
    const links = () => classed('app-rg-link').map((link) => [text(link), link.props.href, link.props.target, link.props.rel])
    check('the album and the pressing chosen on musicbrainz.org, at the foot, opening beside the app', links(), [
      ['The album ↗', `https://musicbrainz.org/release-group/${slowRush.group.id}`, '_blank', 'noopener'],
      ['This pressing ↗', `https://musicbrainz.org/release/${japan.id}`, '_blank', 'noopener']])
    check('...after the tracklist, the page\'s last part', find(byClass('app-rg'))[0].props.children.filter(Boolean).at(-1)?.props.class, 'app-rg-links')
    check('not in your library: said as ever, no maybe', [text(classed('pl-hero-meta')[0]), classed('app-rg-maybe').length], ['2020 · Album · not in your library', 0])
    //? a folder with no MusicBrainz ids of the album's name, filed under its artist
    globalThis.__group.owned = owning([{ path: 'Old Rips/Tame Impala - The Slow Rush', artist: 'Tame Impala', album: 'The Slow Rush', formats: ['mp3'] }])
    draw()
    const maybe = classed('app-rg-maybe')[0]
    check('a folder of its name with no ids: "maybe in your library", dashed - the year and kind still before it',
      [text(classed('pl-hero-meta')[0]), text(maybe), maybe?.type], ['2020 · Album · maybe in your library', 'maybe in your library', 'span'])
    check('...its folders in its tooltip, as the main page\'s card says them (logins off: everyone can Edit albums)', maybe?.props.title.includes('Old Rips/Tame Impala - The Slow Rush (MP3)') && maybe.props.title.startsWith('A folder with this name, not matched to a pressing'), true)
    //? (2.0.6, UX batch 3: RG5) ...and said in words anyone reads, under Get - the tooltip was its only explanation, which a phone never shows
    check('(2.0.6) ...and why, in a line under Get, how to settle it for whoever can Edit albums', [text(classed('app-rg-maybe-note')[0]), classed('app-rg-maybe-note')[0]?.props.class],
      ["You may already have this - an album with this name is in your library, but it isn't matched to a pressing. Match it to a pressing in Edit album.", 'app-footnote app-rg-maybe-note'])
    {
      const session = require(path.join(OUT, 'app/session.js'))
      session.setSessionMe({ user: 'ethan', auth: 'on', admin: false })
      draw()
      check('(2.0.6) ...a listener who can\'t Edit albums: the line without the how, and no folders in a tooltip', [text(classed('app-rg-maybe-note')[0]), classed('app-rg-maybe')[0]?.props.title],
        ["You may already have this - an album with this name is in your library, but it isn't matched to a pressing.", undefined])
      session.setSessionMe(null)
      draw()
    }
    globalThis.__group.owned = owning([{ path: 'Old Rips/Tame Impala - The Slow Rush', artist: 'Tame Impala', album: 'The Slow Rush' },
      { path: 'Tame Impala/The Slow Rush (2020)', release_mbid: usual.id, release_group_mbid: slowRush.group.id }])
    draw()
    check('held by an id as well: "in your library", no maybe', [text(classed('pl-hero-meta')[0]), classed('app-rg-maybe').length], ['2020 · Album · in your library', 0])
    globalThis.__group.owned = owning([{ path: 'Old Rips/Someone Else - The Slow Rush', artist: 'Someone Else', album: 'The Slow Rush' },
      { path: 'Old Rips/Tame Impala - Lonerism', artist: 'Tame Impala', album: 'Lonerism' }])
    draw()
    check('a folder of the name by another artist, or of another album by the artist: no maybe', [text(classed('pl-hero-meta')[0]), classed('app-rg-maybe').length], ['2020 · Album · not in your library', 0])
    globalThis.__group.owned = null
    draw()
    check('the library not answered: nothing said of it, maybe or not', [text(classed('pl-hero-meta')[0]), classed('app-rg-maybe').length], ['2020 · Album', 0])

    const refused = page({ id: 'not-a-group' })
    refused.draw()
    check('a link that isn\'t an album\'s: no links out', classed('app-rg-links').length, 0)

    //? an album of many pressings: The Slow Rush four times over, each a pressing of its own
    const many = slowRush.releases.flatMap((release, copy) => [0, 1, 2, 3].map((n) => ({ ...release, id: `${release.id.slice(0, -2)}${copy}${n}` })))
    const big = P.pressingsView(many)
    const picker = hooks.root(PressingPicker)
    const picks = []
    const show = (view) => { tree = picker({ view, onPick: (id) => picks.push(id) }); picker.commit(); return tree }
    show(P.pressingsView(slowRush.releases))
    classed('app-picker-button')[0].props.onClick()
    show(P.pressingsView(slowRush.releases))
    check('ten pressings: no filter; each option its label, then its facts, then its note',
      [classed('app-picker-filter').length, find((node) => node.props?.role === 'option')[0]?.props.children[1].props.children.filter(Boolean).map((part) => part.props.class)],
      [0, ['app-picker-option-label', 'app-picker-facts', 'app-picker-note']])
    const said = () => find((node) => node.props?.role === 'status', classed('app-picker-popover')[0])
    check('...and no region to say what a filter left', said().length, 0)
    classed('app-picker')[0].props.onKeyDown({ key: 'Escape', preventDefault() {} })
    show(big)
    classed('app-picker-button')[0].props.onClick()
    show(big)
    const field = () => find((node) => node.type === 'input' && byClass('app-picker-filter-input')(node))[0]
    const listbox = () => find((node) => node.props?.role === 'listbox')[0]
    check('forty: a filter at the top, outside the listbox, named, its list the one it controls',
      [many.length, !!field(), find(byClass('app-picker-filter'), listbox()).length, text(find(byClass('app-visually-hidden'), classed('app-picker-filter')[0])[0]), field()?.props['aria-controls'] === listbox()?.props.id],
      [40, true, 0, 'Filter the pressings', true])
    check('...its placeholder saying what works, as the rows say it - a country by its code (review: "country" asked for "Japan")',
      field()?.props.placeholder, 'JP, CD, a label or catalogue no.')
    //? (review: "No pressing matches" was a region made with its words, which VoiceOver doesn't read, and
    //? nothing said how many matched) one region, there before a word is typed, saying what's left
    check('...and a polite live region in the list before anything is typed, read out but never drawn, empty',
      [said().length, said()[0]?.props.class, said()[0]?.props['aria-live'], text(said()[0])], [1, 'app-visually-hidden', 'polite', ''])
    const shown = find((node) => node.props?.role === 'option').length
    field().props.onInput({ currentTarget: { value: 'jp' } })
    show(big)
    check('typed "jp": only the Japanese CDs, folded ones included - and the fold steps aside',
      [find((node) => node.props?.role === 'option').map((option) => option.key.slice(0, 8)), classed('app-picker-more').length, shown < 40],
      [['452ccdb4', '452ccdb4', '452ccdb4', '452ccdb4'], 0, true])
    check('...said by the region: how many match', [said().length, text(said()[0])], [1, '4 pressings match.'])
    field().props.onInput({ currentTarget: { value: 'jp vinyl' } })
    show(big)
    check('nothing matches: said, in words', [find((node) => node.props?.role === 'option').length, text(classed('app-picker-none')[0])], [0, 'No pressing matches “jp vinyl”.'])
    check('...by the same one region - the line drawn under the list no region of its own, so it isn\'t said twice',
      [said().length, text(said()[0]), said()[0]?.props.class, classed('app-picker-none')[0]?.props.role], [1, 'No pressing matches “jp vinyl”.', 'app-visually-hidden', undefined])
    //? the keys, with the page's elements stood in for
    const focused = []
    const input = { focus: () => focused.push('field') }
    const first = { focus: () => focused.push('first') }
    const second = { focus: () => focused.push('second') }
    field().props.onInput({ currentTarget: { value: 'jp' } })
    show(big)
    field().props.ref.current = input
    classed('app-picker')[0].props.ref.current = { querySelectorAll: () => [first, second], contains: () => true }
    globalThis.document = { activeElement: input }
    const keys = []
    const key = (name) => classed('app-picker')[0].props.onKeyDown({ key: name, preventDefault: () => keys.push(name) })
    key('Home')
    key('ArrowUp')
    check('in the field, its own keys stay its own - Home, the arrows across its text', [focused, keys], [[], []])
    key('ArrowDown')
    check('...ArrowDown goes to the first pressing', [focused, keys], [['first'], ['ArrowDown']])
    globalThis.document = { activeElement: first }
    key('ArrowUp')
    check('...and ArrowUp from the first pressing back up to the filter', focused, ['first', 'field'])
    delete globalThis.document
    find((node) => node.props?.role === 'option')[1].props.onClick()
    show(big)
    check('a pick handed on, the list closed', [picks.length, classed('app-picker-popover')[0].props.hidden], [1, true])
    check('...the region kept, emptied with the filter', [said().length, text(said()[0])], [1, ''])
    classed('app-picker-button')[0].props.onClick()
    show(big)
    check('...and opened again, the filter empty and the whole list back as it folds', [field()?.props.value, find((node) => node.props?.role === 'option').length, classed('app-picker-more').length > 0],
      ['', shown, true])
    //? (review: the Pressing button's own press closed the list and kept the words typed)
    field().props.onInput({ currentTarget: { value: 'jp' } })
    show(big)
    classed('app-picker-button')[0].props.onClick()
    show(big)
    check('closed by the Pressing button itself: the list hidden and the filter emptied', [classed('app-picker-popover')[0].props.hidden, field()?.props.value], [true, ''])
    classed('app-picker-button')[0].props.onClick()
    show(big)
    check('...and opened again by it, the whole list back as it folds', [field()?.props.value, find((node) => node.props?.role === 'option').length, classed('app-picker-more').length > 0],
      ['', shown, true])
  }

  console.log('\nwith logins on: "in your library" means yours - and the store line\'s fresh word over a kept answer (2.0.0-player.52)')
  {
    const session = require(path.join(OUT, 'app/session.js'))
    const { StoreState } = require(path.join(OUT, 'app/StoreState.js'))
    const shownId = dummy.expected.representative
    const folder = 'Portishead/Dummy (1994)'
    const heldLine = (yours) => ({ held: { path: folder, paths: [folder], artist: 'Portishead', album: 'Dummy', edition: '', track_count: 11, expected_tracks: 11,
      formats: ['flac'], complete: true, fills_gaps: false, filed_to: null, ...(yours === undefined ? {} : { yours }) }, downloading: null, downloading_part: null, other_pressings: [] })
    const owns = (yours) => owning([{ path: folder, artist: 'Portishead', album: 'Dummy', release_group_mbid: dummy.group.id, release_mbid: shownId,
      ...(yours === undefined ? {} : { yours }) }])
    const meta = () => text(classed('pl-hero-meta')[0])
    const storeLine = () => find((node) => node.type === StoreState)[0]?.props.status?.title ?? null
    const mark = () => {
      const view = find((node) => node.type === PressingPicker)[0].props.view
      const row = [...view.shown, ...view.more].find((each) => each.id === shownId)
      return [row.id === view.chosenId, row.held, !!row.inStore]
    }
    session.setSessionMe({ user: 'ethan', auth: 'on', admin: false })
    globalThis.__group.ownedAsks = 0
    globalThis.__group.owned = owns(false)
    answers.push(answering(dummy))
    const first = page({ id: dummy.group.id })
    first.draw()
    await settle()
    first.draw()
    check('ethan, Dummy the store\'s and not his: the library asked as the page shows, the meta line "in the collection"',
      [globalThis.__group.ownedAsks, meta()], [1, '1994 · in the collection'])
    stateAsks.at(-1).resolve(heldLine(false))
    await settle()
    first.draw()
    check('...under "In the collection, not in your library", the pressing on screen marked "In the collection"',
      [meta(), storeLine(), mark()], ['1994 · in the collection', 'In the collection, not in your library', [true, true, true]])
    first.draw({ shown: false })
    const hidden = globalThis.__group.ownedAsks
    first.draw({ shown: true })
    check('the library not asked as the page goes out of view, and asked again as it shows again', [hidden, globalThis.__group.ownedAsks], [1, 2])

    //? the library's answer kept from earlier in the session says Dummy is his; he has unstarred it in Amperfy
    //? since, and the read-back has taken it out of his library - the store line, asked as the page shows, says so
    globalThis.__group.owned = owns(true)
    const stale = page({ id: dummy.group.id })
    stale.draw()
    check('a library answer kept from before an unstar was read back: the page asks the library again as it shows',
      [globalThis.__group.ownedAsks, meta(), storeLine()], [3, '1994 · in your library', null])
    stateAsks.at(-1).resolve(heldLine(false))
    await settle()
    stale.draw()
    check('...and the store line\'s fresh word wins: "in the collection" over "In the collection, not in your library" - never "in your library" over it',
      [meta(), storeLine(), mark(), / · in your library$/.test(meta())], ['1994 · in the collection', 'In the collection, not in your library', [true, true, true], false])
    //? ...and the other way: starred in Amperfy since, read back into his library
    globalThis.__group.owned = owns(false)
    const starred = page({ id: dummy.group.id })
    starred.draw()
    stateAsks.at(-1).resolve(heldLine(true))
    await settle()
    starred.draw()
    check('...the other way too: starred since, "in your library" over "Already in your library", the pressing unmarked',
      [meta(), storeLine(), mark()], ['1994 · in your library', 'Already in your library', [true, true, false]])

    session.setSessionMe(null)
    globalThis.__group.owned = owns(undefined)
    const off = page({ id: dummy.group.id })
    off.draw()
    stateAsks.at(-1).resolve(heldLine(undefined))
    await settle()
    off.draw()
    check('logins off: "in your library" over "Already in your library", nothing marked the store\'s - as ever',
      [meta(), storeLine(), mark()], ['1994 · in your library', 'Already in your library', [true, true, false]])
    globalThis.__group.owned = null
  }

  console.log('\nopened from a song Search found (2.0.0-player.53): a pressing with the song, the song marked and brought into view')
  {
    const rush = JSON.parse(fs.readFileSync(path.join(FIXTURES, '../songs/slow-rush-pressings.json'), 'utf8'))
    const recording = (prefix) => rush.releases.flatMap((r) => r.media.flatMap((m) => m.tracks)).find((t) => t.recording.id.startsWith(prefix)).recording.id
    const PATIENCE = recording('bba0e134'), SINGLE_MIX = recording('ebbf5e17')
    const JP = rush.releases.find((r) => r.id.startsWith('452ccdb4')).id
    const AU = rush.releases.find((r) => r.id.startsWith('1cf564b9')).id
    //? under an id of its own: The Slow Rush's pressings without recording ids are kept for the session above
    rush.group = '00000000-0000-4000-8000-0000000000a1'
    const answeringRush = () => Promise.resolve({ id: rush.group, releases: rush.releases, problem: null })
    //? a page's scroll and its tracklist's song row, as the browser would have them
    const scrolled = []
    globalThis.window = { scrollY: 0 }
    const mount = (props) => {
      const made = page({ id: rush.group, title: 'The Slow Rush', ...props })
      made.draw()
      const section = find((node) => node.type === 'section' && node.props.class === 'pl-album-page app-rg')[0]
      section.props.ref.current = { querySelector: (selector) => (selector === '.is-song' ? { scrollIntoView: (how) => scrolled.push(how) } : null) }
      return made
    }
    const songRows = () => classed('is-song').map((row) => text(row))

    answers.length = 0
    answers.push(answeringRush)
    const { draw, picks } = mount({ song: PATIENCE })
    await settle()
    draw()
    const view = find((node) => node.type === PressingPicker)[0]?.props.view
    check('Patience, a bonus track: the page opens on the Japanese CD that has it, not the usual pressing', [view?.chosenId === JP, view?.defaultId === AU], [true, true])
    check('...its Patience the one row marked - still a Bonus track - and said to a screen reader', [songRows(), classed('is-song')[0]?.props.class],
      [['13Patience, the song you searched forOnly on this pressingBonus4:53'], 'app-rg-track is-marked is-bonus is-song'])
    check('...brought into view once, as it is first drawn', scrolled, [{ block: 'nearest' }])
    draw()
    draw()
    check('...and never again on that page', scrolled.length, 1)
    find((node) => node.type === PressingPicker)[0].props.onPick(AU)
    check('a pick on it is written into the address even when it is the usual pressing - so the song never overrules it', picks, [[rush.group, AU]])
    draw({ release: AU })
    check('...which then shows, the song not on it marked nowhere', [find((node) => node.type === PressingPicker)[0].props.view.chosenId === AU, songRows()], [true, []])

    scrolled.length = 0
    globalThis.window.scrollY = 640
    const back = mount({ song: PATIENCE })
    back.draw()
    check('come back to with its scroll put back (or scrolled meanwhile): left where it is', [songRows().length, scrolled], [1, []])

    globalThis.window.scrollY = 0
    const away = mount({ song: PATIENCE, shown: false })
    away.draw()
    check('not showing (another tab, a sheet over it): nothing scrolled', scrolled, [])
    away.draw({ shown: true })
    check('...brought into view once it shows', scrolled, [{ block: 'nearest' }])

    scrolled.length = 0
    const single = mount({ song: SINGLE_MIX })
    single.draw()
    check('Borderline\'s single mix, another recording: the usual pressing has Borderline - it opens on that, Borderline marked',
      [find((node) => node.type === PressingPicker)[0].props.view.chosenId === AU, songRows().map((row) => row.replace(/[0-9:]/g, ''))], [true, ['Borderline, the song you searched for']])
    const named = mount({ song: PATIENCE, release: AU })
    named.draw()
    check('a pressing the address names wins over the song\'s', find((node) => node.type === PressingPicker)[0].props.view.chosenId === AU, true)
    const plain = page({ id: rush.group })
    plain.draw()
    check('a page from no song marks nothing, scrolls nothing - and a pick of the usual pressing takes it out of the address, as ever', [classed('is-song').length, scrolled.length], [0, 1])
    find((node) => node.type === PressingPicker)[0].props.onPick(AU)
    check('...', plain.picks, [[rush.group, null]])

    const desk = mount({ song: PATIENCE, desktop: true })
    desk.draw()
    //? the desktop's tracklist, a component of its own, drawn from the page's element as above
    const deskTable = find((node) => node.type?.name === 'DeskTracklist')[0]
    const marked = find((node) => node.type === 'tr' && typeof node.props.class === 'string' && node.props.class.includes('is-song'), deskTable.type(deskTable.props))
    check('on a desktop: the table\'s row of the song marked and said', [marked.length, marked[0] && text(find(byClass('app-rg-title'), marked[0])[0])],
      [1, 'Patience, the song you searched for'])
    delete globalThis.window
  }

  console.log('\nits description (2.0.13): asked by the group\'s id once the pressings are in, the tracklist waiting for it a moment')
  {
    const G = globalThis.__group
    const timers = []
    const realTimeout = globalThis.setTimeout, realClear = globalThis.clearTimeout
    globalThis.setTimeout = (fn, ms) => { const timer = { fn, ms, live: true }; timers.push(timer); return timer }
    globalThis.clearTimeout = (timer) => { if (timer) timer.live = false }
    //? groups the session has kept no pressings of: pages opened for the first time
    const FIRST = 'aaaaaaaa-1111-4000-8000-000000000001', SECOND = 'aaaaaaaa-1111-4000-8000-000000000002'
    G.describeAsks.length = 0
    G.describing = { description: null, settled: false, at: null }
    answers.push(answering(dummy))
    const { draw } = page({ id: FIRST })
    draw()
    check('not asked while the pressings are out - its MusicBrainz lookup never takes a turn ahead of theirs', G.describeAsks.at(-1), ['album', null, false, FIRST])
    await settle()
    draw()
    check('...the pressings in: asked, by the group\'s id alone (an album you don\'t have has nothing of Navidrome\'s)', G.describeAsks.at(-1), ['album', { mbid: FIRST }, false, FIRST])
    check('the pressings in, the description not: the tracklist waits, saying it is loading', [classed('app-rg-track').length, text(classed('app-asking')[0])], [0, 'Loading…'])
    const WIKI = { paragraph: { text: 'Dummy is the debut studio album by Portishead.', source: 'wikipedia', url: 'https://en.wikipedia.org/wiki/Dummy_(album)' },
      subtitle: '1994 studio album by Portishead' }
    const before = G.describeAsks.length
    G.describing = { description: WIKI, settled: true, at: 'top' }
    draw()
    const blocks = () => find((node) => node.type?.name === 'DescriptionBlock')
    check('...it came: under the hero - subtitle and paragraph together - then the tracklist',
      [blocks().map((node) => node.props.at), blocks()[0]?.props.description.subtitle, classed('app-rg-track').length > 0, G.describeAsks[before][2]],
      [['top'], WIKI.subtitle, true, false])
    const kids = tree.props.children.flat(Infinity).filter((node) => node && typeof node === 'object')
    check('...between the hero and the tracklist', [kids.findIndex((node) => node.props?.class === 'pl-album-hero') < kids.findIndex((node) => node.type?.name === 'DescriptionBlock'),
      kids.findIndex((node) => node.type?.name === 'DescriptionBlock') < kids.findIndex((node) => node.props?.class === 'app-rg-tracks')], [true, true])
    draw()
    check('...the page told the tracklist is drawn, from then on', G.describeAsks.at(-1)[2], true)
    G.describing = { description: WIKI, settled: true, at: 'foot' }
    draw()
    const foot = tree.props.children.flat(Infinity).filter((node) => node && typeof node === 'object')
    check('one placed at the foot: under the tracklist, above the links to MusicBrainz', [blocks().map((node) => node.props.at),
      foot.findIndex((node) => node.type?.name === 'DescriptionBlock') > foot.findIndex((node) => node.props?.class === 'app-rg-tracks'),
      foot.findIndex((node) => node.type?.name === 'DescriptionBlock') < foot.findIndex((node) => node.props?.class === 'app-rg-links')], [['foot'], true, true])

    //? come back to (Back) with its description still out: its pressings from the session - the tracklist on the first
    //? frame, which the scroll put back needs
    G.describing = { description: null, settled: false, at: null }
    const back = page({ id: FIRST })
    back.draw()
    check('come back to, the description still out: the tracklist on the first frame', classed('app-rg-track').length > 0, true)

    //? never answering: the tracklist drawn after DESCRIPTION_WAIT_MS all the same
    answers.push(answering(slowRush))
    const late = page({ id: SECOND })
    late.draw()
    await settle()
    late.draw()
    check('the description never coming: the tracklist waits...', classed('app-rg-track').length, 0)
    const due = timers.filter((timer) => timer.ms === 500 && timer.live)
    due.forEach((timer) => timer.fn())
    late.draw()
    check('...DESCRIPTION_WAIT_MS at most, then drawn without it', [due.length > 0, classed('app-rg-track').length > 0], [true, true])

    //? the pressings failing: asked all the same (Wikipedia may still know it), the trouble said
    answers.push(() => Promise.reject(new Error('MusicBrainz away')))
    const THIRD = 'aaaaaaaa-1111-4000-8000-000000000003'
    const failing = page({ id: THIRD })
    failing.draw()
    await settle()
    failing.draw()
    check('the pressings failed: the description asked all the same', G.describeAsks.at(-1).slice(0, 2), ['album', { mbid: THIRD }])
    //? (after review) its trouble - Try again where the tracklist would be - drawn before the description could land:
    //? told it is under the top place, so a description goes to the foot, never above that button
    check('...told that what is under the top place is drawn: the trouble, its Try again', [classed('app-rg-trouble').length, G.describeAsks.at(-1)[2]], [1, true])
    globalThis.setTimeout = realTimeout
    globalThis.clearTimeout = realClear
    G.describing = { description: null, settled: true, at: null }
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main()
