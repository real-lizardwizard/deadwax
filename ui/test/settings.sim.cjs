/**
 * You > Playback in the app: "Maximum quality" (app/QualityChoice.tsx, 2.0.0-player.9 - it was the
 * player's settings sheet, player/Settings.tsx, opened by a gear beside the Library title, until
 * the tabs), "Gapless" (app/GaplessChoice.tsx, 2.0.0-player.10 - it was a switch on the
 * now-playing screen until then), "Now Playing opens as" (app/LookChoice.tsx, 2.0.0-player.11:
 * the cover or the turntable) and "Pause winds the record down" (app/WindDownChoice.tsx,
 * 2.0.0-player.14: the turntable's pause). The components themselves, compiled with the repo's TypeScript
 * and rendered by a small stand-in for Preact into plain objects, with a document that knows which
 * element has focus.
 *
 * What it pins:
 *
 *  - The notes say only what the code does: resampling is of FLAC songs at 88.2 to 384 kHz, it is
 *    as much quieter as src/resample.py's HEADROOM_DB says, and a song plays without a gap only with
 *    Gapless on - named by the checkbox's own label in GaplessChoice.tsx, and never called a
 *    switch now that it isn't one. Word for word.
 *  - It is a radio group as it was: a tap picks; the arrows move the choice and the focus with it,
 *    round the group; only the chosen radio is a tab stop; other keys are left alone.
 *  - Gapless is a checkbox, and ITS TAP CALLS THE PLAYER IN THE SAME TURN: setGapless has been
 *    called by the time the click handler returns (that tap unlocks the second audio element on
 *    iOS), with the opposite of what it was.
 *  - "Now Playing opens as" is a radio group the same way - Cover, then Turntable - and is kept on
 *    its own key, per device, read back as the turntable only when it says exactly that: anything
 *    else, or storage that can't be read, is the cover.
 *  - "Pause winds the record down" is a checkbox, on by default, kept on its own key, per device,
 *    read back as off only when it says exactly that; its tap tells App, and calls no player action.
 *  - Where they live now: You's Playback section - Gapless, then Now Playing opens as, then Pause
 *    winds the record down beside it, then Maximum quality - each on the storage key it always had,
 *    per device; the gear, the sheet and the switch are gone.
 *  - "Confirm before cancelling" (app/ConfirmCancelChoice.tsx, 2.0.0-player.41) is a checkbox in You >
 *    Getting albums, on by default, kept on its own key, per device - carried over ONCE from the main
 *    page's own setting in this browser (deadwax-preferences' confirmCancel): off if that said off,
 *    else marked 'default', which reads as on and stores no choice; never read from the main page
 *    again. Requests reads it at the ✕'s tap; its own tap tells You, and calls no player action.
 *  - "Normalization" (app/NormalizationChoice.tsx, 2.0.0-player.62) is a radio group the same way - Automatic,
 *    By song, By album, Off, word for word - its state its own, kept on its own key, per device, read back as
 *    one of the other three only when it says exactly that: anything else, nothing stored, or storage that
 *    can't be read is Automatic. It calls nothing of the player. Maximum quality's note says its 3 dB is with
 *    Normalization off.
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
  'src/app/QualityChoice.tsx', 'src/app/GaplessChoice.tsx', 'src/app/LookChoice.tsx', 'src/app/WindDownChoice.tsx', 'src/app/ConfirmCancelChoice.tsx', 'src/state/persisted.ts',
  'src/app/NormalizationChoice.tsx',
  '--rootDir', 'src', '--outDir', OUT,
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
//? a storage that can be told what it holds, and to refuse, as a private window's does
const stored = new Map()
let refusing = false
define('localStorage', {
  getItem(key) { if (refusing) throw new Error('SecurityError'); return stored.has(key) ? stored.get(key) : null },
  setItem(key, value) { if (refusing) throw new Error('QuotaExceededError'); stored.set(key, String(value)) },
  removeItem(key) { stored.delete(key) },
})

/* ===== rendering ===== */

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { QualityChoice, QUALITIES } = require(path.join(OUT, 'app/QualityChoice.js'))
const { GaplessChoice } = require(path.join(OUT, 'app/GaplessChoice.js'))
const { LookChoice, LOOKS } = require(path.join(OUT, 'app/LookChoice.js'))
const { WindDownChoice } = require(path.join(OUT, 'app/WindDownChoice.js'))
const { ConfirmCancelChoice } = require(path.join(OUT, 'app/ConfirmCancelChoice.js'))
const { NormalizationChoice, NORMALIZATIONS } = require(path.join(OUT, 'app/NormalizationChoice.js'))
const persisted = require(path.join(OUT, 'state/persisted.js'))

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

