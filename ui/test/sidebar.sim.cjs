/**
 * The desktop sidebar as it is drawn (2.1.35, app/Sidebar.tsx) - a glyph on every row, one Library group with its
 * Yours | All switch, Playlists and Manage folding away, and Settings at the foot - rendered on its own over a fake
 * Preact, as settings.sim renders You's choices. lib/appFrame.ts's rules themselves (sidebarRows, sideShown, sideFlip,
 * foldOf, foldCurrent, manageHeadLabel) are routes.sim's; this holds the component to them.
 *
 * What it pins:
 *
 *  - Every row a glyph before its words - aria-hidden, the class app-desktop.css draws at one weight - but a listed
 *    playlist's, whose name sits under All playlists' words; Settings at the foot a gear and the word "Settings"
 *    (You until 2.1.35), and "You" nowhere in the sidebar.
 *  - Logins off: no switch, and the Library's rows as they always were - Songs left out when Navidrome lists none.
 *  - A library of your own: the switch a radio group labelled by Library's heading, Yours and All, only the chosen one
 *    a tab stop; Yours' rows and All's, plainly named, the row where you are marked on either side. It shows where
 *    you are - All on the collection's views, Yours on yours - and elsewhere the side last shown, which a view of the
 *    other side moves. Turned on a view it opens the same kind of view on the other side (App's onSelect, with the
 *    pick), off one only the rows change; the arrows turn it and take the focus along.
 *  - (review) A page pushed above a view (`overView`): the side last shown, and a turn - click or arrow - opens
 *    nothing, so the album or artist stays; back down to the view, the switch follows it again.
 *  - Playlists and Manage fold: a heading button saying whether its list is open (aria-expanded) and which list
 *    (aria-controls, the list's id), the list `hidden` while folded; both open with nothing kept; a folded group with
 *    its page showing marks its heading current; a folded Manage carries Needs a look's count, said in its name.
 *  - Both choices kept on the device (deadwax-sidebar-side, deadwax-sidebar-folded) and for the page's life: a sidebar
 *    made again finds them with storage refusing; storage that throws reads as the defaults and is never fatal.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/sidebar.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-sidebar-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/Sidebar.tsx', 'src/state/persisted.ts', 'src/player/icons.tsx',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects - { type, props } - and hooks with a cursor, as settings.sim's: rendering calls the component
//? again and gets the same state; effects run after a render whose deps changed
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

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== a document that knows what has focus, and a storage that can refuse ===== */

class FakeElement {
  constructor(name) { this.name = name }
  focus() { document.activeElement = this }
}
const document = { body: new FakeElement('body'), activeElement: null }
document.activeElement = document.body
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
define('document', document)
define('HTMLElement', FakeElement)
const stored = new Map()
let refusing = false
define('localStorage', {
  getItem(key) { if (refusing) throw new Error('SecurityError'); return stored.has(key) ? stored.get(key) : null },
  setItem(key, value) { if (refusing) throw new Error('QuotaExceededError'); stored.set(key, String(value)) },
  removeItem(key) { stored.delete(key) },
})

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const persisted = require(path.join(OUT, 'state/persisted.js'))
const icons = require(path.join(OUT, 'player/icons.js'))
//? required fresh for each mount that should find nothing kept for the page's life - a new page load
const freshSidebar = () => {
  for (const key of Object.keys(require.cache)) if (key.endsWith(`${path.sep}app${path.sep}Sidebar.js`)) delete require.cache[key]
  return require(path.join(OUT, 'app/Sidebar.js')).Sidebar
}

function mount(Sidebar) {
  const render = hooks.root(Sidebar)
  const elements = new Map()
  let tree = null
  const walk = (node, where) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach((child, i) => walk(child, `${where}.${i}`)); return }
    if (typeof node.type === 'string') {
      if (!elements.has(where)) elements.set(where, new FakeElement(`${node.type} ${node.props.class ?? ''}`.trim()))
      node.element = elements.get(where)
    }
    walk(node.props?.children, `${where}/`)
  }
  const find = (test, from = tree) => {
    const hits = []
    const visit = (node) => {
      if (!node || typeof node !== 'object') return
      if (Array.isArray(node)) { node.forEach(visit); return }
      if (test(node)) hits.push(node)
      visit(node.props?.children)
    }
    visit(from)
    return hits
  }
  return {
    render(props) {
      tree = render(props)
      walk(tree, '')
      render.commit()
      return tree
    },
    find,
  }
}

