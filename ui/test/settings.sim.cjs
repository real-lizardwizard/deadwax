/**
 * The player's settings sheet (player/Settings.tsx) and the button that opens it (player/Library.tsx),
 * the components themselves, compiled with the repo's TypeScript and rendered by a small stand-in for
 * Preact into plain objects, with a document that knows which element has focus.
 *
 * What it pins:
 *
 *  - Focus goes back to the Settings button when the sheet closes, in WebKit too. WebKit - Safari, and
 *    every browser on an iPhone - doesn't focus a button that is clicked or tapped
 *    (HTMLFormControlElement::isMouseFocusable()), and the sheet gives focus back to whatever had it as
 *    it opened: so the button has to take focus itself before it opens the sheet, or focus falls to
 *    the page. A click here is WebKit's: it focuses nothing by itself.
 *  - The "Maximum quality" notes say only what the code does: resampling is of FLAC songs at 88.2 to
 *    384 kHz, it is as much quieter as src/resample.py's HEADROOM_DB says, and a song plays without a
 *    gap only with the Gapless switch on - named by the switch's own label in NowPlaying.tsx.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/settings.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const REPO = path.resolve(UI, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-settings-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/player/Settings.tsx', 'src/player/Library.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects - { type, props } - and hooks with a cursor, as Preact's are: rendering calls
//? the component again and gets the same state. Effects run after a render whose deps changed, the
//? last one's cleanup first.
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
  //? the commit: effects whose deps changed, once the refs are set
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

/* ===== a document that knows what has focus ===== */

class FakeElement {
  constructor(name) {
    this.name = name
    this.classes = new Set()
    this.classList = { toggle: (c, on) => (on ? this.classes.add(c) : this.classes.delete(c)) }
  }
  //? focus moves only when asked for - a click doesn't, as in WebKit
  focus() { document.activeElement = this }
  querySelector() { return null }
  querySelectorAll() { return [] }
}
const listeners = new Map()
const document = {
  body: new FakeElement('body'),
  documentElement: new FakeElement('html'),
  activeElement: null,
  addEventListener: (name, fn) => listeners.set(name, [...(listeners.get(name) ?? []), fn]),
  removeEventListener: (name, fn) => listeners.set(name, (listeners.get(name) ?? []).filter((f) => f !== fn)),
}
document.activeElement = document.body
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
define('document', document)
define('HTMLElement', FakeElement)
define('localStorage', { getItem: () => null, setItem: () => {}, removeItem: () => {} })
//? the library's first page is asked for and never answers: nothing here is about the albums
define('fetch', () => new Promise(() => {}))
define('IntersectionObserver', class { observe() {} unobserve() {} disconnect() {} })

/* ===== rendering ===== */

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { Settings, QUALITIES } = require(path.join(OUT, 'player/Settings.js'))
const { Library } = require(path.join(OUT, 'player/Library.js'))

//? each element of a tree, found by where it sits, keeps one FakeElement across renders; a ref names it
function mount(component, name) {
  const render = hooks.root(component)
  const elements = new Map()
  let tree = null
  const walk = (node, where) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach((child, i) => walk(child, `${where}.${i}`)); return }
    if (typeof node.type === 'string') {
      if (!elements.has(where)) elements.set(where, new FakeElement(`${name} ${node.type} ${node.props.class ?? ''}`.trim()))
      node.element = elements.get(where)
      if (node.props.ref) node.props.ref.current = node.element
    }
    walk(node.props?.children, `${where}/`)
  }
  return {
    render(props) {
      tree = render(props)
      walk(tree, '')
      render.commit()
      return tree
    },
    find(test) {
      const hits = []
      const visit = (node) => {
        if (!node || typeof node !== 'object') return
        if (Array.isArray(node)) { node.forEach(visit); return }
        if (test(node)) hits.push(node)
        visit(node.props?.children)
      }
      visit(tree)
      return hits
    },
  }
}

/* ===== the checks ===== */

