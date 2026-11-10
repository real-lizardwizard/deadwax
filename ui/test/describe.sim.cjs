/**
 * A short description on the artist page, the album page and the album you don't have (2.0.13): ui/src/lib/describe.ts's
 * rules, app/useDescription.ts (the page's ask, through latestOnly, kept for the session, placed) and
 * app/Description.tsx (the clamp, More / Less, the source's link) - compiled with the repo's TypeScript and rendered by
 * the small stand-in for Preact the other component sims use, deadwax's answer given by hand.
 *
 * What it pins:
 *
 *  - What is asked: the MusicBrainz id (lowercased) and/or Navidrome's id, as the route's query - nothing at all with
 *    neither. An answer is drawn only with words and a source this page knows; its link only when it goes where it
 *    says (https, en.wikipedia.org or last.fm) - anything else draws the words with no link.
 *  - Kept for the session by what was asked, the oldest going past DESCRIPTIONS_KEPT; a failure, or an answer deadwax
 *    marks `unavailable`, kept only UNSURE_KEPT_MS.
 *  - WHERE IT GOES: under the name or the hero when it is in hand before what lies under that place is drawn, at
 *    the foot when it came after - and once placed, there for the page (a page drawn for another subject placing
 *    afresh).
 *  - The hook: nothing asked until who it is is settled; one ask per question, the newest only drawn (an older
 *    answer landing late draws nothing); `settled` once answered or failed, or with nothing to ask; a kept answer
 *    drawn on the first frame, nothing asked.
 *  - The block: the words as TEXT (a string child, never HTML), `dir="auto"`, clamped (`is-clamped`) until More;
 *    More only when they run past the clamp - a button with `aria-expanded` and `aria-controls` naming the words -
 *    and Less to close them again; measured again as the width changes (a ResizeObserver, else the window's resize);
 *    "From Wikipedia" / "More on Last.fm" opening beside the app (`target="_blank" rel="noopener"`), none without a
 *    link; nothing under the words when there is neither.
 *  - The pages: each asks with useDescription and draws the block at its top place and its foot; the album page's
 *    songs, the artist's albums and the pressings' tracklist wait for it (`settled`) - the songs and the tracklist
 *    DESCRIPTION_WAIT_MS at most, the albums with their own wait - and pass what is drawn under it as `belowDrawn`
 *    (the pressings' trouble and the library's failed notice, with their Try again, counting too).
 *
 * Run it with:  node ui/test/describe.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-describe-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/describe.ts', 'src/app/useDescription.ts', 'src/app/Description.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - artist.sim.cjs's stand-in
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
  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === 'function') s.cleanup() }
  return render
}
`)
//? deadwax's answer, given when the test says - every ask kept
fs.writeFileSync(path.join(OUT, 'api/describe.js'), `
exports.getDescription = (key, signal) => globalThis.__describe.ask(key, signal)
`)
const W = globalThis.__describe = {
  asks: [], open: [],
  ask(key, signal) {
    W.asks.push(key)
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    W.open.push({ key, signal, resolve, reject })
    return promise
  },
}
function answer(key, value) {
  const at = W.open.findIndex((one) => one.key === key)
  if (at < 0) throw new Error(`nothing asked for ${key}`)
  const [one] = W.open.splice(at, 1)
  if (value instanceof Error) one.reject(value)
  else one.resolve(value)
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

const D = require(path.join(OUT, 'lib/describe.js'))
const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { useDescription } = require(path.join(OUT, 'app/useDescription.js'))
const { DescriptionBlock } = require(path.join(OUT, 'app/Description.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const PORTISHEAD = '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11'
const DUMMY = '48140466-cff6-3222-bd55-63c27e43190d'
const WORDS = 'Portishead are an English electronic band formed in 1991 in Bristol.'
const PARAGRAPH = { text: WORDS, source: 'wikipedia', url: 'https://en.wikipedia.org/wiki/Portishead_(band)' }
const WIKI = { ...PARAGRAPH, subtitle: 'English band', unavailable: false }
const DRAWN = { paragraph: PARAGRAPH, subtitle: 'English band' }
const NONE = { text: null, source: null, url: null, subtitle: null, unavailable: false }

function find(test, within) {
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
const classed = (tree, name) => find((node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name), tree)
//? what the session holds for a key, said as a word - JSON writes an undefined in a list as null, and "not kept" and
//? "kept as none" must never read alike
const state = (key, now) => { const found = D.keptDescription(key, now); return found === undefined ? 'not kept' : found === null ? 'none' : found.paragraph?.text ?? found.subtitle }

async function main() {
  console.log('\nwhat is asked')
  {
    check('by MusicBrainz id (as MusicBrainz writes one) and Navidrome\'s', D.describeKey('artist', { mbid: PORTISHEAD.toUpperCase(), navidromeId: 'ar-1' }),
      `/describe/artist?mbid=${PORTISHEAD}&navidrome_id=ar-1`)
    check('by either alone', [D.describeKey('album', { mbid: DUMMY }), D.describeKey('album', { navidromeId: 'al 1' })],
      [`/describe/album?mbid=${DUMMY}`, '/describe/album?navidrome_id=al+1'])
    check('nothing to ask by: nothing asked', [D.describeKey('artist', {}), D.describeKey('album', { mbid: ' ', navidromeId: null })], [null, null])
  }

  console.log('\nwhat is drawn of an answer')
  {
    check('the paragraph with its page, and the subtitle', D.descriptionOf(WIKI), DRAWN)
    check('Navidrome\'s, its link Last.fm\'s page', D.descriptionOf({ text: ' Words. ', source: 'lastfm', url: 'https://www.last.fm/music/Portishead' }),
      { paragraph: { text: 'Words.', source: 'lastfm', url: 'https://www.last.fm/music/Portishead' }, subtitle: null })
    check('a subtitle alone is something to draw', D.descriptionOf({ ...NONE, subtitle: ' Icelandic band ' }), { paragraph: null, subtitle: 'Icelandic band' })
    check('none, no words, a source it doesn\'t know: nothing', [D.descriptionOf(NONE), D.descriptionOf({ ...PARAGRAPH, text: '  ' }), D.descriptionOf({ ...PARAGRAPH, source: 'deezer' }), D.descriptionOf(null)],
      [null, null, null, null])
    check('a link only to where it says - never plain http, another host or a script',
      ['http://en.wikipedia.org/wiki/X', 'https://fr.wikipedia.org/wiki/X', 'https://en.wikipedia.org.evil.example/x', 'javascript:alert(1)', 'not a url']
        .map((url) => D.descriptionOf({ ...PARAGRAPH, url }).paragraph.url), [null, null, null, null, null])
    check('...nor Last.fm\'s words linked to Wikipedia', D.descriptionOf({ text: 'x', source: 'lastfm', url: PARAGRAPH.url }).paragraph.url, null)
    check('the link\'s words: the credit, and where Navidrome\'s go', [D.SOURCE_WORDS.wikipedia, D.SOURCE_WORDS.lastfm], ['From Wikipedia', 'More on Last.fm'])
    check('the clamp\'s button', [D.MORE, D.LESS], ['More', 'Less'])
    check('the songs\' and the tracklist\'s wait; how long an unsure answer is kept', [D.DESCRIPTION_WAIT_MS, D.UNSURE_KEPT_MS], [500, 60000])
    check('the block: an artist\'s paragraph alone (their subtitle is in the hero), an album\'s both',
      [D.inBlock('artist', DRAWN), D.inBlock('album', DRAWN)], [{ paragraph: PARAGRAPH, subtitle: null }, DRAWN])
    check('...an artist\'s subtitle alone: nothing in the block; an album\'s: the block', [D.inBlock('artist', { paragraph: null, subtitle: 'x' }), D.inBlock('album', { paragraph: null, subtitle: 'x' }), D.inBlock('album', null)],
      [null, { paragraph: null, subtitle: 'x' }, null])
  }

  console.log('\nwhere it goes')
  {
    check('in hand before what lies under it is drawn: at the top; after: at the foot', [D.placeOf(null, true, false), D.placeOf(null, true, true)], ['top', 'foot'])
    check('none yet: nowhere', D.placeOf(null, false, false), null)
    check('once placed, there it stays', [D.placeOf('top', true, true), D.placeOf('foot', true, false), D.placeOf('top', false, true)], ['top', 'foot', 'top'])
  }

  console.log('\nkept for the session')
  {
    D.forgetDescriptions()
    check('nothing kept; "none" kept', [state('a'), (D.keepDescription('a', null), state('a'))], ['not kept', 'none'])
    check('...a kept none is null, nothing kept undefined', [D.keptDescription('a') === null, D.keptDescription('zz') === undefined], [true, true])
    for (let n = 0; n < D.DESCRIPTIONS_KEPT; n++) D.keepDescription(`k${n}`, DRAWN)
    check(`at most ${D.DESCRIPTIONS_KEPT}: the oldest went first`, [state('a'), state('k0')], ['not kept', WORDS])
    D.keptDescription('k1')
    D.keepDescription('new', null)
    check('...the most recently used kept over an older one', [state('k1'), state('k2')], [WORDS, 'not kept'])
    D.keepDescription('unsure', DRAWN, true, 1000)
    check('an unsure answer: kept UNSURE_KEPT_MS, then not kept', [state('unsure', 1000 + D.UNSURE_KEPT_MS - 1), state('unsure', 1000 + D.UNSURE_KEPT_MS)], [WORDS, 'not kept'])
    D.keepDescription('sure', DRAWN, false, 1000)
    check('...a sure one for the session', state('sure', 1000 + 365 * 86400000), WORDS)
    D.rememberPageKey('album:al-1', 'k1')
    check('the question a page asked, remembered', [D.pageKeyOf('album:al-1'), D.pageKeyOf('album:al-2')], ['k1', null])
    D.forgetDescriptions()
    check('...forgotten with the rest', D.pageKeyOf('album:al-1'), null)
  }

  const mountHook = () => {
    const render = hooks.root((props) => useDescription(props.kind, props.ids, props.below, props.page))
    const props = { kind: 'artist', ids: null, below: false, page: 'p' }
    const draw = (more = {}) => { Object.assign(props, more); const got = render(props); render.commit(); return got }
    return { render, draw }
  }

  console.log('\nthe hook: asked once who it is is settled, the newest answer only')
  {
    D.forgetDescriptions()
    W.asks.length = 0
    const { render, draw } = mountHook()
    draw({ page: 'ar-1' })
    check('who it is not settled: nothing asked, not settled', [draw(), W.asks], [{ description: null, settled: false, at: null }, []])
    check('settled: asked once, by its key - not settled until it answers',
      [draw({ ids: { mbid: PORTISHEAD } }).settled, draw().settled, W.asks], [false, false, [`/describe/artist?mbid=${PORTISHEAD}`]])
    answer(`/describe/artist?mbid=${PORTISHEAD}`, WIKI)
    await settle()
    check('answered before what is under it was drawn: drawn at the top', draw(), { description: DRAWN, settled: true, at: 'top' })
    check('...and it stays there as the albums are drawn', draw({ below: true }).at, 'top')
    check('...kept for the session', state(`/describe/artist?mbid=${PORTISHEAD}`, Date.now() + 365 * 86400000), WORDS)

    //? another question while the first is out: the first's answer, landing last, draws nothing
    draw({ kind: 'album', ids: { mbid: DUMMY }, page: 'al-1', below: false })
    draw({ ids: { mbid: DUMMY, navidromeId: 'al-1' } })
    check('a newer question asked; the older never called off (its answer is still kept when it comes)', [W.asks.slice(-2), W.open.find((one) => one.key === `/describe/album?mbid=${DUMMY}`)?.signal],
      [[`/describe/album?mbid=${DUMMY}`, `/describe/album?mbid=${DUMMY}&navidrome_id=al-1`], undefined])
    answer(`/describe/album?mbid=${DUMMY}`, WIKI)
    await settle()
    check('...the older one\'s answer drawn nowhere, nothing settled by it - but kept', [draw(), state(`/describe/album?mbid=${DUMMY}`)], [{ description: null, settled: false, at: null }, WORDS])
    check('the hook\'s ask through a latestOnly() of its own, asking current() before it draws',
      [/const requests = useMemo\(latestOnly, \[\]\)/.test(fs.readFileSync(path.join(UI, 'src/app/useDescription.ts'), 'utf8')),
        /if \(request\.current\(\)\) setAnswer\(\{ key, found \}\)/.test(fs.readFileSync(path.join(UI, 'src/app/useDescription.ts'), 'utf8'))], [true, true])
    draw({ below: true })
    answer(`/describe/album?mbid=${DUMMY}&navidrome_id=al-1`, { text: 'Dummy is the debut.', source: 'lastfm', url: null, subtitle: '1994 studio album by Portishead', unavailable: false })
    await settle()
    check('a page drawn for another album places afresh - after its songs were drawn: at the foot', draw().at, 'foot')
    render.unmount()
  }

  console.log('\nthe hook: a page left before its answer came, and come back to')
  {
    D.forgetDescriptions()
    W.asks.length = 0
    const first = mountHook()
    first.draw({ ids: { mbid: PORTISHEAD }, page: 'mb:p' })
    first.render.unmount()
    const back = mountHook()
    check('come back to while it is still out: the same question waited for, nothing asked again', [back.draw({ ids: { mbid: PORTISHEAD }, page: 'mb:p' }).settled, W.asks.length], [false, 1])
    answer(`/describe/artist?mbid=${PORTISHEAD}`, WIKI)
    await settle()
    check('...its answer drawn there', back.draw().description, DRAWN)
    back.render.unmount()
    W.asks.length = 0
    const left = mountHook()
    left.draw({ kind: 'album', ids: { mbid: DUMMY, navidromeId: 'al-9' }, page: 'al-9' })
    left.render.unmount()
    answer(`/describe/album?mbid=${DUMMY}&navidrome_id=al-9`, WIKI)
    await settle()
    check('left before it came: kept all the same', state(`/describe/album?mbid=${DUMMY}&navidrome_id=al-9`), WORDS)
    const again = mountHook()
    check('...come back to, its ids still being settled (the bridge out): the answer it had on the first frame, settled, nothing asked',
      [again.draw({ kind: 'album', ids: null, page: 'al-9' }), W.asks.length], [{ description: DRAWN, settled: true, at: 'top' }, 1])
    again.render.unmount()
  }

  console.log('\nthe hook: the question changing - what is drawn stays until the new answer replaces it')
  {
    D.forgetDescriptions()
    W.asks.length = 0
    const { render, draw } = mountHook()
    draw({ kind: 'artist', ids: { mbid: PORTISHEAD }, page: 'ar-5' })
    answer(`/describe/artist?mbid=${PORTISHEAD}`, WIKI)
    await settle()
    check('drawn at the top', draw().at, 'top')
    check('the ids unsettled a moment (the library asked again): still drawn, at the top', draw({ ids: null, below: true }), { description: DRAWN, settled: true, at: 'top' })
    const asked = draw({ ids: { mbid: PORTISHEAD, navidromeId: 'ar-5' } })
    check('...a new question (Navidrome\'s artist found): still drawn while it is out, not settled', [asked.description, asked.settled, asked.at, W.asks.at(-1)],
      [DRAWN, false, 'top', `/describe/artist?mbid=${PORTISHEAD}&navidrome_id=ar-5`])
    answer(`/describe/artist?mbid=${PORTISHEAD}&navidrome_id=ar-5`, { text: 'Their own words.', source: 'lastfm', url: null, subtitle: 'English band', unavailable: false })
    await settle()
    check('...its answer replaces it, where it was', [draw().description.paragraph.text, draw().at], ['Their own words.', 'top'])
    draw({ ids: { mbid: DUMMY } })
    answer(`/describe/artist?mbid=${DUMMY}`, NONE)
    await settle()
    check('...a new answer of none takes it away', draw(), { description: null, settled: true, at: null })
    check('another page: nothing of the last one\'s drawn', draw({ ids: null, page: 'ar-6' }), { description: null, settled: false, at: null })
    render.unmount()
  }

  console.log('\nthe hook: a failure, an unsure answer, a kept answer, nothing to ask')
  {
    D.forgetDescriptions()
    W.asks.length = 0
    const realNow = Date.now
    let now = 5_000_000
    Date.now = () => now
    const realInfo = console.info
    const said = []
    console.info = (...args) => said.push(args.join(' '))
    const { render, draw } = mountHook()
    draw({ ids: { navidromeId: 'ar-9' }, page: 'ar-9' })
    answer('/describe/artist?navidrome_id=ar-9', new TypeError('Failed to fetch'))
    await settle()
    check('failed: settled, nothing drawn, said to the console only', [draw(), said.length], [{ description: null, settled: true, at: null }, 1])
    check('...kept as "none" a moment - so a page come back to waits for nothing', state('/describe/artist?navidrome_id=ar-9'), 'none')
    now += D.UNSURE_KEPT_MS
    check('...and after UNSURE_KEPT_MS, not kept: asked again', state('/describe/artist?navidrome_id=ar-9'), 'not kept')
    render.unmount()
    console.info = realInfo

    const unsure = mountHook()
    unsure.draw({ ids: { mbid: PORTISHEAD }, page: 'ar-10' })
    answer(`/describe/artist?mbid=${PORTISHEAD}`, { ...NONE, unavailable: true })
    await settle()
    check('deadwax said a source couldn\'t be asked: kept as none a moment, not the session', [state(`/describe/artist?mbid=${PORTISHEAD}`), state(`/describe/artist?mbid=${PORTISHEAD}`, now + D.UNSURE_KEPT_MS)],
      ['none', 'not kept'])
    unsure.render.unmount()
    Date.now = realNow

    D.keepDescription(`/describe/artist?mbid=${PORTISHEAD}`, DRAWN)
    const again = mountHook()
    W.asks.length = 0
    check('kept: drawn on the first frame, at the top, nothing asked', [again.draw({ ids: { mbid: PORTISHEAD }, page: 'mb:x' }), W.asks], [{ description: DRAWN, settled: true, at: 'top' }, []])
    const none = again.draw({ ids: {} })
    check('nothing to ask by: settled at once, nothing drawn, nothing asked', [none.settled, none.description, W.asks], [true, null, []])
    again.render.unmount()
  }

  console.log('\nthe block: the subtitle, the words as text, clamped, More and Less, the source')
  {
    const observed = []
    globalThis.ResizeObserver = class {
      constructor(fn) { this.fn = fn; observed.push(this) }
      observe(element) { this.element = element }
      disconnect() { this.gone = true }
    }
    const render = hooks.root(DescriptionBlock)
    const element = { scrollHeight: 130, clientHeight: 66 }
    let tree = render({ description: DRAWN, at: 'top' })
    const p = find((node) => node.type === 'p' && node.props.ref, tree)[0]
    p.props.ref.current = element
    render.commit()
    tree = render({ description: DRAWN, at: 'top' })
    render.commit()
    const subtitle = classed(tree, 'app-about-subtitle')[0]
    check('the subtitle first, a line of text, its direction its own', [subtitle.props.children, subtitle.props.dir, tree.props.children.flat(Infinity).filter(Boolean)[0] === subtitle], ['English band', 'auto', true])
    const text = classed(tree, 'app-about-text')[0]
    check('the words as a string child, clamped, its direction its own', [text.props.children, text.props.class, text.props.dir, 'dangerouslySetInnerHTML' in text.props],
      [WORDS, 'app-about-text is-clamped', 'auto', false])
    const more = classed(tree, 'app-about-more')[0]
    check('running past the clamp: More, a button saying it opens the words', [words(more), more.type, more.props.type, more.props['aria-expanded'], more.props['aria-controls'] === text.props.id],
      ['More', 'button', 'button', false, true])
    const link = classed(tree, 'app-about-source')[0]
    check('"From Wikipedia", opening beside the app', [words(link), link.props.href, link.props.target, link.props.rel], ['From Wikipedia', PARAGRAPH.url, '_blank', 'noopener'])
    check('measured as the width changes', [observed.length, observed[0].element === element], [1, true])
    more.props.onClick()
    tree = render({ description: DRAWN, at: 'top' })
    render.commit()
    check('More: the words whole, Less to close them', [classed(tree, 'app-about-text')[0].props.class, words(classed(tree, 'app-about-more')[0]), classed(tree, 'app-about-more')[0].props['aria-expanded']],
      ['app-about-text', 'Less', true])
    check('...the watch on the width stopped while open', observed[0].gone, true)
    const other = { paragraph: { ...PARAGRAPH, text: 'Dummy is the debut studio album by Portishead, and much more besides.' }, subtitle: null }
    tree = render({ description: other, at: 'top' })
    render.commit()
    check('open, then drawn for another album (the page kept, its subject changed): clamped again', [classed(tree, 'app-about-text')[0].props.class, words(classed(tree, 'app-about-more')[0])],
      ['app-about-text is-clamped', 'More'])
    tree = render({ description: DRAWN, at: 'top' })
    render.commit()
    classed(tree, 'app-about-more')[0].props.onClick()
    tree = render({ description: DRAWN, at: 'top' })
    render.commit()
    classed(tree, 'app-about-more')[0].props.onClick()
    tree = render({ description: DRAWN, at: 'top' })
    render.commit()
    check('Less: clamped again', [classed(tree, 'app-about-text')[0].props.class, words(classed(tree, 'app-about-more')[0])], ['app-about-text is-clamped', 'More'])
    check('the block says where it sits', classed(tree, 'app-about')[0].props.class, 'app-about is-top')
    render.unmount()

    //? words that fit: no More; Navidrome's with no link: nothing under them at all
    delete globalThis.ResizeObserver
    const resized = []
    globalThis.window = { addEventListener: (name) => resized.push(['on', name]), removeEventListener: (name) => resized.push(['off', name]) }
    const short = hooks.root(DescriptionBlock)
    const plain = { paragraph: { text: 'Short.', source: 'lastfm', url: 'https://www.last.fm/music/X' }, subtitle: null }
    let small = short({ description: plain, at: 'foot' })
    classed(small, 'app-about-text')[0].props.ref.current = { scrollHeight: 22, clientHeight: 22 }
    short.commit()
    small = short({ description: plain, at: 'foot' })
    check('words that fit: no More - Last.fm\'s link still there; no subtitle line without one', [classed(small, 'app-about-more').length, words(classed(small, 'app-about-source')[0]), classed(small, 'app-about-subtitle').length],
      [0, 'More on Last.fm', 0])
    check('...measured on the window\'s resize with no ResizeObserver', resized, [['on', 'resize']])
    short.unmount()
    const bare = hooks.root(DescriptionBlock)
    const noLink = { paragraph: { ...plain.paragraph, url: null }, subtitle: null }
    let none = bare({ description: noLink, at: 'foot' })
    classed(none, 'app-about-text')[0].props.ref.current = { scrollHeight: 22, clientHeight: 22 }
    bare.commit()
    none = bare({ description: noLink, at: 'foot' })
    check('no link and nothing to open: nothing under the words', [classed(none, 'app-about-foot').length, classed(none, 'app-about-source').length], [0, 0])
    bare.unmount()
    const lone = hooks.root(DescriptionBlock)
    const alone = lone({ description: { paragraph: null, subtitle: '1994 studio album by Portishead' }, at: 'top' })
    lone.commit()
    check('an album\'s subtitle alone: that line, nothing else', [words(classed(alone, 'app-about-subtitle')[0]), classed(alone, 'app-about-text').length, classed(alone, 'app-about-foot').length],
      ['1994 studio album by Portishead', 0, 0])
    delete globalThis.window
  }

  console.log('\nthe pages')
  {
    const read = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
    const pages = { 'app/ArtistPage.tsx': 'artist', 'player/AlbumPage.tsx': 'album', 'app/ReleaseGroupPage.tsx': 'album' }
    for (const [file, kind] of Object.entries(pages)) {
      const src = read(file)
      check(`${file}: asks for the ${kind}'s with useDescription`, new RegExp(`useDescription\\('${kind}',`).test(src), true)
      check(`${file}: draws its block (inBlock) at its top place and at its foot`,
        [new RegExp(`const describedBlock = inBlock\\('${kind}', describing\\.description\\)`).test(src),
          ...['top', 'foot'].map((at) => src.includes(`describedBlock && describing.at === '${at}' && <DescriptionBlock description={describedBlock} at="${at}" />`))], [true, true, true])
    }
    const album = read('player/AlbumPage.tsx'), group = read('app/ReleaseGroupPage.tsx'), artist = read('app/ArtistPage.tsx')
    check('the album page: its songs wait for it, DESCRIPTION_WAIT_MS at most, and are drawn only then',
      [/if \(album && \(describing\.settled \|\| songsWaited === id\)\) songsDrawn\.current = id/.test(album), /setTimeout\(\(\) => setSongsWaited\(id\), DESCRIPTION_WAIT_MS\)/.test(album),
        /\(drawSongs \? songs : \[\]\)\.map/.test(album), /songsDrawn\.current === id, id\)/.test(album)], [true, true, true, true])
    check('...asked by THIS album\'s ids, once the bridge has answered for it - or failed (then by Navidrome\'s id alone)',
      [/useDescription\('album', storeFor === id\s*\? \{ mbid: store\?\.release_group_mbid \?\? null, navidromeId: id \}/.test(album),
        /if \(!request\.current\(\)\) return\s*setStore\(answer\)\s*setStoreFor\(id\)/.test(album),
        /if \(!request\.current\(\) \|\| isAbort\(reason\)\) return\s*setStoreFor\(id\)/.test(album)], [true, true, true])
    check('the album you don\'t have: asked by the group\'s id alone once the pressings are in or failed; its tracklist waits the same way, but not on a page come back to; its trouble counts as drawn under the top place',
      [/if \(answer && \(describing\.settled \|\| tracksWaited === id \|\| cameBack\.current === id\)\) tracksDrawn\.current = id/.test(group), /setTimeout\(\(\) => setTracksWaited\(id\), DESCRIPTION_WAIT_MS\)/.test(group),
        /\) : !drawTracks \? \(/.test(group), /useDescription\('album', answer \|\| trouble \? \{ mbid \} : null, tracksDrawn\.current === id \|\| !!trouble, id\)/.test(group),
        /const cameBack = useRef\(answer \? id : null\)/.test(group)], [true, true, true, true, true])
    check('the artist page: its albums wait for it with their other answers (not on a page come back to), asked once the facts are in, the library\'s failed notice counting as drawn under the top place; the subtitle in the hero',
      [/if \(waited \|\| \(libraryKnown && discKnown && ownedKnown && \(describing\.settled \|\| cameBack\.current\)\)\) rowsDrawn\.current = true/.test(artist),
        /libraryKnown && \(!mbid \|\| facts !== null \|\| factsFailed\) \? \{ mbid, navidromeId: libraryId \} : null,\s*rowsDrawn\.current \|\| library\.state === 'failed', id\)/.test(artist),
        /<p class="app-artist-subtitle" dir="auto">\s*\{describing\.description\.subtitle\}/.test(artist)], [true, true, true])
    check('no HTML from outside drawn as HTML, anywhere in the app', ['app/Description.tsx', 'app/useDescription.ts', 'lib/describe.ts', 'player/AlbumPage.tsx', 'app/ArtistPage.tsx', 'app/ReleaseGroupPage.tsx']
      .filter((file) => /dangerouslySetInnerHTML|innerHTML/.test(read(file))), [])
  }
}

main().then(() => {
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}, (error) => {
  console.error(error)
  process.exit(1)
})