//? a keydown on the group, as the browser sends it: its currentTarget is the group's element, whose
//? querySelector finds the radio of that data-rate in the tree as rendered
function keyOn(view, group, key) {
  let prevented = false
  const currentTarget = {
    querySelector(selector) {
      const [, name, value] = /\[(data-rate|data-look|data-level)="([^"]+)"\]/.exec(selector) ?? []
      const [radio] = view.find((node) => node.props?.role === 'radio' && node.props[name] === value)
      return radio?.element ?? null
    },
  }
  group.props.onKeyDown({ key, currentTarget, preventDefault() { prevented = true } })
  return prevented
}

console.log('\n"Maximum quality" is a radio group, keys and all')
{
  const player = { maxRate: '48000', setMaxRate(rate) { this.maxRate = rate } }
  const view = mount(QualityChoice, 'quality')
  const render = () => view.render({ player })
  render()
  const [group] = view.find((node) => node.props?.role === 'radiogroup')
  const [title] = view.find((node) => node.type === 'h3')
  const radios = () => view.find((node) => node.props?.role === 'radio')
  check('a radio group labelled by its heading', [!!group, group?.props['aria-labelledby'] === title?.props.id, title?.props.children], [true, true, 'Maximum quality'])
  check('two radios, 48 kHz chosen', radios().map((r) => [r.props['data-rate'], r.props['aria-checked']]), [['48000', true], ['original', false]])
  check('only the chosen one is a tab stop', radios().map((r) => r.props.tabIndex), [0, -1])

  radios()[1].props.onClick()
  render()
  check('a tap on Original picks it', [player.maxRate, radios().map((r) => r.props['aria-checked'])], ['original', [false, true]])
  check('...and the tab stop moves with it', radios().map((r) => r.props.tabIndex), [-1, 0])

  document.activeElement = document.body
  let prevented = keyOn(view, group, 'ArrowDown')
  render()
  check('ArrowDown from the last wraps to the first', [prevented, player.maxRate], [true, '48000'])
  check('...and takes the focus with it', document.activeElement === radios()[0].element, true)
  prevented = keyOn(view, group, 'ArrowUp')
  render()
  check('ArrowUp wraps back', [prevented, player.maxRate, document.activeElement === radios()[1].element], [true, 'original', true])
  keyOn(view, group, 'ArrowRight')
  render()
  check('ArrowRight moves on', player.maxRate, '48000')
  keyOn(view, group, 'ArrowLeft')
  render()
  check('ArrowLeft moves back', player.maxRate, 'original')
  const focused = document.activeElement
  prevented = keyOn(view, group, 'a')
  render()
  check('any other key is left alone', [prevented, player.maxRate, document.activeElement === focused], [false, 'original', true])
}

//? what an element says: its own words, not those of a component inside it (none is drawn here)
function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  return typeof node.type === 'string' ? words(node.props?.children) : ''
}
const hasClass = (node, name) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)

console.log('\n"Gapless" is a checkbox, and its tap calls the player in the same turn')
{
  const calls = []
  const player = { gapless: false, setGapless(on) { calls.push(on); this.gapless = on } }
  const view = mount(GaplessChoice, 'gapless')
  const render = () => view.render({ player })
  render()
  const box = () => view.find((node) => node.props?.role === 'checkbox')[0]
  const drawn = () => view.find((node) => hasClass(node, 'app-checkbox'))[0]
  check('one checkbox, a button, off to begin with', [view.find((node) => node.props?.role === 'checkbox').length, box()?.type, box()?.props['aria-checked']], [1, 'button', false])
  check('no switch anywhere in it', view.find((node) => node.props?.role === 'switch').length, 0)
  check('it says "Gapless"', words(box()), 'Gapless')
  check('the box is drawn empty', hasClass(drawn(), 'is-on'), false)

  const returned = box().props.onClick()
  check('a tap has called setGapless(true) by the time the click returns', [calls, returned === undefined], [[true], true])
  render()
  check('...and it is drawn ticked', [box().props['aria-checked'], hasClass(drawn(), 'is-on')], [true, true])
  box().props.onClick()
  render()
  check('a second tap turns it off, in the tap again', [calls, box().props['aria-checked']], [[true, false], false])
  check('a click is the only thing it listens for', Object.keys(box().props).filter((name) => /^on[A-Z]/.test(name)), ['onClick'])
}