//? a node's words, its children's included - a function component (a glyph) draws none
const words = (node) => {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  if (typeof node.type === 'function') return ''
  return words(node.props?.children)
}
const classOf = (node) => String(node.props?.class ?? '')
const hasClass = (node, name) => classOf(node).split(/\s+/).includes(name)

const selected = []
const base = (more = {}) => ({
  current: 'home', hasSongs: true, personal: false, arriving: 0, needsLook: null, playlists: [], currentPlaylist: null,
  onSelect(item) { selected.push(item) }, onSearch() {}, onPlaylist() {}, ...more,
})
const rowsOf = (view) => {
  const [library] = view.find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-side-library')
  return view.find((node) => node.type === 'button' && hasClass(node, 'app-side-item'), library).map((row) => [words(row), row])
}
const radios = (view) => view.find((node) => node.props?.role === 'radio')
const switchOf = (view) => view.find((node) => node.props?.role === 'radiogroup')[0]
const foldOf = (view, list) => view.find((node) => node.type === 'button' && node.props['aria-controls'] === list)[0]
const listOf = (view, id) => view.find((node) => node.type === 'ul' && node.props.id === id)[0]
//? a keydown on the switch, as a browser sends it: its currentTarget the group, whose querySelector finds a side
function keyOn(view, key) {
  let prevented = false
  const currentTarget = {
    querySelector(selector) {
      const [, side] = /\[data-side="([^"]+)"\]/.exec(selector) ?? []
      return radios(view).find((radio) => radio.props['data-side'] === side)?.element ?? null
    },
  }
  switchOf(view).props.onKeyDown({ key, currentTarget, preventDefault() { prevented = true } })
  return prevented
}

console.log('\nevery row a glyph, aria-hidden - Settings a gear at the foot, and "You" nowhere')
{
  stored.clear()
  const view = mount(freshSidebar())
  view.render(base({ personal: true, needsLook: 3, playlists: [{ id: 'p1', name: 'Road trip' }, { id: 'p2', name: 'Sunday' }] }))
  const rows = view.find((node) => node.type === 'button' && hasClass(node, 'app-side-item'))
  const glyph = (row) => view.find((node) => typeof node.type === 'function' && classOf(node) === 'app-side-icon', row)
  check('each row but a listed playlist draws one glyph of the class app-desktop.css sizes', rows.map((row) => [words(row), glyph(row).length]),
    [['Home', 1], ['Requests', 1], ['Recently added', 1], ['Albums', 1], ['Artists', 1], ['All playlists', 1], ['Road trip', 0], ['Sunday', 0],
      ['Needs a look3', 1], ['Library care', 1], ['People', 1], ['Server settings', 1], ['Event log', 1], ['Settings', 1]])
  check('...the playlists set under All playlists\' words (their own class), the glyph before the words everywhere else',
    [rows.filter((row) => hasClass(row, 'app-side-playlist')).map(words), rows.every((row) => !glyph(row).length || [row.props.children].flat(3).filter(Boolean)[0].props.class === 'app-side-icon')],
    [['Road trip', 'Sunday'], true])
  const drawn = rows.flatMap(glyph).map((node) => node.type({ class: 'app-side-icon' }))
  check('...every glyph an aria-hidden 24-unit svg, in currentColor', [...new Set(drawn.map((svg) => [svg.type, svg.props['aria-hidden'], svg.props.viewBox, svg.props.stroke].join(' ')))],
    ['svg true 0 0 24 24 currentColor'])
  const byRow = Object.fromEntries(rows.filter((row) => glyph(row).length).map((row) => [words(row).replace(/\d+$/, ''), glyph(row)[0].type]))
  check('...Home and Requests the tab bar\'s, the Library\'s the phone root\'s rows\', Manage\'s and Settings\' their own',
    [byRow.Home === icons.HomeIcon, byRow.Requests === icons.RequestsIcon, byRow['Recently added'] === icons.ClockIcon, byRow.Albums === icons.AlbumIcon,
      byRow.Artists === icons.ArtistIcon, byRow['All playlists'] === icons.PlaylistIcon, byRow['Needs a look'] === icons.FlagIcon,
      byRow['Library care'] === icons.CareIcon, byRow.People === icons.PeopleIcon, byRow['Server settings'] === icons.ServerIcon,
      byRow['Event log'] === icons.LogIcon, byRow.Settings === icons.SettingsIcon],
    Array(12).fill(true))
  check('...no two Manage rows, nor Settings and Server settings, share a glyph',
    new Set([byRow['Needs a look'], byRow['Library care'], byRow.People, byRow['Server settings'], byRow['Event log'], byRow.Settings]).size, 6)
  check('the foot: Settings, a tab button - "You" said nowhere in the sidebar', [words(rows.at(-1)), hasClass(rows.at(-1), 'app-side-you'), /\bYou\b/.test(words(view.find(() => true)[0]))],
    ['Settings', true, false])
  rows.at(-1).props.onClick()
  check('...a click is the tab\'s (`you`, its id unchanged)', selected.splice(0), ['you'])
  view.render(base({ personal: true, current: 'you' }))
  check('...current while Settings shows', view.find((node) => hasClass(node, 'app-side-you'))[0].props['aria-current'], 'page')
}