console.log('\nfocus goes back to the Settings button, in WebKit too')
{
  const player = { maxRate: '48000', setMaxRate(rate) { this.maxRate = rate } }
  let open = false
  const settings = mount(Settings, 'settings')
  const library = mount(Library, 'library')
  const renderSettings = () => settings.render({ player, open, onClose: () => { open = false } })
  let focusedAtOpen = null
  library.render({ onOpen: () => {}, onSettings: () => { focusedAtOpen = document.activeElement; open = true } })
  renderSettings()
  const [gear] = library.find((node) => node.type === 'button' && node.props['aria-label'] === 'Settings')
  check('the library\'s header has the Settings button', !!gear, true)
  check('nothing focused yet', document.activeElement.name, 'body')
  //? a tap: WebKit dispatches the click and focuses nothing
  gear.props.onClick({ currentTarget: gear.element, preventDefault() {} })
  check('a tap on it: the button has focus before the sheet is asked to open', focusedAtOpen === gear.element, true)
  renderSettings()
  check('the sheet open, and focus in it', [open, document.activeElement.name], [true, 'settings div pl-settings-sheet'])
  const [done] = settings.find((node) => node.type === 'button' && node.props.class === 'pl-settings-done')
  done.props.onClick()
  renderSettings()
  check('Done: the sheet closed, and focus back on the Settings button', [open, document.activeElement === gear.element], [false, true])

  gear.props.onClick({ currentTarget: gear.element, preventDefault() {} })
  renderSettings()
  for (const fn of listeners.get('keydown') ?? []) fn({ key: 'Escape' })
  renderSettings()
  check('Escape: closed, and focus back on the button again', [open, document.activeElement === gear.element], [false, true])

  document.activeElement = document.body
  gear.props.onClick({ currentTarget: gear.element, preventDefault() {} })
  renderSettings()
  const [backdrop] = settings.find((node) => node.type === 'div' && node.props.class === 'pl-settings-backdrop')
  backdrop.props.onClick()
  renderSettings()
  check('a tap outside: closed, and focus back on the button', [open, document.activeElement === gear.element], [false, true])
}

console.log('\nthe "Maximum quality" notes say what the code does')
{
  const resample = fs.readFileSync(path.join(REPO, 'src/resample.py'), 'utf8')
  const headroom = Number(/^HEADROOM_DB\s*=\s*([\d.]+)/m.exec(resample)?.[1])
  const nowPlaying = fs.readFileSync(path.join(UI, 'src/player/NowPlaying.tsx'), 'utf8')
  const switchLabel = /class="pl-gapless-label">([^<]+)</.exec(nowPlaying)?.[1]
  const [up, original] = QUALITIES
  check('two choices, 48 kHz first', QUALITIES.map((q) => [q.rate, q.label]), [['48000', 'Up to 48 kHz'], ['original', 'Original']])
  check('"Up to 48 kHz", word for word',
    up.note,
    'FLAC songs at 88.2 to 384 kHz are resampled by deadwax to 48 kHz, or 44.1 kHz, and sent as lossless 24-bit FLAC, ' +
    'so with the Gapless switch on they play without a gap. Nothing below 20 kHz changes, except that they are 3 dB ' +
    'quieter, so nothing can clip.')
  check('"Original", word for word',
    original.note,
    'Songs above 48 kHz are sent as they are. With the Gapless switch on, FLAC songs play without a gap too, but an ' +
    'iPhone can only hold a few seconds of them ahead, so a weak connection can make them stall. The iPhone converts ' +
    'them to 44.1 or 48 kHz itself, unless a USB DAC takes them at their own rate.')
  check('as much quieter as the server lowers them (HEADROOM_DB in src/resample.py)',
    [Number.isFinite(headroom), new RegExp(`\\b${headroom} dB quieter\\b`).test(up.note)], [true, true])
  check('the switch named by its own label, in both', [switchLabel, QUALITIES.every((q) => q.note.includes(`the ${switchLabel} switch on`))], ['Gapless', true])
  const emDash = String.fromCharCode(0x2014)
  check('no em dashes, and deadwax never sentence-cased', QUALITIES.some((q) => q.note.includes(emDash) || q.note.includes('Deadwax')), false)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
