/**
 * MusicBrainz's saved answers beside their settings (2.0.0-player.54): components/MusicBrainzAnswers.tsx -
 * "Clear MusicBrainz's saved answers", on the main page's settings tab and the app's Server settings page
 * alike - and its pure parts, lib/musicbrainzAnswers.ts. The component compiled with the repo's TypeScript
 * and rendered by the small stand-in for Preact the other sims use; deadwax faked at its api module, each
 * ask answered by hand. (Where the page draws it - under the group's two rows on Connections, refused while
 * the path is a draft - is settingslog.sim.cjs's.)
 *
 * What it pins:
 *
 *  - read as it is drawn, through a call that can be called off, and said meanwhile; its words: how many
 *    answers in what size, of how many MB - "Nothing saved yet." with none, saving off said with
 *    MUSICBRAINZ_CACHE_MB at 0 (and what the file still holds), and a problem with the file in the server's
 *    words; a read that fails says so;
 *  - Clear asks the server once, says "Clearing…" and takes no second press meanwhile, then draws what the
 *    server answered and says it was cleared - and a failed Clear says so, with the old count kept;
 *  - refused while the path is a draft ("Save the new path first."), with nothing to clear, and while it
 *    goes - always with aria-disabled and the press refused, never `disabled` (review: Clear refuses itself
 *    on its own press, and a focused button made disabled drops the focus to the page);
 *  - read again each time its page comes back into view (`live` turning true: the app keeps a hidden tab's
 *    page drawn, and the file fills meanwhile) - nothing read while out of view, nor over a Clear on its
 *    way, whose answer still lands once it is back; "Cleared." only until the next read; going out of view
 *    calls nothing off, being let go does;
 *  - only the newest answer draws: a Clear calls the read before it off, and nothing lands once the line
 *    is gone - neither a read nor a Clear answered after it was let go;
 *  - the size in words (bytes, KB, MB to one place, 1024s), and the key the page redraws it on: the
 *    group's settings as saved, so a save of either draws it afresh.
 *
 * Run it with:  node ui/test/mbanswers.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-mbanswers-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/components/MusicBrainzAnswers.tsx', 'src/lib/musicbrainzAnswers.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - care.sim's stand-in
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
  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === 'function') s.cleanup() }
  return render
}
`)

//? deadwax, as the test says it answers: each ask kept, answered by hand
fs.writeFileSync(path.join(OUT, 'api/musicbrainzCache.js'), `
const W = () => globalThis.__answers
exports.getSavedAnswers = (signal) => new Promise((resolve, reject) => W().reads.push({ resolve, reject, signal }))
exports.clearSavedAnswers = (...given) => new Promise((resolve, reject) => W().clears.push({ resolve, reject, given }))
`)
const W = globalThis.__answers = { reads: [], clears: [] }
const reset = () => { W.reads.length = 0; W.clears.length = 0 }

const { MusicBrainzAnswers } = require(path.join(OUT, 'components/MusicBrainzAnswers.js'))
const M = require(path.join(OUT, 'lib/musicbrainzAnswers.js'))
const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))

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
function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  return words(node.props?.children)
}
const note = () => words(find((node) => node.props?.class === 'settings-answers-note')[0])
const clearButton = () => find((node) => node.type === 'button')[0]
//? refused with aria-disabled, never `disabled` (review: a focused button made disabled drops the focus to
//? the page) - and every state drawn is checked never to set `disabled` at all
let disabledSeen = 0
const refusedNow = () => {
  if (clearButton().props.disabled !== undefined) disabledSeen++
  return clearButton().props['aria-disabled']
}

function mount(props) {
  const render = hooks.root(MusicBrainzAnswers)
  const all = { unsaved: false, ...props }
  const draw = (more = {}) => {
    Object.assign(all, more)
    tree = render(all)
    render.commit()
    tree = render(all)
    return tree
  }
  //? drawn again with no effects run - to see what an answer landing after an unmount left behind
  const peek = () => (tree = render(all))
  return { draw, peek, unmount: () => render.unmount() }
}

const stats = (more = {}) => ({ enabled: true, path: '/config/musicbrainz-cache.db', bytes: 3 * 1024 * 1024 + 300 * 1024,
  answers: 1234, limit_mb: 200, problem: null, ...more })

async function main() {
  console.log('\nthe words: sizes, and what the file holds')
  {
    check('sizes: bytes, KB, MB to one place (1024s)', [M.describeBytes(0), M.describeBytes(1023), M.describeBytes(1024), M.describeBytes(45 * 1024), M.describeBytes(3.25 * 1024 * 1024)],
      ['0 bytes', '1023 bytes', '1 KB', '45 KB', '3.3 MB'])
    check('answers held: how many, in what, of how many MB', M.describeSavedAnswers(stats(), false), '1,234 answers in 3.3 MB saved, of 200 MB.')
    check('...one', M.describeSavedAnswers(stats({ answers: 1, bytes: 20480 }), false), '1 answer in 20 KB saved, of 200 MB.')
    check('...none yet', M.describeSavedAnswers(stats({ answers: 0, bytes: 0 }), false), 'Nothing saved yet.')
    check('...none, just cleared', M.describeSavedAnswers(stats({ answers: 0, bytes: 28672 }), true), 'Cleared. The next answers are asked of MusicBrainz again.')
    check('saving off, nothing kept', M.describeSavedAnswers(stats({ enabled: false, answers: 0, bytes: 0 }), false),
      'Saving is off (MUSICBRAINZ_CACHE_MB is 0): answers are kept in memory only, for an hour.')
    check('saving off, a file still there', M.describeSavedAnswers(stats({ enabled: false }), false),
      'Saving is off (MUSICBRAINZ_CACHE_MB is 0), and the file still holds 1,234 answers in 3.3 MB.')
    check('a problem with the file, in the server\'s words', M.describeSavedAnswers(stats({ problem: '/x.db is a database, but not deadwax\'s saved answers', answers: 0, bytes: 0 }), false),
      'Nothing is being saved: /x.db is a database, but not deadwax\'s saved answers.')
    const group = (path, mb) => ({ id: M.SAVED_ANSWERS_GROUP, label: '', note: '', settings: [
      { key: 'MUSICBRAINZ_CACHE_PATH', value: path }, { key: 'MUSICBRAINZ_CACHE_MB', value: mb }] })
    check('the key it is drawn afresh on: the settings as saved', [M.savedAnswersKey(group(null, '200')), M.savedAnswersKey(group('/ssd/', '200')) === M.savedAnswersKey(group(null, '200')),
      M.savedAnswersKey(group(null, '0')) === M.savedAnswersKey(group(null, '200'))], ['MUSICBRAINZ_CACHE_PATH=|MUSICBRAINZ_CACHE_MB=200', false, false])
    check('the group and the setting it watches', [M.SAVED_ANSWERS_GROUP, M.SAVED_ANSWERS_PATH], ['musicbrainz-cache', 'MUSICBRAINZ_CACHE_PATH'])
  }

  console.log('\nread as it is drawn')
  {
    reset()
    const one = mount()
    one.draw()
    check('one read, through a call that can be called off - said meanwhile, Clear not offered yet',
      [W.reads.length, !!W.reads[0].signal, note(), refusedNow()], [1, true, 'Reading the saved answers…', true])
    W.reads[0].resolve(stats())
    await settle()
    one.draw()
    check('answered: what the file holds, and Clear offered, saying what it does',
      [note(), words(clearButton()), refusedNow(), clearButton().props.title.startsWith('Every saved answer gone, on disk and in memory')],
      ['1,234 answers in 3.3 MB saved, of 200 MB.', "Clear MusicBrainz's saved answers", false, true])
    check('the line is a live region, the button outside it', [find((node) => node.props?.role === 'status').map((node) => node.props.class), find((node) => node.props?.role === 'status' && find((child) => child.type === 'button', node).length).length],
      [['settings-answers-note'], 0])

    console.log('\nClear')
    clearButton().props.onClick()
    one.draw()
    check('pressed: the server asked once, with nothing called off later - saying so, refusing a second press',
      [W.clears.length, W.clears[0].given, words(clearButton()), refusedNow()], [1, [], 'Clearing…', true])
    clearButton().props.onClick()
    check('...a second press while it goes asks nothing', W.clears.length, 1)
    W.clears[0].resolve(stats({ answers: 0, bytes: 28672 }))
    await settle()
    one.draw()
    check('answered: what the server says now, and that it was cleared - nothing left to clear',
      [note(), words(clearButton()), refusedNow(), clearButton().props.title], ['Cleared. The next answers are asked of MusicBrainz again.', "Clear MusicBrainz's saved answers", true, 'Nothing saved to clear'])
    one.unmount()
  }

  console.log('\nnothing to clear, a draft of the path, failures')
  {
    reset()
    const empty = mount()
    empty.draw()
    W.reads[0].resolve(stats({ answers: 0, bytes: 0 }))
    await settle()
    empty.draw()
    check('nothing saved: Clear refused, saying why', [note(), refusedNow(), clearButton().props.title], ['Nothing saved yet.', true, 'Nothing saved to clear'])
    clearButton().props.onClick()
    check('...pressed anyway (a stale tap): nothing asked', W.clears.length, 0)
    empty.unmount()

    reset()
    const draft = mount({ unsaved: true })
    draft.draw()
    W.reads[0].resolve(stats())
    await settle()
    draft.draw()
    check('the path a draft: refused - it clears the file that is SAVED', [note(), refusedNow(), clearButton().props.title.startsWith('Save the new path first')],
      ['Save the new path first.', true, true])
    clearButton().props.onClick()
    check('...pressed anyway: nothing asked', W.clears.length, 0)
    draft.draw({ unsaved: false })
    check('...saved (or typed back): offered again', [note(), refusedNow()], ['1,234 answers in 3.3 MB saved, of 200 MB.', false])
    clearButton().props.onClick()
    W.clears[0].reject(new Error('the database is locked'))
    await settle()
    draft.draw()
    check('a failed Clear says so, and the count it had stays for the next try',
      [note(), refusedNow(), words(clearButton())], ["Couldn't clear MusicBrainz's saved answers. Try again. (the database is locked)", false, "Clear MusicBrainz's saved answers"])
    draft.unmount()

    reset()
    const failed = mount()
    failed.draw()
    W.reads[0].reject(new Error('503'))
    await settle()
    failed.draw()
    check('a read that fails says so, and offers nothing to clear', [note(), refusedNow()], ["Couldn't read MusicBrainz's saved answers. Try again. (503)", true])
    failed.unmount()
  }

  console.log('\nonly the newest answer draws')
  {
    reset()
    const one = mount()
    one.draw()
    W.reads[0].resolve(stats())
    await settle()
    one.draw()
    clearButton().props.onClick()
    check('a Clear calls the read before it off: its signal aborted', W.reads[0].signal.aborted, true)
    W.clears[0].resolve(stats({ answers: 0, bytes: 28672 }))
    await settle()
    one.draw()
    check('...what Clear answered stands', note(), 'Cleared. The next answers are asked of MusicBrainz again.')
    one.unmount()
    const two = mount()
    two.draw()
    check('drawn afresh (a save of either setting keys it anew): read again', W.reads.length, 2)
    two.unmount()

    reset()
    const gone = mount()
    gone.draw()
    gone.unmount()
    check('gone before it answered: the read called off', W.reads[0].signal.aborted, true)
    W.reads[0].resolve(stats())
    await settle()
    gone.peek()
    check('...and its answer lands nowhere: still reading, as it was left', note(), 'Reading the saved answers…')

    reset()
    const racing = mount()
    racing.draw()
    W.reads[0].resolve(stats())
    await settle()
    racing.draw()
    clearButton().props.onClick()
    racing.unmount()
    W.clears[0].resolve(stats({ answers: 0 }))
    await settle()
    racing.peek()
    check('gone while Clear went: what it answered lands nowhere - as it was left', [words(clearButton()), note()], ['Clearing…', '1,234 answers in 3.3 MB saved, of 200 MB.'])
  }

  console.log('\nread again as its page comes back into view (the app keeps a hidden page drawn)')
  {
    reset()
    const page = mount({ live: true })
    page.draw()
    W.reads[0].resolve(stats({ answers: 0, bytes: 0 }))
    await settle()
    page.draw()
    check('first shown: read once - nothing saved yet', [W.reads.length, note(), refusedNow()], [1, 'Nothing saved yet.', true])
    page.draw({ live: false })
    page.draw()
    check('out of view (another tab in front): nothing read, nothing called off', [W.reads.length, W.reads[0].signal.aborted], [1, false])
    page.draw({ live: true })
    check('back in view: read again, through a call that can be called off', [W.reads.length, !!W.reads[1]?.signal], [2, true])
    W.reads[1].resolve(stats({ answers: 5, bytes: 40960 }))
    await settle()
    page.draw()
    check('...what the file holds NOW (searched meanwhile): the count, and Clear offered', [note(), refusedNow()], ['5 answers in 40 KB saved, of 200 MB.', false])
    page.draw({ live: true })
    check('drawn again while in view: nothing more read', W.reads.length, 2)

    console.log('\n...and a Clear still on its way as the page goes and comes back')
    clearButton().props.onClick()
    page.draw()
    page.draw({ live: false })
    page.draw({ live: true })
    check('back while Clear goes: nothing read over it, and still clearing', [W.reads.length, words(clearButton()), refusedNow()], [2, 'Clearing…', true])
    W.clears[0].resolve(stats({ answers: 0, bytes: 28672 }))
    await settle()
    page.draw()
    check('...its answer lands - going out of view called nothing off', [note(), words(clearButton()), refusedNow()],
      ['Cleared. The next answers are asked of MusicBrainz again.', "Clear MusicBrainz's saved answers", true])
    page.draw({ live: false })
    page.draw({ live: true })
    W.reads[2].resolve(stats({ answers: 0, bytes: 28672 }))
    await settle()
    page.draw()
    check('..."Cleared." only until the next read: then what the file holds', [W.reads.length, note()], [3, 'Nothing saved yet.'])

    page.draw({ live: false })
    page.draw({ live: true })
    page.unmount()
    check('let go with a read out: that read called off', W.reads[3].signal.aborted, true)
  }

  console.log('\nthe main page draws it with no `live`: read as drawn, once')
  {
    reset()
    const tab = mount({})
    tab.draw()
    tab.draw()
    check('one read, as before', W.reads.length, 1)
    tab.unmount()
  }
}

main().then(() => {
  check('the button never set `disabled`, in any state drawn - aria-disabled only', disabledSeen, 0)
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}, (error) => {
  console.error(error)
  process.exit(1)
})
