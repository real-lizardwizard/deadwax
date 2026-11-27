/**
 * A short description on the artist page, the album page and the album you don't have (2.0.13): ui/src/lib/describe.ts's
 * rules, app/useDescription.ts (the page's ask, through latestOnly, kept for the session, its room held) and
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
 *  - WHERE IT GOES (2.1.52): always its one place - the foot it went to when it came late is gone (placeOf,
 *    DESCRIPTION_WAIT_MS and the `at` a page was handed, with it). The page holds the block's ROOM while an answer
 *    is still to come (`holdsRoom`): from the first frame, never where an answer is kept (a kept none holds none),
 *    and not again once the page has been answered none.
 *  - The hook: nothing asked until who it is is settled; one ask per question, the newest only drawn (an older
 *    answer landing late draws nothing); `settled` once answered or failed, or with nothing to ask; a kept answer
 *    drawn on the first frame, nothing asked.
 *  - The block: the words as TEXT (a string child, never HTML), `dir="auto"`, clamped (`is-clamped`) until More;
 *    More only when they run past the clamp - a button with `aria-expanded` and `aria-controls` naming the words -
 *    and Less to close them again; measured again as the width changes (a ResizeObserver, else the window's resize);
 *    "From Wikipedia" / "More on Last.fm" opening beside the app (`target="_blank" rel="noopener"`), none without a
 *    link; nothing under the words when there is neither. And (2.1.52) its three states - the words, the room, or
 *    nothing: the room an empty block hidden from a screen reader; words landing after the first drawing marked to
 *    fade in, ones there from the first not; a height that changes eased from the one measured to the other (never
 *    on the first drawing), the room closed to nothing left closed until the block has left the page.
 *  - The pages: each asks with useDescription and draws ONE block, in its top place, handing it what it has and
 *    whether the room is held; nothing of theirs waits for it any more - the album page's songs and the pressings'
 *    tracklist are drawn as soon as they are in hand, the artist's albums with their own answers.
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
    check('how long an unsure answer is kept; what a page with nothing to ask by remembers asking', [D.UNSURE_KEPT_MS, D.NOTHING_TO_ASK], [60000, ''])
    check('the block: an artist\'s paragraph alone (their subtitle is in the hero), an album\'s both',
      [D.inBlock('artist', DRAWN), D.inBlock('album', DRAWN)], [{ paragraph: PARAGRAPH, subtitle: null }, DRAWN])
    check('...an artist\'s subtitle alone: nothing in the block; an album\'s: the block', [D.inBlock('artist', { paragraph: null, subtitle: 'x' }), D.inBlock('album', { paragraph: null, subtitle: 'x' }), D.inBlock('album', null)],
      [null, { paragraph: null, subtitle: 'x' }, null])
  }

  console.log('\nwhere it goes: always its one place, its room held while the answer is to come (2.1.52)')
  {
    check('the foot is gone: no place to judge, no wait for what is under it', [typeof D.placeOf, typeof D.DESCRIPTION_WAIT_MS], ['undefined', 'undefined'])
    check('an answer still to come, nothing to draw meanwhile: the room held', D.holdsRoom(false, null, false), true)
    check('answered - words or none: no room', [D.holdsRoom(true, null, false), D.holdsRoom(true, DRAWN, false)], [false, false])
    check('words standing while a new question is out: no room beside them', D.holdsRoom(false, DRAWN, false), false)
    check('a page already answered none: its room stays closed while the question changes', D.holdsRoom(false, null, true), false)
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
    const render = hooks.root((props) => useDescription(props.kind, props.ids, props.page))
    const props = { kind: 'artist', ids: null, page: 'p' }
    const draw = (more = {}) => { Object.assign(props, more); const got = render(props); render.commit(); return got }
    return { render, draw }
  }

  console.log('\nthe hook: asked once who it is is settled, the newest answer only')
  {
    D.forgetDescriptions()
    W.asks.length = 0
    const { render, draw } = mountHook()
    draw({ page: 'ar-1' })
    check('who it is not settled: nothing asked, not settled - and the block\'s room held from this first frame', [draw(), W.asks], [{ description: null, settled: false, holding: true }, []])
    check('settled: asked once, by its key - not settled until it answers, the room held meanwhile',
      [draw({ ids: { mbid: PORTISHEAD } }).settled, draw().settled, draw().holding, W.asks], [false, false, true, [`/describe/artist?mbid=${PORTISHEAD}`]])
    answer(`/describe/artist?mbid=${PORTISHEAD}`, WIKI)
    await settle()
    check('answered: drawn - the words are in the room, which is held no longer', draw(), { description: DRAWN, settled: true, holding: false })
    check('...and so it stays, drawn again', draw(), { description: DRAWN, settled: true, holding: false })
    check('...kept for the session', state(`/describe/artist?mbid=${PORTISHEAD}`, Date.now() + 365 * 86400000), WORDS)

    //? another question while the first is out: the first's answer, landing last, draws nothing
    draw({ kind: 'album', ids: { mbid: DUMMY }, page: 'al-1' })
    draw({ ids: { mbid: DUMMY, navidromeId: 'al-1' } })
    check('a newer question asked; the older never called off (its answer is still kept when it comes)', [W.asks.slice(-2), W.open.find((one) => one.key === `/describe/album?mbid=${DUMMY}`)?.signal],
      [[`/describe/album?mbid=${DUMMY}`, `/describe/album?mbid=${DUMMY}&navidrome_id=al-1`], undefined])
    answer(`/describe/album?mbid=${DUMMY}`, WIKI)
    await settle()
    check('...the older one\'s answer drawn nowhere, nothing settled by it (the room still held) - but kept', [draw(), state(`/describe/album?mbid=${DUMMY}`)], [{ description: null, settled: false, holding: true }, WORDS])
    check('the hook\'s ask through a latestOnly() of its own, asking current() before it draws',
      [/const requests = useMemo\(latestOnly, \[\]\)/.test(fs.readFileSync(path.join(UI, 'src/app/useDescription.ts'), 'utf8')),
        /if \(request\.current\(\)\) setAnswer\(\{ key, found \}\)/.test(fs.readFileSync(path.join(UI, 'src/app/useDescription.ts'), 'utf8'))], [true, true])
    answer(`/describe/album?mbid=${DUMMY}&navidrome_id=al-1`, { text: 'Dummy is the debut.', source: 'lastfm', url: null, subtitle: '1994 studio album by Portishead', unavailable: false })
    await settle()
    check('a page drawn for another album: its own answer, in the same one place', [draw().description.subtitle, draw().holding], ['1994 studio album by Portishead', false])
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
      [again.draw({ kind: 'album', ids: null, page: 'al-9' }), W.asks.length], [{ description: DRAWN, settled: true, holding: false }, 1])
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
    check('drawn, no room held', draw().holding, false)
    check('the ids unsettled a moment (the library asked again): still drawn, no room beside it', draw({ ids: null }), { description: DRAWN, settled: true, holding: false })
    const asked = draw({ ids: { mbid: PORTISHEAD, navidromeId: 'ar-5' } })
    check('...a new question (Navidrome\'s artist found): still drawn while it is out, not settled', [asked.description, asked.settled, asked.holding, W.asks.at(-1)],
      [DRAWN, false, false, `/describe/artist?mbid=${PORTISHEAD}&navidrome_id=ar-5`])
    answer(`/describe/artist?mbid=${PORTISHEAD}&navidrome_id=ar-5`, { text: 'Their own words.', source: 'lastfm', url: null, subtitle: 'English band', unavailable: false })
    await settle()
    check('...its answer replaces it, where it was', [draw().description.paragraph.text, draw().holding], ['Their own words.', false])
    draw({ ids: { mbid: DUMMY } })
    answer(`/describe/artist?mbid=${DUMMY}`, NONE)
    await settle()
    check('...a new answer of none takes it away', draw(), { description: null, settled: true, holding: false })
    const reasked = draw({ ids: { mbid: DUMMY, navidromeId: 'ar-5' } })
    check('...and the question changing after that holds no room a second time: closed once, it stays closed', [reasked.settled, reasked.description, reasked.holding], [false, null, false])
    check('another page: nothing of the last one\'s drawn, and its own room held afresh', draw({ ids: null, page: 'ar-6' }), { description: null, settled: false, holding: true })
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
    check('failed: settled, nothing drawn, no room held, said to the console only', [draw(), said.length], [{ description: null, settled: true, holding: false }, 1])
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
    check('kept: drawn on the first frame, no room held, nothing asked', [again.draw({ ids: { mbid: PORTISHEAD }, page: 'mb:x' }), W.asks], [{ description: DRAWN, settled: true, holding: false }, []])
    const none = again.draw({ ids: {} })
    check('nothing to ask by: settled at once, nothing drawn, no room, nothing asked', [none.settled, none.description, none.holding, W.asks], [true, null, false, []])
    again.render.unmount()
    const noIds = mountHook()
    check('...and remembered so: the page come back to, its ids still being settled, holds no room on its first frame',
      [noIds.draw({ ids: null, page: 'mb:x' }), D.pageKeyOf('artist:mb:x')], [{ description: null, settled: true, holding: false }, D.NOTHING_TO_ASK])
    noIds.render.unmount()
    D.keepDescription(`/describe/album?mbid=${DUMMY}`, null)
    D.rememberPageKey('album:al-none', `/describe/album?mbid=${DUMMY}`)
    const keptNone = mountHook()
    check('a kept "none": the page come back to holds no room - first frame, ids unsettled, and once they are in',
      [keptNone.draw({ kind: 'album', ids: null, page: 'al-none' }), keptNone.draw({ ids: { mbid: DUMMY } }), W.asks],
      [{ description: null, settled: true, holding: false }, { description: null, settled: true, holding: false }, []])
    keptNone.render.unmount()
    const firstVisit = mountHook()
    check('a first visit, nothing kept: the room from the first frame, before anything can be asked',
      firstVisit.draw({ kind: 'album', ids: null, page: 'al-first' }), { description: null, settled: false, holding: true })
    firstVisit.render.unmount()
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
    let tree = render({ kind: 'album', description: DRAWN, holding: false })
    const p = find((node) => node.type === 'p' && node.props.ref, tree)[0]
    p.props.ref.current = element
    render.commit()
    tree = render({ kind: 'album', description: DRAWN, holding: false })
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
    tree = render({ kind: 'album', description: DRAWN, holding: false })
    render.commit()
    check('More: the words whole, Less to close them', [classed(tree, 'app-about-text')[0].props.class, words(classed(tree, 'app-about-more')[0]), classed(tree, 'app-about-more')[0].props['aria-expanded']],
      ['app-about-text', 'Less', true])
    check('...the watch on the width stopped while open', observed[0].gone, true)
    const other = { paragraph: { ...PARAGRAPH, text: 'Dummy is the debut studio album by Portishead, and much more besides.' }, subtitle: null }
    tree = render({ kind: 'album', description: other, holding: false })
    render.commit()
    check('open, then drawn for another album (the page kept, its subject changed): clamped again', [classed(tree, 'app-about-text')[0].props.class, words(classed(tree, 'app-about-more')[0])],
      ['app-about-text is-clamped', 'More'])
    tree = render({ kind: 'album', description: DRAWN, holding: false })
    render.commit()
    classed(tree, 'app-about-more')[0].props.onClick()
    tree = render({ kind: 'album', description: DRAWN, holding: false })
    render.commit()
    classed(tree, 'app-about-more')[0].props.onClick()
    tree = render({ kind: 'album', description: DRAWN, holding: false })
    render.commit()
    check('Less: clamped again', [classed(tree, 'app-about-text')[0].props.class, words(classed(tree, 'app-about-more')[0])], ['app-about-text is-clamped', 'More'])
    check('the block says whose it is - and words there from the first drawing don\'t fade in', classed(tree, 'app-about')[0].props.class, 'app-about is-album')
    render.unmount()

    //? words that fit: no More; Navidrome's with no link: nothing under them at all
    delete globalThis.ResizeObserver
    const resized = []
    globalThis.window = { addEventListener: (name) => resized.push(['on', name]), removeEventListener: (name) => resized.push(['off', name]) }
    const short = hooks.root(DescriptionBlock)
    const plain = { paragraph: { text: 'Short.', source: 'lastfm', url: 'https://www.last.fm/music/X' }, subtitle: null }
    let small = short({ kind: 'artist', description: plain, holding: false })
    classed(small, 'app-about-text')[0].props.ref.current = { scrollHeight: 22, clientHeight: 22 }
    short.commit()
    small = short({ kind: 'artist', description: plain, holding: false })
    check('words that fit: no More - Last.fm\'s link still there; no subtitle line without one', [classed(small, 'app-about-more').length, words(classed(small, 'app-about-source')[0]), classed(small, 'app-about-subtitle').length],
      [0, 'More on Last.fm', 0])
    check('...measured on the window\'s resize with no ResizeObserver', resized, [['on', 'resize']])
    short.unmount()
    const bare = hooks.root(DescriptionBlock)
    const noLink = { paragraph: { ...plain.paragraph, url: null }, subtitle: null }
    let none = bare({ kind: 'artist', description: noLink, holding: false })
    classed(none, 'app-about-text')[0].props.ref.current = { scrollHeight: 22, clientHeight: 22 }
    bare.commit()
    none = bare({ kind: 'artist', description: noLink, holding: false })
    check('no link and nothing to open: nothing under the words', [classed(none, 'app-about-foot').length, classed(none, 'app-about-source').length], [0, 0])
    bare.unmount()
    const lone = hooks.root(DescriptionBlock)
    const alone = lone({ kind: 'album', description: { paragraph: null, subtitle: '1994 studio album by Portishead' }, holding: false })
    lone.commit()
    check('an album\'s subtitle alone: that line, nothing else', [words(classed(alone, 'app-about-subtitle')[0]), classed(alone, 'app-about-text').length, classed(alone, 'app-about-foot').length],
      ['1994 studio album by Portishead', 0, 0])
    delete globalThis.window
  }

  console.log('\nthe block: the room, the words landing in it, and none (2.1.52)')
  {
    const boxOf = (tree) => classed(tree, 'app-about')[0]
    const held = hooks.root(DescriptionBlock)
    let tree = held({ kind: 'album', description: null, holding: true })
    held.commit()
    check('the answer still to come: the room - an empty block, an album\'s, hidden from a screen reader',
      [boxOf(tree).props.class, boxOf(tree).props['aria-hidden'], classed(tree, 'app-about-room').length, words(tree)], ['app-about is-album is-holding', 'true', 1, ''])
    tree = held({ kind: 'album', description: DRAWN, holding: false })
    held.commit()
    check('the words land in it: drawn in the same block, marked to fade in', [boxOf(tree).props.class, words(classed(tree, 'app-about-text')[0]), 'aria-hidden' in boxOf(tree).props],
      ['app-about is-album is-arriving', WORDS, false])
    held.unmount()

    const artist = hooks.root(DescriptionBlock)
    check('an artist\'s room says so (no subtitle line in it: theirs is in the hero)', boxOf(artist({ kind: 'artist', description: null, holding: true })).props.class, 'app-about is-artist is-holding')
    artist.unmount()

    const never = hooks.root(DescriptionBlock)
    check('nothing from the first frame (a kept none): no block at all', never({ kind: 'album', description: null, holding: false }), null)
    never.commit()
    check('...and still none', never({ kind: 'album', description: null, holding: false }), null)
    never.unmount()

    const closing = hooks.root(DescriptionBlock)
    closing({ kind: 'artist', description: null, holding: true })
    closing.commit()
    tree = closing({ kind: 'artist', description: null, holding: false })
    check('none, after the room was held: the block still in the page for the close - empty, hidden', [boxOf(tree).props.class, boxOf(tree).props['aria-hidden'], classed(tree, 'app-about-room').length], ['app-about is-artist', 'true', 0])
    closing.commit()
    check('...with nothing to ease (no element measured): gone at the next drawing', closing({ kind: 'artist', description: null, holding: false }), null)
    closing.unmount()
  }

  console.log('\nthe block: a height that changes is eased, from the one measured to the other (2.1.52)')
  {
    //? an element that can be measured and marked, and the clock ease() ends by - held by hand
    const element = (height) => ({
      offsetHeight: height, style: { height: '' }, marks: {}, log: [], listeners: {},
      getBoundingClientRect() { return { height: this.offsetHeight } },
      setAttribute(name) { this.marks[name] = true; this.log.push(`+${name} ${this.style.height}`) },
      removeAttribute(name) { if (this.marks[name]) this.log.push(`-${name}`); delete this.marks[name] },
      addEventListener(name, fn) { this.listeners[name] = fn },
      removeEventListener(name) { delete this.listeners[name] },
    })
    const timers = []
    const realTimeout = globalThis.setTimeout, realClear = globalThis.clearTimeout
    globalThis.setTimeout = (fn, ms) => { const timer = { fn, ms, live: true }; timers.push(timer); return timer }
    globalThis.clearTimeout = (timer) => { if (timer) timer.live = false }
    globalThis.getComputedStyle = () => ({ transitionDuration: '0.28s' })
    const boxOf = (tree) => classed(tree, 'app-about')[0]
    const mount = (props, height) => {
      const render = hooks.root(DescriptionBlock)
      const box = element(height)
      const draw = (next, tall) => {
        const tree = render(next)
        if (tree) boxOf(tree).props.ref.current = box
        if (tall !== undefined) box.offsetHeight = tall
        render.commit()
        return tree
      }
      draw(props)
      return { render, box, draw }
    }
    const ROOM = { kind: 'album', description: null, holding: true }
    const LANDED = { kind: 'album', description: DRAWN, holding: false }
    const NOTHING = { kind: 'album', description: null, holding: false }

    const same = mount(ROOM, 131.45)
    check('the first drawing is never eased', [same.box.log, same.box.style.height], [[], ''])
    same.draw(LANDED, 131.25)
    check('the words as tall as the room, to within half a pixel: nothing eased - they only fade in', [same.box.log, same.box.style.height, timers.length], [[], '', 0])
    same.render.unmount()

    const shorter = mount(ROOM, 131.45)
    shorter.draw(LANDED, 85.75)
    check('shorter words: from the room\'s height, laid out, to their own, each to the part of a pixel - then the move marked',
      [shorter.box.log, shorter.box.style.height, timers.at(-1).ms], [['+data-easing ', '+data-moving 131.45px'], '85.75px', 360])
    shorter.box.listeners.transitionend({ target: shorter.box, propertyName: 'opacity' })
    check('...another property\'s transition ending ends nothing', shorter.box.style.height, '85.75px')
    shorter.box.listeners.transitionend({ target: shorter.box, propertyName: 'height' })
    check('...the height\'s: the marks off, the height its own again, the clock called off', [shorter.box.marks, shorter.box.style.height, timers.at(-1).live, 'transitionend' in shorter.box.listeners],
      [{}, '', false, false])
    shorter.render.unmount()

    const frozen = mount(ROOM, 131)
    frozen.draw(LANDED, 86)
    timers.at(-1).fn()
    check('a transition that never says it ended (reduced motion, a frozen pane): ended by the clock', [frozen.box.marks, frozen.box.style.height], [{}, ''])
    frozen.render.unmount()

    const none = mount(ROOM, 131)
    let tree = none.draw(NOTHING, 18)
    check('none: the room closed to nothing, and the page\'s own room around the block with it (data-gone)',
      [none.box.log, none.box.style.height, !!tree], [['+data-easing ', '+data-moving 131px', '+data-gone 131px'], '0px', true])
    tree = none.draw(NOTHING)
    check('...still in the page while it closes', !!tree, true)
    none.box.listeners.transitionend({ target: none.box, propertyName: 'height' })
    check('...closed: left closed (its marks kept) until it has left the page - or the page\'s room would be back for a frame', [none.box.marks, none.box.style.height],
      [{ 'data-easing': true, 'data-moving': true, 'data-gone': true }, '0px'])
    check('...and gone at the next drawing', none.render(NOTHING), null)
    none.render.commit()
    none.render.unmount()

    const late = mount(NOTHING, 0)
    tree = late.draw(LANDED, 131)
    check('words where there was nothing (a page that had none, asked again): opened from nothing, the page\'s room with it',
      [late.box.log, late.box.style.height, boxOf(tree).props.class], [['+data-easing ', '+data-gone ', '+data-moving 0px', '-data-gone'], '131px', 'app-about is-album is-arriving'])
    tree = late.draw(NOTHING, 18)
    check('...a change before it has finished ends it at once and starts from where the block stood', [late.box.log.slice(4), late.box.style.height],
      [['-data-easing', '-data-moving', '+data-easing ', '+data-moving 131px', '+data-gone 131px'], '0px'])
    late.render.unmount()

    const opened = mount(LANDED, 131)
    opened.draw(LANDED, 240)
    opened.draw(NOTHING, 18)
    check('how tall it was is read as it is now (More opened since): closed from there', opened.box.log.slice(0, 2), ['+data-easing ', '+data-moving 240px'])
    opened.render.unmount()

    const unseen = mount(ROOM, 0)
    unseen.draw(LANDED, 131.45)
    check('drawn out of sight (its tab\'s pane hidden: measured as nothing), the words landing as it shows: set at once, never eased from a height it never had', [unseen.box.log, unseen.box.style.height], [[], ''])
    unseen.render.unmount()

    globalThis.setTimeout = realTimeout
    globalThis.clearTimeout = realClear
    delete globalThis.getComputedStyle
  }

  console.log('\nthe pages')
  {
    const read = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
    const pages = { 'app/ArtistPage.tsx': 'artist', 'player/AlbumPage.tsx': 'album', 'app/ReleaseGroupPage.tsx': 'album' }
    for (const [file, kind] of Object.entries(pages)) {
      const src = read(file)
      check(`${file}: asks for the ${kind}'s with useDescription`, new RegExp(`useDescription\\('${kind}',`).test(src), true)
      check(`${file}: draws ONE block (inBlock), handing it what it has and whether its room is held - no foot, no place to judge`,
        [new RegExp(`const describedBlock = inBlock\\('${kind}', describing\\.description\\)`).test(src),
          src.split(`<DescriptionBlock kind="${kind}" description={describedBlock} holding={describing.holding} />`).length - 1, src.split('<DescriptionBlock').length - 1,
          /describing\.at\b|at="foot"|at="top"|DESCRIPTION_WAIT_MS|placeOf/.test(src)], [true, 1, 1, false])
    }
    const album = read('player/AlbumPage.tsx'), group = read('app/ReleaseGroupPage.tsx'), artist = read('app/ArtistPage.tsx')
    const before = (src, first, second) => src.indexOf(first) >= 0 && src.indexOf(first) < src.indexOf(second)
    check('the album page: the block under the hero and the Add / Remove line, above the songs - which wait for nothing',
      [before(album, 'app-store-line is-refused', '<DescriptionBlock'), before(album, '<DescriptionBlock', '<ol class="pl-tracks">'),
        /const drawSongs = !!album\n/.test(album), /\(drawSongs \? songs : \[\]\)\.map/.test(album), /songsWaited|songsDrawn/.test(album)], [true, true, true, true, false])
    check('...asked by THIS album\'s ids, once the bridge has answered for it - or failed (then by Navidrome\'s id alone)',
      [/useDescription\('album', storeFor === id\s*\? \{ mbid: store\?\.release_group_mbid \?\? null, navidromeId: id \} : null, id\)/.test(album),
        /if \(!request\.current\(\)\) return\s*setStore\(answer\)\s*setStoreFor\(id\)/.test(album),
        /if \(!request\.current\(\) \|\| isAbort\(reason\)\) return\s*setStoreFor\(id\)/.test(album)], [true, true, true])
    check('the album you don\'t have: asked by the group\'s id alone once the pressings are in or failed; the block under the hero, above the pressings\' trouble and the tracklist - which waits for nothing',
      [/useDescription\('album', answer \|\| trouble \? \{ mbid \} : null, id\)/.test(group), before(group, 'app-rg-maybe-note', '<DescriptionBlock'), before(group, '<DescriptionBlock', 'pl-notice app-rg-trouble'),
        /const drawTracks = !!answer\n/.test(group), /\) : !drawTracks \? \(/.test(group), /tracksWaited|tracksDrawn|cameBack/.test(group)], [true, true, true, true, true, false])
    check('the artist page: asked once the facts are in; the block under Play, above the albums - which wait for their own answers and not for it; the subtitle in the hero',
      [/libraryKnown && \(!mbid \|\| facts !== null \|\| factsFailed\) \? \{ mbid, navidromeId: libraryId \} : null, id\)/.test(artist),
        before(artist, 'class="app-artist-play"', '<DescriptionBlock'), before(artist, '<DescriptionBlock', 'class="app-artist-albums"'),
        /if \(waited \|\| \(libraryKnown && discKnown && ownedKnown\)\) rowsDrawn\.current = true/.test(artist), /describing\.settled|cameBack/.test(artist),
        /<p class="app-artist-subtitle" dir="auto">\s*\{describing\.description\.subtitle\}/.test(artist)], [true, true, true, true, false, true])
    check('the block eases by measuring: no height of its own choosing, nothing that needs a secure context',
      [/style\.height = `\$\{(from|to)\}px`/.test(read('app/Description.tsx')), /\d+px/.test(read('app/Description.tsx').replace(/\/\/\?.*|\/\*[\s\S]*?\*\//g, '').replace(/`\$\{(from|to)\}px`/g, '')),
        /matchMedia|crypto|navigator\./.test(read('app/Description.tsx'))], [true, false, false])
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