console.log('\n"Now Playing opens as" is a radio group too, kept on its own key')
{
  let look = 'cover'
  const chosen = []
  const view = mount(LookChoice, 'look')
  const render = () => view.render({ look, onChange: (next) => { chosen.push(next); look = next } })
  render()
  //? found afresh after each render: the group's keys go by the look it was drawn with
  const group = () => view.find((node) => node.props?.role === 'radiogroup')[0]
  const [title] = view.find((node) => node.type === 'h3')
  const radios = () => view.find((node) => node.props?.role === 'radio')
  check('a radio group labelled by its heading', [!!group(), group()?.props['aria-labelledby'] === title?.props.id, title?.props.children], [true, true, 'Now Playing opens as'])
  check('...and described by the note under it in You, as Gapless is by its own', group()?.props['aria-describedby'], 'app-look-note')
  check('Cover, then Turntable, the cover chosen', radios().map((r) => [words(r), r.props['aria-checked'], r.props.tabIndex]), [['Cover', true, 0], ['Turntable', false, -1]])
  check('...the words the looks are named by', LOOKS.map((l) => [l.look, l.label]), [['cover', 'Cover'], ['turntable', 'Turntable']])
  radios()[1].props.onClick()
  render()
  check('a tap on Turntable picks it, and the tab stop moves with it', [chosen, radios().map((r) => [r.props['aria-checked'], r.props.tabIndex])], [['turntable'], [[false, -1], [true, 0]]])
  document.activeElement = document.body
  let prevented = keyOn(view, group(), 'ArrowDown')
  render()
  check('ArrowDown from the last wraps to the first, taking the focus', [prevented, look, document.activeElement === radios()[0].element], [true, 'cover', true])
  prevented = keyOn(view, group(), 'ArrowLeft')
  render()
  check('ArrowLeft wraps back', [prevented, look, document.activeElement === radios()[1].element], [true, 'turntable', true])
  check('any other key is left alone', [keyOn(view, group(), 'Enter'), look], [false, 'turntable'])

  check('its key, per device', persisted.STORAGE_KEYS.playerOpensAs, 'deadwax-player-opens-as')
  stored.clear()
  check('nothing kept: the cover, as Now Playing always was', persisted.readPlayerOpensAs(), 'cover')
  persisted.writePlayerOpensAs('turntable')
  check('kept, and read back', [stored.get('deadwax-player-opens-as'), persisted.readPlayerOpensAs()], ['turntable', 'turntable'])
  persisted.writePlayerOpensAs('cover')
  check('...both ways', [stored.get('deadwax-player-opens-as'), persisted.readPlayerOpensAs()], ['cover', 'cover'])
  const readsAs = (value) => { stored.set('deadwax-player-opens-as', value); return persisted.readPlayerOpensAs() }
  check('the turntable only when it says exactly that', ['Turntable', 'turntable ', 'vinyl', '', '"turntable"'].map(readsAs), ['cover', 'cover', 'cover', 'cover', 'cover'])
  refusing = true
  let threw = false
  try { persisted.writePlayerOpensAs('turntable') } catch { threw = true }
  check('storage refused: the cover, and nothing thrown either way', [persisted.readPlayerOpensAs(), threw], ['cover', false])
  refusing = false
}