console.log('\nlogins off: no switch, the Library\'s rows as they always were')
{
  stored.clear()
  const view = mount(freshSidebar())
  view.render(base())
  check('no switch, the four views', [switchOf(view) ?? null, rowsOf(view).map(([label]) => label)], [null, ['Recently added', 'Albums', 'Artists', 'Songs']])
  view.render(base({ hasSongs: false }))
  check('...Songs left out when Navidrome lists none', rowsOf(view).map(([label]) => label), ['Recently added', 'Albums', 'Artists'])
  view.render(base({ current: 'artists' }))
  rowsOf(view)[1][1].props.onClick()
  check('...a row is its view (`albums`, the library\'s), and nothing is kept of a side', [selected.splice(0), stored.has('deadwax-sidebar-side')], [['albums'], false])
  view.render(base({ current: 'store' }))
  check('...nor kept from a collection\'s pick shown with logins off', [stored.has('deadwax-sidebar-side'), switchOf(view) ?? null], [false, null])
}

console.log('\na library of your own: the switch, Yours and All')
{
  stored.clear()
  const view = mount(freshSidebar())
  view.render(base({ personal: true }))
  const group = switchOf(view)
  const [heading] = view.find((node) => node.type === 'h2' && node.props.id === 'app-side-library')
  check('a radio group named by Library\'s heading, in it', [!!group, group.props['aria-labelledby'], words(heading)], [true, 'app-side-library', 'Library'])
  check('Yours and All, Yours chosen with nothing kept - only it a tab stop', radios(view).map((radio) => [words(radio), radio.props['aria-checked'], radio.props.tabIndex]),
    [['Yours', true, 0], ['All', false, -1]])
  check('Yours\' rows, plainly named', rowsOf(view).map(([label]) => label), ['Recently added', 'Albums', 'Artists'])

  view.render(base({ personal: true, current: 'store' }))
  check('on a page of the collection\'s: All shown, its rows - plainly named, Songs among them',
    [radios(view).map((radio) => radio.props['aria-checked']), rowsOf(view).map(([label]) => label)], [[false, true], ['Albums', 'Artists', 'Songs']])
  check('...and kept as the side shown', stored.get('deadwax-sidebar-side'), 'all')
  //? (review) which row is current, on each side: the marked Albums is All's (a click on it is `store`), no row of
  //? yours is drawn to be marked
  const marks = (view) => rowsOf(view).map(([label, row]) => [label, row.props['aria-current'] ?? null])
  const markedItem = (view) => { rowsOf(view).find(([, row]) => row.props['aria-current'])?.[1].props.onClick(); return selected.splice(0) }
  check('...All\'s Albums the row marked where you are, and it alone - All\'s own (`store`), no row of yours among them',
    [marks(view), markedItem(view), rowsOf(view).some(([label]) => label === 'Recently added')],
    [[['Albums', 'page'], ['Artists', null], ['Songs', null]], ['store'], false])
  view.render(base({ personal: true, current: 'albums' }))
  check('...on your Albums, Yours\' Albums marked - yours (`albums`), no row of the collection\'s among them',
    [marks(view), markedItem(view), rowsOf(view).some(([label]) => label === 'Songs')],
    [[['Recently added', null], ['Albums', 'page'], ['Artists', null]], ['albums'], false])
  view.render(base({ personal: true, current: 'store' }))
  rowsOf(view)[2][1].props.onClick()
  check('...All\'s rows are the collection\'s views', selected.splice(0), ['songs'])
  view.render(base({ personal: true, current: 'store', hasSongs: false }))
  check('...Songs left out when Navidrome lists none', rowsOf(view).map(([label]) => label), ['Albums', 'Artists'])

  view.render(base({ personal: true, current: 'home' }))
  check('Home after the collection\'s page: All still shown - the side last shown', [radios(view).map((radio) => radio.props['aria-checked']), rowsOf(view).map(([label]) => label)],
    [[false, true], ['Albums', 'Artists', 'Songs']])
  radios(view)[0].props.onClick()
  view.render(base({ personal: true, current: 'home' }))
  check('turned to Yours off the Library: only the rows change - nothing opened - and Yours kept',
    [selected.splice(0), radios(view).map((radio) => radio.props['aria-checked']), rowsOf(view).map(([label]) => label), stored.get('deadwax-sidebar-side')],
    [[], [true, false], ['Recently added', 'Albums', 'Artists'], 'yours'])
  radios(view)[0].props.onClick()
  check('...the side already shown, turned to again: nothing', selected.splice(0), [])

  view.render(base({ personal: true, current: 'artists' }))
  radios(view)[1].props.onClick()
  check('turned to All on your Artists: All\'s Artists opened', [selected.splice(0), stored.get('deadwax-sidebar-side')], [['storeArtists'], 'all'])
  view.render(base({ personal: true, current: 'storeArtists' }))
  check('...and shown there', radios(view).map((radio) => radio.props['aria-checked']), [false, true])
  radios(view)[0].props.onClick()
  check('...back to Yours: your Artists', selected.splice(0), ['artists'])
  view.render(base({ personal: true, current: 'recent' }))
  radios(view)[1].props.onClick()
  check('Recently added turned to All: the collection\'s Albums', selected.splice(0), ['store'])
  view.render(base({ personal: true, current: 'songs' }))
  radios(view)[0].props.onClick()
  check('Songs turned to Yours: your Albums', selected.splice(0), ['albums'])

  //? a turn whose view hasn't opened yet (App's state not drawn back) never reads as the old side shown: a render with
  //? the old view still current doesn't write that view's side back over the side turned to
  view.render(base({ personal: true, current: 'albums' }))
  radios(view)[1].props.onClick()
  view.render(base({ personal: true, current: 'albums' }))
  check('a turn whose view is still opening: the view across asked for, the side kept the one turned to (not written back)',
    [selected.splice(0), stored.get('deadwax-sidebar-side')], [['store'], 'all'])
  view.render(base({ personal: true, current: 'store' }))
  check('...and once App draws that view, All shown with its Albums marked - still kept as All',
    [radios(view).map((radio) => radio.props['aria-checked']), marks(view), stored.get('deadwax-sidebar-side')],
    [[false, true], [['Albums', 'page'], ['Artists', null], ['Songs', null]], 'all'])

  view.render(base({ personal: true, current: 'albums' }))
  document.activeElement = document.body
  const prevented = keyOn(view, 'ArrowRight')
  check('the arrows turn it, open the page across, and take the focus to the side chosen',
    [prevented, selected.splice(0), document.activeElement === radios(view).find((radio) => radio.props['data-side'] === 'all').element], [true, ['store'], true])
  view.render(base({ personal: true, current: 'store' }))
  keyOn(view, 'ArrowLeft')
  check('...either way round', selected.splice(0), ['albums'])
  check('...and any other key is left alone', [keyOn(view, 'Enter'), keyOn(view, 'a'), selected.splice(0)], [false, false, []])
}

