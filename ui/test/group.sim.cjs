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
`)
fs.writeFileSync(path.join(OUT, 'app/useSheet.js'), `
exports.takeOpener = (event) => event.currentTarget
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
    check('"Asking MusicBrainz…", as a status, with the sweep', [text(classed('app-asking')[0]), classed('app-asking')[0]?.props.role, classed('app-sweep').length],
      ['Asking MusicBrainz…', 'status', 1])
    check('the header: title, artist, and what it is - and nothing about the library before it answers',
      [text(classed('pl-hero-title')[0]), text(classed('pl-hero-artist')[0]), text(classed('pl-hero-meta')[0])],
      ['The Slow Rush', 'Tame Impala', '2020 · Album'])
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
    check('it says MusicBrainz isn\'t answering, and offers to ask again', [text(classed('app-rg-trouble')[0]).startsWith("MusicBrainz isn't answering just now"),
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
    check('no pressings at all says so', text(classed('pl-notice')[0]), 'MusicBrainz lists no pressings of this album.')
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
      { kind: 'downloading', title: 'Already downloading', lines: ['From bob · queued', 'Open Requests to cancel it if you want another peer.'] })
    check('...in a polite live region that is always there', classed('app-rg-store')[0]?.props['aria-live'], 'polite')
    check('...UNDER Get, where an answer landing late moves nothing a finger is reaching for',
      classed('app-rg-actions')[0]?.props.children.filter(Boolean).map((child) => child.type === 'button' ? child.props.class : child.props?.class ?? child.type?.name), ['PressingPicker', 'app-rg-get', 'app-rg-store'].map((name) => name))

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

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main()