console.log('\n"Pause winds the record down" is a checkbox, on until turned off, kept on its own key')
{
  let on = true
  const chosen = []
  const view = mount(WindDownChoice, 'wind down')
  const render = () => view.render({ on, onChange: (next) => { chosen.push(next); on = next } })
  render()
  const box = () => view.find((node) => node.props?.role === 'checkbox')[0]
  const drawn = () => view.find((node) => hasClass(node, 'app-checkbox'))[0]
  check('a checkbox, not a switch, named for what it does, described by its note in You',
    [box()?.type, words(box()), box()?.props['aria-describedby'], view.find((node) => node.props?.role === 'switch').length],
    ['button', 'Pause winds the record down', 'app-wind-down-note', 0])
  check('on, as it ships: ticked', [box().props['aria-checked'], hasClass(drawn(), 'is-on')], [true, true])
  box().props.onClick()
  render()
  check('a tap turns it off - App is told, in the tap', [chosen, box().props['aria-checked'], hasClass(drawn(), 'is-on')], [[false], false, false])
  box().props.onClick()
  render()
  check('...and back on', [chosen, box().props['aria-checked']], [[false, true], true])
  check('a click is the only thing it listens for', Object.keys(box().props).filter((name) => /^on[A-Z]/.test(name)), ['onClick'])

  check('its key, per device', persisted.STORAGE_KEYS.playerWindDown, 'deadwax-player-wind-down')
  stored.clear()
  check('nothing kept: on, as it ships', persisted.readPlayerWindDown(), true)
  persisted.writePlayerWindDown(false)
  check('turned off, kept, and read back', [stored.get('deadwax-player-wind-down'), persisted.readPlayerWindDown()], ['off', false])
  persisted.writePlayerWindDown(true)
  check('...and on', [stored.get('deadwax-player-wind-down'), persisted.readPlayerWindDown()], ['on', true])
  const readsAs = (value) => { stored.set('deadwax-player-wind-down', value); return persisted.readPlayerWindDown() }
  check('off only when it says exactly that: anything else is on', ['off', 'Off', 'false', '0', '', 'no', ' off'].map(readsAs), [false, true, true, true, true, true, true])
  refusing = true
  let threw = false
  try { persisted.writePlayerWindDown(false) } catch { threw = true }
  check('storage refused: on, and nothing thrown either way', [persisted.readPlayerWindDown(), threw], [true, false])
  refusing = false
}

console.log('\n"Confirm before cancelling" (2.0.0-player.41): a checkbox, on by default, this device\'s, carried over once')
{
  let on = true
  const chosen = []
  const view = mount(ConfirmCancelChoice, 'confirm cancel')
  const render = () => view.render({ on, onChange: (next) => { chosen.push(next); on = next } })
  render()
  const box = () => view.find((node) => node.props?.role === 'checkbox')[0]
  const drawn = () => view.find((node) => hasClass(node, 'app-checkbox'))[0]
  check('a checkbox named as the main page names it, described by its note in You',
    [box()?.type, words(box()), box()?.props['aria-describedby'], box()?.props['aria-checked']],
    ['button', 'Confirm before cancelling', 'app-confirm-cancel-note', true])
  check('on, as it ships: ticked', hasClass(drawn(), 'is-on'), true)
  box().props.onClick()
  render()
  check('a tap turns it off - You is told, in the tap - and the tick goes', [chosen, box().props['aria-checked'], hasClass(drawn(), 'is-on')], [[false], false, false])
  box().props.onClick()
  render()
  //? (review) a box that could only ever be turned off, or never drew its tick, passed before this
  check('...and back on, ticked again', [chosen, box().props['aria-checked'], hasClass(drawn(), 'is-on')], [[false, true], true, true])
  check('a click is the only thing it listens for', Object.keys(box().props).filter((name) => /^on[A-Z]/.test(name)), ['onClick'])

  check('its key, per device', persisted.STORAGE_KEYS.playerConfirmCancel, 'deadwax-player-confirm-cancel')
  stored.clear()
  check('nothing kept here or on the main page: on - marked carried over as the default, no choice stored',
    [persisted.readConfirmCancel(), stored.get('deadwax-player-confirm-cancel')], [true, 'default'])
  stored.set('deadwax-preferences', JSON.stringify({ confirmCancel: false }))
  check('...and the main page turned off since is never read again', persisted.readConfirmCancel(), true)
  stored.clear()
  stored.set('deadwax-preferences', JSON.stringify({ confirmCancel: false, searchLimit: 30 }))
  check('the main page saying off on this browser, the first read: off, and kept as off',
    [persisted.readConfirmCancel(), stored.get('deadwax-player-confirm-cancel')], [false, 'off'])
  stored.set('deadwax-preferences', JSON.stringify({ confirmCancel: true }))
  check('...once: the main page turned back on changes nothing here', persisted.readConfirmCancel(), false)
  persisted.writeConfirmCancel(true)
  check('chosen on in You: kept as a choice, and read back', [stored.get('deadwax-player-confirm-cancel'), persisted.readConfirmCancel()], ['on', true])
  persisted.writeConfirmCancel(false)
  check('...and off', [stored.get('deadwax-player-confirm-cancel'), persisted.readConfirmCancel()], ['off', false])
  const readsAs = (value) => { stored.set('deadwax-player-confirm-cancel', value); return persisted.readConfirmCancel() }
  check('off only when it says exactly that: anything else kept is on', ['off', 'Off', 'on', 'default', '', 'no'].map(readsAs), [false, true, true, true, true, true])
  stored.clear()
  refusing = true
  let threw = false
  try { persisted.writeConfirmCancel(false) } catch { threw = true }
  check('storage refused: on, and nothing thrown either way', [persisted.readConfirmCancel(), threw], [true, false])
  refusing = false
  stored.clear()
}