console.log('\na page pushed above a Library view (review of 2.1.35): the side last shown, and a turn opens nothing')
{
  //? All albums -> Homogenic -> Yours popped the album to open your Albums; App passes overView (overLibraryView)
  stored.clear()
  const view = mount(freshSidebar())
  view.render(base({ personal: true, current: 'store' }))
  view.render(base({ personal: true, current: 'store', overView: true }))
  check('an album opened from All albums: All still shown (the side last shown), the view under it still marked',
    [radios(view).map((radio) => radio.props['aria-checked']), rowsOf(view).map(([label, row]) => [label, row.props['aria-current'] ?? null]), stored.get('deadwax-sidebar-side')],
    [[false, true], [['Albums', 'page'], ['Artists', null], ['Songs', null]], 'all'])
  radios(view)[0].props.onClick()
  view.render(base({ personal: true, current: 'store', overView: true }))
  check('...turned to Yours there: nothing opened - the album stays - only the rows change, and Yours is kept',
    [selected.splice(0), radios(view).map((radio) => radio.props['aria-checked']), rowsOf(view).map(([label]) => label), stored.get('deadwax-sidebar-side')],
    [[], [true, false], ['Recently added', 'Albums', 'Artists'], 'yours'])
  check('...none of Yours\' rows marked: the view under the album is All\'s', rowsOf(view).filter(([, row]) => row.props['aria-current']).length, 0)
  document.activeElement = document.body
  const prevented = keyOn(view, 'ArrowRight')
  view.render(base({ personal: true, current: 'store', overView: true }))
  check('...the arrows the same: the choice and the focus move, nothing opens',
    [prevented, selected.splice(0), stored.get('deadwax-sidebar-side'), document.activeElement === radios(view).find((radio) => radio.props['data-side'] === 'all').element],
    [true, [], 'all', true])
  radios(view)[0].props.onClick()
  view.render(base({ personal: true, current: 'store', overView: false }))
  check('back down to All albums: the switch follows the view again - All, and kept so', [radios(view).map((radio) => radio.props['aria-checked']), stored.get('deadwax-sidebar-side')],
    [[false, true], 'all'])

  //? a cold link to an album over your Albums, with All kept: the side kept shown, nothing written over it
  stored.set('deadwax-sidebar-side', 'all')
  const cold = mount(freshSidebar())
  cold.render(base({ personal: true, current: 'albums', overView: true }))
  check('an album over your Albums opened cold, All kept: All shown, All still kept', [radios(cold).map((radio) => radio.props['aria-checked']), stored.get('deadwax-sidebar-side')],
    [[false, true], 'all'])
  radios(cold)[0].props.onClick()
  check('...turned to Yours: nothing opened', [selected.splice(0), stored.get('deadwax-sidebar-side')], [[], 'yours'])
}

console.log('\nPlaylists and Manage fold away')
{
  stored.clear()
  const view = mount(freshSidebar())
  const props = (more) => base({ personal: true, needsLook: 3, playlists: [{ id: 'p1', name: 'Road trip' }], ...more })
  view.render(props())
  const heads = () => ['app-side-playlists-list', 'app-side-managing-list'].map((list) => foldOf(view, list))
  check('both open with nothing kept: a button each, saying so, controlling its list', heads().map((head) => [head.props['aria-expanded'], head.props['aria-controls']]),
    [[true, 'app-side-playlists-list'], [true, 'app-side-managing-list']])
  check('...each inside its heading, its words the group\'s name (what the section is labelled by)',
    heads().map((head) => [view.find((node) => node.type === 'h2' && view.find((inner) => inner === head, node).length)[0] !== undefined, view.find((node) => node.type === 'span' && node.props.id, head)[0].props.id, words(head).replace(/\d+$/, '')]),
    [[true, 'app-side-playlists', 'Playlists'], [true, 'app-side-managing', 'Manage']])
  check('...the lists there, not hidden', ['app-side-playlists-list', 'app-side-managing-list'].map((id) => listOf(view, id).props.hidden), [false, false])
  check('...open, Manage\'s heading carries no count and only its name', [view.find((node) => hasClass(node, 'app-side-badge'), heads()[1]).length, heads()[1].props['aria-label'] ?? null], [0, null])

  heads()[0].props.onClick()
  view.render(props())
  check('Playlists folded: its list hidden, the button says so, kept', [listOf(view, 'app-side-playlists-list').props.hidden, heads()[0].props['aria-expanded'], stored.get('deadwax-sidebar-folded')],
    [true, false, 'playlists'])
  check('...Library, Home and Requests have no fold', view.find((node) => node.props?.['aria-expanded'] !== undefined).length, 2)
  view.render(props({ current: 'playlists', currentPlaylist: 'p1' }))
  check('...with a playlist\'s page showing, its heading is current', [hasClass(heads()[0], 'is-current'), heads()[0].props['aria-current']], [true, 'true'])
  view.render(props({ current: 'home' }))
  check('...elsewhere it isn\'t', [hasClass(heads()[0], 'is-current'), heads()[0].props['aria-current'] ?? null], [false, null])

  heads()[1].props.onClick()
  view.render(props({ current: 'settings' }))
  check('Manage folded: hidden, kept with Playlists', [listOf(view, 'app-side-managing-list').props.hidden, stored.get('deadwax-sidebar-folded')], [true, 'playlists,manage'])
  check('...Server settings showing marks its heading current', [hasClass(heads()[1], 'is-current'), heads()[1].props['aria-current']], [true, 'true'])
  check('...and the heading carries Needs a look\'s count, said in its name', [words(view.find((node) => hasClass(node, 'app-side-badge'), heads()[1])[0]), heads()[1].props['aria-label']],
    ['3', 'Manage, 3 albums need a look'])
  view.render(props({ needsLook: null }))
  check('...no count while it isn\'t known - never a 0 over an unknown', [view.find((node) => hasClass(node, 'app-side-badge'), heads()[1]).length, heads()[1].props['aria-label'] ?? null], [0, null])
  view.render(props({ managing: { any: true, queue: false, care: true, people: false, settings: true, log: true } }))
  check('...nor for someone without Needs a look', view.find((node) => hasClass(node, 'app-side-badge'), heads()[1]).length, 0)

  heads()[0].props.onClick()
  heads()[1].props.onClick()
  view.render(props())
  check('both opened again: shown, kept as none', [heads().map((head) => head.props['aria-expanded']), stored.get('deadwax-sidebar-folded')], [[true, true], ''])
}