console.log('\nwhere they live now')
{
  const you = fs.readFileSync(path.join(UI, 'src/app/You.tsx'), 'utf8')
  const library = fs.readFileSync(path.join(UI, 'src/player/Library.tsx'), 'utf8')
  const persisted = fs.readFileSync(path.join(UI, 'src/state/persisted.ts'), 'utf8')
  //? the Playback section: from its labelled <section> to the one after it closes
  const at = you.indexOf('aria-labelledby="app-playback-title"')
  const playback = at === -1 ? '' : you.slice(at, you.indexOf('</section>', at))
  check('in You, in the Playback section, driving the player\'s own setting',
    [/>\s*Playback\s*</.test(playback), playback.includes('<QualityChoice player={{ maxRate: player.maxRate, setMaxRate: actions.setMaxRate }} />')],
    [true, true])
  check('on the same storage key, per device', /playerMaxRate: 'deadwax-player-max-rate'/.test(persisted), true)
  check('Gapless in the same section, above it, handed the player itself',
    [playback.includes('<GaplessChoice player={player} />'), playback.indexOf('<GaplessChoice') < playback.indexOf('<QualityChoice')], [true, true])
  check('Now Playing opens as between them, handed the setting App keeps',
    [playback.includes('<LookChoice look={opensAs} onChange={onOpensAs} />'),
      playback.indexOf('<GaplessChoice') < playback.indexOf('<LookChoice'), playback.indexOf('<LookChoice') < playback.indexOf('<QualityChoice')],
    [true, true, true])
  check('Pause winds the record down beside Now Playing opens as - after it, before Maximum quality - handed the setting App keeps',
    [playback.includes('<WindDownChoice on={windDown} onChange={onWindDown} />'),
      playback.indexOf('<LookChoice') < playback.indexOf('<WindDownChoice'), playback.indexOf('<WindDownChoice') < playback.indexOf('<QualityChoice')],
    [true, true, true])
  check('...on the key it always had', /playerGapless: 'deadwax-player-gapless'/.test(persisted), true)
  check('...and You no longer sends you to the now-playing screen for it', /now-playing screen/.test(playback), false)
  const nowPlaying = fs.readFileSync(path.join(UI, 'src/player/NowPlaying.tsx'), 'utf8')
  check('the switch is gone from Now Playing', [/role="switch"/.test(nowPlaying), /pl-gapless/.test(nowPlaying), /setGapless/.test(nowPlaying)], [false, false, false])
  check('the gear is gone from the Library', [library.includes('aria-label="Settings"'), library.includes('onSettings')], [false, false])
  check('and the sheet with it', fs.existsSync(path.join(UI, 'src/player/Settings.tsx')), false)
  //? Getting albums: from its labelled <section> to the one after it closes
  const from = you.indexOf('aria-labelledby="app-getting-title"')
  const getting = from === -1 ? '' : you.slice(from, you.indexOf('</section>', from))
  check('"Confirm before cancelling" in You > Getting albums, after the three that are kept on deadwax, its note saying it is this device\'s',
    [/<ConfirmCancelChoice\s+on=\{confirmCancel\}/.test(getting), getting.indexOf('<GettingChoices') < getting.indexOf('<ConfirmCancelChoice'),
      /id="app-confirm-cancel-note"[^>]*>[^<]*Kept on this device\./.test(getting), /useState\(readConfirmCancel\)/.test(you), /writeConfirmCancel\(on\)\s*setConfirmCancel\(on\)/.test(you)],
    [true, true, true, true, true])
  const requests = fs.readFileSync(path.join(UI, 'src/app/Requests.tsx'), 'utf8')
  check('...and Requests\' ✕ reads it at the tap, never the main page\'s key', [/else if \(readConfirmCancel\(\)\) setAsking\(row\.key\)/.test(requests), /readPreferences/.test(requests)], [true, false])
}

console.log('\nthe "Maximum quality" notes say what the code does')
{
  const resample = fs.readFileSync(path.join(REPO, 'src/resample.py'), 'utf8')
  const headroom = Number(/^HEADROOM_DB\s*=\s*([\d.]+)/m.exec(resample)?.[1])
  const choice = fs.readFileSync(path.join(UI, 'src/app/GaplessChoice.tsx'), 'utf8')
  const gaplessLabel = /class="app-check-label">([^<]+)</.exec(choice)?.[1]
  const [up, original] = QUALITIES
  check('two choices, 48 kHz first', QUALITIES.map((q) => [q.rate, q.label]), [['48000', 'Up to 48 kHz'], ['original', 'Original']])
  check('"Up to 48 kHz", word for word',
    up.note,
    'Hi-res FLAC songs (88.2 to 384 kHz) are converted by deadwax to 48 or 44.1 kHz, still lossless 24-bit FLAC, ' +
    'so they are lighter to stream and with Gapless on they play without a gap. Nothing in the range you can hear ' +
    'changes, except that with Normalization off they play 3 dB quieter, so nothing can clip.')
  check('"Original", word for word',
    original.note,
    'Hi-res songs are sent at their own rate, in case a USB DAC can play them at it; otherwise an iPhone converts ' +
    'them to 44.1 or 48 kHz itself. With Gapless on, FLAC songs play without a gap too, but an iPhone holds only a ' +
    'few seconds of them ahead, so a weak connection can make them stall.')
  //? (2.0.2, after review) Normalization levels a hi-res song under Original too, so it isn't sent "exactly" as it
  //? is; and whether an iPhone ever runs a USB DAC at a song's own rate isn't known (docs/player.md), so Original
  //? is never sold as the DAC's choice
  check('...Original never says it sends songs exactly as they are, nor that it is the choice for a USB DAC',
    [/exactly/.test(original.note), /choice for a USB DAC/.test(original.note)], [false, false])
  check('as much quieter as the server lowers them (HEADROOM_DB in src/resample.py)',
    [Number.isFinite(headroom), new RegExp(`\\b${headroom} dB quieter\\b`).test(up.note)], [true, true])
  check('the checkbox named by its own label, in both', [gaplessLabel, QUALITIES.every((q) => q.note.includes(`ith ${gaplessLabel} on`))], ['Gapless', true])
  check('...and never called a switch, now that it is a checkbox', QUALITIES.some((q) => /switch/i.test(q.note)), false)
  const emDash = String.fromCharCode(0x2014)
  check('no em dashes, and deadwax never sentence-cased', QUALITIES.some((q) => q.note.includes(emDash) || q.note.includes('Deadwax')), false)
}

console.log('\nthe choices\' words are for the person choosing (2.0.1)')
{
  //? James: "I need the descriptions to be more user oriented and not testing oriented. Like where gapless says
  //? 'an experiment' is unacceptable" - every label and note these choices draw says what it does for you
  const TESTING = /experiment|\btrial|\bverified\b|\btest(s|ed|ing)?\b|2\.0\.0-player|\bplayer\.\d/i
  const said = [...QUALITIES.flatMap((q) => [q.label, q.note]), ...NORMALIZATIONS.flatMap((n) => [n.label, n.note]), ...LOOKS.map((l) => l.label)]
  check('no label or note of Maximum quality, Normalization or Now Playing opens as reads as a test note', said.filter((one) => TESTING.test(one)), [])
  check('...Off for Normalization still says it is bit for bit, and no longer measures itself against "before this setting"',
    [/bit for bit/.test(NORMALIZATIONS.at(-1).note), /before this setting/.test(NORMALIZATIONS.at(-1).note)], [true, false])
}