console.log('\nboth choices kept: on the device, and for the page\'s life without it')
{
  stored.clear()
  check('the keys', [persisted.STORAGE_KEYS.sidebarSide, persisted.STORAGE_KEYS.sidebarFolded], ['deadwax-sidebar-side', 'deadwax-sidebar-folded'])
  check('nothing kept: Yours, both open', [persisted.readSidebarSide(), persisted.readSidebarFolds()], ['yours', { playlists: false, manage: false }])
  const sideReads = ['all', 'yours', 'All', ' all', '', 'store'].map((value) => { stored.set('deadwax-sidebar-side', value); return persisted.readSidebarSide() })
  check('All only when it says exactly that', sideReads, ['all', 'yours', 'yours', 'yours', 'yours', 'yours'])
  const foldReads = ['manage', 'playlists,manage', 'manage, playlists', 'junk', ''].map((value) => { stored.set('deadwax-sidebar-folded', value); return persisted.readSidebarFolds() })
  check('the folds by name, any other word no group', foldReads.map((folds) => [folds.playlists, folds.manage]), [[false, true], [true, true], [true, true], [false, false], [false, false]])

  stored.clear()
  stored.set('deadwax-sidebar-side', 'all')
  stored.set('deadwax-sidebar-folded', 'manage')
  const view = mount(freshSidebar())
  view.render(base({ personal: true }))
  check('a page load reads them: All\'s rows, Manage folded', [radios(view).map((radio) => radio.props['aria-checked']), listOf(view, 'app-side-managing-list').props.hidden],
    [[false, true], true])

  refusing = true
  let threw = false
  try { radios(view)[0].props.onClick(); foldOf(view, 'app-side-playlists-list').props.onClick() } catch { threw = true }
  view.render(base({ personal: true }))
  check('storage refusing: the choices still take, nothing thrown', [threw, radios(view).map((radio) => radio.props['aria-checked']), listOf(view, 'app-side-playlists-list').props.hidden],
    [false, [true, false], true])
  const again = mount(require(path.join(OUT, 'app/Sidebar.js')).Sidebar)
  again.render(base({ personal: true }))
  check('...and a sidebar made again (the window across 1024px and back) finds them, storage or none',
    [radios(again).map((radio) => radio.props['aria-checked']), listOf(again, 'app-side-playlists-list').props.hidden, listOf(again, 'app-side-managing-list').props.hidden],
    [[true, false], true, true])
  const fresh = mount(freshSidebar())
  fresh.render(base({ personal: true }))
  check('...a new page with storage refusing: the defaults - Yours, both open', [radios(fresh).map((radio) => radio.props['aria-checked']), listOf(fresh, 'app-side-playlists-list').props.hidden,
    listOf(fresh, 'app-side-managing-list').props.hidden], [[true, false], false, false])
  refusing = false
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