console.log('\n"Normalization" is a radio group of its own, kept on this device (2.0.0-player.62)')
{
  const KEY = 'deadwax-player-normalization'
  check('the key it is kept on', persisted.STORAGE_KEYS.playerNormalization, KEY)
  check('four choices, Automatic first, word for word', NORMALIZATIONS.map((each) => [each.value, each.label, each.note]), [
    ['auto', 'Automatic', 'An album you play keeps one level for the whole album, so its quiet songs stay quiet beside its loud ones. ' +
      'Anything else - a playlist, a shuffle, a song you add with Play Next - is levelled song by song.'],
    ['song', 'By song', 'Every song brought to the same loudness, even the quiet and loud songs of one album.'],
    ['album', 'By album', "Every song at its album's level, even when it plays on its own or in a playlist."],
    ['off', 'Off', 'No levelling: every song plays exactly as the file is, bit for bit, unless Maximum quality converts it.'],
  ])
  const emDash = String.fromCharCode(0x2014)
  check('...no em dashes, and deadwax never sentence-cased', NORMALIZATIONS.some((each) => each.note.includes(emDash) || each.note.includes('Deadwax')), false)
  //? what it reads back: one of the other three only when it says exactly that
  stored.clear()
  const readings = [persisted.readPlayerNormalization()]
  for (const value of ['song', 'album', 'off', 'auto', 'Song', 'track', '']) {
    stored.set(KEY, value)
    readings.push(persisted.readPlayerNormalization())
  }
  refusing = true
  readings.push(persisted.readPlayerNormalization())
  refusing = false
  check('Automatic by default: nothing stored, anything unknown, storage that can\'t be read', readings,
    ['auto', 'song', 'album', 'off', 'auto', 'auto', 'auto', 'auto', 'auto'])

  stored.clear()
  const view = mount(NormalizationChoice, 'normalization')
  const render = () => view.render({})
  render()
  //? found again after each render: its key handler is the render's own, as Preact binds it
  const group = () => view.find((node) => node.props?.role === 'radiogroup')[0]
  const [title] = view.find((node) => node.type === 'h3')
  const radios = () => view.find((node) => node.props?.role === 'radio')
  check('a radio group labelled by its heading', [!!group(), group()?.props['aria-labelledby'] === title?.props.id, title?.props.children], [true, true, 'Normalization'])
  check('four radios, Automatic chosen on a fresh device, each named and described by its own words',
    radios().map((r) => [r.props['data-level'], r.props['aria-checked'], r.props['aria-labelledby'], r.props['aria-describedby']]), [
      ['auto', true, 'app-normalization-auto-label', 'app-normalization-auto-note'], ['song', false, 'app-normalization-song-label', 'app-normalization-song-note'],
      ['album', false, 'app-normalization-album-label', 'app-normalization-album-note'], ['off', false, 'app-normalization-off-label', 'app-normalization-off-note']])
  check('only the chosen one is a tab stop', radios().map((r) => r.props.tabIndex), [0, -1, -1, -1])
  check('...and nothing stored until one is chosen', stored.has(KEY), false)

  radios()[3].props.onClick()
  render()
  check('a tap on Off picks it, and keeps it on this device', [radios().map((r) => r.props['aria-checked']), stored.get(KEY)], [[false, false, false, true], 'off'])
  check('...the tab stop moves with it', radios().map((r) => r.props.tabIndex), [-1, -1, -1, 0])
  document.activeElement = document.body
  let prevented = keyOn(view, group(), 'ArrowDown')
  render()
  check('ArrowDown from the last wraps to the first, and takes the focus with it', [prevented, stored.get(KEY), document.activeElement === radios()[0].element], [true, 'auto', true])
  keyOn(view, group(), 'ArrowUp')
  render()
  check('ArrowUp wraps back', [stored.get(KEY), document.activeElement === radios()[3].element], ['off', true])
  keyOn(view, group(), 'ArrowLeft')
  render()
  keyOn(view, group(), 'ArrowLeft')
  render()
  check('ArrowLeft moves back, twice: By song', [stored.get(KEY), radios().map((r) => r.props['aria-checked'])], ['song', [false, true, false, false]])
  keyOn(view, group(), 'ArrowRight')
  render()
  check('ArrowRight moves on: By album', stored.get(KEY), 'album')
  const focused = document.activeElement
  prevented = keyOn(view, group(), 'Enter')
  render()
  check('any other key is left alone', [prevented, stored.get(KEY), document.activeElement === focused], [false, 'album', true])
  check('read again on a fresh mount: the choice kept', (() => {
    const again = mount(NormalizationChoice, 'normalization again')
    again.render({})
    return again.find((node) => node.props?.role === 'radio' && node.props['aria-checked']).map((r) => r.props['data-level'])
  })(), ['album'])
  const source = fs.readFileSync(path.join(UI, 'src/app/NormalizationChoice.tsx'), 'utf8')
  check('it calls nothing of the player: its own state, written to this device', [/\bplayer\.|usePlayer|type Player\b/.test(source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '')), /useState<Normalization>\(readPlayerNormalization\)/.test(source)], [false, true])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
